# Trencho — Prototype Generation 2A
## Simulation Kernel Requirements v0.1

**Project:** Trencho  
**Phase:** Prototype Generation 2A — Simulation Kernel  
**Purpose:** Build the new project's reusable simulation foundation before autonomous battlefield command, combat, deck interaction, officers, or player-facing strategy are implemented.

---

# 1. Executive Decision

Prototype Generation 2A will be built as a **new Godot project**.

The current Trencho prototype remains a frozen reference implementation and parts library. Do not refactor the existing tactical-command project into this architecture.

The new project's fundamental ownership model is:

```text
WORLD STATE
    ↓
EVENTS / INFORMATION
    ↓
COMMAND HIERARCHY + LOGISTICS
    ↓
LATER PHASES:
AUTONOMOUS PLANNING → BATTLEFIELD EXECUTION → PLAYER STRATEGIC INFLUENCE
```

2A exists to prove that the simulation can represent and reconstruct:

- physical resources;
- locations;
- logistics routes;
- shipments;
- command hierarchy;
- authority boundaries;
- communication links;
- delayed information;
- private command knowledge;
- causal world events;
- deterministic runs;
- exportable diagnostic data.

2A does **not** need to be fun.

It needs to be correct, modular, inspectable, deterministic when given the same inputs, and suitable for later systems to depend on without knowing one another's implementation details.

---

# 2. North-Star Architecture

The future game is based on this principle:

> **Build the war machine, supply it, influence its priorities, and watch an autonomous command structure try to win the war with what you gave it.**

2A must therefore avoid architecture that assumes:

- the player directly controls squads;
- the player owns tactical objectives;
- a command AI can inspect the entire world;
- all friendly commands share information instantly;
- resources exist as global integers;
- supplies teleport to consumers;
- one system may directly mutate another system's internal state;
- every visible soldier must exist for the strategic simulation to function.

---

# 3. Reference Project Policy

The existing Trencho project is a **reference source only**.

For 2A:

## May be reused deliberately
- generic utility code;
- RNG/seeding approaches;
- telemetry concepts;
- serialization helpers;
- test-runner techniques;
- UI fonts/icons if convenient;
- project setup conventions;
- data-loading techniques.

## Must not be copied as architectural foundations
- `SquadCommand` ownership model;
- player squad selection;
- drawn direct squad routes;
- Defensive Point / Defensive Front ownership model;
- formation-block slot logic;
- reserve-slot logic;
- Line/Triangle battlefield doctrine code;
- tactical reinforcement gesture semantics;
- existing battle scene hierarchy.

Any reused code must be migrated because it fits the new system boundary, not because it already exists.

---

# 4. Engine and Project Requirements

Use **Godot 4.7.2 stable** for 2A unless a blocking technical incompatibility is demonstrated.

2A must support:

- headless simulation runs;
- deterministic automated tests;
- normal editor execution;
- JSON/JSONL diagnostic export;
- fixed-step simulation independent of rendering frame rate.

No `.NET` dependency is required.

---

# 5. Hard Non-Goals for 2A

Do **not** implement these in this phase:

- player cards or deck UI;
- card combinations;
- economy production gameplay;
- combat;
- soldier AI;
- visible battlefield units;
- tactical pathfinding;
- formation systems;
- objective selection AI;
- attack/defend plans;
- command personality;
- officer traits;
- rank-specific historical behavior;
- morale;
- fuel;
- food;
- medicine;
- artillery;
- vehicles;
- POWs;
- captured equipment;
- roads being built by AI;
- railroads being built by AI;
- FOB construction logic;
- resource-request decision logic;
- AI negotiation logic;
- autonomous resource arbitration;
- player-facing strategic UI.

2A may provide **generic data structures/interfaces** needed by these future systems, but must not implement their gameplay policies.

---

# 6. Simulation Model

## 6.1 Fixed simulation clock

The simulation must run on a fixed logical tick.

Recommended initial value:

```text
simulation_tick = 0.1 seconds
```

The exact value may be changed if profiling justifies it, but all simulation time must use the logical simulation clock rather than render-frame delta.

Required clock state:

```text
tick_index: int
simulation_time_seconds: float
```

For a fixed step:

```text
simulation_time_seconds = tick_index * tick_duration
```

Do not accumulate floating-point render delta as the authoritative simulation time.

## 6.2 Deterministic run identity

Every run must contain:

```text
run_id
simulation_seed
schema_version
project_version
engine_version
initial_world_definition_id
```

