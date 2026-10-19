109 is **accepted**.

The reported evidence satisfies the 109 gate, and the separate observation stream was the right architectural choice. In particular, the byte-identical 3,607-event authoritative comparison with observer mode enabled/disabled is strong evidence that player observation is genuinely presentation-only rather than a hidden AI input.

Preserve accepted 109 at:

```text
a28a078416b5d8e79072201aa3de57487978e904
```

Both frozen acceptance tags remain untouched.

The GDD housekeeping result is nonblocking. Do not fabricate missing documents.

You are authorized to begin **110 only**.

# 110 — Nonbinding Player Prompt Foundation

## 1. Purpose

110 introduces the first actual player-to-command interaction.

It does **not** make commanders act on the prompt yet.

Its job is to establish a deterministic, replayable, nonbinding advisory channel through which the player can say:

```text
"Pay attention here."
```

or:

```text
"What happened here?"
```

without:

- issuing an order;
- injecting battlefield truth;
- changing commander beliefs;
- changing posture;
- changing logistics;
- changing resource allocation.

The intended architecture is:

```text
PLAYER
  ↓
nonbinding prompt
  ↓
OPERATIONAL COMMAND prompt inbox
  ↓
[future 111 evaluation]
```

110 ends before the last step.

---

# 2. Starting point

Begin from accepted 109:

```text
a28a078416b5d8e79072201aa3de57487978e904
```

Expected version progression:

```text
Project 0.3.1
Schema 2C.2
```

if consistent with repository convention.

Preserve:

```text
prototype-gen2-2A-accepted
prototype-gen2-2B-accepted
```

unchanged.

---

# 3. Core design rule

A player prompt is:

> **an advisory request for command attention, not information and not an order.**

Therefore a prompt may tell a commander:

```text
"Please consider AREA_C."
```

but it may not carry:

```text
enemy_strength = 73
ammo_remaining = 12
front_is_collapsing = true
```

even if the player can visually infer something like that.

The commander must later evaluate the area from its **own knowledge**.

---

# 4. Initial prompt vocabulary

Implement exactly two prompt types:

```text
DIRECT_ATTENTION
REQUEST_ASSESSMENT
```

Human-facing concepts:

```text
DIRECT_ATTENTION
≈ "Look here / pay attention here."

REQUEST_ASSESSMENT
≈ "What happened here?"
```

Do not add:

```text
CONSIDER_ATTACK
CONSIDER_DEFEND
CONSIDER_RECON
CONSIDER_WITHDRAW
REINFORCE
RESUPPLY
```

Those belong to later A/B experiments, if needed.

---

# 5. Semantics of DIRECT_ATTENTION

`DIRECT_ATTENTION` means only:

> The player believes this StrategicArea deserves command attention.

It does **not** mean:

- investigate;
- attack;
- reinforce;
- gather recon;
- change posture;
- allocate supplies.

110 records and delivers the prompt.

111 will decide what the commander does with it.

---

# 6. Semantics of REQUEST_ASSESSMENT

`REQUEST_ASSESSMENT` means:

> The player asks the recipient command for its best explanation/assessment of the selected StrategicArea.

For 110 this does **not** produce an answer.

It becomes a pending advisory request.

Do not implement:

- analysis teams;
- recon missions;
- spy planes;
- exact-number disclosure;
- historical investigation;
- commander response text.

Those begin later.

---

# 7. Prompt target

A player prompt targets:

```text
StrategicArea.area_id
```

from 109.

Do not target:

- raw WorldState entities;
- shipment IDs;
- stockpile IDs;
- arbitrary coordinates;
- individual soldiers.

This keeps future interaction attached to the stable battlefield-area abstraction.

---

# 8. Prompt recipient

For 110, the player may address only:

```text
OPERATIONAL
```

level commands.

Do not allow direct prompts to LOCAL commands.

This is important to the intended abstraction:

> The player influences the command institution rather than bypassing it to talk directly to frontline officers.

