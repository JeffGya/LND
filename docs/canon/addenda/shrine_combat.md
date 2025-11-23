
# Purify Shrine — Combat Addendum (Post‑Refactor, MVP-Complete)

This document explains how **Purify Shrine** stages function inside the **Combat Simulation Core** after the full generic‑entity refactor. It is a self‑contained specification that a new developer can use to understand, extend, or debug shrine behavior.

This version replaces all earlier shrine documentation.

---

# 1. Concept Overview

A **Purify Shrine** stage is a multi‑wave defensive mission.  
The party must survive multiple enemy waves **while keeping the shrine alive**.  
Heroes may perform a special **Purify** action that stabilizes shrine HP drain.

The shrine is now a **generic combat entity** using the unified entity model:

```
tags = ["ally", "structure", "objective", "objective:shrine"]
```

There is no shrine-specific code inside CombatEngine. Shrine functionality is driven by:

- **CombatEntities** (entity shape, tags)
- **CombatObjectives** (objective logic)
- **EnemyActionChooser** (AI: shrine-target priority)
- **CombatEmotionSystem** (shrine HP drain)
- **GameBalance_HeroCombat** & **GameBalance_Realm** configs

---

# 2. Shrine as a Generic Combat Entity

The shrine is created by ObjectiveRunner when a Purify Shrine stage begins.

## 2.1 Entity Structure

```
{
    id = -1,
    name = "Shrine",
    stats = {
        hp = X,
        max_hp = X,
        atk = 0,
        def = 0,
        agi = 0,
        morale = 0,
        fear = 0,
    },
    tags = ["ally", "structure", "objective", "objective:shrine"],
    meta = {
        purge_cooldowns = {},
        purge_stacks = []
    }
}
```

Notes:
- `id = -1` is reserved for shrine.
- The shrine **never takes actions** (`can_act = false`).
- Shrine **cannot refuse**, cannot be feared, and does not participate in morale.

---

# 3. Shrine HP Sources

Shrine HP decreases from:

1. **Direct enemy attacks** (standard combat damage rules)
2. **Per-round drain** (CombatEmotionSystem)
3. **Purify stack expiry drain** (after a Purify buff ends)

Shrine HP never increases (MVP).  
Purify slows drain; it does not heal.

---

# 4. Shrine HP Drain System (CombatEmotionSystem)

The shrine drain occurs **after all combat actions in a round**.

## 4.1 Base Per-Round Drain

Defined in `GameBalance_HeroCombat.gd`:

- `SHRINE_BASE_DRAIN_PER_ROUND`

Applied every round in a Purify Shrine stage.

## 4.2 Purify Stack Reduction

When Purify succeeds:

- A temporary reduction stack is added:
  - `duration = SHRINE_PURIFY_STACK_ROUNDS`
  - `reduction = SHRINE_PURIFY_STACK_REDUCTION`

This reduction applies **each round** while active.

## 4.3 Stack Expiry Drain

When a Purify reduction expires, shrine takes:

- `SHRINE_PURIFY_EXPIRY_PENALTY`

This simulates spiritual backlash after the blessing weakens.

## 4.4 Drain Formula

```
drain = BASE_DRAIN
        - sum(active_purify_reductions)
        + sum(expiring_purify_penalties)
```

Min drain = 0.

Damage applied: `hp -= drain`.

Logged each round:

```
[shrine] Drain 10 → reduced to 7 (purify stacks=1)
[shrine] Purify stack expired → expiry penalty 3
```

---

# 5. The Purify Action (Hero Ability)

Purify is a **special action type**: `PURIFY_SHRINE`.

Available only when:
- Stage = Purify Shrine
- Shrine is alive
- Shrine HP < 50%
- Hero is the **designated purifier**
- Hero’s Purify cooldown = 0

Purify never targets enemies.  
Purify does not heal.  
Purify only influences shrine drain (as described above).

Purify is resolved by **ActionResolver** and logged as:

```
Amina Osei PURIFY_SHRINE → Shrine (cd=3)
```

---

# 6. Purifier Selection System

Purifier is chosen **once per wave** by ObjectiveRunner:

### Weight formula (MVP):

