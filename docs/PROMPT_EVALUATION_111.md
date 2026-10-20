# Operational Command prompt evaluation (111)

Project0.3.2 / schema2C.3 on Godot4.7.2stable. Starting commit: accepted110 0497e61f9d7ef4c2c8a39d0e865cd783653bf57b. Frozen2A/2B tags remain unchanged. REQUIREMENTS_111.md and AMENDMENT_111.md contain the designer's complete bounded contract. No112 information requirements, reconnaissance, military orders or battlefield UI are implemented.

## Configuration and timing

An incoming OPERATIONAL command may set `strategic_prompt_evaluation_enabled: true`. Default is false. The approved representation amendment consumes this field before WorldDefinition projection and validates it separately; it never enters canonical commands, WorldState or COMMAND_CREATED. Local/unknown/duplicate configurations and non-boolean flags reject before any world event. Enabled configurations require a tick duration that divides one exact simulation second. Configuration queries return detached copies. Changing this configuration is not a runtime input in111.

The separately persisted player_prompt_evaluation_config.json contains a schema and canonically ordered command/enabled entries, with a manifest schema/file/SHA256. Replay initializes the canonical world, validated StrategicAreas and this configuration separately. Empty default configurations preserve110 behavior. Explicit false and true configurations produce identical canonical world artifacts.

At exact whole-second boundaries Simulation retains accepted world/message/report processing, including the existing zero-latency report drain, then calls the evaluator before accepted arbitration. Evaluation does not mutate simulation context or military state, so arbitration retains its existing ordering, IDs and effects. Prompts submitted externally after a boundary wait for the following boundary. Recipient commands are processed in command-ID order; each recipient's prompts retain accepted input order. Each pending prompt evaluates once and remains EVALUATED even if later reports arrive. Disabled commands/configurations leave prompts pending.

## Detached knowledge policy

The policy accepts only pending prompt identity, the configured area front ID, and detached recipient-scoped report provenance. It receives no Simulation, WorldState, AbstractFront, PlayerObserver, stock/shipments, or subordinate beliefs. The simulation obtains the accepted CommandView's identity/delivered superior_need_reports; a strict whitelist removes quantities and unrelated payload before interpretation.

Only current delivered ammunition-need report projections for the recipient and area front count. ACTIVE wins over RESOLVED. Primary selection uses ACTIVE before RESOLVED, latest report_received_at_micro, need_id ascending, then report ID for total deterministic ordering. All materially considered current report IDs and whitelisted snapshots are recorded in report-ID order; message IDs are unique and sorted. Older superseded messages do not replace the current projection. There is no new freshness cutoff. Source observation time, delivery time, need/revision and message/report IDs remain internal audit evidence.

| Knowledge | DIRECT_ATTENTION | REQUEST_ASSESSMENT |
|---|---|---|
| Active delivered report | KNOWN_CONCERN_PRESENT / ACTIVE_AMMO_SUPPLY_CONCERN | ASSESSMENT_AVAILABLE / ACTIVE_AMMO_SUPPLY_PROBLEM |
| Resolved only | NO_ACTIVE_KNOWN_CONCERN / LAST_KNOWN_AMMO_NEED_RESOLVED | ASSESSMENT_AVAILABLE / KNOWN_AMMO_NEED_RESOLVED |
| No supported report, or frontless area | FURTHER_INFORMATION_REQUIRED / NO_SUPPORTED_AREA_INFORMATION | Same |

These results interpret limited command knowledge. They do not certify objective battlefield safety. Merely enabling111 does not enable105/106 report creation; accepted delivered-report infrastructure remains the supported source. FURTHER_INFORMATION_REQUIRED creates no task, mission, message, fact or order.

## Persistence and public views

PLAYER_PROMPT_EVALUATED extends the existing prompt stream (schema2C.3.player-prompt.1), never events.jsonl. The prompt-event counter continues across submissions, receipts and evaluations; prompt IDs remain in successful submission order. An independent prompt-evaluation:N counter identifies evaluations. Records include prompt/recipient/area/type, evaluated_at, fixed result/code, primary report and all considered report/message/need/revision/timing provenance, stateCOMPLETED and evaluated-event reference. Prompt state becomes EVALUATED.

The same apply_event writer builds live and reconstructed projections, checks lifecycle/ID/previous-event lineage, exact boundary timing, report structure/order and result consistency with captured report provenance. Event-only reconstruction requires validated area configuration. Package replay independently regenerates evaluations from the actual delivered report projections and mixed input history; captured provenance alone is not treated as proof that a report existed. Hashes provide integrity, not cryptographic authorship.

PlayerPromptView adds only result, assessment_code and evaluated_at to its existing field allowlist. It retains no evaluation IDs, report/message/need IDs, raw report fields, quantities or arbitrary metadata, including in history/backing data. Recipient views preserve addressed-inbox isolation. Queries and held views remain detached snapshots. Trusted developer GDScript/audit exports can inspect internal evidence; these views are application boundaries, not a sandbox against arbitrary trusted code.

## Evidence and limitations

A–G use accepted scripted ESCALATION messages to isolate supported report delivery, resolution, exact boundary ordering, differing command knowledge and stale reports. Their single communication route deliberately prevents alternate paths from shortening intended latency. These are fixtures, not claims of generated local needs. H uses the unchanged full integrated autonomous hierarchy, including real105/106 reports and its existing network, with six prompts at ticks0,11,39,100,150,240 and a250tick horizon. Enabled/disabled comparisons require byte-identical canonical initial/final world, authoritative events, inputs and109observer files; only prompt config/events/projection and their manifest metadata differ. Separate zero-prompt toggles must produce no prompt/evaluation differences at all. Resource conservation and event-prefix reconstruction remain required.

Reproduce with tools/run.ps1 -Mode evaluations -TimeoutSeconds240; full foundations with -Mode test -TimeoutSeconds600; fresh replay -Mode replay -Package res://artifacts/run_step111_A (substitute B/C/D/E/F/G/H_enabled/H_disabled/zero_enabled/zero_disabled/multi_reports/multi_recipients); -Mode inspector-headless for preserved idle/manual-demo/30FPS/low-processor safeguards. Validation is headless. No graphical playtest, profiling or target-export-build claim.

GDD housekeeping pending — source files unavailable. No missing Generation2v0.1PDF/DOCX is fabricated. Stop at111 review;112 requires separate authorization after acceptance.
