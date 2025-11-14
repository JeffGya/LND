

# Realms MVP — Seeded Realm Runs

Story: **As the Keeper I want seeded Realms**

This addendum describes the MVP implementation of seeded Realms, and how it maps back to the Legacy Never Dies GDD and the Notion story subtasks. It is the “current truth” of how Realms behave in the MVP Godot build.

---

## 1. Canon anchors (why & what)

From the canon and the story brief:

- **Realms are 5–6 sequential stages**  
  MVP uses a fixed **5 stages per Realm**. The deterministic seed picks stage types and encounters.

- **MVP Realms & virtues**  
  Initial set:  
  - `vale_of_dust` → Virtue: **Courage**  
  - `shrouded_grove` → Virtue: **Wisdom**

- **Tiered progression**  
  Rewards, fear pressure, and enemy power **scale by Realm tier**, using balance curves aligned with §8 and §12.

- **Objective templates**  
  Canon supports templates like Purify / Protect / Slay / Recover / Escort.  
  MVP implements a lean subset:
  - `combat_trial`
  - `purify_shrine` (implemented as a lighter combat encounter plus modifiers)

All of this must obey:

- Determinism: same inputs → same Realm layout, same combat seeds, same rewards.  
- No hard stalls: successful runs always yield some Ase/Ekwan; tiers scale upwards (never down).

---

## 2. Realm data model (RealmModel & StageModel)

### 2.1 RealmModel

**File:** `core/world/RealmModel.gd`  
**Class:** `RealmModel`

Fields (core MVP fields):

- `id: String`  
  Realm identifier (e.g., `"vale_of_dust"`, `"shrouded_grove"`).

- `name: String`  
  Player-facing label (e.g., `"Vale of Dust"`).

- `virtue: String`  
  Virtue theme string (e.g., `"courage"`, `"wisdom"`). Used for flavor, balance hooks, and enemy flavor selection.

- `tier: int`  
  Realm difficulty tier (MVP commonly uses tier 1, but tiers are fully supported).

- `seed: int`  
  Deterministic realm seed, derived from the **campaign seed + realm id + tier** via `RealmSeed.realm_seed`.

- `stages: Array[StageModel]`  
  Ordered list of Realm stages. MVP: always **5** stages.

- `current_stage_index: int`  
  Index into `stages`.  
  - `0` at start.  
  - Increments as stages are completed.  
  - When it reaches `stages.size()`, the Realm is finished.

- `restored: bool`  
  Indicates if the Realm was loaded from save. Used to distinguish fresh vs. restored runs.

- `is_completed: bool`  
  Flag set when the final stage is completed. Used by RealmService and UI.

**Constructor (_init)**

`_init` takes optional params for id, name, virtue, tier, seed, and an optional stages array. If a non-empty stages list is provided, it duplicates it into `stages`; otherwise it keeps the default empty typed array and uses that when the generator fills it.

This keeps the model:

- **Serializable** (to Dictionary for save/load).
- **Type-safe** (stages is always `Array[StageModel]`).
- **Deterministic** when reconstructed from seed and meta.

---

### 2.2 StageModel

**File:** `core/world/StageModel.gd`  
**Class:** `StageModel`

Fields:

- `index: int`  
  Stage index in the Realm (0–4 for MVP).

- `objective_type: String`  
  What the stage actually is:
  - `"combat_trial"`
  - `"purify_shrine"`  
  Later expansions can add `"escort"`, `"protect_shrine"`, etc.

- `encounter_seed: int`  
  Seed used for:
  - Enemy pack generation (via `EnemyFactory.spawn_realm_pack`).
  - Combat harness determinism (turn order, rolls, etc.).

- `modifiers: Dictionary`  
  Misc modifiers. MVP examples:
  - `"fear_delta": int` — how much fear pressure this stage applies.  
  - Later: `"env_tags"`, `"special_rules"`, etc.

StageModels are pure data: they do not own any combat or economy logic themselves. They are consumed by the **ObjectiveRunner**, the **EnemyFactory**, and the **RealmRewardCalc**.

---

## 3. Realm balance config (GameBalance_Realm)

