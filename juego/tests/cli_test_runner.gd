extends SceneTree

func _init() -> void:
	var suite_script: GDScript = load("res://tests/test_gameplay.gd")
	if suite_script == null:
		print("ERROR: Failed to load test_gameplay.gd")
		quit(1)
		return
	var suite: Object = suite_script.new()
	var runner_class: GDScript = load("res://addons/godot_ai/testing/test_runner.gd")
	var runner: Object = runner_class.new()
	var res: Dictionary = runner.run_suites([suite], "", "", {}, true)
	print("--- TEST RESULTS ---")
	print("Total: ", res.get("total", 0), " | Passed: ", res.get("passed", 0), " | Failed: ", res.get("failed", 0))
	var failed_count: int = int(res.get("failed", 0))
	if failed_count > 0:
		var failures: Array = res.get("failures", [])
		for f in failures:
			print("FAIL: ", f)
		quit(1)
	else:
		print("SUCCESS: ALL TESTS PASSED!")
		quit(0)
