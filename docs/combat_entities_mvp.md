# Combat Entities MVP Specification

## 1. Purpose & Scope

This document defines the **generic combat entity model** for the Echoes of the Sankofa MVP and the **module split** around `CombatEngine`. It is the canonical reference for how all units and objectives appear inside combat:

- Heroes
- Enemies
- Structures (shrines, wards, gates, etc.)
- NPC allies and escort targets
- Summons
- Multi-objective stage elements

This document is **design-only**. It does **not** describe the final code layout, only the target model and responsibilities that future refactors must follow.

Goals:

1. Make it easy to plug new stage types / unit types into combat without rewriting the engine.
2. Turn `CombatEngine` into an **orchestrator**, not a god-script.
3. Support **multi-objective stages** (sequential or branching objectives) from day one.
4. Preserve all current behavior, seeds, variables, and results for the existing MVP fights (combat_trial, purify_shrine).


## 2. Canon Alignment

This model must stay aligned with the core canon:

- **Legacy Never Dies – GDD**
  - §3 Core Loop: Summon → Guide → Venture → Resolve → Reflect → Legacy.
  - §4 Core Mechanics: deterministic resolution, readable outcomes, refusal and fear as first-class systems.
  - §5 Heroes: Echoes are defined by personality + traits, stats are an expression of that.
  - §6 World / Realm Structure: realms provide structured objectives (trials, shrines, escorts, defenses, etc.).
  - §9 Combat, AI & Simulation: combat is deterministic, fair, and interpretable; the “Echo Behavior Matrix” governs how Echoes respond.

- **Addenda / MVP Docs**
  - `realms_mvp`: stages define objective types and parameters.
  - `combat_rounds_mvp`: step-based combat rounds, initiative, action economy.
  - `emotion_mvp`: morale, fear, and emotional deltas emitted from combat.
  - `shrine_combat`: shrine as an allied objective and special win / loss conditions.

The entity model and module split below are **implementation details** that must still express these narrative and systemic rules. If there is a conflict, canon wins and this doc must be updated.


## 3. Generic Combat Entity Schema

All combat participants (heroes, enemies, shrines, escort carts, gates, NPC allies, summons, etc.) are represented inside combat as a **generic entity dictionary** with a stable shape.

### 3.1 Entity DTO

Canonical shape of a combat entity in GDScript terms:

```gdscript
var entity := {
    "id": 0,                    # int: unique within this combat
    "name": "",                 # String: display name
    "stats": {},                # Dictionary: numeric stats (hp, atk, morale, fear, etc.)
    "tags": [],                 # Array[String]: roles and behaviors
    "archetype": "",            # String (optional): hero archetype / AI flavor
    "status": "",               # String: 'idle', 'downed', 'retreated', etc.
    "ai_profile": "",           # String (optional): which AI profile to use
    "objective_id": -1,         # int (optional): link to objective this entity belongs to
    "meta": {},                 # Dictionary: free-form metadata for future use
}
```

#### Field Definitions

- **id: int**
  - Unique identifier within the current combat.
  - Stable for the full duration of the fight (determinism requirement).
  - Used for snapshots, log output, and post-combat emotion/legacy mapping.

- **name: String**
  - Display name of the unit (“Korkor Kyerematen”, “Ancestral Shrine”, “Bone Warden”, etc.).
  - May be a generic label for dummy enemies (“Training Dummy”, “Test Cart”).

- **stats: Dictionary**
  - Numeric fields required for combat and emotion logic.
  - At minimum (MVP):

    ```gdscript
    stats = {
        "hp": int,
        "max_hp": int,
        "atk": int,
        "def": int,
        "agi": int,
        "morale": int,  # 0–100
        "fear": int,    # 0–100
        # optional extras, e.g.:
        # "range": int,
        # "armor": int,
    }
    ```

  - This shape is compatible with:
    - Hero stats from the summoning & archetype system.
    - Enemy templates defined in balance configs.
    - Structure HP (shrines, gates) via `hp`/`max_hp` only.

- **tags: Array[String]**
  - The **core of the generic entity model**.
  - Describes identity, allegiance, physicality, and objective relationships.
  - See section 4 for full tag vocabulary.

- **archetype: String (optional)**
  - Hero archetype / personality class (e.g., `"valiant"`, `"devout"`, `"empathic"`).
  - Drives AI nuance and narrative flavor, not raw balance.
  - Can be empty for non-hero entities.

- **status: String**
  - High-level state of the entity within combat, e.g.:
    - `"active"` – can act and be targeted normally.
    - `"downed"` – HP 0, cannot act, but body remains for morale/fear calculations.
    - `"retreated"` – out of combat, cannot be targeted.
    - `"destroyed"` – for structures that are fully removed.
  - `CombatEngine` and submodules interpret this in a deterministic, rule-based way.

- **ai_profile: String (optional)**
  - Identifies which AI behavior to use for **EnemyActionChooser**.
  - MVP examples:
    - `""` (empty) – default behavior.
    - `"dummy"` – trivial placeholder behavior.
    - `"boss:discipline"` – special triage rules later.
  - Does not change the entity schema; just a hint to the AI module.

- **objective_id: int (optional)**
  - Link from this entity to a **logical objective** in the current stage.
  - `-1` or missing means the entity is not tied to a specific named objective.
  - Used when stages have **multiple objectives** (see section 5).

- **meta: Dictionary**
  - Free-form metadata for realm / UI / analytics.
  - Examples:
    - `"realm_id": "forest_01"`
    - `"spawn_wave": 2`
    - `"visual_variant": "golden"`


## 4. Tag System

Tags are short strings which, together, describe the combat role of an entity. We rely on tags instead of hardcoded booleans like `is_shrine` so new types can be introduced without changing the engine.

Tags are:

- **Additive**: an entity can have many tags.
- **Composable**: higher-level rules look for combinations (e.g., `"ally"` + `"objective"`).
- **Extensible**: new tags can be added later without schema changes.

### 4.1 Core Identity Tags

These describe allegiance and fundamental type:

- `"ally"` – controlled or allied to the player.
- `"enemy"` – hostile unit.
- `"hero"` – Echo hero (summoned from flame).
- `"npc"` – non-hero ally (e.g., villagers, escort targets).
- `"summon"` – temporary or conjured ally/enemy.

Examples:

- Standard hero:
  - `["ally", "hero"]`
- Enemy footsoldier:
  - `["enemy"]`
- Summoned spirit:
  - `["ally", "summon"]` or `["enemy", "summon"]`

### 4.2 Structure & Objective Tags

These describe physical structures and their role as objectives.

**Structure tags:**

