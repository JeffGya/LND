# Emotion & Morale Core — MVP

> Canon addendum for: **Emotion & Morale Core**  
> Links: `HeroesIO`, `EmotionService`, `CombatEngine`, `ObjectiveRunner`, `GameBalance_Realm`, `realms_mvp.md`, `combat_mvp.md`

This document defines the **MVP emotional model** for Echoes of the Sankofa:

- What emotional variables we track.
- Where they live in data / services.
- How realms, shrine, combat (and later Sanctum) are allowed to change them.
- How emotions *inform* hero attributes over time (summoning + growth), in line with the GDD.

It is the canonical reference for the “Emotion & Morale Core” epic.

---

## 1. Emotional variables

### 1.1 Core tracked values (per hero)

MVP tracks two explicit emotional stats for each hero:

- **Morale**
  - Fields:
    - `morale_base` — the hero’s “resting” morale when safe.
    - `morale_current` — the live value used in combat and decisions.
  - Range: **0–100**
  - Interpretation (MVP guidelines):
    - `0–20`: on the edge of breaking / exhausted.
    - `21–40`: shaken, worn down.
    - `41–70`: steady baseline.
    - `71–100`: highly motivated, fired up.

- **Fear**
  - Fields:
    - `fear_current` — live threat load / lingering fear.
  - Range: **0–100**
  - Interpretation:
    - `0–10`: calm / unshaken.
    - `11–40`: wary, tense.
    - `41–70`: very stressed, on edge.
    - `71–100`: deeply afraid, panic risk.

### 1.2 Not tracked in MVP

- No additional numeric emotions beyond morale and fear.
- No per-hero Faith/Harmony/Favor copies.
- No long-term trauma flags (future epics may derive this from emotional history).

---

## 2. Relationship to Faith / Harmony / Favor

Emotions live inside the larger **Faith ↔ Harmony ↔ Favor** triangle defined in the core GDD.

For MVP:

- **Faith**
  - Represents campaign belief in the Keeper’s path.
  - Does not directly modify morale/fear.
  - Conceptually shapes what “normal” morale looks like.
  - Future epics may use Faith as:
    - A buff to morale recovery.
    - A resistance to fear spikes.

- **Harmony**
  - Represents relational health of party + Sanctum.
  - No direct effect in MVP.
  - Future: may gate max morale, fear resistance, or recovery rate.

- **Favor**
  - Sanctum ritual currency.
  - No direct effect in MVP.
  - Future: rites will spend Favor → EmotionService adjustments.

**Canon rule:**  
Faith/Harmony/Favor do not directly change `morale_current` or `fear_current` in MVP. They can influence these indirectly through future systems that call EmotionService.

---

## 3. Ownership, lifecycle, and persistence

### 3.1 Ownership

- **Data owner (per hero):**  
  `HeroModel` (core/models/HeroModel.gd) is the canonical data holder of emotion fields:
  - `morale_base: int`
  - `morale_current: int`
  - `fear_current: int`  
  `HeroesIO` and `SaveService` are responsible for persisting these fields.

- **Logic owner (global):**  
  `EmotionService` manages:
  - Internal hero emotion map.
  - All getters & setters.
  - Clamping, logging, and emotion helpers.  
  EmotionService is bootstrapped at startup alongside other core services and rebuilt from HeroModel data on load.

**Strict rule:**  
No system may directly modify HeroModel emotion fields.  
All updates must go through EmotionService.

### 3.2 Lifecycle

1. **On Hero Creation (Summoning / Starter)**
   - `morale_base` initialized to the canonical baseline (e.g. ~60) with possible archetype variation.
   - `morale_current = morale_base`.
   - `fear_current` starts low (e.g. 0–10).
   - Emotional state seeds later attribute tendencies (see section 6).

2. **During Play**
   - **Combat:** reads emotions at start, outputs deltas at end.
   - **Purify Shrine:** applies morale drain per wave.
   - **Realm stages:** apply fear_delta after stage resolution.
   - **Sanctum (future):** actions modify emotional state via EmotionService.

3. **On Save/Load**
   - All emotion fields saved in HeroModel.
   - On load, EmotionService rebuilds state from heroes.  
   After load, EmotionService re-registers all heroes based on the loaded HeroModel data so in-memory state matches the save.
   - No silent resets.

---

## 4. EmotionService — conceptual API

### 4.1 Query

```
get_morale(hero_id) -> int
get_fear(hero_id) -> int
```

### 4.2 Generic write

```
apply_delta(hero_id, morale_delta, fear_delta, source)
```

Behavior:

1. Look up hero.  
2. Apply deltas.  
3. Clamp to 0–100.  
4. Write back to HeroModel + internal map.  
5. Log one compact line.

### 4.3 Shrine helper

```
apply_shrine_morale_drain(party_ids, amount, realm_id)
```

Applies `-amount` morale to each hero.

### 4.4 Realm helper (MVP)

```
apply_realm_fear_delta(party_ids, fear_delta, ctx)
```

Simple additive fear.

### 4.5 Combat result helper

```
apply_combat_result(payload: Dictionary)
```

Expects a `payload` dictionary containing a `"heroes"` dictionary with per-hero `morale_delta` and `fear_delta`. For each hero, it forwards the deltas to `apply_delta`.

### 4.6 Determinism

Emotion evolution must be deterministic given:

- Campaign seed  
- Hero identity  
- Event sequence  

---

## 5. Allowed emotional effects (read/write rules)

### 5.1 Who can read?

- Combat engine
- Realm/shrine logic
- Sanctum (future)
- UI / debug tools

### 5.2 Who can write?

Only via EmotionService:

- Combat (end-of-battle deltas)
- Purify Shrine (wave drains)
- Realm stages (fear deltas)
- Debug tools

Forbidden:  
Direct manipulation of `HeroModel.morale_current` / `fear_current`.

### 5.3 Magnitude guidelines

- **Combat:** small/medium deltas (±1–10).  
- **Shrine:** medium hits (morale_drain_per_wave).  
- **Realm:** modest fear_delta per stage.  

Emotions should shift noticeably over 1–3 battles but not break a hero permanently.

---

## 6. Emotions and hero attributes / progression

### 6.1 High-level principle

Emotions influence how heroes **grow**, **perform**, and **evolve**, in line with GDD values:  
*Legacy > Grind* and *Guidance > Control*.

**MVP rule:**

- Emotional state is allowed to **inform**:
  - Attribute initialization ranges (summoning)
  - Attribute growth distribution (future epics)
  - Trait/perk unlocking patterns

But the formulas live in the summoning / growth epics and must reference EmotionService and this doc.

### 6.2 Practical rules for other epics

When attributes need emotional influence:

1. They **read** emotions from EmotionService.
2. They **do not** track their own emotion copies.
3. Adjustments must be:
   - Small, controlled deviations within GDD-approved ranges.
   - Deterministic from hero_seed + campaign_seed + emotional history.
4. Changes must make canonical sense:
   - High morale → stronger leadership/social outcomes.
   - High fear → potential resilience gains but reduced inspiration traits.

---

## 7. Integration points

Primary files involved as the epic is implemented:

- `core/models/HeroModel.gd`
- `core/services/EmotionService.gd`
- `core/combat/CombatEngine.gd`
- `core/world/ObjectiveRunner.gd`
- `core/ui/debug/debug_console.gd`
- Tests under:
  - `core/tests/emotion/`
  - `core/tests/combat/`
  - `core/tests/realm/`

---

## 8. Summary

- Heroes track **morale** and **fear** (0–100), persistent and deterministic.  
- `HeroModel` stores them; `EmotionService` manages them.  
- Combat, shrine, and realms read and write emotions only through the service.  
- Emotional trajectories inform **hero attributes**, both at summoning and during growth, aligning with GDD philosophy.  
- Future epics (Sanctum, refusal, trauma, rites) will extend this core — not replace it.

---

## 9. Sanctum integration (future epic)

The Sanctum is the long-term emotional home for heroes. Emotion-wise, the Sanctum epic will:

- Use EmotionService as the **only** way to modify morale/fear.
- Never duplicate emotion fields; it always talks in terms of hero ids and deltas.

### 9.1 Sanctum needs (MVP-ready hooks)

The current Emotion Core already provides what Sanctum will need:

- Persistent, per-hero `morale_current`, `morale_base`, and `fear_current` on HeroModel.
- A global EmotionService that can:
  - Read current state (`get_morale`, `get_fear`).
  - Apply controlled changes (`apply_delta` and future Sanctum-specific helpers).
  - Log all changes with a `source` so Sanctum actions are auditable.

Sanctum epics should build on top of this by:

- Defining **rest / downtime** actions that slowly restore morale and reduce fear via EmotionService.
- Defining **rituals** that spend Favor (and possibly interact with Faith/Harmony) to apply larger, riskier emotion changes.
- Respecting determinism: given the same campaign_seed, hero history, and Sanctum choices, emotional outcomes must be reproducible.
- Keeping all emotion math in Sanctum **thin**, delegating clamping and storage to EmotionService.

In short, Sanctum becomes another caller of EmotionService, alongside combat and realms, rather than a separate emotional system.