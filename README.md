# Echoes of the Sankofa — Deterministic MVP Simulation

This repository bundles the **Echoes of the Sankofa** MVP simulation loop with canon reference
material. The simulation enforces the guiding priorities (Narrative > Mechanics > Economy) while
remaining reproducible via the `campaign_seed`.

## MVP Guardrails (Pass-02)

- [Tuning Pass 02 — canon notes](docs/mvp_notes/tuning_pass_02.md)
- [Economy loop update summary](docs/simulation/economy_loop_update_summary.md)
- [MVP-ready numbers (MD)](docs/simulation/mvp_ready_numbers.md)
- [MVP-ready numbers (CSV)](docs/simulation/mvp_ready_numbers.csv)
- [Pass-02 changes and outcomes](docs/simulation/changes_and_outcomes_pass02.md)
- [MVP go/no-go checklist](docs/simulation/mvp_go_no_go_checklist.md)

## Running the simulation

```bash
python -m venv .venv
source .venv/bin/activate
pip install pytest  # optional, enables running the test suite
python scripts/run_sim.py --days 20 --tier 2 --encounters 3 --fear 6 --seed 0xA2B94D10
```

Key configuration flags:

- `--seed`: campaign seed that drives all deterministic variance.
- `--tier`: realm tier that scales ekwan upkeep (§12.2).
- `--encounters` and `--fear`: encounter cadence and fear pressure (§12.3).
- `--guardian`: toggles Guardian mitigation for morale (§12.3).
- `--faith_init`, `--harmony_init`, `--favor_init`: override the Sanctum emotional baselines to
  probe different economy states.
- `--use_courage_ritual` / `--use_ward_beads`: schedule mitigation rituals by supplying
  comma-separated day lists (e.g. `--use_courage_ritual day=5,15`).
- `--courage_auto_days` / `--ward_beads_auto_days`: adjust the default days that the sim will use
  when you do not supply a manual schedule (defaults to days 5 and 15).
- `--ward_beads_charges`: set how many Ward Beads are available in the campaign (defaults to `2`).
- `--skip_courage_when_comfortable`: keep this `true` to conserve rituals when fear is <60 and
  morale is >70; set to `false` if you want Courage to fire regardless.
- `--spike_guard_enabled` / `--spike_guard_threshold`: toggle or retune the automatic Spike Guard
  mitigation that fires when the fear forecast is dangerously high.
- `--faith_guardrail_threshold`, `--faith_guardrail_required_days`, `--faith_guardrail_floor`,
  `--faith_guardrail_ase_cost`: tune the Reflection/Prayer downtime that restores Faith when it
  stays below the guardrail for consecutive days.
- `--retirement_rite_enabled`, `--retirement_rite_min_streak`, `--retirement_rite_favor_cost`:
  control when (and if) the voluntary retirement rite unlocks after repeated Spike Guard saves.
- `--log`: persist the JSON report to disk while still echoing it to stdout. Pass an explicit path
  or omit the value to write to `simulation_logs/latest_run.json` under the repository root (parents
  are created automatically, even if you launch the CLI from another directory).

The command prints a JSON payload with a daily log and final summary snapshot.

### Suggested follow-up sims

Quick scenarios that exercise the new ritual scheduling and emotional baselines:

- **Ritual preload (fear spike patch test):**

  ```bash
  python scripts/run_sim.py --days 20 --tier 2 --encounters 3 --fear 6 --seed 0xA2B94D10 \
    --use_courage_ritual day=5,15 --use_ward_beads day=5,15
  ```

- **Stress Faith floor (verify ase collapse when Faith dips):**

  ```bash
  python scripts/run_sim.py --days 20 --tier 2 --encounters 3 --fear 6 --seed 0xA2B94D10 \
    --faith_init 45
  ```

- **Harmony sensitivity check (compare economy when harmony varies):**

  ```bash
  python scripts/run_sim.py --days 20 --tier 2 --encounters 3 --fear 6 --seed 0xA2B94D10 \
    --harmony_init 40

  python scripts/run_sim.py --days 20 --tier 2 --encounters 3 --fear 6 --seed 0xA2B94D10 \
    --harmony_init 60
  ```

The JSON daily log lists Ase, Ekwan spend, and the emotional globals (Faith, Harmony, Favor) so
you can track how mitigation choices and starting states ripple through the broader economy.

## Extending the sim

- Curves live in `sankofa_sim/curves.py` and are annotated with canon §12 references.
- The run loop is in `sankofa_sim/sim.py`; keep additions pure and driven by `campaign_seed` for
  deterministic fairness.
- Add new emotional or economic globals sparingly and always propagate them to the daily log for
  MVP traceability.

## Testing

1. (Optional) Create and activate the virtual environment from the setup steps above.
2. Install the lone test dependency:

   ```bash
   pip install pytest
   ```

3. Execute the regression suite from the repository root:

   ```bash
   pytest
   ```

### Test outcomes

- **Success:** `pytest` exits with status code `0` and the summary footer reports `X passed, 0 failed`.
- **Failure:** Any reported `FAILED` test or a non-zero exit status indicates the simulation or curve
  expectations have regressed and must be resolved before shipping.

Tests cover deterministic behaviour, core curve monotonicity, and tier scaling to prevent
regressions while iterating on the MVP.