If the same initial world, scripted inputs, seed, and simulation version are used, the resulting authoritative state and ordered event output must match.

If nondeterminism is later added, every random choice must use the simulation RNG and be logged.

Do not use unseeded global randomness inside simulation systems.

---

# 7. Entity Identity

Every persistent runtime entity must have a stable unique ID.

Use one shared ID namespace or typed namespaces, but IDs must never depend on:

- Godot node paths;
- memory addresses;
- display names;
- array positions.

Entities requiring IDs in 2A include:

```text
Location
CommandNode
LogisticsEdge
CommunicationEdge
Stockpile
ResourceReservation
Shipment
Message
InformationRecord
Event
```

Display names may change without breaking references.

---

# 8. Authoritative State and Mutation Rule

2A should use an **event-applied state model**.

Persistent simulation state must be changed through explicit state-transition methods that emit/apply authoritative events.

Avoid arbitrary cross-system mutation such as:

```text
other_system.stock -= 50
```

Instead:

```text
ResourceService.dispatch_shipment(...)
→ validates
→ creates authoritative event(s)
→ WorldState.apply_event(...)
```

The event log must be sufficient to reconstruct what changed, when, which entity initiated it, and what caused it.

The world may maintain efficient in-memory projections/caches, but these may not become hidden sources of truth.

---

# 9. World State

Create a central `WorldState` containing registries for:

```text
locations
commands
resource_types
stockpiles
logistics_edges
communication_edges
shipments
resource_reservations
messages
information_records
```

`WorldState` must expose query APIs.

Other systems should not manually search arbitrary scene-tree nodes to find strategic state.

Recommended conceptual interface:

```gdscript
WorldState.get_location(id)
WorldState.get_command(id)
WorldState.get_stockpile(id)
WorldState.get_shipment(id)
WorldState.get_outgoing_logistics_edges(location_id)
WorldState.get_communication_edges(command_id)
```

---

# 10. Locations

A `Location` represents a strategic/logistical place.

2A must support at least these location roles through data:

```text
OFFSCREEN_SOURCE
HQ
COMMAND_SITE
DEPOT
GENERIC
```

Do not hardcode behavior based on display names such as `"HQ West"`.

Required fields:

```text
id
display_name
location_type
position_2d
enabled
metadata
```

`position_2d` is strategic-map position only.

2A does not require a physical soldier-scale interpretation.

---

# 11. Resource Types

The resource system must be generic.

Required `ResourceType` fields:

```text
id
display_name
unit_name
allow_fractional_quantity: bool
metadata
```

2A initially instantiates exactly one gameplay resource:

```text
AMMUNITION
```

Recommended:

```text
allow_fractional_quantity = false
unit_name = "ammo"
```

Do not hardcode ammunition-specific fields into stockpile, shipment, or reservation code.

Future resource types must be addable through data without rewriting those systems.

---

# 12. Stockpiles

A `Stockpile` is physical resource ownership at one location.

Required fields:

```text
id
location_id
owner_command_id or null
quantities: Dictionary[resource_type_id -> quantity]
reserved: Dictionary[resource_type_id -> quantity]
enabled
```

Required derived value:

```text
available(resource) = on_hand(resource) - reserved(resource)
```

Invariant:

```text
0 <= reserved <= on_hand
```

No operation may create negative available stock.

---

# 13. Resource Conservation

Except for explicit creation/destruction events, resources must be conserved.

For each resource type:

```text
created
=
current_stockpiles
+ in_transit_shipments
+ consumed
+ destroyed
```

2A must have a test/helper that calculates the resource ledger and detects unexplained gain/loss.

The only valid resource creation event in 2A is scripted/debug input such as:

```text
RESOURCE_CREATED
```

The only valid resource destruction paths in 2A are:

```text
RESOURCE_CONSUMED
RESOURCE_DESTROYED
```

No other operation may silently remove quantity.

---

# 14. Resource Reservations

A reservation is a concrete claim against stock already present at a stockpile.

It is **not** a continuously changing battlefield need.

Required fields:

```text
id
stockpile_id
resource_type_id
quantity
claimant_command_id or null
purpose_code
created_at
state
```

States:

```text
ACTIVE
CONSUMED
RELEASED
INVALIDATED
```

Rules:

1. Creating a reservation requires `requested_quantity <= available_quantity`.
2. An ACTIVE reservation reduces available stock.
3. Releasing it restores availability.
4. Consuming it removes the reserved quantity from physical on-hand stock.
5. A reservation may only be consumed once.
6. Releasing or consuming a non-ACTIVE reservation must fail cleanly.
7. Reservation quantities cannot be negative or zero.
8. Reservations must not silently shrink because another system needs stock.

