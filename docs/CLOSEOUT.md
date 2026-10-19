# Prototype Generation 2A — acceptance and freeze

Closeout scope follows the designer's Acceptance & Closeout Brief v0.1 (package 102). No autonomous command behavior or other 2B implementation is included.

## Required fixes

`INFORMATION_INGESTED` explicitly inherits its originating message's correlation. Send, delivery and ingestion now retain one operation ID, and each ingestion's causation still points to its immediate delivery event. A generic optional correlation override at event commit keeps operation identity separate from immediate cause without changing belief selection, provenance, privacy or receipt timing. Targeted cases cover delayed and zero-latency reports, with two independent operations sharing a tick.

`MESSAGE_FAILED` now records `reason_code = ROUTE_DISABLED`, exact unavailable `failed_edge_ids` in route order, and `failed_edge_change_event_ids` identifying the corresponding disabling events. It retains the send operation's correlation and send causation. Targeted cases cover the demonstration's one-edge failure and two disabled members of a multi-edge route, no recipient belief/inbox update, and deterministic replay of all metadata.

## Validation commands

```powershell
./tools/run.ps1 -Mode closeout -GodotPath 'C:/path/to/Godot-4.7.2.exe'
./tools/run.ps1 -Mode test -GodotPath 'C:/path/to/Godot-4.7.2.exe'
./tools/run.ps1 -Mode inspector-headless -GodotPath 'C:/path/to/Godot-4.7.2.exe'
./tools/run.ps1 -Mode replay -GodotPath 'C:/path/to/Godot-4.7.2.exe'
```

The focused cases also run as part of the full suite. Counts are assertions including fixture setup, not independent gameplay scenarios. The full suite preserves event-prefix resource conservation, event-only reconstruction, private knowledge, hierarchy/authority, shipments and complete normalized state/event replay checks. Final counts, results and source identity are recorded in the developer closeout report beside the original handoff; generated JSON reports/logs remain in `artifacts/`.

## Accepted baseline

* Godot 4.7.2 stable; observed validation build `4.7.2.stable.steam.ed1daf0bf`.
* Simulation project version `0.1.1`; schema `2A.1`.
* Accepted tag: `prototype-gen2-2A-accepted`. The annotated tag and Git commit identify the exact frozen source. No tag is moved or replaced if it already exists.
* Original specification and clarifications remain in `docs/REQUIREMENTS_v0.1.md` and `docs/DESIGN_CLARIFICATIONS.md`. No persistent resource, authority, knowledge or shipment semantics were changed by closeout.
* Additive diagnostics retain the schema, while the project version changes to distinguish corrected event output. Old packages require their original revision to reproduce their original event metadata; they are not silently reinterpreted.

## Play-freeze status

A graphical Play freeze was reported during 2A. Reversible startup mitigations were applied and the user subsequently confirmed that the freeze no longer reproduces. Headless verification remains passing. The exact original cause and contribution of each mitigation were not isolated.

The accepted source includes the existing 30 FPS cap, low-processor idle mode, manual fixture start, milestone logging and optional standalone launcher. Closeout does not attempt another graphical reproduction or claim an engine/driver root cause.

## Deferred item and transition

Semantic-event versus high-frequency-trace separation is not a 2A blocker. Before 2B substantially increases simulation scale, review separate exports/channels, trace controls and retention while preserving reconstruction and replay guarantees. Current tick/progress events remain authoritative.

Once both regressions, the existing suite and replay pass, the final source is committed and tagged. This freezes 2A and provides the starting revision for a separately specified 2B task; no 2B feature work is inferred from this closeout.
