111 is **accepted**.

The evidence satisfies the 111 gate. The key proofs are present: evaluation uses only delivered command knowledge; identical objective state can produce different answers because reports differ; stale delivered information legitimately drives an answer; PlayerObserver data cannot answer on behalf of command; and enabling evaluation leaves the authoritative military simulation byte-identical.

Preserve accepted 111 at:

```text
62d0e95e4330a3ee54d5d63a514e925561a79918
```

Frozen 2A/2B tags remain unchanged. The GDD housekeeping item remains nonblocking.

You are authorized to begin **112 only**.

# 112 — Command-Generated Information Requirement Foundation

## 1. Purpose

112 turns this accepted 111 result:

```text
FURTHER_INFORMATION_REQUIRED
```

into the first persistent command-generated representation of:

> **“I do not currently know enough about this area to answer the player.”**

This is the first step toward:

```text
question
→ knowledge gap
→ information requirement
→ future information-gathering activity
```

112 stops at the **information requirement**.

It does **not** yet create a reconnaissance mission, send scouts, launch aircraft, task analysis staff, or gather new information.

---

## 2. Starting point

Begin from accepted 111:

```text
62d0e95e4330a3ee54d5d63a514e925561a79918
```

Expected progression:

```text
Project 0.3.3
Schema 2C.4
```

Foundation entering 112:

```text
1186 checks / 0 failures
```

Preserve frozen acceptance tags unchanged.

---

# 3. Core semantic distinction

An `InformationRequirement` is **not information**.

It represents:

> a command's recognized knowledge gap.

Therefore it must never be inserted into `InformationService` as a fact.

Example:

```text
Requirement:
"We need a better situation assessment of AREA_FRONT_C."
```

does not imply:

```text
enemy strength known
ammo shortage known
collapse confirmed
```

This distinction is mandatory.

---

# 4. Initial requirement type

Implement exactly one requirement type:

```text
AREA_SITUATION_ASSESSMENT
```

Meaning:

> Operational Command wants enough legitimate information to make a useful assessment of the selected StrategicArea.

Do not introduce separate:

```text
ENEMY_STRENGTH_REQUIREMENT
AMMO_REQUIREMENT
CASUALTY_REQUIREMENT
RECON_REQUIREMENT
ATTACK_FEASIBILITY_REQUIREMENT
```

yet.

---

# 5. Creation trigger

A requirement may be generated only when an enabled 111 prompt evaluation produces:

```text
FURTHER_INFORMATION_REQUIRED
```

with:

```text
NO_SUPPORTED_AREA_INFORMATION
```

for either accepted prompt type:

```text
DIRECT_ATTENTION
REQUEST_ASSESSMENT
```

Both are eligible.

Rationale:

Even a simple “look here” may cause command to recognize that it lacks enough information to meaningfully evaluate the area.

---

# 6. No requirement for supported knowledge

Do not create a requirement when 111 returns:

```text
KNOWN_CONCERN_PRESENT
ASSESSMENT_AVAILABLE
NO_ACTIVE_KNOWN_CONCERN
```

Command already has enough supported information for the bounded 111 policy.

---

# 7. Separate opt-in configuration

Add an Operational-command 112 configuration equivalent to:

```text
strategic_information_requirements_enabled
```

Default:

```text
false
```

Use the same architectural pattern approved for 111:

```text
raw definition
→ extract/validate 112 config
→ strip it
→ canonical WorldDefinition
```

The flag must not enter canonical command records, WorldState, `COMMAND_CREATED`, or authoritative world IDs.

Persist it in an explicitly 2C/prompt-specific configuration artifact.

Only Operational Commands may enable it.

---

# 8. Requirement record

Create a persistent/reconstructable record equivalent to:

```text
InformationRequirement

requirement_id
requirement_type

owner_command_id
area_id

state

created_at
last_updated_at

source_prompt_ids[]
source_evaluation_ids[]

creation_reason

metadata
```

For 112:

```text
state = OPEN
creation_reason = PLAYER_PROMPT_INFORMATION_GAP
```

No other lifecycle states are required yet.

---

