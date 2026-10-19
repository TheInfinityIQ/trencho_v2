# Architecture and implementation decisions

## Ownership and mutation

The kernel uses RefCounted services and JSON-compatible entity records. It has no strategic scene nodes, Autoloads, tactical entities, engine physics, or render-delta dependency. A minimal Control scene is developer tooling only.

External actions enter `Simulation.execute(command, privileged)`. Services validate, build changes in detached copies, and commit explicit events. `WorldState.apply_event` is the sole persistent projection writer; `EventStore` keeps ordered copies. Failed operations leave resource/reservation/shipment projections unchanged. An `INPUT_RECEIVED` event records each JSON-compatible attempted command and advances the input sequence, including failed attempts. Inputs that cannot be represented safely in JSON are rejected before they can change state or history.

Atomic changes appear together in a single event's `payload.changes`. Subsequent semantic events in the same operation can have no changes and point back through causation. For example, dispatch atomically retires the claim, subtracts on-hand/reserved stock, and activates cargo in `RESERVATION_FULFILLED`; `SHIPMENT_DISPATCHED` follows. This avoids an event prefix with missing or duplicated resources. The acceptance suite independently audits all event prefixes.

GDScript does not provide a security sandbox for private members. Services and developer tooling are trusted kernel collaborators; underscore fields and `commit/apply_event` are internal interfaces. Future command decision modules receive only a `CommandView`, never the coordinator, services, or WorldState.

## Queries and indexes

All entity queries return deep copies. CommandView is a detached filtered snapshot with no WorldState reference; callers obtain a fresh view when they need current knowledge. It exposes directly controlled locations/stockpiles, own command identity/authority, delivered inbox messages, owned information records and explicit public facts. It does not expose outgoing payloads or other commands' local state. Callers cannot ask it for arbitrary world entities.

Indexes are updated per affected entity: source edges, stockpiles by owner/location, information by owner and subject/fact, recipient inboxes, reservation-to-shipment ownership, and active shipments/messages. Entity lookup is map-based. Tick processing visits active transit entities in ascending stable ID order; completed entities remain in history without being updated. Routing uses a deterministic small-graph Dijkstra implementation; it is not a scale benchmark.

## Time, order and determinism

* Default tick duration is 0.1 seconds. Supported time resolution is one integer microsecond. Definition durations are quantized once, and travel arithmetic uses integer microseconds.
* Authoritative time is `tick_index * tick_duration`, never accumulated render delta.
* `advance(n)` commits a clock event, then updates shipments by ID, then messages by ID on each tick.
* External inputs at a tick occur after that tick's updates, in recorded append order. Inputs at tick zero follow initialization. To interrupt a message before delivery, disable its edge at an earlier tick than its due tick.
* Positive communication latency is rounded up to a delivery tick. A zero-latency message is delivered at send time. The same send/delivery ordering repeats during replay.
* Directed route costs are integer-microsecond sums. Equal-cost routes compare edge-ID sequences lexicographically, with the shorter prefix first. Cycles are settled once; routes do not repeat a node.
* Definition IDs cannot contain `:`. Runtime IDs use typed namespaces derived from the next event sequence, independent of names, array indexes, node paths and memory addresses.
* The coordinator owns a seeded RNG and records its state as a decimal string, avoiding JSON integer precision loss. No stochastic choice is implemented or made. A future random operation must introduce a logged event that changes recorded RNG state.
* Replay requires the recorded project/schema and the same reported engine version string. The observed executable's build hash is recorded in the handoff; the package loader does not verify executable file hashes. It compares semantic normalized values, ignoring dictionary order, integral number representation and diagnostic run ID. It preserves all list/event order and all other content.

## Resource lifecycle

Reservations claim already-present physical stock. Active claims count toward reserved totals, never toward additional physical supply. Standalone claims may be released, invalidated or actually consumed. Actual reservation consumption emits `RESERVATION_CONSUMED` and `RESOURCE_CONSUMED`, removes stock, and increases the consumed ledger.

A shipment owns its reservation, so callers cannot independently consume/release that claim. Planning creates the reservation and shipment atomically. Cancellation before dispatch releases the claim. Dispatch changes its state to `FULFILLED`, transfers stock into cargo and leaves consumed totals unchanged. In-transit/blocked cargo cannot be cancelled; rerouting or explicit privileged destruction is required.

Blocked cargo stays at the last reached location and retains partial progress diagnostically. An explicit successful reroute abandons that progress and starts its replacement route from the last reached location. Failed route lookup keeps cargo blocked. A disabled destination blocks arrival. Repairs require an explicit reroute to resume a blocked shipment; simply enabling an edge does not silently restart it. Rerouting to a stockpile at the current location arrives on the next update with an empty route.