Later Operational Command may choose to involve subordinates.

That is not implemented yet.

---

# 9. Recipient scope validation

A prompt is valid only when its target area falls within the recipient Operational Command's organizational scope.

For an area with:

```text
front_id != null
```

the responsible command for that front must be:

- the recipient command itself; or
- a descendant of the recipient in the accepted command hierarchy.

For an area without a front, its configured locations must belong to the recipient or its descendant command scope.

Use existing hierarchy/authority relationships.

Do not introduce a second unrelated ownership model just for prompts.

---

# 10. PlayerPrompt entity/projection

Create a persistent, reconstructable prompt projection equivalent to:

```text
PlayerPrompt

prompt_id
prompt_type

area_id
recipient_command_id

submitted_at
received_at

state

source_input_id or equivalent

submitted_event_id
received_event_id

metadata
```

For 110 the normal successful terminal state is:

```text
PENDING_EVALUATION
```

Suggested lifecycle:

```text
SUBMITTED
→ PENDING_EVALUATION
```

You may internally use `RECEIVED` as an intermediate state if useful.

Do not add ACCEPTED/REJECTED/DEFERRED yet.

Those are 111 responsibilities.

---

# 11. No free-form player text

Do not store arbitrary user-authored text in 110.

The input contains structured enums and IDs only.

This avoids turning the prompt system into an uncontrolled information-injection channel.

---

# 12. Player prompt input

Add a deterministic gameplay input equivalent to:

```text
SubmitPlayerPromptInput
```

Minimum fields:

```text
prompt_type
area_id
recipient_command_id
```

Simulation time is determined by the simulation when the input is accepted.

Do not allow the caller to spoof:

```text
submitted_at
received_at
prompt_id
```

---

# 13. Validation

Reject, with structured errors:

```text
UNKNOWN_PROMPT_TYPE
UNKNOWN_STRATEGIC_AREA
DISABLED_STRATEGIC_AREA
UNKNOWN_RECIPIENT_COMMAND
RECIPIENT_NOT_OPERATIONAL
AREA_OUTSIDE_COMMAND_SCOPE
```

or established repository-equivalent reason codes.

Rejected input must:

- create no prompt;
- create no prompt-stream event;
- mutate no gameplay state.

Follow existing ID-allocation convention so failed validation does not create phantom prompt identities.

---

# 14. Prompt delivery model

For the first 2C prototype:

```text
player → operational command delivery latency = 0
```

This is **not** a battlefield communication link.

It represents the player's strategic/advisory interface to the relevant Operational Command.

Do not create a fake command node called PLAYER.

Do not route the prompt through CommunicationGraph.

Do not make the player a superior officer in CommandHierarchy.

The fiction/interface framing can be refined later.

---

# 15. Evaluation timing

Even though receipt is immediate, no accepted command policy evaluates prompts in 110.

Therefore:

```text
prompt received
→ PENDING_EVALUATION
```

and stops there.

In 111 we will define the actual evaluation cadence.

Do not opportunistically hook the prompt into arbitration or local planning.

---

# 16. Dedicated player-prompt stream

Use a separate deterministic prompt event stream.

Preferred conceptual package:

```text
player_prompt_events.jsonl
```

Do **not** insert prompt-submission events into the accepted core authoritative world event sequence merely to log them.

Rationale:

- 110 prompts are not yet behavior-producing;
- we want to prove behavioral inertness without renumbering accepted world IDs;
- later prompt effects can cause legitimate world divergence while the prompt history remains separately reconstructable.

This stream is different from the 109 observation stream.

We now have conceptually:

```text
events.jsonl
    authoritative simulated world

player_observation_events.jsonl
    WORLD → PLAYER presentation

player_prompt_events.jsonl
    PLAYER → COMMAND advisory intent
```

---

# 17. Prompt stream authority

Unlike the 109 observation stream, the 110 prompt stream is **gameplay-relevant player intent**.

It is not merely presentation.