Dynamic future "needs" will be separate from reservations.

---

# 15. Logistics Network

Locations are connected by directed `LogisticsEdge` entities.

Required fields:

```text
id
from_location_id
to_location_id
travel_time_seconds
enabled
transport_mode
metadata
```

Initial `transport_mode`:

```text
ABSTRACT_ROUTE
```

Do not implement roads/rail behavior yet.

Do not assume edges are bidirectional.

If bidirectional travel is desired, define two edges.

---

# 16. Logistics Routing

2A must support deterministic route finding across enabled logistics edges.

Route cost for 2A:

```text
sum(edge.travel_time_seconds)
```

Use the lowest total travel-time route.

Tie-break equal-cost routes deterministically by ordered edge IDs.

Required route result:

```text
origin_location_id
destination_location_id
edge_ids[]
total_travel_time
```

If no route exists, return:

```text
NO_LOGISTICS_ROUTE
```

---

# 17. Shipment Lifecycle

A `Shipment` physically transfers resources.

Required fields:

```text
id
resource_type_id
quantity
origin_stockpile_id
destination_stockpile_id
requested_by_command_id or null
reservation_id
route_edge_ids[]
current_route_index
current_location_id
edge_progress_seconds
state
created_at
departed_at
arrived_at
blocked_reason
```

States:

```text
PLANNED
IN_TRANSIT
BLOCKED
ARRIVED
CANCELLED
DESTROYED
```

---

# 18. Creating a Shipment

Creating a shipment must be atomic.

Inputs:

```text
origin_stockpile_id
destination_stockpile_id
resource_type_id
quantity
requesting_command_id
```

Validation order:

1. quantity > 0;
2. origin and destination exist and are enabled;
3. origin != destination;
4. requesting command has authority to dispatch from origin OR call is privileged test/system input;
5. sufficient available origin stock;
6. logistics route exists.

On success:

1. create reservation;
2. create PLANNED shipment referencing reservation and route;
3. emit shipment-created event.

No stock leaves origin at creation time.

If any validation fails, neither reservation nor shipment may remain.

---

# 19. Dispatching a Shipment

Dispatch converts reserved stock into in-transit cargo.

Requirements:

1. shipment must be `PLANNED`;
2. reservation must still be `ACTIVE`;
3. reservation quantity/type must match shipment;
4. first logistics edge must still be enabled.

On success, atomically:

```text
consume reservation
subtract shipment quantity from origin on_hand
state = IN_TRANSIT
current_location = origin
current_route_index = 0
edge_progress_seconds = 0
```

The quantity now exists in the shipment and not in any stockpile.

---

# 20. Shipment Movement

Each simulation tick:

1. if shipment is not `IN_TRANSIT`, do nothing;
2. inspect current route edge;
3. if edge is disabled before traversal completes:
   - shipment becomes `BLOCKED`;
   - cargo remains in shipment;
   - current location remains the most recently reached location;
   - no resource is lost;
4. otherwise increase edge progress by tick duration;
5. when progress reaches/exceeds edge travel time:
   - move shipment to edge destination;
   - carry any overshoot time into the next edge;
6. if final destination is reached:
   - add cargo to destination stockpile;
   - state = `ARRIVED`;
   - cargo quantity leaves in-transit accounting.

A shipment may traverse multiple short edges in one tick if carried overshoot is sufficient.

---

# 21. Shipment Cancellation

## Before dispatch

A `PLANNED` shipment may be cancelled.

Result:

- reservation released;
- shipment state = `CANCELLED`;
- origin stock remains unchanged.

## After dispatch

An `IN_TRANSIT` or `BLOCKED` shipment may **not** be cancelled into nothing.

Valid future actions are:

```text
REROUTE
RETURN
DESTROY
```

For 2A, implement:

```text
reroute_shipment(shipment_id, new_destination_stockpile_id)
```

Rerouting computes a new route from the shipment's current location.

If no route exists, shipment remains `BLOCKED`.

Do not teleport cargo back to origin.

---

# 22. Shipment Destruction

2A must support an explicit developer/test action:

```text
destroy_shipment(shipment_id, reason_code)
```

Valid for:

```text
IN_TRANSIT
BLOCKED
```

Result:

- state = `DESTROYED`;
- cargo enters the resource-ledger destroyed total;
- no destination receives it.

