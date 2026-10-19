extends SceneTree

const Cases = preload("res://tests/closeout_cases.gd")
const Exporter = preload("res://kernel/run_exporter.gd")

func _initialize() -> void:
	var result: Dictionary = Cases.run()
	Exporter.write_json("res://artifacts/closeout_regression_results.json", result)
	for failure in result.failures:
		print("FAIL: ", failure)
	print("TRENCHO 2A CLOSEOUT: %d checks, %d failed" % [result.checks.size(), result.failures.size()])
	quit(0 if result.success else 1)