```
weight = hero.faith * SHRINE_PURIFY_WEIGHT_FAITH
if hero.archetype == "devout":
    weight += SHRINE_PURIFY_WEIGHT_ARCH_DEVOUT
```

Highest weight = designated purifier.

Stored in objective context:

```
ctx.purifier_hero_id
```

---

# 7. Enemy Shrine-Target Priority (AI)

EnemyActionChooser chooses targets based on tags.

Rule (MVP):

1. If an entity has tag `"objective:shrine"` → **priority target**
2. Otherwise → fallback to normal enemy rules

This logic is fully generic.  
Any future objective with `"objective:*"` tags can reuse this.

Example log:

```
Grove Seer #1 ATTACK → Shrine dmg=10 [90/100]
```

---

# 8. Round Structure (Purify Shrine Variant)

Purify Shrine rounds follow the **same universal step sequence** as all combat:

1. Initiative order
2. Hero turns (may include Purify)
3. Enemy turns (usually shrine attacks)
4. Emotion tick
   - fear/morale for heroes
   - shrine drain calculation
5. KO fear propagation
6. Objective end-check
7. Snapshot logged

No shrine-specific logic exists in CombatEngine.

---

# 9. Multi-Wave Resolution

Purify Shrine stages consist of N waves (from realm config).

After each wave:

- The shrine’s **remaining HP** is reported back to ObjectiveRunner.
- Allies retain their HP.
- Purify stacks & cooldowns reset.
- ObjectiveRunner advances to next wave.

Success conditions:

- Shrine survives all waves  
- Party not wiped

Failure conditions:

- Shrine HP <= 0  
- Total ally KO

---

# 10. Objective Logic (CombatObjectives)

CombatObjectives handles victory/failure detection and shrine‑specific objective context.

For Purify Shrine:

```
OBJECTIVE_PROTECT_SHRINE
```

The objective context includes:

```
{
    shrine_id = -1,
    purifier_hero_id = X,
    waves_total,
    wave_index,
}
```

Objective end-condition (per wave):

- If shrine HP <= 0 → FAILURE
- If enemies_alive == 0 → WAVE CLEAR

Final summary returned to RealmService:

```
{
    success = true/false,
    waves_cleared = X,
    shrine_hp = Y
}
```

---

# 11. Logs & Snapshot Schema

CombatSnapshotBuilder ensures shrine fields appear consistently.

### During rounds:
```
Shrine 85/100
[shrine] Drain=10 (Purify stacks=1)
```

### In end summaries:
```
Allies: { … , Shrine hp:43/100 }
Enemies: { … }
Outcome: victory=true reason=enemies_defeated
```

### In final stage summary:
```
[shrine] Summary — success=true, waves_cleared=2, shrine_hp=43/100
```

---

# 12. Balance Configuration Summary

`GameBalance_Realm.gd`
- Shrine base HP
- Wave count
- Realm-tier modifiers

`GameBalance_HeroCombat.gd`
- `SHRINE_BASE_DRAIN_PER_ROUND`
- `SHRINE_ENEMY_DAMAGE_MULTIPLIER`
- `SHRINE_PURIFY_COOLDOWN_ROUNDS`
- `SHRINE_PURIFY_STACK_ROUNDS`
- `SHRINE_PURIFY_STACK_REDUCTION`
- `SHRINE_PURIFY_EXPIRY_PENALTY`
- `SHRINE_PURIFY_WEIGHT_FAITH`
- `SHRINE_PURIFY_WEIGHT_ARCH_DEVOUT`

---

# 13. Future Extensions (Beyond MVP)

### Possible improvements:
- Player‑selectable purifier
- Shrine healing abilities
- Multiple objective structures in one stage
- Shrine buffs from specific hero classes
- Enemy shrine‑corruptor variants
- Realm traits modifying shrine rules

These upgrades require **no engine rewrites**, only new objective logic or additional tags.

---

# 14. Developer Checklist

When adding a new shrine-like objective:

- Create a tagged structure  
- Add objective-specific context in CombatObjectives  
- Let EmotionSystem handle periodic effects  
- Let EnemyActionChooser handle targeting  
- Add snapshot builders if needed  
- Put knobs in GameBalance_HeroCombat or Realm configs  

No engine internals need modification.

---

End of file.