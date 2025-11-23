# ⚔️ Echoes of the Sankofa — MVP Combat Rounds Addendum

**Canon Source:** Legacy Never Dies §§3, 4, 9, 12  
**Directive:** Deterministic Fairness — *same seed ⇒ same fight*.

---

## 1. Purpose & Scope

This addendum defines how **MVP combat rounds** work in *Echoes of the Sankofa* after the
**generic entities + orchestrator refactor** (Subtasks A → H).

It answers for any new dev/AI:

- How a **battle** is set up and advanced, step by step.
- Which **modules** own which responsibilities.
- How **morale & fear** affect actions and damage.
- How **objectives** (combat_trial, purify_shrine) plug into the loop.
- How to keep fights **deterministic** and **legible**.

This document is the runtime companion to:
- `combat_entities_mvp.md` (entity shape & tags)
- `combat_engine_refactor.md` (module responsibilities)

If behavior changes, **this file and those two must be updated together.**

---

## 2. High‑Level Loop

**Philosophy:**  
**Guidance > Control** — The Keeper chooses who to send and how to invest in them.
Once the fight starts, Anansi’s game unfolds in a **deterministic, legible autobattle**.

At a high level, a battle is:

1. **Start Battle**
   - Build combat state from realm stage, party, and config.
   - Normalize all entities into the **generic entity model**.
   - Capture **emotion baselines**.
   - Build **objective context** for the stage.

2. **Round Loop** (`step_round`)  
   Repeat until an objective finishes or a round limit is reached:
   
   1. Build round context (round index, PRNG, objective info).
   2. Compute **initiative order**.
   3. For each actor in order:
      - Check **fear‑driven refusal**.
      - Choose actions (ally AI / enemy AI).
      - Resolve actions and apply HP / statuses.
      - Track fear gain from hits, focus fire, ally KOs.
   4. Apply **KO fear** and the **round emotional tick** (fear + morale decay).
   5. Let **CombatObjectives** evaluate end conditions.
   6. Build a **round snapshot** and append logs.

3. **End Battle**
   - Final objective result (victory/defeat + reason).
   - Final HP, KO status, shrine status, emotions.
   - Deterministic log and snapshot trail.

---

## 3. Modules Involved (Runtime View)

The combat round loop is now split across modules. **CombatEngine** only orchestrates:

- **`core/combat/CombatEngine.gd`** – Orchestrator
  - `start_battle(stage, party, seed)`
  - `step_round()`
  - Holds the mutable `state` (entities, round index, objective context, snapshots).

The orchestration calls into:

- **`core/combat/CombatEntities.gd`** – Generic entity model
  - Normalizes heroes, enemies, shrines, NPCs, summons, structures.
  - Tag helpers (`has_tag`, `is_shrine`, `is_structure`, `is_objective`, …).
  - HP read/write helpers.

- **`core/combat/Initiative.gd`** – Initiative scoring
  - Computes initiative per round from stats + seed.

- **`core/combat/EchoActionChooser.gd`** – Ally action chooser (MVP AI)
  - Chooses ATTACK / GUARD / PURIFY_SHRINE / REFUSE (morale) for allies.

- **`core/combat/EnemyActionChooser.gd`** – Enemy AI
  - Chooses ATTACK / GUARD for enemies.
  - Implements shrine‑aware targeting when objective is a shrine.

- **`core/combat/ActionResolver.gd`** – Action rules
  - Resolves ATTACK, GUARD, PURIFY_SHRINE, REFUSE, KO.
  - Applies morale multipliers.
  - Exposes `should_refuse_turn(unit_dict)` for fear‑driven refusals.

- **`core/combat/CombatEmotionSystem.gd`** – Morale & fear
  - Baseline capture, round tick, KO fear, shrine wave morale drain.
  - Builds final emotion results.

- **`core/combat/CombatObjectives.gd`** – Objective logic
  - `defeat` (combat_trial).
  - `purify_shrine` (waves, shrine HP, Purify and drain tuning).
  - Future: `escort_entity`, `defend_structure`, `destroy_target`, `multi_objective`.

- **`core/combat/CombatSnapshotBuilder.gd`** – Snapshots
  - Builds per‑round snapshots and a final snapshot.
  - Builds name map and final state.

- **`core/combat/CombatLog.gd`** – Log formatting
  - Prints deterministic single‑line logs per action.

- **Config:**
  - `core/config/GameBalance_HeroCombat.gd` – morale, fear, shrine combat tuning, logging profiles.
  - `core/config/GameBalance_Realm.gd` – realm + shrine tier tuning (HP, drain, morale penalties, rewards).

