104 is **accepted**.

The reported evidence satisfies the 104 gate: deterministic belief-only reasoning works, candidate scoring/rejection is inspectable, privacy was directly tested against conflicting authoritative truth, outcomes use observed information rather than retroactive world-state access, authority remains outside the planner, strict replay/event reconstruction survives, and no prohibited communication/resource behavior was introduced.

Preserve accepted 104 at:

```text
commit:
ef7e0d0b172f85d89df41c6a1f02c3955d1dfcdf
```

Do not alter the accepted 2A tag.

You are now authorized to begin **105 only**.

# 105 — Dynamic Ammunition Need, Local Self-Help, Peer Coordination & Escalation

## 1. Intended outcome

105 implements the first command-to-command resource-resolution chain:

```text
local command detects a dynamic ammunition need
        ↓
uses resources already under its own authority if possible
        ↓
coordinates with sibling commands for remaining need
        ↓
physical ammunition transfer occurs if a peer can help
        ↓
if peers cannot solve the problem, escalate to direct superior
```

This implements the first version of:

> **solve locally → coordinate laterally → escalate upward**

The superior **does not allocate resources or make an autonomous arbitration decision in 105**. That belongs to the next bounded task.

---

# 2. Core design rule

A resource need is **not a fixed shopping order**.

It is a continuously reevaluated projection of the command's current situation.

Do not implement:

```text
"Commander permanently needs exactly 500 ammo."
```

Implement:

```text
"Given what this command currently believes,
how much additional ammunition would presently restore
the desired operating reserve?"
```

That quantity may rise, fall, or disappear as the simulation evolves.

---

# 3. Scope

105 applies only to:

```text
AMMUNITION
LOCAL commands
their responsible AbstractFront
their directly controlled stockpiles
sibling LOCAL commands under the same direct superior
their direct superior
```

No multi-resource generalization is required beyond using existing generic resource primitives correctly.

---

# 4. Dynamic ResourceNeed projection

Create a persistent/reconstructable resource-need projection or equivalent.

Minimum fields:

```text
need_id
command_id
front_id
resource_type_id

state
urgency

target_stock_quantity
available_quantity
confirmed_incoming_quantity
gross_need_quantity
uncovered_need_quantity

planning_rate_milli

revision
based_on_observation_batch_id
last_evaluated_at

current_resolution_phase
active_coordination_id or null
escalation_message_id or null
```

Recommended states:

```text
ACTIVE
RESOLVED
```

Recommended resolution phases:

```text
LOCAL
PEER_COORDINATION
ESCALATED
```

Exact enum organization is developer latitude.

---

# 5. Need trigger and hysteresis

Use the 104 supply classification.

A new ammunition need opens when the command's latest complete/fresh observation classifies as:

```text
CRITICAL
or
CONSTRAINED
```

Do not open a need when:

```text
SECURE
```

or normally when:

```text
NO_ACTIVE_DEMAND
```

unless recent interval demand/shortage causes the existing critical-first rule to classify it as `CRITICAL`.

Once opened, the need remains active until its projected supply reaches the refill target described below.

This intentionally creates hysteresis:

```text
need begins below 15 seconds coverage
but attempts to refill toward 20 seconds
```

so commands do not oscillate continuously around one threshold.

---

# 6. Planning demand rate

Calculate from the command's beliefs only.

Use:

```text
planning_rate_milli
=
max(
    FRONT_AMMO_DEMAND_RATE,
    FRONT_INTERVAL_DEMAND * 1000
)
```

All values remain canonical integers.

This means a command that just suffered shortage still recognizes its recent consumption requirement even if instantaneous demand happens to fall at the observation boundary.

If both values are zero, planning rate is zero.

---

# 7. Refill target

Prototype target:

```text
TARGET_COVERAGE_MS = 20_000
```

Calculate:

```text
target_stock_quantity
=
ceil(
    planning_rate_milli
    * 20_000
    / 1_000_000
)
```

Use exact integer arithmetic.

No floating-point conversion.

---

# 8. Need quantities

At each complete observation:

```text
gross_need_quantity
=
max(
    0,
    target_stock_quantity - FRONT_AMMO_AVAILABLE
)
```

Then:

```text
uncovered_need_quantity
=
max(
    0,
    gross_need_quantity - confirmed_incoming_quantity
)
```

`confirmed_incoming_quantity` includes only transfers that this command plausibly knows have actually been dispatched toward it.

Do not count:

- merely requested ammunition;
- unaccepted peer offers;
- hidden shipments;
- authoritative shipment state the command has not learned;
- speculative superior assistance.

---

# 9. Need resolution

An active need resolves when:

```text
uncovered_need_quantity == 0
```

and there is no unresolved recent-shortage condition requiring additional target stock.

In the normal case, reaching the 20-second target resolves it.

Emit a resolution event and stop initiating new coordination for that need.

A future shortage creates a **new `need_id`**, not resurrection of an old closed need.

---

# 10. Revision semantics

A need has a monotonically increasing integer `revision`.

Increment revision when a materially actionable field changes, including:

```text
urgency
target_stock_quantity
gross_need_quantity
confirmed_incoming_quantity
uncovered_need_quantity
```

Do not increment merely because simulation time advanced.

Messages must carry:

```text
need_id
need_revision
```

This lets recipients identify stale snapshots.

---

# 11. Local self-help is always attempted first

Before contacting another command, inspect resources already under the command's direct authority through the existing authorized `CommandView`/authority boundary.

Candidate local source stockpiles:

```text
directly controlled stockpiles
excluding the front's destination/supply stockpile
```

Sort deterministically by stockpile ID.

For each source:

```text
transferable = available non-reserved ammunition
```

No special local reserve protection is required for a stockpile that is not serving another active front in 105.

Attempt to dispatch:

```text
min(uncovered_need, transferable)
```

to the front supply stockpile using the existing logistics system.

If no logistics route exists from one source, try the next source.

A successfully dispatched self-help shipment becomes confirmed incoming immediately because the same command authorized it.

---

# 12. Self-help must use real logistics

Do not teleport ammunition.

Local self-help must use:

```text
reservation/shipment semantics
logistics route
travel time
resource conservation
```

already established by 2A.

A failed dispatch does not count as incoming.

---

# 13. Continue resolution after partial self-help

Example:

```text
need = 20
local reserve can send 8
```

After successful dispatch:

```text
confirmed incoming = 8
uncovered need = 12
```

Then proceed to peer coordination for the remaining 12.

Do not wait for the self-help shipment to physically arrive before seeking the remainder.

---

# 14. Peer discovery

Eligible peers are:

```text
enabled LOCAL commands
with the same direct superior
excluding self
```

A peer must also have:

```text
a communication route requester → peer
a communication route peer → requester
```

Sort eligible peers deterministically by command ID.

Coordinate with **one peer at a time**.

Do not broadcast to every peer simultaneously in 105.

---

# 15. Peer request message

Use existing:

```text
message_type = COORDINATION
```

with a structured subtype equivalent to:

```text
AMMO_TRANSFER_REQUEST
```

Payload must include:

```text
coordination_id
need_id
need_revision

requester_command_id
front_id
destination_stockpile_id

requested_quantity
urgency
planning_rate_milli
target_stock_quantity

observation_batch_id
observed_at
```

This is a current coordination snapshot, not a permanent obligation.

---

# 16. Peer response timeout

Do not use arbitrary wall-clock waiting.

When starting coordination, determine the known communication latency:

```text
requester → peer
+
peer → requester
```

Set deterministic response deadline to:

```text
round_trip_latency + 1.0 simulation second
```

If the peer response message explicitly fails before then, handle failure immediately.

If no valid response is received by the deadline:

```text
coordination attempt = timed out
```

and continue to the next eligible peer.

---

# 17. Peer evaluates from its own information

A peer deciding whether it can help must use:

```text
its own CommandView
its own current front beliefs
its own controlled stock
```

It must not inspect:

```text
requester's private beliefs
raw requester front truth
global stockpile truth outside its authority
```

If the peer's required front information is missing/stale under the same 1.5-second rule:

```text
decline reason = STALE_OR_INCOMPLETE_LOCAL_INFORMATION
```

Do not fall back to global truth.

---

# 18. Peer protected stock

Calculate the peer's own planning rate using the same formula:

```text
max(
    its FRONT_AMMO_DEMAND_RATE,
    its FRONT_INTERVAL_DEMAND * 1000
)
```

