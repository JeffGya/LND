

# Invisible Grid Combat — MVP Design

## 0. Purpose & Scope

This document defines an **“invisible grid” combat layer** for Echoes MVP.

The grid is **not visualized in UI yet** — it only exists in simulation and debug logs — but it:

- Gives us a consistent way to talk about **position, distance, and lanes**.
- Powers more interesting objectives like **Protect Totem** without turning the game into a full tactics game.
- Lets existing objectives (**Combat Trial**, **Purify Shrine**) gain spatial flavor and future hooks (movement, interception, “slipping past the line”, etc).

This doc is **design only**. Implementation will be done via a follow‑up story and subtasks.


## 1. High‑Level Goals & Constraints

### 1.1 Goals

- Add **lightweight spatial structure** to combat:
  - Who is closer to whom?
  - Who is between the enemy and the objective?
  - Who gets to the Totem/Shrine first?

- Keep combat **auto‑battler style**:
  - No player input or grid UI.
  - Heroes and enemies act automatically based on simple rules.

- Use one **shared spatial model** for:
  - Combat Trials (defeat enemies).
  - Purify Shrine (protect static shrine vs waves).
  - Protect Totem (static or carriable objective).

- Ensure the model is:
  - **Simple enough** for MVP.
  - **Extensible** for post‑MVP (positional abilities, flanking, cover, etc).

### 1.2 Constraints & Non‑Goals (MVP)

- No manual movement commands from the player.
- No fine‑grained pathfinding (A* etc); we use **simple lane movement**.
- No UI representation yet — only **debug_console logs**.
- No complex terrain (walls, diagonals, height). The board is abstract:
  - Think “rows / lanes” rather than a full tactical map.

- We do **not** redesign the entire CombatEngine:
  - We extend existing step‑based rounds.
  - We keep CombatEntities, CombatObjectives, and CombatEmotionSystem intact and **add** spatial fields/helpers.


## 2. Mental Model: Lanes on a Small Grid

To avoid over‑engineering a full 2D tactics grid, MVP uses a **lane grid**:

- The battlefield is a small grid of **columns (x)** and **rows (y)**:
  - `x` increases from **allies (left)** to **enemies (right)**.
  - `y` indexes **lanes** (front/mid/back, or simply row 0, 1, 2, …).

- Typical MVP board:
  - `BOARD_COLS = 6` (0–5)
  - `BOARD_ROWS = 3` (0–2)

- Side conventions:
  - **Allies**: spawn on the **left** side (`x = 0–1`).
  - **Enemies**: spawn on the **right** side (`x = 4–5`).
  - **Objectives**:
    - Shrine: usually near allies’ backline.
    - Totem (static): similar to Shrine.
    - Totem (carried): shares position with its carrier.

- Distance is computed via **Manhattan distance**:
  - `distance(a, b) = abs(ax - bx) + abs(ay - by)`
  - **Melee range** = 1 (adjacent cells).
  - Future: support **ranged** attacks via larger ranges.


## 3. Data Model Changes

### 3.1 Board & Position Types

We add a lightweight representation of positions:

- Each combat entity gets:
  - `grid_pos: Vector2i` (or `{ x: int, y: int }`)

- The board state is tracked by CombatEngine / CombatState:
  - `board_cols: int`
  - `board_rows: int`
  - Optional helper maps:
    - `entity_by_cell[(x, y)] -> entity_id`
    - Or just `find_entities_at(x, y)` helpers.

### 3.2 Placement Tags & Metadata

Existing **CombatEntities** already use tags. We add spatially relevant tags:

- Team tags (existing concept, clarified):
  - `"ally"`
  - `"enemy"`

- Objective tags:
  - `"objective"`
  - `"objective:shrine"`
  - `"objective:totem"`

- Structural tags:
  - `"structure"` (for static shrine/totem)
  - `"carried"` (for carried totem)

- Spawn/AI hints (optional, mostly config‑driven):
  - `"spawn_lane:front"` / `"spawn_lane:mid"` / `"spawn_lane:back"`
  - `"role:totem_hunter"` for enemies that prefer the Totem.

### 3.3 Objective Types (Recap)

CombatConstants / CombatObjectives now have:

- `OBJECTIVE_DEFEAT_ENEMIES` (Combat Trial).
- `OBJECTIVE_PROTECT_SHRINE` (Purify Shrine).
- `OBJECTIVE_PROTECT_TOTEM` (new).

All objectives will **share** the invisible grid, but differ in:

- Initial placements.
- Movement/targeting priorities.
- Win/fail conditions.


