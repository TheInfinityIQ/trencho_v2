106 is **accepted**.

The reported evidence satisfies the 106 gate: superior knowledge remains message-derived rather than omniscient, arbitration operates on delivered revisions, scarce stock is allocated through the staged coverage policy rather than equal/proportional splitting, stale information can produce explainable over-allocation, physical shipment/notification semantics remain intact, and all prior architecture/replay/conservation guarantees remain green.

Preserve accepted 106 at:

```text
commit:
750333ee1d912d195c78f32fbc5ae738a7d1fd4d
```

Do not modify the accepted 2A tag.

You are authorized to begin **107 only**.

# 107 — Integrated Unattended Autonomous Command Slice

## 1. Intended outcome

107 is the **final 2B task**.

Do not introduce another isolated AI subsystem.

Instead, assemble the accepted 103–106 systems into one continuous simulation and prove that the hierarchy can operate for an extended period with **zero player/runtime intervention**.

The complete chain must function together:

```text
Abstract Front
    ↓
Local Observation
    ↓
Local Posture Decision
    ↓
Dynamic Ammunition Need
    ↓
Local Self-Help
    ↓
Peer Coordination
    ↓
Escalation
    ↓
Superior Arbitration
    ↓
Physical Logistics
    ↓
Delivered Allocation Information
    ↓
Updated Local Beliefs
    ↓
Posture / Need Reevaluation
```

The key 2B question is:

> **Can the command hierarchy continuously operate, adapt and distribute scarce ammunition without the player solving local problems for it?**

---

# 2. Hard scope rule

107 should primarily be **integration, orchestration, validation and diagnostics**.

Do not redesign the accepted policies from 104–106 simply because an integrated run produces imperfect strategic behavior.

If integration reveals a genuine contradiction or defect in an accepted contract, stop and ask before changing that contract.

---

# 3. Unattended-run definition

After the integrated simulation begins:

```text
NO player/debug input may change simulation state.
```

The run may contain:

- autonomous command decisions;
- autonomous communication;
- autonomous logistics;
- autonomous resource-resolution behavior;
- pre-existing shipments configured in `initial_world`.

The run may **not** contain post-start scripted commands such as:

```text
CreateResourceInput
SetFrontPressureInput
SetFrontPostureInput
DispatchShipmentInput
InjectInformationInput
```

The purpose is to verify an actual autonomous continuous run rather than a sequence of test interventions.

---

# 4. Initial-world environmental state

The 107 fixture may contain all required starting resources, routes and one already-dispatched strategic resupply shipment.

That shipment is part of the initial world, not a player/runtime action.

Use:

```text
simulation tick = existing accepted 100 ms

integrated duration = 25.0 simulation seconds
final tick = 250
```

Do not shorten the run because an early milestone passed.

---

# 5. Command hierarchy

Required hierarchy:

```text
OPERATIONAL_COMMAND
        |
  -----------------
  |       |       |
LOCAL_A LOCAL_B LOCAL_C
```

All three LOCAL commands:

- have autonomous 104 local planning enabled;
- have 105 resource resolution enabled;
- report to the same OPERATIONAL command.

`OPERATIONAL_COMMAND` has 106 arbitration enabled.

---

# 6. Abstract fronts

Create:

```text
FRONT_A
FRONT_B
FRONT_C
```

All use:

```text
base_ammo_demand_per_second = 8.000
initial posture = HOLD
```

Initial combat states:

```text
FRONT_A
friendly_strength = 80
enemy_pressure = 40

FRONT_B
friendly_strength = 60
enemy_pressure = 50

FRONT_C
friendly_strength = 50
enemy_pressure = 70
```

Therefore the intended first complete local decisions are:

```text
LOCAL_A → PRESS
LOCAL_B → HOLD
LOCAL_C → REDUCE_ACTIVITY
```

These exact first-cycle outcomes are required.

If they do not occur, treat that as an integration defect rather than changing the fixture thresholds.

