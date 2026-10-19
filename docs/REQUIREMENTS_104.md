103 is **accepted**.

The reported evidence satisfies the 103 gate: strict replay remained intact, the fixed-point and exact-integer import issues were solved without weakening comparison semantics, information privacy held, resource conservation held, the required front behavior matched the specification, and the accepted 2A tag remained unchanged.

Do not modify or retag 103 after this point except for a genuine defect discovered later. Preserve commit:

```text
69f081fb2f2b1e8e2aea67d0ea189e393d6abd6c
```

The next authorized bounded task is **104** below.

---

# 104 — Autonomous Local Command Decision Cycle & Decision Journal

## Intended outcome

Implement the first actual autonomous commander reasoning in Trencho.

At the end of 104, a local command must be able to:

```text
receive local front observations
        ↓
reason only from its CommandView / beliefs
        ↓
evaluate several allowed posture choices
        ↓
record why each candidate was accepted/rejected/scored
        ↓
select the best available action deterministically
        ↓
change its own front posture through validated authority
        ↓
observe the consequence one interval later
        ↓
attach that outcome to the original decision
```

There is still **no player interaction, no peer collaboration, no supply request, and no escalation to a superior** in 104.

This task proves the smallest closed autonomous command loop.

---

# 1. Preserve accepted foundations

104 begins from accepted 103:

```text
commit:
69f081fb2f2b1e8e2aea67d0ea189e393d6abd6c

project version:
0.2.0

schema:
2B.1
```

Do not modify:

```text
prototype-gen2-2A-accepted
```

Do not weaken:

- event reconstruction;
- strict replay;
- information privacy;
- exact numeric state;
- resource conservation;
- authority boundaries.

If 104 exposes a genuine incompatibility with 2A/103, stop and ask before bypassing it.

---

# 2. Scope of autonomous reasoning

104 implements autonomous reasoning only for:

```text
LOCAL command
→ its directly responsible AbstractFront
```

One local command may control one front for the required fixture.

Do not implement multi-front optimization yet.

Do not implement operational/army-level autonomous reasoning yet.

---

# 3. Allowed autonomous actions

The 104 planner may select only:

```text
HOLD
PRESS
REDUCE_ACTIVITY
```

`WITHDRAW` remains a valid front posture in the schema but is **not an autonomous candidate in 104**.

Reason:

`WITHDRAW` currently changes ammunition demand but does not yet have a real spatial/territorial withdrawal mechanism. Allowing the AI to choose it now would create misleading semantics.

Tests/debug inputs may still set `WITHDRAW` manually as established in 103.

---

# 4. Information boundary

The planner must reason exclusively through the existing command-information boundary.

Allowed inputs:

```text
CommandView
delivered/local InformationRecords
command identity
command authority
```

Forbidden inputs:

```text
raw WorldState
AbstractFront internal object
enemy_pressure authoritative field
stockpile registry
global shipment registry
another command's beliefs
```

If a value affects a decision, the decision record must identify the `InformationRecord` from which that value came.

This is a hard requirement.

---

# 5. Required belief inputs

For a complete local decision, the command must have current beliefs for:

```text
FRONT_FRIENDLY_STRENGTH
FRONT_ENEMY_PRESSURE
FRONT_POSTURE
FRONT_AMMO_AVAILABLE
FRONT_AMMO_DEMAND_RATE
FRONT_AMMO_COVERAGE_MILLISECONDS
FRONT_AMMO_COVERAGE_STATUS
FRONT_LAST_SHORTAGE
```

`FRONT_AMMO_ON_HAND` may also be recorded diagnostically but is not required for policy because available stock is the usable quantity.

---

# 6. Belief freshness

A belief used for 104 planning must satisfy:

```text
current_simulation_time - observed_at <= 1.5 seconds
```

This is a prototype freshness rule.

If any required fact is:

- missing;
- expired;
- older than 1.5 seconds;

the command must **not make a posture decision**.

Record a skipped decision evaluation with the missing/stale fact keys.

Do not fall back to authoritative world truth.

---

# 7. Decision trigger

A local command evaluates its front immediately after a complete 1-second observation batch has been ingested.

Therefore normal cadence is:

```text
once per observation interval
```

For the standard fixture:

```text
t = 1.0
t = 2.0
t = 3.0
...
```

Do not evaluate every 0.1-second simulation tick.

Do not evaluate before the first complete observation.

---

# 8. Observation-batch completion