- `"structure"` – non-mobile, HP-bearing object (shrines, gates, wards, carts).
- `"structure:defense"` – structure whose primary role is to be defended.
- `"structure:obstacle"` – structure whose primary role is to be destroyed.

**Objective tags:**

- `"objective"` – this entity is directly involved in win/loss conditions.
- `"objective:shrine"` – purify / defend shrine objective.
- `"objective:escort"` – escort target objective.
- `"objective:gate"` – gate or barrier that must be destroyed.
- `"objective:ward"` – protective ward (defense objective).
- `"objective:boss"` – boss unit tied to an objective.

These tags are *interpretation hints* for:

- `CombatObjectives` – for end-condition logic.
- `EnemyActionChooser` – for target priority (e.g., enemies attacking the shrine).
- Realm logic – for mapping stage objectives to combat entities.

### 4.3 Multi-Objective & Stage Tags (Optional / Future)

We can optionally introduce tags that reference multi-objective flows:

- `"objective:primary"` – first objective in a chain.
- `"objective:secondary"` – follow-up or support objective.
- `"objective:chain:1"` etc. – used only if tag-based chaining is helpful.

However, for MVP we prefer to use **`objective_id` + objective definitions** (see section 5) rather than encoding entire chains in tags.

### 4.4 Worked Examples

**Shrine (Purify Shrine objective):**

```gdscript
tags = ["ally", "structure", "structure:defense", "objective", "objective:shrine"]
```

**Escort cart / NPC:**

```gdscript
tags = ["ally", "npc", "escort_target", "objective", "objective:escort"]
```

**Destructible enemy gate:**

```gdscript
tags = ["enemy", "structure", "structure:obstacle", "objective", "objective:gate"]
```

**Boss enemy tied to an objective:**

```gdscript
tags = ["enemy", "boss", "objective", "objective:boss"]
```


## 5. Stage Objectives & Multi-Objective Support

Realms can define stages that have **one or multiple objectives**. The combat layer must support:

- Single-objective stages (e.g., pure combat trial).
- Multi-objective stages, where objectives are **chained** or **parallel**.
  - Example: Defend the shrine → then escort an NPC → then destroy the gate.

This section describes how objectives are represented conceptually and how they connect to combat entities.

### 5.1 Objective Definition (Conceptual)

At the realm/stage level (outside combat), we assume an objective definition structure like:

```gdscript
var objective_def := {
    "id": 1,                      # int, unique per stage
    "type": "purify_shrine",      # String, e.g. 'defeat', 'purify_shrine', 'escort', 'destroy'
    "params": {},                 # Dict, type-specific parameters
    "next_objective_ids": [],     # Array[int], ids to activate when this completes
}
```

Key ideas:

- **id**: primary key for linking entities (`objective_id` on entities points to this).
- **type**: drives `CombatObjectives` behavior (`defeat`, `purify_shrine`, `escort`, `defend`, `destroy`, etc.).
- **params**:
  - May include time limits, wave counts, HP thresholds, required entities, etc.
- **next_objective_ids**:
  - Enables **chaining**:
    - Linear: `1 → 2 → 3`
    - Branching: `1 → [2, 3]` (parallel or staged activation)

The exact storage and loading is Realm System’s responsibility, but this shape is what `CombatObjectives` expects at runtime.

### 5.2 Linking Entities to Objectives

`objective_id` on entities links them to an objective:

- Shrine entity:
  - `objective_id = 1` with tags `["ally", "structure", "objective", "objective:shrine"]`.
- Escort NPC:
  - `objective_id = 2` with tags `["ally", "npc", "objective", "objective:escort"]`.
- Enemy gate:
  - `objective_id = 3` with tags `["enemy", "structure", "objective", "objective:gate"]`.

This allows `CombatObjectives` to:

- Quickly find all entities participating in a given objective.
- Evaluate objective-specific conditions:
  - “Is all gate HP <= 0?”
  - “Is escort target still alive at extraction?”
  - “Is shrine still standing after N waves?”

### 5.3 Multi-Objective Flow in Combat

At runtime, `CombatObjectives` maintains an **objective state**:

```gdscript
var objective_state := {
    "active_objective_ids": [],   # currently active objectives
    "completed_objective_ids": [],# objectives that have been completed
    "failed_objective_ids": [],   # failed objectives
}
```

High-level flow:

1. **Stage start**
   - Realm passes:
     - `objective_defs`: list of objective definitions.
     - `initial_objective_ids`: first objective(s) to activate.
   - `objective_state.active_objective_ids` is set from `initial_objective_ids`.

2. **During combat**
   - After each round, `CombatEngine` calls:
     - `CombatObjectives.check_end(state, objective_state, objective_defs, round_limit, hero_bal)`
   - `check_end`:
     - Evaluates each active objective:
       - If type is `defeat`: all enemies with `objective` tag and/or `enemy` tag are down.
       - If type is `purify_shrine`: shrine survives; wave rules, etc.
       - If type is `escort`: escort entity remains alive and reaches goal conditions.
       - If type is `destroy`: relevant structure entities reach 0 HP, etc.
     - Marks objectives as **completed** or **failed** as needed.
     - For each completed objective, activates `next_objective_ids`.

3. **End conditions**
   - Stage ends when any of the following holds:
     - A **failure** condition is met for any critical objective.
     - The objective graph has no more active objectives (chain is fully resolved).
     - A global limit is hit (round limit / time limit).
   - `CombatObjectives` returns a status (`ongoing`, `victory`, `defeat`) plus context.

This design allows **multi-objective stages** without changing entity shape or `CombatEngine` logic. All that changes is the content of `objective_defs` and how stages are authored.

### 5.4 Responsibilities Split (Realms vs Combat)

- **Realm / Stage authors** define:
  - Objectives (`id`, `type`, `params`, `next_objective_ids`).
  - Which entities belong to which objective (`objective_id`).
  - Any realm-specific parameters (wave counts, spawn triggers, etc.)

- **Combat layer** (`CombatEngine` + `CombatObjectives`) is responsible for:
  - Evaluating objective conditions based on entities and stats.
  - Advancing objective chains.
  - Emitting a clear result (victory/defeat + reasons) in the snapshot.


## 6. Module Responsibilities

The entity model and multi-objective system are supported by a set of combat modules. This section defines the **target split**. Actual refactor work happens in later subtasks.

### 6.1 CombatEngine.gd – Orchestrator

**Responsibilities:**

- Owns the main loop:
  - `start_battle(state, allies, enemies, stage_context)`
  - `step_round(state)`
- Delegates to other modules:
  - `CombatEntities` for normalization & tag helpers.
  - `CombatEmotionSystem` for morale & fear.
  - `CombatObjectives` for end conditions / objective chains.
  - `EnemyActionChooser` for enemy AI.
  - `CombatSnapshotBuilder` for snapshots.
