# Step 103: abstract fronts and local observations

Project 0.2.0, schema 2B.1, Godot 4.7.2 stable. This bounded extension follows accepted 2A commit 213f2faf98d7ac2a3ad11d25afa698578a69b161. The annotated tag prototype-gen2-2A-accepted is preserved. Old 2A packages use their tagged source; this loader rejects a different project/schema version.

## Module ownership and inputs

- front_definition.gd validates static/runtime creation, supply-location association, quantization and effective rate.
- front_service.gd prepares tick projection changes, resolves integer demand through ResourceService, finalizes one-second counters and ingests nine local facts through InformationService.
- authoritative_json.gd repairs authoritative artifact integer import; it leaves ordinary fixture JSON loading untouched.
- WorldState stores fronts and indexes active front IDs; Simulation coordinates their processing.
- ResourceService owns actual ammunition consumption and ledger changes. Its internal front capability requires the scoped FRONT_SIMULATION actor context; assignment grants no allocation/dispatch authority.
- front_demo.gd and front_world.json exercise the prescribed fixture without rendering.
- front_cases.gd is included in the full acceptance runner and can run separately with -Mode fronts.

Privileged inputs: CreateFront {front}; SetFrontEnemyPressure, SetFrontFriendlyStrength, SetFrontPosture, SetFrontEnabled {front_id, value}. Setters validate before committing; invalid input cannot mutate front state. All returned front records are detached copies.

Supply stock must exist at the front location or at an explicitly directly controlled location of the responsible command. No ancestry-based authority is inferred. Disabled fronts, commands, front locations or supply locations/stockpiles suspend front simulation.

## Numeric contract

Designer approved fixed point after strict JSON replay exposed a binary float discrepancy. No tolerance was added to normalize/equivalent. Only the new front representation changes; accepted resource/time representation remains intact.

| Canonical field | Unit / range |
| --- | --- |
| friendly_strength_centi | 0.01 strength, 0..10000 |
| enemy_pressure_centi | 0.01 pressure, 0..10000 |
| base_ammo_rate_milli | 0.001 ammo/sec, 0..600000000 |
| current_desired_ammo_rate_milli | 0.001 ammo/sec, derived |
| ammo_demand_accumulator_micro | 0.000001 ammo, 0..999999 |
| created_at_micro / next_observation_time_micro | integer simulation microseconds |
| interval demand / consumed / shortage | integer ammunition |
| ammo_coverage_milliseconds | integer floor milliseconds or null |

Public creation data may use friendly_strength, enemy_pressure, base_ammo_demand_per_second and ammo_demand_accumulator. Validation immediately quantizes each to its canonical integer. Canonical creation/snapshot fields are also accepted; providing both representations of one field is rejected. Nonfinite/negative/out-of-range inputs and invalid postures are rejected. Nearest canonical unit is used, exact halves away from zero (half-up for these nonnegative quantities). For example 33.333 pressure becomes 3333, and 8.0005 ammo/sec becomes 8001 milli-ammo/sec. Decimal input history is diagnostic; authoritative front projection contains canonical fields only.

Posture multipliers in thousandths: HOLD 1000, PRESS 1500, REDUCE_ACTIVITY 500, WITHDRAW 250. Effective rate is (base_milli * pressure_centi * posture_milli + 5000000) / 10000000 using integer division. The base-rate upper bound keeps the combined numerator below 2^53, also below signed-64-bit overflow.

Front-enabled worlds require millisecond-aligned tick durations that divide one second (1..1000 ms). The existing 100 ms tick qualifies. This avoids truncation and guarantees exact one-second observation boundaries. Worlds without fronts retain 2A microsecond tick support; runtime creation enforces the same front constraint.

Each tick adds effective_rate_milli * tick_duration_ms to micro-ammo, resolves floor(total / 1000000), and retains total % 1000000. Attempted demand is removed even when unavailable: shortages never become ammunition debt. Zero effective demand burns nothing. Pressure/posture changes affect future ticks only.

Coverage uses available physical stock, excluding reservations and incoming cargo. Integer quotient/remainder arithmetic avoids an overflowing initial multiplication. Zero rate returns null. Coverage status is FINITE, ZERO_DEMAND or OUT_OF_RANGE. For finite coverage beyond 9007199254740991ms, return null with OUT_OF_RANGE; this is distinct from ZERO_DEMAND. Check quotient before multiplication and remainder before addition. Do not change accepted stock ranges or emit a world event for this derived condition.

## Tick order, events and local knowledge

