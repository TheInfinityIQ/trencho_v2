112 is **accepted**.

The evidence satisfies the 112 gate. The important behavior is present: unsupported prompts create a persistent command-owned knowledge gap rather than a fact; repeated player prompting links to one requirement rather than multiplying tasks; PlayerObserver data does not leak into it; and the entire requirement system remains inert to the accepted military simulation until we deliberately give it a collection mechanism.

Preserve accepted 112 at:

```text
653613752628bf3d55cd1f269ea04245069117aa
```

Frozen 2A/2B tags remain unchanged. The GDD housekeeping item remains nonblocking.

You are authorized to begin **113 only**.

# 113 — First Information Acquisition Pathway: Subordinate Situation Report

## 1. Purpose

113 implements the first deliberately small answer to an OPEN:

```text
AREA_SITUATION_ASSESSMENT
```

information requirement.

The first collector is **not reconnaissance infantry, aircraft, vehicles, analysis staff, or spies**.

Instead, Operational Command first asks:

> **“Does the responsible local command already know enough to give me a situation report?”**

This is the simplest legitimate information-acquisition pathway and establishes the hierarchy we want later:

```text
player asks question
↓
Operational Command recognizes knowledge gap
↓
information requirement opens
↓
Operational Command asks responsible subordinate for a report
↓
subordinate answers from its OWN existing beliefs
↓
report travels through real communications
↓
Operational Command learns additional legitimate information
↓
information requirement becomes satisfied
```

113 stops there.

The original player prompt is **not yet answered again**.

---

# 2. Starting point

Begin from accepted 112:

```text
653613752628bf3d55cd1f269ea04245069117aa
```

Expected progression:

```text
Project 0.3.4
Schema 2C.5
```

Foundation entering 113:

```text
1353 checks / 0 failures
```

Preserve all frozen tags.

---

# 3. Design reason for starting with subordinate reporting

The eventual information-acquisition stack may include:

```text
existing subordinate knowledge
field reports
messengers
recon infantry
recon vehicles
observation aircraft
analysis teams
signals intelligence
etc.
```

113 proves only the first step:

> **Before spending specialized reconnaissance capability, ask the existing command hierarchy what it already knows.**

Do not implement the later methods yet.

---

# 4. Separate opt-in

Add a 113-only Operational configuration equivalent to:

```text
strategic_subordinate_reporting_enabled
```

Default:

```text
false
```

Use the same pre-canonical extraction pattern accepted for 111/112:

```text
raw definition
→ extract/validate 113 config
→ strip
→ canonical WorldDefinition
```

Do not place the flag into canonical command records or WorldState.

Only Operational Commands may enable it.

Persist it in an explicitly 2C information-collection configuration artifact.

---

# 5. Eligible requirement

113 may act only on:

```text
requirement_type = AREA_SITUATION_ASSESSMENT
state = OPEN
```

owned by an Operational Command with 113 enabled.

The StrategicArea must have:

```text
front_id != null
```

Frontless requirements remain OPEN and generate no collection request in 113.

---

# 6. Eligible collector

For an eligible front-associated area, the collector is:

```text
AbstractFront.responsible_command_id
```

The responsible command must be:

```text
LOCAL
```

and a descendant of the requirement owner Operational Command.

If not:

```text
no supported collector
```

for 113.

Do not search arbitrary neighboring commands.

Do not ask peers.

Do not ask another Operational Command.

---

# 7. Collection attempt

Create a reconstructable `InformationCollectionAttempt` or equivalent.

Minimum fields:

```text
collection_id
requirement_id

owner_command_id
collector_command_id

area_id
front_id

method
state

created_at
completed_at or null

request_message_id or null
response_message_id or null

source_observation_batch_id or null
source_information_record_ids[]

result_code or null
```

Method is exactly:

```text
SUBORDINATE_SITUATION_REPORT
```

Suggested states:

```text
REQUEST_PENDING
REQUEST_IN_TRANSIT
WAITING_FOR_LOCAL_OBSERVATION
REPORT_IN_TRANSIT
COMPLETED
UNAVAILABLE
```

Exact enum layout is developer latitude if semantics remain equivalent.

---

# 8. Collection IDs

Use an independent deterministic namespace, e.g.:

```text
information-collection:0000000001
```

Do not allocate from the core authoritative event/entity counter.