The ledger is `created = stockpiles + in_transit + consumed + destroyed`. Only IN_TRANSIT/BLOCKED shipments count as cargo; PLANNED stock remains at origin. Initial stock loaded from data is part of the initial baseline and its created total. The demo starts with empty stock and explicitly creates all 1,000 units through a privileged logged input.

## Communication and information

Hierarchy, direct dispatch authority, logistics and communication are independent relationships. A superior acquires neither stock mutation authority nor subordinate knowledge merely through ancestry. Both stockpile and containing location must be enabled for new resource/dispatch operations.

Messages freeze a directed route when sent. Delivery checks that route; there is no automatic alternate path after send. Disabled command endpoints/intermediate commands also cause failure. A broken route may still be used by later sends only if a different enabled path can be found.

REPORT payloads may contain a `facts` array. Facts are validated before sending and frozen in the message. Successful delivery explicitly invokes information ingestion with actual sender, message and delivery-event provenance. Other message types are stored/delivered without gameplay interpretation. A message can contain an ordinary REPORT payload without facts; it then creates no belief. Failed reports never ingest.

Closeout explicitly carries the originating operation correlation through send, delivery and ingestion while preserving immediate causal parents. Message failures include structured unavailable-edge diagnostics and references to disabling events. The event shape remains additive under schema 2A.1; project version 0.1.1 distinguishes its corrected normalized event output from earlier runs.

Current belief excludes records not yet received/observed and those expired at or before query time. It chooses greatest observation time, greatest receipt time, then ascending stable record ID. Confidence is retained but not used to blend or override that rule. Conflicting and expired records stay in history.

## Deliberate boundaries and limitations

* This is a developer simulation fixture, with no player gameplay, planning, resource negotiation, combat, tactical movement, officers, or production economy.
* The kernel accepts data definitions at run start; runtime creation/removal of new locations, stockpiles, resource types and edges is left for the future validated operations that require it. Existing entities can be enabled/disabled; commands can be reparented.
* Replay starts at the exported initial tick-zero world. Loading a final snapshot as an arbitrary mid-run continuation is not implemented or claimed. Snapshots include clock and RNG state for inspection and a future explicit continuation path.
* JSON values must be finite and numerical inputs must remain within the exactly representable JSON integer range. Default ammunition uses integral quantities; a synthetic fractional resource is instantiated only by an acceptance fixture. Resource audit uses an absolute 1e-6 tolerance for fractional arithmetic; integer ammunition checks are exact in the tested range.
* Export writes the five required files and reports file errors; it does not implement crash-atomic directory publication. A partial package is rejected by replay. Export paths are developer-provided; no player-facing storage or save-game compatibility is claimed.
* Dictionary projection updates duplicate changed entity records. No performance or target-scale claim has been made. Only the specified fixture and test workloads were exercised.
* Semantic-event versus high-frequency-trace separation is a non-blocking 2B carry-forward item. Before scale substantially increases, review separate channels/files, trace controls and retention policies while preserving the chosen reconstruction/replay contract. No speculative logging redesign is part of 2A closeout.
* Debug export defaults to the writable source project's `artifacts/` directory. Packaged executable export and target-platform release validation are outside the 2A gate and were not performed.

## Authoritative API references checked

Godot 4.7 documentation was checked while implementing, and behavior was executed on 4.7.2 stable:

* [Command-line tools and headless scripts](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
* [JSON parsing/stringification](https://docs.godotengine.org/en/4.7/classes/class_json.html)
* [Seeded RandomNumberGenerator and state](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html)
* [User/project paths and portable editor data](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html)

## Step 103 extension

FrontDefinition and FrontService implement abstract front state, deterministic fixed-point demand and local sampling. TICK_ADVANCED carries prepared front accumulator patches; logistics/messages resolve before front consumption/interval finalization. ResourceService retains stock ownership. InformationService retains belief ownership. The front state never enters CommandView. See FRONTS_103.md for integer units, event sequence, tick precision, schema change and review boundary.

## Step 104 local decision boundary

LocalCommandPlanner consumes only a detached CommandView and complete observation envelope. DecisionPolicy104 isolates integer prototype scores/eligibility/ties. DecisionJournal coordinates event projections and asks FrontService/AuthorityService to validate the chosen posture change. It attaches descriptive observed outcomes before the next decision. Optional command configuration activates only the responsible LOCAL/front pair. See DECISIONS_104.md.

## Step105 resolution boundary

ResourceNeedPolicy reads complete CommandView beliefs and own authority-scoped resources. ResourceResolutionService coordinates durable needs, one peer conversation at a time and scoped incoming knowledge. Resource/Logistics services retain physical ownership; the narrow existing-offer-claim dispatch path avoids re-reservation. Known arrival/failure notification runs after logistics and before front observation; protocol inbox processing runs after all front samples, preventing a half-ingested donor batch. Superior learns reported snapshots only after delivered escalation and has no allocation policy. See RESOURCE_RESOLUTION_105.md.