# 9. Requirement IDs

Use an independent deterministic namespace/counter, e.g.:

```text
information-requirement:0000000001
```

Do not allocate IDs from:

- authoritative world counter;
- prompt counter;
- prompt-event counter;
- player-observation counter.

---

# 10. Requirement event stream

Use a separate append-only persisted stream, naming flexible, e.g.:

```text
information_requirement_events.jsonl
```

Do not add requirement events to authoritative `events.jsonl`.

Minimum semantic events:

```text
INFORMATION_REQUIREMENT_OPENED
INFORMATION_REQUIREMENT_LINKED
```

`LINKED` is used when another prompt/evaluation discovers the same still-open knowledge gap.

---

# 11. Cross-stream provenance

Every requirement must retain exact provenance to the 111 evaluation that caused or linked it.

For `OPENED`, record:

```text
requirement_id
owner_command_id
area_id
requirement_type

source_prompt_id
source_evaluation_id

created_at
```

For `LINKED`, record the additional:

```text
source_prompt_id
source_evaluation_id
```

Do not pretend these IDs are same-stream causal events.

Explicit typed references are preferred.

---

# 12. Duplicate suppression

There may be at most one OPEN requirement for:

```text
owner_command_id
+
area_id
+
requirement_type
```

If another qualifying evaluation occurs for that same key:

```text
do not create a second requirement
```

Instead:

```text
append prompt/evaluation provenance to existing requirement
emit INFORMATION_REQUIREMENT_LINKED
update last_updated_at
```

This prevents:

> repeated “what happened here?” clicks → hundreds of duplicate intelligence tasks.

This is an important anti-micromanagement foundation.

---

# 13. Deterministic provenance ordering

Maintain:

```text
source_prompt_ids[]
source_evaluation_ids[]
```

in deterministic first-link order.

Do not sort them afterward if that destroys actual interaction chronology.

Duplicate source IDs must not be appended twice.

---

# 14. Timing

Requirement generation occurs immediately after the corresponding 111 evaluation at the same whole-second evaluation boundary.

Ordering:

```text
1. command messages/reports due at boundary
2. superior report projections update
3. prompt evaluation
4. qualifying InformationRequirement open/link
5. accepted arbitration continues
```

Requirement generation must not delay or reorder arbitration.

---

# 15. Input boundary

112 adds **no new player input type**.

The only player inputs remain:

```text
DIRECT_ATTENTION
REQUEST_ASSESSMENT
```

A requirement is generated autonomously by command from the evaluation result.

The player may not directly submit:

```text
CreateInformationRequirement
LaunchRecon
InvestigateArea
```

---

# 16. No hidden player observation payload

A generated requirement contains:

```text
area_id
prompt/evaluation provenance
```

It must not copy:

```text
PlayerObserverView cues
enemy activity band
friendly presence band
visible convoy history
exact world truth
```

The command knows only that it lacks supported information about the selected area.

---

# 17. Requirement ownership

The requirement is owned by the Operational Command that evaluated the prompt.

Do not assign it directly to the area's LOCAL command.

Future work may let the Operational Command choose how to satisfy it.

That decision is intentionally not part of 112.

---

# 18. Frontless areas

A frontless StrategicArea that produced:

```text
FURTHER_INFORMATION_REQUIRED
```

may create a normal:

```text
AREA_SITUATION_ASSESSMENT
```

requirement.

112 does not need to know how such a requirement will eventually be fulfilled.

---

# 19. InformationRequirementView

Create a detached recipient-scoped read-only projection supporting at minimum:

```text
open requirements for Operational Command
requirement by ID
recent requirement event/history
```

Another Operational Command must not see requirements it does not own.

LOCAL commands receive none automatically.

---

# 20. Optional player exposure

Do **not** build a new player UI.

It is acceptable for the existing prompt-facing projection to continue showing only:

```text
FURTHER_INFORMATION_REQUIRED
```

The player does not need direct access to internal `InformationRequirement` IDs yet.

Developer diagnostics may expose them.

---

# 21. No fulfillment in 112

Requirements remain:

```text
OPEN
```

for the duration of 112 fixtures.

