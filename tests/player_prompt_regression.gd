extends SceneTree
const Cases = preload("res://tests/player_prompt_cases.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
func _initialize() -> void:
	var result := Cases.run()
	Exporter.write_json("res://artifacts/step110_results.json", result)
	for failure in result.failures: print("FAIL: ", failure)
	print("TRENCHO STEP110: %d assertions, %d failed" % [result.checks.size(), result.failures.size()])
	quit(0 if result.success else 1)
