"""构建入口必须拒绝失败/错误诊断/缺完成标记/无效 PCK，保留已有发行物。"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT_BIN", str(REPO.parent / ".tools/godot/Godot_v4.7-stable_win64_console.exe"))


class BuildContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="etn-build-contract-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sdk = self.root / "mod_sdk"
        self.sdk.mkdir()
        for name in ("build_common.ps1", "build_mod.ps1", "build_local_mod.ps1", "build_coop_mod.ps1", "pack_mod.gd", "verify_mod_pack.gd"):
            shutil.copy2(REPO / "mod_sdk" / name, self.sdk / name)
        (self.root / "script").mkdir()
        shutil.copy2(REPO / "script/mod_pack_validator.gd", self.root / "script/mod_pack_validator.gd")
        (self.root / "project.godot").write_text('config_version=5\n[application]\nconfig/name="BuildContract"\n', encoding="utf-8")
        self.source = self.root / "mods/fixture"
        self.source.mkdir(parents=True)
        (self.source / "mod.json").write_text(json.dumps({"id": "fixture", "version": "0.0.0"}), encoding="utf-8")

    def invoke(self, entry, godot):
        args = ["pwsh", "-NoProfile", "-File", str(self.sdk / entry), "-Godot", str(godot), "-Project", str(self.root), "-ModId", "fixture"]
        if entry == "build_coop_mod.ps1":
            args += ["-Source", str(self.source)]
        result = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30)
        return result

    def test_failure_contract_all_entries(self):
        for entry, output in (("build_mod.ps1", self.root / "build"), ("build_local_mod.ps1", self.root / "mods/_build"), ("build_coop_mod.ps1", self.sdk / "coop_mod/build")):
            output.mkdir(parents=True, exist_ok=True)
            old_pck = output / "fixture.pck"
            old_zip = output / "fixture.zip"
            old_pck.write_bytes(b"previous-package")
            old_zip.write_bytes(b"previous-release")
            for mode in ("exit", "diagnostic", "marker", "invalid_pack"):
                with self.subTest(entry=entry, mode=mode):
                    fake = self.root / "fake_godot.ps1"
                    # 最后一次结构校验应由真实 Godot 负责，否则伪完成标记不能检测垃圾包。
                    verify = f"& '{str(GODOT).replace(chr(39), chr(39)*2)}' @args; exit $LASTEXITCODE"
                    body = '$out = @($args | Where-Object { $_ -like "--out=*" })\nif ($out.Count) { $path = $out[0].Substring(6) } else { $path = $args[-1] }\n[IO.File]::WriteAllBytes($path, [byte[]](71,68,80,67))\n'
                    body += {"exit": 'exit 42\n', "diagnostic": 'Write-Output "ERROR: simulated pack failure"\nexit 0\n', "marker": 'exit 0\n', "invalid_pack": f'if ($args -contains "{self.sdk / "verify_mod_pack.gd"}") {{ {verify} }}\nWrite-Output "PACK_MOD: done"\nexit 0\n'}[mode]
                    if mode == "invalid_pack":
                        # 校验进程不先写候选文件。
                        body = body[body.index('if ($args -contains'):].split('\nWrite-Output')[0] + '\n' + body[:body.index('if ($args -contains')] + 'Write-Output "PACK_MOD: done"\nexit 0\n'
                    fake.write_text(body, encoding="utf-8-sig")
                    result = self.invoke(entry, fake)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(old_pck.read_bytes(), b"previous-package")
                    self.assertEqual(old_zip.read_bytes(), b"previous-release")

    def test_real_packer_and_structure_validation(self):
        (self.root / "export_presets.cfg").write_text('[preset.0]\nname="ModPack"\nplatform="Windows Desktop"\nrunnable=false\nexport_filter="all_resources"\ninclude_filter="mods/fixture/*"\nexclude_filter=""\n[preset.0.options]\nbinary_format/architecture="x86_64"\n', encoding="utf-8")
        for entry in ("build_local_mod.ps1", "build_coop_mod.ps1", "build_mod.ps1"):
            with self.subTest(entry=entry):
                result = self.invoke(entry, GODOT)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                if entry != "build_mod.ps1":
                    self.assertIn("PACK_MOD:", result.stdout)
                self.assertIn("PACK_VERIFIED", result.stdout)


if __name__ == "__main__":
    unittest.main()
