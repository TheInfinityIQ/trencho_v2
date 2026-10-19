# 106: superior ammunition arbitration

Project 0.2.3 / schema 2B.4, Godot 4.7.2.stable.steam.ed1daf0bf. Full designer packet: REQUIREMENTS_106.md. Accepted105 remains in normal Git ancestry; the accepted2A tag is unchanged.

## Activation and boundaries

Set `ammunition_arbitration_enabled: true` on an OPERATIONAL command. Default is false; LOCAL activation and tick durations that cannot exactly reach each second are rejected. Existing105 demos retain their accepted snapshot behavior with this feature off. An enabled superior also activates revision updates/resolution notifications for its already-escalated subordinate needs. No strategic reserve: all directly controlled, enabled, non-reserved ammunition is usable.

Front demand continues normally. Per tick: transport, known-transport status, due messages, consumption/local observations,105 resolution. With a superior enabled, drain new zero-latency updates before arbitration; evaluate only at exact whole seconds; drain newly delivered orders afterward. The two extra bounded drains are skipped in prior feature-off runs. Existing idle inspector, manual demo,30FPS and low-processor settings remain.

## Knowledge and authority

`superior_need_reports` is a reconstructable private projection of delivered ESCALATION messages, not subordinate truth. The detached CommandView exposes only its owner's reports. Full snapshots include delivered report message/revision, sender, front/destination identifiers, reported quantities/rate, source sample/time and received time. Local direct ownership validates destination authority; no foreign inventory or front metrics enter allocation policy. Valid higher revisions supersede; stale/duplicate history remains without overwriting. A delivered resolution can create a tombstone even before the active report arrives.

Initial escalation already includes destination in105. Material changes send AMMO_NEED_UPDATE once per new revision; closure sends AMMO_NEED_RESOLVED. Time alone sends nothing. Last-attempted revision is persisted separately without changing need arithmetic. Send or delivery failure cannot change superior knowledge. Updates are snapshots, not a global synchronization channel; skipped intermediate material revisions need not each produce a message if superseded before the messaging phase.

Only actual delivered ORDER/AMMO_ALLOCATION_DISPATCHED permits recipient incoming registration. Envelope hierarchy and the named shipment's origin, destination, quantity and arbitration identity are validated. This targeted transport identity check is not an inventory/hidden-shipment scan. Arrived/blocked/destroyed cargo creates historical receipt only. Resolved needs stay resolved even if later cargo/notice arrives. Known105 transfer tracking handles subsequent arrival/failure.

## Exact staged policy

Required stock at5/15/20 seconds is integer ceil(rate_milli*threshold_ms/1,000,000), bounded by the accepted900,000,000 milli rate. Stage order is fixed. Candidate order: CRITICAL,CONSTRAINED,REFILL; exact increasing projected stock/rate; command ID; need ID. REFILL retains105's hysteresis urgency after the two specified bands. Continued-fraction comparison uses division/remainders instead of overflowing cross products; equal rationals remain exact.

Each stage uses reported available+reported incoming+successful dispatches in this cycle. No hidden cargo is added. Funding persists separately by report+revision; remaining is max(0,reported uncovered−successful funding for that revision). New reports may legitimately justify additional allocation while old cargo or updates remain unknown. At each stage the initial sorted order is evaluated once, not continuously re-sorted after each allocation. Source IDs are sorted, reserved quantities excluded, routes and direct dispatch authority revalidated. Real create/reserve/dispatch moves resources; arbitration events never mutate stock. Planned/failed dispatch does not increase projected stock or funding; failed planned shipments are cancelled. No funds are committed after stock exhaustion, but remaining evaluations record zero-allocation reasons for inspectability.

`usable_stock_before` and remaining quantities are ordinary exact integers within the authoritative JSON safe range. If an aggregate across individually valid sources exceeds that range, its exact journal total is decimal text rather than an inexact JSON number. A saturated total is used only for zero/exhaustion checks, never to choose a dispatch quantity; individual source availability remains exact. This does not extend the underlying2A ledger's numeric contract.

## Journal and causation

The common `decisions` projection supports `decision_type: RESOURCE_ARBITRATION`, multiple selected allocations and all candidate evaluations; `Simulation.decision_journal(command)` returns them. Each decision snapshots exact input reports/message IDs/revisions and source IDs, usable stock, stage arithmetic, quantities, reasons, dispatch results, shipment IDs and completion. `resource_arbitrations` stores stable cycle identity, and `superior_revision_funding` prevents repeat funding.

RESOURCE_ARBITRATION_STARTED/NEED_EVALUATED/COMPLETED, RESOURCE_ALLOCATION_SELECTED and SUPERIOR_RESOURCE_TRANSFER_DISPATCHED retain arbitration correlation and decision/need/revision links. Physical shipment events preserve arbitration correlation through autonomous arrival. Local need/known-transfer events retain their existing need correlation and link the delivered notification. Immediate notification send failure is separately journaled. Generic2A messages retain existing semantics.

## Reproduction and evidence limits

`./tools/run.ps1 -Mode arbitration` runs targeted checks and writes step106_results.json plus A–H and resolved-in-transit run packages under artifacts. `-Mode test` includes the632 foundation checks. `-Mode replay -Package res://artifacts/run_step106_A` verifies a package in a new process; substitute B–H or resolved_in_transit. `-Mode inspector-headless` verifies preserved startup safeguards.

A exercises actual105 need/self-help/eligible-peer exhaustion/escalation, superior aid, communication and local physical closure; its single requester has no eligible peer communication route. A uses zero uplink latency and0.2-second downlink, with0.5-second physical transit. B–H deliberately script signed local report snapshots through real communication to isolate exact arbitration contracts (including specified revisions4/5 and uncovered23); these are fixture inputs, not automatic needs generated from raw truth. Fronts still consume throughout. E explicitly creates200 local ammo while delaying its revision2 update; superior correctly allocates80 from delivered revision1. Separate real105 lifecycle coverage resolves locally before delayed aid/notification; cargo continues and cannot resurrect that need.

Coverage includes exact thresholds/large rational ordering/ties, input-order independence, private detached reports, malformed/foreign destination reports, zero rates, reserved/multi-source/no-source stock, route failures, duplicate revision caps, exact-boundary delivery, failed update/resolution/notification, cargo-before-notice, resolved-before-cargo, every relevant event prefix claims/physical conservation, event-only reconstruction and strict replay. No graphical playtest, profiling, production scale, platform export build, player input, strategy, officer model, additional resource or107 work is claimed.

Version-specific references checked2026-10-19: [Godot4.7 int](https://docs.godotengine.org/en/4.7/classes/class_int.html) documents signed64-bit wrap and integer division; [Array](https://docs.godotengine.org/en/4.7/classes/class_array.html) documents custom sorting. The actual4.7.2 build executes all checks. Authoritative JSON importer and equivalence comparison are unchanged.
