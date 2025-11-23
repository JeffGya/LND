

# Combat Engine Refactor (Generic Entity-Oriented)

**Status:** Implemented for MVP (combat trials + purify shrine)  
**Scope:** Core combat loop + module split + generic entity support  
**Related docs:** `combat_rounds_mvp.md`, `shrine_combat.md`, `realms_mvp.md`, `combat_entities_mvp.md`

This addendum describes the *current* combat engine architecture after the refactor to support **generic combat entities** (heroes, enemies, structures, shrines, escorts, summons, NPCs) and **modular objectives**.

It is written for:

- Future you (coming back in 6+ months)
- AI assistants
- New devs joining this project

If you only remember one thing: **CombatEngine is now an orchestrator. All domain logic lives in small focused modules.**

---

## 1. Design Goals

### 1.1 Primary goals

1. **Generic combat entities**

   - Support **structures, shrines, NPCs, summons, escorts, bosses** and arbitrary future entities.
   - Use a **tag-based role system** instead of hard-coded `is_shrine` or special-case branches.
   - Make it possible to add a new entity type *without* editing CombatEngine.

2. **Thin, readable CombatEngine**

   - CombatEngine should:
     - Own the **round loop**.
     - Wire modules together.
     - Keep no bespoke shrine/realm logic.
   - Anything that looks like domain rules should live in:
     - `CombatEntities.gd`
     - `CombatEmotionSystem.gd`
     - `CombatObjectives.gd`
     - `EnemyActionChooser.gd`
     - `CombatSnapshotBuilder.gd`

3. **Objective-driven stages**

   - Different stage types (combat trial, purify shrine, escort, defend, destroy, multi-objective) should be expressed as:
     - An **objective descriptor** on the stage.
     - A **handler** inside `CombatObjectives.gd`.
   - CombatEngine should ask:
     > “Is the battle over yet, given this objective + state?”
     not
     > “Did the shrine die? Did the escort cart die? Did all enemies die?”

4. **Determinism and seed stability**

   - The refactor must **not** change:
     - Random sequences for existing stage types.
     - Battle outcomes for the same seed/input.
   - Realm generation + objective selection remain stable and tested under `/run_tests realms`.

### 1.2 Non-goals (for now)

- No “perfect” AI architecture (we keep the simple chooser, but move it out).
- No UI overhaul.
- No multiplayer or network sync concerns yet.
- No save/load of in-progress combats (but the state structure is compatible with this later).

---

## 2. High-Level Architecture

The combat stack now looks like this:

- **Stage / Realm layer**
  - `RealmService.gd`
  - `ObjectiveRunner.gd`
  - Build stage descriptors (realm, stage index, objective type, modifiers, fear_delta, etc.)
  - Pass **objective** + **encounter seed** into CombatEngine.

- **Combat core**
  - `CombatEngine.gd` — **orchestrator**, owns the loop.
  - `CombatEntities.gd` — shapes, tags, helpers.
  - `CombatEmotionSystem.gd` — fear & morale system.
  - `CombatObjectives.gd` — objective context + end conditions.
  - `EnemyActionChooser.gd` — enemy action selection.
  - `CombatSnapshotBuilder.gd` — per-round + final snapshots for logs/UI.

- **Outer systems**
  - `ActionResolver.gd` — atomic action resolution (attacks, purify, guard, refusal, etc.).
  - `GameBalance_HeroCombat.gd` — tuning knobs, thresholds, deltas.
  - `CombatConstants.gd` — symbolic keys used across modules.
  - `DebugConsole.gd` — test harness + `/run_tests realms` generic entity tests.

---

## 3. Data Model

### 3.1 Generic entity DTO (summary)

The full schema is defined in `combat_entities_mvp.md`. The shape used by the engine:

```gdscript
{
    "id": int,
    "name": String,
    "stats": {
        "hp": int,
        "max_hp": int,
        "atk": int,
        "def": int,
        "agi": int,
        "morale": int,
        "fear": int,
        # ... additional stats as needed
    },
    "tags": Array[String],    # central to generic model
    "archetype": String,      # optional (hero archetype etc.)
    "status": String,         # "ok", "ko", etc.
    "ai_profile": String,     # optional AI hint
    "objective_id": int,      # optional link to objective context
    "meta": Dictionary        # free-form (realm id, wave index, etc.)
}
```

