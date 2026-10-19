# Step105 — dynamic ammunition need and resource resolution

Project0.2.2/schema2B.3, Godot4.7.2 stable. Extends accepted104 commit ef7e0d0b172f85d89df41c6a1f02c3955d1dfcdf. Earlier accepted revisions and prototype-gen2-2A-accepted are preserved.

## Activation and responsibilities

A LOCAL command with local_decision_front_id may opt in via resource_resolution_enabled=true. Defaults remain false for prior fixtures. Opt-in enables need initiation; a delivered105 peer request can be answered by an enabled sibling LOCAL using its own configured front information. A missing/stale donor sample produces a decline, not fallback to stock/front truth. An operational command cannot enable this local resolver.

ResourceNeedPolicy owns exact belief-derived rate/target/supply arithmetic and ordered source candidates. ResourceResolutionService is the trusted event/application coordinator: need projections, self-help, scoped message protocol, offer lifecycle, known incoming and escalation. Existing ResourceService and LogisticsService exclusively own reservations/physical resource mutation; CommunicationService exclusively owns actual message delivery/failure; InformationService owns superior reported knowledge. No superior allocation policy exists.

CommandView gains explicit detached surfaces for own controlled stockpiles, own front assignment/protected front stockpile IDs, sibling identities, direct superior, known communication route latencies and owner-scoped incoming transfers. It never exposes foreign inventories/front values or the global shipment registry. Configured operational communication graphs are treated as known infrastructure; no communication-fog model is added. Route/recipient/source validation uses trusted adapters; policy quantities come from the owner's view and beliefs.

## Belief inputs and exact need

105 uses the complete11-record104 sample, current belief selection/expiry, common batch identity and freshness<=1.5seconds. No incomplete/stale sample opens a need or repairs missing values from truth.

planning_rate_milli=max(observed FRONT_AMMO_DEMAND_RATE, observed FRONT_INTERVAL_DEMAND*1000).
target_stock_quantity=ceil(planning_rate_milli*20000/1000000), calculated with integer numerator/ceiling division.
gross=max(0,target-observed FRONT_AMMO_AVAILABLE).
uncovered=max(0,gross-known confirmed incoming).

Rates retain the103 maximum900000000milli-ammo/sec under PRESS; interval demand is at most900000ammo in a one-second sample. Inconsistent/unsupported interval data is rejected before multiplication. There is no floating demand/utility calculation or fixed shopping quantity.

A new need opens only for CRITICAL/CONSTRAINED supply. Existing active needs persist toward the20second target even after reaching the15second entry threshold. Urgency values are CRITICAL, CONSTRAINED or REFILL (the latter for an active refill after initial scarcity improves). Recent shortage takes priority over ZERO_DEMAND as accepted in104.

Need revisions increment once when actionable urgency/target/rate/gross/incoming/uncovered/lifecycle/condition fields change, not for time/provenance-only reevaluation. Each complete sample persists its evaluation time, underlying observed time, batch and belief IDs. Messages carry need_id/need_revision and the source observation identity/time. Snapshots remain timestamped reports, not continuously updated superior truth.

## Covered versus resolved

ACTIVE/SEEKING_SUPPLY requests additional resources.
ACTIVE/COVERED_IN_TRANSIT has uncovered0 due to known dispatched cargo and suppresses new sourcing/escalation.
ACTIVE/AWAITING_OBSERVATION follows local arrival until the normal complete physical sample.
ACTIVE/AWAITING_CONFIRMATION has no uncovered quantity but awaits a shortage-free/refill observation.

Only a subsequent complete sample can resolve when physical observed available>=recalculated target, confirmed incoming0 and last shortage0. Arrival alone never resolves. A recent shortage holds the need active even if physical stock now satisfies target. Resolved needs remain historical; a later scarcity opens a new ID.

Known blocked/destroyed cargo removes incoming through an owner-scoped local infrastructure notification and resumes the same need. Only already-known shipment IDs are monitored. Arrival removes incoming before front observation, preventing double count. A between-sample arrival suspends new sourcing until the complete observation; this avoids seeking supply against an outdated physical-stock belief. No shipment is teleported/cancelled out of existence when a need improves.

## Self-help, then one peer

Directly controlled non-front stockpiles are tried in sorted ID order. Stock serving another active own front is excluded; no multi-front reserve optimization is attempted. Availability excludes reservations. Unroutable/failed sources are skipped; successful dispatch uses existing reservation/cargo/travel semantics and is immediately known to its authorizing command. Partial self-help proceeds immediately to peers for the remainder.

Peer discovery requires enabled sibling LOCAL commands under a non-null common direct superior and both communication directions. IDs are sorted. One active request/offer blocks simultaneous replacement requests for that need. Quantity/revision changes update the need while the conversation continues. Each resolution pass records attempted peers; no repeated peer in the pass. An oversized offer is cancelled as NEED_REVISED and a new pass may request the smaller quantity.

The donor validates its own fresh complete front sample, calculates the same20second protected target, and considers own non-front sources first (sorted), followed by actual unreserved front spare above protection. Donor decisions never query requester private beliefs or foreign resource quantities. Multiple source allocations may fill one offer; each has a real PEER_AMMO_TRANSFER_OFFER reservation.

Offer expiry=creation time+known return/outbound latency+1simulationsecond. Before expiry an authenticated acceptance must match quantity, live claims, source authority and current logistics routes. Logistics.dispatch_reserved binds the existing offer claim to cargo and invokes existing physical dispatch. There is no release/re-reserve window. Claims cannot be generically retired/stolen from an offer; cancellation/expiry use a narrow coordination-bound maintenance capability, including when the donor is disabled.