The planner must not react after the first fact of an eight/nine-fact observation batch and accidentally reason from a mixture of old and new values.

Provide an explicit mechanism identifying that the complete observation sample is ready.

Acceptable approaches include:

```text
observation batch ID
observation-complete event
shared observation correlation ID + completion signal
```

The exact implementation is developer latitude.

Required property:

> One decision cycle sees one internally consistent observation sample.

---

# 9. Decision identity

Every planning cycle receives a stable:

```text
decision_id
```

A decision ID must remain associated with:

- command;
- front;
- observation batch;
- candidates;
- selected action;
- later outcome.

IDs must not depend on array index or display name.

---

# 10. Decision journal record

Create a persistent/queryable decision projection or equivalent reconstructed journal.

Minimum decision fields:

```text
decision_id
command_id
front_id

trigger_event_id
observation_batch_id

started_at
selected_at

state

belief_record_ids[]

candidate_ids[]

selected_candidate_id or null
selected_action or null

outcome_attached
outcome_event_id or null
```

Suggested states:

```text
STARTED
SKIPPED
SELECTED
OUTCOME_ATTACHED
```

Exact internal representation may differ.

It must reconstruct from authoritative events.

---

# 11. Decision events

Activate the previously reserved decision-event family.

Required semantic events:

```text
DECISION_STARTED
DECISION_CANDIDATE_RECORDED
DECISION_SELECTED
DECISION_SKIPPED
DECISION_OUTCOME_ATTACHED
```

`DECISION_SKIPPED` is a 104 addition.

All events belonging to one decision must share:

```text
correlation_id = decision_id
```

Causation must identify immediate parent events where applicable.

---

# 12. Candidate record

Every considered candidate must record at minimum:

```text
candidate_id
decision_id
action
eligible
score
factor_contributions
rejection_reasons[]
```

If:

```text
eligible = false
```

then:

```text
score = null
```

Do not assign fake numeric scores to impossible actions.

---

# 13. Prototype decision policy

104 uses a deterministic, deliberately small policy.

This is **not final military doctrine**.

Its purpose is to prove:

- belief-driven reasoning;
- candidate comparison;
- inspectability;
- autonomous action;
- replay.

---

# 14. Derived planning classifications

Derive these only from beliefs.

## Supply state

### `CRITICAL`

True if **either**:

```text
FRONT_LAST_SHORTAGE > 0
```

or:

```text
coverage_status = FINITE
and coverage_ms < 5_000
```

### `CONSTRAINED`

If not CRITICAL, true when:

```text
coverage_status = FINITE
and coverage_ms < 15_000
```

### `SECURE`

If neither above, and:

```text
coverage_status = FINITE
and coverage_ms >= 15_000
```

or:

```text
coverage_status = OUT_OF_RANGE
```

### `NO_ACTIVE_DEMAND`

When:

```text
coverage_status = ZERO_DEMAND
```

---

# 15. Strength margin

Calculate:

```text
strength_margin_centi
=
friendly_strength_centi
-
enemy_pressure_centi
```

using the canonical 103 values represented in the beliefs.

Interpretation for 104:

```text
>= +2000  → STRONG_ADVANTAGE
-1999..+1999 → CONTESTED
<= -2000 → STRONG_DISADVANTAGE
```

These are prototype thresholds only.

---

# 16. Candidate eligibility

## HOLD

Always eligible if the required belief set is complete/fresh.

## REDUCE_ACTIVITY

Always eligible if the required belief set is complete/fresh.

## PRESS

Eligible only when **all** are true:

```text
supply_state = SECURE
strength_margin_centi >= +2000
FRONT_LAST_SHORTAGE = 0
```

Otherwise record the relevant rejection reasons.

Allowed reason codes should include equivalents of:

```text
SUPPLY_NOT_SECURE
INSUFFICIENT_STRENGTH_MARGIN
RECENT_AMMO_SHORTAGE
```

Do not use free-text reason strings as the only machine-readable representation.

---

# 17. Candidate scoring

Use integer scores.

No randomness.

No floating-point utility.

No personality modifiers.

## HOLD

```text
base = 50
```

Factor contributions:

```text
+20 if strength state = CONTESTED
+15 if supply state = CONSTRAINED
+10 if supply state = SECURE
-20 if supply state = CRITICAL
```

Maximum/minimum do not need normalization.

---

## REDUCE_ACTIVITY

```text
base = 20
```

Factor contributions:

```text
+100 if FRONT_LAST_SHORTAGE > 0
+60 if supply state = CRITICAL
+25 if supply state = CONSTRAINED
+10 if strength state = STRONG_DISADVANTAGE
-20 if supply state = SECURE
```

If multiple conditions apply, contributions stack.

Example:

```text
recent shortage
+ CRITICAL

20 + 100 + 60
= 180
```

---

## PRESS

Only score if eligible.

```text
base = 30
```

Factor contributions:

```text
+40 if strength margin >= +2000
+20 additional if strength margin >= +4000
+20 if supply state = SECURE
```

Therefore a +4000 or greater advantage with secure supply scores:

```text
30 + 40 + 20 + 20
= 110
```

---

# 18. Tie-breaking

If two eligible candidates have equal score, use this fixed order:

```text
HOLD
REDUCE_ACTIVITY
PRESS
```

First item wins the tie.

This is a deterministic implementation rule, not final design preference.

Record that a tie-break occurred in `DECISION_SELECTED`.

---

# 19. Why these prototype numbers exist

Do not reinterpret these scores as game balance.

They are constructed so 104 reliably demonstrates three qualitatively different decisions:

```text
healthy + large advantage
→ PRESS

ordinary / ambiguous state
→ HOLD

serious ammunition pressure
→ REDUCE_ACTIVITY
```

Future phases may replace these weights without changing the decision-journal architecture.

---

# 20. Applying the decision

The command must not directly mutate:

```text
front.posture
```

The selected action must use the existing validated posture-change pathway from 103.

The autonomous action must identify:

```text
actor_command_id
decision_id
reason/source = AUTONOMOUS_COMMAND_DECISION
```

Authority must be checked.

If authority rejects the change, record the action failure and do not pretend the decision executed successfully.

For the required fixture, the responsible command must possess valid authority.

---

# 21. No redundant posture mutation

If the selected action equals the current believed posture:

```text
selected_action == current posture
```

the decision is still valid and must be journaled.

Do **not** emit a fake `FRONT_POSTURE_CHANGED` event if the actual posture did not change.

The selected decision record should indicate:

```text
action_required = false
```

or equivalent.

---

# 22. Decision outcome

One completed observation interval after a successfully selected decision, attach an outcome.

104 outcome data is descriptive, not a learned reward signal.

Include at minimum:

```text
decision_id

evaluation_start_time
evaluation_end_time

selected_action

starting_ammo_available
ending_ammo_available

starting_coverage_status
starting_coverage_ms

ending_coverage_status
ending_coverage_ms

interval_demand
interval_consumed
interval_shortage

starting_enemy_pressure
ending_enemy_pressure

starting_friendly_strength
ending_friendly_strength
```

The outcome must use information available from the subsequent observation batch rather than querying world truth retroactively.

---

# 23. Outcome does not grade the decision

Do **not** assign:

```text
GOOD_DECISION
BAD_DECISION
SUCCESS
FAILURE
reward
fitness
```

in 104.

We are not yet capable of making that judgment reliably.

`DECISION_OUTCOME_ATTACHED` simply records what happened next.

---

# 24. Overlapping decisions

Because planning occurs every second and outcomes are evaluated one interval later:

At observation `N`:

1. attach the outcome for decision `N-1`;
2. then begin decision `N`.

Use this ordering.

Therefore each completed observation after the first may both:

```text
close previous decision
and
open/select next decision
```

This must remain deterministic.

---

# 25. Required ordering at observation boundary

Extend the 103 boundary semantics to:

```text
1. Resolve final tick demand for interval.
2. Apply physical ammunition consumption.
3. Emit shortage if applicable.
4. Finalize interval counters.
5. Generate complete local observation batch.
6. Ingest all observation records.
7. Mark observation batch complete.
8. Attach outcome to prior decision, if one exists.
9. Start new local-command decision.
10. Record all candidates.
11. Select candidate.
12. Apply posture change if required/authorized.
```

The new posture affects **future ticks**, not the interval that just finished.

No retroactive demand recalculation.

---

# 26. Missing/stale information behavior

If the observation batch is incomplete or required beliefs fail freshness validation:

Emit:

```text
DECISION_STARTED
DECISION_SKIPPED
```

or an equivalent coherent journal transition.

Include machine-readable reason(s):

```text
MISSING_REQUIRED_BELIEF
STALE_REQUIRED_BELIEF
INCOMPLETE_OBSERVATION_BATCH
```

