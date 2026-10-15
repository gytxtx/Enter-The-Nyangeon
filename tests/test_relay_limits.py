"""回环 TCP 验证中继的握手、帧长度及未入房连接预算。"""
import asyncio
import importlib.util
import json
from pathlib import Path
import struct
import sys
import unittest

spec = importlib.util.spec_from_file_location("etn_relay_limits", Path(__file__).resolve().parents[1] / "mod_sdk/coop_mod/server/relay_server.py")
relay = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = relay
spec.loader.exec_module(relay)


class ControlledWriter:
    """只控制传输水位；协议路由和帧编码使用真实服务端。"""
    def __init__(self, buffered=0):
        self.transport = self
        self.buffered = buffered
        self.closed = False
        self.frames = []

    def get_write_buffer_size(self): return self.buffered
    def is_closing(self): return self.closed
    def write(self, data): self.frames.append(data)
    def close(self): self.closed = True


class RelayBackpressure(unittest.IsolatedAsyncioTestCase):
    async def test_soft_overflow_delivers_frame_then_hard_closes(self):
        # 软水位：宽限内仍写入可靠帧，不静默丢帧、不立即断开。
        soft = ControlledWriter(relay.WRITE_SOFT_WATER)
        peer = relay.Peer(reader=None, writer=soft, id=2)
        await relay.send_control(peer, {"type": "peer_disconnected", "peer_id": 3})
        self.assertFalse(soft.closed, "软水位宽限内不应立即断开")
        self.assertTrue(soft.frames, "软水位下可靠帧必须写入，不能静默丢弃")
        # 硬水位：立即断开且不写入（明确失败，而非跳帧后继续）。
        hard = ControlledWriter(relay.WRITE_HARD_WATER)
        peer2 = relay.Peer(reader=None, writer=hard, id=3)
        await relay.send_data(peer2, 1, b"next")
        self.assertTrue(hard.closed, "硬水位必须断开慢端")
        self.assertEqual(hard.frames, [])

    async def test_sustained_soft_overflow_closes_after_grace(self):
        saved = relay.WRITE_GRACE_SEC
        relay.WRITE_GRACE_SEC = 0.0
        try:
            writer = ControlledWriter(relay.WRITE_SOFT_WATER)
            peer = relay.Peer(reader=None, writer=writer, id=2)
            await relay.send_data(peer, 1, b"first")
            self.assertFalse(writer.closed, "首次超过软水位只记时刻、继续写")
            await relay.send_data(peer, 1, b"second")
            self.assertTrue(writer.closed, "超过宽限仍超软水位必须断开")
        finally:
            relay.WRITE_GRACE_SEC = saved

    async def test_slow_receiver_does_not_block_healthy_broadcast(self):
        host = relay.Peer(reader=None, writer=ControlledWriter(), id=1)
        slow = relay.Peer(reader=None, writer=ControlledWriter(relay.WRITE_HARD_WATER), id=2)
        healthy = relay.Peer(reader=None, writer=ControlledWriter(), id=3)
        room = relay.Room(code="TEST", host=host, clients={slow, healthy})
        for peer in (host, slow, healthy): peer.room = room
        packet = struct.pack("<i", 0) + b"reliable-event"
        await asyncio.wait_for(relay.route_packet(host, packet), 1.0)
        self.assertTrue(slow.writer.closed)
        self.assertEqual(healthy.writer.frames, [relay.encode_frame(2, struct.pack("<i", 1) + b"reliable-event")])


class RelayConcurrentAdmission(unittest.IsolatedAsyncioTestCase):
    async def asyncTearDown(self):
        relay.rooms.clear()

    async def test_pending_join_gets_fresh_roster_before_admission(self):
        host, first, second = [relay.Peer(reader=None, writer=ControlledWriter()) for _ in range(3)]
        await relay.handle_control(host, b'{"type":"create_room"}')
        join = json.dumps({"type": "join_room", "room_code": host.room.code}).encode()
        await relay.handle_control(first, join)
        await relay.handle_control(second, join)
        await relay.handle_control(first, b'{"type":"client_ready"}')
        await relay.handle_control(second, b'{"type":"client_ready"}')
        controls = []
        for frame in second.writer.frames:
            offset = 2 if frame[1] < 126 else 4
            controls.append(json.loads(frame[offset:]))
        known = set()
        for event in controls:
            known.update(p["peer_id"] for p in event.get("peers", []))
            if event["type"] in ("peer_pending", "peer_connected"):
                known.add(event["peer_id"])
            if event["type"] == "join_admitted":
                self.assertIn(first.id, known, "准入前必须知道同时加入的另一客机，未知 sender 数据会被永久拒收")
        await relay.route_packet(first, struct.pack("<i", second.id) + b"first-event")
        self.assertEqual(second.writer.frames[-1], relay.encode_frame(2, struct.pack("<i", first.id) + b"first-event"))