Examples:

- Normal hero:
  ```gdscript
  ["ally", "hero"]
  ```

- Shrine (Purify Shrine objective):
  ```gdscript
  ["ally", "structure", "objective", "objective:shrine"]
  ```

- Future escort cart:
  ```gdscript
  ["ally", "structure", "escort_target", "objective"]
  ```

- Destructible enemy gate:
  ```gdscript
  ["enemy", "structure", "objective", "objective:gate"]
  ```

### 3.2 Battle state (conceptual)

The combat state passed around by the engine looks roughly like:

```gdscript
{
    "allies": Array[Dictionary],        # normalized entities
    "enemies": Array[Dictionary],
    "round": int,
    "log": Array,                       # raw round logs (for snapshot builder)
    "objective": Dictionary,            # type, params, context (shrine id etc.)
    "emotion_baseline": Dictionary,     # captured at start
    "emotion_result": Dictionary,       # set at the end
    "meta": {                           # flexible container
        "realm_id": String,
        "stage_index": int,
        "tier": int,
        "encounter_seed": int,
        "stage_type": String,           # "combat_trial", "purify_shrine", ...
        # ...
    }
}
```

`CombatEngine` is responsible for creating and mutating this state, but delegates *interpretation* of it to the specialized modules.

---

## 4. Module Responsibilities

### 4.1 CombatEngine.gd (orchestrator)

#### 4.1.1 Public API

Typical surface (names simplified for clarity):

```gdscript
func start_battle(params: Dictionary) -> Dictionary
func step_round(state: Dictionary) -> Dictionary
```

- **start_battle(params)**:
  - Input: heroes, enemies, realm/stage meta, objective descriptor, config handles.
  - Responsibilities:
    1. Normalize allies/enemies via `CombatEntities`.
    2. Attach tags (heroes, enemies, shrines, etc.).
    3. Apply any morale overrides (realm-specific).
    4. Capture emotion baseline via `CombatEmotionSystem.capture_baseline`.
    5. Build objective context via `CombatObjectives.build_objective_context`.
    6. Seed initial state (`round = 0`, empty logs).
    7. (Optionally) auto-run first round for certain contexts.

- **step_round(state)**:
  - Called once per combat round.
  - Responsibilities:
    1. Construct a **round context** (refs to services, config, meta).
    2. Compute initiative order.
    3. For each actor in initiative:
       - Apply fear-based refusal (via ActionResolver / fear thresholds).
       - Choose ally action (currently simple: attack / guard / purify).
       - Choose enemy action via `EnemyActionChooser`.
       - Resolve the action via `ActionResolver`.
       - Track KO events for later fear processing.
    4. Apply KO fear via `CombatEmotionSystem.apply_ally_ko_fear`.
    5. Apply round tick via `CombatEmotionSystem.apply_round_tick`:
       - fear accumulation
       - morale decay (if enabled)
       - shrine drain (objective-aware)
    6. Ask `CombatObjectives.check_end` whether the fight is over.
    7. Build a per-round snapshot via `CombatSnapshotBuilder`.
    8. If ended:
       - Build final emotion result via `CombatEmotionSystem.build_emotion_result`.
       - Attach final_state snapshot to the result.

CombatEngine **never** directly iterates shrines / escorts / gates. It asks:

- `CombatEntities` to find entities by tag.
- `CombatObjectives` to interpret them in the context of the current objective.

---

### 4.2 CombatEntities.gd

Purpose: **single source of truth for entity shape + tag helpers**.

Key responsibilities:

- Normalize config / save-data into standardized entities:
  - `normalize_allies(allies_raw, HeroBal)`
  - `normalize_enemies(enemies_raw, HeroBal)`
- Stat helpers:
  - `_ensure_stat_int(ent, key)`
  - `read_hp_pair(ent)` → `{ "hp": int, "max_hp": int }`
- Tag helpers:
  - `has_tag(ent, tag: String) -> bool`
  - `add_tag(ent, tag: String)`
  - `ensure_tags(ent, tags: Array)`
  - `find_first_with_tag(group, tag) -> Dictionary or null`
  - `is_structure(ent)`
  - `is_objective(ent)`
  - `is_shrine(ent)` → by tags, not special-case field.
