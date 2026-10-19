extends SceneTree

const Demo = preload("res://debug/demo.gd")
const FrontDemo = preload("res://debug/front_demo.gd")
const DecisionDemo = preload("res://debug/decision_demo.gd")
const Exporter = preload("res://kernel/run_exporter.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "demo"
	var directory: String = args[1] if args.size() > 1 else "res://artifacts/run_demo"
	var result: Dictionary
	if mode == "replay":
		result = Exporter.replay_package(directory)
	elif mode in ["demo", "front-demo", "decision-demo"]:
		result = DecisionDemo.run() if mode == "decision-demo" else (FrontDemo.run() if mode == "front-demo" else Demo.run())
		if result.success:
			var sim: RefCounted = result.details.simulation
			print("LEDGER ", JSON.stringify(sim.audit()))
			result = Exporter.export_run(sim, directory)
			if result.success:
				result = Exporter.replay_package(directory)
	else:
		result = {"success": false, "error_code": "INVALID_MODE"}
	print("TRENCHO ", mode.to_upper(), ": ", JSON.stringify(result))
	quit(0 if result.success else 1)
