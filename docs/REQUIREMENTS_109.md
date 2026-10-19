No prior-step defect or additional human decision is blocking us. The frozen 2B baseline is accepted, so you are authorized to begin **109 only**.

## 109 — Player Observation Boundary & Strategic Area Foundation

### 1. Purpose

109 is the first 2C task.

It does **not** add player commands yet.

Its job is to establish one architectural rule before we let the player interact with the war:

> **What the player can observe and what a commander knows are separate systems.**

The player may eventually have broad visual awareness of the battlefield while commanders remain limited by their own observations, reports and communications.

109 must make that separation concrete and replayable.

---

### 2. Starting point

Begin from frozen 2B:

```text
prototype-gen2-2B-accepted
→ d7a1bb57fcf6cae581acd1502b9772046869985e
```

Preserve:

```text
prototype-gen2-2A-accepted
→ 213f2faf98d7ac2a3ad11d25afa698578a69b161
```

Expected next project/schema:

```text
Project 0.3.0
Schema 2C.1
```

Names may vary only if an existing versioning convention requires it.

---

### 3. Governing design rule

Create three conceptually independent layers:

```text
OBJECTIVE WORLD STATE
        │
        ├────────────→ PLAYER OBSERVATION
        │
        └────────────→ COMMAND KNOWLEDGE
```

The player observation layer may derive sanitized visual information from authoritative world state.

The command-knowledge layer remains exactly constrained by the accepted InformationService / CommandView architecture.

Absolutely forbidden:

```text
PlayerObservationView
→ LocalCommandPlanner

PlayerObservationView
→ Operational arbitration

PlayerObservationView
→ Command InformationService
```

A player seeing something never causes a commander to know it.

---

### 4. Why this exists

The intended player experience is provisionally:

> **visual omniscience without complete informational omniscience**

Example:

The player may visibly notice a supply convoy arrive at an HQ.

The player does **not** automatically receive:

```text
exact cargo quantity
exact remaining HQ ammunition
every ammunition subtype
private command reasoning
```

Those more precise facts may later require reports, inquiry, reconnaissance or analysis.

109 only establishes the observation boundary.

---

## 5. StrategicArea

Add a stable logical target for future player attention/questions.

Minimum equivalent:

```text
StrategicArea
    id
    display_name
    location_ids[]
    front_id or null
    enabled
    metadata
```

Rules:

- stable ID;
- at least one valid location;
- optional associated front;
- all referenced entities must exist;
- enabled areas only participate in observation;
- for 109, one location may belong to only one enabled StrategicArea;
- an area may represent a front or a non-front location such as HQ.

Do not add battlefield coordinates yet.

Future player prompts will target `area_id`, not arbitrary raw WorldState entities.

---

## 6. Activation / regression isolation

Player observation is enabled only when StrategicAreas are configured.

Existing accepted 2A/2B fixtures with no StrategicAreas must preserve their existing behavior and authoritative event sequences except for unavoidable version metadata.

Do not retroactively generate player-observation events for every old fixture.

---

## 7. PlayerObservationRecord

Create an append-only/reconstructable observation record or equivalent.

Minimum internal fields:

```text
observation_id
area_id
observed_at

observation_type
qualitative_value

source_event_id
source_entity_id or null

metadata
```

`source_event_id` is for causal/audit reconstruction.

The normal player-facing view must not expose internal IDs merely because the internal record stores them.

---

## 8. PlayerObserverView

Create a detached read-only player-facing view/projection.

It should support at minimum:

```text
current observation state by StrategicArea
recent qualitative observation history
```

It must not expose unrestricted `WorldState`.

It is a presentation boundary analogous in spirit to `CommandView`, but **not a command belief system**.

---

# 9. Required visible front information

For a StrategicArea associated with a front, expose only these initial qualitative battlefield cues.

### Front behavior

Map authoritative posture to:

```text
HOLD
→ HOLDING

PRESS
→ PRESSING

REDUCE_ACTIVITY
→ REDUCED_ACTIVITY

WITHDRAW
→ WITHDRAWING
```

This is a visual behavioral cue.

Do not expose posture-selection scores or reasons.

---

## 10. Friendly presence band

Derive from authoritative canonical strength:

```text
0–3333 centi
→ LOW

3334–6666
→ MEDIUM

6667–10000
→ HIGH
```

Expose only:

```text
LOW
MEDIUM
HIGH
```

Do not expose the underlying exact strength through PlayerObserverView.

These thresholds are prototype visual categorization, not final gameplay doctrine.

---

## 11. Enemy activity band

Use the same prototype banding over authoritative enemy pressure:

```text
0–3333
→ LOW

3334–6666
→ MEDIUM

6667–10000
→ HIGH
```

Expose only the qualitative band.

Do not expose exact pressure.

This represents what the player can broadly perceive happening in the area, not an intelligence estimate available to commanders.

---

# 12. Visible logistics events

The player should be able to observe physical logistics activity in an enabled StrategicArea.

For 109 support at minimum:

```text
SUPPLY_DEPARTURE_VISIBLE
SUPPLY_ARRIVAL_VISIBLE
SUPPLY_LOSS_VISIBLE
```