## 4. Board Setup Per Objective

The **ObjectiveRunner** (or equivalent orchestration) configures the board at stage start.

### 4.1 Shared Board Defaults

Per stage:

- Decide:
  - `board_cols` (usually 6).
  - `board_rows` (usually 3).
  - `ally_spawn_columns` (e.g. 0–1).
  - `enemy_spawn_columns` (e.g. 4–5).
  - Objective positions (if present).

- Assign heroes and enemies to cells:
  - Heroes:
    - Fill allies’ side from **front row outward**, or using party order.
  - Enemies:
    - Fill enemies’ side similarly; may reserve certain rows for “totem hunters” in Protect Totem.

- Keep placement deterministic for tests:
  - Use ordered lists and simple rules:
    - Row cycling: 0, 1, 2, 0, 1, 2, …
    - Or front‑first: fill front row, then mid, then back.

### 4.2 Combat Trial (OBJECTIVE_DEFEAT_ENEMIES)

- No shrine or totem.
- Setup:
  - Heroes on left (cols 0–1).
  - Enemies on right (cols 4–5).
- Purpose:
  - Simple **line clash**.
  - Establishes the default behaviors for movement and targeting.

### 4.3 Purify Shrine (OBJECTIVE_PROTECT_SHRINE)

- Entities:
  - Shrine: `"ally", "structure", "objective", "objective:shrine"`.
- Placement:
  - Shrine at allies’ backline, middle row:
    - e.g. `grid_pos = (0, 1)` or `(1,1)` depending on taste.
  - Heroes in front / around the Shrine:
    - e.g. `(1, 0)`, `(1,1)`, `(1,2)`.

- Wave spawn:
  - Each wave spawns enemies at the **right‑most columns**.
  - Rows may be:
    - Evenly spread across rows.
    - Or focused on a central lane.

- Behavior:
  - Some enemies target heroes.
  - Some, especially if enemies > heroes, prioritize pathing towards the Shrine.
  - Movement and target selection will be shared with Protect Totem (see below).

### 4.4 Protect Totem (OBJECTIVE_PROTECT_TOTEM)

Two variants share the same underlying grid:

#### Variant A — Static Totem (60%)

- Totem entity:
  - `"ally", "structure", "objective", "objective:totem"`.
- Placement:
  - Similar to Shrine:
    - e.g. `grid_pos = (0, 1)` or `(1,1)`.
- Heroes:
  - Form a **screen** in front of the Totem, as with Shrine.

#### Variant B — Carriable Totem (40%)

- Totem entity:
  - `"ally", "objective", "objective:totem", "carried"`.
- Placement:
  - The Totem’s initial position equals a chosen carrier’s position (e.g. the party leader or random hero).
- Carrier:
  - The carrier gains a **burden debuff** (tuned via GameBalance_HeroCombat).
  - All damage targeting the Totem is redirected to the carrier, except during pass invulnerability (see section 6.3).

Both variants use the same:
- Grid size.
- Basic movement model.
- Enemy targeting rules (excess enemies aim for the Totem).


## 5. Movement & Range Model

The invisible grid extends our **step‑based rounds** with optional movement.

### 5.1 Distance & Ranges

- Distance:
  - `dist(entity_a, entity_b) = |ax - bx| + |ay - by|`
- Ranges:
  - **Melee**: `dist <= 1`.
  - **Contact with objective** (Shrine/Totem): also `dist <= 1`.

### 5.2 Per‑Turn Movement (MVP)

For each acting entity on its turn:

1. **Decide intent** (unchanged high‑level behavior):
   - ATTACK best target.
   - GUARD ally/objective.
   - PURIFY_SHRINE (if available).
   - PASS_TOTEM (Protect Totem, variant B only).
   - REFUSE (if fear/morale logic says so).

2. **Check range**:
   - If chosen action requires adjacency (ATTACK, GUARD, PURIFY_SHRINE, PASS_TOTEM) and no valid target is in range:
     - Move 1 cell toward the intended target (see pathing below).
     - Action **fails** this turn (movement only), or becomes a **MOVE + intent** log line for clarity.
   - If in range:
     - Perform the action as usual.

This ensures movement is **incremental** and the battle log gains a sense of **closing distance and interception**.

### 5.3 Simple Pathing

- Pathing is **greedy Manhattan**:
  - Prefer reducing `|ax - tx|` (horizontal distance) first.
  - If horizontal distance is 0, then move vertically toward the target (`|ay - ty|`).