Starting in 111, command AI may consume its projection.

Therefore it must be:

- persisted;
- deterministic;
- included in export;
- included in replay;
- integrity checked;
- treated as part of the run's authoritative player-input history.

But it still must not mutate WorldState directly.

---

# 18. Prompt IDs

Use independent deterministic namespaces/counters equivalent to:

```text
player-prompt:0000000001
player-prompt-event:0000000001
```

Do not allocate these from the core world-event counter.

Do not allocate them from the 109 player-observation counter.

---

# 19. Prompt semantic events

Implement equivalents of:

```text
PLAYER_PROMPT_SUBMITTED
PLAYER_PROMPT_RECEIVED
```

Both live in the prompt stream.

Minimum payload:

```text
prompt_event_id
prompt_id
prompt_type
area_id
recipient_command_id
at
source_input_id or equivalent
previous_prompt_event_id or null
```

The received event should link to the submitted event through the prompt stream's own lineage field.

Do not overload the authoritative world stream's `causation_event_id` semantics.

---

# 20. Prompt event ordering

Successful inputs are ordered by actual accepted input execution order.

If two prompts are submitted at the same simulation time:

```text
first accepted input
→ lower prompt ID

second accepted input
→ next prompt ID
```

Do not resort player actions by:

- area ID;
- prompt type;
- recipient.

Player action order is meaningful.

---

# 21. PlayerPromptView

Create a detached read-only player-facing projection supporting at minimum:

```text
current prompts
recent prompt history
status by prompt_id
```

It may show:

```text
prompt type
area
recipient
submitted time
state
```

It must not expose hidden command knowledge merely because the player submitted a prompt.

---

# 22. Recipient CommandPromptView

Create a detached recipient-scoped prompt view or equivalent.

For:

```text
OPERATIONAL_COMMAND
```

it returns only prompts addressed to that command.

Another command must not see them.

A LOCAL command must not automatically receive them.

Do not insert prompts into `InformationService`.

A prompt is not a fact about the world.

This distinction is important.

---

# 23. Do not make prompts InformationRecords

Forbidden:

```text
DIRECT_ATTENTION
→ InformationRecord(enemy_activity, ...)
```

or:

```text
REQUEST_ASSESSMENT
→ InformationRecord(front_state, ...)
```

The prompt communicates:

> player interest

not:

> battlefield truth.

111 will give Operational Command a separate prompt-evaluation path.

---

# 24. No PlayerObserver payload copying

Do not attach to the prompt:

```text
current PlayerObserverView
qualitative friendly band
qualitative enemy band
visible logistics history
```

The prompt carries only:

```text
type
area
recipient
```

This is deliberate.

The commander cannot infer what the player saw simply because the player pointed somewhere.

---

# 25. No current AI behavior change

109/2B policies must remain unchanged.

Prompts may not influence:

```text
LocalCommandPlanner
DecisionPolicy104
ResourceNeed
peer coordination
escalation
106 arbitration
shipment dispatch
front posture
```

in 110.

---

# 26. Strong inertness requirement

Create equivalent paired runs:

```text
RUN A
no player prompts

RUN B
one or more valid player prompts
```

with otherwise identical:

```text
world
seed
observer configuration
gameplay state
```

Because prompts use their own event namespace and no AI consumes them yet, require:

```text
events.jsonl
= byte-identical

final authoritative world state
= identical

all core authoritative entity IDs
= identical

local decisions
= identical

needs
= identical

messages
= identical

shipments
= identical

arbitration
= identical

resource ledger
= identical
```

Differences are permitted only in:

```text
inputs.jsonl
player_prompt_events.jsonl
final player-prompt projection
manifest hashes describing those differences
```

and any explicitly prompt-specific export file.

Do not use normalization to hide world differences.

---

# 27. Interaction with player observation

109 PlayerObserverView remains independent.

Submitting a prompt must not:

- create player observations;
- modify qualitative bands;
- reveal new information;
- suppress old observations.

