Based on the reported evidence, **114 is accepted**.

The reported results satisfy the 114 gate, including the difficult integrity point: later inquiry cycles preserve the accepted 110/111 event identities and 112/113 typed provenance, while follow-ups remain additive and independently identifiable. The stale-report case also demonstrates the intended information model: the player can receive a legitimate command assessment that differs from current observable reality because command is reporting what it actually learned.

Preserve accepted 114 at:

```text
0a37a78d77af903f1d3148288591514642fe03bd
```

Frozen 2A/2B tags remain unchanged. GDD housekeeping remains nonblocking.

You are authorized to begin **115 only**.

# 115 — Greybox Battlefield Observer & Player Interaction Surface

## 1. Purpose

115 is the first deliberately player-facing 2C implementation.

It connects the already accepted architecture into a usable greybox loop:

```text
watch battlefield areas
↓
select an area
↓
"Look Here"
or
"What Happened Here?"
↓
existing 110–114 systems execute
↓
player sees command's qualitative response
```

115 does **not** add new simulation intelligence.

Its primary job is presentation and interaction.

The UI must consume the accepted projections rather than bypassing them.

---

## 2. Starting point

Begin from accepted 114:

```text
0a37a78d77af903f1d3148288591514642fe03bd
```

Expected progression:

```text
Project 0.3.6
Schema 2C.7
```

unless repository versioning requires an equivalent increment.

Foundation:

```text
1669 checks / 0 failures
```

Preserve frozen 2A/2B tags unchanged.

---

# 3. Governing architectural boundary

The player UI must operate through:

```text
PlayerObserverView
PlayerPromptView
accepted prompt submission API
```

and any narrowly defined detached presentation/routing projection required for 115.

Forbidden:

```text
UI → WorldState
UI → AbstractFront
UI → InformationService
UI → LocalCommandPlanner
UI → SuperiorNeedReport internals
UI → shipment registry
```

The UI is not a privileged developer inspector.

---

# 4. Presentation philosophy

115 should communicate:

> **You can see the war, but you do not automatically know everything about it.**

Therefore the screen may make battlefield activity visually obvious while withholding exact internal quantities and command knowledge.

This is the working observer-view hypothesis, not a final locked art direction.

Use functional greybox graphics only.

Do not begin final art production.

---

# 5. Greybox battlefield screen

Create one primary gameplay scene/screen containing at minimum:

```text
battlefield / operational area
StrategicArea representations
selected-area panel
command interaction controls
recent command-response/history panel
```

It should be understandable without opening developer/debug inspectors.

---

# 6. StrategicArea representation

Every enabled player-observable StrategicArea should have a selectable greybox representation.

Minimum visible area information:

```text
display name
friendly presence: LOW / MEDIUM / HIGH
enemy activity: LOW / MEDIUM / HIGH
front behavior:
    HOLDING
    PRESSING
    REDUCED_ACTIVITY
    WITHDRAWING
```

For non-front/HQ areas, display only information that legitimately exists in `PlayerObserverView`.

Do not manufacture front values for HQ.

---

# 7. Area placement

109 intentionally did not make battlefield coordinates authoritative.

Therefore 115 presentation placement must remain separate from simulation state.

Use one of these approved approaches:

1. a version-controlled presentation-only layout keyed by `area_id`; or
2. a deterministic greybox auto-layout.

If using explicit layout configuration, it must:

- live outside canonical WorldState;
- not allocate authoritative IDs;
- not affect replay;
- contain presentation geometry only;
- validate unknown/duplicate area IDs.

Do not add coordinates to `StrategicArea` merely for 115 UI.

---

# 8. Visual language

Use simple Godot-native greybox elements:

```text
panels
lines
labels
basic icons/shapes
progress-style categorical indicators
```

No external art dependency is required.

Do not spend significant time polishing:

- textures;
- animation;
- particles;
- final typography;
- historical uniforms;
- final map art.

The purpose is interaction evaluation.

---

# 9. No false precision

Do not visualize qualitative state in a way that implies unavailable precision.

For example, if:

```text
friendly_presence = MEDIUM
```

do not display a bar at `57%`.

Acceptable:

```text
[LOW] [MEDIUM] [HIGH]
```

or a three-step categorical marker.

Same rule for enemy activity and ammo assessment.

---

# 10. Visible logistics

Expose the accepted 109 qualitative logistics observations.