- Maintains deterministic order and consistent seeding.

**Does not**:

- Construct entities from save/DB (delegated).
- Implement emotion rules.
- Implement objective rules.
- Implement enemy AI.
- Construct snapshots directly.

### 6.2 CombatEntities.gd – Entity Construction & Helpers

**Responsibilities:**

- Normalize incoming entities:

  ```gdscript
  CombatEntities.normalize_allies(allies_raw, HeroBal)
  CombatEntities.normalize_enemies(enemies_raw, HeroBal)
  ```

- Ensure consistent stats and types:
  - `_ensure_stat_int` equivalent for all numeric fields.
- Tag helpers:

  ```gdscript
  CombatEntities.has_tag(entity, "objective")
  CombatEntities.add_tag(entity, "structure")
  CombatEntities.ensure_tags(entity, ["ally", "hero"])
  CombatEntities.is_shrine(entity)      # via tags
  CombatEntities.is_structure(entity)
  CombatEntities.is_objective(entity)
  CombatEntities.find_first_with_tag(group, "objective:shrine")
  ```

- Optional:
  - Hero hydration / mapping from save data to combat entities (if not handled earlier).

### 6.3 CombatEmotionSystem.gd – Morale & Fear

**Responsibilities:**

- Capture baseline emotional state per entity.
- Apply per-round ticks:
  - Morale decay or restoration.
  - Fear accumulation / reduction.
  - Shrine-related drain if applicable (via tags + configs).
- Apply KO fear:
  - Allies reacting to ally downs.
- Build final emotion deltas for post-combat systems.

**Example API:**

```gdscript
CombatEmotionSystem.capture_baseline(state)
CombatEmotionSystem.apply_round_tick(state, HeroBal, ctx)
CombatEmotionSystem.apply_ally_ko_fear(state, HeroBal)
CombatEmotionSystem.build_emotion_result(state)
```

### 6.4 CombatObjectives.gd – End Conditions & Objective Chains

**Responsibilities:**

- Given:
  - `state` (entities, stats, round number, etc.)
  - `objective_state` (active/completed/failed objective IDs)
  - `objective_defs` (type, params, next ids)
- Evaluates each active objective according to its type:
  - `defeat`
  - `purify_shrine`
  - `escort`
  - `defend_structure`
  - `destroy_target`
  - `multi_objective` (higher-order objective if needed)
- Advances objective chains via `next_objective_ids`.
- Computes global battle status:

  ```gdscript
  var result = CombatObjectives.check_end(state, objective_state, objective_defs, round_limit, hero_bal)
  # returns something like:
  # { "status": "ongoing" | "victory" | "defeat", "reason": "shrine_destroyed", ... }
  ```

### 6.5 EnemyActionChooser.gd – Enemy AI

**Responsibilities:**

- Encapsulate all enemy targeting and action choice.

  ```gdscript
  EnemyActionChooser.choose_enemy_action(state, entity, ctx)
  ```

- Support:
  - Default enemy behavior.
  - Shrine / objective-aware target selection:
    - Prioritize entities with `["objective"]` or `["structure", "objective:shrine"]` tags when required.
  - Future AI tweaks via `ai_profile`.

### 6.6 CombatSnapshotBuilder.gd – Snapshots & Logs


**Responsibilities:**

- Build per-round snapshots consumed by:
  - Debug console.
  - Combat logs / UI.
  - Post-combat analytics.
- Build final results:
  - `final_state`
  - Objective result summary.
  - Emotion deltas.
- Handle name maps and HP pairs:

  ```gdscript
  CombatSnapshotBuilder.build_snapshot(state, actions_this_round, ticks, end_result)
  CombatSnapshotBuilder.build_name_map(state)
  ```

#### 6.7 Snapshot Builder Integration Notes (Subtask G Final)

The snapshot builder now owns all snapshot construction previously spread
across CombatEngine. This includes:
- Round-by-round snapshots (initiative, actions, ticks, post-round state)
- Final snapshot with emotion results and objective outcome
- Name map construction (hero and entity display names)

CombatEngine no longer builds snapshots directly. It calls only:

```
var snap = CombatSnapshotBuilder.build_snapshot(state, actions, ticks, ctx)
```


## 7. Example Scenarios

### 7.1 Purify Shrine (Single Objective)

- Stage defines:

  ```gdscript
  objectives = [
      { "id": 1, "type": "purify_shrine", "params": { /* shrine rules */ }, "next_objective_ids": [] }
  ]
  initial_objective_ids = [1]
  ```

- Shrine entity:

  ```gdscript
  {
      "id": 10,
      "name": "Ancestral Shrine",
      "stats": { "hp": 100, "max_hp": 100, ... },
      "tags": ["ally", "structure", "structure:defense", "objective", "objective:shrine"],
      "objective_id": 1,
      ...
  }
  ```

- `CombatObjectives.check_end` checks:
  - Shrine HP > 0 after N waves / when conditions met ⇒ victory.
  - Shrine HP <= 0 ⇒ defeat.

### 7.2 Multi-Objective Stage: Defend Shrine → Escort NPC → Destroy Gate

1. **Stage definitions:**

   ```gdscript
   objectives = [
       { "id": 1, "type": "defend_structure", "params": { "duration_rounds": 5 }, "next_objective_ids": [2] },
       { "id": 2, "type": "escort", "params": { "target_entity_id": 20 }, "next_objective_ids": [3] },
       { "id": 3, "type": "destroy_target", "params": { "tag": "objective:gate" }, "next_objective_ids": [] },
   ]
   initial_objective_ids = [1]
   ```

2. **Entities:**

   - Shrine:
     - `tags = ["ally", "structure", "structure:defense", "objective", "objective:shrine"]`
     - `objective_id = 1`
   - Escort NPC:
     - `tags = ["ally", "npc", "objective", "objective:escort"]`
     - `objective_id = 2`
   - Enemy gate:
     - `tags = ["enemy", "structure", "structure:obstacle", "objective", "objective:gate"]`
     - `objective_id = 3`

3. **Flow:**

   - Start: `active_objective_ids = [1]`
   - After 5 rounds with shrine still alive:
     - Objective 1 completes.
     - `active_objective_ids = [2]`
   - Escort NPC reaches goal alive:
     - Objective 2 completes.
     - `active_objective_ids = [3]`
   - Gate destroyed:
     - Objective 3 completes.
     - No more `next_objective_ids` ⇒ stage victory.

Throughout this, `CombatEngine` loops are unchanged. Only `CombatObjectives` and the objective definitions drive the chaining.