This supports future combat/interdiction without implementing those systems now.

---

# 23. Command Hierarchy

A `CommandNode` is an authority/information entity.

Do not hardcode historical WWII rank names yet.

Required fields:

```text
id
display_name
command_level
superior_command_id or null
subordinate_command_ids[]
directly_controlled_location_ids[]
directly_controlled_stockpile_ids[]
enabled
metadata
```

Initial generic command levels:

```text
STRATEGIC
OPERATIONAL
LOCAL
```

These are architecture labels, not final game terminology.

---

# 24. Command Hierarchy Invariants

Requirements:

1. hierarchy must be acyclic;
2. a command may have zero or one direct superior;
3. a command may have any number of direct subordinates;
4. a command cannot be its own ancestor;
5. disabling a command does not delete its history;
6. reparenting a command must emit an event;
7. deleting commands is not required in 2A.

Provide validation that rejects cyclic hierarchy changes.

---

# 25. Authority Rules

Authority and information are separate.

A command may directly mutate/allocate only objects within its defined authority.

For 2A, a command has direct resource-dispatch authority over:

```text
directly_controlled_stockpile_ids
```

A superior does **not** automatically gain implementation-level write access to every subordinate stockpile.

Future systems may issue an order causing the subordinate to act.

Provide helper:

```gdscript
AuthorityService.can_dispatch(command_id, stockpile_id) -> bool
```

2A may provide privileged system/test actions that bypass authority, but those bypasses must be explicitly marked in logs.

---

# 26. Communication Network

Commands do not share information automatically.

Communication uses a separate directed graph.

Required `CommunicationEdge` fields:

```text
id
from_command_id
to_command_id
mode
latency_seconds
enabled
metadata
```

Initial mode:

```text
RADIO
```

2A radio is perfectly reliable if the route remains enabled.

Do not implement random packet loss, encryption, jamming, mail, telephone, or messengers yet.

The architecture must not assume `RADIO` is the only future mode.

---

# 27. Communication Routing

Messages may be sent only if a directed communication route exists from sender to recipient.

Route cost:

```text
sum(latency_seconds)
```

Choose deterministic lowest-latency route.

Equal routes use deterministic edge-ID tie-breaking.

No communication route returns:

```text
NO_COMMUNICATION_ROUTE
```

Do not automatically route "through the command hierarchy" unless communication edges actually support that path.

---

# 28. Message Model

Required `Message` fields:

```text
id
sender_command_id
recipient_command_id
message_type
payload
sent_at
route_edge_ids[]
delivery_time
state
correlation_id or null
causation_event_id or null
```

Message types supported by schema:

```text
REPORT
PROPOSAL
COORDINATION
ESCALATION
STRATEGIC_REQUEST
ORDER
ACKNOWLEDGEMENT
GENERIC
```

2A does not implement policy for when these messages should be generated.

Tests/scripts may create them.

States:

```text
QUEUED
IN_TRANSIT
DELIVERED
FAILED
```

---

# 29. Message Delivery

At send time:

1. validate sender/recipient;
2. find communication route;
3. compute deterministic delivery time;
4. create `IN_TRANSIT` message.

While in transit:

- message does not affect recipient belief state;
- sender may retain outgoing record.

At due time:

1. verify every edge in precomputed communication route remains enabled;
2. if yes:
   - state = `DELIVERED`;
   - message appears in recipient inbox;
   - delivery event emitted;
3. if any route edge is disabled:
   - state = `FAILED`;
   - no automatic reroute in 2A;
   - failure event emitted.

Future phases may implement retry/reroute behavior.

---

# 30. No Telepathy Rule

A command decision module added in later phases must not be given raw unrestricted `WorldState`.

2A must create a `CommandView`/query boundary that can eventually expose only:

1. command's own identity/authority;
2. directly controlled local authoritative state;
3. delivered information records;
4. delivered messages;
5. explicitly public/global facts.

The raw world state remains available to simulation services and developer tooling.

This interface boundary must exist in 2A even though no autonomous decision AI is implemented yet.

---

# 31. Information / Belief State

Each command owns a private belief store.

A belief is not necessarily true.

Required `InformationRecord` fields:

```text
id
owner_command_id
subject_entity_id
fact_key
value
source_command_id or source_system
observed_at
received_at
confidence
expires_at or null
source_message_id or null
causation_event_id or null
```

Confidence range:

```text
0.0 to 1.0
```

2A does not implement probabilistic inference.

---

# 32. Information Ingestion