Examples:

```text
SUPPLY DEPARTURE
SUPPLY ARRIVAL
SUPPLY LOSS
```

A short-lived visual marker, area event badge, or recent-event line is sufficient.

Do not show:

```text
shipment quantity
cargo subtype
exact source stock
exact destination stock
reservation amount
```

Do not invent interpolation for shipments whose physical location is not represented.

---

# 11. Area selection

The player must be able to select an enabled StrategicArea with normal mouse interaction.

Selection changes only local UI state.

It is **not** a simulation input.

Therefore merely selecting/deselecting areas must:

```text
create no prompt
create no world event
create no InformationRecord
change no command behavior
```

---

# 12. Selected-area panel

For a selected front area, show the current accepted qualitative observer state.

Recommended structure:

```text
AREA NAME

Friendly Presence: HIGH
Enemy Activity: MEDIUM
Activity: PRESSING

Recent visible activity:
- Supply arrival
- Supply departure
```

Do not show exact timestamps with unnecessary simulation precision if that harms readability; relative or simple simulation-time presentation is acceptable.

Do not reveal internal IDs.

---

# 13. Player interactions

Expose exactly two strategic interactions:

```text
LOOK HERE
WHAT HAPPENED HERE?
```

Internally these map exactly to:

```text
DIRECT_ATTENTION
REQUEST_ASSESSMENT
```

No other battlefield command buttons.

Do not add:

```text
Attack
Defend
Withdraw
Reinforce
Resupply
Recon
Move
Hold Position
```

---

# 14. Interaction wording

Player-facing wording should reinforce that these are requests, not orders.

Approved conceptual labels:

```text
Look Here
What Happened Here?
```

A short tooltip/subtext may explain:

```text
Look Here:
Ask command to give this area attention.

What Happened Here?:
Ask command for its current assessment.
```

Do not phrase them as imperative military orders.

---

# 15. Recipient routing

The player should not manually choose raw command IDs.

For a selected area, the UI should route through a detached presentation/routing layer to the appropriate eligible Operational Command using the accepted 110 scope rules.

For front-associated areas, preferred routing is:

```text
responsible Local
→ nearest eligible Operational ancestor
```

provided that Operational Command can validly receive the prompt under 110.

For frontless areas, use existing accepted location/scope relationships.

If there is no unique valid Operational recipient:

```text
disable interaction controls
```

and show a qualitative UI state such as:

```text
Command channel unavailable
```

Do not expose raw validation IDs to the normal player.

Do not create a new ownership hierarchy.

---

# 16. Actual submission path

Clicking either interaction must use the real accepted prompt submission path from 110.

The UI may not directly create:

```text
PlayerPrompt
InformationRequirement
InformationCollectionAttempt
InformationRecord
```

Expected path:

```text
button click
→ SubmitPlayerPrompt
→ accepted validation
→ prompt stream
→ 111+
```

---

# 17. Click safety

One intentional click generates one submission attempt.

Avoid accidental duplicate submissions caused by:

- button repeat;
- double signal connections;
- scene redraw;
- projection refresh.

Do not add cooldown mechanics merely to conceal duplicate-event bugs.

---

# 18. Submission feedback

Immediately after a valid submission, provide non-authoritative UI acknowledgement such as:

```text
Attention request sent
```

or:

```text
Assessment requested
```

This UI acknowledgement is not a command response.

Keep it distinct from later:

```text
PENDING_EVALUATION
FURTHER_INFORMATION_REQUIRED
ASSESSMENT_AVAILABLE
```

---

# 19. Prompt history panel

Show recent player-command interactions for the selected area.

At minimum distinguish:

```text
request submitted
pending evaluation
initial command result
follow-up assessment, if any
```

Use normal language where practical.

Example:

```text
You asked: What happened here?
Command: Further information required.
Command: Assessment now available.
```

The underlying record remains structured.

---

# 20. 111 immediate assessment presentation

If a `REQUEST_ASSESSMENT` produces an immediate accepted 111:

```text
ASSESSMENT_AVAILABLE
ACTIVE_AMMO_SUPPLY_PROBLEM
```

the UI may show an equivalent qualitative message:

```text
Command reports an active ammunition supply problem.
```

Likewise:

```text
KNOWN_AMMO_NEED_RESOLVED
```

may be represented as:

```text
Command reports the previously known ammunition need as resolved.
```

Do not imply objective certainty.