---

# 7. Initial frontline ammunition

Use:

```text
A_FRONT_STOCK = 120 ammo
B_FRONT_STOCK = 80 ammo
C_FRONT_STOCK = 20 ammo
```

No pre-existing reservations.

---

# 8. Local reserve stock

Use:

```text
C_LOCAL_RESERVE = 8 ammo
B_LOCAL_RESERVE = 30 ammo
```

`LOCAL_A` has no separate reserve ammunition.

Required routes:

```text
C_LOCAL_RESERVE
→ C_FRONT_STOCK

B_LOCAL_RESERVE
→ C_FRONT_STOCK
```

The exact edge IDs are developer latitude.

Travel times:

```text
C local self-help → C front = 0.5 sec
B reserve → C front = 1.0 sec
```

This fixture is deliberately constructed so C demonstrates:

```text
self-help
→ peer assistance
→ superior escalation if still necessary
```

inside one continuous run.

---

# 9. Operational stock

Use:

```text
OP_HQ_STOCK initial physical ammunition = 50
```

All non-reserved quantity remains eligible under accepted 106 rules.

Provide routes:

```text
OP_HQ_STOCK → A_FRONT_STOCK
OP_HQ_STOCK → B_FRONT_STOCK
OP_HQ_STOCK → C_FRONT_STOCK
```

Travel time for each:

```text
2.0 simulation seconds
```

---

# 10. Pre-existing operational resupply

The initial world must also contain an already-dispatched shipment:

```text
quantity = 60 ammunition
destination = OP_HQ_STOCK
```

Expected arrival:

```text
t = 15.0 seconds
```

The origin may be an existing `OFFSCREEN_SOURCE`-style location.

This shipment:

- exists before the unattended run begins;
- is already legitimate in-transit cargo;
- must be included in initial resource-conservation accounting;
- requires no runtime input.

This gives the hierarchy a later second tranche of scarce ammunition without introducing economy gameplay.

---

# 11. Communication topology

Required bidirectional peer communication:

```text
LOCAL_A ↔ LOCAL_B
LOCAL_A ↔ LOCAL_C
LOCAL_B ↔ LOCAL_C
```

Use:

```text
one-way latency = 0.2 sec
```

Required local/superior communication:

```text
each LOCAL ↔ OPERATIONAL_COMMAND
```

Use:

```text
one-way latency = 0.3 sec
```

No communication edges are deliberately disabled during 107.

Communication-failure behavior was already proven independently.

---

# 12. No world-pressure script

Do not alter:

```text
friendly_strength
enemy_pressure
```

after simulation start.

They remain fixed for this fixture.

The dynamics must emerge from:

```text
posture
ammunition consumption
resource scarcity
communication latency
shipments
command decisions
```

rather than externally scripted battlefield changes.

---

# 13. Required early behavior

At the first complete observation/decision boundary:

### A

Expected:

```text
strength advantage = +40
supply secure
→ PRESS
```

### B

Expected:

```text
contested
supply initially secure
→ HOLD
```

### C

Expected:

```text
strong disadvantage
critical supply condition
→ REDUCE_ACTIVITY
```

All must be journaled using accepted 104 decision semantics.

---

# 14. Required C resolution chain

During the unattended run, C must demonstrate the complete lower-level chain.

Expected ordering:

```text
C ammunition need opens
↓
C attempts local self-help
↓
8 ammo dispatched from C_LOCAL_RESERVE
↓
need remains uncovered
↓
C attempts peer coordination
```

Peer ordering remains deterministic under 105.

The fixture must result in at least:

- one peer unable/unwilling to satisfy the need fully;
- B contributing ammunition from `B_LOCAL_RESERVE`;
- physical peer shipment;
- need still requiring superior escalation at some point.

Do not alter 105's peer-protection or offer semantics merely to force an exact donation quantity.

The expected maximum available from B's separate reserve is 30.

---

# 15. Required escalation

