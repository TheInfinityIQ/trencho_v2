Yes. **Use the separate append-only player-observation event stream.** That is the preferred 109 architecture.

Do **not** migrate the accepted authoritative event/ID system merely to insert presentation observations.

The inertness requirement should be stronger than normalization:

> With the same gameplay world, gameplay inputs and seed, enabling player observation must leave the accepted authoritative simulation event sequence and all authoritative entity IDs **byte-for-byte unchanged**.

## Approved 109 event split

Keep the existing stream untouched:

```text
AUTHORITATIVE WORLD STREAM
events.jsonl

owns:
world mutations
command decisions
needs
messages
shipments
resources
authoritative entity IDs
existing causation/correlation
```

Add a separate persisted stream, naming flexible, e.g.:

```text
player_observation_events.jsonl
```

Conceptually:

```text
PLAYER OBSERVATION STREAM

player_observation_event_id
player_observation_id
area_id
observed_at
observation_type
qualitative_value

source_authoritative_event_id
source_entity_id or null

previous_observation_event_id or null
metadata
```

Use a **separate deterministic counter/namespace** for both observation records and observation semantic events.

For example:

```text
player_observation:0000000001
player_observation_event:0000000001
```

Exact formatting may follow repository conventions.

## Cross-stream causation

Do not pretend the two streams share one event-ID namespace.

For observation events caused by gameplay events, record explicitly:

```text
source_authoritative_event_id
```

That is the cross-stream causal link.

If you want causal ancestry internal to the observation stream as well, use a separate field such as:

```text
previous_observation_event_id
```

or equivalent.

Do not overload an existing same-stream `causation_event_id` contract if doing so would make the event model ambiguous.

The reconstructable relationship should be:

```text
authoritative event
        ↓ source_authoritative_event_id
player observation event
        ↓
PlayerObserverView
```

## Deterministic fan-out

One authoritative event may produce multiple player observations.

Their order must be deterministic.

Use a canonical ordering such as:

```text
area_id ascending
→ observation_type canonical enum order
→ source_entity_id ascending
```

or another explicitly documented stable ordering.

No dictionary/hash iteration order may determine emitted observation IDs.

## Initial observations

For the initial qualitative snapshot, use:

```text
source_authoritative_event_id = RUN_STARTED event
```

or the repository's equivalent authoritative initialization/root event.

Then emit initial observations in deterministic order:

```text
StrategicArea ID ascending
→ observation type canonical order
```

This is sufficient provenance for 109. Do not create fake world mutations merely to provide observation causation.

## StrategicArea persistence

Treat `StrategicArea` in 109 as **persisted observation/interaction configuration**, not as a gameplay-mutating authoritative world entity.

It must still be:

- exported;
- reconstructable;
- deterministically validated;
- available after fresh-process replay;
- stable enough for later 110 prompts to reference by `area_id`.

But merely configuring StrategicAreas must not renumber:

```text
needs
messages
decisions
shipments
resource events
```

Later, when a player submits an actual gameplay-affecting prompt against an `area_id`, **that prompt** will belong in the authoritative input/event path as appropriate. The area definition itself does not need to perturb 2B sequencing.

## Export/package contract

109 run packages should now contain, conceptually:

```text
initial state / observer configuration
events.jsonl                         # accepted authoritative stream
player_observation_events.jsonl      # new 2C observation stream
final authoritative state
final player-observer projection
inputs.jsonl
manifest
```

Names may follow repository conventions.

The manifest should identify both streams and their schema/version/hash information where the existing package format supports that.

## Replay acceptance

Fresh-process replay must independently prove both:

### Authoritative replay

Existing behavior remains strict:

```text
same ordered authoritative events
same authoritative IDs
same final authoritative state
same 2B projections
```

### Observation replay

From:

```text
StrategicArea configuration
+
authoritative event stream
+
player observation stream
```

reconstruct exactly:

```text
all PlayerObservationRecords
observation event IDs/order
current PlayerObserverView
recent observation history
```

No tolerance.

## Scenario D inertness is therefore strengthened

For the observer-disabled versus observer-enabled comparison, require:

```text
authoritative events.jsonl
= byte-identical

authoritative entity IDs
= identical

AI decisions
= identical

needs/messages/shipments
= identical

resource ledger
= identical
```

The enabled run may additionally contain:

```text
StrategicArea configuration
player_observation_events.jsonl
PlayerObserverView
```

Those are excluded only because they do not exist in the disabled run—not because we normalized differences out of the authoritative stream.

This is preferable to accepting renumbered authoritative IDs.

## One constraint

Do not let the separate stream become a hidden second simulation authority.

Observation-stream processing may:

```text
read authoritative events/state
derive qualitative presentation
update PlayerObserverView
```

It may **not**:

```text
mutate WorldState
allocate authoritative IDs
write InformationRecords
trigger planners
dispatch messages
move resources
```

For 109 it is strictly one-way:

```text
WORLD → PLAYER OBSERVATION
```

Approved. Proceed with this separation, preserve the frozen event/ID architecture, and lock the regression around byte-identical authoritative output when observation is enabled versus disabled.
