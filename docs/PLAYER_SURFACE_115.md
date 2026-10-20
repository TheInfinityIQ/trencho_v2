# 115 player observer surface

F5 now opens `player/battlefield.tscn`. Four deterministic area cards show only the accepted PlayerObserverView projection. Selecting a card is local UI state; the two strategic buttons send the existing DIRECT_ATTENTION or REQUEST_ASSESSMENT through SubmitPlayerPrompt. The default fixture is the accepted autonomous integrated fixture with109–114 enabled, without changed military policy.

`battlefield_screen.gd` receives only detached public observer/prompt views, channel availability and replay status. Its text and tooltips contain no WorldState or CommandView data. The trusted `game_session.gd` owns simulation execution and routing. Routing reuses110 scope validation, chooses the nearest eligible Operational ancestor for a front, and disables ambiguous or unavailable frontless channels. No raw routing identity appears in player text.

The sidebar distinguishes current observer cues, immediate submission acknowledgement, pending command response, original111 result and later114 assessment. An acquired assessment retains its own observed time in MM:SS and four qualitative fields. It does not replace current observer cues or explain differences using hidden truth. Attention acquisition does not display inquiry answers. Replay rendering disables request controls.

ATTENTION_ONLY and ATTENTION_AND_INQUIRY are session/UI settings. Selection, layout and variant are not persisted into the authoritative world or replay input history. The default is the two-action variant. This is a deterministic four-card greybox layout, not a geographically accurate map.

The graphical scheduler permits at most one exact0.1-second simulation tick per frame. Long-frame debt is discarded; invalid deltas are ignored. The30FPS cap, low-processor setting and GL Compatibility renderer remain. After a rendering stall simulation may lag wall time. The deterministic kernel is unchanged. The explicit `debug/inspector.tscn` remains the original idle/manual developer scene, with no player-scene shortcut.

## Verification entry points

- `tools/run.ps1 -Mode test -TimeoutSeconds 1800`: existing full1669-check foundation.
- `-Mode player-ui -TimeoutSeconds 300`:115 integration/UI assertions without a graphics device.
- `-Mode player-graphical -Package 720 -TimeoutSeconds 300`: same scenarios through mouse events and the normal renderer, screenshots1280×720.
- `-Mode player-graphical -Package 1080 -TimeoutSeconds 300`:1920×1080.
- `-Mode player-replay -TimeoutSeconds 180`: separate-process strict replay and player history rendering.
- `-Mode inspector-headless`: unchanged developer-inspector startup regression.
- `-Mode inspector`: explicit diagnostic launch.

Supply an explicit `-GodotPath` when the runner cannot discover the validated Godot4.7.2 executable. The renderer test records the actual adapter/method, viewport, autonomous250-tick duration, prompt identities, public text, conservation and assertion results. A scripted pressure change in the disagreement case and scripted escalation in the immediate-knowledge case are controlled fixture setup, not player capabilities.

The complete designer requirements and approved startup amendment accompany this contract. Stop after115 evidence handoff and await the human's further instructions. The proposed next packet is2C integrated acceptance/evaluation and a freeze decision; it is not authorized to start automatically.
