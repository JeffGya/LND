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

## 5.1 Morale System Implementation (MVP Final)

**Canon Link:** §9 Combat, AI & Simulation → “Morale & Fear System”  
**Implements:** “As the Keeper I want morale to affect output”

During combat, each ally operates with a morale value (0–100) that affects their attack output.  
Enemies currently ignore morale in MVP.

| Tier | Range | Multiplier | Behavior |
|:--|:--:|:--:|:--|
| INSPIRED | 80–100 | × 1.10 | Attacks deal +10 % damage |
| STEADY | 50–79 | × 1.00 | Baseline output |
| SHAKEN | 30–49 | × 0.90 | Attacks deal −10 % damage |
| BROKEN | 0–29 | — | Refuses major actions (enters REFUSE state) |

**Files touched**
- `core/combat/CombatConstants.gd` – Canonical thresholds & multipliers  
- `core/combat/CombatEngine.gd` – Morale accessor and snapshot fields  
- `core/combat/ActionResolver.gd` – Applies multiplier (+ BROKEN → REFUSE)  
- `core/combat/CombatLog.gd` – Displays morale tags (+10 % / −10 %)  
- `core/ui/debug/debug_console.gd` – QA commands `/morale_show`, `/morale_set`

**Testing Tools**
| Command | Purpose |
|:--|:--|
| `/morale_show` | Lists current ally morale and tier in combat |
| `/morale_set <id> <0..100>` | Manually adjusts ally morale for QA |
| `/fight_again` | Replays last battle to verify morale effects |

**Design Notes**
- Morale is combat‑state only in MVP. It resets to 50 each battle.  
- Post‑battle persistence (“carry‑over morale”) is planned for post‑MVP.  
- Deterministic: no RNG involved; same seed ⇒ same results.  
- Broken enforcement is authoritative in resolver, not chooser.

---

## 5.2 Fear-Driven Refusal (MVP Final)

**Canon Link:** LND §4 Core Mechanics, §9 Combat, AI & Simulation (“Echo Behavior Matrix”), §12 Balance Curves  
**Narrative Intent:** An echo that is too afraid does not always obey — the Keeper must see *why*.

**Goal (story):** “As the Keeper I want fear to push refusal.”

**What it does (runtime):**

1. Every combatant tracks a `fear` value (0–100).  
2. At the start of a turn, **before** normal action selection and **before** morale-based refusals, the engine asks `ActionResolver.should_refuse_turn(unit_dict)`.  
3. If fear is **below** the configured threshold, the unit acts normally.  
4. If fear is **at or above** the threshold, we roll a refusal chance that scales with how far above the threshold the unit is.  
5. On success, we do **not** go through the normal attack path. Instead we emit a fear outcome:
   - **"refuse"** → unit skips its major action  
   - **"guard"** → unit takes a defensive minor action on self (reuses existing GUARD resolver)  
   - **(post-MVP)** **"abandon"/"retreat"** → *not part of MVP combat loop; see below*  
6. All fear refusals are **logged** so the Keeper can see what happened.

**Balance source of truth:** `core/config/GameBalance_HeroCombat.gd`

```gdscript
const FEAR_REFUSAL_THRESHOLD: int = 70
const FEAR_MAX: int = 100
const FEAR_REFUSAL_BASE_CHANCE: float = 0.35
const FEAR_REFUSAL_PER_10_OVER: float = 0.05
const FEAR_REFUSAL_ACTIONS: Array[String] = [
    "refuse",
    "guard"
    # "retreat"  # POST-MVP: uses its own high-severity trigger
]

# Fear gain sources (MVP)
const FEAR_PER_HIT: int = 2
const FEAR_PER_ALLY_KO: int = 4
const FEAR_PER_FOCUS_HIT: int = 1
```

**Execution order (important):**

1. Initiative determined  
2. **Fear check** (new)  
3. If fear → refusal: emit fear action, log, continue to next actor  
4. Else: normal action selection (attack / guard / stub)  
5. Morale tick & decay  
6. Victory/defeat checks

This preserves the canon directive **“Guidance > Control”**: the Keeper chose the team, but Anansi’s web (fear/morale) still speaks.

**Files touched (MVP):**
- `core/config/GameBalance_HeroCombat.gd` — added fear → refusal block and fear gain constants.
- `core/combat/ActionResolver.gd` — new helper `static func should_refuse_turn(unit: Dictionary) -> Dictionary` that clamps fear, pulls the config, rolls, and picks a mode (`"refuse"`/`"guard"`).
- `core/combat/CombatEngine.gd` — in the actor loop, we now call the resolver **before** normal actions and apply the outcome through `_apply_fear_outcome(...)`; also wires fear gain for “got hit”, “got hit multiple times (focus)”, and “ally KO” in the same round.
- `core/combat/CombatLog.gd` — added `add_refusal(...)` and taught the formatter to show fear data:  
  `REFUSE Kwamena Amponsah  (fear_refusal, fear=80)`
- `core/ui/debug/debug_console.gd` — added `/fear_show` and `/fear_set <id> <0..100>` for QA; later extended to persist fear across demo fights.

**Why we kept it deterministic:** the chance is computed from fear and a small roll inside the resolver, but the overall battle is still deterministic for a given seed because combat PRNG is already isolated for the round. Same seed ⇒ same fear events.

**Fear gain (MVP):**
- on **every hit**: +`FEAR_PER_HIT`
- on **extra hits in the same round on the same target**: +`FEAR_PER_FOCUS_HIT`
- on **ally KO this round**: every surviving ally +`FEAR_PER_ALLY_KO`
- on **round tick**: existing `FEAR_PER_ROUND` still applies

This ensures that 2–3 bad rounds are enough to reach the refusal threshold, which was the original Notion test goal (“At fear 70, refusal triggers in sample”).

**QA Commands (debug_console):**

- `/fear_show` → list current combat allies with their fear
- `/fear_set 1 80` → force hero with id=1 to fear=80 (current fight + persisted for future demo fights)
- `/fight_again` → re-run same fight, fear is re-applied

**Persistence (MVP+ for tooling):**

- Console keeps an in-memory `_fear_overrides_persist` map so that setting fear once applies to every new `/fight_demo` in the same session.
- `SaveService.gd` gained `hero_set_fear(id, value)` so fear can be written into the actual save roster.
- The demo fight builder now reapplies persisted fear onto the newly created combat state, so the “I was scared in the last fight” feeling can be demonstrated.

**Post-MVP: High-severity Abandon / Retreat**

During this user story we discovered that “retreat” should **not** be a casual outcome of normal fear refusal. Canonically, abandoning the party/sanctum is a *severe* act and must yield legacy value (see LND §10 “Loss as continuity”). Therefore:

- MVP fear refusal only ever produces: **"refuse"** or **"guard"**.
- **Abandon/retreat** is reserved for a **separate, higher-threshold trigger**, e.g.:
  ```gdscript
  const FEAR_ABANDON_THRESHOLD: int = 95
  const FEAR_ABANDON_BASE_CHANCE: float = 0.35
  ```
- When triggered, combat should **signal** an abandon event (e.g. `notes: "fear_abandon_signal"`) but the *actual* removal from Sanctum / roster should be handled by the campaign/sanctum layer, not in combat.
- This keeps combat MVP fair and readable, and keeps permanent loss tied to legacy recovery (Faith / Legacy Fragments) per canon §10.


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