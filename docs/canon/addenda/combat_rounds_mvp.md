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

## 5.3 Readable Combat Logs (MVP Final)

**Canon Link:** LND §3, §4, §9, §12  
**User Story:** *As the Keeper I want readable combat logs*

**Directive:** Every combat **action** must produce **exactly one single-line** entry.

**Line shape (canonical):**
```
<actor> <VERB> → <target?> <payload> <tags…>
```
- If there is **no target**, omit the arrow.
- The output is **deterministic** and driven entirely by config.

**Loggable verbs (MVP):** `ATTACK`, `GUARD`, `REFUSE`, `KO`, `TICK`  
(Controlled via `LOG_ACTIONS` in `core/config/GameBalance_HeroCombat.gd`.)

**Payload mapping:**
- `ATTACK` → `dmg=<N>`
- `GUARD` → `(+shield[=<N>])`
- `REFUSE` → `(fear_refusal, fear=<N>)` or `(morale_refusal, morale=<N>)`
- `KO` → no extra payload (0 HP is conveyed by the tag)
- `TICK` → `(round_tick)`

**Tags (order intent):**
1. **HP/status** — `[hp/max]` (e.g., `[29/40]`, or `[0/40]` when KO)
2. **Guard** — `[guard=<N>]` (only when `N>0`)
3. **Breakdown** — `[ATK <A> → DEF <D>]` (designer view)

> Tag visibility and presence are controlled **via verbosity profiles**.

**Verbosity profiles & overrides:**
- Declared in `GameBalance_HeroCombat.gd` under **COMBAT LOGGING (MVP)**:
  - `LOGGING_PROFILES` → named profiles: `"mvp"`, `"designer"`, `"qa"`
  - `LOG_PROFILE` → selects the active profile
  - `LOG_OVERRIDE_SHOW_HP | _SHOW_GUARD | _SHOW_DMG_BREAKDOWN | _SHOW_INTERNAL` → per-flag hot overrides
- Effective flags are resolved in the logger and applied uniformly.

**Examples (designer profile):**
```
Kobi Gyasi ATTACK → Training Wraith #1 dmg=8 [32/40] [ATK 12 → DEF 4]
Training Wraith #2 GUARD → Training Wraith #1 (+shield) [guard=1] [18/40]
Sarah Danquah REFUSE (fear_refusal, fear=80)
```

**MVP vs Designer behaviors:**
- **mvp** → only HP tags; no guard stack; no ATK→DEF breakdown.
- **designer** → HP + guard + ATK→DEF breakdown.
- **qa** → same as designer; reserved for future internal tags (rolls/seed crumbs).

**Definition of Done (logs):**
- Each **loggable** action yields **one** line; non-loggable actions yield **none**.
- No blank lines; no `[guard=0]` tags; ordering is `HP → Guard → Breakdown` when visible.
- Flipping any profile/override changes all lines on next run without code edits.

**QA quick checks:**
1. Set `LOG_PROFILE="mvp"` → attack lines show `dmg` + `[hp/max]` only.
2. Set `LOG_PROFILE="designer"` → guard + breakdown tags appear.
3. Set `LOG_OVERRIDE_SHOW_DMG_BREAKDOWN=false` (designer) → breakdown tag disappears, guard remains.
4. Force refusal (`/fear_set <id> 80`) → `REFUSE (fear_refusal, fear=80)` single-line entry appears.

## 5.4 Purify Shrine as Combat Scenario (MVP Layout)

**Canon Link:** LND §4 Core Mechanics, §6 Realm Structure, §8 Economy, §9 Combat  
**User Story:** *As the Keeper I want an actual shrine to protect, purify action and enemies that attack the shrine.*  
**Epic:** Combat Simulation Core

Purify Shrine is a **realm objective** that becomes a specific kind of combat encounter:

- Realm side (already implemented) seeds shrine HP, passive drain per wave, morale drain, reward multiplier and wave count.  
- Combat side (this epic) represents the shrine as a special combat entity, gives enemies a shrine-focused targeting bias, and exposes a **Purify** action that can soften shrine drain at the right time.

### 5.4.1 Inputs from Realm Balance

Realm-side numbers live in `core/config/GameBalance_Realm.gd` under the `PURIFY_SHRINE` block. Combat and ObjectiveRunner should treat these helpers as the single source of truth:

- `get_purify_shrine_hp(tier)`  
  → Max shrine HP for the stage tier (e.g. 100/135/170).  
- `get_purify_shrine_passive_drain_per_wave(tier)`  
  → How much shrine HP is lost automatically **between waves** (the coarse “timer”).  
- `get_purify_morale_drain(tier)`  
  → Morale loss per wave for participating heroes; drives EmotionService and refusal pressure.  
- `get_purify_reward_mult(tier)`  
  → Ase/Ekwan reward multiplier for shrine stages.  
- `get_purify_shrine_drain_reduction(tier)`  
  → Effective Purify **drain reduction multiplier** for this tier, combining combat base + tier scalar.  
- `get_purify_shrine_hp_threshold_fraction(tier)`  
  → Shrine HP fraction at which Purify becomes available (more forgiving on low tiers, harsher on high tiers).  
- `get_purify_shrine_max_purify_per_wave(tier)`  
  → Maximum number of successful Purify uses per wave for this tier.

This keeps **tier scaling** in Realm, while Combat stays tier-agnostic and only asks “what are my knobs for this stage?”.

### 5.4.2 Combat-Side Shrine Knobs

Combat-global shrine tuning lives in `core/config/GameBalance_HeroCombat.gd` under the **PURIFY SHRINE (combat tuning)** section:

- `SHRINE_ENEMY_DAMAGE_MULTIPLIER`  
  → Enemies deal slightly **more damage** to the shrine than to heroes (e.g. 1.2×), making focused shrine attacks feel threatening.  
