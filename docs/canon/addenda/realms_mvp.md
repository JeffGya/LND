

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

**File:** `core/models/RealmModel.gd`  
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

**File:** `core/model/StageModel.gd`  
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

  
  For **purify_shrine** stages (when `objective_type == "purify_shrine"`), the generator is expected to populate:
  - `"shrine_waves"` (int) — number of combat waves for this shrine stage (MVP: 2, from `GameBalance_Realm.get_purify_waves()`).
  - `"morale_drain_per_wave"` (int) — amount of morale each participating hero loses after each successful wave, tier-scaled via `GameBalance_Realm.get_purify_morale_drain(tier)`.
  - `"shrine_reward_multiplier"` (float) — multiplier applied to the standard stage rewards for shrines, tier-scaled via `GameBalance_Realm.get_purify_reward_mult(tier)`.
  
  These keys allow ObjectiveRunner, the morale system, and RealmRewardCalc to behave correctly without hard-coded shrine numbers, while keeping StageModel itself generic.

StageModels are pure data: they do not own any combat or economy logic themselves. They are consumed by the **ObjectiveRunner**, the **EnemyFactory**, and the **RealmRewardCalc**.

---

## 3. Realm balance config (GameBalance_Realm)
### 3.1 Purify Shrine objective (MVP)

The `purify_shrine` objective is a **two-wave survival trial** with fully deterministic shrine-specific parameters defined in `StageModel.modifiers`.

#### Core rules (MVP)

- **Two waves**
  - Exactly **2 waves** per shrine stage (no variation in MVP).
  - Same party is used for both waves.
  - KO’d heroes **remain KO’d** between waves.

- **Shrine HP system**
  Shrine stages now include HP tracking:
  - `shrine_hp_max` — maximum shrine HP.
  - `shrine_passive_drain_per_wave` — guaranteed shrine HP loss after each wave.
  - If shrine HP reaches **0 at any time**, the stage **fails immediately**, even if that combat wave was won.

