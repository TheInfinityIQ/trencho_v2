#109: player observation and strategic areas

Project0.3.0/schema2C.1; actual Godot4.7.2.stable.steam.ed1daf0bf. REQUIREMENTS_109.md is the full packet. AMENDMENT_109.md explicitly authorizes the separate stream and strengthens AI inertness to byte-identical authoritative output. Accepted2A/2B tags remain immutable.

## Three independent boundaries

WorldState remains objective simulation authority. Existing InformationService/CommandView/local planner/superior arbitration remain command knowledge. `PlayerObserver` is an independent, one-way qualitative presentation projection. It holds no Simulation/WorldState reference and calls no command service. Simulation delivers each already-committed authoritative event plus read-only entity queries to the observer after appending that authoritative event.

Configuring observation never allocates an authoritative ID, writes InformationRecords, triggers planners, changes resource quantities or affects command timing. All accepted policies, one-second observations,1.5-second freshness and existing information records remain unchanged. PlayerObserverView does not implement the command belief interface. No player commands, attention/questions, recon, procurement or strategic UI are implemented.

## StrategicArea configuration

Optional world-definition `strategic_areas` contains stable IDs, display names, nonempty location-ID arrays, optional front ID, enabled flag and JSON-compatible metadata. Defaults: display name=id, front=null, enabled=true, metadata={}. IDs must be unique nonempty strings without the runtime-ID separator. All references validate, location lists reject duplicates, and a location belongs to at most one enabled area. Disabled areas may overlap but generate no observations. No areas means no observer events; prior fixtures retain authoritative sequences apart from version metadata.

Areas are persisted observation/interaction configuration outside authoritative WorldState, as specifically approved. Their configuration is exported separately and validated again on replay. Unknown metadata remains developer/internal configuration; it never enters the normal player view. Area IDs/display names are intentionally public future targeting labels; raw location/front/observation/source-event/source-entity IDs are not public view fields. No coordinates are introduced.

## Observation semantics

Initial qualitative cues use RUN_STARTED as explicit source_authoritative_event_id. Areas sort by ID, then canonical type order FRONT_BEHAVIOR,FRIENDLY_PRESENCE,ENEMY_ACTIVITY,SUPPLY_DEPARTURE_VISIBLE,SUPPLY_ARRIVAL_VISIBLE,SUPPLY_LOSS_VISIBLE. Each area has at most one front; each physical event has one named shipment. The order is independent of dictionary/configuration insertion order.

Postures map HOLD→HOLDING,PRESS→PRESSING,REDUCE_ACTIVITY→REDUCED_ACTIVITY,WITHDRAW→WITHDRAWING. Strength and pressure use exact canonical centi boundaries0..3333LOW,3334..6666MEDIUM,6667..10000HIGH. Front mutation events are inspected immediately, including initialization; a cue is recorded only when the qualitative value changes. Accumulator/demand changes and repeated values create no redundant front cue.

Only SHIPMENT_DISPATCHED/ARRIVED/DESTROYED create visible departure/arrival/loss. Departure uses origin location, arrival destination location, loss the existing abstract current_location_id (not invented coordinates). Initial already-in-flight cargo creates no fake departure. Cues expose SUPPLY_MOVEMENT, area and time; no resource identity, stock, quantity, claim, requester, need or private reasoning. Planned/reserved cargo is not visible physical movement.

## Separate stream and exact replay

The existing `events.jsonl` and authoritative ID/causation model are untouched. Player records/events use independent monotonic namespaces player-observation:N and player-observation-event:N. Internal records retain source_event_id/source_entity_id/metadata; semantic events use explicit source_authoritative_event_id and previous_observation_event_id rather than overloading authoritative same-stream causation. This is not a second world authority.

Enabled packages add player_observer_config.json,player_observation_events.jsonl,final_player_observer.json. Manifest identifies both stream names/schemas and SHA256 hashes plus config/projection hashes. FileAccess.get_sha256 executes on the actual4.7.2 build. Ordinary observer-off packages have player_observation_enabled=false and no new observation files/events are generated. The importer and accepted authoritative equivalence comparator are unchanged.

Fresh replay initializes validated separate config and regenerates both streams through the normal input/tick path. Independently, event-only reconstruction applies the recorded authoritative stream to WorldState and derives the observer without running AI, then compares all observation events, records, latest projection and sanitized view. The observer comparator checks canonical serialized values exactly, without the authoritative comparator's run_id exception or numeric normalization. Tampered streams fail hashes; even a rehashed forged cross-stream source or private public-view field fails regeneration comparison. Invalid area config is rejected on reload.

## Detached public surface

`Simulation.player_view()` returns a detached `PlayerObserverView`. `areas()` exposes area_id/display_name; `current(area_id)` provides qualitative front cues and last generic movement; `recent_history(limit)` returns only area_id,observed_at,observation_type,qualitative_value (bounded0..1000,default50). `snapshot()` returns those sanitized values. Queries return deep copies and retained old views never update behind callers.

The constructor copies only a fixed field allowlist and validates type/value enum pairs. It omits generic metadata, exact strength/pressure/ammo/coverage/demand/consumption/shortage, cargo/reservation/need quantities, scores and internal provenance even from its private backing value. Developer run packages still contain authoritative and internal audit data; those are not the normal player-facing view and no confidentiality claim is made for developer exports.

## Verification scenarios

A: objective80/40/PRESS gives HIGH/MEDIUM/PRESSING, no exact data or metadata leakage. B: pressure32→34 crosses LOW→MEDIUM with exact source event;34→35 mutates world without duplicate cue. C: physical HQ→A arrival at0.5s is immediately visible, while remoteLOCAL_B has no details or A inventory access and LOCAL_A beliefs have not sampled it; later a real delayed report informs B. Further real dispatch/destruction verifies movement/loss. D: full accepted25s/250tick integrated hierarchy with/without four areas has byte-identical authoritative events.jsonl, entity IDs, entire state and all AI/resource projections; only separate observer files differ. E: pressure changes at1.1s, player sees MEDIUM immediately, command retains its3200 belief until its ordinary2.0s local observation updates to3400.

Additional checks cover band edges, posture enums, invalid/duplicate/overlapping/disabled areas, deterministic fan-out, detached queries/history, source/previous-ID chains, strict data allowlists and forged packages. Every relevant authoritative prefix conserves resources/claims and full reconstruction; accepted834-check foundations remain mandatory. Fresh-process replay verifies A–E and observer-disabled D separately.

## Reproduction, housekeeping and limits

Run tools/run.ps1 -Mode observer -TimeoutSeconds150 for targeted tests/packages and -Mode test -TimeoutSeconds180 for all regressions. Replay using -Mode replay -Package res://artifacts/run_step109_A (substitute B–E or D_disabled). Use the preserved -Mode inspector-headless for startup safeguards. Inspector UI changes are optional and intentionally omitted.

The named Generation2 GDD PDF/DOCX were not found in synced sources, the established handoff folder or the checked readable local download/Codex locations. Some unrelated local dependency folders were unreadable; no missing GDD was fabricated/recreated and no older GDD was overwritten. This administrative absence is not an implementation blocker.

This is a headless architectural boundary, not player input, reconnaissance, strategic influence, a polished interface or graphical/performance validation. Frozen2B remains independently reproducible by its accepted tag; new-schema packages are not a migration of old evidence. Stop at109 review; no110.