Do not automatically satisfy them if a later report arrives.

Do not close them because time passed.

Do not create:

```text
SATISFIED
FAILED
EXPIRED
CANCELLED
```

yet.

Lifecycle completion belongs with the first actual collection pathway.

---

# 22. No military action

Creating/linking a requirement must not itself cause:

```text
messages
recon missions
shipments
resource reservations
posture changes
local decisions
arbitration changes
```

It is a command work item only.

---

# 23. No InformationRecords

Verify explicitly:

```text
InformationRequirement
≠
InformationRecord
```

Creation/linking must produce zero new command belief facts.

---

# 24. Authoritative inertness

112 must preserve the same strong boundary established in 109–111.

Compare equivalent worlds with information-requirement generation enabled versus disabled.

Require byte-identical:

```text
initial_world.json
events.jsonl
final_world.json

core authoritative entity IDs
local decisions
needs
communications
shipments
arbitration
resource ledger
```

Differences are allowed only in the separate 112 config/requirement artifacts and related manifest hashes.

No normalization.

---

# 25. Required Scenario A — assessment opens requirement

Operational Command lacks supported information for `AREA_FRONT_C`.

Submit:

```text
REQUEST_ASSESSMENT
```

111 result:

```text
FURTHER_INFORMATION_REQUIRED
NO_SUPPORTED_AREA_INFORMATION
```

Expected 112 result:

```text
information-requirement:0000000001

type = AREA_SITUATION_ASSESSMENT
owner = OPERATIONAL_COMMAND
area = AREA_FRONT_C
state = OPEN
```

with exact prompt/evaluation provenance.

---

# 26. Required Scenario B — attention also opens requirement

Submit:

```text
DIRECT_ATTENTION
```

to another unsupported area.

Expected:

```text
FURTHER_INFORMATION_REQUIRED
→ one OPEN AREA_SITUATION_ASSESSMENT requirement
```

No automatic action follows.

---

# 27. Required Scenario C — known information creates no requirement

Use delivered ACTIVE need knowledge.

Expected 111 result:

```text
KNOWN_CONCERN_PRESENT
```

or:

```text
ASSESSMENT_AVAILABLE
```

Expected 112:

```text
0 new requirements
```

---

# 28. Required Scenario D — duplicate same-area prompts

Submit multiple qualifying prompts against the same area.

Example:

```text
REQUEST_ASSESSMENT AREA_C
DIRECT_ATTENTION AREA_C
REQUEST_ASSESSMENT AREA_C
```

Expected:

```text
1 OPEN requirement
3 prompt/evaluation provenance links
1 INFORMATION_REQUIREMENT_OPENED
2 INFORMATION_REQUIREMENT_LINKED
```

No duplicate task creation.

---

# 29. Required Scenario E — different areas

Submit qualifying prompts for:

```text
AREA_A
AREA_B
AREA_C
```

Expected:

```text
3 independent requirements
```

IDs follow deterministic evaluation order.

---

# 30. Required Scenario F — player observation leakage

PlayerObserverView visibly contains activity for AREA_C.

Operational Command lacks supported delivered knowledge.

Prompt produces a requirement.

Verify requirement contains no copied observer cue or objective-world fact.

---

# 31. Required Scenario G — multiple Operational Commands

Two Operational Commands independently receive unsupported prompts for areas in their respective scopes.

Expected:

- separate requirement ownership;
- separate recipient views;
- no cross-command visibility;
- deterministic global requirement IDs according to evaluation order.

---

# 32. Required Scenario H — authoritative inertness

Use a meaningful autonomous fixture.

Run:

```text
requirements disabled
```

versus:

```text
requirements enabled
```

with identical prompts/evaluations.

Require byte-identical authoritative artifacts and military behavior.

Requirement stream/projection differs as intended.

---

# 33. Required Scenario I — strict replay

Fresh-process replay must reproduce exactly:

```text
InformationRequirement IDs
OPENED/LINKED events
source prompt/evaluation provenance
recipient requirement views

111 prompt evaluations
110 prompt history
109 player observation stream/view

authoritative world stream/state
all existing 2B projections
```