## 8. Integration Guidelines

When adding new combat content or new stage types, follow these rules:

1. **Always use the generic entity schema.**
   - Fill `id`, `name`, `stats`, `tags`, and `status` at minimum.
   - Use `objective_id` for any entity that participates in an objective.

2. **Express roles with tags, not booleans.**
   - Prefer `["ally", "structure", "objective", "objective:shrine"]` over `is_shrine = true`.
   - Let `CombatEntities.is_shrine` be the only helper that knows the shrine tag combination.

3. **Model objectives explicitly.**
   - Each stage objective gets an `id`, `type`, `params`, and `next_objective_ids`.
   - Multi-objective stages are just graphs of these objectives.

4. **Keep CombatEngine thin.**
   - New rules should go into:
     - `CombatEntities` (if it’s about the entity shape).
     - `CombatEmotionSystem` (if it’s morale/fear).
     - `CombatObjectives` (if it’s win/loss logic).
     - `EnemyActionChooser` (if it’s AI).
     - `CombatSnapshotBuilder` (if it’s logging/snapshot structure).

5. **Respect determinism.**
   - Entity lists, IDs, and order must be stable.
   - Any randomness must be derived from the campaign/realm seed and logged consistently.

If a new feature requires changing this model, update this document first, then refactor the modules to match.


## 9. Glossary

**Combat Entity**  
A dictionary-based representation of any unit or structure that participates in combat.

**Tag**  
A short string that describes a role, attribute, or combat function of an entity. Tags are composable and additive.

**Objective**  
A stage-defined condition that determines combat progress, victory, or failure.

**Objective Chain**  
A sequence or graph of objectives where completing one activates the next.

**Objective ID**  
An integer linking a combat entity to a stage objective.

**CombatEngine**  
The orchestrator of the battle loop. Delegates to specialized modules.

**CombatEntities**  
Module that constructs, normalizes, and manages entity data and tag helpers.

**CombatEmotionSystem**  
Module responsible for morale, fear, and emotional delta calculations.

**CombatObjectives**  
Module that evaluates end conditions and manages objective chaining.

**EnemyActionChooser**  
AI module that determines enemy behavior and target selection.

**CombatSnapshotBuilder**  
Module that constructs per-round and final results for logs, UI, and analytics.

**Structure**  
A combat entity with “structure” tags. Typically stationary and HP-based (shrines, gates, wards).

**Multi-Objective Stage**  
A stage with more than one objective, possibly sequential or branching.

**DTO (Data Transfer Object)**  
A stable schema for passing structured data through systems without exposing implementation details.

---

# 10. Integration Notes (Final A–H Implementation)

This document is now fully aligned with the final engine architecture implemented across Subtasks A through H.

## 10.1 Entity Model Fully Adopted

All combat entities—heroes, enemies, shrines, NPCs, escort targets, summons, and structures—use the canonical DTO defined in section 3:

- Stable ids  
- Stats dictionary (hp/max_hp/atk/def/agi/morale/fear…)  
- Tag-driven identity  
- Optional archetype, ai_profile, objective_id, meta  

All shrine, escort, defense, and multi-objective patterns now use tags instead of booleans.

## 10.2 Tag System Active Throughout Engine

Tags are now:

- Required on all entities  
- Used by:  
  - CombatEntities  
  - EnemyActionChooser  
  - CombatObjectives  
  - CombatSnapshotBuilder  
  - Realm stage builders  
- Source of truth for all role logic  

Standardized tag sets are enforced during normalization.

## 10.3 Entity Normalization Extracted to CombatEntities

CombatEntities.gd now owns:

- normalize_allies  
- normalize_enemies  
- ensure_stats  
- hp read/write pipeline  
- tag helpers  
- shrine/entity identification  
- fallback stat hydration  

CombatEngine no longer manipulates entity shapes.

## 10.4 Shrine is Now a Standard Structure Objective

Shrines are represented entirely through tags and generic stats:

```
["ally", "structure", "structure:defense", "objective", "objective:shrine"]
```

CombatEngine no longer has shrine-specific code paths.
All shrine wave drain and Purify logic is inside CombatObjectives + EmotionSystem.

## 10.5 Multi-Objective Support in Place

CombatObjectives supports:

- defeat  
- purify_shrine  
- escort (future)  
- defend_structure (future)  
- destroy_target (future)  
- chained objectives via next_objective_ids  

Entities bind to objectives via `objective_id`.

## 10.6 Purifier System Documented & Integrated

Entity-level fields + tags support Purifier selection:

- Archetype (devout bonus)  
- Stats (faith, wisdom)  
- Morale (tie-breaker)  

Purifier is now an attribute of the battle state, not the entity model.

## 10.7 Emotion System Separation

CombatEmotionSystem owns all emotional state:

- Fear gain from hits/focus/KO  
- Fear-first refusal  
- Morale decay and tier rules  
- Shrine wave morale drain  

No emotional logic remains in CombatEngine.

## 10.8 Snapshot Builder Integration Complete

CombatSnapshotBuilder now constructs:

- Round snapshots  
- Final snapshot  
- Name maps  
- All HP/Guard fields  
- Canonical log shape  

Entity DTO defined in this doc matches the snapshot shape required for UI.

## 10.9 Determinism Assurance

The entity model is deterministic with respect to:

- ID assignment  
- Normalization order  
- Snapshot order  
- Objective evaluation  
- Purifier logic  
- Shrine logic  

## 10.10 Ready for Future Extensions

This document now accurately reflects:

- Multi-objective stages  
- Summons and NPCs  
- Structure objectives  
- Expanded AI profiles  
- Realm-config-driven objective parameters  
# Combat Engine Refactor – Orchestrator & Module Architecture

## 1. Purpose

This document explains how the **CombatEngine** and its related modules work after the refactor performed in the story:

> _“As the Keeper I want CombatEngine to support generic combat entities (structures, NPCs, objectives, summons, escorts)”_

It is written so that a **new developer or AI assistant** can understand and extend the system **without reading the entire codebase first**.

This doc focuses on:

- How the combat loop works (round-by-round).
- How the **orchestrator-style** `CombatEngine` delegates to other modules.
- How the engine uses the **generic combat entity model** and **objective system** described in `combat_entities_mvp.md`.
- Where to plug in new:
  - entity types (shrines, gates, wards, escorts, summons, NPC allies, bosses, etc.)
  - objective types (defeat, purify_shrine, escort, defend_structure, destroy_target, multi-objective flows)
  - AI behaviors
  - logging / UX / analytics hooks

If there is any conflict between this document and the canonical design docs (`combat_entities_mvp.md`, `combat_rounds_mvp.md`, `realms_mvp.md`, `emotion_mvp.md`, `shrine_combat`), **canon wins** and this doc should be updated accordingly.