Its protected front stock is:

```text
peer_protected_stock
=
ceil(
    peer_planning_rate_milli
    * 20_000
    / 1_000_000
)
```

For the peer's front supply stockpile:

```text
front_spare
=
max(
    0,
    peer_available_ammo - peer_protected_stock
)
```

The peer may not offer ammunition that would reduce its own front below that protected amount.

---

# 19. Peer source stockpiles

When finding supply to offer, peer source order is:

1. directly controlled stockpiles that are **not** its active front stockpile, sorted by stockpile ID;
2. then any spare quantity above the protected target in its active front stockpile.

Existing reservations already reduce availability.

Do not double-count reserved stock.

---

# 20. Offer quantity

The peer may offer:

```text
min(requested_quantity, total_transferable_spare)
```

If result is zero, send a structured decline.

Minimum decline reasons:

```text
INSUFFICIENT_SPARE_STOCK
STALE_OR_INCOMPLETE_LOCAL_INFORMATION
NO_LOGISTICS_ROUTE
NO_RETURN_COMMUNICATION_ROUTE
UNAUTHORIZED_SOURCE
```

Use machine-readable reason codes.

---

# 21. Offers must reserve physical stock

A positive peer offer must immediately reserve the offered ammunition.

Purpose code equivalent:

```text
PEER_AMMO_TRANSFER_OFFER
```

This prevents:

```text
one donor
→ simultaneously promises the same 20 ammo
→ to two different commands
```

The reservation belongs to the offer/coordination operation.

---

# 22. Offer lifetime

Before creating an offer, both communication directions must exist.

Set:

```text
offer_expiry
=
current_time
+ peer_to_requester_latency
+ requester_to_peer_latency
+ 1.0 second
```

If no valid acceptance reaches the peer before expiry:

```text
release reservation
mark offer expired
```

Do not leave abandoned reservations indefinitely.

---

# 23. Requester handling of an offer

When an offer arrives, reevaluate the current need.

Accept only if:

```text
need is still ACTIVE
and
offer_quantity <= current uncovered_need_quantity
```

If the need has resolved:

```text
decline/cancel reason = NEED_RESOLVED
```

If the need shrank below the offer:

```text
decline reason = NEED_REVISED
```

Do not partially accept an oversized offer in 105.

A later coordination attempt may request the smaller quantity.

---

# 24. Accepted offer → real shipment

When peer receives a valid acceptance:

1. verify offer reservation still ACTIVE;
2. verify source authority;
3. verify logistics route still exists;
4. atomically convert/use the existing offer reservation for a shipment;
5. dispatch shipment.

Do **not** release the reservation and create an unrelated new reservation in a way that creates a double-spend window.

A narrow extension allowing an existing valid reservation to become shipment cargo is authorized if needed.

It must preserve all 2A conservation semantics.

---

# 25. Dispatch notification

After successful dispatch, peer sends a `COORDINATION` message subtype equivalent to:

```text
AMMO_TRANSFER_DISPATCHED
```

including:

```text
coordination_id
need_id
shipment_id
quantity
source_stockpile_id
destination_stockpile_id
```

Only after this notification is delivered may the requester count that quantity as:

```text
confirmed_incoming_quantity
```

An accepted offer that never dispatched is not incoming.

---

# 26. Shipment failure after dispatch

If a coordinated shipment becomes:

```text
BLOCKED
or
DESTROYED
```

its quantity must stop counting as confirmed incoming once the requester receives/plausibly obtains that failure information.

For 105, it is acceptable for the coordination/logistics integration to generate a local structured notification to the receiving command when a shipment it already knows about becomes blocked/destroyed.

Do not make every command globally aware of arbitrary shipment failures.

After incoming is removed, the active need is reevaluated normally.

---

# 27. Arrival

When a known incoming shipment arrives at the requester's directly controlled destination:

- remove it from confirmed incoming;
- physical stock now contains the ammunition;
- the next normal front observation reflects the new local supply.

Do not count both:

```text
arrived physical stock
+
still-confirmed incoming
```

for the same shipment.

---

# 28. Sequential peer attempts

If a peer:

```text
declines
times out
has message failure
has expired offer
or transfer cannot dispatch
```

and uncovered need remains positive:

```text
try next eligible peer
```

Do not repeatedly retry the same peer during the same resolution pass.

Track attempted peer IDs for the active coordination cycle.

---

# 29. Escalation condition

Escalate only when:

```text
uncovered_need > 0
and
local self-help has been exhausted
and
all eligible peers for the current resolution cycle
have declined / failed / timed out / become unavailable
```

This is the first real implementation of:

> lower levels attempt to solve their own problem before asking higher command.

---

# 30. Escalation message

Send:

```text
message_type = ESCALATION
```

with subtype equivalent:

```text
AMMO_NEED_ESCALATION
```

to the command's **direct superior only**.

Payload:

```text
need_id
need_revision

requesting_command_id
front_id
resource_type_id

urgency

available_quantity
confirmed_incoming_quantity
uncovered_need_quantity
target_stock_quantity
planning_rate_milli

observation_batch_id
observed_at
```

This is explicitly a **time-stamped need snapshot**.

It is not a guaranteed fixed quantity forever.

---

# 31. Superior information

When a valid escalation is delivered, the superior should receive structured information records sufficient for the next phase to reason about it.

At minimum:

```text
SUBORDINATE_AMMO_NEED_QUANTITY
SUBORDINATE_AMMO_NEED_URGENCY
SUBORDINATE_AMMO_NEED_REVISION
SUBORDINATE_AMMO_NEED_FRONT
```

Use:

```text
subject = need_id
source_command_id = requesting LOCAL
source_message_id = escalation message
```

`confidence = 1.0` means the superior knows exactly what the subordinate **reported**.

It does not mean the report is guaranteed to reflect objective world truth.

The superior performs **no autonomous resource allocation in 105**.

---

# 32. Missing superior or communication route

If no direct superior exists:

```text
escalation status = NO_SUPERIOR
```

If superior exists but no communication route:

```text
escalation status = NO_COMMUNICATION_ROUTE
```

Do not bypass the hierarchy.

Do not teleport the escalation into superior beliefs.

The need remains active.

---

# 33. Need resolution during coordination

If later observations show the need is resolved while:

```text
request outstanding
offer outstanding
or escalation already sent
```

the local command must stop seeking new resources.

For an outstanding reserved peer offer, send cancellation when possible.

Reservation must eventually be released by:

```text
cancellation
or
offer expiry
```

If an already dispatched shipment exists, do **not** teleport or cancel it into nothing. It remains a real physical shipment unless a future reroute policy explicitly changes it.

Extra supply can therefore occasionally arrive after circumstances improve. That is acceptable and is an emergent consequence of logistics latency.

---

# 34. Required semantic events / journal

Implement enough durable state/events to reconstruct the resolution chain.

At minimum equivalents of:

```text
RESOURCE_NEED_OPENED
RESOURCE_NEED_UPDATED
RESOURCE_NEED_RESOLVED

LOCAL_RESOURCE_TRANSFER_DISPATCHED

PEER_COORDINATION_STARTED
PEER_TRANSFER_OFFERED
PEER_TRANSFER_DECLINED
PEER_TRANSFER_OFFER_EXPIRED
PEER_TRANSFER_ACCEPTED
PEER_TRANSFER_DISPATCHED

RESOURCE_NEED_ESCALATED
RESOURCE_NEED_ESCALATION_FAILED
```

Existing:

```text
MESSAGE_*
RESERVATION_*
SHIPMENT_*
RESOURCE_*
```

remain authoritative for their respective subsystems.

Do not duplicate physical resource mutation in need events.

---

# 35. Correlation

Use:

```text
need_id
```

as the high-level correlation for the resource problem.

Each peer conversation should also have:

```text
coordination_id
```

All messages/events for one peer negotiation must retain that coordination ID in payload or dedicated correlation metadata.

Do not lose the connection:

```text
need
→ peer conversation
→ reservation
→ shipment
→ outcome
```

---

# 36. No per-observation message spam

An active outstanding peer request or offer blocks creation of another simultaneous request for the same uncovered quantity.

Do not send the same coordination request every one-second observation.

Observations update the need projection while the existing conversation continues.

A changed need may make the eventual offer invalid under §23, but it does not automatically generate another message every second.

---

# 37. Required scenarios

## Scenario A — local self-help

