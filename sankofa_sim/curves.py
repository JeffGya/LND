
from .models import Sanctum
import math

def ase_yield_per_tick(base_ase: float, faith: float) -> float:
    # Ase_yield = BaseAse * (1 + 0.015 * (Faith - 50)), clamped to [0.5x, 2.0x]
    mult = 1.0 + 0.015 * (faith - 50.0)
    mult = max(0.5, min(2.0, mult))
    return base_ase * mult

def ekwan_cost_for_tier(base: float, tier: int) -> float:
    # Cost = base * (1.25)^(tier-1)
    return base * (1.25 ** (tier - 1))

def morale_decay_step(morale: float, fear: float, guardian=False) -> float:
    # Morale_next = Morale - (Fear/10)^(exp) , exp=1.2 (or 1.0 with guardian)
    exponent = 1.0 if guardian else 1.2
    return morale - ((fear / 10.0) ** exponent)

def faith_recovery_step(faith: float, harmony: float) -> float:
    # Faith_{t+1} = Faith_t + (100 - Faith_t) * 0.05 * (Harmony/100)
    return faith + (100.0 - faith) * 0.05 * (harmony / 100.0)

def harmony_efficiency(harmony: float) -> float:
    # Efficiency = 1 + 0.003*(Harmony - 50), clamp to [0.8, 1.25]
    eff = 1.0 + 0.003 * (harmony - 50.0)
    return max(0.8, min(1.25, eff))
