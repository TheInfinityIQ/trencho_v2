extends RefCounted
const Demo = preload("res://debug/player_observation_demo.gd")
const Simulation = preload("res://kernel/simulation.gd")
const Observer = preload("res://kernel/player_observer.gd")
const Areas = preload("res://kernel/strategic_area_definition.gd")
const PlayerView = preload("res://kernel/player_observer_view.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
const Needs = preload("res://tests/resource_resolution_cases.gd")

static func check(checks: Array, valid: bool, name: String) -> void:
	checks.append({"name": "109 / " + name, "passed": valid})

static func observations(sim: RefCounted, type := "") -> Array:
	return sim.player_observer.events().filter(func(e): return type.is_empty() or e.observation_type == type)

static func record_case(checks: Array, summaries: Dictionary, sim: RefCounted, name: String) -> void:
	var directory := "res://artifacts/run_step109_" + name
	check(checks, Exporter.export_run(sim, directory).success, name + " exports dualstream package")
	var reconstructed := Exporter.reconstruct_player(sim.initial_world, sim.player_observer.configuration().values(), sim.events.all())
	check(checks, reconstructed.success and Exporter.equivalent(reconstructed.details.world, sim.snapshot()) and Exporter.equivalent(reconstructed.details.events, sim.player_observer.events()) and Exporter.equivalent(reconstructed.details.projection.state, sim.player_observer.snapshot()) and Exporter.equivalent(reconstructed.details.projection.view, sim.player_view().snapshot()), name + " independent event-only observer reconstruction leavesworld intact")
	check(checks, Needs.conserved_prefixes(sim), name + " authoritative prefixes conserve physicalstock/cargo/claims")
	var public_view: Dictionary = sim.player_view().snapshot()
	check(checks, safe_view(public_view), name + " strict public allowlist no exactdata/provenance/metadata")
	var source_ids: Array = sim.events.all().map(func(e): return e.event_id)
	var valid := true
	var previous: Variant = null
	var counter := 1
	for event in sim.player_observer.events():
		if event.source_authoritative_event_id not in source_ids or event.previous_observation_event_id != previous or event.player_observation_event_id != "player-observation-event:%010d" % counter or event.player_observation_id != "player-observation:%010d" % counter: valid = false
		previous = event.player_observation_event_id
		counter += 1
	check(checks, valid, name + " separate deterministic IDs/crossstream sources/internal previous chain")
	summaries[name] = {"authoritative_events": sim.events.count(), "player_events": sim.player_observer.events().size(), "end_tick": sim.world.clock().tick_index, "area_ids": sim.player_observer.configuration().keys(), "view": public_view, "observation_types": sim.player_observer.events().map(func(e): return e.observation_type), "ledger": sim.audit()}

static func safe_view(data: Dictionary) -> bool:
	if data.keys().any(func(k): return k not in ["areas", "current", "history"]): return false
	for area in data.areas:
		if area.keys().any(func(k): return k not in ["area_id", "display_name"]): return false
	for current in data.current.values():
		if current.keys().any(func(k): return k not in ["area_id", "display_name", "front_behavior", "friendly_presence", "enemy_activity", "last_supply_movement"]): return false
		if current.has("last_supply_movement") and not safe_record(current.last_supply_movement): return false
	for record in data.history:
		if not safe_record(record): return false
	return true

static func safe_record(record: Dictionary) -> bool:
	return record.keys().size() == 4 and record.keys().all(func(k): return k in ["area_id", "observed_at", "observation_type", "qualitative_value"]) and record.qualitative_value in ["LOW", "MEDIUM", "HIGH", "HOLDING", "PRESSING", "REDUCED_ACTIVITY", "WITHDRAWING", "SUPPLY_MOVEMENT"]

static func run() -> Dictionary:
	var checks: Array = []
	var summaries: Dictionary = {}
	var a: RefCounted = Demo.fresh("A")
	check(checks, a.player_view().current("AREA_FRONT_A").friendly_presence == "HIGH" and a.player_view().current("AREA_FRONT_A").enemy_activity == "MEDIUM" and a.player_view().current("AREA_FRONT_A").front_behavior == "PRESSING", "A qualitativeHIGH/MEDIUM/PRESSING")
	check(checks, observations(a).size() == 3 and observations(a).all(func(e): return e.source_authoritative_event_id == "event:0000000001" and e.observed_at == 0), "A deterministic initial snapshot sourced RUN_STARTED")
	check(checks, a.player_view().current("AREA_HQ").size() == 2 and a.player_view().areas().size() == 2, "HQ nonfrontarea exists without invented frontcues")
	check(checks, not JSON.stringify(a.player_view().snapshot()).contains("777") and not JSON.stringify(a.player_view()._data).contains("metadata"), "area exactmetadata not even retained in detachedview backingdata")
	var copied: Dictionary = a.player_view().snapshot()
	copied.current.AREA_FRONT_A.front_behavior = "CHEAT"
	check(checks, a.player_view().current("AREA_FRONT_A").front_behavior == "PRESSING", "viewqueries detached from observer")
	check(checks, not a.player_view().has_method("information") and not a.player_view().has_method("current_belief") and not a.player_view().has_method("identity") and not a.command_view("LOCAL_A").has_method("areas"), "observer cannot satisfy commandknowledge/planner interface")
	record_case(checks, summaries, a, "A")
	var b: RefCounted = Demo.fresh("B")
	Demo.input(b, "SetFrontEnemyPressure", 34)
	var changed: Dictionary = Needs.events(b, "FRONT_ENEMY_PRESSURE_CHANGED").back()
	check(checks, b.player_view().current("AREA_FRONT_A").enemy_activity == "MEDIUM" and observations(b, "ENEMY_ACTIVITY").back().source_authoritative_event_id == changed.event_id, "B32to34 crossesLOWMEDIUM immediateexactsource")
	var count := observations(b).size()
	Demo.input(b, "SetFrontEnemyPressure", 35)
	check(checks, observations(b).size() == count and Needs.events(b, "FRONT_ENEMY_PRESSURE_CHANGED").size() == 2, "B34to35worldmutation no duplicatequalitativeevent")
	record_case(checks, summaries, b, "B")
	var c: RefCounted = Demo.fresh("C")
	var planned: Dictionary = c.execute({"type": "CreateShipment", "origin_stockpile_id": "HQ_STOCK", "destination_stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": 7}, true)
	check(checks, observations(c, "SUPPLY_DEPARTURE_VISIBLE").is_empty(), "reservation/planning alone no invented visual departure")
	c.execute({"type": "DispatchShipment", "shipment_id": planned.entity_id}, true)
	c.advance(5)
	check(checks, observations(c, "SUPPLY_ARRIVAL_VISIBLE").size() == 1 and observations(c, "SUPPLY_ARRIVAL_VISIBLE")[0].observed_at == 0.5 and c.world.get_shipment(planned.entity_id).state == "ARRIVED", "Cphysicalarrival immediatevisible at0.5")
	check(checks, c.command_view("LOCAL_B").information().is_empty() and c.command_view("LOCAL_B").local_stockpile("A_STOCK").is_empty() and c.command_view("LOCAL_A").information().is_empty(), "Cplayerseesarrival without remotecommander details or premature local beliefs")
	c.execute({"type": "SendMessage", "actor_entity_id": "LOCAL_A", "sender_command_id": "LOCAL_A", "recipient_command_id": "LOCAL_B", "message_type": "REPORT", "payload": {"facts": [{"subject_entity_id": "DEPOT_A", "fact_key": "DELIVERED_SUPPLY_QUANTITY", "value": 7, "observed_at": 0.5, "confidence": 1.0}]}}, false)
	c.advance(19)
	check(checks, c.command_view("LOCAL_B").information().is_empty(), "visualarrival doesnotbypass two-second reportlatency")
	c.advance()
	check(checks, c.command_view("LOCAL_B").current_belief("DEPOT_A", "DELIVERED_SUPPLY_QUANTITY", c.time()).value == 7, "remotecommander learns exactquantity onlyfrom deliveredreport")
	var loss := Demo.shipment(c, 3)
	c.advance(2)
	c.execute({"type": "DestroyShipment", "shipment_id": loss.entity_id, "reason_code": "TEST_PHYSICAL_LOSS"}, true)
	check(checks, observations(c, "SUPPLY_LOSS_VISIBLE").size() == 1 and observations(c, "SUPPLY_DEPARTURE_VISIBLE").size() == 2, "actual destroyed/departed physicalevents producegenericcues")
	record_case(checks, summaries, c, "C")
	var d: RefCounted = Demo.fresh("D")
	var disabled: RefCounted = Demo.fresh("D", false)
	d.advance(250)
	disabled.advance(250)
	check(checks, JSON.stringify(d.events.all(), "", true, true) == JSON.stringify(disabled.events.all(), "", true, true) and JSON.stringify(d.snapshot(), "", true, true) == JSON.stringify(disabled.snapshot(), "", true, true), "Dauthoritativeevents IDsandentirestate byte-identicalenabled/disabled")
	check(checks, d.events.count() == 3607 and not observations(d).is_empty() and observations(disabled).is_empty(), "Dunchangedfull2B3607events onlyobserverstream differs")
	for table in ["decisions", "decision_candidates", "resource_needs", "peer_coordinations", "superior_need_reports", "resource_arbitrations", "shipments", "information_records", "ledger"]:
		check(checks, Exporter.equivalent(d.snapshot()[table], disabled.snapshot()[table]), "DexactAIinertness " + table)
	record_case(checks, summaries, d, "D")
	Exporter.export_run(disabled, "res://artifacts/run_step109_D_disabled")
	check(checks, FileAccess.get_file_as_bytes("res://artifacts/run_step109_D/events.jsonl") == FileAccess.get_file_as_bytes("res://artifacts/run_step109_D_disabled/events.jsonl"), "Dactualexported authoritative events.jsonl byte-identical without normalization")
	var e: RefCounted = Demo.fresh("E")
	e.advance(10)
	var belief: Dictionary = e.command_view("LOCAL_A").current_belief("FRONT_A", "FRONT_ENEMY_PRESSURE", e.time())
	var held_view: RefCounted = e.player_view()
	e.advance()
	Demo.input(e, "SetFrontEnemyPressure", 34)
	check(checks, e.player_view().current("AREA_FRONT_A").enemy_activity == "MEDIUM" and held_view.current("AREA_FRONT_A").enemy_activity == "LOW", "Eimmediatevisiblecrossing betweencommandobservations and oldviewdetached")
	check(checks, e.command_view("LOCAL_A").current_belief("FRONT_A", "FRONT_ENEMY_PRESSURE", e.time()).id == belief.id and belief.value == 3200, "Ecommanderpriorbelief unchanged afterplayersees change")
	e.advance(8)
	check(checks, e.command_view("LOCAL_A").current_belief("FRONT_A", "FRONT_ENEMY_PRESSURE", e.time()).id == belief.id, "Epriorbelief remains untilnormalone-secondboundary")
	e.advance()
	var updated: Dictionary = e.command_view("LOCAL_A").current_belief("FRONT_A", "FRONT_ENEMY_PRESSURE", e.time())
	check(checks, updated.value == 3400 and updated.id != belief.id and updated.observed_at == 2.0 and observations(e, "ENEMY_ACTIVITY").back().observed_at == 1.1, "Eplayer1.1commander2.0 via legitimateobservation notplayerfeedback")
	record_case(checks, summaries, e, "E")
	_validation_and_boundaries(checks)
	_package_integrity(a, checks)
	var failures: Array = []
	for item in checks:
		if not item.passed: failures.append(item.name)
	return {"success": failures.is_empty(), "checks": checks, "failures": failures, "scenarios": summaries}

static func _validation_and_boundaries(checks: Array) -> void:
	for pair in [[0, "LOW"], [3333, "LOW"], [3334, "MEDIUM"], [6666, "MEDIUM"], [6667, "HIGH"], [10000, "HIGH"]]: check(checks, Observer.band(pair[0]) == pair[1], "canonicalcentiband boundary " + str(pair))
	for bad in [{"id": ""}, {"location_ids": []}, {"location_ids": ["MISSING"]}, {"location_ids": ["DEPOT_A", "DEPOT_A"]}, {"front_id": "MISSING"}, {"enabled": "yes"}, {"metadata": [80]}, {"display_name": 80}]:
		var data := Demo.definition()
		data.strategic_areas[0].merge(bad, true)
		check(checks, not Simulation.new().initialize(data).success, "invalidarea rejected " + JSON.stringify(bad))
	var data := Demo.definition()
	data.strategic_areas.append(data.strategic_areas[0].duplicate(true))
	check(checks, not Simulation.new().initialize(data).success, "duplicatearea IDsrejected")
	data = Demo.definition()
	data.strategic_areas.append({"id": "OVERLAP", "location_ids": ["DEPOT_A"]})
	check(checks, not Simulation.new().initialize(data).success, "enabledlocationmembership unique")
	data.strategic_areas.back().enabled = false
	var disabled_area := Simulation.new()
	check(checks, disabled_area.initialize(data).success and disabled_area.player_view().areas().size() == 2 and not disabled_area.player_view().current("OVERLAP").size(), "disabledoverlap allowed but absentfromobservation")
	var plain: RefCounted = Demo.fresh("A", false)
	check(checks, plain.player_view().areas().is_empty() and plain.player_observer.events().is_empty(), "noareas noobserverevents/projectedfronts")
	var sim: RefCounted = Demo.fresh("A")
	for pair in [["HOLD", "HOLDING"], ["REDUCE_ACTIVITY", "REDUCED_ACTIVITY"], ["WITHDRAW", "WITHDRAWING"], ["PRESS", "PRESSING"]]:
		Demo.input(sim, "SetFrontPosture", pair[0])
		check(checks, sim.player_view().current("AREA_FRONT_A").front_behavior == pair[1], "behaviorcue " + pair[0])
	var before := observations(sim).size()
	Demo.input(sim, "SetFrontPosture", "PRESS")
	check(checks, observations(sim).size() == before, "sameposture no redundantcue")
	Demo.input(sim, "SetFrontFriendlyStrength", 33.33)
	check(checks, sim.player_view().current("AREA_FRONT_A").friendly_presence == "LOW", "friendlystrength bandupdates")
	Demo.input(sim, "SetFrontFriendlyStrength", 33.34)
	check(checks, sim.player_view().current("AREA_FRONT_A").friendly_presence == "MEDIUM", "friendlycentithreshold exact")
	data = Demo.definition()
	data.strategic_areas.reverse()
	var reordered := Simulation.new()
	reordered.initialize(data, 109, "step109_A")
	var same: RefCounted = Demo.fresh("A")
	check(checks, Exporter.equivalent(reordered.player_observer.events(), same.player_observer.events()) and Exporter.equivalent(reordered.player_view().snapshot(), same.player_view().snapshot()), "canonicalareaorder deterministic despiteconfigurationorder")
	var repeat: RefCounted = Demo.fresh("A")
	check(checks, JSON.stringify(repeat.player_observer.events(), "", true, true) == JSON.stringify(same.player_observer.events(), "", true, true), "sameworld/config/seed exactobserverIDsandorder")
	var history: Array = repeat.player_observer.events()
	history[0].qualitative_value = "TAMPERED"
	check(checks, repeat.player_observer.events()[0].qualitative_value != "TAMPERED" and repeat.player_view().recent_history(0).is_empty() and repeat.player_view().recent_history(1).size() == 1, "detachedappendonlyhistory andboundedrecentqueries")
	var invalid := PlayerView.new({"areas": repeat.player_observer.configuration(), "records": [{"area_id": "AREA_FRONT_A", "observation_type": "FRIENDLY_PRESENCE", "qualitative_value": 8000, "observed_at": 0, "metadata": {"ammo": 777}}, {"area_id": "AREA_FRONT_A", "observation_type": "EXACT_AMMO", "qualitative_value": "777", "observed_at": 0}]})
	check(checks, invalid.snapshot().history.is_empty() and not JSON.stringify(invalid.snapshot()).contains("8000") and not JSON.stringify(invalid.snapshot()).contains("777"), "defensiveview whitelist rejects malformedexactvalue/unknowncue")
	data = Demo.definition()
	for area in data.strategic_areas: area.enabled = false
	var invisible := Simulation.new()
	invisible.initialize(data)
	check(checks, invisible.player_observer.events().is_empty() and invisible.player_view().areas().is_empty(), "configuredalldisabledareas emitnothing andexposeemptyview")

static func _package_integrity(sim: RefCounted, checks: Array) -> void:
	var directory := "res://artifacts/run_step109_tampered"
	Exporter.export_run(sim, directory)
	check(checks, Exporter.replay_package(directory).success, "untampereddualstream package strictreplay")
	var altered: Array = Exporter.read_lines(directory.path_join("player_observation_events.jsonl")).details.value
	altered[0].source_authoritative_event_id = "event:9999999999"
	Exporter.write_json(directory.path_join("player_observation_events.jsonl"), altered, true)
	check(checks, Exporter.replay_package(directory).error_code == "OBSERVER_PACKAGE_HASH_MISMATCH", "tamperedobserverstream failsmanifesthash")
	var manifest: Dictionary = Exporter.read_json(directory.path_join("manifest.json")).details.value
	manifest.streams.player_observation.sha256 = FileAccess.get_sha256(directory.path_join("player_observation_events.jsonl"))
	Exporter.write_json(directory.path_join("manifest.json"), manifest)
	check(checks, Exporter.replay_package(directory).error_code == "PLAYER_OBSERVATION_REPLAY_MISMATCH", "evenrehashedforgedcrossstreamsource failsstrictregeneratedreplay")
	Exporter.export_run(sim, directory)
	var projection: Dictionary = Exporter.read_json(directory.path_join("final_player_observer.json")).details.value
	projection.view.current.AREA_FRONT_A.private_ammo = 777
	Exporter.write_json(directory.path_join("final_player_observer.json"), projection)
	manifest = Exporter.read_json(directory.path_join("manifest.json")).details.value
	manifest.observer_projection_sha256 = FileAccess.get_sha256(directory.path_join("final_player_observer.json"))
	Exporter.write_json(directory.path_join("manifest.json"), manifest)
	check(checks, Exporter.replay_package(directory).error_code == "PLAYER_OBSERVATION_REPLAY_MISMATCH", "forgedexactfield inpublicview failsstrictprojectionreplay")
	Exporter.export_run(sim, directory)
	var configuration: Dictionary = Exporter.read_json(directory.path_join("player_observer_config.json")).details.value
	configuration.strategic_areas.AREA_FRONT_A.location_ids = ["MISSING"]
	Exporter.write_json(directory.path_join("player_observer_config.json"), configuration)
	manifest = Exporter.read_json(directory.path_join("manifest.json")).details.value
	manifest.observer_configuration_sha256 = FileAccess.get_sha256(directory.path_join("player_observer_config.json"))
	Exporter.write_json(directory.path_join("manifest.json"), manifest)
	check(checks, Exporter.replay_package(directory).error_code == "INVALID_STRATEGIC_AREA", "invalidrehashedconfiguration rejectedafterfreshload")
	Exporter.export_run(sim, directory)
	altered = Exporter.read_lines(directory.path_join("player_observation_events.jsonl")).details.value
	altered[0].run_id = "UNEXPECTED_FIELD"
	Exporter.write_json(directory.path_join("player_observation_events.jsonl"), altered, true)
	manifest = Exporter.read_json(directory.path_join("manifest.json")).details.value
	manifest.streams.player_observation.sha256 = FileAccess.get_sha256(directory.path_join("player_observation_events.jsonl"))
	Exporter.write_json(directory.path_join("manifest.json"), manifest)
	check(checks, Exporter.replay_package(directory).error_code == "PLAYER_OBSERVATION_REPLAY_MISMATCH", "observerstrictcompare doesnotinheritcore run_idnormalizationexception")
