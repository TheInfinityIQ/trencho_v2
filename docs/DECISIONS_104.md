# Step 104 — local command cycle and decision journal

Project0.2.1/schema2B.2. Godot4.7.2 stable. Starts after accepted103 commit69f081fb2f2b1e8e2aea67d0ea189e393d6abd6c; the2A accepted tag is preserved.

## Activation and boundaries

A LOCAL command opts in with local_decision_front_id naming its directly responsible front in the world definition. The loader validates level, existence and responsibility; one command configures one front. The default is null, preserving non-autonomous kernel/front fixtures. No multi-front optimization or higher-command reasoning is implemented.

DecisionPolicy104 owns eligibility, threshold/score constants and tie order. LocalCommandPlanner receives only a detached CommandView, front identity, observation envelope and current simulation time. It has no Simulation, WorldState, resource/front service or authoritative registry reference. It reads current_belief and cites record IDs; the existing local-stockpile view is not used for policy.

DecisionJournal is the trusted kernel coordinator and event projection writer. It creates the filtered view, invokes the planner, persists candidates/selections/outcomes and asks FrontService to apply the action. AuthorityService checks LOCAL level, enabled state and direct front responsibility. The front pathway requires the matching selected decision and internal AUTONOMOUS_COMMAND_DECISION context. Policy never owns/mutates physical front/resource state.

## Complete observations and freshness

An autonomous front samples eleven InformationRecords after consumption/counter finalization: the nine103 facts plus FRONT_INTERVAL_DEMAND and FRONT_INTERVAL_CONSUMED. Those additions are actual canonical integer ammunition totals from the completed interval, with FRONT_OBSERVATION source, confidence1, identical observation time and shared cause.

Only after all11 ingestions does FRONT_OBSERVATION_COMPLETE persist an observation_batches record containing ID, command/front IDs, record_ids by fact, expected_fact_keys, observed_at_micro and complete=true. The batch ID links to the FRONT_OBSERVED cause; every fact ID is explicitly listed. Non-autonomous fronts retain nine facts and trigger no decision.

Planner verifies the complete11-fact schema, record ownership through CommandView, per-fact IDs matching the batch, common observed time, expiry/current-belief selection, canonical types/ranges and freshness<=1500000microseconds. The eight policy-required facts are all present; the three diagnostic/outcome records also must complete the declared sample. Incomplete/missing/stale/expired/mixed/invalid samples produce STARTED then SKIPPED with machine-readable reasons and affected keys. No candidates, posture mutation or world-truth fallback follows a skipped cycle.

The privileged EvaluateLocalDecision diagnostic input accepts command_id, front_id, record_ids, complete and observed_at_micro. It persists an explicit batch and runs the same validation/journal/action path; used for missing/stale/privacy/authority tests. It cannot inject information by itself. IngestInformation remains the existing privileged fact fixture pathway. Automatic cycles use the actual complete-sample signal only.

## Policy

Allowed candidates in fixed tie order: HOLD, REDUCE_ACTIVITY, PRESS. WITHDRAW remains debug-valid but is not considered autonomously.

Supply classification priority:
1. Any last shortage ->CRITICAL, including ZERO_DEMAND.
2. FINITE coverage<5000ms ->CRITICAL.
3. FINITE coverage<15000ms ->CONSTRAINED.
4. FINITE coverage>=15000ms or OUT_OF_RANGE ->SECURE.
5. ZERO_DEMAND with no recent shortage ->NO_ACTIVE_DEMAND.

Strength margin uses observed centi-strength minus centi-pressure. +/-2000 mark strong advantage/disadvantage; otherwise contested. PRESS requires secure supply, margin>=2000 and no shortage. Rejections retain SUPPLY_NOT_SECURE, INSUFFICIENT_STRENGTH_MARGIN, RECENT_AMMO_SHORTAGE as applicable. Ineligible candidates have null score and no fabricated utility.

Integer factors:
- HOLD: base50, contested+20, constrained+15, secure+10, critical-20.
- REDUCE_ACTIVITY: base20, shortage+100, critical+60, constrained+25, strong disadvantage+10, secure-20.
- PRESS if eligible: base30, advantage+40, margin>=4000 additional+20, secure+20.

Every factor code/contribution is journaled. No random rolls, floating utility, personalities or balancing claims. The fixed tie order is independent of candidate array order and the selected record marks tie_break.