- Future:
  - Summon helpers.
  - Escort target discovery (`find_first_with_tag(group, "escort_target")`).
  - Group queries (all shrines, all structures, etc.).

This module makes it trivial for other systems to say *“give me the shrine”* or *“give me any escort targets”* without knowing where that data came from.

---

### 4.3 CombatEmotionSystem.gd

Purpose: **centralize morale & fear logic**, independent of objective type.

Key responsibilities:

- `capture_baseline(state)`
  - Record starting morale/fear per hero.
- `apply_round_tick(state, HeroBal, ctx)`
  - Increment fear each round by a realm/stage-defined amount.
  - Apply morale decay on long/stressful fights (according to config).
  - Apply **shrine drain** (for Purify Shrine type objectives), using:
    - Objective context (e.g., which structure is the shrine).
    - `GameBalance_HeroCombat` / config for drain per wave or round.
- `apply_ally_ko_fear(state, HeroBal)`
  - When an ally is KO’d, increase fear of surviving allies.
  - Tuned via hero combat balance config.
- `build_emotion_result(state)`
  - Compare final morale/fear to baseline and produce:
    - Per-hero deltas.
    - Summary per stage type (combat_trial, purify_shrine, etc.).
- Label helpers:
  - `_morale_tier_label(value)` – convert numeric morale into qualitative label (e.g. “shaken”, “steady”, “inspired”).

This system treats shrine fights just as another **context**, driven by objective tags and realm metadata.

---

### 4.4 CombatObjectives.gd

Purpose: **define objectives and end conditions**.

Key responsibilities:

- `build_objective_context(state)`
  - Derive context from the current state and tags, such as:
    - Shrine entity id (for protect-shrine).
    - Protected structure lists.
    - Escort target entity.
    - Multi-objective sets (e.g., defend shrine *and* keep escort alive).
- `check_end(state, objective, round_limit, hero_bal) -> Dictionary`
  - Determines whether the battle is over and why.
  - Examples:
    - **Defeat enemies**
      - End when all enemies are KO.
    - **Protect shrine**
      - Lose when shrine HP reaches 0.
      - Win when all enemies are KO *or* wave conditions met.
    - **Future objectives**
      - Escort: fail if escort_target dies, win on surviving exit.
      - Destroy target: win when gate/structure is destroyed.
      - Multi-objective: both conditions must be satisfied (or prioritized).

- Helper functions to keep logic clean:
  - `_all_enemies_defeated(state)`
  - `_shrine_destroyed(state, ctx)`
  - `_objectives_satisfied(state, ctx)`

CombatEngine just calls `CombatObjectives.check_end(...)` and uses the reply:

```gdscript
{
    "ended": bool,
    "victory": bool,
    "reason": String,  # "enemies_defeated", "shrine_destroyed", etc.
}
```

---

### 4.5 EnemyActionChooser.gd

Purpose: **centralize enemy AI decision-making**.

Key responsibilities:

- `choose_action(state, enemy_ent, ctx) -> Dictionary`
  - Returns an action descriptor (attack, guard, purify_shrine, etc.) to be fed into `ActionResolver`.

- Current behaviors:
  - Preserve existing shrine priority:
    - When shrine is present and protected, enemies may prefer to attack the shrine or shield its defenders (depending on their type).
  - Simple target heuristics:
    - `_pick_lowest_hp_ratio(allies)`
    - `_pick_weakest(allies)`

- Future behaviors:
  - Objective-aware targeting:
    - Prefer `escort_target` if escort objective is active.
    - Prefer `structure` / `objective` entities when appropriate.
  - Personality/archtype-aware targeting (courageous, devout, etc.).

By living outside CombatEngine, this file is easy to iterate on without touching the core loop.

---

### 4.6 CombatSnapshotBuilder.gd

Purpose: **build stable snapshots for logs and UI**.

Key responsibilities:

- `build_round_snapshot(state, ctx) -> Dictionary`
  - Round number.
  - Turn order.
  - Actions taken.
  - HP/guard/morale/fear summaries.