---

# 21. Further-information presentation

For:

```text
FURTHER_INFORMATION_REQUIRED
NO_SUPPORTED_AREA_INFORMATION
```

show wording equivalent to:

```text
Command does not currently have enough information to assess this area.
```

Do not claim:

```text
Recon mission launched
Scouts dispatched
Investigation underway
```

unless that information is actually exposed through an accepted player-facing projection.

113's current subordinate-report collection remains internal.

---

# 22. 114 follow-up presentation

When a legitimate 114 follow-up arrives, display:

```text
Assessment available
Friendly presence: ...
Enemy activity: ...
Activity: ...
Ammo condition: ...
```

using only the accepted qualitative follow-up projection.

Also show, in player-understandable form, that the assessment reflects when the underlying report was observed.

Example:

```text
Based on a report observed at 00:03
```

Do not expose:

```text
collection ID
message ID
InformationRecord IDs
exact centi-strength
exact pressure
exact ammo coverage
```

---

# 23. Preserve disagreement

Do not reconcile:

```text
PlayerObserverView
```

against:

```text
command follow-up assessment
```

If the observer currently sees:

```text
Enemy Activity: HIGH
```

while command's acquired report says:

```text
Enemy Activity: MEDIUM
```

display the mismatch honestly.

Do not silently update one to agree with the other.

This is a major intended gameplay signal.

---

# 24. No automatic explanation of mismatch

115 should not add explanatory text like:

```text
Command is wrong because its information is stale.
```

unless that is explicitly derivable from player-facing information.

Showing:

```text
Observer view: HIGH
Command assessment: MEDIUM
Report observed earlier
```

is sufficient.

Let the player infer the discrepancy.

---

# 25. Attention-only behavior

`LOOK HERE` may produce command evaluation internally, but it must not be rendered as though the player requested a full assessment.

If command already knows a concern, a small acknowledgement/status is acceptable.

Do not turn `LOOK HERE` into a hidden duplicate of `WHAT HAPPENED HERE?`.

---

# 26. Interaction variants for later A/B testing

Preserve two presentation modes:

```text
ATTENTION_ONLY
ATTENTION_AND_INQUIRY
```

These are UI/presentation configurations only.

### ATTENTION_ONLY

Expose:

```text
Look Here
```

only.

### ATTENTION_AND_INQUIRY

Expose both:

```text
Look Here
What Happened Here?
```

Default 115 development/demo mode may be:

```text
ATTENTION_AND_INQUIRY
```

Do not yet declare one variant superior.

Do not add artificial command points, cooldowns, or prompt budgets.

---

# 27. Variant configuration

If a variant flag/config is implemented, keep it outside WorldState/canonical simulation.

Changing presentation variant with no submitted prompts must not alter:

```text
events.jsonl
WorldState
command knowledge
prompt history
resource behavior
```

---

# 28. UI local state

UI-only state may include:

```text
selected_area_id
open/closed panel state
scroll position
presentation variant
```

This state does not need to enter deterministic simulation replay.

Do not contaminate gameplay input history with ordinary UI navigation.

---

# 29. Replay behavior

Simulation replay does not need to reproduce:

```text
mouse cursor movement
area selection
panel scrolling
```

It must reproduce the accepted gameplay state that the UI reads:

```text
PlayerObserverView
PlayerPromptView
114 follow-ups
```

Opening the UI after replay must render that reconstructed state correctly.

---

# 30. No developer data leakage

The normal player UI must contain no toggle/button/shortcut that exposes:

```text
WorldState dump
all InformationRecords
exact stock values
exact shipment quantities
AI candidate scores
need quantities
report/message IDs
```

A separate existing developer inspector may continue to exist.

Do not embed developer inspection into the player-facing scene.

---

# 31. Keyboard/debug shortcuts

Any developer-only shortcut must be clearly separated from normal player controls and disabled from the player-facing production scene by default.

No hidden "press F3 to reveal omniscient values" feature in 115.

---

# 32. Autonomous-zero-input behavior

Launching the greybox battlefield and doing nothing must still permit the autonomous simulation to run.

The UI must not block simulation progression awaiting player input.

This remains a core product invariant:

> **The war continues without the player.**

---

# 33. No-click inertness

Compare:

```text
headless/normal autonomous run
```

against:

```text
greybox UI open, zero player interaction
```

with otherwise identical setup.