After C exhausts lower-level resolution for its remaining uncovered need:

```text
C → OPERATIONAL_COMMAND
```

must occur through the normal delivered 105 escalation path.

Operational Command may then allocate from its initial 50-ammo stock under the existing 106 policy.

No special integration shortcut is permitted.

---

# 16. A and B must naturally become supply problems

Because front consumption continues:

```text
A's PRESS posture increases burn
B's HOLD posture continues normal burn
```

Both A and B should eventually enter resource-need behavior during the 25-second run.

The fixture must produce a period in which:

```text
at least TWO delivered ACTIVE subordinate need reports
exist at OPERATIONAL_COMMAND simultaneously
```

This is a required 107 milestone.

If the exact timing fails because of an implementation integration issue, diagnose it.

Do not inject needs manually.

---

# 17. Scarce superior arbitration milestone

Before or after the 60-ammo resupply reaches HQ, the integrated run must contain at least one arbitration cycle where:

```text
2+ actionable subordinate reports exist
and
available superior stock is insufficient to refill all reports to their complete 20-second targets
```

The accepted 106 staged policy must determine the resulting allocations.

Required proof:

- more than one report considered;
- scarcity was real;
- resulting allocation was not produced by equal/proportional splitting;
- exact reports/revisions used are journaled.

No new arbitration policy is introduced in 107.

---

# 18. Strategic resupply arrival

At approximately:

```text
t = 15.0 sec
```

the pre-existing 60-ammo shipment must physically arrive at OP_HQ_STOCK.

Operational Command should then naturally become capable of additional allocations during later arbitration cycles if actionable reports remain.

Do not manually trigger arbitration because supply arrived.

Existing cadence handles it.

---

# 19. Posture adaptation

The integrated run must show at least two autonomous posture transitions caused by evolving supply state.

Required examples:

### A

A begins:

```text
HOLD → PRESS
```

and later, as ammunition becomes constrained, must cease PRESS through the existing local planner.

Expected normal transition:

```text
PRESS → HOLD
```

if its later belief state matches accepted 104 policy.

### C

C begins:

```text
HOLD → REDUCE_ACTIVITY
```

and, after observed physical resupply and shortage recovery, should eventually leave REDUCE_ACTIVITY.

Expected:

```text
REDUCE_ACTIVITY → HOLD
```

if accepted policy conditions are satisfied.

Do not force these posture changes through scripted input.

---

# 20. Need lifecycle integration

The run must demonstrate at least:

```text
one ResourceNeed that fully RESOLVES
```

through:

```text
physical arrival
→ complete local observation
→ shortage-free interval
→ observed stock satisfying recalculated target
```

It is acceptable for one or more other needs to remain active at tick 250 because supply is scarce.

An active unresolved need at the end is not itself a failure.

---

# 21. No message/request spam

Verify during the integrated run:

- no duplicate per-second peer request for an already outstanding conversation;
- no duplicate escalation for an unchanged revision;
- no repeated superior funding beyond an unchanged report's remaining amount;
- resolved needs do not continue sending requests;
- stale reports cannot overwrite newer ones.

Use existing rules; do not introduce arbitrary cooldowns.

---

# 22. No player surrogate

The following do **not** count as autonomous success and are forbidden after the run begins:

```text
test code deciding which command receives ammo
script changing posture
script resolving needs
script creating new resources
script manually starting negotiation
script selecting arbitration outputs
```

Test code may inspect and assert.

It may not make strategic choices for the AI.

---

# 23. Integrated causal audit

Add a test/query helper capable of reconstructing at least one complete chain from the 107 package.

For one need that reached superior arbitration, return or assert links equivalent to:

```text
front observation batch
→ local command decision
→ ResourceNeed opening/revision
→ local self-help attempt
→ peer coordination messages
→ peer reservation/shipment if applicable
→ escalation message
→ superior delivered report
→ arbitration decision
→ selected allocation
→ superior shipment
→ allocation notification
→ subordinate confirmed incoming
→ physical arrival
→ subsequent observation
→ need/posture reevaluation
```

