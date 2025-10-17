# Economy Loop Update Summary

This document captures the balance adjustments introduced in the latest ritual mitigation pass. These values are now the standing reference for downstream game tuning.

## High-level goals

- **Stabilize morale during scripted fear spikes** so squads do not cascade-break before players can respond.
- **Preserve Faith-driven Ase output** by keeping fear pressure manageable and enabling sustained emotional recovery.
- **Expose daily emotional telemetry** (Faith, Harmony, Favor) alongside resources to accelerate balance tuning.

## Loop flow overview

1. **Nightly reset window**: Each new day begins with a flat `-5` fear and `+5` morale drift, representing sleep and coaching downtime.
2. **Economy production**: Harmony efficiency is sampled before the day’s encounters, then Ase yield is computed using the Faith curve and multiplied by Harmony.
3. **Upkeep spend**: Realm upkeep subtracts ekwan and bleeds Ase based on tier cost, locking economic pressure to the realm tier.
4. **Pre-encounter mitigation**:
   - Ward Beads flag a day-long fear multiplier (`×0.8`).
   - Courage Ritual grants `-20` fear, `+25` morale, and establishes an 8-round lingering resistance buffer.
5. **Encounter stress**: Fear gain equals `encounters_today × fear_per_encounter × modifiers`. Guardians, Ward Beads, and active courage resistance stack multiplicatively.
6. **Morale decay**: `morale_decay_step` converts the new fear total into morale loss, respecting Guardian protection.
7. **Lingering mitigation**: While the courage buffer persists, an extra `-5` fear is removed to represent sustained resolve.
8. **Legacy fail-safe**: If morale reaches zero, the squad converts to a Legacy Fragment, morale resets to 45, and fear is clamped to 60%.
9. **Emotional recovery**:
   - Faith rebounds via `faith_recovery_step`, and the delta is logged.
   - Harmony nudges up when Favor is healthy and fear is low; otherwise it slips.
   - Favor tracks Faith confidence minus encounter fatigue.
10. **Logging**: The daily entry records resources, emotional states, mitigation usage, and recovery deltas.

## Notable balance levers

- **Lingering courage resistance (`8` day-ticks)** halves encounter fear gain and shaves an extra 5 fear per night, ensuring ritual preload keeps `fear_max ≤ 80`.
- **Nightly passive recovery (`±5` morale/fear)** gives squads breathing room between scripted spikes without negating tension.
- **Guardian + Ward Beads stacking** is multiplicative, so combining them with rituals allows designer-tunable difficulty ramps.
- **Faith/Harmony baseline overrides** allow you to test failure and success cases directly from the CLI (`--faith_init`, `--harmony_init`, `--favor_init`).
- **`--log` CLI flag** writes the JSON payload to disk (creating parent folders) while keeping stdout unchanged, making comparisons across runs easier.

## Suggested validation sims

Run these from the repository root (`PYTHONPATH=. python scripts/run_sim.py ...`):

- **Ritual preload** — verifies the target fear/morale envelope:
  ```bash
  --days 20 --tier 2 --encounters 3 --fear 6 --seed 0xA2B94D10 --use_courage_ritual day=5,15 --use_ward_beads day=5,15
  ```
- **Faith floor stress test** — start at Faith 45 and observe Ase collapse until recovery kicks in:
  ```bash
  --days 20 --tier 2 --encounters 3 --fear 6 --seed 0xA2B94D10 --faith_init 45
  ```
- **Harmony sensitivity pair** — compare economy velocity at low vs. high harmony:
  ```bash
  --days 20 --tier 2 --encounters 3 --fear 6 --seed 0xA2B94D10 --harmony_init 40
  --days 20 --tier 2 --encounters 3 --fear 6 --seed 0xA2B94D10 --harmony_init 60
  ```

These runs align with the balance checks described in the game design document and should be re-used when iterating on encounter pacing.