The collection record may live in the 2C information-requirement/collection subsystem.

---

# 9. One active collection per requirement

An OPEN requirement may have at most one active 113 collection attempt.

Repeated player prompts linking to the same requirement must **not** produce additional simultaneous subordinate-report requests.

This extends the anti-spam principle established in 112.

---

# 10. When collection starts

A newly OPEN eligible requirement should begin collection at the same whole-second command-processing boundary after requirement creation.

Conceptually:

```text
1. due communications/reports process
2. prompt evaluates
3. requirement opens/links
4. if requirement newly needs collection:
      start one subordinate-report collection
5. existing arbitration continues
```

For an already-open requirement loaded/replayed with no attempt yet, collection may start at the next eligible exact whole-second boundary.

Do not evaluate every 100 ms.

---

# 11. Request message

Use the existing real command CommunicationService.

Send:

```text
message_type = REPORT
```

with structured subtype equivalent to:

```text
AREA_SITUATION_REPORT_REQUEST
```

from:

```text
Operational owner
→ responsible LOCAL collector
```

Payload minimum:

```text
collection_id
requirement_id

area_id
front_id

requesting_command_id
collector_command_id
```

Do not include:

```text
PlayerObserver cues
enemy activity band
what the player visually saw
objective world truth
```

The local command learns only:

> “Higher command wants a situation report for this area.”

---

# 12. Real communication

The request must use the accepted CommunicationGraph.

Therefore it is subject to:

- route existence;
- latency;
- existing delivery semantics;
- existing message failure semantics.

Do not teleport the request.

Do not invent a separate zero-latency 2C command channel.

---

# 13. No route

If no valid communication route exists:

```text
Operational → Local
```

do not send a fake message.

Mark the collection attempt:

```text
UNAVAILABLE
```

with:

```text
NO_COMMUNICATION_ROUTE
```

The InformationRequirement remains:

```text
OPEN
```

113 does not retry automatically.

A later system may define retry/recovery policy.

---

# 14. Local response knowledge boundary

When the Local command receives a valid request, it may answer only from its own accepted local information.

It must not read:

```text
raw AbstractFront
WorldState
PlayerObserverView
Operational reports
global stock
other Local beliefs
```

The response source is the Local command's own complete local front observation batch / InformationRecords.

---

# 15. Required local facts

A successful 113 report requires one internally consistent complete observation batch containing the accepted autonomous-front facts necessary for this bounded situation report.

Require at minimum:

```text
FRONT_FRIENDLY_STRENGTH
FRONT_ENEMY_PRESSURE
FRONT_POSTURE
FRONT_AMMO_COVERAGE_MILLISECONDS
FRONT_AMMO_COVERAGE_STATUS
FRONT_LAST_SHORTAGE
```

Use the accepted observation-batch completion identity.

Do not mix facts across batches.

---

# 16. Freshness

Use the existing accepted local belief freshness rule:

```text
age <= 1.5 seconds
```

A batch exactly 1.5 seconds old remains valid.

Do not introduce a second freshness doctrine.

---

# 17. If fresh information is immediately available

If the request arrives and a complete/fresh batch exists:

```text
construct response immediately
→ send through CommunicationService
```

No direct Operational knowledge mutation occurs before response delivery.

---

# 18. If information is not yet fresh/complete

If the request arrives but no valid complete/fresh batch exists:

```text
collection state = WAITING_FOR_LOCAL_OBSERVATION
```

Do **not** respond with fabricated information.

The request remains pending locally until the next valid complete local observation for that front.

At that point:

```text
construct response
→ send it
```

This prevents unnecessary failure/retry spam and is the one bounded waiting behavior authorized in 113.

---

# 19. Disabled/non-observing Local

If the responsible Local can never generate the required observation because its configured front observation system is disabled or invalid, reject/start the attempt as:

```text
UNAVAILABLE
```

with an equivalent reason:

```text
LOCAL_OBSERVATION_UNAVAILABLE
```

Do not leave a known-impossible waiter forever.

---

# 20. Situation report payload

Use a structured response message subtype equivalent to:

```text
AREA_SITUATION_REPORT
```

Minimum payload:

```text
collection_id
requirement_id

area_id
front_id

reporting_command_id
requesting_command_id

observation_batch_id
observed_at

friendly_strength_centi
enemy_pressure_centi
posture

ammo_coverage_status
ammo_coverage_milliseconds or null

last_shortage

source_information_record_ids[]
```

