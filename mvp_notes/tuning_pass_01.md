# Tuning Pass 01 — Autopilot safeguards

This note tracks how the "Spike Guard" brief was implemented and what to look for when you replay
the balance scenarios. Everything below is written for designers and producers rather than
programmers.

## What we added

- **Spike Guard auto-ritual**: The sim now checks the next day's fear forecast and fires a protective
  ritual when the number would hit 90+. It lowers fear before encounters, adds morale, and cuts the
  day's fear gain by almost a third.
- **Ward Beads budgeting**: Only two Ward Beads are available in a 20-day arc. If you do nothing,
  the loop spends them on days 5 and 15; if you schedule your own days the charges will be consumed
  there instead.
- **Courage ritual awareness**: Courage is still powerful, but it now skips itself when fear is under
  control (fear < 60 and morale > 70) so we do not burn charges unnecessarily. Use the
  `--disable_courage_skip` flag to force rituals on during testing.
- **Faith guardrail downtime**: If Faith stays below 60 for two consecutive days, the squad takes a
  Reflection/Prayer downtime. That spends 15 Ase and bumps Faith back above 60 so the economy does
  not stall.
- **Voluntary retirements**: After Spike Guard has protected the squad on ten different days, the
  team can retire a veteran instead of waiting for a wipe. This grants one Legacy Fragment and costs
  three Favor.
- **Daily log flags**: The JSON log now tells you when Spike Guard, Courage skips, reflections, or
  retirements happen. This makes telemetry review easier.

## How to verify the pass

1. **Baseline ritual preload**
   - Command: `python scripts/run_sim.py --days 20 --tier 2 --encounters 3 --fear 6 --seed 0xA2B94D10 --use_courage_ritual day=5,15 --use_ward_beads day=5,15 --log simulation_logs/ritual_preload_run.json`
   - What to check: fear peaks at 88.44, morale never drops below 71.36, Faith floats in the high
     70s, and Spike Guard only fires late in the campaign.

2. **Faith floor guardrail**
   - Command: `python scripts/run_sim.py --days 20 --tier 2 --encounters 3 --fear 6 --seed 0xA2B94D10 --faith_init 45 --log simulation_logs/faith_floor_run.json`
   - What to check: the log shows a Reflection/Prayer event on day 2 and the final Faith value lands
     back near 79, proving the guardrail works.

3. **Harmony spread**
   - Commands:
     - `python scripts/run_sim.py --days 20 --tier 2 --encounters 3 --fear 6 --seed 0xA2B94D10 --harmony_init 40 --log simulation_logs/harmony_low_run.json`
     - `python scripts/run_sim.py --days 20 --tier 2 --encounters 3 --fear 6 --seed 0xA2B94D10 --harmony_init 60 --log simulation_logs/harmony_high_run.json`
   - What to check: low harmony tops out around 1,331 Ase while high harmony reaches ~1,487 Ase with
     noticeably stronger daily yields.

4. **Spike Guard streak (optional stress test)**
   - Command: `python scripts/run_sim.py --days 20 --tier 2 --encounters 4 --fear 10 --seed 0xA2B94D10 --log simulation_logs/spike_guard_streak_run.json`
   - What to check: there are ten Spike Guard activations and a voluntary retirement on day 19 so we
     still earn a Legacy Fragment without losing the squad.

Keep these runs handy for future tuning passes so we can prove the safety rails still work.
