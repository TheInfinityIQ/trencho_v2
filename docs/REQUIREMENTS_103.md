2A is accepted. The tag and commit you reported satisfy the closeout gate, so **do not modify or retag `prototype-gen2-2A-accepted`**. Begin 2B from that accepted revision.

The next authorized development unit is **Package/Step 103** below. This is intentionally only the first part of 2B. **Do not begin peer collaboration, escalation, autonomous resource arbitration, or higher-command planning after finishing this task. Stop and report back to me.**

# 103 — 2B Abstract Front & Local Observation Foundation

## Intended outcome

Create the smallest deterministic abstract battlefield layer that gives future commanders a real situation to reason about.

At the end of 103, the simulation must be able to represent:

```text
LOCAL COMMAND
     ↓
ABSTRACT FRONT
     ↓
AMMUNITION CONSUMPTION
     ↓
CHANGING LOCAL SUPPLY CONDITION
     ↓
LOCAL OBSERVATIONS / BELIEFS
```

There is **no autonomous decision-making in 103**.

The purpose is to establish the world state that 104's commander AI will observe and reason about without forcing 104 to invent battlefield state, supply consumption, or information semantics simultaneously.

---

# 1. Preserve the accepted 2A boundary

Start from:

```text
tag:
prototype-gen2-2A-accepted

commit:
213f2faf98d7ac2a3ad11d25afa698578a69b161
```

Create normal post-2A development history from that revision.

Do not rewrite the tag.

Do not change existing 2A semantics unless a 103 requirement exposes an actual defect. If that happens, stop and report the issue rather than casually changing the kernel contract.

---

# 2. New entity: `AbstractFront`

Introduce a persistent strategic-simulation entity representing an active combat frontage without individual soldiers.

The exact class/file name may differ, but the data contract must contain equivalents of:

```text
id
display_name
location_id
responsible_command_id
supply_stockpile_id

friendly_strength
enemy_pressure

posture
base_ammo_demand_per_second

ammo_demand_accumulator
enabled

metadata
```

## Field semantics

### `friendly_strength`

Prototype-scale numerical representation of friendly combat presence.

Use:

```text
0.0 to 100.0
```

for 103.

This is **not** a final combat-stat scale.

Reject values outside that range rather than silently accepting invalid state.

### `enemy_pressure`

Prototype-scale representation of the intensity of hostile pressure currently affecting this front.

Use:

```text
0.0 to 100.0
```

for 103.

This is objective world state.

It does **not** imply that every command automatically knows the true value.

### `posture`

Implement the schema now with these values:

```text
HOLD
PRESS
REDUCE_ACTIVITY
WITHDRAW
```

For 103, all fixture fronts begin as:

```text
HOLD
```

Do not implement autonomous posture selection yet.

Tests/debug inputs may explicitly change posture so its supply behavior can be validated.

### `base_ammo_demand_per_second`

Non-negative floating-point value defining ammunition demand under full pressure while in `HOLD`.

This exists to create a deterministic supply problem for the prototype.

It is data-configurable and not final balance.

### `ammo_demand_accumulator`

Persistent fractional demand accumulator.

It must be included in authoritative state/snapshots because it affects deterministic future consumption.

---

# 3. Posture ammunition multipliers

Use these **prototype-only** values:

```text
HOLD             1.00
PRESS            1.50
REDUCE_ACTIVITY  0.50
WITHDRAW         0.25
```

These numbers are not game-balance commitments.

Their purpose is to ensure future command decisions can have materially different logistical consequences.

---

# 4. Ammunition-demand calculation

A front's instantaneous desired ammunition rate is:

```text
base_ammo_demand_per_second
× pressure_factor
× posture_multiplier
```

where:

```text
pressure_factor = enemy_pressure / 100.0
```

Example:

```text
base demand = 8 ammo/sec
enemy pressure = 50

HOLD:
8 × 0.50 × 1.00
= 4 ammo/sec
```

If enemy pressure is zero, combat ammunition demand is zero.

Do not create an arbitrary minimum burn.

---

