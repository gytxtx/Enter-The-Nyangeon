"""隔离 user://，验证架构修复契约；可指定已准备好的工程副本。"""
import argparse
import os
from pathlib import Path
import tempfile
import sys
from isolated_godot import REPO, prepare, run
from godot_check_output import unexpected_errors


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", str(REPO.parent / ".tools/godot/Godot_v4.7-stable_win64_console.exe")))
    parser.add_argument("--project", type=Path, default=REPO)
    args = parser.parse_args()
    log = args.project / ".godot/architecture_contract.log"
    log.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="etn-architecture-contract-") as directory:
        env = prepare(args.godot, Path(directory), [])
        code, output = run([args.godot, "--headless", "--path", str(args.project), "--script", "res://tests/architecture_contract_checks.gd"], env, log, 40)
    print(output)
    if code or unexpected_errors(output) or "ARCHITECTURE_RESULT" not in output or "failures=0" not in output:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
