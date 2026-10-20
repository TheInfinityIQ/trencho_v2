# Approved115 startup amendment

+Approved. For **115**, make the new greybox battlefield the default F5/main-scene entry point and preserve the existing idle developer inspector as an explicitly launched diagnostic scene.

This is the correct default now that 115 is the first player-facing slice. A normal project launch should enter something the player can actually watch and interact with, rather than an intentionally inert engineering surface.

Treat this as a bounded 115 startup amendment.

### Default entry

Use:

```text
F5 / project main scene
→ 115 Greybox Battlefield Observer
→ autonomous simulation begins without requiring player input
```

The existing developer inspector remains available through its explicit developer launch path only:

```text
explicit inspector scene/tool launch
→ existing idle/manual behavior
```

Do not put an inspector link, omniscient-data button, or developer shortcut into the normal player-facing UI.

### Preserve the freeze mitigations

Keep the accepted resource safeguards:

```text
30 FPS cap
low-processor / low-idle-cost behavior where applicable
fixed simulation step = 0.1 s
```

The player scene may autonomously drive the simulation, but it must use a bounded graphical scheduler.

Approved rule:

```text
0 or 1 simulation tick per rendered frame
each simulation tick = exactly 0.1 simulation seconds
```

Do **not** implement an unbounded:

```text
while accumulator >= 0.1:
    simulate_tick()
```

catch-up loop.

That could recreate the class of runaway workload the earlier startup mitigation was intended to prevent.

### Wall-clock debt

Also do not retain arbitrarily large accumulated wall-clock debt after a long frame or stall.

Use a bounded accumulator policy equivalent to:

```text
accumulate elapsed wall time

if enough for one 0.1 s simulation step:
    run exactly one fixed simulation tick

discard/clamp excess catch-up debt so it cannot grow without bound
```

The exact implementation is developer latitude, but these properties are required:

- simulation steps themselves remain exact 0.1-second ticks;
- no simulation tick is partially advanced;
- no multiple-tick burst occurs in one graphical frame;
- a rendering stall may make the simulation temporarily run **slower than wall clock**;
- it must never cause a large catch-up burst.

That slowdown is acceptable for this prototype and preferable to destabilizing the machine.

Do not change the deterministic headless/replay kernel to accommodate graphical timing.

### Important evidence interpretation

For 115 graphical autonomy comparisons, compare by **simulation tick/time**, not by elapsed real-world seconds.

For example, if the integrated evidence target is:

```text
250 ticks
= 25.0 simulation seconds
```

the graphical fixture should prove it reaches and correctly executes those 250 sequential fixed ticks while untouched.

Do not require exactly 25 wall-clock seconds if rendering stalls occurred.

### Separation of responsibilities

Keep this architecture:

```text
Simulation
→ deterministic fixed 0.1 s steps

Graphical player scene
→ bounded scheduler deciding when to request next step

Developer inspector
→ accepted separate idle/manual scheduler
```

The main-scene change must not alter the simulation kernel's fixed-step semantics.

### Regression requirement

Lock both entry points separately.

**Player main scene:**

```text
F5
→ greybox battlefield
→ autonomous simulation advances
→ zero clicks required
```

**Developer inspector:**

```text
explicit inspector launch
→ retains accepted idle/manual behavior
→ no autonomous-running regression introduced
```

The existing inspector regression test should remain unchanged where practical. Add separate 115 tests for the new player startup path rather than redefining what the inspector means.

Also verify that simply instantiating/rendering the player scene does not submit a prompt. Autonomous military behavior should begin because the simulation is running, not because the UI fabricated gameplay input.

### One additional graphical guard

Add a deliberate long-frame/stall test to the 115 scheduler if inexpensive. Inject or simulate a large frame delta and verify:

```text
one frame
→ at most one 0.1 s simulation tick
```

with no burst of queued catch-up ticks on subsequent frames.

This is specifically a startup/runtime safety test, not a change to simulation semantics.

So the approved 115 default is:

> **F5 opens the actual greybox observer experience and the war runs autonomously. The developer inspector remains a separate explicitly launched diagnostic surface with its existing idle/manual behavior.**

Continue **115 only**.
