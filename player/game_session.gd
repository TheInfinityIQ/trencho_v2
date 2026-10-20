extends Node
# Trusted composition root: owns execution/routing, not a player-visible inspector.
# The child screen receives only detached public projections and channel status.
const Simulation = preload("res://kernel/simulation.gd")
const Fixture = preload("res://player/battlefield_fixture.gd")
const Screen = preload("res://player/battlefield_screen.gd")
const Routing = preload("res://player/prompt_routing.gd")
const Scheduler = preload("res://player/frame_scheduler.gd")
signal tick_advanced(tick: int)
var simulation: RefCounted
var screen: Control
var autonomous := true
var replay_mode := false
var variant := Screen.ATTENTION_AND_INQUIRY
var _scheduler := Scheduler.new()
var _routes: Dictionary = {}

func _ready() -> void:
	if simulation == null:
		simulation = Simulation.new()
		var initialized: Dictionary = simulation.initialize(Fixture.definition(), 115, "step115")
		assert(initialized.success)
	screen = Screen.new()
	screen.set_variant(variant)
	add_child(screen)
	screen.requested.connect(_on_requested)
	refresh()

func _process(delta: float) -> void:
	if not autonomous or replay_mode or not _scheduler.due(delta): return
	advance_ticks(1)
	tick_advanced.emit(simulation.world.clock().tick_index)

func advance_ticks(ticks: int) -> void:
	var result: Dictionary = simulation.advance(ticks)
	assert(result.success)
	refresh()

func refresh() -> void:
	_routes = Routing.routes(simulation.world, simulation.player_observer.configuration())
	screen.present(simulation.player_view(), simulation.player_prompt_view(), Routing.availability(_routes), replay_mode)

func set_variant(value: String) -> bool:
	if value not in [Screen.ATTENTION_ONLY, Screen.ATTENTION_AND_INQUIRY]: return false
	variant = value
	if screen != null: screen.set_variant(value)
	return true

func _on_requested(area: String, type: String) -> void:
	if replay_mode or type not in ["DIRECT_ATTENTION", "REQUEST_ASSESSMENT"] or type == "REQUEST_ASSESSMENT" and variant == Screen.ATTENTION_ONLY: return
	_routes = Routing.routes(simulation.world, simulation.player_observer.configuration())
	var route: Dictionary = _routes.get(area, {})
	if not route.get("available", false):
		screen.acknowledge(false, type)
		return
	var result: Dictionary = simulation.execute({"type": "SubmitPlayerPrompt", "prompt_type": type, "area_id": area, "recipient_command_id": route.recipient_command_id})
	refresh()
	screen.acknowledge(result.success, type)
