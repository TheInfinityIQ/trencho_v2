extends Control
# Player-only view/controller. Inputs are accepted sanitized projections and
# channel availability. This script has no simulation/authority/knowledge access.
signal requested(area_id: String, prompt_type: String)
const ATTENTION_ONLY = "ATTENTION_ONLY"
const ATTENTION_AND_INQUIRY = "ATTENTION_AND_INQUIRY"
const SUPPLY_LABELS = {"SUPPLY_DEPARTURE_VISIBLE": "Supply departure", "SUPPLY_ARRIVAL_VISIBLE": "Supply arrival", "SUPPLY_LOSS_VISIBLE": "Supply loss"}
var _observer: RefCounted
var _prompts: RefCounted
var _available: Dictionary = {}
var _selected := ""
var _variant := ATTENTION_AND_INQUIRY
var _replay := false
var area_buttons: Dictionary = {}
var _area_names: Dictionary = {}
var _grid: GridContainer
var selected_title: Label
var selected_observer: Label
var history: VBoxContainer
var attention: Button
var inquiry: Button
var acknowledgement: Label
var _footer: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("171c22")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)
	page.add_child(_label("TRENCHO  |  Battlefield observer", 25))
	page.add_child(_label("Watch the front. Ask command for attention or an assessment.", 16))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)
	var map_box := VBoxContainer.new()
	map_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_box.add_theme_constant_override("separation", 10)
	columns.add_child(map_box)
	map_box.add_child(_label("OBSERVER VIEW", 18))
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	map_box.add_child(_grid)
	var clear := LinkButton.new()
	clear.text = "Clear selection"
	clear.pressed.connect(func(): select_area(""))
	map_box.add_child(clear)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 430
	side.size_flags_horizontal = Control.SIZE_FILL
	side.add_theme_constant_override("separation", 8)
	columns.add_child(side)
	selected_title = _label("Select an area", 23)
	side.add_child(selected_title)
	selected_observer = _label("Choose a battlefield area to see its observer cues.", 17)
	selected_observer.custom_minimum_size.y = 100
	side.add_child(selected_observer)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	side.add_child(actions)
	attention = _button("Look Here")
	attention.tooltip_text = "Ask command to give this area attention."
	attention.pressed.connect(func(): _request("DIRECT_ATTENTION"))
	actions.add_child(attention)
	inquiry = _button("What Happened Here?")
	inquiry.tooltip_text = "Ask command for its current assessment."
	inquiry.pressed.connect(func(): _request("REQUEST_ASSESSMENT"))
	actions.add_child(inquiry)
	acknowledgement = _label("", 15)
	acknowledgement.custom_minimum_size.y = 20
	side.add_child(acknowledgement)
	side.add_child(_label("COMMAND HISTORY", 18))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	history = VBoxContainer.new()
	history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history.add_theme_constant_override("separation", 12)
	scroll.add_child(history)
	_footer = _label("Autonomous simulation running · Select an area to compare observation and command reports.", 14)
	page.add_child(_footer)
	_refresh_selection()

func _label(value: String, font_size := 16) -> Label:
	var node := Label.new()
	node.text = value
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size", font_size)
	return node

func _button(value: String) -> Button:
	var node := Button.new()
	node.text = value
	node.custom_minimum_size.y = 42
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_font_size_override("font_size", 16)
	return node

func set_variant(value: String) -> bool:
	if value not in [ATTENTION_ONLY, ATTENTION_AND_INQUIRY]: return false
	_variant = value
	if is_node_ready(): _refresh_selection()
	return true

func present(observer: RefCounted, prompts: RefCounted, available: Dictionary, replay := false) -> void:
	_replay = replay
	_observer = observer
	_prompts = prompts
	_available = available.duplicate(true)
	var areas: Array = observer.areas()
	var ids: Array = areas.map(func(area): return area.area_id)
	if area_buttons.keys() != ids:
		for child in _grid.get_children(): child.free()
		area_buttons.clear()
		_area_names.clear()
		for area in areas:
			var button := _button("")
			button.custom_minimum_size.y = 170
			button.size_flags_vertical = Control.SIZE_EXPAND_FILL
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.toggle_mode = true
			button.add_theme_font_size_override("font_size", 18)
			button.tooltip_text = "Select this area. Selection does not send a request."
			button.pressed.connect(select_area.bind(area.area_id))
			_grid.add_child(button)
			area_buttons[area.area_id] = button
			_area_names[area.area_id] = area.display_name
	if _selected not in area_buttons: _selected = ""
	for id in area_buttons:
		var current: Dictionary = observer.current(id)
		var title: String = _area_names[id]
		var cue_text := _observer_text(current)
		var supply := _recent_supply(id)
		area_buttons[id].text = ("[Selected] " if id == _selected else "") + title + "\n\n" + cue_text + ("\n\n" + supply.back() if not supply.is_empty() else "")
		area_buttons[id].set_pressed_no_signal(id == _selected)
	_footer.text = "Recorded situation · Replay view" if replay else "Autonomous simulation running · Observation and command reports may differ."
	_refresh_selection()