**File:** `core/config/GameBalance_Realm.gd`

This file is the **single source of truth** for Realm-related knobs. Core MVP elements:

- `REALM_LIST: Dictionary`  
  Map of `realm_id` → `{ name, virtue, default_tier }`.

  Example (conceptual):

  ```gdscript
  const REALM_LIST := {
      "vale_of_dust": {
          "name": "Vale of Dust",
          "virtue": "courage",
          "default_tier": 1,
      },
      "shrouded_grove": {
          "name": "Shrouded Grove",
          "virtue": "wisdom",
          "default_tier": 1,
      },
  }
  ```

- `REALM_STAGE_COUNT: int = 5`  
  Fixed MVP stage count per Realm.  
  Future: this can become a per-realm or per-tier curve, but tests currently assume a 5-stage MVP layout.

- `REALM_OBJECTIVE_WEIGHTS: Dictionary`  
  Per realm, defines how likely each objective type is when seeding the Realm.

  Example shape:

  ```gdscript
  const REALM_OBJECTIVE_WEIGHTS := {
      "vale_of_dust": {
          "combat_trial": 3,
          "purify_shrine": 1,
      },
      "shrouded_grove": {
          "combat_trial": 2,
          "purify_shrine": 2,
      },
  }
  ```

- `TIER_SCALARS`  
  Scalar curves for tier-based modifications, e.g.:

  - `enemy_power`  
  - `fear_pressure`  
  - `ekwan_drop`  
  - `ase_reward`

  These are aligned with Balance Curve §12 and ensure monotonic scaling (higher tiers never pay less than lower tiers).

- `REWARD_BASE`  
  Base reward template: `{ ase: X, ekwan: Y, relic_weights: {...} }`  
  Used by `RealmRewardCalc` to compute per-stage and completion rewards.

Accessors from this file are used by both:

- `RealmGenerator` (for layout, stage types, and fear modifiers).  
- `RealmRewardCalc` (for Ase/Ekwan and relic probabilities).

---

## 4. Seed pipeline (RealmSeed)

**File:** `core/world/RealmSeed.gd`

Responsibility: turn high-level campaign + realm info into deterministic seeds.

- `static func realm_seed(campaign_seed: int, realm_id: String, tier: int) -> int`  
  Combines the campaign seed, realm id, and tier into a single realm seed.
  - Same `(campaign_seed, realm_id, tier)` → same `realm_seed`.
  - Different campaign seeds → typically different `realm_seed`.

- `static func stage_seed(realm_seed: int, stage_index: int) -> int`  
  Derives a stage seed from the realm seed and the stage index.
  - Same `(realm_seed, stage_index)` → same `stage_seed`.
  - Each stage index gets its own deterministic sub-seed.

These functions are pure and have no side effects, which makes them safe and testable.

**Tests:** `test_realm_generation.gd`

- Confirms that `realm_seed` and `stage_seed` are stable across repeated calls with the same input.

---

## 5. Realm generation (RealmGenerator)

**File:** `core/world/RealmGenerator.gd`

Entry point:

```gdscript
func generate(realm_id: String, tier: int, campaign_seed: int) -> RealmModel
```

High-level steps:

1. **Lookup meta**  
   - Fetch `name`, `virtue`, default tier, and other settings from `GameBalance_Realm.REALM_LIST`.

2. **Compute seeds**  
   - `realm_seed := RealmSeed.realm_seed(campaign_seed, realm_id, tier)`.

3. **Create RealmModel**  
   - Construct a `RealmModel` with id, name, virtue, tier, seed.
   - Initialize `stages` as an empty `Array[StageModel]`.

4. **Populate stages** (MVP: fixed 5)

   For `i` from `0` to `REALM_STAGE_COUNT - 1`:

   - Compute `stage_seed := RealmSeed.stage_seed(realm_seed, i)`.
   - Use a deterministic PRNG and `REALM_OBJECTIVE_WEIGHTS[realm_id]` to select an `objective_type`.
   - Build a `StageModel` with:
     - `index = i`
     - `objective_type`
     - `encounter_seed = stage_seed`
     - `modifiers["fear_delta"]` from tier-based scalars.