# 5. Fractional consumption

`AMMUNITION` remains integer-valued.

Every simulation tick:

```text
ammo_demand_accumulator
+= desired_ammo_rate × tick_duration
```

Whenever:

```text
ammo_demand_accumulator >= 1.0
```

determine:

```text
integer_demand = floor(ammo_demand_accumulator)
```

Attempt to consume that quantity.

Then remove the **attempted integer demand** from the accumulator, even if insufficient ammunition was available.

Example:

```text
accumulator = 3.7
integer demand = 3
available ammo = 1

actual consumed = 1
shortage = 2
remaining accumulator = 0.7
```

The missing two ammunition units represent unmet demand; they must not accumulate forever as deferred ammunition debt.

---

# 6. Actual ammunition consumption

The front may **not directly mutate its stockpile**.

Consumption must pass through the existing 2A resource service.

Use the existing validated resource-consumption operation, extended only as necessary to identify:

```text
actor/source = front simulation / front ID
reason_code = FRONT_COMBAT_CONSUMPTION
```

Actual consumption must:

- reduce physical stock;
- increment the resource ledger's consumed total;
- emit the existing `RESOURCE_CONSUMED` event;
- preserve conservation.

Combat consumption may use only **available**, non-reserved ammunition.

Existing reservations must remain protected.

---

# 7. Shortage behavior

If:

```text
integer_demand > available ammunition
```

consume:

```text
min(integer_demand, available)
```

and record:

```text
shortage_quantity
=
integer_demand - actually_consumed
```

Stock may never become negative.

Do not invent borrowing, emergency supply, automatic transfers, or request generation in 103.

A shortage is simply a world condition that future command AI will need to react to.

---

# 8. Front supply metrics

The simulation must expose deterministic derived front metrics.

At minimum:

```text
current_ammo_on_hand
current_available_ammo
current_desired_ammo_rate
ammo_coverage_seconds
last_interval_demand
last_interval_consumed
last_interval_shortage
```

## Ammo coverage

If:

```text
current_desired_ammo_rate > 0
```

then:

```text
ammo_coverage_seconds
=
current_available_ammo / current_desired_ammo_rate
```

If desired rate is zero:

```text
ammo_coverage_seconds = null
```

or an explicitly documented equivalent representing no active burn.

Do **not** use infinity in exported JSON.

Coverage is based only on ammunition physically available at that front's stockpile.

Do not include unknown future shipments in this metric.

Incoming supply will become part of commander reasoning later when the command plausibly knows about it.

---

# 9. Observation model

A front's objective state must not automatically become global command knowledge.

Create a front-observation mechanism that ingests information into the **responsible local command's existing 2A belief/information system**.

Use the existing `InformationService`.

Do not create a second information architecture.

---

# 10. Observation cadence

For 103 use:

```text
observation_interval = 1.0 simulation second
```

This is a prototype sampling interval, not simulated radio latency.

The responsible local command is considered close enough to its directly controlled front to observe these local conditions without going through the strategic communication network.

Each observation must record the actual observation time.

---

# 11. Required observed facts

At each observation interval, create/update information records for the responsible command covering at least:

```text
FRONT_FRIENDLY_STRENGTH
FRONT_ENEMY_PRESSURE
FRONT_POSTURE
FRONT_AMMO_ON_HAND
FRONT_AMMO_AVAILABLE
FRONT_AMMO_DEMAND_RATE
FRONT_AMMO_COVERAGE_SECONDS
FRONT_LAST_SHORTAGE
```

Use the existing provenance structure.

Recommended source:

```text
source_system = FRONT_OBSERVATION
```

Confidence for these local prototype observations:

```text
1.0
```

This does not establish that all future intelligence will be perfectly accurate.

---

# 12. No information leakage

Only:

```text
responsible_command_id
```

receives these automatic local observations.

Its superior does not.

Its peers do not.

Other friendly commands do not.

The raw world state obviously remains visible to developer tooling and authoritative simulation services.

`CommandView` must continue to prevent an AI-level consumer from bypassing the information system.

