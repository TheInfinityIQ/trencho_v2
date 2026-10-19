extends SceneTree

const Cases = preload("res://tests/front_cases.gd")
const Exporter = preload("res://kernel/run_exporter.gd")

func _initialize() -> void:
	var result: Dictionary = Cases.run()
	Exporter.write_json("res://artifacts/step103_results.json", result)
	for failure in result.failures:
		print("FAIL: ", failure)
	print("TRENCHO STEP 103: %d assertions, %d failed" % [result.checks.size(), result.failures.size()])
	quit(0 if result.success else 1)
