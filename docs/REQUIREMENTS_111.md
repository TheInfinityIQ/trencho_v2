110 is **accepted**.

The evidence satisfies the 110 gate. The dedicated pre-core prompt-input branch was the correct implementation: valid and invalid prompt attempts remain auditable without perturbing the accepted authoritative input/event/ID architecture, and the F/H byte-identical 3,607-event comparison is the key inertness proof.

Preserve accepted 110 at:

```text
0497e61f9d7ef4c2c8a39d0e865cd783653bf57b
```

Frozen 2A/2B tags remain untouched. The GDD housekeeping item remains nonblocking.

You are authorized to begin **111 only**.

# 111 — Operational Command Prompt Evaluation

## 1. Purpose

111 adds the first autonomous command reaction to the player's nonbinding prompts.

It answers only:

> **“Given what Operational Command already knows, what can it currently say about the area the player pointed to?”**

It does **not** yet:

- gather new information;
- launch reconnaissance;
- change posture;
- allocate resources because of the prompt;
- generate battlefield orders.

The chain becomes:

```text
PLAYER
  ↓
DIRECT_ATTENTION / REQUEST_ASSESSMENT
  ↓
Operational Command prompt inbox
  ↓
Command evaluates from its OWN delivered knowledge
  ↓
structured evaluation result
```

---

## 2. Starting point

Begin from accepted 110:

```text
0497e61f9d7ef4c2c8a39d0e865cd783653bf57b
```

Expected progression:

```text
Project 0.3.2
Schema 2C.3
```

Preserve frozen acceptance tags unchanged.

Foundation entering 111:

```text
1043 checks / 0 failures
```

---

## 3. Opt-in compatibility

Add an Operational-command configuration equivalent to:

```text
strategic_prompt_evaluation_enabled
```

Default:

```text
false
```

111 fixtures enable it explicitly.

This is required so accepted 110 fixtures continue ending at:

```text
PENDING_EVALUATION
```

unless the new 111 behavior is intentionally enabled.

Do not retroactively change 110 evidence.

---

## 4. Evaluation cadence

Enabled Operational Commands evaluate pending prompts once per:

```text
1.0 simulation second
```

Use the existing exact timing infrastructure.

At a whole-second boundary:

1. process communication/messages due at that boundary;
2. update accepted command/report projections;
3. evaluate pending player prompts;
4. continue with existing arbitration/other accepted processing.

Therefore information delivered exactly at the evaluation boundary is available.

Do not evaluate every 100 ms tick.

---

## 5. Evaluate once in 111

Each prompt receives exactly one 111 evaluation.

Lifecycle:

```text
SUBMITTED
→ PENDING_EVALUATION
→ EVALUATED
```

111 does **not** automatically reevaluate a prompt when later information arrives.

Future information-requirement/recon work may extend that lifecycle.

---

# 6. Knowledge boundary

The evaluator may consume only recipient-scoped command knowledge.

For 111 the supported source is primarily the accepted **delivered superior ammunition-need report projection** from 105/106.

It may use recipient-scoped CommandView infrastructure where technically necessary, but must not broaden the supported assessment domain.

Allowed:

```text
delivered SuperiorNeedReports
report state/revision
source message/report IDs
recipient command identity/hierarchy
StrategicArea configuration
simulation time
```

Forbidden:

```text
WorldState front truth
AbstractFront internals
PlayerObserverView
player observation history
subordinate private beliefs
undelivered messages
hidden shipments
global inventory
```

---

# 7. Important scope limitation

111 is **not a general battlefield-intelligence system**.

Its first evaluation policy understands only one meaningful operational concern already present in the accepted system:

> **delivered subordinate ammunition-need knowledge associated with the selected front.**

This narrowness is intentional.

Do not invent enemy intelligence, casualty assessment, recon doctrine, or tactical interpretation just to answer the prompt.

---

# 8. Evaluation results

Implement exactly these result classes, or repository-equivalent enums:

```text
KNOWN_CONCERN_PRESENT
ASSESSMENT_AVAILABLE
NO_ACTIVE_KNOWN_CONCERN
FURTHER_INFORMATION_REQUIRED
```

These are command-evaluation results, not player orders.

---

# 9. DIRECT_ATTENTION policy

For:

```text
DIRECT_ATTENTION
```

on a front-associated StrategicArea:

### Active delivered need exists

Return:

```text
KNOWN_CONCERN_PRESENT
```

Assessment code:

```text
ACTIVE_AMMO_SUPPLY_CONCERN
```

Meaning:

> Operational Command already knows of an active ammunition problem in this area.

The prompt causes no additional military action.

### No active report, but at least one delivered resolved need report exists

Return:

```text
NO_ACTIVE_KNOWN_CONCERN
```

Assessment code:

```text
LAST_KNOWN_AMMO_NEED_RESOLVED
```

This means only:

> Within the limited 111 knowledge domain, command has no active delivered ammunition concern here.

It does **not** mean the area is objectively safe.

### No supported delivered report exists

Return:

```text
FURTHER_INFORMATION_REQUIRED
```

Assessment code:

```text
NO_SUPPORTED_AREA_INFORMATION
```

---

# 10. REQUEST_ASSESSMENT policy

For:

```text
REQUEST_ASSESSMENT
```

### Active delivered need exists

Return:

```text
ASSESSMENT_AVAILABLE
```

Assessment code:

```text
ACTIVE_AMMO_SUPPLY_PROBLEM
```

### No active report, but delivered resolved report exists

Return:

```text
ASSESSMENT_AVAILABLE
```

Assessment code:

```text
KNOWN_AMMO_NEED_RESOLVED
```

### No supported delivered report exists

Return:

```text
FURTHER_INFORMATION_REQUIRED
```

Assessment code:

```text
NO_SUPPORTED_AREA_INFORMATION
```

Do not manufacture an answer from absence of reports.

---

# 11. Frontless areas

For a StrategicArea with:

```text
front_id = null
```

111 has no supported knowledge model yet.

Return:

```text
FURTHER_INFORMATION_REQUIRED
```

with:

```text
NO_SUPPORTED_AREA_INFORMATION
```

Do not add HQ analysis merely because the area contains owned stock.

---

# 12. Multiple reports / needs for one front

A front may have history from multiple `need_id`s.

Evaluation must inspect the recipient's **currently delivered report projection**, not raw report-message history.

Rules:

1. if any current report for that front is `ACTIVE`, active concern wins;
2. otherwise, if one or more current reports are `RESOLVED`, use resolved knowledge;
3. otherwise, information required.

For provenance, record all report IDs materially considered in canonical order.

Select a `primary_report_id` deterministically:

```text
ACTIVE before RESOLVED
→ latest report_received_at
→ need_id ascending as final tie-break
```

Do not rely on dictionary iteration.

---

# 13. No new freshness threshold

Do **not** invent a 111 freshness cutoff.

106 intentionally established that Operational Command may reason from stale delivered reports.

A stale delivered report remains part of what command knows until superseded.

Internally record enough timing to explain this, e.g.:

```text
source_observed_at
report_received_at
evaluated_at
```

but do not silently query current subordinate truth to verify it.

---

# 14. PromptEvaluation record

Create a persistent/reconstructable evaluation equivalent to:

```text
evaluation_id
prompt_id
recipient_command_id
area_id
prompt_type

evaluated_at

result
assessment_code

primary_report_id or null
knowledge_report_ids[]
knowledge_message_ids[]

state
```

Suggested state:

```text
COMPLETED
```

Stable deterministic evaluation IDs, e.g.:

```text
prompt-evaluation:0000000001
```

Use a separate namespace/counter.

---

# 15. Provenance requirement

If an evaluation says command knows something, it must identify the delivered report(s) supporting that conclusion.

For an active supply concern, store the actual accepted:

```text
SuperiorNeedReport ID
source escalation/update message ID
need_id
need_revision
```

in the internal evaluation/journal.

Do not expose all of those IDs in the normal player-facing view.

---

# 16. Player-facing response remains qualitative

111 does **not** yet reveal exact:

```text
uncovered ammo quantity
available ammo
planning rate
target stock
shipment quantity
strength
enemy pressure
```

even if Operational Command's internal report contains those numbers.

The player-facing prompt projection may expose:

```text
result
assessment_code
evaluated_at
```

plus existing prompt identity/area information.

Exact-number inquiry is deliberately reserved for later experimentation.

---

# 17. No world action

A 111 evaluation must not itself cause:

```text
resource allocation
shipment dispatch
posture mutation
resource need
peer coordination
escalation
reconnaissance
message to subordinate
```

If Operational Command already has an active need report, accepted 106 arbitration continues independently as normal.

