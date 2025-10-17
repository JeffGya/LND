"""Simulation-level tests ensuring determinism and economy sanity."""

from sankofa_sim import SimConfig, run_economy_sim


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
    )

    base = run_economy_sim(base_cfg)
    boosted = run_economy_sim(ritual_cfg)

    assert boosted["log"][0]["morale"] > base["log"][0]["morale"]


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
