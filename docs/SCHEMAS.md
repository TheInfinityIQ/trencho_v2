# Diagnostic schemas — 2B.2 / project 0.2.1

Step 103 adds the fronts registry with canonical integer fixed-point fields and private front observations; see FRONTS_103.md for field and belief units. Current replay requires schema2B.1/project0.2.0. The following closeout notes describe the preserved 2A baseline.

The closeout adds communication diagnostics and repairs correlation metadata without changing physical simulation semantics. These additive envelope/payload fields retain schema `2A.1`; the simulation project version is bumped to `0.1.1` because normalized event output differs from `0.1.0`. Older packages remain inspectable data and can be replayed with their original source revision; the closeout loader explicitly rejects their older project version rather than silently changing their replay output.

## Run directory

```text
run_<run_id>/
    manifest.json
    initial_world.json
    final_world.json
    events.jsonl
    inputs.jsonl
```

`manifest.json` fields: `run_id`, `project_version`, `schema_version`, `engine_version`, `simulation_seed`, `tick_duration`, `start_time_utc`, `end_tick`, `initial_world_definition_id`. UTC wall time is diagnostic metadata only and does not influence simulation output. A package can be exported while a run is active; the demonstration explicitly ends its run first.

## Snapshots

Both world files contain all registries as objects keyed by stable entity ID:

`locations`, `commands`, `resource_types`, `stockpiles`, `logistics_edges`, `communication_edges`, `resource_reservations`, `shipments`, `messages`, `information_records`, `ledger`, `fronts`.

They also contain `schema_version`, `project_version`, `engine_version`, `run_id`, `simulation_seed`, `initial_world_definition_id`, `event_sequence`, `input_sequence`, `ended`, `rng_state`, `public_facts`, and `clock`.

`clock` contains `tick_index`, `tick_duration`, `simulation_time_seconds`. `rng_state` is an exact decimal string. A ledger row is `{id, created, consumed, destroyed}`; physical stock/cargo totals are derived, not duplicated as a stored total.

Entity fields follow the supplied requirements. `position_2d` is a JSON two-number array. Nullable IDs/timestamps use JSON null. Dictionaries such as quantities/reserved use resource IDs as keys. Internal indexes and provenance lookup caches are derived and excluded from snapshots.

Initial snapshots contain the validated complete static baseline before RUN_STARTED, event/input sequence zero, tick zero, empty runtime records, and zero reservations. Initialization events describe those baseline entities. The replay loader validates version, identity, topology, authority, quantities, ledger and initial projection consistency. It rejects unsupported schemas and differing reported engine version strings instead of interpreting them as current data. `engine_version` stores `Engine.get_version_info().string`; executable provenance is recorded separately in the handoff.

Reservation states: `ACTIVE`, `FULFILLED`, `CONSUMED`, `RELEASED`, `INVALIDATED`. FULFILLED is specific to shipment dispatch. Shipment and message states follow the requirements. `QUEUED` is reserved in the message schema; a successful send directly creates IN_TRANSIT, and 2A adds no queue policy.

Messages add `delivery_tick` to the required fields so tick scheduling is explicit. The outgoing message retains its payload; only DELIVERED messages enter recipient CommandViews. Information records retain both nullable `source_command_id` and nullable `source_system` fields.

## Event envelope

Every JSONL line contains:

```json
{
  "event_id": "event:0000000042",
  "event_type": "SHIPMENT_DISPATCHED",
  "schema_version": "2A.1",
  "run_id": "demo",
  "tick_index": 3,
  "simulation_time": 0.3,
  "actor_entity_id": null,
  "subject_entity_id": "shipment:0000000038",
  "location_id": "ARMY_HQ",
  "correlation_id": "input:0000000005",
  "causation_event_id": "event:0000000041",
  "payload": {"privileged": true, "changes": []}
}
```

`event_id` is ordered application sequence. `correlation_id` links the initiating input throughout autonomous shipment/message updates. `causation_event_id` identifies an earlier input/operation/entity event or message delivery; multi-event transfers retain explicit links. This supports tracing origin without treating chronology alone as a causal claim.

`payload.changes` is an ordered array of `{table, id, value}` complete changed entity projections. `clock` replaces the clock projection. `run` patches run metadata keys such as `input_sequence` and `ended`. These are validated internal changes created by services; they are not an external arbitrary-write API. Atomic transfers put all affected records in one event. Informational companion events can have an empty changes array.

Communication closeout guarantees:

* `MESSAGE_SENT`, its `MESSAGE_DELIVERED` and every resulting `INFORMATION_INGESTED` share the originating message/input correlation ID. Delivery points causally to the send event; ingestion points to the immediate delivery event. This also holds for zero-latency delivery and multiple messages delivered at one tick. Direct privileged ingestion keeps its own input correlation.
* `MESSAGE_FAILED.payload.reason_code` is `ROUTE_DISABLED` for the current unavailable-route behavior. `failed_edge_ids` lists unavailable required route edges in route order. An enabled edge whose endpoint command is disabled is also unavailable. The existing self-message/disabled-recipient corner can have an empty edge array because its zero-edge route contains no edge.
* `failed_edge_change_event_ids` maps each actually disabled edge to the authoritative event that most recently changed it. The failed message's causation points to the original send, while this payload records the independent edge-change causes explicitly. Correlation remains the original send operation, never the input that disabled an edge.

All required minimum event types are supported with the designer's dispatch rename. Added event types are:

