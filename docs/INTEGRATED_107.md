#107: unattended autonomous command slice

Project0.2.4/schema2B.5, actual Godot4.7.2.stable.steam.ed1daf0bf. REQUIREMENTS_107.md preserves the designer packet; AMENDMENT_107.md explicitly supersedes the physical-closure interpretation of§20/milestone13. Accepted103–106 decision, need, peer and arbitration policies are unchanged.

## Fixed fixture and purity

`debug/integrated_demo.gd` constructs the supplied world: OPERATIONAL_COMMAND,LOCAL_A/B/C, three fronts,100ms tick. Front initial stock120/80/20; B reserve30,C reserve8; HQ50; initial strategic cargo60 arriving15seconds. Strength/pressure80/40,60/50,50/70; allbase demand8 andpostureHOLD. Required peer latency0.2s, local↔HQ0.3s; selfhelp0.5s, peerreserve1.0s, HQ→front2.0s. No extra logistics edges or stock tuning.

The run calls initialize then advance250, without execute, bootstrap dispatch or EndRun. Inputs.jsonl is empty. The25second horizon is a snapshot, not a forced clean shutdown; legitimate messages due after250 and latest local outcome cycles remain pending. No state-changing runtime input or artificial cleanup is added.

## Narrow initial-cargo extension

Previous definitions required empty initial shipments.107 explicitly authorizes already-dispatched environmental cargo. `initial_cargo.gd` adds optional `initial_in_transit_shipments` at definition time: canonical enabled origin/destination/resource, positive legal quantity, simple enabled contiguous route ending at destination, optional valid requester. The origin stock remains0; the already-in-transit quantity is counted once in initial created total. There is no active/fulfilled fabricated reservation or runtime resource creation. Initial total is308physical stock+60cargo=368.

Snapshots reconstruct these definitions and must match canonical initial cargo exactly: stateIN_TRANSIT, progress0, departed/created0, reservationnull, no arbitrary extra state. Existing dynamic initial tables stay empty. INITIAL_CARGO_RECORDED gives explicit initialization/correlation provenance; existing transport advances and arrives naturally. Importer/replay comparison are unchanged. Negative/fractional/zero ammo, missing entities/resources, invalid/colliding IDs, disconnected routes and tampered snapshot state/claim/progress are rejected.

## Observed behavior and acceptance amendment

At1second A selectsPRESS,BHOLD,CREDUCE_ACTIVITY. C sends8 from own reserve, triesA (no usable aid route), negotiates real30 fromB reserve, then escalates remaining need at2.2seconds. HQ initial50 is dispatched toC across accepted arbitration cycles. At15seconds, initial60cargo arrives; normal scarcity arbitration sendsC51,B9. A/B also develop needs without injected requests.

A first ceasesPRESS as supply tightens. Its need later closes at12seconds with observed66, planning rate3200 and recalculated20secondtarget64, shortage0. It has received no resupply. This is documented as dynamic target-based closure, not physical-resupply closure. The designer's explicit amendment accepts this and separately requires evidence that C's physical aid changes observed need/command state. C self/peer/superior arrivals increase subsequently observed stock and feed linked need revision and local decision records. C remainsACTIVE at250, as doesB and a later newA need. The original C need is not forced closed.

The policies can oscillate between postures near supply thresholds.107 records this behavior without hysteresis/cooldown/scoring changes. It is not graded as strategic competence or optimized away.

## Causal and isolation audits

`tests/integrated_audit.gd` follows explicit entity relationships: need observation_batch_id, batch belief IDs, local decision batch, need/coordination IDs, request/offer/acceptance message IDs, bound reservation/peer cargo IDs, escalation source message, delivered report IDs/revisions, arbitration selection and shipment identity, delivered order, known-transfer record and physical arrival.

Arrival→observation proof uses authoritative event order and declared front supply-stock IDs as a read/write dependency, not timestamp proximity: collect actual writes from SHIPMENT_ARRIVED, project intervening consumption, then read the next complete sample of that same stock through its front/batch/information IDs. Before/after belief IDs and quantities, last stock-write event and subsequent need/decision IDs are retained. This is a diagnostic derivation; it does not invent new kernel causation events or retroactively claim a direct event.causation_event_id where none exists. Evidence includes all three C aid origins and its full escalation/allocation chain.

LOCAL detached views contain own observations/inbox/inventory only. Every local decision's eleven records match its owned complete batch. Superior decisions snapshot delivered reports with exact message/revision and own usable stock; no foreign inventory is introduced. Incoming from another command requires its delivered named notification. Existing106 privacy/authority tests remain mandatory.

Every authoritative event prefix checks ledger/stock/cargo/claims and exact event-only reconstruction. All75local cycles and superior decisions remain inspectable. Stability checks cover oneactive need percommand, bounded conversations, no duplicate escalation/update revision, one request perconversation, funding caps by delivered revision, no active claims/offers at the horizon, no orphan cargo and no overdue unresolved message. Future-due messages and unobserved final outcomes are explicitly permitted horizon state.

## Reproduction

Run `./tools/run.ps1 -Mode integrated -TimeoutSeconds90` for107 checks/report/package; `-Mode test -TimeoutSeconds120` for accepted foundations plus107. Replay in a fresh process with `-Mode replay -Package res://artifacts/run_step107 -TimeoutSeconds90`. `-Mode inspector-headless` checks preserved idle/manual-demo/30FPS/low-processor safeguards. No graphics or optional UI work is needed.

`artifacts/step107_results.json` includes assertion results, event type/family counts, bytes, posture/need timeline, completeC causal audit with actual IDs, scarce arbitration journal, needs/conversations/shipments and ledger. The numbered completion report accompanies the full package and hash manifest. Runtime replay duration is reported only if measured by the harness; no profiler/scale/platform-export claim.

107 proves only unattended operation of the current abstract front command/logistics hierarchy. It does not establish full game autonomy, victory/enemy AI/economy, player preferences or2C. Stop at107 acceptance review.
