class_name ModPatch

# 补丁引擎：作用于 ModManager 的内容注册表（内存）。
# registry: kind -> id -> { "res": Resource, "scene": String, "card_scene": PackedScene, "mod": String }
# op：replace / add / remove / inherit；target 形如 "characters:aris"。
# 缺 target / 字段：warning + 跳过，不报错（对齐 RimWorld 补丁行为）。

static func apply_all(registry: Dictionary, patches: Array, order: Dictionary = {}, validate: Callable = Callable(), validate_entry: Callable = Callable()) -> int:
	var applied := 0
	for op in patches:
		if op is Dictionary and apply_one(registry, op, order, validate, validate_entry):
			applied += 1
	return applied


static func apply_one(registry: Dictionary, op: Dictionary, order: Dictionary = {}, validate: Callable = Callable(), validate_entry: Callable = Callable()) -> bool:
	var target := str(op.get("target", ""))
	var kind := str(op.get("kind", ""))
	var id := target
	if target.contains(":"):
		var parts := target.split(":", false, 1)
		kind = parts[0]
		id = parts[1]
	var verb := str(op.get("op", "replace"))
	if verb == "inherit":
		return _op_inherit(registry, kind, id, op, order, validate, validate_entry)
	if not registry.has(kind) or not registry[kind].has(id):
		push_warning("[ModPatch] target 不存在，跳过：%s" % target)
		return false
	match verb:
		"remove":
			registry[kind].erase(id)
			return true
		"replace", "add":
			# add 与 replace 都要求字段存在：Resource 不支持新增属性，对不存在的字段
			# set() 只会刷引擎错误，这里提前告警并跳过。
			var candidate: Dictionary = registry[kind][id].duplicate()
			candidate.res = candidate.res.duplicate(true)
			var field := str(op.get("field", ""))
			if field == identity_field(kind) or not _op_set(candidate, field, op.get("value"), true):
				return false
			if validate_entry.is_valid() and not bool(validate_entry.call(kind, id, candidate)):
				return false
			registry[kind][id] = candidate
			return true
		_:
			push_warning("[ModPatch] 未知 op：%s" % verb)
			return false


static func _op_set(entry: Dictionary, field: String, value, require_existing: bool) -> bool:
	if field == "":
		push_warning("[ModPatch] 缺少 field")
		return false
	var res: Resource = entry.get("res")
	if res == null:
		return false
	if require_existing and not _has_prop(res, field):
		push_warning("[ModPatch] 字段不存在，已跳过：%s" % field)
		return false
	var coerced = _coerce(res, field, value)
	var property_type := TYPE_NIL
	var property_class := ""
	for p in res.get_property_list():
		if p.name == field and (int(p.usage) & PROPERTY_USAGE_STORAGE) != 0:
			property_type = p.type
			property_class = str(p.class_name)
	if field == "script" or property_type == TYPE_NIL:
		return false
	if property_type in [TYPE_FLOAT, TYPE_INT] and typeof(coerced) in [TYPE_FLOAT, TYPE_INT]:
		coerced = float(coerced) if property_type == TYPE_FLOAT else int(coerced)
	if typeof(coerced) != property_type and not (property_type == TYPE_OBJECT and coerced == null):
		push_warning("[ModPatch] 字段类型不符，已跳过：%s" % field)
		return false
	if property_type == TYPE_OBJECT and coerced != null and property_class != "" and not coerced.is_class(property_class):
		return false
	var current = res.get(field)
	if current is Array and current.is_typed():
		var elements: Array = current.duplicate()
		elements.clear()
		for element in coerced:
			if typeof(element) != current.get_typed_builtin():
				return false
			if element is Object and element != null:
				if current.get_typed_class_name() != "" and not element.is_class(current.get_typed_class_name()):
					return false
				if current.get_typed_script() != null and not is_instance_of(element, current.get_typed_script()):
					return false
			elements.append(element)
		coerced = elements
	res.set(field, coerced)
	if field == "scene_path":
		entry["scene"] = str(coerced)
	if field == "card_scene":
		entry["_card_scene_changed"] = true
	entry["_patched"] = true
	return true