This may be a test helper.

Do not build player UI for it.

Every link must use existing IDs/correlation/causation rather than heuristic timestamp matching.

---

# 24. Information-isolation audit

During the integrated run verify:

- LOCAL commands see only their permitted local beliefs/messages;
- OPERATIONAL sees delivered subordinate reports and its own stock;
- OPERATIONAL never reads raw subordinate fronts;
- one LOCAL does not automatically receive another LOCAL's observations;
- shipment existence is not knowledge until the relevant accepted mechanism communicates it.

---

# 25. Resource audit

At every authoritative event prefix in the integrated run verify:

```text
created/initial physical resource total
=
stock
+ cargo
+ consumed
+ destroyed
```

with active reservation accounting remaining valid.

Initial in-transit 60-ammo strategic resupply must be included correctly.

---

# 26. Decision audit

For the full run verify:

- every autonomous local posture decision is reconstructable;
- every superior arbitration is reconstructable;
- all decisions use exact belief/report revisions;
- no random selection occurs;
- no player preference exists;
- outcomes remain descriptive rather than graded.

---

# 27. Replay requirement

The full 25-second integrated run must pass strict fresh-process replay.

Verify identical:

```text
final authoritative state
all ordered authoritative events
decision journal
resource needs
coordination state
superior reports
arbitration state
shipments
beliefs
resource ledger
```

No tolerance may be introduced.

---

# 28. Initial-world replay purity

Because 107 prohibits runtime external interventions:

```text
inputs.jsonl
```

for the unattended interval must contain no state-changing actions after simulation start.

If repository startup infrastructure necessarily emits a run/bootstrap marker, that is acceptable provided it does not alter gameplay state.

Document the exact input count and types.

---

# 29. Long-run stability checks

During the 25-second run assert:

- no runaway recursive messaging;
- no unbounded duplicate needs;
- no reservation leak;
- no offer leak after expiry/resolution;
- no negative stock;
- no orphan shipment references;
- no unresolved message state past its legitimate lifecycle without explanation;
- no authority bypass;
- no event-reconstruction divergence.

---

# 30. Event-volume observation

Report:

```text
total event count
event count by major event type/family
events.jsonl size
replay duration if already measured by existing harness
```

This is observational only.

Do **not** optimize or separate trace logs during 107 unless the run exposes an actual blocking problem.

The previously discussed semantic-event/trace separation remains a later architecture consideration.

---

# 31. Developer inspector

No new player-facing UI is required.

If inexpensive, the existing developer inspector may display integrated state such as:

```text
front posture
ammo / coverage
active need phase
peer coordination state
superior report state
last arbitration allocation
```

But this is optional.

Do not delay 107 for presentation work.

---

# 32. Required integrated fixture summary

The initial fixture must therefore contain approximately:

```text
1 OPERATIONAL command
3 LOCAL commands
3 AbstractFronts

Front stock:
A = 120
B = 80
C = 20

Local reserve:
B = 30
C = 8

Operational stock:
50

Pre-existing inbound operational cargo:
60 arriving at 15 sec

Front base demand:
8 ammo/sec each

Strength / pressure:
A = 80 / 40
B = 60 / 50
C = 50 / 70

Initial posture:
HOLD / HOLD / HOLD
```

Communication and logistics use §§8–11 above.

Do not silently tune these quantities simply to make assertions pass.

If the accepted autonomous policies produce a materially different interaction than predicted, **stop and report what actually happened** before redesigning the fixture or policy.

Minor implementation-level timing caused by accepted fixed-step boundaries is fine.

---

# 33. Required milestone assertions

The 107 run must prove all of these:

