extends RefCounted

## 启停记录事务。坏主档不自动信任旧备份的 enabled=true：备份可能早于最近一次停用。
## 保留备份供人工恢复；坏档启动时全停用，用户显式选择后可重建完整状态。
var path: String

func _init(state_path: String = "user://mods/mods_state.json"):
	path = state_path

func load_data() -> Dictionary:
	var data = _read(path)
	if data != null:
		return {"data": data, "default_enabled": true, "warning": ""}
	var existing := FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path) \
		or FileAccess.file_exists(path + ".bak") or DirAccess.dir_exists_absolute(path + ".bak")
	return {"data": {}, "default_enabled": not existing,
		"warning": "mod_state_load_failed" if existing else ""}

func save_data(data: Dictionary) -> bool:
	if not _valid(data):
		return false
	var temporary := path + ".new"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or _read(temporary) != data:
		return false
	# 只备份已验证主档；坏主档不能覆盖既有有效备份。
	if _read(path) != null:
		error = DirAccess.copy_absolute(path, path + ".bak.new")
		if error == OK:
			error = _replace(path + ".bak.new", path + ".bak")
		if error != OK:
			return false
	return _replace(temporary, path) == OK

func _replace(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(source, destination)

func _read(source: String):
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary or not _valid(json.data):
		return null
	return json.data

func _valid(data: Dictionary) -> bool:
	for id in data:
		if not id is String or not data[id] is bool:
			return false
	return true
