"""隔离验证 Mod 启停坏档/写入失败/UI 反馈与实体特效记录生命周期。"""
import argparse
import os
from pathlib import Path
import sys
import subprocess
import tempfile
from isolated_godot import REPO, prepare, run
from godot_check_output import unexpected_errors


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", str(REPO.parent / ".tools/godot/Godot_v4.7-stable_win64_console.exe")))
    args = parser.parse_args()
    logs = REPO / ".godot/mod_state_fx_checks"
    logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="etn-mod-state-fx-") as directory:
        for name, marker in (("mod_state", "MOD_STATE_RESULT"), ("fx_lifetime", "FX_LIFETIME_RESULT")):
            env = prepare(args.godot, Path(directory) / name, [])
            try:
                code, output = run([args.godot, "--headless", "--path", str(REPO), "--quit-after", "120", "--script", f"res://tests/{name}_checks.gd"], env, logs / f"{name}.log", 30)
            except subprocess.TimeoutExpired as error:
                output = "".join(part.decode("utf-8", errors="replace") if isinstance(part, bytes) else (part or "") for part in (error.stdout, error.stderr))
                (logs / f"{name}.log").write_text(output, encoding="utf-8")
                print(output, flush=True)
                raise SystemExit(f"{name} 超时，已保存日志")
            print(output, flush=True)
            if code or unexpected_errors(output) or marker not in output or "failures=0" not in output or "FAIL:" in output:
                raise SystemExit(1)


if __name__ == "__main__":
    main()
