extends RefCounted

## 只读预检独立、未加密的 PCK，不挂载候选包或改变当前资源视图。
## 格式依据 Godot 4.7 core/io/file_access_pack.cpp 与 pck_packer.cpp。
## MD5 只检测内容损坏，不是对 Mod 作者的身份认证。
static func validate(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "无法读取 PCK"
	var error := _check(file)
	file.close()
	return error

static func _check(file: FileAccess) -> String:
	var length := file.get_length()
	if length < 96 or file.get_32() != 0x43504447:
		return "PCK 文件头无效或已截断"
	var version := file.get_32()
	if version not in [2, 3, 4]:
		return "不支持的 PCK 格式版本"
	var major := file.get_32()
	var minor := file.get_32()
	file.get_32() # patch 不参与引擎兼容判断，与原生加载器一致。
	var engine := Engine.get_version_info()
	if major > int(engine.major) or (major == int(engine.major) and minor > int(engine.minor)):
		return "PCK 要求更新的 Godot 引擎"
	var flags := file.get_32()
	if flags & ~2:
		return "Mod 安装仅支持未加密的完整 PCK"
	var base := file.get_64()
	var header_size := 96 if version == 2 else 104
	if length < header_size or base < header_size or base > length:
		return "PCK 数据起点越界"
	var directory := 96 if version == 2 else file.get_64()
	if directory < header_size or directory > length - 4:
		return "PCK 目录起点越界"
	file.seek(directory)
	var count := file.get_32()
	if count > (length - file.get_position()) / 40:
		return "PCK 目录条目数无效"
	var entries: Array[Dictionary] = []
	var paths := {}
	for index in count:
		if length - file.get_position() < 40:
			return "PCK 目录已截断"
		var path_size := file.get_32()
		if path_size == 0 or path_size > length - file.get_position() - 36:
			return "PCK 目录路径长度无效"
		var bytes := file.get_buffer(path_size)
		while not bytes.is_empty() and bytes[-1] == 0:
			bytes.resize(bytes.size() - 1)
		if bytes.is_empty() or bytes.has(0):
			return "PCK 目录路径无效"
		var path := bytes.get_string_from_utf8()
		if path.to_utf8_buffer() != bytes:
			return "PCK 目录路径不是有效 UTF-8"
		path = path.trim_prefix("res://").replace("\\", "/")
		if path.is_absolute_path() or path.contains(":") or path.split("/").has("..") or path.ends_with("/"):
			return "PCK 目录路径不安全"
		path = path.simplify_path()
		if path.is_empty() or path == "." or paths.has(path):
			return "PCK 目录路径为空或重复"
		paths[path] = true
		var offset := file.get_64()
		var size := file.get_64()
		var md5 := file.get_buffer(16)
		var entry_flags := file.get_32()
		if entry_flags & ~2:
			return "Mod 安装不支持加密文件或增量补丁"
		if entry_flags & 2: # Godot 的文件移除条目没有内容。
			if size != 0:
				return "PCK 文件移除条目无效"
			continue
		if offset < 0 or offset > length - base or size < 0 or size > length - base - offset:
			return "PCK 文件内容越界或已截断"
		entries.append({"offset": base + offset, "size": size, "md5": md5})
	var directory_end := file.get_position()
	var hashes := {}
	var hashed_bytes := 0
	for entry in entries:
		var start: int = entry.offset
		var size: int = entry.size
		if start < header_size or (size > 0 and start < directory_end and start + size > directory):
			return "PCK 文件内容与文件头或目录重叠"
		var key := "%d:%d" % [start, size]
		if not hashes.has(key):
			# 重复区间只校验一次；交错范围不能把小包放大成无限量哈希工作。
			if size > length - hashed_bytes:
				return "PCK 重叠内容超出校验预算"
			hashed_bytes += size
			var hash := HashingContext.new()
			hash.start(HashingContext.HASH_MD5)
			file.seek(start)
			var remaining := size
			while remaining > 0:
				var chunk := file.get_buffer(mini(remaining, 65536))
				if chunk.is_empty():
					return "PCK 文件内容读取失败"
				hash.update(chunk)
				remaining -= chunk.size()
			hashes[key] = hash.finish()
		if hashes[key] != entry.md5:
			return "PCK 文件校验和不匹配"
	return ""