func select_area(id: String) -> bool:
	if not id.is_empty() and id not in area_buttons: return false
	_selected = id
	acknowledgement.text = ""
	if _observer != null: present(_observer, _prompts, _available, _footer.text.begins_with("Recorded"))
	else: _refresh_selection()
	return true

func _observer_text(current: Dictionary) -> String:
	if not current.has("friendly_presence"): return "No front cues in this observer view."
	return "Friendly presence: " + current.friendly_presence + "\nEnemy activity: " + current.enemy_activity + "\nActivity: " + current.front_behavior.replace("_", " ")

static func report_time(seconds: float) -> String:
	var total := floori(seconds)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [total / 60, total % 60]

func _recent_supply(id: String) -> Array:
	var result: Array = []
	for event in _observer.recent_history(1000):
		if event.area_id == id and SUPPLY_LABELS.has(event.observation_type): result.append(SUPPLY_LABELS[event.observation_type] + " · " + report_time(event.observed_at))
	return result.slice(maxi(0, result.size() - 3))

func _refresh_selection() -> void:
	if attention == null: return
	var available: bool = not _replay and not _selected.is_empty() and _available.get(_selected, false)
	attention.disabled = not available
	inquiry.disabled = not available
	inquiry.visible = _variant == ATTENTION_AND_INQUIRY
	for child in history.get_children(): child.free()
	if _selected.is_empty():
		selected_title.text = "Select an area"
		selected_observer.text = "Choose a battlefield area to see its observer cues."
		history.add_child(_label("No area selected."))
		return
	selected_title.text = _area_names[_selected]
	selected_observer.text = "Current observer view\n" + _observer_text(_observer.current(_selected))
	var supply := _recent_supply(_selected)
	if not supply.is_empty(): selected_observer.text += "\n" + "\n".join(supply)
	if _replay: acknowledgement.text = "Recorded history · requests disabled"
	elif not available: acknowledgement.text = "Command channel unavailable"
	var records: Array = _prompts.current().filter(func(prompt): return prompt.area_id == _selected)
	if records.is_empty(): history.add_child(_label("No requests for this area yet."))
	for prompt in records.slice(maxi(0, records.size() - 8)):
		var text := "You requested attention." if prompt.prompt_type == "DIRECT_ATTENTION" else "You asked: What happened here?"
		text += "\nRequest submitted."
		if prompt.state in ["SUBMITTED", "PENDING_EVALUATION"]: text += "\nCommand reply pending."
		else: text += "\n" + _initial_response(prompt)
		if prompt.prompt_type == "REQUEST_ASSESSMENT" and prompt.has("latest_follow_up"):
			var answer: Dictionary = prompt.latest_follow_up
			text += "\nCommand: Assessment available.\nBased on a report observed at " + report_time(answer.assessment_observed_at) + "\nFriendly presence: " + answer.friendly_presence + "\nEnemy activity: " + answer.enemy_activity + "\nActivity: " + answer.front_behavior.replace("_", " ") + "\nAmmo condition: " + answer.ammo_condition.replace("_", " ")
		history.add_child(_label(text, 16))

func _initial_response(prompt: Dictionary) -> String:
	match prompt.get("assessment_code"):
		"ACTIVE_AMMO_SUPPLY_PROBLEM": return "Command reports an active ammunition supply problem."
		"KNOWN_AMMO_NEED_RESOLVED": return "Command reports the previously known ammunition need as resolved."
		"ACTIVE_AMMO_SUPPLY_CONCERN": return "Command acknowledges a known ammunition concern."
		"LAST_KNOWN_AMMO_NEED_RESOLVED": return "Command reports no active known concern."
		"NO_SUPPORTED_AREA_INFORMATION": return "Command does not currently have enough information to assess this area." if prompt.prompt_type == "REQUEST_ASSESSMENT" else "Command needs more information about this area."
	return "Command acknowledgement received."

func _request(type: String) -> void:
	if _replay or _selected.is_empty() or not _available.get(_selected, false) or type == "REQUEST_ASSESSMENT" and _variant == ATTENTION_ONLY: return
	requested.emit(_selected, type)

func acknowledge(success: bool, type: String) -> void:
	acknowledgement.text = ("Attention request sent" if type == "DIRECT_ATTENTION" else "Assessment requested") if success else "Command channel unavailable"
