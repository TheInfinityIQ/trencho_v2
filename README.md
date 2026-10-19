# Trencho — Generation 2 simulation prototype (Step 104)

A separate Godot 4.7.2 stable project implementing the simulation kernel requirements v0.1 and the designer's three clarifications. No code or architecture was copied from the tactical prototype.

Open `project.godot` with **Godot 4.7.2 stable**, then run the main scene. The developer inspector starts idle; click **Run demonstration** to execute the fixture. Its export button writes a run package and verifies replay from the files on disk.

After a reported system freeze on editor Play, presentation is capped at 30 FPS with idle redraw throttling. The cause is unconfirmed; see [startup diagnostics](docs/STARTUP_DIAGNOSTICS.md). For a standalone window without editor embedding, run `./tools/open_inspector.ps1` in PowerShell 7. That launcher was not graphically retested during the freeze investigation.

## Run the checks

From this directory, in PowerShell 7:

```powershell
./tools/run.ps1 -Mode test -GodotPath 'C:/path/to/Godot-4.7.2.exe'
./tools/run.ps1 -Mode demo -GodotPath 'C:/path/to/Godot-4.7.2.exe'
./tools/run.ps1 -Mode replay -GodotPath 'C:/path/to/Godot-4.7.2.exe'
```

`GODOT_BIN` can supply the engine path. The wrapper also detects the local validation copy, a `godot` executable on PATH, or the installed Steam engine. No Python, .NET, addons, or third-party test framework is required. The wrapper bounds execution time, collects output, and fails on engine/script errors as well as a nonzero exit code.

Equivalent direct commands:

```text
godot --headless --path . --script res://tests/acceptance.gd
godot --headless --path . --script res://tools/cli.gd -- demo res://artifacts/run_demo
godot --headless --path . --script res://tools/cli.gd -- replay res://artifacts/run_demo
```

The engine must be able to write its ordinary user-data directory when using direct commands. The PowerShell wrapper redirects process-local application data and logs into `artifacts/` for this restricted workspace. The installed Steam binary was copied to workspace tooling for validation because its portable editor settings reside beside the executable. No installed engine settings were changed.

## Directory map

| Path | Responsibility |
| --- | --- |
| `kernel/simulation.gd` | Input boundary, logical ticks, event application order, developer queries |
| `kernel/world_state.gd` | Authoritative projection, copied queries, incremental indexes |
| `kernel/event_store.gd` | Append-only event records, copied history |
| `kernel/world_definition.gd` | Validated static definitions and initial snapshots |
| `kernel/resource_service.gd` | Physical stock, reservations, consumption, destruction, ledger audit |
| `kernel/logistics_service.gd` | Atomic shipment lifecycle and fixed-step travel |
| `kernel/router.gd` | Deterministic directed routing for both graphs |
| `kernel/hierarchy_service.gd` | Cycle-safe reparenting |
| `kernel/authority_service.gd` | Direct resource authority, separate from ancestry |
| `kernel/communication_service.gd` | Validated messages, latency, delivery/failure |
| `kernel/information_service.gd` | Provenance and current-belief selection |
| `kernel/command_view.gd` | Detached private command snapshot without a world reference |
| `kernel/run_exporter.gd` | JSON/JSONL export, normalization, replay and comparison |
| `kernel/front_definition.gd`, `kernel/front_service.gd` | Fixed-point abstract fronts and private local sampling |
| kernel/authoritative_json.gd | Exact integer import for authoritative run artifacts |
| kernel/clock.gd, kernel/result.gd | Time conversion and common result/value checks |
| `data/demo_world.json` | Configurable world, hierarchy, authority and both graphs |
| `debug/` | Privileged demonstration and developer inspector |
| `tests/` | Headless acceptance checks and rendered inspector smoke test |
| `tools/` | CLI and bounded Windows runner |
| `docs/` | Architecture, schemas, clarifications, requirement mapping |
| `artifacts/` | Generated run packages, test reports, logs and inspector capture; ignored by Git |

## What the demonstration establishes

It creates 1,000 ammunition at the source; moves 600 to HQ; sends 300 to A and 200 to B; interrupts B's active route; explicitly reroutes B via A; delivers one report; then interrupts another report after send. The recipient learns only from the successfully delivered report.

At tick 17 (1.7 logical seconds), stock is source **400**, HQ **100**, A **300**, B **200**. There is no cargo remaining and no consumption or destruction in this fixture. A separate acceptance group covers those destruction/consumption paths.

The diagnostic run contains 93 ordered events. Tests compare independent same-seed runs, a different seed without stochastic policy, replay from exported files, and reconstruction by applying events alone.

## 2A accepted closeout

Project version `0.1.1` retains schema `2A.1`. The two mandatory closeout fixes propagate correlation through information ingestion and add structured message-failure diagnostics. Run `./tools/run.ps1 -Mode closeout` for targeted regressions, `-Mode test` for the full suite, and `-Mode inspector-headless` to verify the preserved idle-startup mitigations without a graphics window. See `docs/CLOSEOUT.md` for acceptance scope, results and the freeze/tag procedure. The earlier 0.1.0 archive remains a historical artifact.

See [architecture](docs/ARCHITECTURE.md), [schemas](docs/SCHEMAS.md), [designer clarifications](docs/DESIGN_CLARIFICATIONS.md), and [acceptance mapping](docs/ACCEPTANCE.md).

## Step 103: abstract fronts

Project 0.2.0 / schema 2B.1 extends the preserved accepted 2A baseline with fixed-point ammunition demand and private one-second local observations. It adds no commander AI. The inspector still runs the accepted kernel demonstration; run the new front fixture with ./tools/run.ps1 -Mode front-demo, and replay it with -Mode replay -Package res://artifacts/run_step103. See [front contract, units and validation](docs/FRONTS_103.md). The full test mode includes original 2A and new front regressions.

## Step 104: autonomous local decisions

Project0.2.1/schema2B.2 adds an opt-in LOCAL commander loop: complete local observations, belief-only integer candidate comparison, validated posture action and a reconstructable decision/outcome journal. Run ./tools/run.ps1 -Mode decisions for the targeted suite, or -Mode decision-demo and then -Mode replay -Package res://artifacts/run_step104 for the causal PRESS fixture. See [decision contract and journal](docs/DECISIONS_104.md). Earlier103 and2A fixtures remain available with autonomy off.
