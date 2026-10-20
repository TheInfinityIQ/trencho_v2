# Approved113 fixture clarification

Designer approval: preserve accepted one-second observation cadence/generation and snapshot validation. Nonassigned or disabled/known-impossible Local observation is unavailable; assigned observation-capable commands may wait.

The accepted snapshot validator rejected a modified initial next-observation timestamp with INVALID_SNAPSHOT / INCONSISTENT_INITIAL_PROJECTION. No production exception was added. Freshness tests use an actual completed batch and source records at controlled query times.

+Yes. That nearest-existing integrated case is approved and satisfies the fallback.

Use it as a **targeted fixture**, not as evidence that ordinary autonomous observation naturally enters this state.

The important sequence is:

```text
t = 1.0
normal FRONT_OBSERVATION_COMPLETE
→ coherent eleven-fact batch A

t = 1.1
accepted IngestInformation updates one relevant Local fact
→ current Local belief set no longer corresponds to one coherent completed front-observation batch
→ do not combine injected fact with batch-A facts
→ do not search backward and reuse batch A merely because it is still <1.5s old

t = 1.2
AREA_SITUATION_REPORT_REQUEST arrives
→ no valid current complete batch
→ WAITING_FOR_LOCAL_OBSERVATION

t = 2.0
normal accepted observation process produces complete eleven-fact batch B
→ coherent current batch restored
→ report generated from batch B
→ normal return communication proceeds
```

Lock these assertions:

- The `IngestInformation` mutation must **not** itself count as `FRONT_OBSERVATION_COMPLETE`.
- The collector must not synthesize a hybrid report from batch A plus the injected fact.
- It must not opportunistically fall back to batch A after a newer relevant belief has superseded part of that coherent snapshot.
- It must not read raw `AbstractFront`/WorldState to fill the missing consistency.
- The eventual response must cite the actual batch-B identity and its actual source InformationRecord IDs.
- The test should state explicitly that the privileged ingestion is a controlled test perturbation used to create an otherwise difficult-to-reach current-belief inconsistency; it is not being claimed as the normal gameplay acquisition path.

Then retain the separate pure sampler tests for the actual freshness boundary:

```text
age < 1.5s  → usable
age = 1.5s  → usable
age > 1.5s  → stale/unusable
```

This combination is sufficient for Scenario C and D without weakening snapshot validation, changing observation cadence, or adding production-only behavior for the test.

Continue 113 only.
