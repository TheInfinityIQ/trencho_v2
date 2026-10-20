# Approved114 prompt stream integrity refinement

The designer approved independent base/follow-up event identities and lineage so presentation cannot renumber later111 evaluation events or alter typed112/113 provenance. Base SUBMITTED/RECEIVED/EVALUATED events retain player-prompt-event:N and previous_prompt_event_id pointing only to base events. Follow-up events use player-prompt-follow-up-event:N, previous_follow_up_event_id, independent prompt-follow-up:N records and explicit typed source prompt/evaluation/requirement/collection references.

+Confirmed. That equivalent is approved and is cleaner than modifying accepted base-event payloads.

Use the **JSONL physical record position itself as the total stream ordering authority**. Do not add `stream_sequence` to existing 110/111 base records.

For Schema 2C.6, lock the contract as:

```text
Physical combined prompt stream
    JSONL record index = total stream sequence
```

Choose and document one indexing convention, preferably:

```text
first JSONL record = stream position 1
```

Then:

```text
SUBMITTED / RECEIVED / EVALUATED
→ existing accepted record shape unchanged
→ player-prompt-event:N namespace
→ existing base lineage unchanged
```

and:

```text
PLAYER_PROMPT_FOLLOW_UP_ISSUED
→ player-prompt-follow-up-event:N
→ prompt-follow-up:N
→ previous_follow_up_event_id
→ stream_sequence = its actual physical JSONL record position
```

The follow-up record's `stream_sequence` therefore acts as an explicit assertion about where that new event was interleaved, while the base records remain byte-identical.

Validation must prove all of the following:

- JSONL physical order is deterministic and authoritative for the combined stream.
- Every follow-up's `stream_sequence` exactly equals its actual physical record index.
- Follow-up `stream_sequence` values are strictly increasing.
- `player-prompt-event:N` remains independently contiguous according to the accepted 110/111 contract.
- `player-prompt-follow-up-event:N` is independently contiguous.
- `previous_prompt_event_id` remains entirely within the base namespace.
- `previous_follow_up_event_id` remains entirely within the follow-up namespace.
- Typed source references from the follow-up resolve exactly to the qualifying prompt/evaluation/requirement/collection chain.
- Replay regenerates the identical full JSONL sequence and hash.

For the 114 on/off inertness comparison, use exactly the property you described:

```text
enabled combined prompt stream
- remove only PLAYER_PROMPT_FOLLOW_UP_ISSUED records
= disabled combined prompt stream
```

The remaining base records must be **byte-for-byte identical**, including IDs, payloads, base lineage, evaluation IDs, and all later 112/113 typed references. No ID remapping, field normalization, or sequence rewriting is permitted.

The enabled file itself will of course have different physical positions for later base records because follow-ups are interleaved. That is acceptable: physical file position is not embedded into those base records and does not constitute a mutation of their accepted identities or payloads.

One additional integrity case is worthwhile: alter a follow-up's stored `stream_sequence`, rehash the package, and require replay/import validation to reject it because it no longer matches its actual JSONL position.

No sidecar envelope is required. Your proposed representation satisfies the ordering proof while preserving literal base-record equality.

Continue **114 only**.