---

## 4. Round Phases (Detailed)

Every `step_round` call advances combat through the same phases.

| Phase | Description | Primary Owner |
|:------|:------------|:--------------|
| **INITIATIVE** | Compute deterministic order for this round. | `Initiative.gd` |
| **FEAR CHECK** | For each acting entity, decide if fear forces refusal. | `ActionResolver.gd` + `CombatEmotionSystem.gd` |
| **SELECT** | For non‑refusing actors, choose Major/Minor actions. | `EchoActionChooser.gd` / `EnemyActionChooser.gd` |
| **RESOLVE** | Apply chosen actions (ATTACK, GUARD, PURIFY_SHRINE, REFUSE). | `ActionResolver.gd` |
| **EMOTION TICK** | Apply KO fear, fear tick, and morale decay. | `CombatEmotionSystem.gd` |
| **OBJECTIVE CHECK** | Determine victory/defeat/continue. | `CombatObjectives.gd` |
| **SNAPSHOT** | Record the round summary + logs. | `CombatSnapshotBuilder.gd` + `CombatLog.gd` |

The engine’s job is to call these phases in order and glue the results back into `state`.

---

## 5. Initiative Formula (MVP)

**Goal:** same inputs ⇒ same initiative order.

Conceptual formula:

```text
score = base + a*Courage + b*Wisdom + tiebreak(seed, hero_id, round_index)
```

- `a` and `b` are tuning knobs in `CombatConstants.gd`.
- Tiebreak uses a deterministic combination of the encounter seed, entity id, and
  round index to avoid random ties.
- Initiative is recomputed **every round**, so temporary buffs/debuffs can affect
  turn order in future versions.

The function lives in `Initiative.gd` and only depends on:
- The combat seed (from realm stage).
- The round index.
- The entity’s stats (Courage/Wisdom, etc.).

---

## 6. Action Economy (MVP)

### 6.1 Per‑Round Budget

Each combatant can perform at most:

- **1 Major Action** (ATTACK / REFUSE / PURIFY_SHRINE / INTERACT stub)
- **1 Minor Action** (GUARD / MOVE stub / INTERACT stub)

In practice for MVP:

- Heroes:
  - **Major:** ATTACK or PURIFY_SHRINE or REFUSE.
  - **Minor:** GUARD (MOVE/INTERACT reserved for future).
- Enemies:
  - **Major:** ATTACK.
  - **Minor:** GUARD (shrine bias comes from target selection, not a different action).
- Shrine:
  - No actions at all; it is a defended structure, not an actor.

The action budget is enforced in the orchestrator loop and resolvers; no action
may be resolved twice in the same phase.

### 6.2 ATTACK & GUARD

- **ATTACK**
  - Uses Attack vs Defense with a simple, deterministic formula.
  - Damage is modified by the attacker’s **morale tier**.
  - For shrine stages, attacks against the shrine get a multiplier
    (`SHRINE_ENEMY_DAMAGE_MULTIPLIER`).

- **GUARD**
  - Adds a guard value to the target.
  - The next incoming damage is reduced based on accumulated guard.
  - Guard is reset/decayed via the normal damage pipeline.

### 6.3 KO Handling

- When `hp_current <= 0`, entity is marked `ko = true` in its status.
- KO units:
  - Never act.
  - May still appear in logs and snapshots for context.
- MVP has **no permanent death** in combat; persistence is decided by
  higher‑level systems per canon §10 “Loss as continuity”.

---

## 7. Morale System (MVP Final)

**Story:** *“As the Keeper I want morale to affect output.”*

Combat tracks a **morale** value (0–100) per hero. Enemies are not yet using
morale tiers in MVP.

### 7.1 Morale Tiers & Effects

| Tier      | Range | Multiplier | Behavior |
|-----------|:-----:|:----------:|----------|
| INSPIRED  | 80–100| × 1.10     | +10% damage on ATTACK |
| STEADY    | 50–79 | × 1.00     | Baseline output |
| SHAKEN    | 30–49 | × 0.90     | −10% damage on ATTACK |
| BROKEN    | 0–29  | —          | Cannot take major actions; uses REFUSE |

Implementation details:

- Thresholds and multipliers live in `CombatConstants.gd`.
- `CombatEmotionSystem.gd` is responsible for:
  - Reading/writing morale on entities.
  - Computing the **tier label**.
- `ActionResolver.gd` is responsible for:
  - Applying the multiplier on ATTACK.
  - Translating BROKEN tier into a major‑action REFUSE.

