

# Echoes of the Sankofa — Archetypes (MVP Addendum)
**Version:** 1.5  
**Date:** 2025-10-26  
**Scope:** MVP personality canon, deterministic mapping from traits, and lightweight behavior/dialogue hooks.

> Canon alignment: This addendum mirrors the *Legacy Never Dies* GDD — §5 (Heroes / Echoes of Personality), §3 (Loop: Guidance > Control), §9 (Deterministic AI), §10 (Legacy continuity). It is implementation-facing, not lore prose.

---

## 1) MVP Archetype Canon
**Source of truth:** `res://core/echoes/EchoConstants.gd`

Each entry is a *tone pattern*, not a power modifier. Values are **strings** used across systems.

| Key (string) | Display | One-liner (intent) |
|---|---|---|
| `loyal` | Loyal | Steadfast, team-first; trusts the Keeper; morale stable. |
| `proud` | Proud | Projects strength; hates appearing weak; morale swings high. |
| `reflective` | Reflective | Thoughtful but **hesitant under pressure**; seeks reassurance and asks questions. |
| `valiant` | Valiant | Courage-led, idealistic; charges ahead for a cause. |
| `canny` | Canny | Calculated, pragmatic; looks for clever advantages. |
| `devout` | Devout | Faith-anchored calm; resilient against fear/corruption. |
| `stoic` | Stoic | Composed, reserved; holds the line under stress. |
| `empathic` | Empathic | People-attuned; notices and responds to allies’ states. |
| `ambitious` | Ambitious | Goal-hungry; pushes for leadership and progress. |

> Canonical list constant: `EchoConstants.ARCHETYPES`.

---

## 2) Deterministic Mapping (Traits → Archetype)
**Source of truth:** `res://core/echoes/PersonalityArchetype.gd`

**Input:** `{courage, wisdom, faith}` as integers (0..100).  
**Output:** one **string** key from the table above.  
**Determinism:** No RNG. Same inputs ⇒ same archetype.

### 2.1 Algorithm (readable spec)
1. **Center** values around their mean:
   - `mean = (c + w + f) / 3`  
   - `dc = c − mean`, `dw = w − mean`, `df = f − mean`
2. **Dominance pass** — if one delta is a **unique** maximum and ≥ `DOMINANCE_THRESHOLD`:
   - `dc` dominant → **valiant**
   - `dw` dominant → **canny**
   - `df` dominant → **devout**
3. **Midline/tie rules** — band each delta into `HIGH (≥ +BAND_EDGE)`, `MID`, `LOW (≤ −BAND_EDGE)` and apply first-match wins:
   1) `C:HIGH` + `F:HIGH` → **loyal**  
   2) `C:HIGH` + `F:LOW`  → **proud**  
   3) `C:LOW`  + `W:HIGH` → **stoic**  
   4) `F:HIGH` + `W:≥MID` → **empathic**  
   5) `W:HIGH` + `C:MID`  → **ambitious**  
   6) **Siphon rule (MVP tuning):** `C:HIGH` + `W:HIGH` + `F:MID` → **ambitious**  
   7) **Fallback:** **reflective** (hesitant/asks questions)

### 2.2 Tunable knobs (current values)
- `DOMINANCE_THRESHOLD = 8.0`
- `BAND_EDGE = 5.0`

These are safe balance levers. Lowering the dominance threshold or the band edge reduces fallback frequency (less `reflective`).

---

## 3) Lightweight Hooks (Behavior & Dialogue)
**Source of truth:** `res://core/echoes/PersonalityArchetype.gd`

Helpers are **pure** (no state), intended for AI/dialogue epics later.

### 3.1 `combat_bias(arch) -> String`
Returns one of: `aggressive`, `cautious`, `steadfast`, `supportive`, `balanced`.

| Archetype | Bias |
|---|---|
| loyal | steadfast |
| proud | aggressive |
| reflective | cautious |
| valiant | aggressive |
| canny | balanced |
| devout | steadfast |
| stoic | steadfast |
| empathic | supportive |
| ambitious | balanced |

### 3.2 `dialogue_key(arch) -> String`
Returns a stable key `voice_<name>` for line selection.

| Archetype | Dialogue key |
|---|---|
| loyal | `voice_loyal` |
| proud | `voice_proud` |
| reflective | `voice_reflective` |
| valiant | `voice_valiant` |
| canny | `voice_canny` |
| devout | `voice_devout` |
| stoic | `voice_stoic` |
| empathic | `voice_empathic` |
| ambitious | `voice_ambitious` |

---

## 4) Telemetry (MVP)
- **Summon batch event:** includes `heroes_preview` with `{id, name, arch, seed}`.
- **Per-hero events:** emitted on hero add; tail shows `{id, name, seed, arch}`.  
**Sources:** `res://core/services/SummonService.gd`, `res://core/save/SaveService.gd`.

Use the debug console to inspect: `/telemetry tail 10`.

---

## 5) Testing & Ops Cheatsheet
- **List heroes:** `/list_heroes`  
- **Hero details:** `/hero_info <id>` (shows Archetype + Bias + Dialogue Key)
- **Sampler (offline balance):** `/archetype_sample [count=1000] [seed]`  
- **Expected distribution (current tuning):** top-4 buckets ~20–22% each; others ~1–5%.

---

## 6) Notes & Guarantees
- **Deterministic fairness:** mapping is pure and reproducible.
- **MVP isolation:** archetype does **not** change stats, drops, or economy.
- **Extensibility:** mapping is trait-relative; changes to absolute roll ranges won’t break outcomes.


## 7) Arrival Barks (MVP)

**Source of truth:** `res://core/echoes/ArchetypeBarks.gd`  
**Purpose:** When a new Echo appears (starter or summoned), display a short, deterministic "arrival bark" line based on their archetype.  

### Implementation
- **API:**  
  ```gdscript
  static func arrival(arch: String, hero_name: String) -> String
  ```
- **Determinism:** One fixed line per archetype (no RNG, no cycling).  
- **Fallback:** Unknown or missing archetype returns `"I’ll do my part."`
- **Side effects:** None. This function is pure and display-only.  
- **Localization:** Lines live in a single table, ready for localization.

### Integration Points
- `/new_game`: prints the starter hero’s bark after their summary.
- `/summon [n]`: prints a bark under each “✨ …summary” line.
- `/hero_info <id>`: shows an “Intro Bark: …” line for any hero.

### Canon Alignment
- Mirrors *Legacy Never Dies* §3 (loop rhythm) and §5 (Hero personality tone).
- Non-mechanical flavor only; does not affect stats or progression.
- Deterministic fairness: same archetype → same line.

### Example Lines

| Archetype | Line |
|------------|------|
| loyal | I’ll hold the line. Say the word. |
| proud | Watch closely—this will be done right. |
| reflective | I have questions… but I will walk with you. |
| valiant | For the cause—point me to the breach. |
| canny | We’ll take the smart path—fewer wounds, more wins. |
| devout | Asé guides us. I will not falter. |
| stoic | I’ve stood through worse. Let’s move. |
| empathic | I’ll keep an eye on the others. We rise together. |
| ambitious | Give me a challenge worth remembering. |

### Testing
Use the debug console:
```
/new_game
/give_ase 300
/summon 3
/hero_info 1
```

### Changelog
- **v1.1 (2025-10-26):** Added MVP arrival bark system (`ArchetypeBarks.gd`). Pure display helper; deterministic one-liner per archetype.