No tolerance.

---

# 34. Required Scenario J — zero qualifying evaluations

Enable requirement generation but submit either:

- no prompts; or
- prompts that evaluate with supported knowledge.

Expected:

```text
0 requirements
0 requirement events
```

Configuration alone is inert.

---

# 35. Export additions

Prompt-enabled 112 packages should include equivalents of:

```text
information_requirement_events.jsonl
final_information_requirements.json
player_prompt_information_requirement_config.json
```

Naming may follow repository conventions.

Manifest must include schema/hash information.

No changes to 109/110/111 stream integrity contracts.

---

# 36. Replay integrity

Reject at minimum:

- forged requirement ID;
- unknown owner command;
- unknown area;
- unsupported requirement type;
- invalid state;
- broken OPENED/LINKED lineage;
- nonexistent source prompt;
- nonexistent source evaluation;
- evaluation that did not produce `FURTHER_INFORMATION_REQUIRED`;
- duplicate OPEN requirement for the same key;
- projection inconsistent with event stream;
- altered hashes.

Do not weaken existing importers/comparers.

---

# 37. Explicit non-goals

Do **not** implement in 112:

- reconnaissance missions;
- recon infantry;
- recon vehicles;
- aircraft;
- analysis teams;
- messengers;
- information-request messages to subordinates;
- information requirement fulfillment;
- requirement prioritization;
- requirement urgency;
- resource cost;
- risk/failure of collection;
- exact player assessment numbers;
- player battlefield UI;
- attack/defend/recon prompt vocabulary;
- economy;
- procurement;
- deck/cards.

---

# 38. GDD housekeeping

Still administrative/nonblocking.

If the requested GDD files remain unavailable to the developer environment, report:

```text
GDD housekeeping pending — source files unavailable
```

Do not fabricate them.

---

# 39. Regression requirement

Run the full suite.

Foundation entering 112:

```text
1186 checks / 0 failures
```

All accepted 2A/2B/109/110/111 behavior remains green.

Any genuine prior behavior regression is blocking.

---

# 40. 112 acceptance gate

112 is complete only when:

### Requirement generation
- qualifying `FURTHER_INFORMATION_REQUIRED` evaluations create an OPEN requirement;
- unsupported attention and assessment prompts both work;
- supported evaluations create none.

### Deduplication
- repeated prompts for the same command/area link to one requirement;
- provenance remains complete and ordered.

### Isolation
- requirement is not an InformationRecord;
- no PlayerObserver/world truth enters it;
- LOCAL commands do not automatically receive it.

### Inertness
- requirement generation causes no military action;
- authoritative world artifacts remain byte-identical in paired runs.

### Integrity
- exact export/reconstruction/replay passes;
- accepted regression foundation remains green;
- conservation remains unchanged.

---

# 41. Completion report

Save under:

```text
C:\Users\dawso\OneDrive\Desktop\trencho
```

using **112** and the established naming convention.

Include at minimum:

```text
112 completion status

commit SHA
project/schema/Godot

total checks / failures
112-specific checks

Scenario A–J results

requirement IDs
requirement event counts
OPENED/LINKED results

prompt/evaluation provenance results
duplicate suppression result
recipient isolation result

PlayerObserver leakage result
InformationRecord isolation result

byte-identical authoritative inertness result
resource conservation result
event reconstruction result
strict replay result

111 compatibility result
GDD housekeeping result

known limitations
deliberate deviations
```

Preserve the full requirements in repository documentation.

---

# 42. Stop condition

When the full 112 gate passes:

**STOP.**

Do not begin 113.

Do not send the information requirement to a subordinate.

Do not choose a reconnaissance method.

Do not create a mission.

Do not consume personnel/equipment/resources.

Do not build the battlefield UI.

Return the complete 112 evidence for review.

If accepted, **113 will introduce the first deliberately tiny information-acquisition pathway** so one OPEN information requirement can cause command to obtain additional legitimate information. We will keep that first collector intentionally simple rather than prematurely implementing recon infantry, vehicles, aircraft, analysis staff, and all their production chains at once.