## Wire protocol and timing

Existing COORDINATION messages use subtypes:
AMMO_TRANSFER_REQUEST, OFFER, ACCEPT, CANCEL, DECLINED, EXPIRED and DISPATCHED (all prefixed AMMO_TRANSFER_).

Request includes need/revision, coordination, requester/front/destination, quantity/urgency/planning rate/target, source batch/observed time and deadline. Deadline=known round-trip latency+1simulationsecond. Offer includes quantity/expiry; accept includes current need revision/quantity; cancel/decline include machine-readable reason. Dispatch notice includes shipment/source/destination/quantity.

Only delivered dispatch notices make peer cargo known incoming; offers/acceptances/hidden shipments do not count. Multi-source dispatch notices accumulate to the accepted quantity before closing the conversation. Local self-help is known immediately. Dispatch/failure/arrival remain physical states in LogisticsService.

Message processing uses owner inboxes, durable receipts and a bounded deterministic64-pass drain per tick for zero-latency chains. Offer expiry is checked in simulation microseconds. Explicit message failures advance immediately. Delivered responses are processed before response-timeout determination at the deadline. Silent-response timeout boundary is tested as a pure scheduling rule; live message-failure and offer-expiry cleanup have integration coverage. No wall-clock gameplay waits exist.

## Escalation and private reported knowledge

After local sources and eligible unattempted peers are exhausted, one ESCALATION/AMMO_NEED_ESCALATION snapshot goes to the direct superior only. No superior or route gives NO_SUPERIOR/NO_COMMUNICATION_ROUTE and leaves the need active. A failed in-flight escalation is recorded; route restoration can permit a new attempt. No automatic per-observation escalation spam is generated.

Only delivery generates four superior InformationRecords: SUBORDINATE_AMMO_NEED_QUANTITY, URGENCY, REVISION, FRONT (each full key prefixed SUBORDINATE_AMMO_NEED_). Subject is need_id, source_command_id is the sender, source_message_id is the delivered escalation, confidence1 means faithfully reported. Older/duplicate reported revisions are retained in message history but cannot overwrite newer superior need facts. No raw need/front truth is supplied to superior policy; no allocation occurs.

## Durable projections/events/correlation

New registries:resource_needs, peer_coordinations, known_transfers, resolution_receipts. WorldState.apply_event remains the sole projection mutation boundary. Need fields include all packet quantities, state/condition/urgency, revision, batch/beliefs, evaluation/observation times, phase, attempted peers, current conversation and escalation status/ID.

Coordination records preserve requester/donor state separately (undelivered donor activity does not imply requester knowledge), source allocations/claims, protected target/belief IDs, message/shipment IDs, offered/accepted/confirmed quantities and expiry/deadlines. IDs derive from event sequence and are scoped to a run.

Required event families are implemented:RESOURCE_NEED_OPENED/UPDATED/RESOLVED,LOCAL_RESOURCE_TRANSFER_DISPATCHED,PEER_COORDINATION_STARTED,PEER_TRANSFER_OFFERED/DECLINED/OFFER_EXPIRED/ACCEPTED/DISPATCHED,RESOURCE_NEED_ESCALATED/ESCALATION_FAILED. Additional receipt/known-status/request/response/finish/notice events preserve application transitions. Existing resource/reservation/shipment/message events remain authoritative for physical transport.

need_id is the high-level correlation; coordination_id is retained in negotiation payloads/claims/shipments and event metadata. Actual dispatch and message causation links remain inspectable. Generic REPORT and other2A messages preserve their previous correlation semantics even when payloads contain unrelated need_id metadata.

EvaluateResourceNeed {observation_batch_id} is a privileged fixture diagnostic using the same validated batch path; it supplies no facts and cannot bypass freshness/ownership. The existing privileged information/decision diagnostics build controlled privacy/freshness scenarios.

## Reproduction, evidence and limits

Runner modes:
test ->complete foundations+105;
needs ->105 targeted checks/A-E summaries;
need-demo ->peer-success fixture, exports artifacts/run_step105;
replay -Package res://artifacts/run_step105 ->separate-process replay;
inspector-headless ->preserved idle/manual/30FPS/low-processor startup checks.
Pass -GodotPath <Godot4.7.2> and optionally -TimeoutSeconds25.

Scenarios:A self-help resolves without peers/escalation; B peer reserves80/dispatches real cargo then observed refill resolves; C protected donor declines and superior learns delivered need snapshot without allocating; D legitimate supply changes need before offer acceptance and cancels/releases80; E concurrent demands reserve74 once and decline a second requester, never promising the same ammunition twice.

Tests cover all event prefixes/active claims/cargo, dynamic revisions/target/fallback, belief-conflicting truth, stale/missing/expired information, protected sources, partial/multi-source transfers, unknown shipments, notice gating, arrival/shortage closure, new IDs, blocked/destroyed recovery, cancellation/expiry/disabled-donor cleanup, route failures, hierarchy, stale escalation revisions, correlation and deterministic declaration/peer order. Strict integer importer/normalizer/comparer are unchanged.

The bounded E fixture stops at tick18 with its first offer still reserved to expose the competition state; separate continuing-run expiry/cancellation tests prove cleanup. Final live outcomes may remain pending when diagnostic EndRun stops time. Each active need sends an escalation snapshot per resolution pass; this is not continuous superior truth synchronization. Known communication topology is configured infrastructure, not an inference/fog system. No scale benchmark, graphics launch or target export is claimed.

No106, superior arbitration/proportional allocation, player involvement, new resources, production, construction, territorial policy, personality, dishonesty, learning or random negotiation. Stop at105 acceptance and return evidence.
