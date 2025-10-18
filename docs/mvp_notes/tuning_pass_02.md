# Tuning Pass 02 — Canon Notes

Pass 02 locks the MVP guardrails that will ship with the Echoes of the Sankofa build. Use these targets as the default configuration unless a future balancing pass overrides them.

## Default safeguards
- **Spike Guard:** enable by default with a 90 fear forecast trigger. When it fires, apply −18 fear / +12 morale before the day’s encounters and increment the streak counter.
- **Courage rituals:** auto-schedule on days 5 and 15, but skip when fear < 60 and morale > 70 so the squad only spends when pressure is real.
- **Ward Beads:** provide two auto-charges per 20-day campaign (days 5 and 15) to smooth the worst spikes.
- **Faith guardrail:** after two straight days below 60 Faith, run Reflection/Prayer to restore Faith to at least 62 for a 15 Ase cost.
- **Voluntary retirement:** once Spike Guard prevents disasters for ten days in a row, unlock a rite that costs 3 Favor and awards one Legacy fragment.

## Validation runs
Re-run the regression pack with seed `0xA2B94D10`, Tier 2, 20-day horizon, and three encounters per day unless otherwise stated:
1. Ritual preload baseline with Spike Guard ON and the default charges.
2. Faith floor stress with Faith starting at 45 and Harmony at 55 to confirm the guardrail.
3. Harmony sensitivity at 40 and 60 to show the bright zone uplift.
4. Spike-guard streak stress (four encounters, fear 10) to ensure the retirement rite unlocks cleanly.

These guardrails should keep morale above collapse thresholds, cap fear near the high 80s under normal pressure, and maintain Legacy flow without forcing player-engineered wipes.
