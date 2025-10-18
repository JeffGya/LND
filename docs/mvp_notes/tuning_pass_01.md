# Echoes of the Sankofa — MVP Tuning Pass 01
**Date:** 2025-10-18  
**Seed Reference:** 0xA2B94D10  
**Simulation Source:** Tier 2, 20-Day Runs (Faith Floor, Ritual Preload, Harmony Low/High)  
**Author:** Simulation Feedback Integration Team (AI + Designer)

---

## 🧭 Overview
This tuning pass integrates verified simulation data into the MVP baseline.  
The changes below align with the canonical clauses in **Legacy Never Dies** and its linked subsystem documents.

**Goals**
- Preserve deterministic fairness (§13, Directive 2).  
- Reinforce emotional balance between Faith ↔ Harmony ↔ Favor (§8, Directive 3).  
- Maintain legacy continuity through non-lethal progression (§10, Directive 4).  
- Codify practical defaults for playtesting stability.

---

## 1. Harmony Stabilization — “Bright Zone” Enforcement
**Findings:** High-Harmony runs produced ≈ +11 % Ase vs low-Harmony runs (1482 → 1326 Ase).  
**Adjustment:**
- Target Harmony ≥ 55 during active campaigns.  
- Add **Group Meditation** downtime if Harmony < 55 for ≥ 2 days.  
- Meditation grants +Faith recovery (12.3.4) and +2 % efficiency next day.  
- Display *Bright Sanctum* banner when both Faith ≥ 70 and Harmony ≥ 55.

**Document Links:**  
_Game Design v1 §7 / Economic Model v1 §9 / Balance Curves v1 §12_

---

## 2. Spike Guard System — Default Fear Control
**Findings:** Courage Ritual + Ward Beads reduced fear from 86 → 45 and morale collapse 33 → 86.  
**Adjustment:**
- Enable **Spike Guard** (automatic) when predicted next-day Fear ≥ 90.  
- Default triggers: **days 5 and 15**, unless Fear < 60 and Morale > 70 → skip to conserve resources.  
- Provide 2 Ward Beads per 20-day cycle; Courage Ritual consumes baseline Ase/Ekwan cost.  
- Diminishing returns if used > 2× in 5 days (anti-spam rule).

**Document Links:**  
_Game Design v1 §9 / Design Checklist v2 §5_

---

## 3. Faith Floor Guardrail — “Reflection” Downtime
**Findings:** Faith < 60 stalls Ase yield ≈ 25 %; recovery resumes only above 60.  
**Adjustment:**
- When Faith < 60 for 2 days, auto-queue a **Reflection Rest** block:  
  - Reduce next-day encounters by 1.  
  - Apply +Faith Δ per formula 12.3.4.  
  - Skip if Harmony < 50 (to avoid compounding lows).

**Document Links:**  
_Economic Model v1 §7 / Balance Curves v1 §12_

---

## 4. Legacy Continuity — Voluntary Retirement Rite
**Findings:** Perfect stability yielded 0 Legacy Fragments; canon requires continuity through loss.  
**Adjustment:**
- When Spike Guard prevents all deaths for ≥ 10 days, unlock **Retirement Rite**:  
  - Player may retire 1 Echo.  
  - Gain 1 Legacy Fragment + 5 Faith; lose 1 Favor.  
  - Trigger funeral/ancestral memory dialogue.

**Document Links:**  
_Game Design v1 §10 / Economic Model v1 §11_

---

## 5. Telemetry & KPI Tracking
**Adjustment:**
- Log per day:  
  - Ase gain/spend  
  - Faith, Harmony, Favor  
  - Fear max, Morale min  
  - Legacy Fragments  
  - Ritual / Bead usage flags  
- KPI targets:  
  - Ase gain:spend = 1.1–1.3  
  - Faith σ ≤ 20  
  - Morale collapse ≈ 1 in 5 fights

**Document Links:**  
_Balance Curves v1 §12 / Design Checklist v2 §5_

---

## 🎛️ Knob Summary
| System | Parameter | New Baseline |
|---------|------------|--------------|
| Harmony Efficiency | Clamp ≥ 0.9, Target 1.03 @ 55 Harmony | +6 % avg Ase yield |
| Courage Ritual | Cost = 25 Ase / 10 Ekwan | Fear −40 for 2 days |
| Ward Beads | Stock = 2 / 20 days | Fear gain −50 % (1 day) |
| Faith Reflection | 1-day cooldown | Faith +6 avg |
| Retirement Rite | Favor −1 → Legacy +1 | Keeps continuity |

---

## 🧪 Validation Sims
| Test | Command | Purpose |
|------|----------|----------|
| **A)** Spike Guard Economics | `--use_courage_ritual day=5,15` vs `--use_ward_beads day=5,15` | Identify cheaper stability path |
| **B)** Harmony Clamp 55 | `--harmony_init 50 --auto_meditate` | Confirm Ase ≥ high-Harmony ±3 %, Faith σ drop |
| **C)** Retirement Rite Impact | `--use_courage_ritual day=5 --skip day=15` | Ensure ≥ 1 Fragment gain < 3 % Ase loss |

---

## 📎 Commit Path
File Location: `docs/mvp_notes/tuning_pass_01.md`  
Upstream References:
- _Legacy Never Dies_ § 8 / § 9 / § 10 / § 12  
- _Echoes of the Sankofa Game Design v1_ § 7 / § 9 / § 10  
- _Economic Model FULL v1_ § 7 / § 9 / § 11  
- _Balance Curve Modeling v1_ § 12  
- _Design Checklist v2_ § 5

---

*End of Tuning Pass 01 — Ready for simulation verification and MVP integration.*