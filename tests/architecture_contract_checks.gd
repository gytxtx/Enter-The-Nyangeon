extends SceneTree

var failures: int = 0
var checks: int = 0

class CaptureStore extends RefCounted:
	var snapshots: Array = []
	var fail: bool = false
	func save_data(data: SceneData) -> bool:
		snapshots.append(data.duplicate(true))
		return not fail

class SmallMap extends Node:
	var cells: Array = [Vector2i.ZERO]
	func get_used_cells(_layer: int) -> Array:
		return cells
	func map_to_local(cell: Vector2i) -> Vector2:
		return Vector2(cell)

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", label)

func _run() -> void:
	await process_frame
	var hooks = root.get_node("ExtensionHooks")
	var events = root.get_node("GameEvents")
	var game = root.get_node("Game")
	var pd = root.get_node("PlayerData")
	var mm = root.get_node("ModManager")
	var support = root.get_node("SupportData")
	for pair in [["zh_CN", "保存失败"], ["en", "Save failed"], ["pt", "Falha ao salvar"], ["vi_VN", "Lưu thất bại"]]:
		var translation := load("res://ETN_localization.%s.translation" % pair[0]) as Translation
		check(translation != null and str(translation.get_message("operation_save_failed")).begins_with(pair[1]), "保存失败文案已重新导入：%s" % pair[0])
	var yes := func(): return true
	var neutral := func(): return false
	check(hooks.should_start_first_round(), "默认允许首回合")
	hooks.add_hook("first_round_start_gate", neutral)
	check(hooks.should_start_first_round(), "中性命名回调不阻止首回合")
	hooks.first_round_start_gate = neutral
	check(not hooks.should_start_first_round(), "兼容旧客机允许查询")
	hooks.add_hook("first_round_start_gate", yes)
	check(not hooks.should_start_first_round(), "命名接管不能放行旧客机")
	hooks.remove_hook("first_round_start_gate", yes)
	hooks.remove_hook("first_round_start_gate", neutral)
	hooks.first_round_start_gate = Callable()
	hooks.first_round_start_interceptor = yes
	check(not hooks.should_start_first_round(), "新槽 true 接管")
	hooks.first_round_start_interceptor = neutral
	check(hooks.should_start_first_round(), "新槽 false 中性")
	hooks.first_round_start_interceptor = Callable()

	var base := AbilityUpgrade.new()
	base.id = "fixture_base"
	var registry := {"upgrades": {base.id: {"res": base, "scene": "res://tests/fixtures/architecture/shared_effect.tscn", "mod": "fixture"}}, "characters": {}}
	var order := {"upgrades": [base.id], "characters": []}
	check(ModPatch.apply_one(registry, {"op": "inherit", "target": "upgrades:fixture_copy", "base": "upgrades:fixture_base"}, order), "合法继承")
	check(registry.upgrades.fixture_copy.res.id == "fixture_copy" and base.id == "fixture_base", "继承 ID 一致且源不变")
	check(order.upgrades.has("fixture_copy"), "继承进入顺序表")
	check(not ModPatch.apply_one(registry, {"op": "inherit", "target": "characters:fixture_wrong", "base": "upgrades:fixture_base"}), "拒绝跨类型继承")
	check(not ModPatch.apply_one(registry, {"target": "upgrades:fixture_base", "field": "id", "value": "wrong"}), "拒绝直接改身份")
	check(not ModPatch.apply_one(registry, {"target": "upgrades:fixture_base", "field": "rare", "value": "invalid"}), "拒绝错误字段类型")
	check(registry.upgrades.fixture_base.res == base and base.rare == 0, "失败补丁原子拒绝")
	check(not ModPatch.apply_one(registry, {"target": "upgrades:fixture_base", "field": "weight", "value": 5}, {}, Callable(), func(_kind, _id, _entry): return false), "注册校验失败拒绝写回")
	check(base.weight == 1.0, "校验失败保留源资源")
	check(not ModPatch.apply_one(registry, {"target": "upgrades:fixture_base", "field": "tags", "value": [42]}), "拒绝 typed Array 元素不符")
	check(ModPatch.apply_one(registry, {"target": "upgrades:fixture_base", "field": "tags", "value": ["fixture"]}), "合法 typed Array 补丁")
	check(registry.upgrades.fixture_base.res.tags == ["fixture"] and base.tags.is_empty(), "typed Array 保持源资源隔离")

	var owner_a := Node.new()
	var owner_b := Node.new()
	root.add_child(owner_a)
	root.add_child(owner_b)
	events.set_pause_request(owner_a, true)
	events.set_pause_request(owner_b, true)
	events.set_pause_request(owner_a, false)
	check(paused and events.is_pause_locked(), "释放 A 保留 B 的世界暂停和菜单锁")
	owner_b.queue_free()
	await process_frame
	await process_frame
	check(not paused and not events.is_pause_locked(), "释放持有者自动解除")
	events.set_pause_request(owner_a, true, &"menu", true, false)
	check(paused and not events.is_pause_locked(), "普通菜单暂停不锁自己")
	events.set_pause_request(owner_a, true, &"boss")
	events.set_pause_request(owner_a, false, &"menu")
	check(paused and events.is_pause_locked(), "同节点不同标签独立")
	events.release_pause_owner(owner_a)
	check(not paused and not events.is_pause_locked(), "按持有者整体释放")
	owner_a.queue_free()

	var store := CaptureStore.new()
	var original_store = game._save_store
	game._save_store = store
	game._loading_playerdata = true
	pd.player_pyroxenes = 100
	game._loading_playerdata = false
	var card := CharacterCard.new()
	card.id = "fixture_transaction"
	card.group = "fixture_school"
	card.cost = 10
	store.fail = true
	check(not game.purchase_unlock("characters", card), "保存失败购买失败")
	check(pd.player_pyroxenes == 100 and not pd.character.has(card.id) and not pd.group.has(card.group), "失败购买内存不变")
	check(store.snapshots.size() == 1 and store.snapshots[0].player_pyroxenes == 90 and store.snapshots[0].character.has(card.id) and store.snapshots[0].group.has(card.group), "单次完整候选快照")
	store.fail = false
	check(game.purchase_unlock("characters", card), "成功购买")
	check(pd.player_pyroxenes == 90 and pd.character.has(card.id) and pd.group.has(card.group) and store.snapshots.size() == 2, "一次写入同时公布余额和所有权")
	check(not game.purchase_unlock("characters", card) and pd.player_pyroxenes == 90 and store.snapshots.size() == 2, "重复购买不扣款不写盘")
	var clothes := ClothesCard.new()
	clothes.id_name = "fixture_owner"
	clothes.id = "fixture_clothes"
	clothes.cost = 2
	store.fail = true
	check(not game.purchase_unlock("clothes", clothes) and not pd.clothes_group.has(clothes.id_name) and pd.player_pyroxenes == 90, "服装失败不改变嵌套所有权或余额")
	store.fail = false
	check(game.purchase_unlock("clothes", clothes) and pd.clothes_group[clothes.id_name] == [clothes.id] and pd.player_pyroxenes == 88 and store.snapshots.size() == 4, "服装单次提交")
	var support_card: SupportCard = support.support_pool.filter(func(c): return c.support_id != "null")[0]
	support.support_data.erase(support_card.support_id)
	support_card = support_card.duplicate(true)
	support_card.unlock_cost = 1
	check(game.purchase_unlock("supports", support_card), "支援购买单次提交")
	support.get_card(support_card)
	var old_exp: int = support.now_exp
	var old_balance: int = pd.player_pyroxenes
	store.fail = true
	check(not game.purchase_support_upgrade(1) and support.now_exp == old_exp and pd.player_pyroxenes == old_balance, "支援升级失败不改变经验或余额")
	store.fail = false
	var count: int = store.snapshots.size()
	check(game.purchase_support_upgrade(1) and support.now_exp == old_exp + support.EXP_PER_PYROXENE and pd.player_pyroxenes == old_balance - 1 and store.snapshots.size() == count + 1, "支援升级单次提交")
	game._save_store = original_store
	check(game.save_playerdata(), "实际存储写入完整购买状态")
	var reloaded: SceneData = original_store.load_data()
	check(reloaded.character.has(card.id) and reloaded.group.has(card.group) and reloaded.clothes_group[clothes.id_name] == [clothes.id] and reloaded.player_pyroxenes == pd.player_pyroxenes and int(reloaded.support_savedata[support_card.support_id].exp) == support.now_exp, "实际重读余额与全部购买结果一致")

	var player = load("res://scenes/player/momoi/momoi.tscn").instantiate()
	root.add_child(player)
	pd.player = player
	pd.reset_date()
	pd.get_player_base_ability()
	var manager = load("res://scenes/manager/upgrade_manager.tscn").instantiate()
	root.add_child(manager)
	var upgrade := AbilityUpgrade.new()
	upgrade.id = "fixture_boost"
	check(mm.register_content("upgrades", upgrade.id, upgrade, "fixture", "res://tests/fixtures/architecture/shared_effect.tscn"), "任意场景文件名合法注册")
	check(not mm.register_content("upgrades", "fixture_wrong_identity", upgrade, "fixture"), "正常注册同样拒绝身份不一致")
	var bad_scene := AbilityUpgrade.new()
	bad_scene.id = "fixture_bad_scene"
	check(not mm.register_content("upgrades", bad_scene.id, bad_scene, "fixture", "res://tests/fixtures/architecture/missing.tscn"), "正常注册同样拒绝缺失场景")
	var weights = manager.weight_manager
	var default_tags: Dictionary = weights.tag_weights.duplicate()
	check(default_tags[AbilityUpgrade.ItemType.DEFENSE] == 1.0, "用户裁定默认防御中性权重")
	weights.tag_weights = {AbilityUpgrade.ItemType.TRAJECTORY: 0.25, AbilityUpgrade.ItemType.DEFENSE: 0.0, AbilityUpgrade.ItemType.CONVERT: 0.75}
	weights.rarity_weights = {0: 1.0}
	var tagged := AbilityUpgrade.new()
	tagged.id = "fixture_tags"
	for pair in [[AbilityUpgrade.ItemType.TRAJECTORY, 0.25], [AbilityUpgrade.ItemType.DEFENSE, 0.0], [AbilityUpgrade.ItemType.CONVERT, 0.75], [AbilityUpgrade.ItemType.TRAJECTORY | AbilityUpgrade.ItemType.CONVERT, 0.5], [AbilityUpgrade.ItemType.NONE, 1.0]]:
		tagged.item_tags = pair[0]
		check(is_equal_approx(weights.calculate_item_weight(tagged), pair[1]), "仅按启用标签取平均：%d" % pair[0])
	weights.tag_weights = default_tags
	tagged.item_tags = AbilityUpgrade.ItemType.DEFENSE
	check(is_equal_approx(weights.calculate_item_weight(tagged), 1.0), "默认纯防御可抽取")
	weights.player_state = {"health_percent": 0.2}
	weights.defense_bonus = 0.3
	weights.defense_tag_quantity = 1
	manager.now_round = 2.0
	manager.refresh_mult = 0.1
	check(is_equal_approx(weights.calculate_item_weight(tagged), 1.4), "已有数量不抹去低血防御额外加成")
	weights.player_state.clear()
	weights.defense_bonus = 0.0
	weights.defense_tag_quantity = 0
	manager.refresh_mult = 0.0
	manager.apply_upgrade(upgrade)
	manager.apply_upgrade(upgrade)
	var effect = player.get_children().filter(func(n): return n.get_script() == load("res://tests/fixtures/architecture/shared_effect.gd"))[0]
	check(effect.item_id == upgrade.id and effect.applied == [1, 2], "实际升级管理器按注册 ID 叠层")
	manager.upgrade_pool.clear()
	manager.is_pool_built = false
	check(manager.get_triple_choice().is_empty(), "空配置安全返回")
	manager.upgrade_pool.append(upgrade)
	manager.weight_manager.rarity_weights = {0: 0.0}
	manager.is_pool_built = false
	check(manager.get_triple_choice().is_empty() and not manager.can_offer_upgrades(), "全零权重安全返回")
	manager.weight_manager.rarity_weights = {0: 1.0}
	for size in range(1, 5):
		if size > 1:
			var another := AbilityUpgrade.new()
			another.id = "fixture_%d" % size
			manager.upgrade_pool.append(another)
		manager.is_pool_built = false
		manager.pool_size = 1
		var choices: Array = manager.get_triple_choice()
		check(choices.size() == mini(size, 3), "候选 %d 返回唯一可用项" % size)
		check(choices.size() == choices.reduce(func(acc, item): acc[item.id] = true; return acc, {}).size(), "选项按 ID 唯一")
	var zero_weights: Array[float] = [0.0, 0.0]
	check(WeightedRandomSystem.AliasMethod.new(zero_weights).next_index() == -1, "AliasMethod 零总权重安全")
	var screen = manager.upgrade_screen_scene.instantiate()
	manager.add_child(screen)
	var empty: Array[AbilityUpgrade] = []
	screen.set_ability_upgrades(empty)
	var charged := [0]
	var on_charge := func(_cost): charged[0] += 1
	events.refresh_coin_cost.connect(on_charge)
	screen.refresh_button()
	check(charged[0] == 0 and not screen._closed, "空页刷新不扣款且可继续")
	screen.joy_select(InputEventAction.new())
	check(screen.joy_box.has(screen.next), "空页手柄可访问继续按钮")
	events.refresh_coin_cost.disconnect(on_charge)
	screen.queue_free()

	var spawn = load("res://script/enemies_spawn.gd").new()
	var map := SmallMap.new()
	spawn.tilemap = map
	spawn.player = player
	spawn.enemy.append(EnemyCard.new())
	spawn.enemy[0].id = "fixture_spawn"
	spawn.enemy_spawn_num.append(1)
	spawn.enemy_spawn_time_copy = [0.0]
	spawn.round_mult = 1.0
	player.position = Vector2.ZERO
	spawn.enemy_spawn()
	check(spawn._spawn_positions(map.cells, player).is_empty(), "无可行距离时刷怪正常返回")
	check(root.get_node("PoolManager").get_pending_count_by_id("fixture_spawn") == 0, "失败选点不占 pending 名额")
	map.cells.clear()
	spawn.enemy_spawn()
	check(spawn._spawn_positions(map.cells, player).is_empty(), "空地图安全返回")
	map.cells = [Vector2i.ZERO, Vector2i(170, 0)]
	check(spawn._spawn_positions(map.cells, player) == [Vector2(170, 0)], "筛选仅保留合格位置含边界")
	spawn.free()
	map.free()
	manager.queue_free()
	player.queue_free()
	await process_frame

	var result: Dictionary = await events.change_scene("res://tests/fixtures/architecture/missing.tscn", "")
	check(not result.ok and not events._scene_change_pending, "失败切场立即返回")
	var unrelated := Node.new()
	root.add_child(unrelated)
	check(current_scene == null, "无关树变更不算切场成功")
	unrelated.queue_free()
	var observed := [0]
	var on_first := func():
		observed[0] += 1
		check(current_scene.get_node("PlayerRoot/FixturePlayer").is_node_ready(), "首回合前玩家已就绪")
	events.first_round_add.connect(on_first)
	result = await events.change_scene("res://tests/fixtures/architecture/scene.tscn", "res://tests/fixtures/architecture/player.tscn")
	check(result.ok and observed[0] == 1, "成功切场仅初始化一次")
	var switched := []
	_request_scene(events, "res://tests/fixtures/architecture/other_scene.tscn", switched)
	_request_scene(events, "res://tests/fixtures/architecture/scene.tscn", switched)
	while switched.size() < 2:
		await process_frame
	check(current_scene.scene_file_path == "res://tests/fixtures/architecture/scene.tscn", "重叠切场最终完成最新请求")
	check(switched[0].get("cancelled", false) and switched[1].ok and observed[0] == 2, "过期请求不生成玩家或发首回合信号")
	events.first_round_add.disconnect(on_first)
	print("ARCHITECTURE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _request_scene(events: Node, path: String, results: Array) -> void:
	results.append(await events.change_scene(path, "res://tests/fixtures/architecture/player.tscn"))