## 2. High-Level Design

### 2.1 Orchestrator Philosophy

The refactored `CombatEngine` is a **thin orchestrator**:

- It owns the **battle loop** (start + per-round stepping).
- It owns the **combat state container**.
- It delegates **all domain rules** to dedicated modules:
  - Entity shape and tags → `CombatEntities`
  - Morale & fear → `CombatEmotionSystem`
  - Objectives & end conditions → `CombatObjectives`
  - Enemy AI → `EnemyActionChooser`
  - Snapshots & logs → `CombatSnapshotBuilder`
  - Action resolution (damage, KO, etc.) → `ActionResolver` (existing module)

`CombatEngine` itself **does not** implement:
- Shrine special rules.
- AI targeting rules.
- Emotion logic.
- Objective-specific logic.
- The details of log / snapshot formatting.

Instead, it wires these modules together in a deterministic way.

### 2.2 Module Overview

The core modules involved in combat after the refactor are:

- `core/combat/CombatEngine.gd`  
  Orchestrator; owns the main battle loop and combat state.

- `core/combat/CombatEntities.gd`  
  Entity construction, normalization, type-safe stat accessors, tag helpers, shrine/structure/objective helpers.

- `core/combat/CombatEmotionSystem.gd`  
  Morale & fear rules, baselines, per-round ticks, KO fear, shrine drain.

- `core/combat/CombatObjectives.gd`  
  End-condition logic and objective state machine (defeat, purify_shrine, and future escort/defend/destroy/multi-objective flows).

- `core/combat/EnemyActionChooser.gd`  
  Enemy AI; picks actions for enemy entities based on tags, objectives, and configs.

- `core/combat/CombatSnapshotBuilder.gd`  
  Snapshot + log construction (per-round and final).

- `core/combat/ActionResolver.gd` (pre-existing)  
  Low-level action resolution: applies damage, KO, buffs, guards, etc.

Additional systems that integrate with the combat engine:

- `RealmService` / `RealmStageBuilder` – creates realm stages with **objective_definitions** and **entity lists**.
- `EmotionService` – receives final emotion deltas.
- `DebugConsole` – drives test and debug runs via commands (e.g. `/run_tests realms`).


## 3. Data Model Overview

This section summarizes the main data structures `CombatEngine` uses. Full details of the entity model live in `combat_entities_mvp.md`.

### 3.1 Combat Entity DTO (Recap)

All participants in combat (heroes, enemies, shrines, escort carts, gates, wards, NPC allies, summons, bosses, etc.) share a **generic entity schema**:

```gdscript
var entity := {
    "id": 0,                    # int: unique within this combat
    "name": "",                 # String: display name
    "stats": {},                # Dictionary: numeric stats (hp, atk, morale, fear, etc.)
    "tags": [],                 # Array[String]: roles and behaviors
    "archetype": "",            # String (optional): hero archetype / personality
    "status": "",               # String: 'active', 'downed', 'retreated', 'destroyed', etc.
    "ai_profile": "",           # String (optional): which AI profile to use
    "objective_id": -1,         # int (optional): link to stage objective
    "meta": {},                 # Dictionary: free-form metadata
}
```

`CombatEngine` never relies on hard-coded flags like `is_shrine`. It uses **tags** and helper functions in `CombatEntities` instead.

### 3.2 Tag System (Recap)

Tags describe an entity’s combat role and objective relationships. Examples:

- Identity & allegiance:
  - `"ally"`, `"enemy"`, `"hero"`, `"npc"`, `"summon"`
- Structure & objective role:
  - `"structure"`, `"structure:defense"`, `"structure:obstacle"`
  - `"objective"`, `"objective:shrine"`, `"objective:escort"`, `"objective:gate"`, `"objective:boss"`

Shrine example:

```gdscript
tags = ["ally", "structure", "structure:defense", "objective", "objective:shrine"]
```

Escort cart example:

```gdscript
tags = ["ally", "npc", "escort_target", "objective", "objective:escort"]
```

Destructible gate example:

```gdscript
tags = ["enemy", "structure", "structure:obstacle", "objective", "objective:gate"]
```

All shrine, escort, defense, gate, and multi-objective behaviors are driven by **tags + objective definitions**, not bespoke code inside `CombatEngine`.


### 3.3 Objective Definition & State

Stages define **one or more objectives** using the structure outlined in `combat_entities_mvp.md`:

```gdscript
var objective_def := {
    "id": 1,                      # int, unique per stage
    "type": "purify_shrine",      # 'defeat', 'purify_shrine', 'escort', 'destroy', etc.
    "params": {},                 # Dict, type-specific parameters
    "next_objective_ids": [],     # Array[int], ids to activate when this completes
}
```

At runtime, `CombatObjectives` maintains objective state:

```gdscript
var objective_state := {
    "active_objective_ids": [],
    "completed_objective_ids": [],
    "failed_objective_ids": [],
}
```

Entities participating in objectives set `objective_id` to match one of these objective definitions.

### 3.4 Combat State

`CombatEngine` owns a **combat state** dictionary. The exact keys may evolve, but it conceptually contains:

```gdscript
var state := {
    "round": 0,
    "rng": RandomNumberGenerator,       # seeded from realm / campaign
    "allies": [],                       # Array[entity]
    "enemies": [],                      # Array[entity]
    "actions_this_round": [],           # for snapshot/logs
    "ticks_this_round": [],             # fear/morale/shrine/etc ticks
    "objective_state": {},              # see above
    "objective_defs": [],               # definitions from realm
    "context": {},                      # stage-specific context (e.g., shrine params)
    "emotion_baseline": {},             # captured by CombatEmotionSystem
    "emotion_result": {},               # computed at the end
    "ended": false,
    "result": {},                       # final victory/defeat payload
}
```

`CombatEngine` is responsible for **initializing** this state and passing it to the different modules each round.


## 4. CombatEngine Lifecycle

### 4.1 Entry Points

The primary public entry points into `CombatEngine` are:

```gdscript
func start_battle(allies_raw, enemies_raw, stage_context) -> Dictionary
func step_round(state: Dictionary) -> Dictionary
```

Depending on the caller, there may also be convenience wrappers (e.g. run-to-completion for tests), but these are the two core pieces to understand.

#### 4.1.1 start_battle

`start_battle` is called when a realm stage initiates combat. It is responsible for:

1. **Constructing/normalizing entities**:
   - Calls `CombatEntities.normalize_allies(allies_raw, HeroBal)`.
   - Calls `CombatEntities.normalize_enemies(enemies_raw, HeroBal)`.
   - Guarantees the entity DTO shape and required tags/stats.