This requirement is important enough to have explicit tests.

---

# 13. Front ownership

A front belongs to exactly one responsible command in 103.

Validate:

```text
responsible_command_id exists
location_id exists
supply_stockpile_id exists
```

The supply stockpile must be located at either:

- the front's location; or
- another location explicitly associated with the responsible command in the test fixture.

Do not build multi-command front ownership yet.

---

# 14. Front-state mutation

Provide validated input/service operations for at least:

```text
create_front
set_front_enemy_pressure
set_front_friendly_strength
set_front_posture
set_front_enabled
```

Tests/debug fixtures must use these operations.

Do not directly modify runtime fields from tests.

These changes must participate in the existing external-input/event architecture where appropriate.

---

# 15. New semantic events

Add explicit semantic event types equivalent to:

```text
FRONT_CREATED
FRONT_ENABLED_CHANGED
FRONT_ENEMY_PRESSURE_CHANGED
FRONT_FRIENDLY_STRENGTH_CHANGED
FRONT_POSTURE_CHANGED
FRONT_AMMO_SHORTAGE
```

Use the existing event base fields.

`FRONT_AMMO_SHORTAGE` should be emitted when an actual integer demand cannot be fully satisfied.

Payload should include at least:

```text
front_id
resource_type_id
demanded
consumed
shortage
available_before_consumption
```

Do not emit `FRONT_AMMO_SHORTAGE` when shortage is zero.

`RESOURCE_CONSUMED` remains the authoritative resource-accounting event.

The shortage event explains the operational consequence; it must not alter the resource ledger itself.

---

# 16. Avoid unnecessary high-frequency semantic events

Do not add a durable semantic event for every fractional accumulator update.

Do not emit:

```text
FRONT_AMMO_ACCUMULATOR_CHANGED
```

every tick.

The accumulator belongs in authoritative state/snapshots for replay.

The event stream should record meaningful transitions and actual resource consumption/shortages rather than deterministic arithmetic noise.

This is consistent with the trace-separation issue deferred from 2A.

---

# 17. Snapshot/export/replay

Extend 2A world serialization so fronts and any required front-simulation state are present in:

```text
initial_world.json
final_world.json
```

Replay must reproduce:

- front state;
- demand accumulator;
- ammunition totals;
- shortages;
- observations;
- resulting event sequence.

Do not create a separate replay mechanism.

Extend the existing one.

---

# 18. 103 demonstration fixture

Extend or create a dedicated 2B fixture with:

```text
ARMY_COMMAND
   |
LOCAL_A
   |
FRONT_A
```

Required starting conditions:

```text
FRONT_A posture = HOLD
FRONT_A friendly_strength = 60
FRONT_A enemy_pressure = 50

FRONT_A base_ammo_demand_per_second = 8

front supply stockpile ammo = 10
```

Therefore initial desired rate is:

```text
8 × 0.5 × 1.0
= 4 ammo/sec
```

---

# 19. Required demonstration behavior

Run the fixture long enough to show:

### First second

Approximately:

```text
demand = 4
consumed = 4
remaining ammo = 6
```

### Second second

```text
demand = 4
consumed = 4
remaining ammo = 2
```

### Third second

```text
demand = 4
consumed = 2
shortage = 2
remaining ammo = 0
```

The exact tick index of integer-consumption events may reflect fixed-step accumulation, but normalized simulation behavior must equal the above.

Then:

1. raise `enemy_pressure` to `100`;
2. add ammunition through the existing resource system;
3. explicitly change posture to `REDUCE_ACTIVITY`;
4. verify the desired burn rate changes according to the formula;
5. verify local observations update on the next observation interval;
6. verify `ARMY_COMMAND` has **not** automatically learned those front facts.

No messages should be automatically sent upward in 103.

That belongs to later 2B work.

---

# 20. Required acceptance tests

## Front validation

Test:

- invalid command rejected;
- invalid location rejected;
- invalid stockpile rejected;
- friendly strength below 0 rejected;
- friendly strength above 100 rejected;
- enemy pressure below 0 rejected;
- enemy pressure above 100 rejected;
- negative base ammunition demand rejected.