static func _op_inherit(registry: Dictionary, target_kind: String, target_id: String, op: Dictionary, order: Dictionary, validate: Callable, validate_entry: Callable) -> bool:
	var base := str(op.get("base", ""))
	var base_kind := ""
	var base_id := base
	if base.contains(":"):
		var parts := base.split(":", false, 1)
		base_kind = parts[0]
		base_id = parts[1]
	if base_kind == "":
		base_kind = str(op.get("kind", ""))
	if base_kind == "":
		base_kind = target_kind
	if target_id == "":
		push_warning("[ModPatch] inherit 缺少 target")
		return false
	if target_kind == "":
		target_kind = base_kind
	if target_kind != base_kind:
		push_warning("[ModPatch] inherit 不允许跨 kind：%s → %s" % [base_kind, target_kind])
		return false
	if not registry.has(base_kind) or not registry[base_kind].has(base_id):
		push_warning("[ModPatch] inherit base 不存在：%s" % base)
		return false
	if not registry.has(target_kind):
		push_warning("[ModPatch] inherit 未知 kind：%s" % target_kind)
		return false
	# 与正常注册一致：走前缀/冲突校验（overrides 命中则放行覆盖）
	if validate.is_valid():
		var err: String = str(validate.call(target_kind, target_id))
		if err != "":
			push_warning("[ModPatch] inherit 被拒：(%s:%s) %s" % [target_kind, target_id, err])
			return false
	var base_entry: Dictionary = registry[base_kind][base_id]
	var res: Resource = base_entry.get("res")
	if res == null:
		return false
	res = res.duplicate(true)
	var candidate: Dictionary = base_entry.duplicate()
	candidate.res = res
	var identity := identity_field(target_kind)
	if not _has_prop(res, identity):
		return false
	res.set(identity, target_id)
	var overrides = op.get("overrides", {})
	if not overrides is Dictionary:
		return false
	for k in overrides:
		if str(k) == identity or not _op_set(candidate, str(k), overrides[k], true):
			return false
	if validate_entry.is_valid() and not bool(validate_entry.call(target_kind, target_id, candidate)):
		return false
	var existed: bool = registry[target_kind].has(target_id)
	candidate["_patched"] = true
	registry[target_kind][target_id] = candidate
	# 新条目写回 target 的 kind 顺序表，保证 get_content()（遍历 _order）能看到
	if not existed and order.has(target_kind):
		order[target_kind].append(target_id)
	return true

static func identity_field(kind: String) -> String:
	return {"supports": "support_id", "game_modes": "game_mode_id", "levels": "level_id"}.get(kind, "id")


static func _has_prop(res: Resource, field: String) -> bool:
	for p in res.get_property_list():
		if p.name == field:
			return true
	return false


static func _coerce(res: Resource, field: String, value):
	if value is String:
		var cur = res.get(field)
		if cur is Color:
			var color := Color.from_string(value, Color(-1, -1, -1, -1))
			return value if color == Color(-1, -1, -1, -1) else color
		if cur is Vector2:
			var parts = value.split(",")
			if parts.size() == 2 and parts[0].is_valid_float() and parts[1].is_valid_float():
				return Vector2(float(parts[0]), float(parts[1]))
		if cur is Vector2i:
			var parts_i = value.split(",")
			if parts_i.size() == 2 and parts_i[0].is_valid_int() and parts_i[1].is_valid_int():
				return Vector2i(int(parts_i[0]), int(parts_i[1]))
		if cur is bool:
			var lv: String = str(value).strip_edges().to_lower()
			if lv in ["true", "1", "yes", "on"]:
				return true
			if lv in ["false", "0", "no", "off"]:
				return false
			push_warning("[ModPatch] 无法把 '%s' 转为 bool（%s）" % [value, field])
			return value
		if cur is int:
			if value.is_valid_int():
				return value.to_int()
			if value.is_valid_float():
				return int(value.to_float())
			push_warning("[ModPatch] 无法把 '%s' 转为 int（%s）" % [value, field])
			return value
		if cur is float:
			if value.is_valid_float():
				return value.to_float()
			push_warning("[ModPatch] 无法把 '%s' 转为 float（%s）" % [value, field])
			return value
		# 字符串目标字段（含未声明字段）原样返回
		return value
	return value