5. **Return RealmModel**  
   - `current_stage_index` = 0
   - `is_completed` = false
   - `restored` = false

**Determinism properties:**

- Same `(campaign_seed, realm_id, tier)` → identical `RealmModel` (id, tier, seed, stages list).
- Different campaign seeds → typically different stage seeds and/or objective layouts.

**Tests:** `test_realm_generation.gd`

- `test_realm_generator_determinism` ensures two calls with the same inputs generate identical realms (including stage types, seeds, and modifiers).

---

## 6. RealmService — caching & active Realm

**File:** `core/services/RealmService.gd`

Responsibility: manage Realm instances and active selection.

Static fields:

- `_realms: Dictionary`  
  In-memory cache keyed by a composite key (realm id + tier). Holds `RealmModel` instances.

- `_active_realm: RealmModel`  
  Currently selected Realm for the run.

Key static functions:

- `get_cached(realm_id: String, tier: int) -> RealmModel`  
  Look up a Realm from `_realms` using a composite key. Returns `null` if not found.

- `get_or_create(realm_id: String, tier: int, campaign_seed: int) -> RealmModel`  

  - If a cached Realm exists for `(realm_id, tier)`, return it.
  - Otherwise:
    - Call `RealmGenerator.generate(...)` to build a new RealmModel.
    - Cache it in `_realms`.
    - Optionally set it as `_active_realm`.
  - This implements the story’s “Realm JSON created and cached” requirement.

- `set_active(realm: RealmModel) -> void`  
  Sets `_active_realm` to the provided Realm and ensures it also lives in the cache.

- `get_active() -> RealmModel`  
  Returns the current active Realm (or `null` if none is active).

- `complete_stage() -> Dictionary`  
  Handles “stage completion” behavior:
  - Reads the active Realm and its `current_stage_index`.
  - Uses `RealmRewardCalc.stage_rewards` for the current stage.
  - Applies rewards via `EconomyService.apply_realm_stage_rewards`.
  - Increments `current_stage_index`.
  - If the last stage was just completed:
    - Adds `completion_rewards` and sets `is_completed = true`.
  - Returns a summary `Dictionary` of total rewards and flags (`{ ase, ekwan, relics, completed }`).

**Note:** In MVP, the cache key is `(realm_id, tier)`. This means:

- Within a single session, repeated calls with the same realm and tier share the same instance.
- Cross-campaign differentiation can be extended later (e.g., by including `campaign_seed` in the cache key or clearing cache on `/new_game`).

**Tests:** `test_realm_generation.gd`

- `test_realm_service_cache` asserts `get_or_create` returns the exact same instance when called twice with identical inputs.

---

## 7. Reward model (RealmRewardCalc)

**File:** `core/world/RealmRewardCalc.gd`

Responsible for computing **per-stage** and **completion** rewards.

### 7.1 Stage rewards

```gdscript
func stage_rewards(realm: RealmModel, stage: StageModel) -> Dictionary
```

Inputs:

- Realm meta: `realm.tier`, `realm.virtue`.
- Stage meta: `objective_type`, `index`, `modifiers`.
- Balance config: `REWARD_BASE`, `TIER_SCALARS`.

Typical output shape:

```gdscript
{
    "ase_delta": int,
    "ekwan_delta": int,
    "relic_roll": { "rarity": String, ... }?, # optional
}
```

Properties:

- Ase rewards are **always ≥ 1** on success (no zero-reward wins).
- Ekwan rewards are **never negative**.
- Higher tiers (2, 3, …) pay **at least as much** as lower tiers for equivalent stages.

### 7.2 Completion rewards

```gdscript
func completion_rewards(realm: RealmModel) -> Dictionary
```

- Provides a one-time bonus when the last stage is completed.
- Uses tier and stage count to derive additional Ase/Ekwan on top of per-stage rewards.
- All completion rewards are **non-negative**.

### 7.3 Tests

**File:** `core/tests/realm/test_realm_rewards.gd`

Includes:

- `test_stage_rewards_non_negative`  
  - Asserts per-stage Ase ≥ 1, Ekwan ≥ 0.

