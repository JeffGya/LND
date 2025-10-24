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

## 🧩 System Integration Map

| Module | Role | New/Updated |
|---------|------|-------------|
| `EconomyConstants.gd` | Summon cost = 60; RNG channels (“summon”, “starter”) | Updated |
| `EchoConstants.gd` | Class codes + trait ranges + rarity map | New |
| `EchoFactory.gd` | Deterministic summon generator | New |
| `SummonService.gd` | Economy + creation pipeline | New |
| `HeroesIO.gd` | Roster persistence | New |
| `DebugConsole.gd` | `/summon`, `/list_heroes`, `/hero_info` | Updated |
| `test_summon.gd` | Determinism & economy validation | New |

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

## 📚 Revision History

| Version | Date | Author | Notes |
|----------|------|--------|-------|
| v1.0 | Oct 2025 | Jeff Gyamfi / GPT-5 Co-Design | Introduces physical trio, reduces cost to 60, adds starter hero plan. |