These values must come from the Local's actual belief records, not reconstructed truth.

---

# 21. Exact values are allowed internally

Unlike PlayerObserverView, this Local→Operational report may contain exact values because it is legitimate command information.

That does **not** mean the player receives them.

113 must maintain this distinction:

```text
LOCAL COMMAND KNOWLEDGE
        ↓ legitimate report
OPERATIONAL COMMAND KNOWLEDGE
        ↓
[future player assessment policy]

PLAYER
```

Do not copy the report payload into the normal player-facing prompt view.

---

# 22. Response communication

The situation report must use the real return path:

```text
Local → Operational
```

with accepted communication latency/failure semantics.

A valid request route does not guarantee a valid return route.

---

# 23. No return route

If the Local has valid information but cannot communicate back:

```text
collection attempt = UNAVAILABLE
```

with equivalent reason:

```text
NO_RETURN_COMMUNICATION_ROUTE
```

Requirement remains OPEN.

No Operational knowledge is created.

---

# 24. Message failure

If either the request or response message later fails under accepted communication semantics:

- collection does not complete;
- requirement remains OPEN;
- record structured failure provenance.

Do not retry automatically in 113.

---

# 25. Operational knowledge ingestion

Only after `AREA_SITUATION_REPORT` is delivered may Operational Command learn its contents.

Ingest corresponding legitimate InformationRecords into Operational Command's accepted InformationService or equivalent recipient knowledge projection.

Use distinct fact types appropriate for reported area state, e.g.:

```text
REPORTED_FRONT_FRIENDLY_STRENGTH
REPORTED_FRONT_ENEMY_PRESSURE
REPORTED_FRONT_POSTURE
REPORTED_FRONT_AMMO_COVERAGE_MILLISECONDS
REPORTED_FRONT_AMMO_COVERAGE_STATUS
REPORTED_FRONT_LAST_SHORTAGE
```

Names may follow repository conventions.

---

# 26. Reported fact semantics

For ingested Operational facts:

```text
subject = front_id or area_id according to existing InformationRecord contract
source_command_id = reporting Local
source_message_id = delivered AREA_SITUATION_REPORT
observed_at = Local observation timestamp
received_at = Operational delivery time
confidence = 1.0
```

`confidence = 1.0` means:

> Operational Command knows exactly what the Local command reported.

It does not magically certify objective truth.

---

# 27. Preserve source provenance

Each Operational InformationRecord should retain enough provenance to identify:

```text
Local source InformationRecord ID
Local observation batch ID
response message ID
collection ID
requirement ID
```

If the existing InformationRecord schema cannot hold every typed relationship, store them in the dedicated collection/report projection without weakening the existing schema.

Do not hide important provenance in arbitrary unvalidated metadata.

---

# 28. Requirement satisfaction

After a valid complete situation report is delivered and its supported information is ingested:

```text
InformationRequirement
OPEN
→ SATISFIED
```

Add fields/equivalent:

```text
satisfied_at
satisfaction_collection_id
satisfaction_message_id
satisfaction_information_record_ids[]
```

`last_updated_at` becomes satisfaction time.

---

# 29. Requirement semantic event

Extend the separate requirement event stream with:

```text
INFORMATION_REQUIREMENT_SATISFIED
```

Minimum payload:

```text
requirement_id
owner_command_id
area_id

collection_id
response_message_id
information_record_ids[]

satisfied_at
```

This event does not duplicate the command InformationRecords themselves.

---

# 30. Collection completion

After successful delivery/ingestion:

```text
collection state = COMPLETED
result_code = REPORT_DELIVERED
```

Store:

```text
completed_at
response_message_id
source_observation_batch_id
source_information_record_ids
```

---

# 31. No original prompt reevaluation yet

This is important.

The 111 evaluation remains historically:

```text
FURTHER_INFORMATION_REQUIRED
```

even after the requirement becomes SATISFIED.

Do not rewrite history.

Do not automatically append a new player-facing answer.

Do not reevaluate the original prompt in 113.

A future bounded task will handle:

```text
requirement satisfied
→ command produces follow-up assessment for player
```

---

# 32. Existing 111 evaluator behavior

111 continues to understand only its accepted delivered need-report domain.