A visible logistics observation may expose:

```text
event type
area
time
```

It must **not** expose:

```text
shipment quantity
reservation quantity
exact destination stock
exact source stock
private requester need
```

For 109, do not expose resource subtype through the normal player-facing observation unless required by an existing generic event contract. Prefer simply:

```text
SUPPLY MOVEMENT
```

Future systems may reveal cargo identity through legitimate information.

---

# 13. Physical event semantics

Player-visible logistics observations are triggered by actual physical shipment events.

Examples:

```text
SHIPMENT_DISPATCHED
→ visible departure if source location belongs to an enabled area

SHIPMENT_ARRIVED
→ visible arrival if destination location belongs to an enabled area

SHIPMENT_DESTROYED
→ visible loss if current shipment location/associated area is observable
```

Do not invent a visual shipment event if no underlying physical event occurred.

---

# 14. Observation timing

Player visual observations should update when the underlying observable authoritative event occurs.

They do **not** wait for command communication latency.

This is intentional.

Example:

```text
t = 4.0
physical shipment arrives
```

Player observer may see the arrival at `t=4.0`.

A commander may remain unaware until its own legitimate information path updates.

That asymmetry is required.

---

# 15. Front-state observation timing

Initial player observation state is established deterministically at initialization for configured StrategicAreas.

Subsequent qualitative updates occur when an authoritative front mutation changes the visible qualitative state.

Example:

```text
enemy pressure:
3200 → 3400
```

must produce:

```text
LOW → MEDIUM
```

player observation update.

But:

```text
3400 → 3500
```

remains MEDIUM and need not generate a redundant qualitative-change event.

Same rule for:

```text
friendly presence band
front behavior
```

Avoid meaningless duplicate observation events.

---

# 16. Semantic event

Add an equivalent semantic event such as:

```text
PLAYER_OBSERVATION_RECORDED
```

or narrow event family if cleaner.

Minimum payload:

```text
observation_id
area_id
observation_type
qualitative_value
observed_at
```

Causation must point to the authoritative event that caused the player-visible observation where applicable.

Do not duplicate the authoritative world mutation in the observation event.

---

# 17. Initial observation provenance

Initial area observations must also be reconstructable.

Use either:

- explicit initialization observation events causally tied to the corresponding initialized entities; or
- an equivalent event-reconstructable initialization projection.

Do not rely on a hidden runtime-only cache.

---

# 18. No exact numeric leakage

PlayerObserverView must not expose exact:

```text
friendly_strength
enemy_pressure
front ammo
ammo coverage
interval demand
interval consumed
shortage
shipment quantity
reservation quantity
decision scores
candidate scores
private need quantity
```

109 is intentionally qualitative.

Later inquiries/reports may reveal exact values through legitimate mechanisms.

---

# 19. Command knowledge remains unchanged

Do not change 103/104 local observation semantics.

Do not change:

```text
1.0-second local observation cadence
InformationRecord structure
1.5-second freshness rule
CommandView boundary
```

Do not feed qualitative PlayerObservationRecords back into commands.

---

# 20. Operational Command remains unchanged

106 arbitration continues to reason only from:

```text
delivered subordinate reports
its own authorized stock/infrastructure
accepted command information
```

It must not read PlayerObserverView.

---

# 21. Required Scenario A — player sees qualitative front

Fixture:

```text
friendly strength = 80
enemy pressure = 40
posture = PRESS
```

Player view should show:

```text
friendly presence = HIGH
enemy activity = MEDIUM
front behavior = PRESSING
```

It must not expose:

```text
80
40
exact ammo
planner scores
```

---

# 22. Required Scenario B — qualitative boundary change

Change authoritative enemy pressure through an explicit test fixture input:

```text
32.00 → 34.00
```

Expected:

```text
LOW → MEDIUM
```

player observation update with causation to the authoritative pressure-change event.

Then:

```text
34.00 → 35.00
```

Expected:

- underlying world mutation occurs;
- no redundant enemy-band player observation event.

This scripted mutation is a targeted test input, not an autonomous integrated-run claim.

---

# 23. Required Scenario C — visible arrival without command knowledge

Construct a case where:

1. a physical shipment arrives in an observed area;
2. PlayerObserverView immediately records `SUPPLY_ARRIVAL_VISIBLE`;
3. the relevant command has not yet legitimately learned the corresponding detailed logistics information.

Expected:

```text
player sees physical arrival
≠
commander automatically knows shipment details
```

Prove command beliefs do not gain shipment quantity or cargo details from PlayerObserverView.

---

# 24. Required Scenario D — player observation cannot affect AI

Run equivalent simulations:

```text
Run 1:
StrategicAreas absent / observation disabled

Run 2:
StrategicAreas enabled
```

Keep all command beliefs, resources, inputs and seed otherwise identical.

Ignoring the new player-observation event/projection family, verify identical:

```text
local decisions
candidate scores
posture changes
resource needs
peer coordination
escalation
superior arbitration
physical shipments
resource ledger
```

Player observation must be behaviorally inert to AI.