- `test_tier_scaling_monotonic`  
  - Confirms that for the same Realm and stage type:
    - Tier 2 Ase ≥ Tier 1 Ase  
    - Tier 3 Ase ≥ Tier 2 Ase  
    - Same monotonic constraint for Ekwan.

- `test_completion_rewards_non_negative`  
  - Confirms completion rewards are never negative.

These tests are intentionally **shape-based**, not hard-coded to specific numbers, so you can retune curves without rewriting tests.

---

## 8. ObjectiveRunner & EnemyFactory — from stages to fights

### 8.1 ObjectiveRunner

**File:** `core/world/ObjectiveRunner.gd`

Entry point:

```gdscript
func run_stage(stage: StageModel, realm: RealmModel) -> Dictionary
```

MVP behavior:

- If `stage.objective_type == "combat_trial"`:
  - Fetch the active party (from `PartyRoster`, either staged via `/party_set` or chosen automatically).
  - Use `EnemyFactory.spawn_realm_pack(realm, stage)` to build the enemy pack.
  - Run the deterministic combat harness using `stage.encounter_seed`.
  - On victory:
    - Ask `RealmService.complete_stage()` for rewards.
  - Return a summary of the result and rewards.

- If `stage.objective_type == "purify_shrine"`:
  - Uses the same combat harness, with a slightly lighter pack size or modified fear deltas.
  - On success, still flows through `RealmService.complete_stage()`.

The ObjectiveRunner is the bridge between **pure data** (RealmModel/StageModel) and the existing **Combat Simulation Core**.

---

### 8.2 EnemyFactory realm-aware packs

**File:** `core/combat/EnemyFactory.gd`

MVP function:

```gdscript
func spawn_realm_pack(realm: RealmModel, stage: StageModel) -> Array[Enemy]
```

Behavior:

- Uses `realm.id` and `realm.virtue` to determine which enemy profile to use.
- Examples:
  - `vale_of_dust` → `"Dust Wraith"` enemies.
  - `shrouded_grove` → `"Grove Seer"` and related enemies.

This ensures:

- Combat logs reflect Realm flavor:
  - `Dust Wraith #1`, `Dust Wraith #2` for Vale of Dust.
- Enemy stats and pack sizes can be tuned per Realm and tier.

---

## 9. Debug Console — Realm QA commands

**File:** `core/ui/debug/debug_console.gd`

MVP commands:

- `/realm list`  
  Lists available Realms from `GameBalance_Realm.REALM_LIST`:

  ```text
  [realm] available realms:
   - vale_of_dust  | courage | default_tier=1
   - shrouded_grove  | wisdom | default_tier=1
  ```

- `/realm new <realm_id> [tier]`  
  Uses the current `campaign_seed` to fetch or generate a Realm via `RealmService.get_or_create`.  
  Sets it active. Example:

  ```text
  [realm] Active: Vale of Dust (courage) | tier=1 | seed=1315888032 | stages=5
  ```

- `/realm show`  
  Shows the active Realm summary and a stage table:

  ```text
  [realm] Vale of Dust (courage) | tier=1 | seed=1315888032 | stages=5 | current=1 | finished=false
  Stages:
     0 | purify_shrine | seed=1746048249 | fear_delta=5
   > 1 | combat_trial  | seed=1683888268 | fear_delta=5
     2 | combat_trial  | seed=1894613843 | fear_delta=5
     3 | combat_trial  | seed=1295583078 | fear_delta=5
     4 | combat_trial  | seed=1497664301 | fear_delta=5
  ```

- `/realm enter [stage_index]`  
  - If index omitted → uses `current_stage_index`.  
  - Runs the stage through `ObjectiveRunner`.  
  - On success, prints:

    ```text
    [realm enter] stage=0 type=purify_shrine success=true
    [realm enter] rewards — Ase +20, Ekwan +13
    [realm enter] realm progress — current_stage=1/5, finished=false
    ```

