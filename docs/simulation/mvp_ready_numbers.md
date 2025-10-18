# MVP-ready Numbers (Pass-02)

| Run | Final Ase | Morale Min | Fear Max | Fragments | Voluntary Retirements |
| --- | --- | --- | --- | --- | --- |
| ritual_preload | 1447.61 | 71.36 | 88.44 | 0 | 0 |
| faith_floor | 1401.87 | 71.36 | 88.44 | 0 | 0 |
| harmony_low | 1330.79 | 71.36 | 88.44 | 0 | 0 |
| harmony_high | 1486.68 | 71.36 | 88.44 | 0 | 0 |
| spike_guard_stress | 1445.78 | 77.52 | 75.00 | 1 | 1 |

**Ship-these defaults (Pass-02):**
- `SPIKE_GUARD_THRESHOLD = 90`
- `WARD_BEADS_CHARGES_PER_20D = 2`
- `COURAGE_SKIP_CONDITION = (fear < 60) AND (morale > 70)`
- `FAITH_GUARDRAIL = {threshold: 60, floor: 62, ase_cost: 15, required_days: 2}`
- `RETIREMENT_RITE = {min_streak: 10, favor_cost: 3}`
- `HARMONY_BRIGHT_ZONE = 55–60 (target ≥55)`

**Key KPIs (Ase/Faith/Harmony/Favor/Morale/Fear/Flags)**

- **ritual_preload** → Final Ase 1447.61, Faith 79.00, Harmony 50.14, Favor 18.24, Morale 85.50, Fear 80.64; Spike Guard 3x, Courage used 1x (skipped 1x), Ward Beads 2x, Reflection/Prayer 0x, Voluntary retirements 0x.
- **faith_floor** → Final Ase 1401.87, Faith 78.66, Harmony 50.13, Favor 18.03, Morale 85.50, Fear 80.64; Spike Guard 3x, Courage used 1x (skipped 1x), Ward Beads 2x, Reflection/Prayer 1x, Voluntary retirements 0x.
- **harmony_low** → Final Ase 1330.79, Faith 74.73, Harmony 35.13, Favor 17.94, Morale 85.50, Fear 80.64; Spike Guard 3x, Courage used 1x (skipped 1x), Ward Beads 2x, Reflection/Prayer 0x, Voluntary retirements 0x.
- **harmony_high** → Final Ase 1486.68, Faith 80.26, Harmony 55.14, Favor 18.33, Morale 85.50, Fear 80.64; Spike Guard 3x, Courage used 1x (skipped 1x), Ward Beads 2x, Reflection/Prayer 0x, Voluntary retirements 0x.
- **spike_guard_stress** → Final Ase 1445.78, Faith 78.93, Harmony 49.87, Favor 14.23, Morale 90.22, Fear 59.40; Spike Guard 10x, Courage used 2x (skipped 0x), Ward Beads 2x, Reflection/Prayer 0x, Voluntary retirements 1x.

MVP build reference (pin these)
	•	SPIKE_GUARD_THRESHOLD = 90
	•	WARD_BEADS_CHARGES_PER_20D = 2
	•	COURAGE_SKIP_CONDITION = (fear < 60) AND (morale > 70)
	•	FAITH_GUARDRAIL = { threshold: 60, floor: 62, ase_cost: 15, required_days: 2 }
	•	RETIREMENT_RITE = { min_streak: 10, favor_cost: 3 }
	•	HARMONY_BRIGHT_ZONE = 55–60 (target ≥55)
