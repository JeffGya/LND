# 🜂 **Hero Summoning Addendum – “Echoes of the Flame”**
### Canon Alignment: §5, §7, §8, §10 — Echoes of Personality / Sanctum / Flow of Ase / Legacy

---

## 📜 Purpose

This addendum records the **design adjustments** made to the *Hero Summoning (Echoes)* system after the initial “Legacy Never Dies” Game Design Document.  
It supersedes or refines the baseline defined in **Echoes_of_the_Sankofa_Game_Design_v1 §5–8** and must remain attached to the canonical chain.  
All downstream systems — particularly **EchoFactory**, **SummonService**, and **Balance Curve v1 §12** — must mirror these parameters.

---

## 🔁 Summary of Key Changes

| Canon Area | Original | Updated (Addendum v1) | Rationale |
|-------------|-----------|----------------------|------------|
| MVP Class Set | Okofor (Guardian), Obayifo (Mage), Onyamesu (Healer) | **Eban Warder (Guardian / Tank)**  **Akofena Blade (Warrior / Fighter)**  **Fawohodie Ranger (Archer / Ranged DPS)** | Early MVP favors **physical archetypes**; magical/healing Echoes become **rare / post-unlock** classes. |
| Summon Cost | 80 Ase | **60 Ase** | Encourages faster roster growth without breaking progression; 1–1.5 missions fund a summon. |
| Starter Hero | None | **One free hero on new campaign start** (no Ase cost) | Prevents early grind wall, provides instant playable Echo. |
| Trait Focus | 6-trait full model | **Courage / Wisdom / Faith only (MVP scope)** | Keeps first iteration simple while retaining emotional spread. |
| Combat Stat Baseline | Derived from traits, mid-band (50+ HP at birth) | Early-game compressed (HP ~20–30, ATK ~10–15) for summoned/starter Echoes | MVP heroes were spawning at midgame power; rebalanced to match training encounters and §12 pacing. |
| RNG Determinism | per-seed generation | **Channel-salted RNG ("summon", "starter")** | Ensures reproducible rolls and telemetry clarity. |

---

## ⚔️ MVP Class Profiles
*(Lore-aligned physical Echoes – Canon §5.3 “Echoes of Personality”)*

Each class embodies a **Virtue of Sankofa** and defines the player’s emotional rhythm in early encounters.  
These are deterministic tags (stored as `"guardian"`, `"warrior"`, `"archer"`) with corresponding in-world titles for flavor.

---

### 🛡 **Eban Warder — The Guardian**
- **Code:** `guardian`  
- **Role:** Tank / Protector  
- **Virtue Alignment:** *Faith ↔ Harmony*  
- **Signature Traits:** High Courage · Steady Faith  
- **Weapon Style:** Eban-crest shield, heavy mace  
- **Behavioral Focus:** Absorbs fear; morale anchor for the squad  
- **Lore Note:** Named for the *Eban*, the Adinkra symbol of safety and fortified home — they stand as living ramparts of the Sanctum.  
- **Rarity:** Common (Weight 1.0)

---

### ⚔️ **Akofena Blade — The Warrior**
- **Code:** `warrior`  
- **Role:** Melee Fighter / Vanguard  
- **Virtue Alignment:** *Courage ↔ Legacy*  
- **Signature Traits:** High Courage · Balanced Wisdom  
- **Weapon Style:** Dual *Akofena* ceremonial swords  
- **Behavioral Focus:** Momentum and decisive strikes; thrives on morale surges  
- **Lore Note:** The *Akofena* (crossed swords) represent valor and the authority of truth — Warriors turn their resolve into action.  
- **Rarity:** Common (Weight 1.0)

---

### 🏹 **Fawohodie Ranger — The Archer**
- **Code:** `archer`  
- **Role:** Ranged DPS / Skirmisher  
- **Virtue Alignment:** *Wisdom ↔ Freedom*  
- **Signature Traits:** High Wisdom · Balanced Faith  
- **Weapon Style:** Longbow of woven Ase strands  
- **Behavioral Focus:** Keeps distance, punishes hesitation, guides flow of combat  
- **Lore Note:** *Fawohodie* (“Independence”) marks those who walk unbound yet loyal — their arrows whisper of freedom’s price.  
- **Rarity:** Common (Weight 1.0)

---

### 🌑 Future Rare Paths *(post-MVP placeholders)*
- **Onyamesu Vessel** — Healer / Faith-aligned (Weight 0.2)  
- **Obayifo Adept** — Dark Mage / Ambition-aligned (Weight 0.2)  
*(Do not roll in MVP. Unlock later via Crafting & Research v2 events.)*

---

## 🔥 Summoning Parameters (v1)

