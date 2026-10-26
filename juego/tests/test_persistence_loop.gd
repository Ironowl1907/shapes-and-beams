extends SceneTree

func _init() -> void:
	print("\n=== STARTING FULL PERSISTENCE LOOP TEST ===")
	
	# 1. Obtain GameManager
	var gm_script: GDScript = load("res://scripts/game_manager.gd")
	var gm: Node = root.get_node_or_null("GameManager")
	if gm == null:
		gm = gm_script.new()
		root.add_child(gm)
		gm._ready()
	
	print("[Step 1] Initial GameManager state:")
	print("  Player Name: ", gm.call("get_player_name"))
	print("  Best Summary: ", gm.call("get_best_summary"))
	print("  Save Path (Resource): ", gm.get("save_path"))
	print("  Absolute Disk Path: ", gm.call("get_absolute_save_path"))
	
	# 2. Change player name
	var test_name: String = "Facundo & Bauti"
	print("\n[Step 2] Updating player name to: '", test_name, "'")
	gm.call("set_player_name", test_name)
	var updated_name: String = str(gm.call("get_player_name"))
	assert(updated_name.begins_with("Facundo"), "Player name should be updated")
	print("  Verified Player Name: ", updated_name)
	
	# 3. Simulate submitting run results
	print("\n[Step 3] Submitting run result: Difficulty 2 (Hard), 45.0s, completed = true")
	(gm.get("save_data") as Resource).set("records", {}) # Clear to test fresh run submission
	var improved: bool = bool(gm.call("report_result", 2, 45.0, true))
	assert(improved, "First completed run on empty record should be marked as improved/new record")
	print("  Improved flag: ", improved)
	print("  New Best Summary: ", gm.call("get_best_summary"))
	# Submitting a worse or equal run should return improved = false
	var repeat_run: bool = bool(gm.call("report_result", 2, 30.0, false))
	assert(not repeat_run, "A worse run should not overwrite an existing completed record")
	
	# 4. Check that save file exists on disk
	var abs_path: String = str(gm.call("get_absolute_save_path"))
	var file_exists: bool = FileAccess.file_exists(abs_path)
	print("\n[Step 4] Checking file existence on disk at: ", abs_path)
	print("  File exists on disk: ", file_exists)
	assert(file_exists, "Save file must exist on disk at user://save_data.tres")
	
	# Read the raw text of the saved .tres file
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
	assert(f != null, "Must be able to open saved file")
	var file_content: String = f.get_as_text()
	f.close()
	print("\n[Step 5] Raw content of saved Resource (.tres):")
	print("--------------------------------------------------")
	print(file_content.strip_edges())
	print("--------------------------------------------------")
	
	# 5. Reload from disk in a fresh loader to guarantee complete round-trip persistence
	print("\n[Step 6] Testing round-trip reload from disk into a fresh instance:")
	var fresh_data: Resource = ResourceLoader.load(abs_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert(fresh_data != null, "Fresh reload from disk must succeed")
	print("  Loaded fresh resource script: ", fresh_data.get_script().resource_path)
	print("  Loaded player_name: ", fresh_data.get("player_name"))
	print("  Loaded records: ", fresh_data.get("records"))
	var hard_record: Dictionary = fresh_data.call("get_record", 2) as Dictionary
	assert(bool(hard_record.get("completed", false)) == true, "Hard difficulty must be recorded as completed")
	assert(float(hard_record.get("time", 0.0)) == 45.0, "Hard difficulty record time must be 45.0s")
	
	print("\n=== FULL PERSISTENCE LOOP VERIFIED SUCCESSFULLY! ===\n")
	quit(0)