No posture change occurs.

A skipped decision receives no candidate scores if there is insufficient information to evaluate candidates consistently.

---

# 27. Unsupported coverage condition

`OUT_OF_RANGE` means supply coverage is extremely large but finite.

For 104 planning:

```text
OUT_OF_RANGE
→ treat as SECURE
```

`ZERO_DEMAND` means there is currently no active burn.

For 104:

```text
NO_ACTIVE_DEMAND
```

In this state:

- PRESS is not eligible solely on supply grounds because `SECURE` is required;
- HOLD remains eligible;
- REDUCE remains eligible.

This prevents the local planner from interpreting “nobody is currently consuming ammo” as evidence of a well-supplied offensive opportunity.

---

# 28. Required demonstration scenarios

Build deterministic tests/fixture coverage for at least these.

## Scenario A — strong and well supplied

Beliefs equivalent to:

```text
friendly_strength = 80
enemy_pressure = 40

strength margin = +40

coverage = 20+ sec
last shortage = 0
```

Expected:

```text
PRESS eligible
PRESS score = 110
PRESS selected
```

assuming HOLD/REDUCE calculate lower.

---

## Scenario B — contested and adequately supplied

Example:

```text
friendly_strength = 60
enemy_pressure = 50
coverage >= 15 sec
last shortage = 0
```

PRESS rejected:

```text
INSUFFICIENT_STRENGTH_MARGIN
```

Expected selected action:

```text
HOLD
```

---

## Scenario C — ammunition shortage

Example:

```text
last shortage > 0
```

Expected:

```text
PRESS rejected
REDUCE_ACTIVITY receives shortage + critical factors
REDUCE_ACTIVITY selected
```

---

## Scenario D — recovery after conservation

Begin in shortage so AI selects:

```text
REDUCE_ACTIVITY
```

Then provide sufficient ammunition using the existing resource system.

Once observations indicate:

```text
SECURE supply
no recent shortage
```

and the strength advantage is not sufficient for PRESS:

Expected:

```text
HOLD
```

This proves autonomous posture can recover rather than becoming permanently stuck in a low-activity state.

---

# 29. Required privacy test

Create a condition where authoritative world state would justify PRESS, but the command's current valid beliefs do **not**.

The command must act from its beliefs.

Example:

```text
authoritative friendly strength = 90
command belief still = 50

enemy pressure belief = 50
```

Expected:

```text
PRESS not selected
```

until a later valid observation delivers the updated strength.

This is one of the most important 104 tests.

---

# 30. Required stale-information test

Inject or construct a belief older than:

```text
1.5 seconds
```

with no fresh replacement.

Expected:

```text
decision skipped
posture unchanged
```

The planner must not read authoritative state to repair the missing information.

---

# 31. Decision-journal acceptance tests

Verify:

- every completed planning cycle has a stable decision ID;
- belief record IDs used by the decision are recorded;
- candidate records are reconstructable;
- rejected PRESS candidate records reasons;
- selected candidate has exact deterministic score;
- all decision events share decision correlation ID;
- causation chain is reconstructable;
- no randomness fields/rolls exist in 104;
- journal reconstructs from authoritative events;
- fresh-process replay reproduces identical decisions and scores.

---

# 32. Resource behavior acceptance

104 must not alter 103 resource semantics.

Verify:

- PRESS increases subsequent ammunition burn through the existing posture multiplier;
- REDUCE_ACTIVITY decreases subsequent burn;
- the current completed interval is unaffected by the decision made at its boundary;
- shortages remain actual unmet demand;
- no supply is created by the planner;
- no automatic resource transfer occurs;
- no automatic reservation occurs;
- no resource request exists yet.

---

# 33. Authority acceptance

Verify:

- responsible command can apply its selected posture;
- unrelated command cannot autonomously alter that front;
- planner does not bypass `AuthorityService`;
- authority failure is logged rather than silently ignored.

---

# 34. Determinism and numeric contract

All scores, thresholds and strength calculations in 104 must use exact integer/canonical values.

Do not introduce floating-point utility scoring.

Do not introduce stochastic candidate selection.

The same:

```text
world
inputs
beliefs
seed
```

must produce the same:

```text
candidates
scores
selection
posture
outcome
event stream
```

The seed remains present infrastructure but is not used by 104 decision policy.

---

# 35. Decision service boundaries

Recommended logical separation:

```text
LocalCommandPlanner
DecisionJournal
DecisionPolicy104
```

Exact names are developer latitude.

Conceptually:

```text
Observation complete
        ↓
LocalCommandPlanner
        ↓
CommandView
        ↓
DecisionPolicy104
        ↓
candidate evaluations
        ↓
DecisionJournal
        ↓
selected action
        ↓
validated front posture command
```

The policy should not own resource or front state directly.

---

# 36. Policy replaceability

Do not scatter 104 score constants throughout planner code.

Keep the prototype policy sufficiently isolated that a later policy can replace:

```text
eligibility
thresholds
weights
tie-break
```

without rewriting:

- observation ingestion;
- DecisionJournal;
- CommandView;
- event semantics;
- action application.

This is an important modularity requirement.

---

# 37. No personality yet

Do not implement:

- aggressive commander;
- cautious commander;
- greedy commander;
- competence;
- experience;
- officer traits;
- random risk appetite.

104 establishes the neutral deterministic planner first.

Personality will later modify the same reasoning framework if testing justifies it.

---

# 38. No communication behavior yet

The planner may consume locally observed beliefs.

It must not send:

```text
REPORT
COORDINATION
ESCALATION
STRATEGIC_REQUEST
```

automatically.

104 remains a local closed loop.

Communication-driven command hierarchy behavior is a subsequent task.

---

# 39. Explicit non-goals

Do **not** implement:

- peer collaboration;
- requests for ammunition;
- automatic logistics dispatch;
- superior arbitration;
- operational command planning;
- player decisions;
- deck/cards;
- economy gameplay;
- enemy commander AI;
- officer personalities;
- command learning;
- reinforcement allocation;
- territory changes;
- real withdrawal behavior;
- tactical combat units;
- random decision variation;
- difficulty levels.

---

# 40. Expected 104 demonstration narrative

A successful 104 run should be able to produce a causal history similar to:

```text
Local observation:
strength 80
pressure 40
supply secure

Decision:
HOLD scored ...
REDUCE scored ...
PRESS scored 110

Selected:
PRESS

Front posture:
HOLD → PRESS

Next interval:
ammo demand increased because PRESS multiplier applied

Next observation:
outcome attached to prior decision

New decision:
reevaluate from new beliefs
```

And separately:

```text
ammo shortage occurs
↓
local observation records shortage
↓
PRESS rejected
↓
REDUCE_ACTIVITY receives highest score
↓
posture changes
↓
subsequent ammo demand falls
↓
later resupply removes scarcity
↓
AI returns to HOLD when appropriate
```

No player action is required beyond scripted fixture state changes.

---

# 41. Acceptance gate

104 is complete only when:

### Reasoning
- local planner operates from `CommandView`;
- all required beliefs are checked;
- stale/missing information causes abstention;
- three candidates are evaluated as specified;
- deterministic selection works.

### Decision journal
- start/candidates/selection/outcome are recorded;
- factor contributions are inspectable;
- rejected candidates contain reason codes;
- belief provenance is recorded;
- correlation/causation is intact.

### Action
- selected posture uses validated authority path;
- redundant posture changes do not create fake mutation events.

### Outcome
- prior decision receives the next complete interval's observed result;
- outcome is descriptive, not graded.

### Integrity
- resource conservation still passes;
- information privacy still passes;
- exact numeric/replay behavior still passes;
- accepted 2A tag remains unchanged.

---

# 42. Completion report

When complete, save the numbered report under:

`C:\Users\dawso\OneDrive\Desktop\trencho`

using **104** as the next step number and the same established naming convention.

Include:

```text
104 completion status

commit SHA
project version
schema version
Godot version

modules/files added or changed

total suite result
assertion count
failure count

104-specific assertion count

Scenario A result
Scenario B result
Scenario C result
Scenario D result

privacy/stale-belief results

decision IDs/event counts
decision replay result

resource conservation result
strict fresh-process replay result

known limitations
deliberate deviations
```

Preserve the 104 requirements alongside the completion evidence if that matches the established repository/document convention.

---

# 43. Stop condition

After every 104 requirement passes:

**STOP.**

Do not begin resource requests.

Do not begin peer collaboration.

Do not begin superior escalation.

Do not begin 105.

Return the 104 completion evidence to me for review.

The next likely task, if 104 succeeds, will connect this local reasoning loop to **dynamic resource need, command-to-command communication, and the first solve-locally / coordinate / escalate behavior**.
