# Command-generated information requirements (112)

Project0.3.3 / schema2C.4, Godot4.7.2stable. Starting point: accepted111 62d0e95e4330a3ee54d5d63a514e925561a79918. Frozen2A/2B acceptance tags remain unchanged. REQUIREMENTS_112.md preserves the full designer packet. No113 collection pathway, fulfillment, subordinate task/message, military effect, resource cost, prioritization or battlefield UI is included.

## Independent configuration and source

An OPERATIONAL command can explicitly set strategic_information_requirements_enabled. Default is false. The same111 extraction/validation pattern strips this separate112 flag before canonical WorldDefinition projection. Unknown/Local/duplicate configuration, malformed entries and non-boolean flags reject before world initialization. player_prompt_information_requirement_config.json persists the separately validated command/enabled entries with schema/hash. There is no runtime flag input. Requirement generation needs an actual qualifying111 evaluation; enabling112 alone cannot evaluate a prompt when111 is disabled.

Prompt policy and111 event semantics remain unchanged. Immediately after each successful PLAYER_PROMPT_EVALUATED projection, an ordinary synchronous Godot signal hands a minimal detached envelope directly to the requirement store. The envelope contains only prompt/evaluation/recipient/area identity, prompt type, fixed result/code, evaluation time/state and the prompt-stream evaluation-event reference. No report payload, observation, front, quantity, inventory, shipment, belief or Simulation reference is passed. The store retains only area IDs/enabled status, Operational owner IDs, configuration and whitelisted source envelopes. It has no WorldState, InformationService, PlayerObserver or transport capability.

The signal is connected without deferred flags, so each source immediately opens/links before the next pending evaluation and before accepted arbitration. The syntax and connect/emit API were checked against the [official Godot4.7 Signal documentation](https://docs.godotengine.org/en/4.7/classes/class_signal.html), then exercised on actual4.7.2. An explicit multi-prompt test observes requirement event counts1,2,3 at each evaluation signal at the same boundary.

## Work-item semantics

Only COMPLETED111 evaluations with FURTHER_INFORMATION_REQUIRED plus NO_SUPPORTED_AREA_INFORMATION qualify, for either DIRECT_ATTENTION or REQUEST_ASSESSMENT. Exactly one requirement type exists: AREA_SITUATION_ASSESSMENT. State is always OPEN; reason is PLAYER_PROMPT_INFORMATION_GAP. Supported active/resolved knowledge creates none. Frontless supported StrategicAreas can have a normal knowledge gap.

One OPEN record exists per owner/area/type. Its first qualifying evaluation allocates information-requirement:N from a counter independent of world, prompt, evaluation, observer and requirement-event counters. Later qualifying evaluations append first-link prompt/evaluation provenance and update last_updated_at on the same record. Reprocessing an identical source is idempotent. Provenance is never sorted after linking. created_at remains fixed. A later report or elapsed time cannot fulfill, close or update the requirement.

Records contain only requirement ID/type, Operational owner, area ID, OPEN state, creation/update times, ordered source prompt/evaluation IDs, fixed reason and empty metadata. A requirement is a recognized gap, never a battlefield fact. It is not an InformationRecord and does not manufacture command beliefs.

## Separate stream, views and reconstruction

information_requirement_events.jsonl has independent information-requirement-event:N IDs and INFORMATION_REQUIREMENT_OPENED/LINKED events. previous_requirement_event_id is the requirement stream's own global append chain. source_prompt_id, source_evaluation_id and source_evaluation_event_id are explicitly typed references into accepted prompt/evaluation history, not authoritative causation IDs. Event metadata must be empty. The same apply_event writer builds live and reconstructed projections, validates IDs/lineage/times/type/state/ownership/source qualification and suppresses duplicate OPEN keys or duplicate source links.

Event-only reconstruction receives validated areas/owners/config and a registry reconstructed from111 prompt events. It rejects nonexistent or nonqualifying sources. Full package replay additionally regenerates the entire source evaluation history and the requirement stream from mixed inputs, accepted delivered knowledge and configuration; captured provenance is not treated as proof of its own authenticity.

Simulation.information_requirement_view(command_id) supports open_requirements(), requirement(id), recent_history(limit=50), snapshot(). These are detached owner-scoped snapshots; another Operational command cannot retrieve the owner's records by ID, and Local/unknown commands receive no records/history. Normal PlayerPromptView is unchanged and gains no requirement ID or payload. Developer diagnostics can inspect full typed provenance. These are trusted-application boundaries, not a sandbox against arbitrary developer GDScript.

Packages include the separate config, events, final_information_requirements.json (state and recipient views), manifest schemas/fixed filenames/SHA256 hashes, including empty streams. Existing109/110/111 schemas and integrity checks remain intact. Existing authoritative importer/comparer is unchanged. All requirement comparisons are exact, without run-ID stripping or numeric normalization. Hashes establish integrity, not cryptographic authorship. Old-schema artifacts remain reproducible with their frozen source; no migration is implemented.

## Verification and limits

A–G isolate assessment/attention/frontless gaps, supported active/resolved knowledge, repeated links, multiple areas, player-observation isolation and multiple owners. Scripted reports use the accepted report pathway inherited from111; they are fixtures rather than claims of generated local needs. H uses the unchanged full25-second autonomous hierarchy and six identical prompts. Enabling/disabling only112 must leave all canonical world, inputs, observer and111 prompt/evaluation files byte-identical; only112 config/events/projection and their manifest metadata differ. No-prompt and evaluation-disabled configurations must generate nothing. Later supported knowledge never fulfills an OPEN item.

Reproduce: tools/run.ps1 -Mode requirements -TimeoutSeconds240; full suite -Mode test -TimeoutSeconds900; fresh -Mode replay -Package res://artifacts/run_step112_A (substitute B/C/D/E/F/G/H_enabled/H_disabled/J_zero_enabled/J_zero_disabled/evaluation_disabled/requirements_disabled); -Mode inspector-headless. Verification is headless; existing idle/manual-demo/30FPS/low-processor startup mitigations are preserved. No graphical playtest, profiling or target-export-build claim.

GDD housekeeping pending — source files unavailable. No missing Generation2v0.1PDF/DOCX is fabricated. Stop at112 review;113 requires acceptance and separate authorization.