- If the desired cell is occupied:
  - Option A (MVP): skip movement (unit “stutter steps”).
  - Option B (slightly fancier, maybe post‑MVP): try a nearby lane instead.

For MVP, **Option A** is acceptable; log will show when entities are blocked.

### 5.4 Board Boundaries

- Entities cannot move outside `0 <= x < board_cols`, `0 <= y < board_rows`.
- Enemies are generally constrained to move **leftwards**; allies mostly **rightwards** (unless fleeing, post‑MVP).


## 6. Objective‑Specific Logic on the Grid

### 6.1 Combat Trial

- Movement:
  - Both sides move toward the nearest enemy until in melee.
  - Once engaged, they mostly stay in place (unless their target dies, then they re‑target and move again).
- Targeting:
  - Existing “pick target” logic is enhanced by spatial filters:
    - Prefer enemies in melee range.
    - Otherwise, prefer nearest enemy (by distance), with tie‑breakers (HP, role, etc).
- Logging:
  - New log lines can show movement:
    - `Joseph Ofori steps toward Grove Seer #1 (1,1 → 2,1)`.

### 6.2 Purify Shrine

- Shrine placement (static structure) defines a **defensive anchor**.
- Enemy behavior:
  - If `enemy_count > hero_count`, “excess” enemies prioritize the Shrine:
    - They move along shortest path towards the Shrine’s cell.
  - Others behave like Combat Trial (target front‑line heroes).
  - It is not possible to attack the shrine past a hero. No line of sight then target closet hero.
- Hero behavior:
  - Heroes may form a “wall” in front of the Shrine.
  - If a hero GUARDs the Shrine, the Shrine gains guard stacks (as already implemented logically).

- Failure condition:
  - Shrine HP <= 0.
- Success:
  - All waves cleared, Shrine HP > 0.

Spatially, this creates situations like:
- “Grove Seer #2 slips past the front line and reaches the Shrine lane” (post‑MVP log flavor).
- “Rahama steps back to guard the Shrine.”

### 6.3 Protect Totem

#### Shared Behavior (Static + Carried)

- Objective type: `OBJECTIVE_PROTECT_TOTEM`.
- Failure:
  - Static Totem: totem_hp <= 0.
  - Carried Totem: totem_hp <= 0 or carrier dies while totem is “exposed” (depending on how we model HP vs carrier; see below).
- Success:
  - Survive N rounds with Totem intact.

#### Enemy Assignment

- If `enemies_alive > heroes_alive`:
  - Compute `extra = enemies_alive - heroes_alive`.
  - Assign `extra` enemies as **totem hunters**:
    - Priority target: Totem (or its carrier).
    - They move towards the Totem using greedy Manhattan movement each turn.
  - Remaining enemies act like standard combat (attack heroes).

#### Static Totem Variant

- Totem entity:
  - `hp`, `max_hp`, low `def`.
  - Tags: `"ally", "structure", "objective", "objective:totem"`.
- Placement:
  - Similar to Shrine (`grid_pos = (0,1)` or `(1,1)`).
- Hero interactions:
  - GUARD on Totem adds guard stacks (same as Shrine).
- Enemy behavior:
  - Totem hunters move straight toward the Totem.
  - When adjacent, they ATTACK the Totem for **increased damage**:
    - `damage_to_totem = base_damage * totem_damage_multiplier[tier]`.

#### Carried Totem Variant

- Totem entity:
  - Tags: `"ally", "objective", "objective:totem", "carried"`.
  - Logical HP is tracked on the Totem, but its position **follows the carrier**:
    - `totem.grid_pos = carrier.grid_pos` each step.

- Burden debuff (MVP suggestion):
  - While carrying:
    - -ATK% and/or -AGI%.
    - Optional: +fear gain per round.

- Passing the Totem:
  - Action: `PASS_TOTEM(target_hero)` available only when:
    - Totem is carried.
    - `pass_cooldown == 0`.
    - Target hero is alive and in range (MVP: melee range only).
  - Effects:
    - This turn: Totem is **invulnerable** (spirit displacement).
    - Next turn:
      - Totem is now “attached” to the recipient.
      - Burden debuff moves from old carrier to new carrier.
    - `pass_cooldown` resets to a configured value (e.g. 2–3 rounds).

- Damage model:
  - Easiest MVP option:
    - All damage that “would hit” the Totem instead hits the carrier’s HP.
    - Totem has implicit HP modeled via objective summary (tracked separately).
  - Slightly richer option:
    - Attacks targeting Totem reduce Totem HP directly, but Totem position is the carrier’s position.

