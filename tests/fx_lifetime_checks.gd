extends SceneTree

var failures := 0
func _initialize(): _run.call_deferred()
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		print("FAIL: ", message)

func _run():
	var pool = root.get_node("PoolManager")
	var game = root.get_node("Game")
	game.hit_flash_freq = 4
	game.effect_freq = 4
	var body := Node.new()
	root.add_child(body)
	check(pool.hit_flash_allowed(body), "实体首次受击允许闪白")
	check(not pool.hit_flash_allowed(body), "同实体立即重复受击被节流")
	check(pool.fx_allowed_body(&"muzzle_flash", body), "普通特效和受击闪白分类独立")
	check(not pool.fx_allowed_body(&"muzzle_flash", body), "同分类重复特效被节流")
	check(pool.fx_allowed_body(&"hit_spark", body), "不同特效分类互不抑制")
	var stamps: Dictionary = body.get_meta(pool.FX_TIMESTAMPS_META)
	stamps.hit_flash_white = -1000000000
	check(pool.hit_flash_allowed(body), "间隔过期后允许再次闪白")
	pool.clear_pool()
	check(not pool.hit_flash_allowed(body), "存活池化节点保留同实体节流语义")
	body.free()
	var released: Array[WeakRef] = []
	for index in 1000:
		var node := Node.new()
		root.add_child(node)
		check(pool.hit_flash_allowed(node), "新实体不受已释放实体的节流影响")
		released.append(weakref(node))
		node.free()
	await process_frame
	for reference in released:
		check(reference.get_ref() == null, "时间戳不能保活已释放节点")
	check(not ("_fx_body_last_ms" in pool), "不再跨节点/游戏局累积旧全局实体缓存")
	game.hit_flash_freq = 0
	game.effect_freq = 0
	var disabled := Node.new()
	root.add_child(disabled)
	check(not pool.hit_flash_allowed(disabled) and not pool.fx_allowed_body(&"muzzle_flash", disabled), "关闭频率时保持不播放")
	check(not disabled.has_meta(pool.FX_TIMESTAMPS_META), "关闭效果时不创建节流记录")
	disabled.free()
	print("FX_LIFETIME_RESULT failures=", failures)
	quit(1 if failures else 0)
