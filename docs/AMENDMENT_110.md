Approved on both clarifications.

### Input-contract clarification

Use the dedicated `SubmitPlayerPrompt` branch **before** the legacy `Simulation.execute` path touches the accepted core input sequence or emits `INPUT_RECEIVED`.

That branch should use its own deterministic namespace/counter, e.g.:

```text
player-prompt-input:0000000001
```

For prompt submissions:

- record the structured prompt attempt in `inputs.jsonl` in actual accepted-call order;
- record tick, arguments, prompt-input ID, and structured result;
- do **not** increment the legacy/core input counter;
- do **not** emit core `INPUT_RECEIVED`;
- do **not** modify authoritative WorldState/input context;
- valid prompt → independently emit `PLAYER_PROMPT_SUBMITTED` + `PLAYER_PROMPT_RECEIVED`;
- invalid prompt → inputs-history record only, with structured failure; no prompt ID, prompt event, or world mutation.

Fresh-process replay must replay the **mixed input history in original order**, routing prompt-input records through this dedicated branch and legacy gameplay inputs through the existing accepted path, then compare all relevant streams/projections exactly.

This preserves the §26 requirement that adding inert prompts cannot renumber later accepted gameplay inputs or world IDs.

### Frontless-area scope

Your proposed interpretation is approved.

For every configured location in a frontless `StrategicArea`, establish scope only from **existing command/location associations**, such as the accepted direct-control relationships and owned/directly-controlled stockpile locations.

Every location must resolve to at least one command within:

```text
recipient
or
recipient's descendants
```

If a location has no such existing association:

```text
AREA_OUTSIDE_COMMAND_SCOPE
```

Do not create a new location-ownership system for 110.

If a location is shared/associated with multiple commands, it is sufficient that there is a legitimate existing in-scope controlling/owning association; do not reject merely because another command also has infrastructure there unless an existing authority invariant already forbids that configuration.

---

# 46. Stop condition — remainder

When the full 110 gate passes:

**STOP.**

Do not begin 111.

Do not make commanders react to prompts.

Do not generate assessments.

Do not create reconnaissance missions.

Do not build the player-facing battlefield UI.

Return the complete 110 evidence for review.

If accepted, **111** will add the first autonomous Operational Command evaluation of these prompts—specifically determining whether command already has sufficient information, whether the prompt raises an actionable concern, or whether additional information would be required—without yet building the full reconnaissance/equipment ecosystem.