Do not teach it to consume the new area situation report during ordinary prompt evaluation in 113.

That would combine collection and player-answer policy in one task.

113 proves acquisition only.

---

# 33. Existing military AI behavior

The new Operational area facts are not consumed by:

```text
104 local posture planner
105 needs/peer resolution
106 arbitration
```

in 113.

Therefore collection may add:

- messages;
- InformationRecords;
- requirement/collection state;

but must not change:

- posture policy;
- resource allocation policy;
- shipment decisions;
- military resource consumption.

---

# 34. Authoritative divergence is now legitimate

Unlike 109–112, 113 creates real command messages and Operational knowledge.

Therefore **do not require byte-identical `events.jsonl`** between collection-enabled and disabled runs.

The new communication events are legitimate authoritative simulation effects.

However, compare semantic military outcomes and require identical:

```text
front posture choices
resource needs
peer resource behavior
superior ammunition allocations
physical shipments
resource ledger
```

for a controlled paired fixture where the only new information is the 113 situation report.

Authoritative IDs may shift because real messages/events now exist.

Do not normalize away resource/military behavior differences if they actually occur.

If an accepted AI subsystem unexpectedly consumes the new facts and changes behavior, treat that as a defect and stop.

---

# 35. Collection event/projection persistence

Persist InformationCollectionAttempt state separately with exact replay/reconstruction.

Naming flexible, e.g.:

```text
information_collection_events.jsonl
final_information_collections.json
```

You may alternatively extend the 112 information subsystem stream if that produces a cleaner exact contract.

Whichever approach is used, preserve clear typed distinctions:

```text
requirement
collection attempt
authoritative communication message
Operational InformationRecord
```

Do not collapse all four into one generic event.

---

# 36. Collection semantic events

At minimum equivalents of:

```text
INFORMATION_COLLECTION_STARTED
INFORMATION_COLLECTION_WAITING
INFORMATION_COLLECTION_REPORT_SENT
INFORMATION_COLLECTION_COMPLETED
INFORMATION_COLLECTION_UNAVAILABLE
```

Do not emit WAITING if the attempt never actually waits.

Do not emit fake COMPLETED before Operational receipt/ingestion.

---

# 37. Correlation

Use:

```text
collection_id
```

as the collection-level correlation identity in 2C collection records/events.

Messages should carry:

```text
collection_id
requirement_id
```

in structured payload.

The audit chain must reconstruct:

```text
player prompt
→ prompt evaluation
→ information requirement
→ collection attempt
→ report request message
→ Local belief batch / source records
→ response message
→ Operational InformationRecords
→ requirement satisfaction
```

---

# 38. Duplicate prompt behavior while collecting

If another qualifying player prompt links to the same OPEN requirement while its collection is:

```text
REQUEST_IN_TRANSIT
WAITING_FOR_LOCAL_OBSERVATION
REPORT_IN_TRANSIT
```

then:

- append requirement provenance as accepted in 112;
- do not create a second collection attempt;
- do not send a duplicate report request.

---

# 39. Prompt after satisfaction

If the old requirement is already:

```text
SATISFIED
```

and a later unsupported 111 evaluation occurs for the same owner/area/type, do **not** silently reuse the satisfied requirement as if it were current forever.

For 113, create a **new OPEN requirement with a new requirement ID**.

Rationale:

A satisfied information requirement represents one completed information acquisition cycle.

Later questions may concern a changed battlefield.

This supersedes the 112 uniqueness rule, which applied only to OPEN requirements.

---

# 40. Requirement key rule after lifecycle extension

At most one:

```text
OPEN
```

requirement may exist for:

```text
owner_command_id
+ area_id
+ requirement_type
```

Any number of historical:

```text
SATISFIED
```

requirements may exist for that key.

Update validation/reconstruction accordingly.

---

# 41. Required Scenario A — successful subordinate report

Setup:

- unsupported `AREA_FRONT_C`;
- requirement opens;
- responsible `LOCAL_C`;
- complete/fresh Local C observation exists;
- both communication directions valid.

Expected:

```text
requirement opens
→ collection starts
→ report request travels to C
→ C builds report from own fresh batch
→ response travels to Operational
→ Operational ingests reported area facts
→ requirement SATISFIED
→ collection COMPLETED
```

No player follow-up answer yet.

---

