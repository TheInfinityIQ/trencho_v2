extends Control

const Demo = preload("res://debug/demo.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
var sim: RefCounted
var text: TextEdit
var status: Label

func _ready() -> void:
	print("INSPECTOR: building developer view")
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := Label.new()
	title.text = "TRENCHO 2A | Simulation kernel · developer inspector"
	box.add_child(title)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	for pair in [["Run demonstration", _run], ["Export + verify replay", _export]]:
		var button := Button.new()
		button.text = pair[0]
		button.pressed.connect(pair[1])
		actions.add_child(button)
	status = Label.new()
	box.add_child(status)
	text = TextEdit.new()
	text.editable = false
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	status.text = "Ready · select Run demonstration to execute the 17-tick fixture"
	text.text = "The simulation is stopped.\n\nRun demonstration executes the fixture once.\nExport + verify replay is available after a successful run."
	print("INSPECTOR: ready; simulation stopped; render cap %d FPS" % Engine.max_fps)

func _run() -> void:
	var started := Time.get_ticks_usec()
	print("INSPECTOR: starting demonstration")
	var result := Demo.run()
	if not result.success:
		status.text = "Demonstration failed: " + JSON.stringify(result)
		return
	sim = result.details.simulation
	status.text = "Demonstration passed · tick %d · %.1f seconds · %d events" % [sim.world.clock().tick_index, sim.time(), sim.events.count()]
	var state: Dictionary = sim.snapshot()
	var recent: Array = sim.events.all().slice(maxi(0, sim.events.count() - 12))
	text.text = "AMMUNITION: 1000 created | 1000 in stock | 0 cargo | 0 consumed | 0 destroyed\nSource 400 · HQ 100 · Depot A 300 · Depot B 200\n\n" + JSON.stringify({"clock": state.clock, "resource_ledger": sim.audit(), "locations": state.locations, "stockpiles": state.stockpiles, "shipments": state.shipments, "command_hierarchy": state.commands, "communication_edges": state.communication_edges, "messages": state.messages, "belief_records": state.information_records, "recent_events": recent}, "  ")
	print("INSPECTOR: demonstration and text prepared in %.2f ms; %d events" % [(Time.get_ticks_usec() - started) / 1000.0, sim.events.count()])

func _export() -> void:
	if sim == null:
		status.text = "Run the demonstration before exporting."
		return
	var directory := "res://artifacts/run_demo"
	var result := Exporter.export_run(sim, directory)
	if result.success:
		result = Exporter.replay_package(directory)
	status.text = "Export + replay passed · final state and all %d events match · artifacts/run_demo" % result.details.event_count if result.success else "Export/replay failed: " + result.error_code