### 7.2 Morale Decay & Tick

Round tick behavior:

- Every N rounds (`MORALE_DECAY_N_ROUNDS` in `CombatConstants.gd`),
  `CombatEmotionSystem.apply_round_tick` reduces morale by a small amount.
- Additional morale effects may come from:
  - Shrine wave drain (see §9.3).
  - Future story events and skills.

MVP baseline:

| Variable                 | Typical MVP Value | Source |
|--------------------------|-------------------|--------|
| `MORALE_DECAY_N_ROUNDS`  | 2                 | `CombatConstants.gd` |
| `MORALE_DECAY_PER_TICK`  | small negative    | `CombatConstants.gd` |

Morale is **combat‑local** for MVP and resets to a neutral baseline
per fight unless debug tools or save data override it.

---

## 8. Fear System & Refusal (MVP Final)

**Story:** *“As the Keeper I want fear to push refusal.”*

Fear adds a second axis of emotional pressure:

- Every entity has `fear` (0–100).
- Fear increases from:
  - Taking hits.
  - Being focus‑fired in the same round.
  - Ally KOs.
  - Round tick baseline.
- High fear can cause a **fear‑driven refusal** of the turn, even if morale
  is not yet Broken.

### 8.1 Fear ⇒ Refusal Flow

Execution order within a round:

1. Initiative order decided.
2. For each actor in order, `ActionResolver.should_refuse_turn(unit_dict)` is called.
3. This function:
   - Clamps fear to `[0, FEAR_MAX]`.
   - Checks `FEAR_REFUSAL_THRESHOLD` (config in `GameBalance_HeroCombat.gd`).
   - If below threshold → no fear refusal.
   - If at/above threshold → compute refusal chance based on:
     ```gdscript
     FEAR_REFUSAL_BASE_CHANCE + 
     FEAR_REFUSAL_PER_10_OVER * ((fear - FEAR_REFUSAL_THRESHOLD) / 10)
     ```
   - Uses the deterministic combat PRNG to roll.
   - If roll passes, returns an outcome:
     - **"refuse"** → skip major action.
     - **"guard"** → take a defensive minor GUARD on self.
4. CombatEngine applies this outcome via a small helper and logs it.
5. If there is **no fear refusal**, normal major/minor selection proceeds.

MVP deliberately **excludes** “retreat/abandon” from this path; abandoning the
Sanctum or a run is a high‑severity event (canon §10) and will have its own
separate trigger in future.

### 8.2 Fear Gains

Config lives in `GameBalance_HeroCombat.gd`:

```gdscript
const FEAR_REFUSAL_THRESHOLD: int = 70
const FEAR_MAX: int = 100
const FEAR_REFUSAL_BASE_CHANCE: float = 0.35
const FEAR_REFUSAL_PER_10_OVER: float = 0.05

const FEAR_PER_HIT: int = 2
const FEAR_PER_ALLY_KO: int = 4
const FEAR_PER_FOCUS_HIT: int = 1
const FEAR_PER_ROUND: int = 1
```

- **Per hit:** every time an entity takes damage, fear increases.
- **Focus fire:** being hit multiple times in one round adds extra fear.
- **Ally KO:** when an ally drops to 0 HP in this round, surviving allies
  gain fear.
- **Tick:** round‑level bonus via `FEAR_PER_ROUND`.

`CombatEmotionSystem` owns how these increments are applied during the
resolution and tick phases.

### 8.3 Debug Tools

`debug_console.gd` exposes:

- `/fear_show` – list current combat allies with their fear.
- `/fear_set <id> <0..100>` – force hero fear, with in‑session persistence.

These commands are used heavily in QA to verify that refusal triggers at the
expected thresholds.

---

## 9. Purify Shrine as a Combat Scenario (MVP Final)

**Story:** *“As the Keeper I want an actual shrine to protect, purify action and enemies that attack the shrine.”*

Purify Shrine is a **realm objective** that manifests as a special combat stage
with an allied shrine structure and multiple enemy waves.

### 9.1 Realm Inputs (Balance Source of Truth)

Realm tuning lives in `GameBalance_Realm.gd` under the `PURIFY_SHRINE` block.
Combat treats this file as authoritative for **tier scaling**.

Helpers include:

- `get_purify_shrine_hp(tier)`
- `get_purify_shrine_passive_drain_per_wave(tier)`
- `get_purify_morale_drain(tier)`
- `get_purify_reward_mult(tier)`
- `get_purify_shrine_drain_reduction(tier)`
- `get_purify_shrine_hp_threshold_fraction(tier)`
- `get_purify_shrine_max_purify_per_wave(tier)`

