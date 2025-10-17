
def _clamp(value: float, minimum: float, maximum: float) -> float:
    """Clamp helper so every curve honours canon guard rails."""
    return max(minimum, min(maximum, value))


def ase_yield_per_tick(base_ase: float, faith: float) -> float:
    """Deterministic ase multiplier derived from canon §12.1."""
    # §12.1 Ase Resonance Ladder — each point of Faith above 50 adds +1.6% yield
    # but the resonance stabilises between half and double the base output.
    multiplier = 1.0 + 0.016 * (faith - 50.0)
    multiplier = _clamp(multiplier, 0.5, 2.0)
    return base_ase * multiplier


def ekwan_cost_for_tier(base: float, tier: int) -> float:
    """Realm tier upkeep using canon §12.2 geometric growth."""
    # §12.2 Ekwan Flow — each tier compounds upkeep by 28% over the prior tier.
    growth = 1.28 ** max(0, tier - 1)
    return base * growth


def morale_decay_step(morale: float, fear: float, guardian: bool = False) -> float:
    """Morale decay with guardian mitigation from canon §12.3."""
    # §12.3 Morale Decay — fear pressure scales super-linearly without Guardians.
    exponent = 1.15 if guardian else 1.25
    decay = (max(0.0, fear) / 12.0) ** exponent
    return morale - decay


def faith_recovery_step(faith: float, harmony: float) -> float:
    """Faith rebound paced by harmony as outlined in canon §12.4."""
    # §12.4 Faith Recovery — harmony converts the gap to peak Faith at 6% rate.
    recovery_rate = 0.06 * _clamp(harmony / 100.0, 0.0, 1.2)
    return faith + (100.0 - faith) * recovery_rate


def harmony_efficiency(harmony: float) -> float:
    """Harmony efficiency clamp per canon §12.5."""
    # §12.5 Harmony Efficiency — efficiency window spans 0.85x to 1.3x.
    efficiency = 1.0 + 0.004 * (harmony - 50.0)
    return _clamp(efficiency, 0.85, 1.3)
