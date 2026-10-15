extends SceneTree

class FailReplace extends "res://script/mod_state_store.gd":
	var fail_primary := true
	func _replace(source: String, destination: String) -> Error:
		if fail_primary and destination == path:
			return ERR_CANT_CREATE
		return super._replace(source, destination)

var failures := 0
var checks := 0
func _initialize(): _run.call_deferred()
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

func write(path: String, text: String):
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func record(id: String, enabled: bool) -> Dictionary:
	return {"id": id, "dir": "user://mods/" + id, "manifest": {"id": id}, "enabled": enabled, "mounted": false, "error": ""}

func _run():
	check(tr("mod_state_load_failed") != "mod_state_load_failed" and tr("mod_state_save_failed") != "mod_state_save_failed", "错误提示已导入本地化资源")
	var path := "user://mod_state_checks.json"
	var store = preload("res://script/mod_state_store.gd").new(path)
	check(store.load_data().default_enabled, "首次无记录允许按原策略启用新 Mod")
	check(store.save_data({"alpha": true, "beta": false}), "保存初始启停记录")
	check(store.save_data({"alpha": false, "beta": false}), "保存最新停用意图")
	var backup := FileAccess.get_file_as_bytes(path + ".bak")
	check(store._read(path + ".bak").alpha, "备份可以早于最近一次停用")
	for bad in ["{", "[]", '{"alpha":1}', '{"alpha":null}']:
		write(path, bad)
		var loaded: Dictionary = store.load_data()
		check(not loaded.default_enabled and loaded.data.is_empty(), "坏记录不能通过旧备份重新启用任何 Mod")
		check(loaded.warning == "mod_state_load_failed", "坏记录有面向 UI 的提示")
		check(FileAccess.get_file_as_string(path) == bad and FileAccess.get_file_as_bytes(path + ".bak") == backup, "读取保留坏档和备份证据")
	check(store.save_data({"alpha": false}), "用户明确重新选择后可重建记录")
	check(FileAccess.get_file_as_bytes(path + ".bak") == backup, "坏主档不覆盖旧有效备份")
	check(not store.load_data().data.alpha, "重建后仍保留停用")
	DirAccess.remove_absolute(path)
	check(not store.load_data().default_enabled, "缺主档但有备份不能伪装首次启动")
	check(store.save_data({"alpha": true}), "缺主档后可显式重建")
	var old := FileAccess.get_file_as_bytes(path)
	var failing := FailReplace.new(path)
	check(not failing.save_data({"alpha": false}), "主档替换失败明确返回失败")
	check(FileAccess.get_file_as_bytes(path) == old, "替换失败保持有效主档")
	# 用独立路径验证临时文件不可写，不依赖平台权限位。
	var blocked_path := "user://mod_state_blocked.json"
	DirAccess.make_dir_recursive_absolute(blocked_path + ".new")
	check(not preload("res://script/mod_state_store.gd").new(blocked_path).save_data({"alpha": false}), "临时路径被目录占用时返回失败")
	var manager = root.get_node("ModManager")
	manager._state_store = failing
	manager._mods = {"alpha": record("alpha", true)}
	var panel = load("res://ui/mod_option.tscn").instantiate()
	root.add_child(panel)
	panel._on_toggle("alpha", false)
	check(manager._mods.alpha.enabled, "保存失败恢复内存启用状态")
	check(panel.status_label.text == tr("mod_state_save_failed") and not panel._pending_restart, "失败提示传到 UI，不谎报重启生效")
	check(not manager.uninstall("alpha").ok and manager._mods.has("alpha"), "保存失败不开始卸载或丢失注册项")
	write(path, "{")
	manager._mods.clear()
	var loaded: Dictionary = manager._read_state()
	DirAccess.make_dir_recursive_absolute("user://mods/alpha")
	write("user://mods/alpha/mod.json", '{"id":"alpha"}')
	manager._try_load_mod("user://mods/alpha", "alpha", loaded)
	manager._mount_enabled()
	check(not manager._mods.alpha.enabled and not manager._mods.alpha.mounted, "坏状态的实际扫描与挂载均保持停用")
	panel._refresh()
	check(panel.status_label.text == tr("mod_state_load_failed"), "坏记录在管理面板显示提示")
	failing.fail_primary = false
	panel._on_toggle("alpha", true)
	check(manager._mods.alpha.enabled and manager.state_warning.is_empty(), "显式选择成功后清除坏档提示")
	check(panel._pending_restart and panel.status_label.text == tr("mod_restart_notice"), "成功后才提示重启生效")
	# autoload 注册完成后再编译替身，避免入口脚本预编译时反向加载整个 ModManager。
	var deletion_script := GDScript.new()
	deletion_script.source_code = 'extends "res://script/mod_manager.gd"\nfunc _delete_mod_dirs(_id: String) -> bool:\n\treturn false\n'
	check(deletion_script.reload() == OK, "运行期编译删除失败替身")
	var deletion = deletion_script.new()
	deletion._state_store = store
	deletion._mods = {"alpha": record("alpha", true), "beta": record("beta", false)}
	check(deletion.uninstall("alpha").ok, "删除被占用时保留待卸载状态")
	check(not store.load_data().data.alpha, "未删目录的 ID 持久化为停用墓碑")
	check(deletion.set_enabled("beta", true).ok and not store.load_data().data.alpha, "切换其他 Mod 仍保留待卸载墓碑")
	deletion.free()
	panel.queue_free()
	await process_frame
	print("MOD_STATE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