### 9.2 Shrine as a Generic Entity

Shrine is normalized by `CombatEntities` as:

```text
["ally", "structure", "structure:defense", "objective", "objective:shrine"]
```

Key points:

- Shrine has `hp_current` and `hp_max` from `get_purify_shrine_hp(tier)`.
- Shrine **never acts** (no actions chosen).
- Enemy AI recognizes the shrine via tags and objective context.

### 9.3 Enemy Behavior in Shrine Stages

In Purify Shrine stages, `EnemyActionChooser`:

- Defaults ATTACK targets to the **shrine** while it is alive.
- Uses normal damage pipeline, then multiplies shrine damage by
  `SHRINE_ENEMY_DAMAGE_MULTIPLIER` from `GameBalance_HeroCombat.gd`.
- Falls back to normal targeting once the shrine is destroyed (for future
  “fail‑but‑keep‑fighting” variants).

### 9.4 Purify Action & Waves

Purify is a **support Major Action** available only in Purify Shrine objectives:

- Only available when:
  - Objective type is `purify_shrine`.
  - Shrine is alive.
  - Shrine HP is below the **tier‑adjusted threshold** from
    `get_purify_shrine_hp_threshold_fraction(tier)`.
  - The designated **purifier hero** is off cooldown.
  - The wave has not reached its max Purify count.

On a successful Purify:

- The current wave is marked as having a **Purify stack**.
- At the **end of the wave**, when passive shrine drain is applied, that drain
  is reduced by a multiplier combining:
  - `SHRINE_PURIFY_BASE_DRAIN_REDUCTION` from `GameBalance_HeroCombat.gd`.
  - `get_purify_shrine_drain_reduction(tier)` from realm balance.
- Purify **does not restore HP**, it only reduces the *upcoming* drain.

Between waves:

- Shrine loses HP from passive drain.
- Heroes suffer morale drain via `get_purify_morale_drain(tier)`.

### 9.5 Purifier System (Designated Purifier, MVP)

To keep the UX clean and emphasize story, shrine stages use a
**designated purifier**:

- At the **start of the stage**, `CombatEngine` asks `GameBalance_HeroCombat.gd`
  to score each hero based on:
  - Archetype (Devout gets a bonus).
  - Faith.
  - Wisdom.
  - Morale (tiebreaker).
- The highest‑scoring hero becomes the **purifier** for this stage.
- Only this hero is allowed to take the `PURIFY_SHRINE` major action.
- Per‑hero cooldown is `SHRINE_PURIFY_COOLDOWN_ROUNDS`.
- Per‑wave cap is `get_purify_shrine_max_purify_per_wave(tier)` from realm.

Post‑MVP, the Keeper may be allowed to **choose** the purifier explicitly
(see §11.1).

### 9.6 Objective Result

`CombatObjectives` defines Purify Shrine success/failure:

- **Success** if:
  - All configured waves are cleared, and
  - Shrine HP > 0 at the end of the last wave.

- **Failure** if at any point:
  - Shrine HP ≤ 0 ⇒ `reason = "shrine_destroyed"`.

Reward multipliers and emotion outputs are derived from realm helpers and
`CombatEmotionSystem` results.

---

## 10. Combat Logs & Snapshots (MVP Final)

**Story:** *“As the Keeper I want readable combat logs.”*

### 10.1 Single‑Line Action Logs

Every **loggable** action produces exactly **one line**:

```text
<actor> <VERB> → <target?> <payload> <tags…>
```

- If there is no target, omit the arrow.
- The line is fully deterministic; no ad‑hoc prints.

**Verbs (MVP):** `ATTACK`, `GUARD`, `REFUSE`, `TICK`, `KO`.

Payload examples:

- `ATTACK` → `dmg=<N>`
- `GUARD` → `(+shield)`
- `REFUSE` → `(fear_refusal, fear=<N>)` or `(morale_refusal, morale=<N>)`
- `TICK` → `(round_tick)`

Tag ordering intent:

1. HP/status — `[hp/max]` or `[0/40 KO]`.
2. Guard — `[guard=<N>]` (only if `N>0`).
3. Designer breakdown — `[ATK <A> → DEF <D>]`.

### 10.2 Verbosity Profiles

`GameBalance_HeroCombat.gd` defines:

- `LOGGING_PROFILES` – named sets of flags; currently:
  - `"mvp"` – minimal player‑facing (HP only).
  - `"designer"` – HP + guard + breakdown.
  - `"qa"` – designer + extra internal crumbs (future).