---

# 25. Required Scenario E — player sees change before commander updates

Create a deterministic timing case where an authoritative visible front property crosses a qualitative band between command observations.

Expected:

```text
authoritative world changes
↓
PlayerObserverView updates immediately
↓
command's prior belief remains unchanged
↓
next legitimate local observation updates command belief
```

This is the key 2C architectural proof.

---

# 26. Replay / reconstruction

Strict fresh-process replay must reproduce:

```text
StrategicAreas
PlayerObservationRecords
current PlayerObserverView
all player-observation semantic events
final authoritative world state
all existing 2B projections
```

No replay tolerance.

---

# 27. Information-isolation tests

Verify:

- player observer does not write InformationRecords;
- LocalCommandPlanner cannot consume player observations;
- Operational arbitration cannot consume player observations;
- enabling observer mode does not change AI outcomes;
- exact world values omitted from the player-facing projection cannot be recovered through accidental generic metadata fields.

That last point matters: do not hide exact data in `metadata` while claiming the view is qualitative.

---

# 28. Resource integrity

Observation code must never mutate:

```text
stock
cargo
reservations
consumption
destruction
```

Existing conservation and active-claim checks remain green.

---

# 29. Determinism

Same:

```text
initial state
inputs
seed
StrategicArea configuration
```

must produce identical observation IDs, records, order and view state.

No random visual inference.

---

# 30. No player input yet

Do **not** add:

```text
LOOK_HERE
DIRECT_ATTENTION
WHAT_HAPPENED_HERE
REQUEST_ASSESSMENT
CONSIDER_RECON
CONSIDER_ATTACK
```

109 only creates the observation/target boundary those later systems will use.

---

# 31. No reconnaissance system yet

Do not implement:

- scouts;
- recon infantry;
- recon vehicles;
- spy planes;
- analysis teams;
- information missions;
- investigation risk;
- reconnaissance combat.

Those are later 2C experiments.

---

# 32. No production/procurement yet

Do not implement:

- factories;
- barracks;
- manpower conversion;
- resource markets;
- military procurement toggles;
- limited procurement quotas;
- deck/cards;
- fabrication trucks.

Those are preserved design direction for 2D and later.

---

# 33. No polished UI requirement

109 remains primarily architectural/headless.

If inexpensive, the existing developer inspector may display:

```text
StrategicArea
current qualitative player observations
recent visible logistics cue
```

Optional only.

Do not delay acceptance for UI.

The first deliberately player-facing greybox interface comes later in 2C.

---

# 34. Administrative GDD housekeeping

This is **not an implementation dependency**.

Place the current Generation 2 GDD files in:

```text
C:\Users\dawso\OneDrive\Desktop\trencho
```

alongside the previous GDD version(s).

Do not overwrite or delete older GDDs.

Current filenames are:

```text
Trencho_Game_Design_Document_Generation_2_v0.1.pdf
Trencho_Game_Design_Document_Generation_2_v0.1.docx
```

You do **not** need to read them or implement from them.

The numbered requirements packets remain implementation authority.

If those files are not available in your environment, simply note that in the 109 report; do not recreate or fabricate them.

---

# 35. Required regression baseline

Run the full accepted suite.

At minimum preserve the accepted:

```text
834 checks / 0 failures
```

as foundation, plus new 109 tests.

Any accepted 2B behavior change requires immediate escalation before proceeding.

---

# 36. 109 acceptance gate

109 is complete only when:

### Strategic targeting
- stable StrategicAreas exist;
- references validate;
- areas are reconstructable.

### Player observation
- qualitative front cues work;
- visible physical logistics cues work;
- exact hidden numeric state is absent;
- observations update deterministically.

### Information separation
- player can observe something a commander does not yet know;
- commander beliefs remain unchanged until legitimate information arrives;
- PlayerObserverView cannot influence local or superior AI.

### Integrity
- prior 2B suite remains green;
- conservation remains green;
- event reconstruction passes;
- strict fresh-process replay passes.

---

# 37. Completion report

Save under:

```text
C:\Users\dawso\OneDrive\Desktop\trencho
```

using **109** and the established naming convention.

Include at minimum:

```text
109 completion status

commit SHA
project version
schema version
Godot version

total checks / failures
109-specific checks

Scenario A result
Scenario B result
Scenario C result
Scenario D result
Scenario E result

StrategicArea IDs

player observation types produced
qualitative-band results

exact-data leakage test result
AI-inertness comparison result
command/player divergence result

resource conservation result
event reconstruction result
strict fresh-process replay result

GDD housekeeping result

known limitations
deliberate deviations
```

Preserve the full 109 requirements in the repository if that remains the established convention.

---

# 38. Stop condition

When all 109 requirements pass:

**STOP.**

Do not begin 110.

Do not add player prompts.

Do not add “look here.”

Do not add “what happened here?”

Do not build reconnaissance missions.

Do not build the strategic UI.

Return the complete 109 evidence for review.

If accepted, **110** will introduce the first replayable nonbinding player-to-command prompt foundation, starting from the StrategicAreas and PlayerObserverView created here.