| Parameter | Value | Notes |
|------------|--------|-------|
| **Cost** | 60 Ase | Tunable; based on “no hard stalls” rule (§8A.6) |
| **Seed Source** | `campaign_seed + "summon" + roster_count` | Deterministic per run |
| **Trait Keys** | courage, wisdom, faith | MVP subset of six-trait model |
| **Trait Range** | 30 – 70 | ± 20 % bias window for balance tuning |
| **Class Bias Map** | guardian: 1.0 · warrior: 1.0 · archer: 1.0 | Equal weight; healer/mage ≤ 0.2 (locked) |
| **Starter Hero** | 1 free summon → seed: `campaign_seed + "starter"` | Created at new-game bootstrap, telemetry evt `starter_hero` |
| **Rank at Birth** | 1 (Uncalled) | Classes emerge later through gameplay |
| **Name Source** | `NameBank.gd` | Deterministic Ghanaian/Akan pool |

---

### Combat Stat Derivation (v1.1)

**EchoFactory.gd** is the single source of truth for these calculations. Combat stats for summoned and starter Echoes are derived from their core traits as follows (all values rounded to int):

```gdscript
hp = max(floor(5 + courage * 0.25 + faith * 0.15), 15)
atk = round(4 + courage * 0.12 + faith * 0.05)
def = round(2 + wisdom * 0.12 + faith * 0.08)
agi = round(2 + wisdom * 0.08 + courage * 0.08)
cha = round(1 + faith * 0.08 + wisdom * 0.08)
int = round(4 + wisdom * 0.22 + courage * 0.04)
max_hp = hp  # on birth
```

---

#### Post-MVP Stat Fields (reserved)

These fields are already present in the hero `stats` dictionary in code but are **intentionally 0 for MVP**.  
The fields include `acc`, `eva`, `crit`, and `mag`/`spirit_pow` (name TBD, tied to Obayifo/Onyamesu path).  
Their purpose for (`acc`, `eva` and `crit`) is to support hit/graze/bullseye resolution, evasion/initiative interactions, and crit-tier damage.  
According to canon, they must obey **Legacy Never Dies §9 Combat** and **§12 Balance Curves** once activated.  
Activation condition for `mag`/`spirit_pow` (name TBD): these stats will be enabled when we introduce non-physical classes (Obayifo, Onyamesu) and realm-specific enemy resistances.

## 🧩 System Integration Map

| Module | Role | New/Updated |
|---------|------|-------------|
| `EconomyConstants.gd` | Summon cost = 60; RNG channels (“summon”, “starter”) | Updated |
| `EchoConstants.gd` | Class codes + trait ranges + rarity map | New |
| `EchoFactory.gd` | Deterministic summon generator + v1.1 early-game combat stat compression | New |
| `SummonService.gd` | Economy + creation pipeline | New |
| `HeroesIO.gd` | Roster persistence | New |
| `DebugConsole.gd` | `/summon`, `/list_heroes`, `/hero_info` | Updated |
| `test_summon.gd` | Determinism & economy validation | New |
| `core/combat/EnemyFactory.gd` | Training/dummy enemy stat alignment | Updated (Oct 2025) |

---

## 🧭 Canon Compliance

- **§1 Core Concept & Vision** – “Guidance > Control” remains: the Keeper guides souls from the Flame; class variety aids narrative pacing.  
- **§5 Heroes / Echoes of Personality** – Physical trio still reflect emotional virtues (Courage, Wisdom, Faith).  
- **§8 Economy & Progression** – 60 Ase cost ensures “no hard stalls.”  
- **§10 Legacy, Death & Recovery** – Each death yields Faith/Legacy fragments unchanged.  
- **§12 Balance Curves** – Adjust expected Ase flow multiplier → `mission_avg_reward ≈ 1.2 × summon_cost`.

---

## 🧱 Implementation Notes

- **Physical archetypes** will appear first; spiritual archetypes unlock after the Obosom Sanctum expansion (post-MVP).  
- **Starter hero** is created during `NewGameService.init_save()`, using RNG channel `"starter"`.  
- **Testing rule:** Fixed seed = fixed heroes; changes to RNG salts or name bank require bumping schema version.  
- **Telemetry:** Every summon logs `{ evt:"summon", cat:"heroes", cost_ase, ids:[…] }`.

---

### MVP Combat Balance Notes (Oct 30 2025)

- Heroes at birth now land around 20–30 HP and 10–15 ATK (depending on trait rolls 30–70).  
- Training enemies (e.g. “Training Wraith”) rebalanced to HP 40, ATK 6–8, DEF 4, AGI 5 to avoid one-shotting weak Echoes.  
- This change preserves determinism: same campaign seed → same hero → same stats.  
- Midgame growth to 100–200 HP is deferred to rank-ups / calling / legacy growth, **not** to summoning.

---

## 📚 Revision History

| Version | Date | Author | Notes |
|----------|------|--------|-------|
| v1.0 | Oct 2025 | Jeff Gyamfi / GPT-5 Co-Design | Introduces physical trio, reduces cost to 60, adds starter hero plan. |