1. Prepare deterministic front accumulator patches and commit them with TICK_ADVANCED.
2. Process logistics and messages in the existing order.
3. Resolve active fronts in sorted ID order. ResourceService consumes min(integer demand, available ammunition); RESOURCE_CONSUMED has actor front ID and reason FRONT_COMBAT_CONSUMPTION.
4. Record positive FRONT_AMMO_SHORTAGE (no stock/ledger changes), then FRONT_AMMO_DEMAND_RESOLVED with integer interval totals.
5. At the one-second boundary finalize last_interval_* from current counters, reset current counters and emit FRONT_OBSERVED.
6. Ingest post-consumption facts to the responsible command only, observed_at = simulation time, confidence 1, source_system FRONT_OBSERVATION, causation = observation event.

Semantic creation/setter events: FRONT_CREATED, FRONT_ENABLED_CHANGED, FRONT_ENEMY_PRESSURE_CHANGED, FRONT_FRIENDLY_STRENGTH_CHANGED, FRONT_POSTURE_CHANGED. Full front patches permit event-only reconstruction. No FRONT_AMMO_ACCUMULATOR_CHANGED event is emitted each fractional tick. FRONT_AMMO_DEMAND_RESOLVED occurs only on integer demand, and FRONT_OBSERVED once per sampled interval.

Nine fact keys and authoritative units:

| Fact key | Value |
| --- | --- |
| FRONT_FRIENDLY_STRENGTH | integer centi-strength |
| FRONT_ENEMY_PRESSURE | integer centi-pressure |
| FRONT_POSTURE | posture string |
| FRONT_AMMO_ON_HAND | integer physical ammunition |
| FRONT_AMMO_AVAILABLE | integer unreserved ammunition |
| FRONT_AMMO_DEMAND_RATE | integer milli-ammunition/sec |
| FRONT_AMMO_COVERAGE_MILLISECONDS | integer ms or null (approved replacement for SECONDS) |
| FRONT_AMMO_COVERAGE_STATUS | FINITE, ZERO_DEMAND or OUT_OF_RANGE |
| FRONT_LAST_SHORTAGE | integer shortage in last completed one-second interval |

No superior/peer information or message is created automatically. CommandView has no front/world truth query. Developer metrics require trusted Simulation access; divide canonical units only for presentation.

## Required fixture and verification

Start FRONT_A at HOLD, strength 60, pressure 50, base rate 8, stock 10. The first three seconds produce demand/consumed/shortage 4/4/0, 4/4/0, 4/2/2; stock 6,2,0. Change pressure to 100 (rate8), create12 ammunition through ResourceService, change posture to REDUCE_ACTIVITY (rate4), then run another second. End tick40: created22, consumed14, stock8, destroyed0, no cargo. Four samples give36 local facts; Army/peer have none; no messages.

Run in PowerShell7 with Godot4.7.2:
./tools/run.ps1 -Mode test -GodotPath <engine>
./tools/run.ps1 -Mode fronts -GodotPath <engine>
./tools/run.ps1 -Mode front-demo -GodotPath <engine>
./tools/run.ps1 -Mode replay -Package res://artifacts/run_step103 -GodotPath <engine>
./tools/run.ps1 -Mode inspector-headless -GodotPath <engine>

The demo exports artifacts/run_step103. Replay checks canonical state, all ordered events and final tick. Tests additionally reconstruct every event prefix, verify conservation, protect reservations, test shared-stock fronts, fractional boundaries, awkward/half rounding, mid-interval changes and private observations. No graphics performance or target export claim is made.

## Scope boundary

No commander policy, AI decisions, supply request automation, planning, escalation, tactical combat, UI redesign or 104 implementation. Existing idle startup, 30FPS cap and low-processor mitigations remain. Review at 103 acceptance is required before further work.


## Authoritative JSON integer import repair

Boundary testing observed Godot4.7.2's native JSON parser change the integer token9007199254740991 to9007199254740992. Native parser limitations are documented at https://docs.godotengine.org/en/4.7/classes/class_json.html (checked2026-10-19): numbers use String.to_float. The specific boundary rounding was measured in this build.

The designer explicitly approved a narrow import repair. AuthoritativeJSON tokenizes objects, arrays, literals, strings and number syntax. Plain integer tokens are range-checked lexically against +/-9007199254740991 then converted directly to int, never through float. Out-of-range tokens produce INTEGER_OUT_OF_EXACT_JSON_RANGE. Fractional/exponent tokens retain Godot's existing numeric conversion. Strings retain string type, including quoted numeric text and escaped quotes/backslashes/Unicode. Malformed syntax and nesting deeper than128 levels fail with INVALID_JSON and offset.

RunExporter's JSON/JSONL import uses this loader for manifest, initial/final worlds, inputs and events. Export formats, resource representation, normalize(), equivalent(), strict ordered comparison and the accepted tag are unchanged. General fixture/debug JSON parsing remains native. Exact integer tests include positive/negative boundaries, adjacent integers, unsupported values, mixed nested JSON/JSONL, fractional/exponent type preservation, escaped strings, malformed input, maximum finite coverage and the previously failing max-stock replay.
