# Economy Loop Update Summary

This tuning pass keeps the Tier 2 campaign resilient during fear spikes while still surfacing the
pressure that the balance chapter expects designers to feel. The changes below are written in plain
language so anyone on the team can reuse the numbers when building scenes or prototyping UI.

## Why this pass matters

- Squads now survive scripted spikes without needing manual babysitting, which means we can test
  the narrative pacing the MVP promised instead of firefighting morale collapses.
- Faith no longer drifts under 60 for long stretches. When it does dip, the loop automatically
  invests downtime to climb back above the healthy band so Ase income stays predictable.
- Legacy fragments can still enter the economy even if Spike Guard prevents actual deaths, keeping
  the post-battle progression loop alive without encouraging wipes.

## What changed inside the loop

### Spike Guard auto-ritual
- The sim now “forecasts” each day before encounters. If the upcoming fear would cross the 90
  threshold, Spike Guard fires automatically, shaving 18 fear, adding 12 morale, and reducing the
  day’s fear gain by 30%.
- In the ritual preload scenario this only triggers three times (days 18–19) and holds the fear
  ceiling at 88.44 while morale never drops below 71.36.【F:simulation_logs/ritual_preload_run.json†L172-L223】【F:simulation_logs/ritual_preload_run.json†L320-L353】
- A concentrated pressure test with four encounters per day shows the guard firing ten times. On
  the tenth activation (day 19) the squad unlocks a voluntary retirement instead of wiping, gaining
  a Legacy Fragment at the cost of three Favor.【F:simulation_logs/spike_guard_streak_run.json†L238-L309】【F:simulation_logs/spike_guard_streak_run.json†L352-L375】

### Ward Beads charges and default cadence
- Ward Beads now draw from a two-charge pool per 20-day arc. If the player does not schedule them
  manually, the sim spends the charges on days 5 and 15.
- You can see the charges being consumed during both ritual preload and harmony sensitivity runs;
  after the day 15 activation there are no further Ward Beads until the cycle resets.【F:simulation_logs/ritual_preload_run.json†L204-L223】【F:simulation_logs/harmony_high_run.json†L204-L223】

### Courage ritual budget awareness
- Courage rituals still grant the large fear/morale swing and eight-day resistance, but the loop now
  skips them when fear is below 60 and morale sits above 70. In the ritual preload scenario the day
  15 ritual is skipped because the squad is already stable, saving resources for harder beats.【F:simulation_logs/ritual_preload_run.json†L204-L223】
- Designers can override this behaviour from the CLI with `--disable_courage_skip` if they want to
  brute-force a ritual-heavy run during testing.【F:scripts/run_sim.py†L37-L86】【F:scripts/run_sim.py†L121-L149】

### Faith guardrail downtime
- Whenever Faith stays under 60 for two days in a row, a Reflection/Prayer downtime injects 15 Ase
  and boosts Faith back to at least 62. The Faith floor stress test shows this triggering on day 2,
  immediately lifting Faith to 62 and logging the downtime flag.【F:simulation_logs/faith_floor_run.json†L102-L141】
- This keeps the Ase yield from collapsing; once Faith stabilises the daily income ramps back into
  the upper 60s and low 70s without designer intervention.【F:simulation_logs/faith_floor_run.json†L274-L353】

### Voluntary retirement rite
- Spike Guard interventions now feed the Legacy economy. After ten guarded days the squad may
  retire a veteran, gaining a Legacy Fragment while spending three Favor instead of suffering a
  morale wipe. The streak stress test shows the rite firing on day 19 and deducting Favor in the
  final summary.【F:simulation_logs/spike_guard_streak_run.json†L308-L369】

### Richer telemetry in the daily log
- Each entry now records whether Spike Guard fired, whether a Courage ritual was skipped, and if a
  Reflection or voluntary retirement occurred. This makes it easier to line up the log with design
  hypotheses when reviewing tuning graphs.【F:simulation_logs/ritual_preload_run.json†L172-L223】

## Validation runs to keep on file
All commands assume you are in the repository root.

1. **Ritual preload (fear spike patch test)**
   ```bash
   python scripts/run_sim.py --days 20 --tier 2 --encounters 3 --fear 6 \
     --seed 0xA2B94D10 --use_courage_ritual day=5,15 --use_ward_beads day=5,15 \
     --log simulation_logs/ritual_preload_run.json
   ```
   - Fear stays capped at 88.44, morale never drops below 71.36, and Faith hovers inside the
     61–79 band while ending with 1,447.61 Ase.【F:simulation_logs/ritual_preload_run.json†L172-L353】

2. **Faith floor stress test**
   ```bash
   python scripts/run_sim.py --days 20 --tier 2 --encounters 3 --fear 6 \
     --seed 0xA2B94D10 --faith_init 45 --log simulation_logs/faith_floor_run.json
   ```
   - Ase income stalls in the mid-40s while Faith is below 60, the guardrail fires on day 2, and the
     run finishes at 1,401.87 Ase once Faith stabilises at 78.66.【F:simulation_logs/faith_floor_run.json†L54-L141】【F:simulation_logs/faith_floor_run.json†L274-L353】

3. **Harmony sensitivity pair**
   ```bash
   python scripts/run_sim.py --days 20 --tier 2 --encounters 3 --fear 6 \
     --seed 0xA2B94D10 --harmony_init 40 --log simulation_logs/harmony_low_run.json
   python scripts/run_sim.py --days 20 --tier 2 --encounters 3 --fear 6 \
     --seed 0xA2B94D10 --harmony_init 60 --log simulation_logs/harmony_high_run.json
   ```
   - Low harmony drags efficiency to ~0.94 and wraps at 1,330.79 Ase, while high harmony lifts the
     multiplier above 1.02 and closes at 1,486.68 Ase with steadier Faith recovery.【F:simulation_logs/harmony_low_run.json†L54-L353】【F:simulation_logs/harmony_high_run.json†L54-L353】

4. **Spike Guard streak sanity check (optional)**
   ```bash
   python scripts/run_sim.py --days 20 --tier 2 --encounters 4 --fear 10 \
     --seed 0xA2B94D10 --log simulation_logs/spike_guard_streak_run.json
   ```
   - Demonstrates ten Spike Guard activations over the campaign and the resulting voluntary
     retirement that keeps Legacy fragments flowing without a wipe.【F:simulation_logs/spike_guard_streak_run.json†L54-L375】

Reuse these runs whenever you adjust encounter pacing, ritual strength, or emotional baselines so
we keep today’s behaviour intact while iterating.
