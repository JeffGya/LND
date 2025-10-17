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