1. A selects PRESS on first decision.
2. B selects HOLD on first decision.
3. C selects REDUCE_ACTIVITY on first decision.
4. C opens a dynamic ammunition need.
5. C uses its own 8-ammo reserve before peers.
6. At least one successful peer ammunition transfer occurs.
7. C or another local eventually escalates.
8. Operational Command performs at least one real superior allocation.
9. At least one arbitration considers 2+ active delivered needs simultaneously.
10. At least one arbitration occurs under insufficient stock for all 20-second targets.
11. Pre-existing 60-ammo HQ resupply arrives physically without runtime input.
12. At least one command exits an earlier non-HOLD posture autonomously.
13. At least one ResourceNeed reaches `RESOLVED`.
14. At least one complete need chain is causally reconstructable.
15. No gameplay-state external input occurs after autonomy begins.
16. Strict replay matches every ordered event.
17. Every relevant event prefix conserves resources.

---

# 34. What 107 does not need to prove

2B does **not yet** contain:

- territorial victory;
- dynamically selected strategic map objectives;
- enemy command hierarchy;
- a production economy;
- deck interaction;
- player preference;
- officer personality.

Therefore do not claim 107 proves the full game is autonomous.

It proves the **command/logistics hierarchy can autonomously operate its current abstract fronts**.

That is the correct 2B milestone.

---

# 35. Explicit non-goals

Do **not** implement:

- player controls;
- strategic player preference;
- cards/deck;
- production economy;
- additional resources;
- enemy command AI;
- territorial objective generation;
- victory/defeat;
- officer personalities;
- command experience;
- randomness;
- learning;
- new allocation weights;
- new peer-negotiation policy;
- strategic reserves;
- visual soldiers;
- tactical combat;
- final UI;
- temporary art assets.

107 is integration and proof, not feature expansion.

---

# 36. 107 acceptance gate

107 is complete only when:

### Autonomy
- the 25-second run proceeds without gameplay-state external input;
- all command/logistics actions come from accepted autonomous systems.

### Local behavior
- three expected initial posture decisions occur;
- later posture adaptation occurs naturally.

### Resource hierarchy
- self-help, peer cooperation, escalation and superior allocation all operate in one continuous run.

### Scarcity
- at least one genuine multi-need scarce arbitration occurs.

### Logistics
- all aid is physical;
- the pre-existing strategic resupply arrives naturally;
- incoming/physical stock remain distinct.

### Information
- all decisions respect private knowledge;
- superior reasoning remains report-derived.

### Diagnostics
- one complete causal chain can be reconstructed using IDs;
- local decisions and superior arbitration remain inspectable.

### Integrity
- conservation passes;
- reservation lifecycle passes;
- strict replay passes;
- all prior 2A/103/104/105/106 suites remain green.

---

# 37. Completion report

Save under:

`C:\Users\dawso\OneDrive\Desktop\trencho`

using **107** and the existing naming convention.

Include at minimum:

```text
107 completion status

commit SHA
project version
schema version
Godot version

total checks / failures
107-specific checks

integrated final tick
total ordered events
events.jsonl size

runtime external gameplay-input count

initial decisions:
A
B
C

posture transition timeline

ResourceNeed timeline by command

self-help shipment IDs
peer coordination / shipment IDs
escalation message IDs
superior report IDs

arbitration IDs
reports/revisions used
allocation quantities
superior shipment IDs

t=15 strategic resupply shipment result

resolved need IDs
active end-state need IDs

multi-need scarcity arbitration proof

causal audit result
information isolation result
resource prefix-conservation result
strict fresh-process replay result

event counts by major family

known limitations
deliberate deviations
```

Preserve the full 107 requirements beside the evidence if that remains the repository convention.

---

# 38. Stop condition

When every 107 acceptance requirement passes:

**STOP.**

Do not begin 2C.

Do not implement player influence.

Do not create strategic preference controls.

Do not begin temporary art production.

Return the 107 evidence to me.

If accepted, I will declare **Prototype Generation 2B complete**, establish the 2B freeze/tag instruction, and then issue the first bounded **2C — Strategic Player Influence** packet.
