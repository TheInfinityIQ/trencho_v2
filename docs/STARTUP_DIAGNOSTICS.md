# Pressing Play caused a near-system freeze — investigation, 19 October 2026

The user reported a severe freeze when pressing Play in Godot. No graphics reproduction was attempted during this investigation.

Closeout status: A graphical Play freeze was reported during 2A. Reversible startup mitigations were applied and the user subsequently confirmed that the freeze no longer reproduces. Headless verification remains passing. The exact original cause and contribution of each mitigation were not isolated. This does not block 2A acceptance; any recurrence should be investigated from its new reproduction.

## Observed evidence

* The latest normal launch log identifies Godot 4.7.2 stable, OpenGL Compatibility, NVIDIA RTX 4070 Ti, driver 610.47. It contains no script error, but lacks startup stage instrumentation, so it cannot establish how far the scene progressed.
* The supplied fixture runs 17 logical ticks and stops. There is no `_process`/`_physics_process` simulation loop in the inspector. Its entire exported event file is about 59 KB. These observations make an expected large simulation workload unlikely; they do not prove that the process could not have allocated excessive memory during the freeze.
* The editor settings of both the installed engine and validation copy contain `run/window_placement/game_embed_mode = 0`, i.e. embedding is enabled. Earlier rendered verification launched standalone and did not exercise the editor's embedded Play path.
* At the later inspection there was no running Godot process, approximately 6.6 GiB of system memory was free, and current GPU use was 1,370 MiB / 12,282 MiB with 7% GPU utilization. These are recovery-time measurements, not measurements of the freeze.
* Windows Application Error event 1000 records an earlier Godot executable access violation (`0xc0000005`) at 00:00:52 on 19 October. That predates this package's implementation/validation; it is not evidence that this specific incident had the same cause.
* The inspected six-hour log queries returned no matching display-reset or resource-exhaustion event identifying this incident. The absence of such a record does not rule either cause out.

## Working hypothesis and limits

The difference between embedded Play and the successful standalone smoke test makes the engine's embedded-window/rendering path a useful first suspect. A primary Godot issue report describes a whole-system allocation runaway in embedded Play: https://github.com/godotengine/godot/issues/122221 . Its versions/renderers differ (reported 4.7.1/4.6.3 Mono, Forward+ Vulkan/D3D12), so it is corroboration of a possible mechanism, not a diagnosis of this OpenGL/GDScript project. The issue was closed without a maintainer-confirmed fix/reproduction.

The cause remains unconfirmed. CPU, RAM and VRAM were not sampled during the user's freeze. Neither excessive simulation load nor a driver fault has been demonstrated for this incident.

## Reversible mitigations

* The developer inspector now caps rendering at 30 FPS and uses low-processor/redraw-on-demand mode with a 33,333 microsecond idle sleep. These affect presentation, not logical simulation time.
* Pressing Play now opens an idle inspector. The demonstration starts only when Run demonstration is clicked. Milestone logs distinguish view construction from simulation execution and record the demonstration/text preparation duration.
* `tools/open_inspector.ps1` is an optional standalone launcher, bypassing editor embedding. It was created but not launched during this investigation.
* To change normal editor Play, open the Game screen's top-right menu and disable **Embed Game on Next Play**. This is a user editor preference and was not automatically changed for other projects.

The documented Godot controls are at https://docs.godotengine.org/en/4.7/tutorials/editor/game_embedding.html and https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html . The cap and idle mode reduce avoidable work; they do not establish that the freeze is fixed.

## Validation boundary

Only headless checks are used for this mitigation. `tests/inspector_headless.gd` checks idle startup, cap/idle settings, explicit demonstration and export/replay. The existing rendered smoke test is adjusted for manual startup but is intentionally not executed during the freeze investigation. Full graphical and embedded Play reproduction remains unverified.