Setup:

```text
LOCAL_A front is ammunition constrained
LOCAL_A owns a separate reserve stockpile
reserve has enough ammunition
valid logistics route exists
```

Expected:

```text
need opens
→ local transfer dispatched
→ no peer coordination
→ no escalation
→ physical shipment arrives
→ need resolves
```

---

## Scenario B — peer collaboration succeeds

Setup:

```text
LOCAL_A needs ammunition
no usable local reserve
LOCAL_B is sibling
LOCAL_B has stock above its protected 20-second target
communication/logistics paths valid
```

Expected:

```text
A sends coordination request
B evaluates own state
B reserves offer stock
B offers
A accepts
B converts reservation into shipment
shipment dispatches
A receives dispatch notice
A counts confirmed incoming
shipment arrives physically
need resolves
```

No superior escalation.

---

## Scenario C — peer protects itself and escalation occurs

Setup:

```text
LOCAL_A needs ammunition
LOCAL_B has ammunition
but giving requested ammo would push B below its own protected target
```

Expected:

```text
B declines INSUFFICIENT_SPARE_STOCK
A exhausts peers
A escalates to superior
superior receives structured need information
superior takes no autonomous action
```

---

## Scenario D — need changes before offer acceptance

Setup:

```text
A requests peer supply
before offer arrives/accepts,
A receives another legitimate supply source
and current need shrinks/resolves
```

Expected:

```text
stale/oversized offer is not blindly accepted
offer declined/cancelled
reservation released
no double allocation
```

---


# Lifecycle amendment and remaining requirements
Yes—make the lifecycle distinction explicit:

> **`uncovered_need_quantity == 0` means the need is fully covered for sourcing purposes, but not necessarily closed.**

Use a condition such as:

```text
ACTIVE / SEEKING_SUPPLY
ACTIVE / COVERED_IN_TRANSIT
RESOLVED
```

or equivalent fields if you prefer separating lifecycle state from coverage state.

### Approved lifecycle semantics

If dispatched, known incoming supply reduces:

```text
uncovered_need_quantity
```

to zero:

```text
state = ACTIVE
condition = COVERED_IN_TRANSIT
```

Effects:

- stop local self-help attempts;
- stop new peer coordination;
- do not escalate;
- continue tracking the known shipment(s);
- continue reevaluating the need from new observations.

Do **not** mark the need `RESOLVED` merely because an in-transit shipment mathematically covers it.

A need becomes `RESOLVED` only after a subsequent complete observation confirms:

```text
physical FRONT_AMMO_AVAILABLE >= current target_stock_quantity
and
confirmed_incoming_quantity == 0
and
FRONT_LAST_SHORTAGE == 0
```

The target is recalculated from that observation before testing resolution.

So Scenarios A/B are correct as written: they close after physical arrival is reflected in observation.

### Recent-shortage case

Yes: if:

```text
FRONT_LAST_SHORTAGE > 0
```

then the need **cannot resolve**, even if known incoming currently covers the target.

It may become:

```text
COVERED_IN_TRANSIT
```

and stop asking for additional supply, but it remains active until a later complete observation reports:

```text
FRONT_LAST_SHORTAGE == 0
```

and physical available stock satisfies the then-current target.

This gives us useful hysteresis without generating duplicate requests.

### Shipment failure while covered

If a need is:

```text
ACTIVE / COVERED_IN_TRANSIT
```

and a known shipment becomes blocked/destroyed and that information reaches the command:

```text
confirmed_incoming decreases
↓
uncovered_need becomes > 0
↓
condition returns to SEEKING_SUPPLY
```

Resolution then resumes from the appropriate point. It does not create a new `need_id`.

Treat this as a clarification/amendment to §9 and §33 of 105.

---

# 37. Required scenarios — Scenario E remainder

## Scenario E — competing peer demand

Use at least three LOCAL commands.

Two requesters attempt to obtain ammunition from the same possible donor.

Expected:

```text
first active offer reservation reduces donor availability
second request cannot be offered the same physical ammunition
```

No resource duplication or negative availability.

This is an important first test of commanders competing for shared resources.

---

# 38. Required integrity tests

Verify at minimum:

- need only opens from complete/fresh beliefs;
- no raw front/global truth used to calculate need;
- 20-second target calculation exact;
- recent interval demand fallback works;
- dynamic need quantity can increase and decrease;
- local self-help precedes peer messaging;
- peer protection calculation exact;
- stale peer information prevents offer;
- offers reserve real stock;
- expired/cancelled offers release reservations;
- accepted offers cannot double-spend;
- actual shipment conserves resources;
- confirmed incoming is not physical stock;
- arrival does not double count;
- blocked/destroyed incoming can reopen uncovered need;
- peer attempts are deterministic;
- escalation occurs only after local/peer resolution is exhausted;
- superior learns only after delivered escalation;
- no superior allocation occurs;
- strict replay/event reconstruction remains exact;
- 2A/103/104 regressions remain green.

Add these lifecycle regressions from today's clarification:

- `uncovered_need == 0` due solely to dispatched incoming produces `COVERED_IN_TRANSIT`, not `RESOLVED`;
- `COVERED_IN_TRANSIT` suppresses additional coordination/escalation;
- arrival alone does not resolve until represented by a complete observation;
- physical stock at/above target plus `FRONT_LAST_SHORTAGE > 0` remains active;
- later shortage-free observation with physical stock at/above the recalculated target resolves the need;
- blocked/destroyed known incoming can transition `COVERED_IN_TRANSIT → SEEKING_SUPPLY`;
- a resolved need never reopens; a later shortage creates a new `need_id`.

---

# 39. Explicit non-goals

Do **not** implement in 105:

- superior resource arbitration;
- operational command allocation policy;
- multiple superiors collaborating;
- player/high-command interaction;
- strategic requests to the player;
- personalities;
- greedy/exaggerating commanders;
- dishonest reports;
- imperfect need estimates;
- cards/deck;
- economy production;
- additional resource types;
- roads/rail construction;
- FOB construction;
- territory planning;
- enemy command AI;
- command learning;
- random negotiation;
- priority auctions;
- proportional splitting of shared stock.

In particular, **do not solve competing subordinate needs at the superior level yet**. Scenario E only proves that peer offers cannot promise the same physical resource twice.

---

# 40. Acceptance gate

105 is complete only when:

### Dynamic need
- opens, revises and resolves correctly;
- is based on beliefs;
- uses the exact 20-second refill target;
- accounts for confirmed incoming separately from physical stock;
- distinguishes `SEEKING_SUPPLY` from `COVERED_IN_TRANSIT`;
- closes only after observed physical refill plus a shortage-free completed interval.

### Local resolution
- command uses its own reserves first;
- transfer travels physically.

### Peer collaboration
- sibling discovery is deterministic;
- peer protects its own operating reserve;
- offers reserve physical stock;
- request/offer/accept/dispatch chain is reconstructable;
- concurrent demand cannot double-spend donor stock.

### Escalation
- occurs only after local and peer options fail;
- travels through communication network;
- superior receives the subordinate's reported need;
- superior does not act yet.

### Integrity
- resource conservation passes every relevant prefix;
- privacy/authority boundaries pass;
- strict fresh-process replay passes;
- all prior accepted suites remain green.

---

# 41. Completion report

Save the numbered completion material under:

`C:\Users\dawso\OneDrive\Desktop\trencho`

using **105** and the established naming convention.

Include at minimum:

```text
105 completion status

commit SHA
project version
schema version
Godot version

total checks / failures
105-specific checks

Scenario A result
Scenario B result
Scenario C result
Scenario D result
Scenario E result

need IDs / coordination IDs
reservation behavior
shipment behavior

COVERED_IN_TRANSIT lifecycle result
physical-arrival resolution result
recent-shortage resolution hold result

resource conservation result
information privacy result
authority result
strict replay result

superior escalation information result

known limitations
deliberate deviations
```

Preserve the 105 requirements alongside the evidence if that remains the repository convention.

---

# 42. Stop condition

When the full 105 gate passes:

**STOP.**

Do not implement superior arbitration.

Do not implement proportional allocation.

Do not implement player involvement.

Do not begin 106.

Return the 105 evidence to me.

If 105 is accepted, the next bounded task will be the first **operational/superior command arbitration problem**: multiple subordinate needs competing for genuinely scarce shared resources, without dividing everything blindly or requiring player micromanagement.