2. **Seeding RNG + state**:
   - Seeds `state.rng` from realm/campaign seed for determinism.
   - Sets `state.round = 0`.
   - Sets `state.allies`, `state.enemies`.

3. **Objective/wave context**:
   - Reads `stage_context`, including:
     - `objective_defs`
     - `initial_objective_ids`
     - shrine/wave parameters for shrine stages.
   - Initializes `state.objective_state` (`active_objective_ids`, etc.).

4. **Emotion baseline**:
   - Calls `CombatEmotionSystem.capture_baseline(state)` to record initial morale/fear and any other emotional baselines.

5. **Initial snapshot (optional)**:
   - May build an initial snapshot (pre-round 1) via `CombatSnapshotBuilder` for logs/UI.

The return value is the initialized `state` dictionary, ready for `step_round`.


#### 4.1.2 step_round

`step_round` performs exactly one round of combat and returns an updated `state` (plus a snapshot in `state.result` or via an explicit return payload).

Core responsibilities:

1. **Increment round counter**.
2. **Build round context** (for logs and submodules).
3. **Compute initiative**.
4. **Iterate over actors in initiative order**:
   - Skip downed/destroyed/retreated entities.
   - Determine action (ally vs enemy).
   - Call `ActionResolver` to apply results.
   - Record actions taken.
   - Apply per-hit emotion effects (fear on hit, etc.).
5. **Apply KO fear** via `CombatEmotionSystem.apply_ally_ko_fear`.
6. **Apply round tick** via `CombatEmotionSystem.apply_round_tick`.
7. **Evaluate objectives** via `CombatObjectives.check_end`:
   - Update `state.objective_state`.
   - Resolve victory/defeat/ongoing.
8. **Build snapshot** via `CombatSnapshotBuilder.build_snapshot`.
9. **If battle ended**, build final result and emotion payload (`CombatEmotionSystem.build_emotion_result`).

The rest of this section details these steps.


### 4.2 Round Flow in Detail

#### 4.2.1 Initiative

`CombatEngine` builds the initiative order using the stats on each entity (often `agi`, plus RNG for ties) and the stable entity IDs.

Typical pattern:

```gdscript
var turn_order := _build_initiative_order(state)
for actor_id in turn_order:
    _take_turn(state, actor_id)
```

The exact initiative computation is defined by `combat_rounds_mvp.md` and implemented in the engine; the refactor ensures it is **deterministic** and unchanged behavior-wise.

#### 4.2.2 Taking a Turn

For each entity in initiative:

1. **Lookup entity** from state (ally or enemy list).
2. **Skip** if:
   - `status` is `"downed"`, `"retreated"`, `"destroyed"`, etc.
3. **Build action context** (used by AI, emotion, and snapshot modules):
   - Includes entity ID, tags, objective links, shrine info, etc.
4. **Determine action**:
   - **Allies**:
     - MVP: allies use a simple “auto-combat” behavior (attack enemies in range, etc.), driven by existing code.
     - Future: will be driven by a higher-level command/behavior system.
   - **Enemies**:
     - Call `EnemyActionChooser.choose_enemy_action(state, entity, ctx)`.
     - This may prioritize entities with `"objective"` or `"structure:defense"` tags (e.g. shrines), or default to lowest HP targets.
5. **Refusal / fear checks**:
   - If a hero is in a fear-based refusal state, their action is overridden with a refusal action (e.g. `REFUSE`), consistent with `emotion_mvp` behavior.
6. **Resolve action**:
   - Pass action into `ActionResolver`;
   - `ActionResolver` updates HP, statuses, guard stacks, etc.
7. **Record action**:
   - Append to `state.actions_this_round` for snapshot logging.
8. **Apply per-hit emotion effects**:
   - E.g. fear gain on being targeted or hit; this uses `CombatEmotionSystem` helpers.

The combination of `EnemyActionChooser`, fear/refusal logic, and `ActionResolver` ensures behavior matches the canonical rules while remaining modular.


#### 4.2.3 KO Fear & Round Tick

After all entities in the initiative order have taken a turn:

1. **Apply KO fear**:
   - `CombatEmotionSystem.apply_ally_ko_fear(state, HeroBal)`  
   - Allies may gain fear from seeing an ally go down, based on config.

2. **Apply round tick**:
   - `CombatEmotionSystem.apply_round_tick(state, HeroBal, ctx)`  
   - Handles:
     - Fear accumulation over time.
     - Morale decay over time.
     - Shrine-specific morale/fear effects.
     - Any other round-based emotional effects.

Tick results are logged into `state.ticks_this_round` so they appear in snapshots.


#### 4.2.4 Objective Evaluation

Next, `CombatEngine` calls `CombatObjectives` to evaluate whether the battle has ended or objectives have advanced:

```gdscript
var end_result := CombatObjectives.check_end(
    state,
    state.objective_state,
    state.objective_defs,
    round_limit,
    hero_bal
)
```

`check_end` returns something like:

```gdscript
{
    "status": "ongoing" | "victory" | "defeat",
    "reason": "enemies_defeated" | "shrine_destroyed" | "round_limit" | ...,
    "objective_state": updated_objective_state,
}
```

`CombatEngine` then:

- Updates `state.objective_state` from the returned payload.
- If `status != "ongoing"`:
  - Sets `state.ended = true`.
  - Stores `state.result.status` and `state.result.reason`.


#### 4.2.5 Snapshot Construction

Regardless of whether the battle has ended, `CombatEngine` asks `CombatSnapshotBuilder` to construct a snapshot for this round:

```gdscript
var snapshot := CombatSnapshotBuilder.build_snapshot(
    state,
    state.actions_this_round,
    state.ticks_this_round,
    end_result
)
```

`build_snapshot` is responsible for:

- Initiative order summary.
- Per-action log entries.
- Per-tick log entries (fear, morale, shrine drain, etc.).
- HP/guard/morale/fear after the round.
- Friendly & enemy summary lists.
- If battle ended:
  - Attach emotion results (from `CombatEmotionSystem.build_emotion_result(state)`).
  - Attach objective result summary.

The snapshot shape is the canonical format used by:

- Debug console output.
- Combat logs for the UI.
- Future analytics and replay systems.

`CombatEngine` does **not** know the details of this format; it just passes data in and receives a snapshot out.


#### 4.2.6 Finalization (End of Battle)

If `end_result.status` is `"victory"` or `"defeat"`:

1. `CombatEngine` asks `CombatEmotionSystem.build_emotion_result(state)` to build per-hero emotion deltas.
2. `CombatEngine` passes these deltas to `EmotionService` / caller.
3. The final snapshot for the last round is marked as terminal (contains stage result, reward hooks, etc.).
4. The battle caller (e.g. `RealmService`) can then:
   - Apply rewards / penalties.
   - Advance realm progression.
   - Trigger additional narrative/effects.