- `LOG_PROFILE` – active profile.
- Overrides:
  - `LOG_OVERRIDE_SHOW_HP`
  - `LOG_OVERRIDE_SHOW_GUARD`
  - `LOG_OVERRIDE_SHOW_DMG_BREAKDOWN`
  - `LOG_OVERRIDE_SHOW_INTERNAL`

`CombatLog.gd` resolves the active flags per line and formats accordingly.

### 10.3 Snapshots

`CombatSnapshotBuilder.gd` builds a canonical payload per round:

```gdscript
{
    "round": int,
    "order": Array[int],          # entity ids
    "actions": Array[Dictionary], # per actor
    "ticks": {                    # fear, morale, shrine drain, etc.
        "fear_tick": int,
        "morale_decay": bool,
        # shrine wave info, if any
    },
    "state_after": {              # HP/KO/guard per entity
        "entities": Dictionary,
    },
    "end": Dictionary | null      # objective result if finished this round
}
```

The final snapshot includes:

- All per‑round snapshots.
- `final_state` (entities, shrine, objectives, emotions).
- `name_map` from entity id → final display name.

The `/fight_again` debug command replays a battle from its snapshot payload and
seed and must reproduce the same fight.

---

## 11. Debug Console & QA Tools

All interactive testing lives in `core/ui/debug/debug_console.gd`.

### 11.1 Party & Fights

- `/party_list` – list available heroes.
- `/party_set <ids…>` – stage a valid party (max 3 heroes in MVP).
- `/party_show` – show staged party with full info.
- `/party_clear` – clear staged party.
- `/fight_demo [seed] [rounds] [--auto]` – run a deterministic training fight.
- `/fight_again` – replay the last fight.

### 11.2 Emotions

- `/morale_show` – show current morale and tier.
- `/morale_set <id> <0..100>` – adjust morale for a hero.
- `/fear_show` – show current fear.
- `/fear_set <id> <0..100>` – adjust fear.

These commands are used during development to verify that logs, refusal, and
Purify timing match the intended MVP behavior.

---

## 12. Future Extensions (Post‑MVP)

These are not implemented yet, but the current architecture is designed to
support them with **new modules/config**, not new god‑scripts.

### 12.1 New Objectives

- **Escort entity** – keep a tagged escort target alive while moving through waves.
- **Defend structure** – hold a gate/ward for a number of rounds.
- **Destroy target** – break an enemy structure objective.
- **Multi‑objective** – e.g. defend shrine *and* escort.

All of these should only require new handlers in `CombatObjectives.gd` and
additional tags in entity definitions.

### 12.2 Keeper‑Chosen Purifier

Currently, shrine stages auto‑select a purifier. Post‑MVP:

- Keeper may explicitly choose the purifier at shrine stage start.
- This adds a strong “protect the purifier” micro‑narrative.
- Purifier selection UI can sit on top of the existing assignment hook.

### 12.3 Richer Action Types

- Skills, reactions, positional effects.
- Personality‑colored behavior via archetypes.
- Status effects and conditions (bleed, guard break, etc.).

The action economy and orchestrator loop remain the same; only
`ActionResolver`, `EchoActionChooser`, and `EnemyActionChooser` gain new cases.

---

## 13. Canon References

- **§3 Loop pacing** – visible rounds, readable cadence.
- **§4 Core Mechanics** – major/minor action economy and deterministic seed use.
- **§5 Heroes / Personality** – morale, fear, and refusal loops.
- **§9 Combat AI & Simulation** – mandates deterministic combat resolution.
- **§12 Balance Curves** – how morale and fear shape difficulty.

---

## 14. Definition of Done (for this Addendum)

This document is considered up to date when:

- It matches the behavior of:
  - `CombatEngine.gd` orchestration.
  - `CombatEntities.gd` entity model & tags.
  - `CombatEmotionSystem.gd` morale/fear rules.
  - `CombatObjectives.gd` defeat + purify_shrine objectives.
  - `EnemyActionChooser.gd` shrine targeting.
  - `CombatSnapshotBuilder.gd` snapshot shape.
  - `CombatLog.gd` output shape and logging profiles.
- A new dev can, from this file plus `combat_entities_mvp.md` and
  `combat_engine_refactor.md`, correctly implement:
  - A new unit type using tags.
  - A new objective type.
  - A new stage type using existing round phases.

Any change to combat round behavior **must** be reflected here as part of the
story’s Definition of Done.