# ⚔️ Echoes of the Sankofa — MVP Combat Rounds Addendum

**Canon Source:** Legacy Never Dies §§3, 4, 9, 12  
**Directive:** Deterministic Fairness — same seed ⇒ same fight.

---

## 1. Overview
The MVP combat loop implements a **step-based autobattle** where both player and AI actions resolve in deterministic rounds. The player selects a valid party from available heroes; enemies are seeded dummy packs for now. Every round, order and outcomes remain fully reproducible from the campaign seed.

**Philosophy:**  
Guidance > Control — the Keeper curates who to send; Anansi’s game unfolds predictably and legibly.

---

## 2. Round Phases

| Phase | Description | Source File |
|:------|:-------------|:-------------|
| **INITIATIVE** | Compute deterministic order for this round. | `core/combat/Initiative.gd` |
| **SELECT** | Each actor (ally/enemy) chooses a major + minor action. | `core/combat/EchoActionChooser.gd` |
| **RESOLVE** | Apply major, then minor actions (ATTACK, GUARD, etc.). | `core/combat/ActionResolver.gd` |
| **TICK** | Apply fear increment + morale decay cadence. | `core/combat/CombatEngine.gd` |
| **CHECK** | Evaluate victory/defeat/round-limit conditions. | `core/combat/CombatEngine.gd` |

Each round produces a **snapshot** with:
- `round` index
- `order` list
- `actions[]`
- `ticks` {fear, morale_decay}
- `state_after` (HP, KO, guard)
- `end` (if applicable)

---

## 3. Initiative Formula (MVP)

```
score = base + a*Courage + b*Wisdom + tiebreak(seed, hero_id, round_index)
```
- `a` and `b` constants tuned in `CombatConstants.gd`.
- Tiebreak uses seed XOR hero_id and round_index for stable ordering.
- Result is **fully reproducible** given the same inputs.

---

## 4. Action Types (Economy)

Each combatant gets:
- **1 Major Action:** ATTACK / REFUSE / INTERACT (stub)
- **1 Minor Action:** GUARD / MOVE / INTERACT (stub)

### Major Actions
| Type | Behavior |
|------|-----------|
| **ATTACK** | Deals base damage; affected by morale tier. |
| **REFUSE** | Skips turn if Broken morale or fear ≥ threshold. |

### Minor Actions
| Type | Behavior |
|------|-----------|
| **GUARD** | Adds guard_shield to target; reduces next dmg. |
| **MOVE** | Stubbed for MVP; advances toward nearest target. |

**KO Handling:** hp ≤ 0 ⇒ mark `ko=true`. No permanent death (see §10 canon: “Loss as continuity”).

---

## 5. Morale & Fear Knobs (MVP Values)

| Variable | Description | Typical MVP Value | Source |
|-----------|--------------|--------------------|--------|
| `FEAR_PER_ROUND` | Base fear gain each round. | +1 | `CombatConstants.gd` |
| `MORALE_DECAY_N_ROUNDS` | Interval of morale drop. | every 2 rounds | `CombatConstants.gd` |
| Morale Tiers | Inspired (+20%), Steady (±0%), Shaken (−20%), Broken (REFUSE). | — | `CombatConstants.gd` |

**Intended Feel:** gentle drift toward pressure without stalling combat.

---

## 6. Determinism Guarantees

✅ Identical seed ⇒ identical battle order, choices, and outcomes.  
✅ PRNG isolated to battle seed (no external randomness).  
✅ All logs and snapshots can replay a fight exactly (`/fight_again`).  
✅ No hidden state changes between runs.

---

## 7. Debug Console Commands (QA / Player Demo)

| Command | Purpose | Example |
|----------|----------|----------|
| `/party_list` | Lists available heroes with traits & archetypes. | Shows only non-resting heroes. |
| `/party_set <ids>` | Stages a valid party (max 3 heroes). | `/party_set 1 3 5` |
| `/party_show` | Displays staged party with full info. | `/party_show` |
| `/party_clear` | Clears current staged party. | — |
| `/fight_demo [seed] [rounds] [--auto]` | Runs deterministic fight with dummy enemies. | `/fight_demo 0xABCD 5` |
| `/fight_again` | Replays the exact last fight for verification. | `/fight_again` |

All commands live in `core/ui/debug/debug_console.gd`.

---

## 8. Future Extensions

| Feature | Description |
|----------|--------------|
| **Realm Packs** | `EnemyFactory.spawn_realm_pack()` swaps dummy dummies for themed enemies without API changes. |
| **Reactions / Conditions** | On-hit events, morale bursts, and conditional skills. |
| **Persistence Hooks** | Return-to-Sanctum state updates post-battle. |
| **UI Layer** | Animated timeline for round snapshots. |

---

## 9. Canon References

- **§3 Loop pacing** → defines readable cadence & visible rounds.
- **§4 Core Mechanics** → establishes Major/Minor action economy.
- **§5 Heroes / Personality** → refusal and morale pressure loops.
- **§9 Combat AI & Simulation** → mandates deterministic seed behavior.
- **§12 Balance Curves** → morale & fear as pacing variables.

---

**Definition of Done**  
This document matches code constants and behaviors for MVP.  
Any future combat rebalances must update this addendum to stay canon-aligned.

---