Do not duplicate it because the player pointed at the area.

---

# 18. No InformationRecord fabrication

Prompt evaluation must not create fake battlefield facts in InformationService.

Forbidden:

```text
player asks "what happened?"
→ create fact saying shortage exists
```

The evaluator reads existing delivered command knowledge and reports its interpretation.

---

# 19. Prompt stream extension

Keep evaluation semantics in the existing separate player-prompt stream.

Add equivalent event:

```text
PLAYER_PROMPT_EVALUATED
```

Minimum payload:

```text
prompt_event_id
evaluation_id
prompt_id

result
assessment_code

evaluated_at

primary_report_id or null
knowledge_report_ids[]

previous_prompt_event_id
```

Do not insert these events into `events.jsonl`.

---

# 20. Authoritative world inertness remains required

Because 111 still only interprets knowledge and records a response:

> Prompt evaluation must remain behaviorally inert to the existing autonomous war simulation.

Paired runs with evaluation enabled/disabled must retain identical:

```text
events.jsonl
authoritative entity IDs
final WorldState
local decisions
needs
messages
shipments
arbitration
resource ledger
```

Only prompt-specific projection/event artifacts may differ.

No normalization.

---

# 21. PlayerObserver separation remains absolute

A crucial test:

```text
PlayerObserver sees something alarming
Operational Command has no delivered supported report
```

Then:

```text
REQUEST_ASSESSMENT
→ FURTHER_INFORMATION_REQUIRED
```

The command may not answer using what the player saw.

This is the foundation for later:

> question → information requirement → reconnaissance mission.

---

# 22. Required Scenario A — attention, known active concern

Operational Command has a delivered ACTIVE ammunition need report for `AREA_FRONT_C`.

Submit:

```text
DIRECT_ATTENTION AREA_FRONT_C
```

At next evaluation boundary:

```text
KNOWN_CONCERN_PRESENT
ACTIVE_AMMO_SUPPLY_CONCERN
```

Provenance cites the delivered current report.

No new military action occurs.

---

# 23. Required Scenario B — assessment available

Same knowledge state.

Submit:

```text
REQUEST_ASSESSMENT AREA_FRONT_C
```

Expected:

```text
ASSESSMENT_AVAILABLE
ACTIVE_AMMO_SUPPLY_PROBLEM
```

No exact quantity exposed in PlayerPromptView.

---

# 24. Required Scenario C — player sees it, command does not

Construct:

```text
PlayerObserverView contains visible/qualitative activity in AREA_FRONT_C
```

while Operational Command has no supported delivered report for that area.

Submit:

```text
REQUEST_ASSESSMENT
```

Expected:

```text
FURTHER_INFORMATION_REQUIRED
NO_SUPPORTED_AREA_INFORMATION
```

This is a primary acceptance case.

---

# 25. Required Scenario D — resolved knowledge

Deliver a valid need report and later its valid resolution to Operational Command before evaluation.

Expected:

For `DIRECT_ATTENTION`:

```text
NO_ACTIVE_KNOWN_CONCERN
LAST_KNOWN_AMMO_NEED_RESOLVED
```

For `REQUEST_ASSESSMENT`:

```text
ASSESSMENT_AVAILABLE
KNOWN_AMMO_NEED_RESOLVED
```

No claim that objective battlefield conditions are safe.

---

# 26. Required Scenario E — boundary delivery

Arrange a supported report to arrive exactly at a 1.0-second evaluation boundary while a prompt is pending.

Required ordering:

```text
message delivered
→ superior report projection updated
→ prompt evaluated
```

Evaluation must use that newly delivered report.

---

# 27. Required Scenario F — same prompt, different knowledge

Use otherwise equivalent worlds.

### Run 1

Operational Command has delivered ACTIVE report.

### Run 2

Same objective front state, but report has not reached Operational Command.

Submit identical:

```text
REQUEST_ASSESSMENT
```

Expected:

```text
Run 1 → ASSESSMENT_AVAILABLE

Run 2 → FURTHER_INFORMATION_REQUIRED
```

This proves evaluation follows command knowledge, not objective truth.

---

# 28. Required Scenario G — stale delivered report

Deliver an ACTIVE report, then change subordinate reality without delivering the update before prompt evaluation.

Expected:

```text
command evaluates from stale ACTIVE report
```

and returns the corresponding known concern/assessment.