Require equivalent authoritative simulation behavior.

Opening/rendering the UI must not:

- submit prompts;
- pause command AI;
- alter timing;
- change resources.

---

# 34. Selection inertness

Run a graphical/scripted case that:

```text
selects A
selects B
selects C
deselects
```

without pressing interaction buttons.

Expected:

```text
0 prompt inputs
0 prompt events
0 military changes attributable to UI selection
```

---

# 35. Required Scenario A — initial observer screen

Launch graphical greybox fixture with at least:

```text
AREA_FRONT_A
AREA_FRONT_B
AREA_FRONT_C
AREA_HQ
```

Expected:

- all enabled areas visible/selectable;
- front qualitative cues match `PlayerObserverView`;
- no exact hidden values visible;
- simulation continues unattended.

Capture evidence of actual rendered UI.

---

# 36. Required Scenario B — Look Here

Select a supported front.

Click:

```text
LOOK HERE
```

Expected:

```text
one DIRECT_ATTENTION submission
```

through the accepted input path.

UI shows submission/state feedback.

No direct posture/resource mutation occurs.

---

# 37. Required Scenario C — What Happened Here, immediate knowledge

Use an area where Operational Command already has supported 111 knowledge.

Click:

```text
WHAT HAPPENED HERE?
```

Expected player-visible command assessment from accepted existing knowledge.

No 112 requirement or 113 collection should be created if 111 does not return `FURTHER_INFORMATION_REQUIRED`.

---

# 38. Required Scenario D — full delayed inquiry loop

Use an unsupported area.

Click:

```text
WHAT HAPPENED HERE?
```

Visibly demonstrate:

```text
request submitted
↓
command lacks enough information
↓
later legitimate 114 follow-up appears
```

The UI must update from projection changes without requiring scene reload.

---

# 39. Required Scenario E — stale/disagreeing assessment

Create the accepted style of case where:

```text
current PlayerObserver enemy activity = HIGH
command acquired assessment = MEDIUM
```

Expected:

Both remain visibly distinct.

No reconciliation or hidden truth substitution.

This is a primary 115 experience proof.

---

# 40. Required Scenario F — failed acquisition

Use a no-route/failed-report case.

Expected UI:

```text
initial FURTHER_INFORMATION_REQUIRED remains
```

and no fabricated follow-up appears.

Do not display "assessment available."

---

# 41. Required Scenario G — DIRECT_ATTENTION vs inquiry distinction

On equivalent areas:

```text
LOOK HERE
```

and:

```text
WHAT HAPPENED HERE?
```

must produce visibly distinguishable interaction history.

Successful collection triggered by attention must not magically create an inquiry-style player assessment.

---

# 42. Required Scenario H — no exact-value leakage

Automated UI tree/text inspection should verify absence of exact fixture sentinel values for:

```text
strength
enemy pressure
coverage milliseconds
shortage amount
shipment quantity
stock
```

Check:

- selected area panel;
- prompt history;
- follow-up view;
- logistics cues;
- accessibility/tooltip text if used.

Do not rely only on visual inspection.

---

# 43. Required Scenario I — interaction variants

Verify:

```text
ATTENTION_ONLY
```

shows only `Look Here`.

Verify:

```text
ATTENTION_AND_INQUIRY
```

shows both interactions.

With no clicks, variants produce identical simulation artifacts.

---

# 44. Required Scenario J — replay/render

Load a fresh-process replay package containing:

```text
observer history
prompt history
completed follow-up
```

Open the greybox UI.

Expected:

- current qualitative area state renders correctly;
- prior prompt/follow-up history renders correctly;
- no new prompt is generated merely by rendering replay state.

---

# 45. Required Scenario K — zero-input autonomous run

Run a meaningful autonomous fixture for the same duration used in accepted integrated evidence while the graphical scene is active and untouched.

Require continued autonomous:

```text
decisions
needs
communications
shipments
arbitration
front changes
```

as applicable to the fixture.

The player UI cannot become a dependency for simulation progress.

---

# 46. Graphical acceptance evidence

Because 115 is explicitly visual, headless tests alone are insufficient.

Perform at minimum one real graphical smoke run using the normal Godot renderer.

Provide evidence for at least:

```text
initial battlefield screen
selected area
pending/insufficient-information state
completed follow-up state
```

Screenshots are sufficient.

A short capture/video is optional, not required.