For MVP, the **redirected damage → carrier** is simpler, and we can derive “damage_taken_by_totem” from event tags.

#### Reward Logic (Relic Drop)

- Only for **carriable** variant.
- After victory:
  - Compute `damage_fraction = damage_taken_by_totem / max_totem_hp`.
  - Chance:
    - `chance = BASE_REWARD_CHANCE - damage_fraction * PENALTY_MULTIPLIER`
    - Clamp to `[0, 0.30]` as per your note (base chance below 30%).
  - Drop a relic representing the Totem if RNG succeeds.

- This encourages:
  - Smart guarding / passing.
  - Minimizing Totem exposure and damage.


## 7. Emotion & Cinematic Logging Hooks

### 7.1 Morale / Fear

For MVP:

- We **reuse CombatEmotionSystem** as‑is, but we can:
  - Add optional per‑round adjustments for perfect defense:
    - e.g. “No damage to Totem this round” → small morale boost.
  - Mirror Shrine behavior if/when desired.

These are small tweaks on top of existing emotion tuning.

### 7.2 Debug / Narrative Logs

Since there is no UI yet, logs must make the grid **feel real**:

- Movement examples:
  - `Joseph Ofori steps toward Dust Wraith #1 (1,1 → 2,1)`
  - `Dust Wraith #2 advances down the mid lane toward the Shrine`

- Objective interactions:
  - `Kojo Appiah moves to guard the Totem`
  - `Akuaaa Addo passes the Totem to Kingsley Donkor (invulnerable this round)`

- Failure / success summaries:
  - `Protect Totem — success: waves=2/2, totem_hp=43/100`
  - `Protect Totem — failure: totem destroyed on round 5`

These logs should be consistent across objectives and will help future UI work.


## 8. MVP vs Post‑MVP Features

### 8.1 MVP (Target for This Story)

Implement:

- Core grid model:
  - Positions on a small lane grid.
  - Greedy Manhattan movement (1 cell/turn).
- Shared board setup per objective (trial, shrine, totem).
- Static Totem and carried Totem variants:
  - Tags, HP, burden debuff, pass cooldown.
- Enemy objective logic:
  - Excess enemies target Shrine/Totem.
  - Damage multiplier vs Totem.
- Simple relic drop chance for carried Totem (using damage taken).
- Basic spatial logging.

Refactor:

- Combat Trial → uses grid for placement and movement/targeting.
- Purify Shrine → uses grid for Shrine placement, wave spawn, and AI targeting.
- New Protect Totem objective → designed explicitly around the grid.

### 8.2 Post‑MVP Extensions (Not in Scope Now)

Ideas that the grid naturally enables but are **out of scope** for this story:

- Advanced AI behaviors:
  - Intercept passes.
  - Feints (pretend to charge Shrine, then peel off to heroes).
  - Coordinated pincer moves across lanes.

- Positional mechanics:
  - Flanking bonuses (attack from side/rear).
  - Zone of control (blocking movement past a front line).
  - Cover / obstacles / choke points.

- Richer actions:
  - Dashes, pulls, pushes, knockback.
  - Area‑of‑effect attacks based on cell neighborhoods.

- UI:
  - Visual board representation.
  - Hover tooltips showing “distance to objective”, etc.

The MVP grid is intentionally **minimal** so that these can be layered on later without redoing core combat.


## 9. Integration Checklist

This section is for future subtasks; it’s not implementation, but a checklist.

- [ ] Extend CombatEntities with `grid_pos` and helper functions.
- [ ] Add grid configuration to GameBalance / objective configs (board size, spawn columns).
- [ ] Implement board setup in ObjectiveRunner for:
  - [ ] Combat Trial
  - [ ] Purify Shrine
  - [ ] Protect Totem (static + carried)
- [ ] Add movement step to CombatEngine’s per‑actor processing.
- [ ] Update enemy target selection to respect objectives and grid distance.
- [ ] Implement Totem burden / pass logic (carried variant).
- [ ] Implement Totem damage multiplier and relic reward chance.
- [ ] Enhance combat logs with spatial lines.
- [ ] Add tests for:
  - [ ] Basic placement (heroes on left, enemies on right, objectives in correct cell).
  - [ ] Movement toward targets.
  - [ ] Enemies preferring Totem/Shrine when outnumbering heroes.
  - [ ] Pass cooldown and invulnerability behavior.

This doc is the **source of truth** for how the invisible grid should behave across all current objectives (Combat Trial, Purify Shrine, Protect Totem) in the MVP.