- `/realm complete`  
  - Fast-forwards all remaining stages.  
  - Applies per-stage rewards and a single completion reward.  
  - Prints a summary:

    ```text
    [realm complete] auto-completed 3 remaining stages. Ase +116, Ekwan +51, relics=1
    ```

These commands are the main QA and design tools for validating the Realm system without UI.

---

## 10. Tests & Definition of Done

### 10.1 Automated tests

**Files:**

- `core/tests/realm/test_realm_generation.gd`
- `core/tests/realm/test_realm_rewards.gd`

**Debug console integration:**

- `/run_tests realms`  
  Runs both realm test suites (generation + rewards).

- `/run_tests all`  
  Runs the economy tests via `TestRunner.run_all(true)` and then the realm tests.

**Generation tests cover:**

- Seed stability for `realm_seed` and `stage_seed`.
- Determinism of `RealmGenerator.generate` for identical inputs.
- Cache behavior of `RealmService.get_or_create`.

**Reward tests cover:**

- Non-negative stage rewards (Ase ≥ 1, Ekwan ≥ 0).
- Monotonic tier scaling (Tier 2/3 ≥ Tier 1/2).
- Non-negative completion rewards.

### 10.2 Story-level Definition of Done

For the story **“As the Keeper I want seeded Realms”**, this MVP implementation is considered done when:

- **Config & models**
  - `GameBalance_Realm` defines at least Vale of Dust and Shrouded Grove, with virtue and default tier.
  - `RealmModel` and `StageModel` serialize to and from Dictionary without losing structure.
  - `REALM_STAGE_COUNT` is 5 and used consistently.

- **Determinism**
  - Same `(campaign_seed, realm_id, tier)` → same Realm layout and stage seeds across runs.
  - `ObjectiveRunner` runs produce consistent combat logs and rewards for a fixed seed (within the combat harness determinism guarantees).

- **Progression & economy**
  - `RealmService.complete_stage` correctly advances `current_stage_index` and marks the Realm completed at the final stage.
  - `RealmRewardCalc` ensures stage rewards and completion rewards are non-negative and scale with tier.
  - Ase and Ekwan rewards are applied via `EconomyService` and visible in the existing economy UI/debug panel.

- **Debug/QA tooling**
  - `/realm list`, `/realm new`, `/realm show`, `/realm enter`, `/realm complete` all function without errors and produce readable logs.
  - `/run_tests realms` runs green on both generation and reward tests.

---

## 11. Suggested QA script

For quick manual regression:

1. **Realm config & listing**

   ```text
   /realm list
   ```

   Verify both MVP realms appear with virtues and default tiers.

2. **New game + Realm creation**

   ```text
   /new_game
   /realm new vale_of_dust
   /realm show
   ```

   Check:
   - 5 stages.
   - Seeds are non-zero.
   - `current=0`, `finished=false`.

3. **Stage determinism**

   - Restart game.
   - Repeat `/new_game`, `/realm new vale_of_dust`, `/realm show`.
   - Confirm stage table matches previous run (same seeds, objective types, fear deltas).

4. **Combat & rewards**

   - Summon a few heroes, set a party.
   - Run:

     ```text
     /realm enter
     ```

   - Verify:
     - `[realm enter] ... success=true`
     - Ase/Ekwan rewards logged.
     - `current_stage` increments in `/realm show`.

5. **Realm completion**

   - Repeat `/realm enter` until finished.
   - Confirm:
     - `current_stage == 5`
     - `finished=true`
     - Completion reward applied (Ase/Ekwan jump at last stage).

6. **Fast-forward completion**

   - New game, new Realm.
   - Call:

     ```text
     /realm complete
     ```

   - Confirm:
     - `auto-completed N remaining stages`
     - Ase/Ekwan totals are plausible and non-negative.
     - `/realm show` reports `current=5`, `finished=true`.

7. **Enemy flavor**

   - Confirm that Vale of Dust uses “Dust Wraith” enemies, Shrouded Grove uses its own enemy flavor.

If any of these steps diverge from the expectations here, the bug should be traced through: `GameBalance_Realm` → `RealmSeed` → `RealmGenerator` → `RealmService` → `ObjectiveRunner` → `EnemyFactory` → `EconomyService`.