Information enters a command belief store only through explicit ingestion:

```text
InformationService.ingest_record(...)
```

Sources may include:

- delivered message;
- direct local observation inserted by a future simulation system;
- privileged test input.

Do not automatically synchronize a command's belief records with global truth.

---

# 33. Current-Belief Query

2A must support:

```gdscript
get_current_belief(command_id, subject_id, fact_key, simulation_time)
```

Selection rule:

1. discard expired records;
2. choose greatest `observed_at`;
3. tie-break greatest `received_at`;
4. tie-break stable record ID.

Do not blend conflicting reports in 2A.

Return the complete chosen `InformationRecord`, not only its value.

This preserves provenance for later AI reasoning.

---

# 34. Local Authoritative Knowledge

For 2A, a command may access exact state for:

```text
its directly controlled stockpiles
its directly controlled locations
its own metadata
```

This access is through `CommandView`, not beliefs.

Everything else must be learned through information records/messages unless explicitly marked public.

A superior does not automatically know a subordinate's current stockpile level.

The subordinate must eventually report it.

---

# 35. Event Log

Every meaningful authoritative mutation must emit an append-only event.

Required base event fields:

```text
event_id
event_type
schema_version
run_id
tick_index
simulation_time
actor_entity_id or null
subject_entity_id or null
location_id or null
correlation_id or null
causation_event_id or null
payload
```

`event_id` order must match authoritative application order.

---

# 36. Minimum 2A Event Types

Implement at least:

```text
RUN_STARTED
RUN_ENDED

LOCATION_CREATED
LOCATION_ENABLED_CHANGED

COMMAND_CREATED
COMMAND_REPARENTED
COMMAND_ENABLED_CHANGED

LOGISTICS_EDGE_CREATED
LOGISTICS_EDGE_ENABLED_CHANGED

COMMUNICATION_EDGE_CREATED
COMMUNICATION_EDGE_ENABLED_CHANGED

RESOURCE_CREATED
RESOURCE_CONSUMED
RESOURCE_DESTROYED

RESERVATION_CREATED
RESERVATION_RELEASED
RESERVATION_CONSUMED
RESERVATION_INVALIDATED

SHIPMENT_CREATED
SHIPMENT_DISPATCHED
SHIPMENT_REACHED_LOCATION
SHIPMENT_BLOCKED
SHIPMENT_REROUTED
SHIPMENT_ARRIVED
SHIPMENT_CANCELLED
SHIPMENT_DESTROYED

MESSAGE_SENT
MESSAGE_DELIVERED
MESSAGE_FAILED

INFORMATION_INGESTED
```

Future phases may add more event types without changing existing event semantics.

---

# 37. Correlation and Causation

Every event that is part of a multi-step operation must support:

```text
correlation_id
causation_event_id
```

The exact event ordering may differ by implementation, but a causal chain must be reconstructable.

This is a hard requirement for later AI debugging.

---

# 38. Decision Journal Compatibility

2A does not implement autonomous commander decisions.

However, the logging schema must reserve a compatible record type/interface for future:

```text
DECISION_STARTED
DECISION_CANDIDATE_RECORDED
DECISION_SELECTED
DECISION_OUTCOME_ATTACHED
```

Do not fake decision records in production 2A.

A unit test may emit sample records to validate serialization if useful.

---

# 39. World Event vs Information Event

The log must distinguish:

```text
what objectively happened
```

from:

```text
who learned about it
```

Example:

```text
RESOURCE_CREATED
```

does **not** imply every command receives:

```text
INFORMATION_INGESTED
```

Knowledge propagation must remain explicit.

This is fundamental to preventing omniscient AI later.

---

# 40. Exportable Run Package

Every headless or editor simulation run must be exportable into a directory:

```text
run_<run_id>/
    manifest.json
    initial_world.json
    final_world.json
    events.jsonl
    inputs.jsonl
```

## `manifest.json`

Must include:

```text
run_id
project_version
schema_version
Godot version
simulation_seed
tick_duration
start_time_utc
end_tick
initial_world_definition_id
```

## `events.jsonl`

One complete event JSON object per line, ordered by `event_id`.

## `inputs.jsonl`

Every external/scripted input that changed the simulation, including privileged test actions.

This lets a future diagnostic package distinguish external commands from autonomous simulation events.

---

# 41. Snapshot Serialization

`initial_world.json` and `final_world.json` must serialize all persistent 2A state necessary to inspect the run.

Do not serialize transient caches as authoritative state.

Serialized state must include:

- locations;
- commands;
- resource types;
- stockpiles;
- logistics edges;
- communication edges;
- reservations;
- shipments;
- messages;
- belief records;
- simulation clock;
- RNG state if required for exact continuation.

---

# 42. Replay Requirement

Provide a developer replay/test path that can:

1. load `initial_world.json`;
2. apply recorded external inputs at their original tick;
3. run with the recorded seed;
4. produce the same final authoritative state and event sequence.

Exact text serialization order does not need to be byte-for-byte identical if dictionaries are reordered, but normalized semantic output must match.

Provide a normalization helper for tests.

---

# 43. External Inputs

No test may mutate strategic state by directly editing runtime objects.

All scripted/debug actions must use explicit input commands, for example:

```text
CreateResourceInput
EnableLogisticsEdgeInput
DisableLogisticsEdgeInput
CreateShipmentInput
DispatchShipmentInput
RerouteShipmentInput
DestroyShipmentInput
SendMessageInput
IngestInformationInput
ReparentCommandInput
```

Inputs must be logged to `inputs.jsonl`.

This prevents test-only state mutation from bypassing the architecture.

---

# 44. Error Handling

Simulation APIs must return structured results.

Do not use silent failure.

Recommended shape:

```gdscript
{
    "success": bool,
    "error_code": String,
    "entity_id": Variant,
    "details": Dictionary
}
```

Minimum error codes:

```text
INVALID_ENTITY
INVALID_QUANTITY
INSUFFICIENT_AVAILABLE_STOCK
NO_LOGISTICS_ROUTE
NO_COMMUNICATION_ROUTE
UNAUTHORIZED
INVALID_STATE
ROUTE_DISABLED
HIERARCHY_CYCLE
DESTINATION_DISABLED
ORIGIN_DISABLED
RESOURCE_TYPE_MISMATCH
RESERVATION_MISMATCH
```

Tests must assert error codes, not fragile UI/error text.

---

# 45. Service Boundaries

Recommended logical services:

```text
SimulationClock
WorldState
EventStore
ResourceService
LogisticsService
AuthorityService
CommandHierarchyService
CommunicationService
InformationService
RunExporter
```

These may be implemented as Godot nodes, RefCounted services, or another clean pattern.

The requirement is ownership separation, not a specific class inheritance tree.

---

# 46. Forbidden Coupling

Examples:

## Forbidden
`CommunicationService` directly subtracts ammunition.

## Correct
Communication delivers a message. A later command system may react by asking `ResourceService` to perform an authorized operation.

## Forbidden
`CommandNode` scans all stockpiles to discover friendly supply.

## Correct
`CommandView` exposes local authoritative supply plus delivered reports.

## Forbidden
A shipment directly writes destination quantity when created.

## Correct
Shipment cargo enters destination stock only after physical simulated arrival.

## Forbidden
Turning off a communication edge directly changes beliefs.

## Correct
It affects whether future/in-transit messages can be delivered.

---

# 47. 2A Demonstration Fixture

Build one non-gameplay simulation fixture.

Required world:

```text
OFFSCREEN_SOURCE
      |
      v
    ARMY_HQ
    /        v       v
DEPOT_A   DEPOT_B
```

Commands:

```text
STRATEGIC_COMMAND
        |
   ARMY_COMMAND
    /        LOCAL_A    LOCAL_B
```

Communication:

```text
ARMY_COMMAND <-> LOCAL_A
ARMY_COMMAND <-> LOCAL_B
LOCAL_A <-> LOCAL_B
```

All communication uses RADIO initially.

Resources:

```text
AMMUNITION only
```

No combat/frontline simulation.

---

# 48. Required Demonstration Script

The automated demonstration must execute this sequence category:

1. Create 1000 ammunition at `OFFSCREEN_SOURCE`.
2. Create a shipment of 600 from `OFFSCREEN_SOURCE` to `ARMY_HQ`.
3. Dispatch it.
4. Advance simulation until it arrives.
5. Create two shipments:
   - 300 from HQ to DEPOT_A;
   - 200 from HQ to DEPOT_B.
6. Dispatch both.
7. Disable the final logistics edge to DEPOT_B before its shipment completes.
8. Verify:
   - A shipment arrives normally;
   - B shipment becomes `BLOCKED`;
   - no ammunition disappears.