- **Shrine drain & Purify (MVP behavior)**
  - Realm config (`GameBalance_Realm`) defines a **base**
    - Combat and ObjectiveRunner may **temporarily reduce** the effective drain for a given wave when a Purify action succeeds. The reduction factor is tier-scaled via Realm helpers (e.g. 
  - Purify never restores shrine HP directly; it only affects how much HP is lost between waves. Once a wave is finished and its drain is applied (with any reductions), that effect is permanent.

- **Combat flow**
  1. **Wave 1**  
     - Uses `stage.encounter_seed`.
     - If party wipes → **failure**.
     - Apply shrine passive drain.
  2. **Wave 2**  
     - Uses deterministic seed: `encounter_seed + 1`.
     - If party wipes → **failure**.
     - Apply shrine passive drain.
  3. **Success condition**  
     - Party survives both waves.
     - Shrine HP > 0 after the final drain.

- **Morale integration (MVP placeholder)**
  - `morale_drain_per_wave` exists and is seeded into modifiers.
  - Actual morale-reduction logic will be completed in the **Emotion & Morale Core mini-epic**.
  - Currently logged but not applied to hero morale.

- **Rewards**
  - Shrine rewards use normal reward calculation plus:
    - `shrine_reward_multiplier` (tier-scaled: e.g., 1.1 / 1.2 / 1.3).
  - This makes shrines slightly more rewarding than standard `combat_trial` stages.

#### Shrine-specific StageModel modifiers

`RealmGenerator` populates these keys for shrine stages:

| Key                               | Type   | Meaning |
|-----------------------------------|--------|---------|
| `"fear_delta"`                    | int    | Fear pressure for the stage |
| `"shrine_waves"`                  | int    | Always 2 in MVP |
| `"shrine_hp_max"`                 | int    | Maximum shrine HP |
| `"shrine_passive_drain_per_wave"` | int    | Passive HP loss per wave |
| `"purify_drain_reduction_mult"`   | float  | Multiplier applied to base shrine drain when a wave has been purified (tier-scaled) |
| `"morale_drain_per_wave"`         | int    | Configured, integration pending |
| `"shrine_reward_multiplier"`      | float  | Multiplier applied to rewards |

#### Determinism

- Wave seeds are always:  
  - Wave 0 → `encounter_seed`  
  - Wave 1 → `encounter_seed + 1`
- Same campaign seed + realm + stage index → same wave behavior, same shrine HP evolution.

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
# Realms MVP — Seeded Realm Runs

Story: **As the Keeper I want seeded Realms**

This addendum describes the MVP implementation of seeded Realms, and how it maps back to the Legacy Never Dies GDD and the Notion story subtasks. It is the “current truth” of how Realms behave in the MVP Godot build, and how they plug into the **generic combat objective system** (CombatObjectives, generic entities, shrine objectives, etc.).

Realms are intentionally **data‑first** and **deterministic**: they declare *what should happen* (stage types, seeds, modifiers). Separate systems (ObjectiveRunner, CombatObjectives, EnemyFactory, CombatEngine) implement *how it plays out*.

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
  Rewards, fear pressure, and enemy power **scale by Realm tier**, using balance curves aligned with §8 and §12 of the GDD.

- **Objective templates**  
  Canon supports templates like Purify / Protect / Slay / Recover / Escort.  
  The **combat layer** now exposes these as generic **objectives** in `CombatObjectives.gd` (e.g. defeat enemies, protect shrine, escort target, multi‑objective).  
  The **Realm layer** simply references them by `objective_type` + modifiers.

  MVP implements a lean subset of realm stages:
  - `combat_trial` → maps to the **defeat_enemies** objective
  - `purify_shrine` → maps to a **protect_shrine + purify hooks** objective

All of this must obey:

- **Determinism:** same inputs → same Realm layout, same combat seeds, same rewards, same shrine parameters.  
- **No hard stalls:** successful runs always yield some Ase/Ekwan; tiers scale upwards (never down).  
- **Shape stability:** Realms describe stages via a stable, documented data model so future objectives (escort, defend, destroy, multi‑objective) can be added without rewriting Realm generation.

Realms are therefore the **bridge** between campaign meta (seed, tier, virtue) and the generic combat/objective systems.

---

## 2. Realm data model (RealmModel & StageModel)

### 2.1 RealmModel

**File:** `core/models/RealmModel.gd`  
**Class:** `RealmModel`

Fields (core MVP fields):

- `id: String`  
  Realm identifier (e.g., `"vale_of_dust"`, `"shrouded_grove"`). Stable key used in config and saves.

- `name: String`  
  Player‑facing label (e.g., `"Vale of Dust"`). Used in logs and UI.

- `virtue: String`  
  Virtue theme string (e.g., `"courage"`, `"wisdom"`). Used for flavor, balance hooks, and realm‑specific enemy flavor.

- `tier: int`  
  Realm difficulty tier (MVP commonly uses tier 1, but tiers are fully supported in config and reward curves).

- `seed: int`  
  Deterministic realm seed, derived from the **campaign seed + realm id + tier** via `RealmSeed.realm_seed`.

- `stages: Array[StageModel]`  
  Ordered list of Realm stages. MVP: always **5** stages, each a `StageModel` instance.

- `current_stage_index: int`  
  Index into `stages`.  
  - `0` at start.  
  - Increments as stages are completed.  
  - When it reaches `stages.size()`, the Realm is considered finished.

- `restored: bool`  
  Indicates if the Realm was loaded from save. Used to distinguish fresh vs. restored runs.

- `is_completed: bool`  
  Flag set when the final stage is completed. Used by `RealmService` and UI.

**Constructor (`_init`)**

`_init` takes optional params for id, name, virtue, tier, seed, and an optional stages array. If a non‑empty stages list is provided, it duplicates it into `stages`; otherwise it keeps the default empty typed array which will be filled by the generator later.

This keeps the model:

- **Serializable** (to/from `Dictionary` for save/load).  
- **Type‑safe** (stages is always `Array[StageModel]`).  
- **Deterministic** when reconstructed from seed and meta.

RealmModel itself is **pure data**: no combat logic, no reward calculation, no AI. It is consumed by RealmService, ObjectiveRunner, and RealmRewardCalc.

---

### 2.2 StageModel

**File:** `core/model/StageModel.gd`  
**Class:** `StageModel`

Fields:

- `index: int`  
  Stage index in the Realm (0–4 for MVP).

- `objective_type: String`  
  Declares what type of objective this stage represents. This string lines up with `CombatConstants` and `CombatObjectives`:

  - `"combat_trial"` → defeat all enemies (maps to `CombatConstants.OBJECTIVE_DEFEAT_ENEMIES`)
  - `"purify_shrine"` → protect the shrine over multiple waves with Purify hooks (maps to a shrine‑aware objective in `CombatObjectives`)

  Future examples (not yet active in MVP):

  - `"escort_entity"`  
  - `"defend_structure"`  
  - `"destroy_target"`  
  - `"multi_objective"`

  Realm generation never hard‑codes shrine behavior; it only picks an `objective_type` and adds modifiers.

- `encounter_seed: int`  
  Seed used for:
  - Enemy pack generation (`EnemyFactory.spawn_realm_pack` / other encounter factories).  
  - Combat harness determinism (turn order, rolls, AI decision RNG, etc.).  
  - Shrine wave seeds are deterministically derived from this via `encounter_seed + wave_index` (see §3.3).

- `modifiers: Dictionary`  
  Misc modifiers that further describe this stage to the systems that consume it. MVP examples:

  - `"fear_delta": int` — how much fear pressure this stage applies upon success/failure (used by EmotionService / realm emotion hooks).  

  For **purify_shrine** stages (when `objective_type == "purify_shrine"`), the generator additionally populates shrine‑specific keys (see §3.1 for exact meanings):

  - `"shrine_waves"` (int) — number of combat waves for this shrine stage (MVP: 2).  
  - `"shrine_hp_max"` (int) — maximum shrine HP at the start of wave 1.  
  - `"shrine_passive_drain_per_wave"` (int) — baseline shrine HP loss between waves.  
  - `"purify_drain_reduction_mult"` (float) — multiplier applied to the baseline shrine drain when the wave was purified (e.g. 0.5 = half drain on a purified wave).  
  - `"morale_drain_per_wave"` (int) — placeholder for per‑wave morale penalties, tier‑scaled. Logged and reserved for future Emotion & Morale integration.  
  - `"shrine_reward_multiplier"` (float) — multiplier applied to the standard stage rewards for shrines, tier‑scaled via `GameBalance_Realm` helpers.

  These keys allow `CombatObjectives`, `ObjectiveRunner`, the emotion system, and `RealmRewardCalc` to behave correctly without hard‑coded shrine numbers inside those systems.

StageModels are **pure DTOs**: they do not own any combat or economy logic. They are consumed by the **ObjectiveRunner**, the **CombatObjectives** module, the **EnemyFactory**, and **RealmRewardCalc**.

---

## 3. Realm balance config (GameBalance_Realm)

**File:** `core/config/GameBalance_Realm.gd`

This config is the main home for Realm definitions and numeric knobs used by generation and rewards.

### 3.1 Purify Shrine objective (MVP realm layer view)

The `purify_shrine` objective is modelled at realm level as a **two‑wave shrine defense stage** with shrine‑specific parameters baked into the stage modifiers.

Realm config defines, per realm/tier:

- **Base shrine parameters**
  - `shrine_hp_max`  
  - `shrine_passive_drain_per_wave`  
  - `shrine_waves` (MVP fixed to 2 but wired for future variation)

- **Purify scaling**
  - `purify_drain_reduction_mult` → how much the shrine drain is reduced on waves where Purify succeeds. This does *not* restore HP; it only reduces the amount lost between waves.

- **Morale hooks**
  - `morale_drain_per_wave` → configured per tier to allow future morale integration. For now the value is stored in StageModel and logged by the combat/emotion layer, but morale changes are handled in the dedicated Emotion epic.

- **Reward multiplier**
  - `shrine_reward_multiplier` → stage reward multiplier applied on top of standard reward curves to make shrine stages slightly more rewarding than a regular `combat_trial` of the same tier.

Realm generation uses these helpers to fill `StageModel.modifiers` for shrine stages (see §5). The **actual shrine logic** (waves, shrine HP tracking, Purify behavior) lives in the **combat/objective layer**, not in the realm generator.

### 3.2 Global Realm knobs

Key config pieces in `GameBalance_Realm` (MVP):

- `REALM_LIST`  
  Declares the list of available realms, their virtues, and default tiers. Example entries:

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

- `REALM_STAGE_COUNT`  
  MVP uses a fixed value of `5`. RealmGenerator uses this to decide how many StageModels to create.

- `REALM_OBJECTIVE_WEIGHTS`  
  Per‑realm tables that set weighted probabilities of stage types (combat_trial, purify_shrine, etc.). Example shape:

  ```gdscript
  const REALM_OBJECTIVE_WEIGHTS := {
      "vale_of_dust": {
          "combat_trial": 4,
          "purify_shrine": 1,
      },
      "shrouded_grove": {
          "combat_trial": 3,
          "purify_shrine": 2,
      },
  }
  ```

- Tier scaling helpers for stage rewards, completion rewards, fear deltas, and shrine modifiers.  
  These are used by `RealmGenerator`, `RealmRewardCalc`, and shrine helper functions to derive per‑stage modifier values.

### 3.3 Shrine determinism (realm view)

For shrine stages, determinism is achieved by deriving all seeds from the **stage** seed:

- `stage.encounter_seed` → used for **wave 0** (first shrine wave).  
- `stage.encounter_seed + 1` → used for **wave 1** (second shrine wave).  
- Additional future waves would continue (`+2`, `+3`, …).

The realm layer doesn’t know about rounds or turn order; it only guarantees that the **wave‑level seeds** are stable based on `encounter_seed`, and that shrine parameters are deterministic functions of `(realm_id, tier, stage_index)`.

---

## 4. Seed pipeline (RealmSeed)

**File:** `core/world/RealmSeed.gd`

Responsibility: turn high‑level campaign + realm info into deterministic seeds.

- `static func realm_seed(campaign_seed: int, realm_id: String, tier: int) -> int`  
  Combines the campaign seed, realm id, and tier into a single realm seed.
  - Same `(campaign_seed, realm_id, tier)` → same `realm_seed`.  
  - Different campaign seeds → different `realm_seed` (with extremely high probability).

- `static func stage_seed(realm_seed: int, stage_index: int) -> int`  
  Derives a stage seed from the realm seed and the stage index.
  - Same `(realm_seed, stage_index)` → same `stage_seed`.  
  - Each stage index gets its own deterministic sub‑seed.

These functions are **pure** and have no side effects, which makes them safe and testable.

**Tests:** `core/tests/realm/test_realm_generation.gd`

- Confirm that `realm_seed` and `stage_seed` are stable across repeated calls with the same input.
- Confirm that RealmGenerator uses them consistently to produce deterministic Realm layouts.

---

## 5. Realm generation (RealmGenerator)

**File:** `core/world/RealmGenerator.gd`

Entry point:

```gdscript
func generate(realm_id: String, tier: int, campaign_seed: int) -> RealmModel
```

High‑level steps:

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
   - Create a `StageModel`:
     - `index = i`  
     - `objective_type` (string key compatible with `CombatConstants`)  
     - `encounter_seed = stage_seed`  
     - `modifiers = {}`

   - Fill common modifiers:
     - `modifiers["fear_delta"]` from tier‑based scalars.

   - If `objective_type == "purify_shrine"`:
     - Use shrine helpers in `GameBalance_Realm` to derive:
       - `shrine_waves`
       - `shrine_hp_max`
       - `shrine_passive_drain_per_wave`
       - `purify_drain_reduction_mult`
       - `morale_drain_per_wave`
       - `shrine_reward_multiplier`
     - Store them in `modifiers`.

   - Append the `StageModel` to `realm.stages`.

5. **Return RealmModel**  
   - `current_stage_index = 0`  
   - `is_completed = false`  
   - `restored = false`

**Determinism properties:**

- Same `(campaign_seed, realm_id, tier)` → identical `RealmModel` (id, tier, seed, stages list, objective types, seeds, modifiers).  
- Different campaign seeds → typically different stage seeds and/or objective layouts.

**Tests:** `core/tests/realm/test_realm_generation.gd`

- `test_realm_generator_determinism` ensures two calls with the same inputs generate identical realms (including stage types, seeds, and modifiers).

---

## 6. RealmService — caching & active Realm

**File:** `core/services/RealmService.gd`

Responsibility: manage Realm instances, caching, and active selection.

Static fields:

- `_realms: Dictionary`  
  In‑memory cache keyed by a composite key (realm id + tier). Holds `RealmModel` instances.

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

  This implements the story’s “Realm JSON created and cached” requirement and centralizes instantiation.

- `set_active(realm: RealmModel) -> void`  
  Sets `_active_realm` to the provided Realm and ensures it also lives in the cache.

- `get_active() -> RealmModel`  
  Returns the current active Realm (or `null` if none is active).

- `complete_stage() -> Dictionary`  
  Handles “stage completion” behavior:

  - Reads the active Realm and its `current_stage_index`.  
  - Uses `RealmRewardCalc.stage_rewards(realm, stage)` for the current stage.  
  - Applies rewards via `EconomyService.apply_realm_stage_rewards`.  
  - Increments `current_stage_index`.  
  - If the last stage was just completed:
    - Adds `completion_rewards(realm)` and sets `is_completed = true`.  
  - Returns a summary `Dictionary` of total rewards and flags:

    ```gdscript
    {
        "ase_delta": int,
        "ekwan_delta": int,
        "relics": Array,
        "completed": bool,
    }
    ```

**Note:** In MVP, the cache key is `(realm_id, tier)`. This means:

- Within a single session, repeated calls with the same realm and tier share the same instance.  
- Cross‑campaign differentiation is provided by the campaign seed passed at generation time; caches are typically cleared when starting a new game via `/new_game`.

**Tests:** `core/tests/realm/test_realm_generation.gd`

- `test_realm_service_cache` asserts `get_or_create` returns the exact same instance when called twice with identical inputs.

---

## 7. Reward model (RealmRewardCalc)

**File:** `core/world/RealmRewardCalc.gd`

Responsible for computing **per‑stage** and **completion** rewards, including shrine multipliers.

### 7.1 Stage rewards

```gdscript
func stage_rewards(realm: RealmModel, stage: StageModel) -> Dictionary
```

Inputs:

- Realm meta: `realm.tier`, `realm.virtue`.  
- Stage meta: `objective_type`, `index`, `modifiers`.  
- Balance config: reward bases and tier scalars in `GameBalance_Realm`.

Typical output shape:

```gdscript
{
    "ase_delta": int,
    "ekwan_delta": int,
    "relic_roll": { "rarity": String, ... }?, # optional
}
```

Properties:

- Ase rewards are **always ≥ 1** on success (no zero‑reward wins).  
- Ekwan rewards are **never negative**.  
- Higher tiers (2, 3, …) pay **at least as much** as lower tiers for equivalent stages.  
- Shrine stages apply `stage.modifiers["shrine_reward_multiplier"]` on top of base reward curves to keep shrines slightly more rewarding than standard `combat_trial` stages.

### 7.2 Completion rewards

```gdscript
func completion_rewards(realm: RealmModel) -> Dictionary
```

- Provides a one‑time bonus when the last stage is completed.  
- Uses tier and stage count to derive additional Ase/Ekwan on top of per‑stage rewards.  
- All completion rewards are **non‑negative**.

### 7.3 Tests

**File:** `core/tests/realm/test_realm_rewards.gd`

Includes:

- `test_stage_rewards_non_negative`  
  - Asserts per‑stage Ase ≥ 1, Ekwan ≥ 0.

- `test_tier_scaling_monotonic`  
  - Confirms that for the same Realm and stage type:
    - Tier 2 Ase ≥ Tier 1 Ase  
    - Tier 3 Ase ≥ Tier 2 Ase  
    - Same monotonic constraint for Ekwan.

- `test_completion_rewards_non_negative`  
  - Confirms completion rewards are never negative.

These tests are intentionally **shape‑based**, not tied to specific numeric values, so you can retune curves without rewriting tests.

---

## 8. From stages to fights — ObjectiveRunner & CombatObjectives

Realms describe **what** the player will face. The **combat layer** decides **how** it is resolved.

### 8.1 ObjectiveRunner

**File:** `core/world/ObjectiveRunner.gd`

Entry point:

```gdscript
func run_stage(stage: StageModel, realm: RealmModel) -> Dictionary
```

MVP behavior:

- Builds a deterministic combat context based on:
  - `realm` (virtue, tier, id)  
  - `stage` (objective_type, encounter_seed, modifiers)

- Constructs generic **combat entities** (heroes, enemies, structures) via the combat layer. For shrine stages, this includes creating a **shrine entity** tagged as:

  ```gdscript
  ["ally", "structure", "objective", "objective:shrine"]
  ```

- Delegates objective logic to `CombatObjectives`:
  - For `objective_type == "combat_trial"` → uses the **defeat_enemies** objective.  
  - For `objective_type == "purify_shrine"` → uses the shrine‑aware objective that tracks shrine HP from modifiers and the shrine entity, including Purify hooks.

- On success, asks `RealmService.complete_stage()` for rewards and applies them to the economy.  
- Returns a summary `Dictionary` with:
  - `success: bool`  
  - `reason: String` (e.g. `"enemies_defeated"`, `"shrine_destroyed"`)  
  - `rewards: Dictionary` (per `RealmRewardCalc`)  
  - `snapshots: Array` (per‑round combat snapshots, see combat docs)

ObjectiveRunner is the **bridge** from Realm data into the generic CombatEngine pipeline.

### 8.2 CombatObjectives (overview from Realm’s perspective)

**File:** `core/combat/CombatObjectives.gd`

From the **realm** point of view:

- Realms provide:
  - `objective_type` (string)  
  - Stage modifiers (especially shrine keys)
- CombatObjectives provides:
  - End‑condition checks (`check_end`)  
  - Objective context building (`build_objective_context`) — e.g. which entity is the shrine, which entities count as defeat targets.  
  - Shrine‑specific behavior (HP tracking, Purify cooldown, wave success/failure) using the **same modifiers** described in this doc.

Realms never need to know about shrine HP math beyond setting the initial parameters in StageModel.

---

## 9. EnemyFactory realm‑aware packs

**File:** `core/combat/EnemyFactory.gd`

MVP function:

```gdscript
func spawn_realm_pack(realm: RealmModel, stage: StageModel) -> Array[Enemy]
```

Behavior:

- Uses `realm.id` and `realm.virtue` to determine which enemy profiles to use.  
- Examples:
  - `vale_of_dust` → “Dust Wraith” enemies.  
  - `shrouded_grove` → “Grove Seer” enemies.

This ensures combat logs reflect Realm flavor:

- `Dust Wraith #1`, `Dust Wraith #2` for Vale of Dust.  
- `Grove Seer #1`, etc. for Shrouded Grove.

Pack composition and stats can be tuned per realm and tier via config, without changing Realm generation.

---

## 10. Debug Console — Realm QA commands

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

  (Shrine‑specific keys like `shrine_hp_max` live in `StageModel.modifiers` and are not printed in this short summary, but can be inspected via debug dumps if needed.)

- `/realm enter [stage_index]`  
  - If index omitted → uses `current_stage_index`.  
  - Runs the stage through `ObjectiveRunner`.  
  - On success, prints something like:

    ```text
    [realm enter] stage=0 type=purify_shrine success=true
    [realm enter] rewards — Ase +22, Ekwan +14
    [realm enter] realm progress — current_stage=1/5, finished=false
    ```

- `/realm complete`  
  - Fast‑forwards all remaining stages using ObjectiveRunner, applying per‑stage rewards and a single completion reward.  
  - Prints a summary:

    ```text
    [realm complete] auto-completed 3 remaining stages. Ase +116, Ekwan +51, relics=1
    ```

- `/run_tests realms`  
  - Runs all Realm‑related test suites (generation, rewards, and generic combat entity tests; see §11).

These commands are the main QA and design tools for validating the Realm system without UI.

---

## 11. Tests & Definition of Done

### 11.1 Automated tests

**Files:**

- `core/tests/realm/test_realm_generation.gd`  
- `core/tests/realm/test_realm_rewards.gd`  
- `core/tests/combat/test_combat_generic_entities.gd` (shared with the combat epic but wired into `/run_tests realms`)

**Debug console integration:**

- `/run_tests realms`  
  Runs the realm test suites (generation + rewards + generic entity objective support).

- `/run_tests all`  
  Runs the economy tests via `TestRunner.run_all(true)` and then the realm tests.

**Generation tests cover:**

- Seed stability for `realm_seed` and `stage_seed`.  
- Determinism of `RealmGenerator.generate` for identical inputs.  
- Cache behavior of `RealmService.get_or_create`.

**Reward tests cover:**

- Non‑negative stage rewards (Ase ≥ 1, Ekwan ≥ 0).  
- Monotonic tier scaling (Tier 2/3 ≥ Tier 1/2).  
- Non‑negative completion rewards.

**Generic entity tests (realm + combat integration) cover:**

- That **shrine stages** correctly expose a shrine structure entity to the objective system via tags and modifiers.  
- That objectives like **defeat_enemies** and **protect_shrine** correctly **ignore allied structures** when counting defeat targets.  
- That shrine HP is tracked from StageModel modifiers and objective context without crashes.  
- That generic entity helpers (tags, objective roles) behave in a way compatible with realm‑driven stage definitions.

These tests are intentionally **shape‑ and behavior‑based**, not tied to specific numbers, so balance tuning does not break them.

### 11.2 Story‑level Definition of Done

For the story **“As the Keeper I want seeded Realms”**, this MVP implementation is considered done when:

- **Config & models**
  - `GameBalance_Realm` defines at least Vale of Dust and Shrouded Grove, with virtue and default tier.  
  - `RealmModel` and `StageModel` serialize to and from Dictionary without losing structure.  
  - `REALM_STAGE_COUNT` is 5 and used consistently.  
  - Shrine‑related modifiers are present for all `purify_shrine` stages.

- **Determinism**
  - Same `(campaign_seed, realm_id, tier)` → same Realm layout and stage seeds across runs.  
  - For a fixed stage, `encounter_seed` and shrine modifiers are stable.  
  - ObjectiveRunner + CombatEngine runs produce consistent combat logs and rewards for a fixed seed (within the combat harness determinism guarantees).

- **Progression & economy**
  - `RealmService.complete_stage` correctly advances `current_stage_index` and marks the Realm completed at the final stage.  
  - `RealmRewardCalc` ensures stage rewards and completion rewards are non‑negative and scale with tier.  
  - Ase and Ekwan rewards are applied via `EconomyService` and visible in the existing economy UI/debug panel.

- **Objective integration**
  - `ObjectiveRunner.run_stage` correctly maps realm `objective_type` values to combat objectives (defeat enemies, protect/purify shrine).  
  - Shrine stages correctly build a shrine objective context from StageModel modifiers and generic entity tags.  
  - Generic entity tests pass, proving Realms can feed future objectives (structures, escorts, multi‑objectives) without CombatEngine rewrites.

- **Debug/QA tooling**
  - `/realm list`, `/realm new`, `/realm show`, `/realm enter`, `/realm complete` all function without errors and produce readable logs.  
  - `/run_tests realms` runs green on generation, rewards, and generic entity tests.

---

## 12. Suggested QA script

For quick manual regression of Realms in the current MVP build:

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
   - Seeds are non‑zero.  
   - `current=0`, `finished=false`.

3. **Stage determinism**

   - Restart the game.  
   - Repeat `/new_game`, `/realm new vale_of_dust`, `/realm show`.  
   - Confirm stage table matches previous run (same seeds, objective types, fear deltas).

4. **Combat & rewards (combat_trial)**

   - Summon a few heroes, set a party.  
   - Run:

     ```text
     /realm enter
     ```

   - Verify:

     - `[realm enter] ... success=true`  
     - Ase/Ekwan rewards logged.  
     - `current_stage` increments in `/realm show`.

5. **Shrine stages (purify_shrine)**

   - Use `/realm new` (or cycle realms) until you have a realm with a `purify_shrine` stage early in the sequence.  
   - Enter that stage and play both waves.  
   - Confirm:

     - Shrine HP is logged as part of the combat summary.  
     - Shrine HP drops by passive drain each wave.  
     - Purify actions are logged and affect the effective drain according to config.  
     - Stage fails if shrine HP reaches 0 even if enemies are defeated.

6. **Realm completion**

   - Repeat `/realm enter` until finished.  
   - Confirm:

     - `current_stage == 5`  
     - `finished=true`  
     - Completion reward applied (Ase/Ekwan jump at last stage).

7. **Fast‑forward completion**

   - New game, new Realm.  
   - Call:

     ```text
     /realm complete
     ```

   - Confirm:

     - `auto-completed N remaining stages`  
     - Ase/Ekwan totals are plausible and non‑negative.  
     - `/realm show` reports `current=5`, `finished=true`.

8. **Enemy flavor**

   - Confirm that Vale of Dust uses “Dust Wraith” enemies, Shrouded Grove uses “Grove Seer” enemies, and that this stays consistent across runs with the same campaign seed.

9. **Tests**

   - Run:

     ```text
     /run_tests realms
     ```

   - Ensure all suites (generation, rewards, generic entities) report PASS for their checks.

If any of these steps diverge from the expectations here, the bug should be traced through the chain: `GameBalance_Realm` → `RealmSeed` → `RealmGenerator` → `RealmService` → `ObjectiveRunner` → `CombatObjectives` → `EnemyFactory` → `EconomyService`.