## Projection, causation and actions

New snapshot registries: observation_batches, decisions, decision_candidates. All changes apply through authoritative events. Stable typed IDs derive from event sequence, never display names or array positions. New states/fields use canonical integer microseconds for times and integer scores.

Decision record includes command/front, trigger/batch IDs, started/selected times, state, belief values, belief_record_ids and explicit per-fact provenance map, candidate IDs, chosen candidate/action/score, classifications/tie flag, action_required/success/error/changed/event ID and outcome fields. Query Simulation.decision_journal(command_id) returns detached developer records. Planner does not receive this trusted query surface.

Events:
- DECISION_STARTED: cause complete batch/request event.
- DECISION_CANDIDATE_RECORDED: cause STARTED; candidate action/eligibility/score/factors/reasons and provenance in its projection.
- DECISION_SELECTED: cause selected candidate event.
- DECISION_SKIPPED: cause STARTED.
- DECISION_ACTION_RESOLVED / DECISION_ACTION_FAILED: cause posture-change event if one occurred, otherwise selection.
- DECISION_OUTCOME_ATTACHED: cause subsequent complete observation batch.

All decision events share correlation_id=decision_id. A real autonomous FRONT_POSTURE_CHANGED also carries the command actor, decision ID, source/reason AUTONOMOUS_COMMAND_DECISION and selection causation.

A chosen action matching believed posture sets action_required=false; it still produces a complete decision journal. If an action is required but the actual front already has that posture, the validated pathway returns changed=false. Neither case emits a fake posture mutation. Failed authority records action_success=false/error code and cannot receive an executed-action outcome. Privileged103 setter result semantics remain unchanged.

## Outcomes and ordering

After a subsequent complete, valid observation at least one second after successful selection, attach the descriptive outcome before starting the new cycle. It contains starting/ending observed available ammunition, coverage/status, pressure/strength, selected action, start/end canonical times and actual observed interval demand/consumption/shortage. Ending records are cited by ID/key; starting provenance stays in the decision. No reward, grade, fitness or learned policy update is generated.

At each boundary: tick demand ->ResourceService consumption ->shortage ->interval finalization ->all observation records ->complete signal ->prior outcome ->new start ->three candidates ->selection ->validated action. New posture affects future ticks only. If a later sample cannot validate, a pending outcome waits for a valid complete sample; no retrospective truth query repairs it. The final decision of a bounded demo remains pending when the run stops before its next observation.

## Reproduction and observed scenarios

PowerShell7 runner modes:
- test: complete foundation and104 suite.
- decisions:104-only checks and scenario summary artifacts.
- decision-demo: scenarioA, exports artifacts/run_step104.
- replay -Package res://artifacts/run_step104: separate-process replay.
- inspector-headless: existing idle/manual demonstration safeguards.

Pass -GodotPath <Godot4.7.2 executable>. Runs can be bounded with -TimeoutSeconds25.

ScenarioA: strength80,pressure40,base10,stock200 ->PRESS110. First second demand4; following seconds6 each; final184stock/16consumed, three cycles/two outcomes.
ScenarioB: strength60,pressure50,stock200 ->HOLD80, PRESS rejected for margin; final188stock/12consumed.
ScenarioC: stock2 ->shortage2 at second1, REDUCE180. No supply creation; final0stock/2consumed.
ScenarioD: initial shortage ->REDUCE180; create200ammo through ResourceService at second1; next complete observation ->HOLD80; third interval resumes4 demand. Final202created/8consumed/194stock.

Tests include exact thresholds/ties, critical-over-zero precedence, expiry/freshness1.5second boundary, partial/old-nine/mixed samples, policy and outcome truth-isolation fixtures, owned provenance, unrelated-command failure, same-posture no-ops, journal/event reconstruction, every-event conservation, independent runs/different policy seed, strict file replay and no automatic messages/shipments/reservations.

## Scope and limitations

One configured LOCAL/front pair per command; no multi-front policy. The existing inspector continues to display the accepted kernel demo;104 inspection is via developer journal/run JSON and headless fixtures. No rendered performance, hardware profiling or exported build claim. Startup mitigation settings are unchanged.

No105, supply requests, peer collaboration, escalation, automatic dispatch/reservations, higher-command planning, player interaction, tactical units, withdrawal mechanics, personality or learning. Stop at104 acceptance and return completion evidence.