9. Re-enable or reroute the blocked shipment through a valid alternate route provided by the fixture.
10. Verify eventual arrival.
11. Have LOCAL_A send a `REPORT` message to ARMY_COMMAND containing a test fact.
12. Verify ARMY_COMMAND cannot see that fact before message delivery.
13. Verify it receives/ingests the information only after delivery.
14. Disable a communication edge.
15. Send another message whose route depends on that edge.
16. Verify message failure and no recipient belief update.
17. Export the run package.
18. Replay the run from its initial world + inputs.
19. Verify normalized final world and event sequence match.

The fixture may add an alternate logistics edge solely so rerouting can be tested.

---

# 49. Resource Accounting Acceptance Tests

Required tests:

## Conservation
At every test checkpoint:

```text
created = stockpiles + in_transit + consumed + destroyed
```

## No double spending
Given 500 on hand:

- reserve 300 succeeds;
- reserve another 250 fails;
- reserve another 200 succeeds.

## Cancellation before dispatch
A cancelled PLANNED shipment releases its reservation and changes no physical stock.

## No cancellation teleport
An IN_TRANSIT shipment cannot be cancelled back into origin stock.

## Arrival exactly once
Calling update after arrival cannot add cargo twice.

## Destroy exactly once
Destroyed shipment cargo cannot later arrive.

---

# 50. Logistics Acceptance Tests

Required tests:

- deterministic shortest route;
- deterministic equal-cost tie-break;
- no-route failure;
- disabled edge excluded from new routing;
- shipment blocked if an edge in its active route becomes disabled;
- reroute from current location, not original origin;
- destination receives correct amount;
- shipment cannot use disabled location;
- origin and destination cannot be same stockpile;
- zero/negative shipment quantity rejected.

---

# 51. Command Hierarchy Acceptance Tests

Required tests:

- valid parent/child creation;
- multiple siblings;
- attempt to parent command beneath its descendant fails with `HIERARCHY_CYCLE`;
- reparent event recorded;
- direct authority test succeeds;
- unauthorized stockpile dispatch fails;
- superior does not automatically receive direct stockpile mutation authority;
- hierarchy does not imply automatic information sharing.

---

# 52. Communication Acceptance Tests

Required tests:

- one-edge message delivery;
- multi-edge delivery;
- deterministic route selection;
- no-route failure;
- recipient cannot inspect in-transit message as delivered knowledge;
- disabling required edge before due delivery causes failure;
- failed message does not update beliefs;
- delivered message remains in history;
- sender and recipient are not required to be parent/child if a communication path exists.

---

# 53. Belief-State Acceptance Tests

Required tests:

- ingestion stores provenance;
- global truth does not automatically create a belief;
- newest `observed_at` wins current-belief query;
- tie breaks use `received_at`;
- expiration excludes old record;
- conflicting reports remain separately inspectable;
- superior command may hold stale belief while subordinate has newer local truth;
- command view cannot query unrestricted global truth.

---

# 54. Determinism Acceptance Tests

Required:

1. Run fixture twice with same seed and inputs.
2. Compare:
   - final world;
   - resource ledger;
   - shipment states;
   - message states;
   - belief stores;
   - normalized event stream.
3. They must match.

Also run with a different seed.

Because 2A contains no stochastic policy, the result may still be identical. This is acceptable.

The purpose is to verify that seed ownership exists before randomness is introduced.

---

# 55. Performance Expectations

2A is not a scale benchmark yet.

However, avoid algorithms that obviously require scanning every entity for ordinary operations.

At minimum:

- entity lookup by ID should be dictionary/map based;
- stockpile access by location/owner should be indexed;
- outgoing logistics/communication edges should be indexed by source;
- event append should be O(1) amortized;
- belief lookup should not scan all commands.

Do not prematurely optimize beyond measured need.

---

# 56. Developer Debug View

Provide a minimal developer-only inspector or textual debug view showing:

```text
simulation time
locations
stockpile quantities / reservations
shipments + states
command hierarchy
communication edges
message states
belief records
recent events
```

This is not player UI.

It may be a simple Godot Control scene, terminal output, or both.

The headless tests remain authoritative.

---

# 57. Data-Driven Configuration

Static world definitions should be loadable from data rather than hardcoded in scene scripts.

Acceptable approaches:

- Godot Resources;
- JSON;
- `.tres` data assets.

The developer may choose.

The following must be data-configurable:

- locations;
- commands;
- hierarchy links;
- stockpile ownership;
- initial stock;
- logistics edges;
- communication edges;
- resource definitions.

---

# 58. Schema Versioning

Exported events and snapshots must include:

```text
schema_version
```

2A starts at:

```text
"2A.1"
```