class RelayLimits(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.server = await asyncio.start_server(relay.handle_connection, "127.0.0.1", 0)
        self.port = self.server.sockets[0].getsockname()[1]
        self.writers = []
        self.saved = {}
        for name, value in (("HTTP_HANDSHAKE_TIMEOUT_SEC", 0.1), ("JOIN_TIMEOUT_SEC", 0.2), ("FRAME_TIMEOUT_SEC", 0.1), ("MAX_TOTAL_CLIENTS", 512)):
            self.saved[name] = getattr(relay, name, None)
            setattr(relay, name, value)

    async def asyncTearDown(self):
        for writer in self.writers:
            writer.close()
            try:
                await writer.wait_closed()
            except ConnectionError:
                pass  # 超限立即关闭时，Windows 可用 reset 表示拒绝。
        self.server.close()
        await self.server.wait_closed()
        await self.wait_for_slots(0)
        for name, value in self.saved.items():
            if value is None:
                delattr(relay, name)
            else:
                setattr(relay, name, value)
        relay.rooms.clear()

    async def connect(self, upgrade=True):
        reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
        self.writers.append(writer)
        if upgrade:
            writer.write(b"GET / HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n")
            await writer.drain()
            self.assertIn(b"101 Switching Protocols", await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 2))
        return reader, writer

    async def test_oversized_frame_rejected_before_body(self):
        reader, writer = await self.connect()
        writer.write(b"\x82\xff" + struct.pack(">Q", 128 * 1024 * 1024) + b"\0\0\0\0")
        await writer.drain()
        self.assertEqual(await asyncio.wait_for(reader.read(), 1.5), b"")

    async def test_incomplete_http_handshake_expires(self):
        reader, writer = await self.connect(upgrade=False)
        writer.write(b"GET / HTTP/1.1\r\n")
        await writer.drain()
        self.assertEqual(await asyncio.wait_for(reader.read(), 1.5), b"")

    async def test_unjoined_socket_expires(self):
        reader, _ = await self.connect()
        self.assertEqual(await asyncio.wait_for(reader.read(), 1.5), b"")

    async def test_partial_frame_has_assembly_deadline(self):
        reader, writer = await self.connect()
        writer.write(b"\x82\xfe" + struct.pack(">H", 1000) + b"\0\0\0\0x")
        await writer.drain()
        self.assertEqual(await asyncio.wait_for(reader.read(), 1.5), b"")

    async def test_valid_control_frame_still_creates_room(self):
        reader, writer = await self.connect()
        payload = b'{"type":"create_room","player_name":"check"}'
        writer.write(bytes([0x81, 0x80 | len(payload)]) + b"\0\0\0\0" + payload)
        await writer.drain()
        response = await asyncio.wait_for(reader.read(4096), 1.5)
        self.assertIn(b'"type":"room_created"', response)

    async def wait_for_slots(self, count):
        async def wait():
            while len(relay.active_connections) != count:
                await asyncio.sleep(0.001)
        await asyncio.wait_for(wait(), 1.5)

    async def test_incomplete_handshakes_are_counted_before_upgrade(self):
        relay.MAX_TOTAL_CLIENTS = 1
        relay.HTTP_HANDSHAKE_TIMEOUT_SEC = 2
        first, writer = await self.connect(upgrade=False)
        writer.write(b"GET / HTTP/1.1\r\n")
        await writer.drain()
        await self.wait_for_slots(1)
        for _ in range(5):
            rejected, _ = await self.connect(upgrade=False)
            self.assertIn(b"503 Server full", await asyncio.wait_for(rejected.read(), 1))
            self.assertEqual(len(relay.active_connections), 1)
        self.assertEqual(len(relay.connected_peers), 0)
        writer.close()
        await asyncio.wait_for(first.read(), 1)
        await self.wait_for_slots(0)
        await self.connect()  # 名额释放后正常升级仍可用。

    async def test_websocket_and_http_share_the_same_budget(self):
        relay.MAX_TOTAL_CLIENTS = 1
        _, first = await self.connect()
        rejected, writer = await self.connect(upgrade=False)
        writer.write(b"GET / HTTP/1.1\r\n\r\n")
        await writer.drain()
        try:
            response = await asyncio.wait_for(rejected.read(), 1)
            self.assertIn(b"503 Server full", response)
        except ConnectionError:
            pass  # 请求与服务端立即拒绝交错，TCP reset 也表示未准入。
        self.assertEqual(len(relay.active_connections), 1)
        first.close()
        await self.wait_for_slots(0)

    async def test_slots_released_after_all_http_exit_paths(self):
        relay.MAX_TOTAL_CLIENTS = 1
        for request, expected in (
            (b"GET / HTTP/1.1\r\n\r\n", b"200 OK"),
            (b"GET / HTTP/1.1\r\nUpgrade: websocket\r\n\r\n", b"400 Missing WebSocket key"),
            (b"GET / HTTP/1.1\r\n", b""),
        ):
            reader, writer = await self.connect(upgrade=False)
            writer.write(request)
            await writer.drain()
            response = await asyncio.wait_for(reader.read(), 1.5)
            self.assertIn(expected, response)
            await self.wait_for_slots(0)
        await self.connect()


if __name__ == "__main__":
    unittest.main()