Likewise, receiving a player observation does not automatically create a prompt.

The two directions remain:

```text
WORLD → PLAYER
```

and:

```text
PLAYER → COMMAND
```

as separate systems.

---

# 28. Required Scenario A — Direct attention

Setup:

```text
AREA_FRONT_C
OPERATIONAL_COMMAND
```

Submit:

```text
DIRECT_ATTENTION
```

Expected:

```text
prompt created
PLAYER_PROMPT_SUBMITTED
PLAYER_PROMPT_RECEIVED
state = PENDING_EVALUATION
```

Operational recipient view sees it.

No Local command sees it.

No world behavior changes.

---

# 29. Required Scenario B — Request assessment

Submit:

```text
REQUEST_ASSESSMENT
AREA_FRONT_C
```

Expected:

```text
PENDING_EVALUATION
```

No assessment is generated yet.

No recon occurs.

No information record is created.

No exact values are revealed.

---

# 30. Required Scenario C — player can point at something commander does not know

Create a case where PlayerObserverView has already observed a qualitative/visible event in an area that the Operational Command does not currently know in equivalent detail.

Submit:

```text
DIRECT_ATTENTION
```

Expected:

The prompt arrives with only:

```text
AREA_ID
```

Operational Command still does **not** magically acquire:

- the player-visible event;
- exact world truth;
- the player's qualitative observation.

This is a key test.

---

# 31. Required Scenario D — invalid scope

Create an area outside the selected Operational Command's hierarchy.

Expected:

```text
AREA_OUTSIDE_COMMAND_SCOPE
```

No prompt ID/event/state mutation.

Also test:

```text
recipient = LOCAL
```

Expected rejection.

---

# 32. Required Scenario E — multiple prompts same tick

At one simulation time submit:

```text
DIRECT_ATTENTION AREA_A
REQUEST_ASSESSMENT AREA_C
DIRECT_ATTENTION AREA_B
```

in that order.

Expected:

- deterministic sequential prompt IDs;
- event sequence preserves input order;
- recipient view preserves deterministic ordering;
- no hash/dictionary iteration affects IDs.

---

# 33. Required Scenario F — world inertness

Use a meaningful accepted autonomous fixture, preferably the 107/109 integrated hierarchy.

Compare:

```text
no prompts
```

versus:

```text
several valid prompts during the run
```

Expected:

```text
byte-identical authoritative events.jsonl
identical final authoritative world state
```

while prompt-specific artifacts differ exactly as expected.

---

# 34. Required Scenario G — strict replay

Fresh-process replay must reproduce exactly:

```text
all PlayerPrompt records
all prompt-event IDs/order
current PlayerPromptView
recipient CommandPromptView
inputs
final authoritative world state
authoritative world stream
109 player-observation projection/stream
```

No tolerance.

---

# 35. Required Scenario H — no-prompt compatibility

A run with the 110 code present but no player prompts must preserve accepted 109 behavior.

No prompt events should be fabricated simply because the subsystem exists.

An empty prompt stream/file is acceptable according to established package conventions.

---

# 36. Export/package additions

For prompt-enabled runs include equivalents of:

```text
player_prompt_events.jsonl
final_player_prompts.json
```

and whatever validated configuration/projection metadata is necessary.

`inputs.jsonl` must contain the actual prompt submissions.

Update the manifest with prompt stream/projection hashes/schema information using existing package conventions.

Do not alter the 109 observation-stream integrity rules.

---

# 37. Replay integrity

Replay must reject, at minimum:

- forged prompt type;
- forged area ID;
- forged recipient;
- broken prompt-event chain;
- altered prompt-event hash;
- prompt state inconsistent with events;
- source input mismatch;
- prompt event claiming nonexistent prompt ID.

Do not weaken existing importer/comparer contracts.

---

# 38. No response yet

Do not implement any of these 111 concepts:

```text
ASSESSMENT_AVAILABLE
INFORMATION_INSUFFICIENT
FURTHER_INFORMATION_REQUIRED
NO_NEW_CONCERN
ACCEPTED
DEFERRED
REJECTED
```

110 ends with:

```text
PENDING_EVALUATION
```

---

# 39. No information mission yet

Do not implement:

- reconnaissance mission creation;
- scout deployment;
- analysis staff;
- spy planes;
- recon vehicles;
- messengers;
- battlefield investigation;
- risk to recon assets.

Those remain future capability experiments.

---

# 40. No player-visible strategic UI yet

Do not build the actual greybox battlefield interaction interface in 110.

Headless/demo input fixtures are sufficient.

Optional developer inspector support is acceptable if inexpensive.

Do not delay acceptance for presentation.

---

# 41. No economy/deck/procurement

Do not implement:

- factories;
- towns;
- barracks;
- population training;
- procurement toggles;
- procurement quotas;
- exact equipment orders;
- cards;
- fabrication trucks.

Those remain preserved design direction for 2D.

---

# 42. GDD housekeeping reminder

Administrative only.

The human still wants the current Generation 2 GDD stored under:

```text
C:\Users\dawso\OneDrive\Desktop\trencho
```

alongside previous GDD versions.

Requested filenames:

```text
Trencho_Game_Design_Document_Generation_2_v0.1.pdf
Trencho_Game_Design_Document_Generation_2_v0.1.docx
```

109 established that these exact files were not available to your environment.

Do **not** recreate or fabricate them.

If still unavailable, simply record:

```text
GDD housekeeping pending — source files unavailable
```

again.

This is nonblocking.

---

# 43. Required regressions

Run full accepted suite.

Foundation entering 110:

```text
925 checks / 0 failures
```

All previous:

```text
2A
2B
109
```

behavior must remain green.

Any genuine prior-behavior regression is blocking.

---

# 44. 110 acceptance gate

110 is complete only when:

### Prompt foundation
- two prompt types exist;
- StrategicArea is the target;
- only Operational Commands receive prompts;
- scope validation works;
- prompt lifecycle ends at `PENDING_EVALUATION`.

### Information safety
- prompts contain no battlefield truth;
- prompts create no InformationRecords;
- PlayerObserver data is not copied into prompts;
- Local commands do not receive prompts.

### Behavioral inertness
- no accepted AI policy consumes prompts;
- prompt/no-prompt world streams remain byte-identical;
- authoritative IDs/state remain identical.

### Determinism
- input order produces deterministic prompt IDs/events;
- export/replay reconstruct prompts exactly.

### Integrity
- 925-check accepted foundation remains green;
- conservation remains green;
- 109 observation architecture remains unchanged.

---

# 45. Completion report

Save under:

```text
C:\Users\dawso\OneDrive\Desktop\trencho
```

using **110** and the established naming convention.

Include at minimum:

```text
110 completion status

commit SHA
project version
schema version
Godot version

total checks / failures
110-specific checks

Scenario A result
Scenario B result
Scenario C result
Scenario D result
Scenario E result
Scenario F result
Scenario G result
Scenario H result

prompt IDs/types
prompt event counts
recipient/scope results

player-observation separation result
InformationRecord leakage result
Local-command isolation result

byte-identical world inertness result
resource conservation result
strict fresh-process replay result

GDD housekeeping result

known limitations
deliberate deviations
```

Preserve the full 110 requirements in repository documentation if that remains the established convention.

---

# 46. Stop condition — remainder

When the full 110 gate passes:

**STOP.**

Do not begin 111.

Do not make commanders react to prompts.

Do not generate assessments.

Do not create reconnaissance missions.

Do not build the player-facing battlefield UI.

Return the complete 110 evidence for review.

If accepted, **111** will add the first autonomous Operational Command evaluation of these prompts—specifically determining whether command already has sufficient information, whether the prompt raises an actionable concern, or whether additional information would be required—without yet building the full reconnaissance/equipment ecosystem.