At this point, the combat state is complete.


## 5. Module Responsibilities in Detail

This section summarizes each module in more detail, focusing on how `CombatEngine` interacts with it.

### 5.1 CombatEntities.gd

Purpose: own entity shape, tags, and basic helpers

Key functions (conceptually):

```gdscript
static func normalize_allies(allies_raw: Array, hero_bal) -> Array
static func normalize_enemies(enemies_raw: Array, hero_bal) -> Array
static func ensure_stats(entity: Dictionary) -> void
static func read_hp_pair(entity: Dictionary) -> Dictionary
static func write_hp(entity: Dictionary, hp: int) -> void

static func has_tag(entity: Dictionary, tag: String) -> bool
static func add_tag(entity: Dictionary, tag: String) -> void
static func ensure_tags(entity: Dictionary, tags: Array[String]) -> void

static func is_shrine(entity: Dictionary) -> bool
static func is_structure(entity: Dictionary) -> bool
static func is_objective(entity: Dictionary) -> bool
static func find_first_with_tag(entities: Array, tag: String) -> Dictionary
```

Notable points:

- All entity construction logic is here (not in `CombatEngine`).
- Shrine identification uses tags, not `is_shrine` flags.
- Future entity types (gates, wards, summons, bosses, escort NPCs) only require:
  - Correct `tags`,
  - Correct `stats`,
  - Any extra `meta`/`objective_id` fields as needed.

`CombatEngine` treats entities as opaque DTOs and uses these helpers where necessary.


### 5.2 CombatEmotionSystem.gd

Purpose: own morale & fear rules

Key functions (conceptually):

```gdscript
static func capture_baseline(state: Dictionary) -> void
static func apply_round_tick(state: Dictionary, hero_bal, ctx: Dictionary) -> void
static func apply_ally_ko_fear(state: Dictionary, hero_bal) -> void
static func build_emotion_result(state: Dictionary) -> Dictionary
```

Responsibilities:

- Record initial morale/fear per entity at battle start.
- Apply:
  - Fear gains from hits and attacks.
  - Morale decay or boosts.
  - Shrine-specific fear/morale effects (using entity tags and stage params; **no shrine-specific code in `CombatEngine`**).
  - KO fear when allies go down.
- Produce final per-hero emotion deltas (morale, fear, other emotion axes) for `EmotionService`.

`CombatEngine` only calls these methods at the appropriate times; all implementation details live here.


### 5.3 CombatObjectives.gd

Purpose: end conditions & objective chaining

Key function:

```gdscript
static func check_end(
    state: Dictionary,
    objective_state: Dictionary,
    objective_defs: Array,
    round_limit: int,
    hero_bal
) -> Dictionary
```

Responsibilities:

- Inspect entities and tags to evaluate **active objectives**:
  - `defeat`: all enemies with relevant tags are downed/destroyed.
  - `purify_shrine`: shrine survives waves/purifications.
  - Future:
    - `escort`: escort target alive + extraction conditions.
    - `defend_structure`: hold out for N rounds with structure alive.
    - `destroy_target`: structure/target destroyed.
- Update the objective state graph:
  - Mark objectives as completed or failed.
  - Activate `next_objective_ids` upon completion.
- Determine global status:
  - `"ongoing"`, `"victory"`, `"defeat"`.
  - Reason codes (`"enemies_defeated"`, `"shrine_destroyed"`, `"round_limit"`, etc.).

`CombatEngine` is completely agnostic about the specifics of each objective type.


### 5.4 EnemyActionChooser.gd

Purpose: enemy AI and targeting

Key function:

```gdscript
static func choose_enemy_action(state: Dictionary, entity: Dictionary, ctx: Dictionary) -> Dictionary
```

Responsibilities:

- Given current state and the acting enemy entity, decide **what action** they take.
- MVP behaviors:
  - Attack heroes directly.
  - Prefer shrine / objective entities when objective type demands it.
  - Support existing shrine-priority behavior (unchanged from pre-refactor).
- Future behaviors:
  - Differentiate by `ai_profile` (bosses, cowardly enemies, zealots, etc.).
  - Smarter multi-objective behavior (e.g. some enemies chase escort target, others harass heroes).

`CombatEngine` simply calls this and passes the resulting action to `ActionResolver`.


### 5.5 CombatSnapshotBuilder.gd

Purpose: round and final snapshot construction

Key function:

```gdscript
static func build_snapshot(
    state: Dictionary,
    actions_this_round: Array,
    ticks_this_round: Array,
    end_result: Dictionary
) -> Dictionary
```

Responsibilities:

- Construct:
  - Initiative list for the round.
  - Per-action log lines (actor, target, action type, damage/healing, KO events, refusals, purify actions, etc.).
  - Per-tick log lines (fear/morale changes, shrine drain, etc.).
  - State summary:
    - Allies: hp/max_hp, guards, morale, fear.
    - Enemies: same as above.
    - Shrine and other structure status.
  - If `end_result.status != "ongoing"`:
    - Attach stage result and reason.
    - Include emotion deltas from `CombatEmotionSystem.build_emotion_result(state)`.
    - Include objective_state summary for UI/analytics.

The snapshot format is the **canonical log shape** for the MVP. All UI and debug views should rely on this instead of reconstructing logs from raw state.


### 5.6 ActionResolver.gd

Purpose: resolve chosen actions into state changes

Responsibilities:

- Apply damage/defense/armor calculations.
- Handle guard stacks and shielding.
- Handle KO detection and status changes.
- Handle special actions like `GUARD`, `REFUSE`, `PURIFY_SHRINE`, etc.

`CombatEngine` and `EnemyActionChooser` never directly modify HP; they always go through `ActionResolver` (often via helpers exposed by `CombatEngine`).


## 6. Example Flows

### 6.1 Standard Combat Trial (Defeat Enemies)

Stage configuration (simplified):

```gdscript
objectives = [
    { "id": 1, "type": "defeat", "params": {}, "next_objective_ids": [] },
]
initial_objective_ids = [1]
```

Entity tags:

- Heroes: `["ally", "hero"]`
- Enemies: `["enemy"]`

Flow:

1. Realm invokes `CombatEngine.start_battle(allies, enemies, stage_context)`.
2. Entities normalized (heroes and enemies).
3. Emotion baseline captured.
4. Round-by-round:
   - Allies auto-attack enemies.
   - Enemies attack heroes (via `EnemyActionChooser`).
   - Fear/morale ticks applied.
   - `CombatObjectives.check_end` sees all enemies downed => `status = "victory", reason = "enemies_defeated"`.