# 42. Required Scenario B — communication latency proves no telepathy

Use nonzero:

```text
Operational → Local latency
Local → Operational latency
```

Verify:

Before request delivery:

```text
Local has no request state
Operational has no new area facts
```

After request delivery but before response delivery:

```text
Local may have produced/sent report
Operational still has no new area facts
requirement remains OPEN
```

Only after response delivery:

```text
Operational learns facts
requirement SATISFIED
```

---

# 43. Required Scenario C — waits for next local observation

Deliver request when Local has no complete/fresh observation batch.

Expected:

```text
collection = WAITING_FOR_LOCAL_OBSERVATION
```

No fabricated report.

At next legitimate complete local observation:

```text
response generated from that exact batch
```

and normal return communication continues.

---

# 44. Required Scenario D — stale local information cannot answer

Make Local's most recent complete batch older than:

```text
1.5 seconds
```

at request receipt.

Expected:

```text
WAITING_FOR_LOCAL_OBSERVATION
```

not use of stale belief and not raw truth fallback.

A later fresh observation enables response.

Exactly 1.5 seconds remains accepted as fresh.

---

# 45. Required Scenario E — no route

No valid:

```text
Operational → responsible Local
```

communication route.

Expected:

```text
collection = UNAVAILABLE
NO_COMMUNICATION_ROUTE
requirement remains OPEN
```

No response, no Operational facts.

---

# 46. Required Scenario F — no return route

Request can reach Local.

No valid:

```text
Local → Operational
```

route when response would be sent.

Expected:

```text
UNAVAILABLE
NO_RETURN_COMMUNICATION_ROUTE
requirement remains OPEN
```

No Operational knowledge injection.

---

# 47. Required Scenario G — duplicate prompts during collection

While first collection is in transit/waiting:

submit additional qualifying prompts for same owner/area.

Expected:

```text
one OPEN requirement
one collection attempt
one report request
multiple requirement provenance links
```

No request spam.

---

# 48. Required Scenario H — frontless area

Unsupported prompt creates an OPEN frontless requirement.

113 finds no supported collector.

Expected:

```text
requirement remains OPEN
0 collection request messages
```

Do not fabricate a Local recipient.

A diagnostic `NO_SUPPORTED_COLLECTOR` may be recorded without changing requirement state.

---

# 49. Required Scenario I — player observation does not enter report

PlayerObserver may contain:

```text
HIGH enemy activity
visible supply movement
```

Local beliefs differ or omit those observations.

Situation report must contain only Local belief-derived values.

Operational learns only the Local report.

No observer cue is copied into request, response, or Operational InformationRecords.

---

# 50. Required Scenario J — report can be stale relative to objective truth

Local completes a valid observation.

Then objective world changes before the Local receives/sends the report, without another valid observation updating that belief.

Expected:

```text
Local reports its legitimate believed values
```

not current truth.

Operational receives those stale values.

This is correct.

Store original:

```text
observed_at
received_at
```

so the stale provenance is inspectable.

---

# 51. Required Scenario K — military-policy isolation

Use a meaningful autonomous fixture.

Compare collection disabled vs enabled with the same underlying world and prompts.

Permit differences in:

```text
information-request messages
information-report messages
Operational InformationRecords
requirement/collection states
authoritative IDs affected by those new messages/events
```

Require equivalent military outcomes:

```text
local posture actions/scores
resource needs
peer resource behavior
ammunition escalations
106 allocation quantities/order
physical resource shipments
final physical resource ledger
```

The new area report is not yet an input to those policies.

---

# 52. Required Scenario L — strict replay

Fresh-process replay must reproduce exactly:

```text
requirements and lifecycle
collection IDs/states/events
request/response messages
source observation batch IDs
source Local InformationRecord IDs
Operational ingested InformationRecords
requirement SATISFIED event/projection

112 provenance
111 evaluations
110 prompts/inputs
109 player-observation stream/view

authoritative world events/state
all existing 2B projections
```

No tolerance.

---

# 53. Required Scenario M — later question after satisfaction

Complete one successful collection:

```text
requirement 1 → SATISFIED
```

Later cause another qualifying unsupported evaluation for the same owner/area/type.

Expected:

```text
requirement 2
```

with a new ID and one new collection attempt.

Do not reopen requirement 1.

Do not link new prompt provenance to satisfied requirement 1.

