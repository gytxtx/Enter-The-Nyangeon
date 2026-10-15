extends RefCounted

## ZIP 先完整写入隐藏暂存目录，再交换安装目录；失败不删除旧安装。
func install(zip_path: String, root: String, max_files: int, max_bytes: int) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return _failure("无法打开 zip")
	var files := reader.get_files()
	var error := _layout_error(files, max_files)
	if error != "":
		reader.close()
		return _failure(error)
	var manifest = JSON.parse_string(reader.read_file("mod.json").get_string_from_utf8())
	if not manifest is Dictionary:
		reader.close()
		return _failure("mod.json 解析失败")
	var id: String = str(manifest.get("id", ""))
	var id_pattern := RegEx.new()
	id_pattern.compile("^[a-z0-9_]+$")
	var pck: String = str(manifest.get("pck", id + ".pck"))
	if id.is_empty() or id_pattern.search(id) == null or _bad_path(pck):
		reader.close()
		return _failure("非法 mod id 或 pck 路径")
	if not files.has(pck) or pck.ends_with("/"):
		reader.close()
		return _failure("缺少 pck：" + pck)
	var suffix := "%s_%d_%d" % [id, Time.get_ticks_usec(), randi()]
	var stage := root.path_join(".import_" + suffix)
	var rollback := root.path_join(".rollback_" + suffix)
	if DirAccess.make_dir_recursive_absolute(stage) != OK:
		reader.close()
		return _failure("无法创建暂存目录")
	error = _extract(reader, files, stage, max_bytes)
	reader.close()
	if error == "":
		error = preload("res://script/mod_pack_validator.gd").validate(stage.path_join(pck))
	if error != "":
		_cleanup(stage, root)
		return _failure(error)
	var destination := root.path_join(id)
	var had_old := DirAccess.dir_exists_absolute(destination)
	if FileAccess.file_exists(destination):
		_cleanup(stage, root)
		return _failure("安装路径被文件占用")
	if had_old and _rename(destination, rollback) != OK:
		_cleanup(stage, root)
		return _failure("旧安装目录不可移动，已保留")
	if _rename(stage, destination) != OK:
		var restored := not had_old or _rename(rollback, destination) == OK
		_cleanup(stage, root)
		return _failure("替换失败，旧安装已恢复" if restored else "替换及回滚失败，旧安装保留于 " + rollback)
	if had_old:
		_cleanup(rollback, root)
	return {"ok": true, "id": id}

func _layout_error(files: PackedStringArray, max_files: int) -> String:
	if files.size() > max_files:
		return "条目过多（>%d）" % max_files
	var kinds: Dictionary = {}
	for path in files:
		if _bad_path(path):
			return "路径不安全：" + path
		var key := path.replace("\\", "/").simplify_path().trim_suffix("/")
		if OS.has_feature("windows"):
			key = key.to_lower()
		var is_dir := path.ends_with("/") or path.ends_with("\\")
		if key.is_empty() or key == ".":
			return "路径不安全：" + path
		if kinds.has(key) and (not kinds[key] or not is_dir):
			return "重复文件或文件/目录冲突：" + path
		kinds[key] = is_dir
		var parent := key.get_base_dir()
		while not parent.is_empty() and parent != ".":
			if kinds.has(parent) and not kinds[parent]:
				return "文件/目录冲突：" + path
			kinds[parent] = true
			parent = parent.get_base_dir()
	if not files.has("mod.json"):
		return "缺少 mod.json"
	return ""

func _extract(reader: ZIPReader, files: PackedStringArray, stage: String, max_bytes: int) -> String:
	var total := 0
	for path in files:
		var output := stage.path_join(path.replace("\\", "/"))
		if path.ends_with("/") or path.ends_with("\\"):
			if DirAccess.make_dir_recursive_absolute(output) != OK:
				return "创建目录失败：" + path
			continue
		if DirAccess.make_dir_recursive_absolute(output.get_base_dir()) != OK:
			return "创建父目录失败：" + path
		var data := reader.read_file(path)
		total += data.size()
		if total > max_bytes:
			return "解压体积超限"
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			return "写入失败：" + path
		file.store_buffer(data)
		file.flush()
		var error := file.get_error()
		file.close()
		if error != OK:
			return "写入失败：" + path
	return ""

func _bad_path(path: String) -> bool:
	return path.is_empty() or path.begins_with("/") or path.begins_with("\\") or path.contains("..") or path.contains(":")

func _rename(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(source, destination)

func _cleanup(path: String, root: String):
	# 清理目标只允许是本次创建的根目录直接子目录。
	if path.get_base_dir() != root.trim_suffix("/") or not (path.get_file().begins_with(".import_") or path.get_file().begins_with(".rollback_")):
		push_warning("拒绝清理范围外暂存路径：" + path)
		return
	if not _erase_tree(path):
		push_warning("暂存目录暂未清理，已保留：" + path)

func _erase_tree(path: String) -> bool:
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null and parent.is_link(path.get_file()):
		return DirAccess.remove_absolute(path) == OK
	var directory := DirAccess.open(path)
	if directory == null:
		return not DirAccess.dir_exists_absolute(path)
	directory.include_hidden = true
	for file in directory.get_files():
		if DirAccess.remove_absolute(path.path_join(file)) != OK:
			return false
	for child in directory.get_directories():
		if not _erase_tree(path.path_join(child)):
			return false
	return DirAccess.remove_absolute(path) == OK

func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
