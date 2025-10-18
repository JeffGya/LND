"""Curve regression tests anchored to canon §12."""

from simulation.curves import (
    ase_yield_per_tick,
    ekwan_cost_for_tier,
    faith_recovery_step,
    harmony_efficiency,
)


def test_ase_yield_respects_faith_clamp():
    base = 50.0
    low = ase_yield_per_tick(base, 30)
    mid = ase_yield_per_tick(base, 60)
    high = ase_yield_per_tick(base, 95)

    assert low < mid < high
    assert high <= base * 2.0
    assert ase_yield_per_tick(base, -20) >= base * 0.5


def test_faith_recovery_scales_with_harmony():
    faith = 40.0
    slow = faith_recovery_step(faith, 20) - faith
    fast = faith_recovery_step(faith, 90) - faith

    assert fast > slow
    assert faith_recovery_step(99.0, 90.0) <= 100.0


def test_harmony_efficiency_window():
    assert harmony_efficiency(-10.0) == 0.85
    assert harmony_efficiency(50.0) == 1.0
    assert harmony_efficiency(140.0) == 1.3


def test_ekwan_tier_scaling_geometric():
    base = 12.0
    tier_one = ekwan_cost_for_tier(base, 1)
    tier_five = ekwan_cost_for_tier(base, 5)

    assert tier_five > tier_one
    assert round(tier_five / tier_one, 2) == round(1.28 ** 4, 2)