If fields later change incompatibly, bump schema version.

Do not silently reinterpret old diagnostic packages.

---

# 59. Test/Production Separation

Debug fixtures, privileged resource creation, forced edge failure, and direct information injection must be isolated from future production gameplay.

Recommended:

```text
res://tests/
res://debug/
```

Production simulation services may expose validated APIs used by tests, but test-only bypasses must not accidentally become normal game actions.

---

# 60. What 2A Must Make Easy Later

The architecture must allow later implementation of these without rewriting the kernel:

## Multiple resource types
Add fuel, manpower, spare parts, etc. as `ResourceType` data.

## Road/rail differences
Add transport modes and route properties.

## Forward Operating Bases
Add Location entities plus future AI construction policy.

## Communication modes
Add messenger/mail/telephone/radio transport behavior.

## Communication failure
Disable edges or add reliability policy later.

## Command personality
Decision system reads traits later; hierarchy stays unchanged.

## Resource requests
Future need objects reference resource types/commands without replacing reservations.

## Command collaboration
Future messages/negotiation use existing communication graph.

## Player high-command interaction
Player modifies strategic allocations/constraints through validated inputs.

## Battlefield simulation
Combat systems consume/produce strategic events without owning the logistics ledger.

---

# 61. What 2A Must NOT Pre-Solve

Do not build speculative abstractions for:

- exact WWII rank structures;
- historical radio ranges;
- realistic truck tonnage;
- ammunition caliber compatibility;
- officer psychology;
- negotiation algorithms;
- battlefield intelligence estimation;
- resource-priority utility functions;
- deck balance;
- card recipes.

Provide clean extension points only where 2A already requires the concept.

---

# 62. Completion Gate

2A is complete only when all of the following are true:

## Architecture
- new Godot project exists;
- strategic state is independent from tactical scene nodes;
- service boundaries are enforced;
- direct cross-system mutation is not used for persistent strategic state.

## Resources
- generic resource types work;
- AMMUNITION is implemented;
- stock/reservation/shipment accounting is conservative and tested.

## Logistics
- deterministic routing works;
- shipment travel takes simulation time;
- blocked/rerouted/destroyed shipment behavior works.

## Command hierarchy
- generic hierarchy works;
- cycles are rejected;
- authority is enforced separately from hierarchy.

## Communication
- messages require communication routes;
- messages have latency;
- disabled routes can cause failure;
- there is no automatic telepathy.

## Beliefs
- each command has private information state;
- delivered information has provenance and time;
- global state does not automatically become command knowledge.

## Logging
- all authoritative mutations create events;
- causation/correlation is recorded;
- run package export works.

## Replay
- demonstration run replays to the same normalized final state/event sequence.

## Tests
- all acceptance tests in this package pass.

---

# 63. Required Developer Handoff

When 2A is complete, provide:

```text
1. Source commit/hash.
2. Godot version.
3. Architecture summary.
4. Directory/module map.
5. Event schema documentation.
6. Snapshot/export schema documentation.
7. Automated test results.
8. Demonstration-run exported data package.
9. Replay result.
10. Known limitations or deliberate deviations from this specification.
```

If any requirement had to change during implementation, document:

```text
original requirement
implemented behavior
reason for deviation
consequence for later phases
```

Do not silently substitute a simpler behavior.

---

# 64. Developer Decision Latitude

The developer may choose:

- exact class/file names;
- Node vs RefCounted service implementation;
- JSON vs Godot Resource static definitions;
- internal cache structures;
- test framework organization;
- UI layout for the developer inspector.

The developer may not silently change:

- resource conservation semantics;
- event/history requirements;
- information privacy;
- authority boundaries;
- shipment physicality;
- communication latency;
- deterministic replay expectations;
- required acceptance behavior.

---

# 65. Summary

Prototype Generation 2A is a **simulation kernel**, not a gameplay slice.

It must establish the reliable primitives on which the new Trencho can later build:

```text
STATE
RESOURCES
LOCATIONS
LOGISTICS
COMMAND AUTHORITY
COMMUNICATION
PRIVATE INFORMATION
EVENT HISTORY
REPLAY
DIAGNOSTIC EXPORT
```

The most important architectural rule is:

> **Systems communicate through validated interfaces, events, messages, and state ownership. A future subsystem should be removable or replaceable without requiring unrelated systems to know its implementation details.**

If 2A succeeds, 2B can begin adding autonomous command behavior without changing what a resource, shipment, command, message, belief, or event fundamentally is.
