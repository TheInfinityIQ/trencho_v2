Do **not** tune the fixture to force C to close. I am amending the 107 acceptance contract to accept the naturally occurring behavior you observed.

The reason is important: A's resolution is not a loophole. It demonstrates one of the core reasons we deliberately designed `ResourceNeed` as a **dynamic projection rather than a fixed order**. Its operating requirement changed, its recalculated 20-second target fell to 64, its observed physical stock was 66, and the need legitimately became unnecessary without somebody artificially satisfying the original quantity. Forcing extra ammunition into the fixture solely so a prewritten narrative occurs would work against what this prototype is supposed to teach us.

The existing implementation has already independently proven physical-arrival-driven need closure in 105. 107's primary purpose is to prove that the accepted systems operate together unattended, not to re-prove every isolated lifecycle transition in exactly the same form.

## 107 acceptance amendment

Replace the strict interpretation of §20 / milestone 13 with **two separate integrated requirements**.

### A. Autonomous need resolution

At least one `ResourceNeed` must reach `RESOLVED` during the unattended 107 run through any lifecycle transition that is valid under the accepted 105 contract.

Therefore this observed sequence qualifies:

```text
LOCAL_A need active
↓
posture / demand evolves autonomously
↓
planning rate becomes 3.2 ammo/sec
↓
20-second target recalculates to 64
↓
complete observation reports 66 physical ammo
↓
shortage condition permits closure
↓
need RESOLVED
```

This is actually useful evidence that needs are not stale fixed requests.

Preserve and document that causal chain.

### B. Physical resupply must materially affect an active need

Separately, at least one active need must receive **real physical logistics aid** during the same unattended run and subsequently react to it through the normal observation system.

Full `RESOLVED` closure is **not required** for this second requirement.

For C, verify the chain contains:

```text
active C need
↓
C local 8-ammo self-help shipment
↓
physical arrival / local observation
↓
peer B 30-ammo shipment
↓
physical arrival / local observation
↓
superior allocation shipment(s)
↓
physical arrival / local observation
↓
C need projection changes and/or supply classification changes
and/or autonomous posture changes as a consequence
```

The important requirement is that the delivered ammunition becomes **observed physical stock and materially changes the command's subsequent state**. It cannot merely pass through logistics while the command behaves identically.

Record the before/after evidence using existing IDs and belief records. Suitable proof includes one or more of:

```text
available ammo increases
coverage changes
uncovered need decreases
need revision changes
SEEKING_SUPPLY ↔ COVERED_IN_TRANSIT changes
supply classification changes
posture changes
```

Do not require C to close if the accepted policy correctly determines that its evolving demand still exceeds available supply.

---

## Revised milestone 13

Change:

> At least one ResourceNeed reaches `RESOLVED` through physical resupply.

to:

> **At least one ResourceNeed reaches `RESOLVED` autonomously under the accepted dynamic lifecycle, and at least one active ResourceNeed independently receives physical resupply that materially affects subsequent observed need/command state.**

Your observed A + C behavior can satisfy those as two different needs.

---

## Preserve the fixture exactly

Keep the supplied 107 values unchanged:

```text
HQ initial = 50
strategic inbound = 60 at t=15
A front = 120
B front = 80
C front = 20
B reserve = 30
C reserve = 8
25-second run
```

Do not:

- increase the strategic shipment;
- inject another shipment;
- extend the run to make a desired outcome happen;
- modify planning thresholds;
- change posture scoring;
- alter need targets;
- add a special resolution rule.

The observed result is more valuable than a fixture tuned until it acts out our original expectation.

## Your current probe is therefore not a failure

Subject to the remaining 107 audits, what you reported is consistent with the intended prototype:

- zero runtime gameplay inputs;
- expected first decisions;
- local self-help;
- peer assistance;
- escalation;
- superior allocation;
- multi-need scarcity;
- scheduled strategic resupply;
- evolving local needs;
- autonomous posture adaptation;
- one legitimate autonomous need resolution;
- real physical aid affecting other active needs.

That is precisely the sort of emergent interaction 107 was intended to expose.

Continue only the remaining **107 replay, conservation, privacy, causal-audit, event-volume, and acceptance verification work** against this unchanged probe.

Document this as an explicit acceptance amendment in the 107 requirements/evidence so we do not later pretend the original physical-closure wording was met literally.

Once the amended 107 gate is fully green, **STOP and report the complete 107 evidence. Do not begin 2C.**
