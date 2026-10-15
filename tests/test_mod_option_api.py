"""实际 Mod 管理页在旧 autoload 签名及新运行期实现下的解析和启停契约。"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from godot_check_output import unexpected_errors
from isolated_godot import REPO, environment

GODOT = os.environ.get("GODOT_BIN", str(REPO.parent / ".tools/godot/Godot_v4.7-stable_win64_console.exe"))
MANAGER = '''extends Node
signal mods_changed
var state_warning := ""
var calls := 0
var next_result := {"ok": true}
func list_mods() -> Array: return []
func set_order(_ids: Array) -> void: pass
func import_zip(_path: String) -> Dictionary: return {"ok": true}
func uninstall(_id: String) -> Dictionary: return {"ok": true}
'''
MODERN = MANAGER + '''func set_enabled(_id: String, _on: bool) -> Dictionary:
    calls += 1
    return next_result
'''
LEGACY = MANAGER + '''func set_enabled(_id: String, _on: bool) -> void:
    calls += 1
'''
CHECK = '''extends SceneTree
func _initialize(): _run.call_deferred()
func _run():
    var mode := OS.get_environment("ETN_MOD_OPTION_CASE")
    var manager := root.get_node("ModManager")
    if mode == "stale_signature":
        manager.set_script(load("res://manager_actual.gd"))
    if mode == "failure":
        manager.set("next_result", {"ok": false, "error": "fixture_failed"})
    var script = load("res://script/mod_option.gd")
    if script == null or not script.can_instantiate():
        print("FAIL: actual mod_option.gd did not compile")
        quit(1)
        return
    var panel = script.new()
    var label := Label.new()
    panel.status_label = label
    panel._on_toggle("fixture", false)
    var ok: bool
    if mode == "legacy":
        ok = not panel._pending_restart and int(manager.get("calls")) == 0 and label.text == "mod_state_save_failed"
    elif mode == "failure":
        ok = not panel._pending_restart and int(manager.get("calls")) == 1 and label.text == "fixture_failed"
    else:
        ok = panel._pending_restart and int(manager.get("calls")) == 1 and label.text == "mod_restart_notice"
    panel.free()
    label.free()
    print("MOD_OPTION_API mode=%s ok=%s" % [mode, ok])
    quit(0 if ok else 1)
'''


class ModOptionApi(unittest.TestCase):
    def run_case(self, mode):
        with tempfile.TemporaryDirectory(prefix="etn-mod-option-api-") as directory:
            root = Path(directory)
            for folder in ("script", "ui", "fonts"):
                (root / folder).mkdir()
            shutil.copy2(REPO / "script/mod_option.gd", root / "script/mod_option.gd")
            shutil.copy2(REPO / "script/option_menu.gd", root / "script/option_menu.gd")
            shutil.copy2(REPO / "fonts/BoutiqueBitmap9x9_1.9.ttf", root / "fonts/BoutiqueBitmap9x9_1.9.ttf")
            (root / "ui/option_toggle.tscn").write_text('[gd_scene format=3]\n[node name="Toggle" type="Control"]\n', encoding="utf-8")
            (root / "project.godot").write_text('config_version=5\n[application]\nconfig/name="ModOptionApiCheck"\n[autoload]\nModManager="*res://manager.gd"\n', encoding="utf-8")
            (root / "manager.gd").write_text(LEGACY if mode in ("legacy", "stale_signature") else MODERN, encoding="utf-8")
            (root / "manager_actual.gd").write_text(MODERN, encoding="utf-8")
            (root / "check.gd").write_text(CHECK, encoding="utf-8")
            env = environment(root / "user")
            env["ETN_MOD_OPTION_CASE"] = mode
            command = [GODOT, "--headless", "--path", str(root)]
            imported = subprocess.run(command + ["--editor", "--quit"], env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=25)
            self.assertEqual(imported.returncode, 0, imported.stdout + imported.stderr)
            result = subprocess.run(command + ["--script", "res://check.gd"], env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=15)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertFalse(unexpected_errors(output), output)
            self.assertIn(f"MOD_OPTION_API mode={mode} ok=true", output)

    def test_legacy_void_signature_compiles_without_mutating_state(self):
        self.run_case("legacy")

    def test_stale_signature_uses_current_runtime_manager(self):
        self.run_case("stale_signature")

    def test_modern_success(self):
        self.run_case("success")

    def test_modern_failure(self):
        self.run_case("failure")


if __name__ == "__main__":
    unittest.main()
