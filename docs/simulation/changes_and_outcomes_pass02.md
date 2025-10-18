# Pass-02 Changes and Outcomes

## Loop adjustments
- Added a Spike Guard forecast that triggers when next-day fear would hit 90+, trimming fear by 18 and lifting morale by 12 before encounters.
- Kept Courage rituals on days 5 and 15 but allowed them to skip automatically when fear stays under 60 and morale is above 70, preserving resources for real spikes.
- Limited Ward Beads to two auto-charges per 20-day run and tracked their spend so balance sheets line up with the canon.
- Installed a Faith guardrail: after two straight days below 60, Reflection/Prayer restores Faith to at least 62 at the cost of 15 Ase.
- Unlocked a voluntary retirement rite after ten Spike Guard saves to grant a fragment at the cost of 3 Favor, keeping Legacy flow without deliberate wipes.

## Observed outcomes
- **Ritual preload** ([log](../../simulation_logs/_reg_preload.json)): fear never topped 88.44, morale bottomed at 71.36, and the run still closed at 1,447.61 Ase with no fragments spent.
- **Faith floor stress** ([log](../../simulation_logs/_reg_faithfloor.json)): the guardrail fired on day 2, lifting Faith from 46.81 to 62 and costing 15 Ase; the campaign recovered to 1,401.87 Ase with faith stabilising near 78.66.
- **Harmony low vs. high** ([low log](../../simulation_logs/_reg_harm_low.json), [high log](../../simulation_logs/_reg_harm_high.json)): ending Ase diverged 1,330.79 vs 1,486.68, showing the expected 5–10% uplift when Harmony starts inside the 55–60 bright zone.
- **Spike-guard streak stress** ([log](../../simulation_logs/_reg_stress.json)): Spike Guard triggered 10 times, culminating in a day-19 voluntary retirement that spent 3 Favor, yielded one fragment, and still left morale at 93.39 when the rite fired.

These runs confirm the guardrails stabilize fear, keep Faith above the production cliff, and maintain Legacy pacing without forcing squad wipes.