---

# 54. InformationRecord isolation tests

Verify:

- collection request creates no battlefield fact;
- waiting state creates no battlefield fact;
- Local report is based only on Local InformationRecords;
- Operational facts appear only after response delivery;
- facts retain Local/message/observation provenance;
- player prompt itself is never treated as a battlefield fact.

---

# 55. Resource integrity

113 information collection consumes no physical resources yet.

Therefore it must not mutate:

```text
ammo
stock
cargo
reservations
consumption
destruction
```

Existing conservation checks remain green.

This is a report-request mechanism, not yet a physical reconnaissance capability.

---

# 56. No player exact-data response yet

Even though Operational may now hold exact reported values:

```text
do not expose them to PlayerPromptView
```

The player still sees the historical 111 result:

```text
FURTHER_INFORMATION_REQUIRED
```

until a later task defines a follow-up command response.

---

# 57. Explicit non-goals

Do **not** implement in 113:

- player follow-up answer;
- automatic original-prompt reevaluation;
- recon infantry;
- recon vehicles;
- observation aircraft;
- spy planes;
- analysis teams;
- messenger assets;
- physical reconnaissance;
- reconnaissance risk/combat;
- resource costs for information;
- collector prioritization;
- multiple collector candidates;
- attack/defend/recon player prompts;
- strategic battlefield UI;
- economy;
- factories;
- barracks;
- procurement;
- cards/deck.

---

# 58. GDD housekeeping

Still administrative/nonblocking.

If the current GDD PDF/DOCX remain unavailable to the developer environment, continue to record:

```text
GDD housekeeping pending — source files unavailable
```

Do not fabricate them.

---

# 59. Regression requirement

Run the full suite.

Foundation entering 113:

```text
1353 checks / 0 failures
```

All accepted behavior from:

```text
2A
2B
109
110
111
112
```

must remain green when 113 is disabled.

Any genuine accepted regression is blocking.

---

# 60. 113 acceptance gate

113 is complete only when:

### Collection
- one OPEN supported area requirement creates one subordinate-report collection;
- request uses real command communication;
- Local response uses one complete/fresh local observation batch;
- no raw truth fallback exists.

### Knowledge acquisition
- Operational learns report contents only after response delivery;
- exact Local provenance is reconstructable;
- requirement becomes SATISFIED only after valid report ingestion.

### Anti-spam/lifecycle
- duplicate prompts do not create duplicate active collections;
- satisfied requirement stays historical;
- later qualifying question creates a new requirement.

### Information boundaries
- PlayerObserver does not enter report contents;
- prompt itself is not battlefield information;
- stale Local belief may legitimately produce stale report.

### Isolation
- new reported facts do not yet influence accepted military policies;
- physical resource behavior remains unchanged.

### Integrity
- export/reconstruction/replay exact;
- conservation remains green;
- all accepted regressions remain green.

---

# 61. Completion report

Save under:

```text
C:\Users\dawso\OneDrive\Desktop\trencho
```

using **113** and established naming.

Include at minimum:

```text
113 completion status

commit SHA
project/schema/Godot

total checks / failures
113-specific checks

Scenario A–M results

requirement IDs/states
collection IDs/states

request message IDs
response message IDs

source observation batch IDs
source Local InformationRecord IDs
Operational ingested InformationRecord IDs

communication-latency result
fresh/stale belief result
no-route / no-return-route results

duplicate-prompt suppression result
later-question-new-requirement result

PlayerObserver leakage result
raw-world-truth isolation result
military-policy isolation result

resource conservation result
event reconstruction result
strict fresh-process replay result

112 compatibility result
GDD housekeeping result

known limitations
deliberate deviations
```

Preserve the full requirements in repository documentation.

---

# 62. Stop condition

When the full 113 gate passes:

**STOP.**

Do not begin 114.

Do not send the newly acquired information back to the player as a follow-up answer.

Do not automatically reevaluate the original prompt.

Do not add recon personnel, vehicles, aircraft, analysis teams, or resource costs.

Do not build the battlefield UI.

Return the complete 113 evidence for review.

If accepted, the next bounded task will connect a **SATISFIED information requirement back to the player-facing inquiry lifecycle**, so `"What happened here?"` can eventually progress from `"I don't know yet"` to a legitimate follow-up assessment based on information the command actually acquired.