## Consumption

Test:

- zero enemy pressure consumes zero ammunition;
- HOLD multiplier is correct;
- PRESS multiplier is correct;
- REDUCE_ACTIVITY multiplier is correct;
- WITHDRAW multiplier is correct;
- fractional accumulation is deterministic;
- consumption cannot spend reserved stock;
- stock never goes negative;
- shortage equals demand minus consumption;
- consumption enters the existing resource ledger;
- shortage does not count as consumed ammunition.

## Information privacy

Test:

- responsible local command receives observations;
- observations do not exist before the observation time;
- superior command does not receive them automatically;
- peer command does not receive them automatically;
- `CommandView` cannot use the front system as an unrestricted global-truth escape hatch.

## Event behavior

Test:

- front mutations emit appropriate semantic events;
- actual consumption emits `RESOURCE_CONSUMED`;
- unmet integer demand emits `FRONT_AMMO_SHORTAGE`;
- no shortage event when demand is fully satisfied.

## Replay

Run the fixture twice/fresh-process as appropriate and verify:

- normalized final world matches;
- ordered semantic event stream matches;
- front accumulator matches;
- resource ledger matches;
- information records match.

---

# 21. Explicit non-goals for 103

Do **not** implement:

- autonomous command AI;
- candidate-plan generation;
- decision scoring;
- decision journal;
- automatic supply requests;
- peer resource negotiation;
- lateral transfers initiated by AI;
- escalation to superior command;
- superior arbitration;
- strategic player interaction;
- cards;
- economy gameplay;
- personalities;
- officer traits;
- combat units;
- soldiers;
- weapons;
- vehicles;
- territory capture;
- autonomous attacks;
- autonomous withdrawals;
- morale;
- command difficulty;
- random decision-making;
- fog-of-war estimation;
- inaccurate observations.

103 is deliberately a **world-state and observation foundation**.

---

# 22. Architectural intent

The important dependency direction is:

```text
AbstractFront
    ↓
uses ResourceService for real consumption
    ↓
objective world state changes

FrontObservationService
    ↓
reads authorized front state
    ↓
uses InformationService
    ↓
responsible command receives beliefs
```

Future command AI will then operate:

```text
Command AI
    ↓
CommandView / beliefs
```

It must **not** become:

```text
Command AI
    ↓
AbstractFront internals / unrestricted WorldState
```

That boundary is the main reason 103 exists as a separate development step.

---

# 23. Developer latitude

You may choose:

- exact class names;
- exact directory structure;
- node/service implementation;
- whether front definitions use Resources or other existing project data format;
- internal indexing;
- how derived metrics are cached.

Do not materially change:

- the demand formula;
- the four prototype posture multipliers;
- local observation cadence;
- information privacy;
- resource-consumption semantics;
- shortage semantics;
- replay requirements.

If an existing 2A architectural constraint makes one of these requirements problematic, **stop and ask me before replacing it with a workaround**.

---

# 24. Completion report

When 103 is complete, place the completed-step report in:

`C:\Users\dawso\OneDrive\Desktop\trencho`

using the project's existing numbering convention and **103 as the next step/package number**.

The report should contain at minimum:

```text
103 completion status

commit SHA
Godot version
schema/project version if changed

files/modules added or changed

acceptance suite result
assertion count
failure count

103-specific regression result

demonstration final state

resource conservation result

replay result
event count / final tick

information privacy tests

known limitations
deliberate deviations
```

If you maintain separate requirement/completion files, preserve the existing local naming convention rather than inventing a new one.

---

# 25. Stop condition

Once every requirement above is implemented and the relevant tests pass:

**STOP.**

Do not begin the next 2B task.

Do not implement commander reasoning because the next step appears obvious.

Do not add automatic requests, collaboration, escalation, or planning.

Return the 103 completion evidence to me. I will review it and then authorize the next bounded step, which is expected to introduce the first autonomous local-command decision cycle and decision journal on top of this front/observation foundation.