- `build_final_result(state, objective_result, emotion_result) -> Dictionary`
  - Victory/defeat.
  - End reason from `CombatObjectives`.
  - Final HP of all entities (including shrines / structures).
  - Emotion deltas from `CombatEmotionSystem`.
  - Realm/stage metadata from `state.meta`.

- Helpers:
  - `build_name_map(allies, enemies)`
  - `_hero_name_from_save` (if needed).
  - HP readers (`read_hp_pair`) in cooperation with `CombatEntities`.

The snapshot format is intentionally rigid so that:

- Debug logs remain readable.
- UI rendering can rely on consistent keys.
- Tests can assert on behavior without depending on internal engine details.

---

## 5. Round Lifecycle (Step-Based)

The step-based combat loop is described in detail in `combat_rounds_mvp.md`. This section summarizes how the refactored engine wires the modules together.

1. **Initialization**
   - `CombatEngine.start_battle` creates the state.
   - Entities are normalized + tagged.
   - Emotion baseline captured.
   - Objective context built.

2. **Per-round (`step_round`)**
   1. Increment round counter.
   2. Compute initiative order (using AGI and deterministic seed).
   3. Iterate over actors:
      - If actor is KO, skip.
      - Determine action:
        - Ally → simple heuristic or later player input.
        - Enemy → `EnemyActionChooser.choose_action`.
      - Send action into `ActionResolver`:
        - Mutates entities (HP, status, guard, shrine HP, etc.).
        - Broadcast log entries.
      - Record KO events for fear processing.
   4. Apply KO fear:
      - `CombatEmotionSystem.apply_ally_ko_fear`.
   5. Apply round tick:
      - `CombatEmotionSystem.apply_round_tick` (fear, morale decay, shrine drain).
   6. Check end-condition:
      - `CombatObjectives.check_end`.
   7. Build round snapshot:
      - `CombatSnapshotBuilder.build_round_snapshot`.

3. **Battle end**
   - If ended:
     - Build emotion result:
       - `CombatEmotionSystem.build_emotion_result`.
     - Build final snapshot + result:
       - `CombatSnapshotBuilder.build_final_result`.
   - Callers (ObjectiveRunner/RealmService/UI) consume the result.

---

## 6. Shrine & Purify Shrine Integration

The shrine objective is just one concrete use of the generic system.

- Shrine entity:
  - Tags: `["ally", "structure", "objective", "objective:shrine"]`.
  - Lives in the `allies` list as a normal entity.
- Objective:
  - `objective_type = OBJECTIVE_PROTECT_SHRINE` (see `CombatConstants.gd`).
- End conditions:
  - Victory:
    - All enemies KO **and** shrine still alive.
  - Defeat:
    - Shrine HP reaches 0.
- Emotion:
  - Fear & morale adjusted per wave.
  - Additional pressure from shrine HP loss (encoded via config).

More detailed shrine rules live in `shrine_combat.md`. This document focuses on **where** the logic is hosted, not all of the numbers.

---

## 7. Generic Entities & Future Objectives

The refactor was explicitly built to make these future tasks straightforward:

- **Escort cart**
  - Stage spawns:
    - Allied heroes.
    - Allied `escort_target` structure.
  - Objective:
    - `OBJECTIVE_ESCORT_ENTITY`.
  - Rules live in `CombatObjectives.gd`.
  - AI can prioritize threats to the escort via `EnemyActionChooser`.

- **Defense ward / totems**
  - Stage spawns:
    - Allied structures with tags like: `["ally", "structure", "ward"]`.
  - Objective:
    - Survive X rounds with at least one ward alive.
  - `CombatObjectives.check_end` decides when enough wards have survived.

- **Destructible gate**
  - Enemy structure with `["enemy", "structure", "objective:gate"]`.
  - Objective:
    - Win when gate HP is 0, regardless of remaining minions.
  - AI/targeting can be nudged to protect the gate.

- **Multi-objective**
  - E.g. “Protect shrine *and* keep escort alive”.
  - Context:
    - Multiple structure entities with different objective roles.
  - `CombatObjectives` composes checks to decide victory/defeat.

Because **entities are generic** and **CombatEngine is ignorant of specific objectives**, these use-cases primarily require:

1. New tags and stage-setup.
2. New objective handlers inside `CombatObjectives.gd`.
3. Optional AI tweaks inside `EnemyActionChooser.gd`.

---

## 8. Configuration & Constants

Key config/control points:

- `CombatConstants.gd`
  - Objective names:
    - `OBJECTIVE_DEFEAT_ENEMIES`
    - `OBJECTIVE_PROTECT_SHRINE`
    - (future) `OBJECTIVE_ESCORT_ENTITY`, `OBJECTIVE_DESTROY_TARGET`, etc.
  - Refusal and fear thresholds.
  - Misc combat tuning enums/keys.

- `GameBalance_HeroCombat.gd`
  - Damage/fear/morale tuning:
    - Fear per round.
    - Morale decay rate.
    - KO fear impact.
    - Shrine drain parameters (if not fully realm-specific).

- Realm-specific configs (see `realms_mvp.md`)
  - `fear_delta` per stage.
  - Reward tuning.
  - Per-realm flavor hooks.

All modules should read configuration via these centralized files, not hard-coded numbers.

---

## 9. Testing & Debug Hooks

### 9.1 Realms + combat tests

Via `DebugConsole`:

```text
/run_tests realms
```

This runs:

1. **Realm generation tests**
   - Seed stability.
   - Stage objective type consistency.
   - Encounter seed + modifiers matching.

2. **Realm reward tests**
   - Reward bounds & monotonicity across tiers.

3. **Generic entity tests**
   - `TestCombatGenericEntities.gd` covers:
     - `find_alive_shrine` behavior.
     - End-conditions for defeat vs. protect-shrine.
     - Emotion stability and absence of crashes with structure entities.

### 9.2 How to add new tests

When adding new objective types or entity roles:

1. Add / extend a test script in the `core/tests/combat/` folder.
2. Make sure it exposes a `run_all()` function.
3. Wire it into `DebugConsole.gd` under `/run_tests realms` (or another test command).
4. Prefer asserting on **snapshots** (from `CombatSnapshotBuilder`) rather than internal state details.

---

## 10. Practical Guidance for New Work

### 10.1 Adding a new unit type

1. Decide on tags (e.g. `["ally", "hero", "summon"]`).
2. Extend the builder that creates raw entities (hero summoning, realm encounter builder).
3. Ensure `CombatEntities.normalize_*` preserves or assigns tags.
4. Add any custom behavior:
   - In `ActionResolver` if it’s a new action type.
   - In `EnemyActionChooser` if it changes targeting.

### 10.2 Adding a new objective

1. Define a new constant in `CombatConstants.gd`.
2. Update realm/stage generation to use that objective type where appropriate.
3. Implement the logic in `CombatObjectives.gd`:
   - Extend `build_objective_context` if needed.
   - Extend `check_end` to handle the new type.
4. Add tests in `TestCombatGenericEntities.gd` (or a new test script).
5. Update docs:
   - `realms_mvp.md`
   - `combat_rounds_mvp.md` (if round flow changes)
   - Any new objective-specific addendum.

### 10.3 When to touch CombatEngine

You **should not** need to edit CombatEngine for:

- New objectives.
- New entity roles (shrines, carts, gates, wards, summons).
- AI tuning (as long as it fits the same round/action model).

You **may** need to edit CombatEngine when:

- The overall *structure* of a combat round changes.
- We introduce new phases (e.g. deployment phase, reaction step).
- We support player-driven, non-automatic combat selection (UI turn picks etc.).

---

## 11. Summary

- CombatEngine is now a **lean orchestrator**.
- Entities are **generic**, tagged, and normalized via `CombatEntities`.
- Objectives drive end-conditions via `CombatObjectives`.
- Fear/morale and shrine drain are owned by `CombatEmotionSystem`.
- Enemy behavior is centralized in `EnemyActionChooser`.
- Snapshots for logs/UI are built by `CombatSnapshotBuilder`.
- Tests (`/run_tests realms`) confirm:
  - Realm generation stability.
  - Reward correctness.
  - Generic entity behavior for shrines and other structures.

If you keep module boundaries clean and push domain rules into the right helper, this architecture should scale smoothly as the game adds more combat stages, objectives, and entity types.