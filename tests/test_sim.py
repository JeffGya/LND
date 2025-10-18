"""Simulation-level tests ensuring determinism and economy sanity."""

import json
import subprocess
import sys
from pathlib import Path

from simulation import SimConfig, run_economy_sim
from simulation.scripts import run_sim


def test_deterministic_campaign_seed():
    cfg = SimConfig(days=7, campaign_seed=0xDEADBEEF, realm_tier=2)
    first = run_economy_sim(cfg)
    second = run_economy_sim(cfg)
    assert first == second


def test_tier_spend_progression():
    cfg_low = SimConfig(days=1, realm_tier=1)
    cfg_high = SimConfig(days=1, realm_tier=5)

    low = run_economy_sim(cfg_low)
    high = run_economy_sim(cfg_high)

    low_spend = low["log"][0]["ekwan_spend"]
    high_spend = high["log"][0]["ekwan_spend"]

    assert high_spend > low_spend


def test_faith_growth_increases_ase_yield():
    cfg = SimConfig(days=2)
    result = run_economy_sim(cfg)
    day1 = result["log"][0]
    day2 = result["log"][1]
    assert day2["ase_yield"] >= day1["ase_yield"]


def test_ward_beads_reduce_fear_gain():
    base_cfg = SimConfig(days=1, fear_per_encounter=10, encounters_per_day=2)
    mitigated_cfg = SimConfig(
        days=1,
        fear_per_encounter=10,
        encounters_per_day=2,
        ward_beads_days=(1,),
    )

    base = run_economy_sim(base_cfg)
    mitigated = run_economy_sim(mitigated_cfg)

    assert mitigated["log"][0]["fear"] < base["log"][0]["fear"]


def test_courage_ritual_boosts_morale():
    base_cfg = SimConfig(days=1, fear_per_encounter=12, encounters_per_day=3)
    ritual_cfg = SimConfig(
        days=1,
        fear_per_encounter=12,
        encounters_per_day=3,
        courage_ritual_days=(1,),
        skip_courage_when_comfortable=False,
    )

    base = run_economy_sim(base_cfg)
    boosted = run_economy_sim(ritual_cfg)

    assert boosted["log"][0]["morale"] > base["log"][0]["morale"]


def test_courage_ritual_grants_lingering_fear_resistance():
    base = run_economy_sim(SimConfig(days=2, fear_per_encounter=12, encounters_per_day=3))
    ritual = run_economy_sim(
        SimConfig(
            days=2,
            fear_per_encounter=12,
            encounters_per_day=3,
            courage_ritual_days=(1,),
            skip_courage_when_comfortable=False,
        )
    )

    assert ritual["log"][1]["fear"] < base["log"][1]["fear"]


def test_initial_faith_can_start_below_default():
    default = run_economy_sim(SimConfig(days=1))
    lowered = run_economy_sim(SimConfig(days=1, faith_initial=45.0))

    assert lowered["log"][0]["faith"] < default["log"][0]["faith"]


def test_harmony_initial_impacts_ase_yield():
    low_harmony = run_economy_sim(SimConfig(days=1, harmony_initial=40.0))
    high_harmony = run_economy_sim(SimConfig(days=1, harmony_initial=60.0))

    assert low_harmony["log"][0]["ase_yield"] < high_harmony["log"][0]["ase_yield"]


def test_daily_log_includes_emotional_globals():
    result = run_economy_sim(SimConfig(days=1))
    entry = result["log"][0]

    for key in ("faith", "harmony", "favor"):
        assert key in entry


def test_cli_log_flag_writes_json(tmp_path, monkeypatch, capsys):
    log_path = tmp_path / "reports" / "out.json"
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "run_sim.py",
            "--days",
            "1",
            "--log",
            str(log_path),
        ],
    )

    run_sim.main()
    captured = capsys.readouterr()

    assert log_path.exists()
    payload = json.loads(log_path.read_text())
    assert payload["log"][0]["day"] == 1

    stdout_payload = json.loads(captured.out)
    assert stdout_payload["final"]["morale"] == payload["final"]["morale"]


def test_cli_log_flag_without_value_uses_default(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    default_log = run_sim.DEFAULT_LOG_PATH
    monkeypatch.setattr(sys, "argv", ["run_sim.py", "--days", "1", "--log"])

    try:
        run_sim.main()
        captured = capsys.readouterr()

        assert default_log.exists()
        payload = json.loads(default_log.read_text())
        assert payload["log"][0]["day"] == 1

        stdout_payload = json.loads(captured.out)
        assert stdout_payload["final"] == payload["final"]
    finally:
        if default_log.exists():
            default_log.unlink()


def test_cli_log_relative_path_resolves_against_repo_root(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    relative_target = Path("simulation/logs/test_relative.json")
    expected = run_sim.PROJECT_ROOT / relative_target
    monkeypatch.setattr(
        sys,
        "argv",
        ["run_sim.py", "--days", "1", "--log", str(relative_target)],
    )

    try:
        run_sim.main()
        capsys.readouterr()  # drain stdout/stderr

        assert expected.exists()
        payload = json.loads(expected.read_text())
        assert payload["log"][0]["day"] == 1
    finally:
        if expected.exists():
            expected.unlink()


def test_script_executes_without_pythonpath_requirement():
    repo_root = Path(__file__).resolve().parents[1]
    script_path = repo_root / "simulation" / "scripts" / "run_sim.py"
    result = subprocess.run(
        [sys.executable, str(script_path), "--days", "1"],
        cwd=repo_root,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr


def test_spike_guard_triggers_on_high_forecast():
    cfg = SimConfig(
        days=1,
        encounters_per_day=7,
        fear_per_encounter=15.0,
        spike_guard_threshold=80.0,
    )

    result = run_economy_sim(cfg)
    entry = result["log"][0]

    assert entry["spike_guard_used"] is True
    assert entry["fear"] < 90.0


def test_courage_skip_saves_ritual_when_stable():
    cfg = SimConfig(
        days=1,
        courage_ritual_days=(1,),
        skip_courage_when_comfortable=True,
        fear_per_encounter=4.0,
        encounters_per_day=1,
    )

    result = run_economy_sim(cfg)
    entry = result["log"][0]

    assert entry["courage_ritual_used"] is False
    assert entry["courage_ritual_skipped"] is True


def test_faith_guardrail_restores_floor():
    cfg = SimConfig(
        days=4,
        faith_initial=45.0,
        harmony_initial=40.0,
        faith_guardrail_threshold=60.0,
        faith_guardrail_required_days=2,
        faith_guardrail_floor=62.0,
        faith_guardrail_ase_cost=5.0,
    )

    result = run_economy_sim(cfg)
    reflections = [entry for entry in result["log"] if entry["reflection_prayer_used"]]

    assert reflections, "Expected at least one reflection/prayer event"
    for entry in reflections:
        assert entry["faith"] >= 62.0


def test_retirement_rite_unlocks_after_spike_guard_streak():
    cfg = SimConfig(
        days=6,
        encounters_per_day=7,
        fear_per_encounter=15.0,
        spike_guard_threshold=70.0,
        retirement_rite_min_streak=2,
    )

    result = run_economy_sim(cfg)
    retirements = [entry for entry in result["log"] if entry["voluntary_retirement"]]

    assert retirements, "Expected the retirement rite to trigger"
    assert result["final"]["voluntary_retirements"] >= 1
