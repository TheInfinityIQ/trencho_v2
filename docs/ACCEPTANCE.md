# Requirements-to-verification map

The machine-readable result is `artifacts/acceptance_results.json`. Check counts include individual assertions and fixture prerequisites; they are not presented as independent test scenarios. All acceptance groups in §§49–54 are represented.

| Requirements | Implementation and verification |
| --- | --- |
| §§1–5: new project / scope | Separate project, no imports from prior prototype, no forbidden gameplay; source review |
| §§6–9: clock, IDs, event-applied world | `simulation`, `clock`, `world_state`, `event_store`; same-input determinism, fixed tick, detached queries and event-only reconstruction |
| §§10–12: data entities and stock | Definition loader; ID validation, dictionary access, physical/reserved checks |
| §§13–14 / §49: resource conservation | No double spending, claim consumption/release/invalidation, dispatch transfer, cancel before dispatch, no cancellation teleport, arrival/destruction exactly once, independent audit of every event prefix |
| §§15–22 / §50: logistics | Directed shortest routing, equal-cost edge IDs, disabled edge exclusion, no-route atomic failure, overshoot across multiple edges, interruption, explicit reroute from last reached intermediate location, abandoned progress logging, disabled destinations, invalid quantities, destruction |
| §§23–25 / §51: hierarchy and authority | Parent/child and siblings, cycles/self-cycles, reparent projections/event, direct authority, no inherited authority, disabled command history, privileged bypass logging |
| §§26–29 / §52: communication | One/multi-edge delivery, stable equal-cost path, no route, sibling path, in-transit privacy, disabled route failure, no belief on failure, delivered history, zero-latency boundary |
| §§30–34 / §53: private information | Filtered detached CommandView, provenance, no global-truth ingestion, observation/receipt/ID selection, expiration boundary, preserved conflicts, stale superior/newer subordinate knowledge |
| §§35–39: event/causal history | All mutations use projection events; causal references point backward, autonomous delivery retains correlation, future decision envelope serializes without production fake records |
| §§40–44 / §54: export and replay | Five-file package, normalized final state/event equality from disk, identical same-seed runs, different-seed ownership, event-only reconstruction, failed-input replay, unsupported/corrupt snapshot rejection |
| §§45–46: boundaries | RefCounted services; commands get filtered views, messages do not allocate stock, creation never delivers stock, edge changes never directly create beliefs |
| §§47–48: required demonstration | `debug/demo.gd`; explicit alternate reroute and corrected send-then-disable failure; final distribution 400/100/300/200 |
| §55: basic performance structure | Map lookups and incremental source/owner/belief/inbox indexes; active transit iteration; source review, no scale measurement claimed |
| §56: developer view | Actual rendered inspector smoke: initialize, run demo, export, verify replay, save capture; image visually inspected |
| §§57–59: data/schema/test separation | JSON world, 2A.1 schema, isolated debug/tests, explicit logged privilege |
| §§60–64: extension/handoff | Generic resource test adds a fractional synthetic resource via data; module/schema docs and source checkpoint; no future gameplay policies |

## Checks run for the handoff

* Headless acceptance script on installed Godot 4.7.2 stable, using a workspace-local copy of the same binary.
* Headless editor import with no engine/script errors after directing validation data into writable storage.
* Main scene headless startup.
* Rendered inspector on the available Windows/OpenGL system, including its export/replay action and an inspected screenshot.
* CLI replay in a new engine process against the exported demonstration package.

The handoff records the final check count, engine string, commit hash and replay result. No executable export, device test, multiplayer test, or performance benchmark was required or claimed.