* `INPUT_RECEIVED`: accepted-for-processing JSON-compatible input and input sequence; validation may subsequently fail.
* `TICK_ADVANCED`: authoritative tick/time.
* `RESOURCE_TYPE_DEFINED`, `STOCKPILE_CREATED`: baseline entity records.
* `STOCKPILE_ENABLED_CHANGED`: explicit developer enable/disable operation.
* `SHIPMENT_PROGRESS_CHANGED`: partial traversal, ensuring event-only reconstruction.
* `RESERVATION_FULFILLED`: stock-to-cargo transfer, with no consumption.

`RESERVATION_CONSUMED` is retained only for actual standalone reservation consumption. `RESOURCE_CONSUMED`/`RESOURCE_DESTROYED` companion records carry quantity/type and reason where applicable; their ledger changes have already been atomically applied in the causal event.

Future `DECISION_STARTED`, `DECISION_CANDIDATE_RECORDED`, `DECISION_SELECTED`, `DECISION_OUTCOME_ATTACHED` can use this same envelope and extensible payload. The kernel emits none in its production demonstration. A test checks JSON compatibility of a sample candidate record.

## External input records

```json
{
  "schema_version": "2A.1",
  "input_id": "input:0000000001",
  "tick_index": 0,
  "privileged": true,
  "command": {"type": "CreateResource", "stockpile_id": "SOURCE_STOCK", "resource_type_id": "AMMUNITION", "quantity": 1000},
  "result": {"success": true, "error_code": "", "entity_id": "SOURCE_STOCK", "details": {}}
}
```

Privilege is an explicit trusted caller flag, not an escalation requested by the command dictionary. It is logged in both inputs and event payloads. Future gameplay callers use `execute(command, false)` and must provide the correct `actor_entity_id`; debug fixtures explicitly use true. Authority and information access remain separate.

Supported command types and required payload fields:

| Type | Fields beyond optional actor_entity_id |
| --- | --- |
| CreateResource | stockpile_id, resource_type_id, quantity; privileged |
| ConsumeResource / DestroyResource | stockpile_id, resource_type_id, quantity, reason_code |
| ReserveResource | stockpile_id, resource_type_id, quantity; optional purpose_code |
| ReleaseReservation / ConsumeReservation / InvalidateReservation | reservation_id; invalidation privileged |
| CreateShipment | origin_stockpile_id, destination_stockpile_id, resource_type_id, quantity |
| DispatchShipment / CancelShipment | shipment_id |
| RerouteShipment | shipment_id, destination_stockpile_id |
| DestroyShipment | shipment_id, reason_code; privileged |
| SetEnabled | table, entity_id, enabled; privileged |
| ReparentCommand | command_id, superior_command_id or null; privileged |
| SendMessage | sender_command_id, recipient_command_id, message_type, payload |
| IngestInformation | owner_command_id, fact; privileged |
| EndRun | privileged |

REPORT payload contract: `{ "facts": [ { "subject_entity_id": "...", "fact_key": "...", "value": <JSON value>, "observed_at": 0.0, "confidence": 0.8, "expires_at": null } ] }`. All facts are validated before the message is created. Source identity is assigned from the actual sender on delivery; caller payload cannot forge the record's source or recipient. Other message types have no automated gameplay policy.

## Results and errors

All external simulation actions return `{success, error_code, entity_id, details}`. Failed actions do not leave partial resource operations. Required error codes are implemented; additional validation/export codes include `INVALID_INPUT`, `INVALID_WORLD_DEFINITION`, `INVALID_SNAPSHOT`, `INVALID_INFORMATION`, `INVALID_MESSAGE_TYPE`, `UNSUPPORTED_SNAPSHOT`, `ENGINE_VERSION_MISMATCH`, `EXPORT_FAILED`, `IMPORT_FAILED`, `INVALID_REPLAY_INPUT`, `REPLAY_INPUT_MISMATCH`, `REPLAY_MISMATCH`.

## Replay normalization

Normalization recursively sorts dictionary keys, leaves arrays in order, canonicalizes integral floats within JSON's exact integer range, and omits diagnostic `run_id`. It preserves seed, schema, project/engine version, timestamps in logical time, provenance, IDs, all entity contents and event order. Wall-clock start time occurs only in the manifest, which is not part of the deterministic event/state comparison.

Replay validates the initial world, applies external commands at their original ticks and in file order, and checks each result before comparing final state and the complete event stream. It does not inject recorded authoritative events while re-simulating, so an incorrect service result cannot be hidden by loading the expected events. Independent event-only projection reconstruction is tested separately.


## 2B.1 front and import additions

Snapshots add fronts, including integer centi-strength/pressure, milli-ammo base rate, micro-ammo accumulator, microsecond observation deadlines and integer interval counters. Front belief values follow the canonical unit table in FRONTS_103.md; coverage has both milliseconds and a FINITE/ZERO_DEMAND/OUT_OF_RANGE status fact. Each sample now emits nine facts. Run artifact imports preserve exact integer number tokens within +/-9007199254740991 and explicitly reject unsupported integer tokens. Decimal/exponent interpretation and string values retain their existing behavior. The external JSON format and strict comparison are unchanged.

## 2B.2 decision additions

Commands gain nullable local_decision_front_id. New authoritative registries: observation_batches, decisions, decision_candidates. Autonomous observation batches have11 records and explicit completion; ordinary103 fronts retain9. Decision/candidate/outcome fields, canonical units, correlation/causation and privileged diagnostic input are specified in DECISIONS_104.md. Current replay requires project0.2.1/schema2B.2; accepted earlier packages use their preserved source revisions. Exact integer import and strict comparison remain unchanged.