Do not claim graphical acceptance if only headless rendering was used.

---

# 47. Minimum viewport testing

Verify the greybox remains usable at least at:

```text
1280×720
1920×1080
```

No critical buttons/panels may be unreachable or clipped.

This is a prototype usability check, not full responsive-design certification.

---

# 48. Input modality

Mouse interaction is required.

Keyboard shortcuts are optional.

Do not delay 115 to build controller support.

---

# 49. Accessibility/readability basics

For the prototype:

- do not encode LOW/MEDIUM/HIGH solely by color;
- use visible text labels;
- selected area must have a non-color-only indicator;
- buttons need readable labels.

Do not undertake a full accessibility system yet.

---

# 50. Performance

Do not perform major optimization work.

However, verify the greybox observer can run the accepted simulation at normal prototype speed without obvious UI-caused stalls.

If instrumentation exists, report rough observed behavior.

Do not claim platform performance certification.

---

# 51. Resource integrity

UI rendering and navigation consume no simulated resources.

Prompt-driven 113 reporting still consumes no physical resources under its accepted contract.

Existing conservation tests remain green.

---

# 52. No new military semantics

115 may not modify:

```text
104 planner
105 need logic
106 arbitration
113 report acquisition policy
```

Do not make the UI more useful by quietly changing the underlying AI.

---

# 53. No new information capability

Do not add:

- recon infantry;
- recon vehicles;
- aircraft;
- analysis staff;
- scouts;
- spies;
- radios as new gameplay equipment.

115 only exposes the existing subordinate-report pathway.

---

# 54. No economy/deck/procurement

Do not implement:

```text
production
factories
population
training
procurement permissions
cards
deck
```

Those remain 2D.

---

# 55. No art integration yet

Use temporary greybox visuals.

Do not contact/integrate Artist assets as a requirement for 115.

Artist coordination remains especially important later during visible autonomous battle work in 2E.

---

# 56. Regression requirement

Run the full accepted automated suite.

Foundation entering 115:

```text
1669 checks / 0 failures
```

All accepted 2A/2B/109–114 behavior must remain green.

Add UI-specific automated checks separately.

---

# 57. 115 acceptance gate

115 is complete only when:

### Observer experience

- enabled StrategicAreas are visibly selectable;
- accepted qualitative observer information renders;
- visible logistics cues render without exact hidden quantities.

### Interaction

- `Look Here` submits the real `DIRECT_ATTENTION`;
- `What Happened Here?` submits the real `REQUEST_ASSESSMENT`;
- no raw command IDs are exposed to the player.

### Inquiry loop

- immediate supported assessment can display;
- insufficient-information state displays;
- later legitimate 114 follow-up updates live;
- stale/disagreeing command assessment remains visibly distinct from observer state.

### Safety

- selecting/navigating creates no gameplay inputs;
- no exact hidden values leak through normal UI;
- no developer omniscience appears in player scene.

### Autonomy

- zero-input graphical run continues normally;
- presentation variants with no clicks are simulation-inert.

### Engineering

- full automated regression suite passes;
- strict replay still passes;
- graphical smoke test passes at required viewport sizes.

---

# 58. Completion report

Save under:

```text
C:\Users\dawso\OneDrive\Desktop\trencho
```

using **115** and the established naming convention.

Include at minimum:

```text
115 completion status

commit SHA
project/schema/Godot

total automated checks / failures
115-specific automated checks

Scenario A–K results

graphical renderer used
viewport results
screenshot evidence paths

StrategicAreas rendered
interaction variant tested

actual prompt IDs produced by UI
prompt types produced by UI

immediate assessment result
delayed inquiry/follow-up result
stale/disagreement result
failed-acquisition result

selection/no-click inertness result
exact-value leakage scan result
zero-input autonomous graphical result

resource conservation result
strict replay result
full regression result

GDD housekeeping result

known limitations
deliberate deviations
```

Preserve the complete requirements in repository documentation.

---

# 59. Stop condition

When the full 115 gate passes:

**STOP.**

Do not begin the next numbered task.

Do not add new command vocabulary.

Do not add specialized reconnaissance.

Do not begin 2D.

Do not begin 2E.

Return the complete 115 evidence for review.

If accepted, the next packet will be the **2C integrated acceptance/evaluation and freeze decision**, including review of whether the two-interaction observer model is strong enough to carry forward before we start the economy/deck work in 2D.