Journal exact report/revision used.

Do not query subordinate truth.

---

# 29. Required Scenario H — authoritative inertness

Compare equivalent autonomous runs with:

```text
prompt evaluation disabled
```

versus:

```text
prompt evaluation enabled
```

using identical valid prompts.

Require byte-identical:

```text
events.jsonl
final authoritative world
all core IDs and accepted 2B behavior
```

Prompt-specific stream/projection differs only by evaluation events/state.

---

# 30. Required Scenario I — strict replay

Fresh-process replay must reproduce exactly:

```text
prompt records
evaluation IDs
evaluation result/order
provenance report IDs
player prompt view
recipient prompt view
prompt event stream
input history

109 player observation stream/view

authoritative world stream/state
all existing 2B projections
```

No tolerance.

---

# 31. Regression compatibility

With:

```text
strategic_prompt_evaluation_enabled = false
```

accepted 110 fixtures must continue to end:

```text
PENDING_EVALUATION
```

with no fabricated `PLAYER_PROMPT_EVALUATED`.

This compatibility check is required.

---

# 32. No information missions yet

`FURTHER_INFORMATION_REQUIRED` is a **result only**.

Do not turn it into:

- recon patrol;
- reconnaissance request;
- scout task;
- spy plane;
- analysis-team task;
- subordinate message;
- command order.

That comes next.

---

# 33. No richer prompt vocabulary

Do not add:

```text
CONSIDER_ATTACK
CONSIDER_RECON
CONSIDER_DEFEND
REINFORCE
WITHDRAW
```

111 continues to use only the two accepted 110 prompt types.

---

# 34. No greybox player battlefield UI yet

Headless/demo fixtures remain sufficient for 111.

Optional developer-inspector representation is fine if trivial.

Do not delay acceptance for UI.

---

# 35. GDD housekeeping

Administrative and nonblocking.

The requested Generation 2 PDF/DOCX remained unavailable in the developer environment during 109/110.

If they are still unavailable, record:

```text
GDD housekeeping pending — source files unavailable
```

Do not fabricate them.

---

# 36. Integrity requirements

Verify:

- no PlayerObserver data enters evaluation;
- no raw WorldState enters evaluation;
- report provenance is exact;
- no exact-number leakage through player projection metadata;
- evaluator produces no InformationRecords;
- evaluator produces no command messages;
- conservation remains unchanged;
- event-only prompt reconstruction works;
- strict replay works.

---

# 37. 111 acceptance gate

111 is complete only when:

### Evaluation
- enabled Operational Command evaluates pending prompts at exact 1-second cadence;
- each prompt evaluates exactly once;
- both prompt types follow the specified policy.

### Knowledge boundary
- only delivered command knowledge drives results;
- player-visible truth cannot answer for the commander;
- stale delivered information may legitimately drive an answer.

### Inspectability
- result and assessment code are recorded;
- exact delivered reports/revisions used are reconstructable.

### Inertness
- evaluation does not change military behavior;
- authoritative world events/IDs remain byte-identical in paired runs.

### Integrity
- accepted 2A/2B/109/110 regression foundation remains green;
- conservation/reconstruction/replay remain exact.

---

# 38. Completion report

Save under:

```text
C:\Users\dawso\OneDrive\Desktop\trencho
```

using **111** and established naming.

Include at minimum:

```text
111 completion status

commit SHA
project/schema/Godot

total checks / failures
111-specific checks

Scenario A–I results

prompt IDs
evaluation IDs
evaluation results
assessment codes

report IDs / need IDs / revisions used

player-vs-command knowledge divergence proof
stale-report proof
exact-data leakage result
InformationRecord/message isolation result

byte-identical authoritative inertness result
resource conservation result
event reconstruction result
strict replay result

110 compatibility result
GDD housekeeping result

known limitations
deliberate deviations
```

Preserve the full requirements in repository documentation if that remains convention.

---

# 39. Stop condition

When the full 111 gate passes:

**STOP.**

Do not begin 112.

Do not create information requirements or reconnaissance missions.

Do not make `FURTHER_INFORMATION_REQUIRED` cause an action.

Do not add player-facing battlefield UI.

Return the complete 111 evidence for review.

If accepted, **112 will turn `FURTHER_INFORMATION_REQUIRED` into the first bounded command-generated information requirement**, without yet attempting the full recon-vehicle/aircraft/personnel ecosystem.
