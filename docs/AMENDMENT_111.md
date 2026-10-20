Yes. **Approved.** That satisfies both the 111 opt-in requirement and the exact authoritative-inertness requirement, and it is preferable to contaminating canonical command records with a 2C-only evaluation flag.

Treat this as an explicit **111 representation amendment**.

### Approved configuration boundary

`strategic_prompt_evaluation_enabled` may appear in the incoming definition/configuration source, but it must be consumed before canonical world-definition projection.

Conceptually:

```text
raw definition
    ↓
extract 111 prompt-evaluation config
    ↓
validate separately
    ↓
strip 111-only field
    ↓
canonical WorldDefinition
    ↓
WorldState / COMMAND_CREATED / events.jsonl
```

The canonical command representation therefore remains identical to the corresponding evaluation-disabled world.

Use a separate persisted configuration equivalent to:

```text
prompt_evaluation_config

operational_command_id
enabled
```

Only Operational Commands may be configured.

Default remains:

```text
false
```

No configuration entry is required for commands using the default.

### Validation

Reject invalid evaluation configuration before simulation start for conditions equivalent to:

```text
UNKNOWN_COMMAND
COMMAND_NOT_OPERATIONAL
DUPLICATE_COMMAND_CONFIG
INVALID_ENABLED_VALUE
```

Do not silently ignore malformed entries.

The configuration must not:

- allocate authoritative entity IDs;
- emit `COMMAND_CREATED`;
- mutate WorldState;
- create an InformationRecord;
- alter the accepted command snapshot schema.

### Export / replay

Persist it in an explicitly prompt-specific artifact, naming flexible, for example:

```text
player_prompt_evaluation_config.json
```

Include its schema/hash in the manifest.

Fresh-process replay should:

```text
load canonical world
+
load StrategicArea config
+
load prompt evaluation config
+
replay mixed input history
+
reconstruct prompt/evaluation stream
```

The evaluator configuration is therefore deterministic and auditable without becoming part of authoritative military state.

### Paired inertness test

For the §20/§29 comparison, use the same:

```text
canonical initial world
seed
run identity
StrategicAreas
inputs
authoritative gameplay state
```

The only intended configuration difference is:

```text
prompt evaluation enabled vs disabled
```

in the separate 111 configuration.

Require byte-identical:

```text
initial_world.json
events.jsonl
final authoritative world
core authoritative IDs
accepted 2B projections
resource ledger
```

assuming `initial_world.json` is the canonical post-strip world artifact, as it should be.

Prompt-specific artifacts may differ:

```text
prompt evaluation config
player_prompt_events.jsonl
final player prompt projection
manifest hashes for those files
```

If your package also persists a raw pre-canonical definition for developer diagnostics, do not include that raw file in the byte-identical authoritative comparison; clearly classify it as configuration evidence rather than authoritative world state.

### Evaluator input boundary

Your proposed evaluator boundary is also approved.

It may receive detached copies of:

```text
recipient command identity
recipient-scoped superior_need_reports
StrategicArea configuration
current simulation time
pending prompt records
```

It must not hold or receive:

```text
Simulation
WorldState
PlayerObserverView
raw AbstractFront
global shipment registry
subordinate InformationService
```

A detached recipient `CommandView` subset is ideal.

The evaluator should be able to answer its entire 111 policy from that detached input.

### Whole-second ordering

Use the ordering you proposed:

```text
1. advance/process world events due at boundary
2. deliver accepted command messages due at boundary
3. update superior_need_reports / resolved report projection
4. evaluate pending player prompts
5. emit PLAYER_PROMPT_EVALUATED in prompt stream only
6. continue accepted superior arbitration
```

That satisfies Scenario E.

One important nuance: **111 evaluation must not delay, suppress, or reorder the accepted arbitration behavior.** It is logically inserted before arbitration only so it reads the same newly delivered reports; because evaluation is inert, arbitration must see exactly the state it would have seen without 111.

### Prompt compatibility

With evaluation disabled:

```text
prompt → PENDING_EVALUATION
```

indefinitely, exactly as accepted 110.

With evaluation enabled:

```text
prompt → PENDING_EVALUATION
→ next exact 1-second boundary
→ EVALUATED
```

Each prompt evaluates once.

### Event isolation

`PLAYER_PROMPT_EVALUATED` remains in:

```text
player_prompt_events.jsonl
```

not `events.jsonl`.

Its provenance may cite:

```text
SuperiorNeedReport IDs
source message IDs
need IDs/revisions
```

but those are references only. No cross-stream authoritative mutation is implied.

### One additional regression to lock

Add an explicit test that merely toggling the separate evaluation config:

```text
false → true
```

with **zero submitted prompts**

produces:

```text
0 evaluation events
0 prompt projection differences
byte-identical authoritative artifacts
```

That will prove the configuration itself is inert.

Proceed with this amendment. Preserve it in the 111 requirements/evidence, and continue only 111.