- `SHRINE_PURIFY_BASE_DRAIN_REDUCTION`  
  → Base fraction of shrine passive drain that remains after a successful Purify on a wave (e.g. 0.5 = 50% of normal drain). Tier scalars from Realm adjust this up/down.  
- `SHRINE_PURIFY_BASE_HP_THRESHOLD_FRACTION`  
  → Base shrine HP fraction where Purify becomes available (e.g. 0.5 = below 50% HP); Realm may shift this by tier.  
- `SHRINE_PURIFY_COOLDOWN_ROUNDS`  
  → Global per-hero cooldown in rounds after using Purify (same across tiers).  
- `SHRINE_MAX_PURIFY_PER_WAVE_BASE`  
  → Base cap on how many Purify uses can succeed per wave across all heroes (e.g. 1). Realm can tighten this per tier.

Together, Realm + Combat form a two-layer dial:

- Combat describes **what Purify is** and how shrine damage behaves in general.  
- Realm describes **how intense** shrine stages feel at each tier by scaling those knobs.

### 5.4.3 Shrine as a Combat Entity (Design Target for MVP)

In shrine stages, the combat layer treats the shrine as a special allied unit:

- Has `hp_current` and `hp_max` seeded from `get_purify_shrine_hp(tier)`.  
- Marked with an `is_shrine` flag so AI and logs can recognize it.  
- Does **not** act (no major/minor actions) — it is an object to defend, not a participant.  
- Appears in combat state and logs so the Keeper can track its HP over time.

Enemy AI for these stages:

- If the objective is `purify_shrine` and the shrine is alive, ATTACK actions **default to the shrine** as their primary target.  
- Damage against the shrine uses the normal damage pipeline, then multiplies by `SHRINE_ENEMY_DAMAGE_MULTIPLIER`.  
- If the shrine is destroyed, enemies fall back to normal hero-targeting behavior.

End condition (MVP target):

- If shrine HP ≤ 0 at any point → immediate failure with reason `"shrine_destroyed"`, even if heroes are still standing.  
- Success requires clearing all configured waves **and** keeping the shrine alive.


### 5.4.4 Purify Action & Wave Drain

Purify is a **support action** that manipulates shrine drain rather than dealing damage:

- Only available if the current objective is `purify_shrine`.  
- Only offered when shrine HP is below the tier-specific threshold from `get_purify_shrine_hp_threshold_fraction(tier)`.  
- Has a per-hero cooldown of `SHRINE_PURIFY_COOLDOWN_ROUNDS` rounds.  
- Once a hero successfully uses Purify on a wave, that wave is marked as `wave_purified = true` and the passive drain applied between waves is reduced using `get_purify_shrine_drain_reduction(tier)`.  
- At most `get_purify_shrine_max_purify_per_wave(tier)` successful Purify actions may occur per wave across all heroes.

Intended feel:

- Early tiers: Purify unlocks earlier and is relatively strong, giving the Keeper a forgiving safety valve.  
- Later tiers: Purify unlocks later and is weaker, increasing tension unless the Keeper invests in heroes/sanctum that bolster Purify-related stats.


#### 5.4.4.1 MVP Purifier Assignment & Cooldown Logic (Final)

MVP introduces an **auto-designated purifier** system:

- At the *start of a Purify Shrine stage*, CombatEngine automatically selects exactly **one** hero to serve as the **Purifier** for the entire stage.
- Selection heuristic is defined in `GameBalance_HeroCombat.gd` via scoring weights:
  - Higher **Faith** → higher score
  - **Devout** archetype → score bonus  
  (Weights tunable in config.)
- Only the designated purifier is allowed to use `PURIFY_SHRINE`.
- Other heroes will *never* attempt Purify and will behave normally.

**Cooldown & usage rules (final MVP behavior):**

- Purify has a **global per-wave cap** (configurable): only a limited number of successful Purify uses may occur each wave.
- Individual purifier has a **round-based cooldown** (`SHRINE_PURIFY_COOLDOWN_ROUNDS`).
- Purify creates a **temporary reduction stack** for this wave only; stacks expire at the end of the wave.
- Purify never restores shrine HP — it only *reduces that wave’s post-wave drain*.

This matches the implemented behavior and provides predictable support pressure without introducing multi‑hero Purify clutter.

### 5.4.5 Interaction with Morale & Fear

Shrine stages are deliberately tuned to feel **emotionally heavy**:

- `get_purify_morale_drain(tier)` applies morale penalties between waves, pushing heroes toward SHAKEN/BROKEN over time.  
- Concentrated damage on one object (the shrine) tends to trigger more **fear-related refusal** as KO events and bad rounds stack up.  
- The Keeper’s choice to spend a Purify (and when) directly affects how long heroes must endure under pressure.

This keeps shrine encounters aligned with the core canon loop:

- **Guidance > Control:** the Keeper chooses the party and whether to Purify; Echoes still respond to fear and morale.  
- **Legacy > Grind:** shrine failures feed into Faith and story, not just numeric loss.

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

### 8.1. Future: Keeper-chosen purifier (post-MVP)

For MVP, Purify Shrine battles auto-designate a single hero as the **purifier**.
Only this hero will use the `PURIFY_SHRINE` command; the rest of the party
focuses on defending both the shrine and that purifier.

A preferred post-MVP upgrade is to let the **Keeper** explicitly choose which
hero will act as purifier at the start of the shrine stage. This creates a
strong "protect the purifier" dynamic (who do you trust to guard the flame?)
and gives more strategic weight to party composition.

One possible progression:
- Early realms: auto-selection only (current behavior).
- Later, more demanding realms: unlock Keeper choice of purifier as an active
  decision before the shrine waves begin.


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