extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(1)
		return
	var validator = load(args[0])
	if validator == null:
		quit(1)
		return
	var error: String = validator.validate(args[1])
	if error != "":
		printerr("PCK validation failed: ", error)
		quit(1)
		return
	print("PACK_VERIFIED")
	quit()