5. Final snapshot contains victory result, per-hero emotion deltas, and reward hooks.


### 6.2 Purify Shrine Stage (Protect Shrine Objective)

Stage configuration (simplified):

```gdscript
objectives = [
    { "id": 1, "type": "purify_shrine", "params": { "waves": 2, "drain_per_wave": 10 }, "next_objective_ids": [] },
]
initial_objective_ids = [1]
```

Entities:

- Shrine:

  ```gdscript
  tags = ["ally", "structure", "structure:defense", "objective", "objective:shrine"]
  objective_id = 1
  ```

- Heroes: `["ally", "hero"]`
- Enemies: `["enemy"]`

Flow:

1. Realm builds shrine entity as a normal entity with structure + objective tags.
2. `CombatEngine.start_battle` sets up waves and shrine HP in `stage_context` and state.
3. Each wave is resolved via normal rounds:
   - Enemies use standard AI which prioritizes the shrine as needed.
   - Heroes can use `PURIFY_SHRINE` actions (controlled by existing logic and `ActionResolver`).

4. `CombatObjectives.check_end` evaluates:
   - Shrine HP thresholds.
   - Wave progression.
   - Purify actions taken.
   - Decides `"victory"` (shrine survives) or `"defeat"` (shrine destroyed or other fail condition).

All shrine rules live in `CombatObjectives` and `CombatEmotionSystem`, driven by tags and objective params. `CombatEngine` just runs rounds.


## 7. Extending the System

This section explains how a new developer should approach adding content or systems.

### 7.1 Adding a New Entity Type (e.g., Ward, Gate, Summon, Escort NPC)

1. **Define tags** for the entity in `combat_entities_mvp.md` (if new ones are needed).
2. Ensure the entity is constructed with the **generic entity DTO** shape:
   - Set `stats.hp`, `stats.max_hp`, etc.
   - Set `tags` appropriately.
   - Set `objective_id` if tied to an objective.
3. If additional helpers are needed (e.g., `is_gate`, `is_ward`), add them as **tag-based helpers** to `CombatEntities`.
4. No changes to `CombatEngine` should be necessary.

### 7.2 Adding a New Objective Type (e.g., Escort, Defend, Destroy)

1. Update `CombatObjectives`:
   - Teach `check_end` how to interpret the new `type` value.
   - Use tags + `objective_id` to find participating entities.
2. Add docs to `combat_entities_mvp.md` and `realms_mvp.md` describing:
   - Expected `params`.
   - How entities link via `objective_id` and tags.
3. Update `RealmStageBuilder` to author stages with this new objective type.
4. Optionally update `EnemyActionChooser` to make AI aware of the new objective (e.g., prioritize escort targets or gates).

Again, `CombatEngine` itself remains unchanged.


### 7.3 Adding or Changing AI Behavior

1. Modify or extend `EnemyActionChooser`:
   - Add new behaviors keyed by `ai_profile`.
   - Use tags and objective context to drive target selection.
2. Ensure behavior remains deterministic given the same seeds and state.
3. If necessary, update docs to describe new `ai_profile` values.

No direct changes to `CombatEngine` are needed beyond any new data fields stored in `ctx`.


### 7.4 Changing Snapshot / Log Shape

1. Update `CombatSnapshotBuilder`:
   - Add new fields or alter structure.
2. Update any consumers (Debug console, UI) accordingly.
3. If you must preserve backward compatibility, add versioning to the snapshot structure.

`CombatEngine` continues to call `build_snapshot` and treat the snapshot as opaque.


## 8. Testing & Debug Hooks

### 8.1 Realm & Generic Entity Tests

The test suite now includes:

- **Realm generation & reward tests** (existing):
  - Seed stability.
  - Reward consistency by tier.
- **Generic entity tests** (new, see `TestCombatGenericEntities.gd`):
  - `find_alive_shrine_picks_allied_shrine`
  - `find_alive_shrine_ignores_ko_shrine`
  - `defeat_enemies_objective_ignores_allied_shrine`
  - `protect_shrine_objective_tracks_shrine_hp`

These tests focus on:

- Tag-driven entity behavior.
- Objective handling and shrine logic.
- Ensuring generic entity support works even before realms fully use all features.

### 8.2 Debug Console Integration

The `DebugConsole` exposes a command like:

```text
/run_tests realms
```

Which will:

1. Run realm generation tests.
2. Run realm reward tests.
3. Run generic combat entity tests.

Output follows the pattern:

```text
[run_tests] realms: starting realm generation tests…
[test_realm_generation] PASS: ...
...
[run_tests] realms: starting generic entity tests…
[test_generic] RUN: ...
[test_generic] PASS: ...
...
[run_tests] realms: all realm + generic entity tests invoked (see per-suite output above)
```

This ensures that changes to combat code can be validated quickly without setting up complex UI scenarios.


## 9. Migration Notes (Legacy → Refactored)

Key changes from the pre-refactor engine:

- **Shrine logic**:
  - Previously: special cased inside `CombatEngine` in multiple places.
  - Now: shrine is just an entity with structure + objective tags; behavior is handled by `CombatObjectives` and `CombatEmotionSystem`.

- **Entity shape**:
  - Previously: heroes and enemies had bespoke shapes and ad-hoc fields.
  - Now: all participants share the generic entity DTO, with tags and optional fields in `meta`.

- **Objective handling**:
  - Previously: only “defeat” and shrine were supported, entangled with engine flow.
  - Now: objectives are data-driven (`objective_defs` + `objective_id` links) and generalized for future escort/defend/destroy/multi-objective stages.

- **CombatEngine size**:
  - Previously: monolithic god-script mixing entity construction, AI, shrine logic, emotions, and logs.
  - Now: thin orchestrator delegating logic to specialized modules.

Any new work should **follow the refactored pattern**: if you need new behavior, put it in the appropriate module and only adjust `CombatEngine` to wire it in.


## 10. Summary

The refactored combat engine architecture achieves the original goals:

1. **Generic entity model** so new stage types and units plug in easily.
2. **Thin, orchestrator-style CombatEngine** that delegates logic to specialized modules.
3. **Objective-based flow** that supports current MVP objectives (combat_trial, purify_shrine) and future ones (escort, defend, destroy, multi-objective) without rewriting the engine.
4. **Deterministic and debuggable behavior**, with a clear snapshot/log shape and robust tests.

When in doubt:

- Check `combat_entities_mvp.md` for entity and objective model details.
- Check this document for orchestration and module responsibilities.
- Keep `CombatEngine` small and focused on wiring; put rules into the modules.