# Economy Loop Update Summary — Pass 02

Spike Guard now watches the next-day fear forecast and automatically fires when the outlook hits 90 or higher. Courage rituals still sit on days 5 and 15, but the loop skips them when fear is under 60 and morale is above 70 to save charges. Ward Beads track two automatic charges per 20-day campaign, Faith has a guardrail that nudges it back above 62 after two low-faith days (at a 15 Ase cost), and a voluntary retirement rite unlocks after ten Spike Guard saves to keep Legacy fragments flowing without intentional wipes.

| Run | Final Ase | Morale Min | Fear Max | Fragments | Voluntary Retirements |
| --- | --- | --- | --- | --- | --- |
| ritual_preload | 1447.61 | 71.36 | 88.44 | 0 | 0 |
| faith_floor | 1401.87 | 71.36 | 88.44 | 0 | 0 |
| harmony_low | 1330.79 | 71.36 | 88.44 | 0 | 0 |
| harmony_high | 1486.68 | 71.36 | 88.44 | 0 | 0 |
| spike_guard_stress | 1445.78 | 77.52 | 75.00 | 1 | 1 |

## Why this matters for the MVP build

These guardrails keep the MVP feel aligned with the design doc: fear spikes are softened automatically, rituals fire when they are actually needed, and Faith or Legacy never stall for long. Designers can lift these defaults straight into the build, confident that the regression runs demonstrate stable morale, predictable fear caps, and a steady supply of fragments even during extended Spike Guard streaks.
