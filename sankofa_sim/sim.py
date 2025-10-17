
from dataclasses import dataclass
from typing import Dict, Any, List
from .models import Sanctum, RealmState
from .curves import ase_yield_per_tick, ekwan_cost_for_tier, morale_decay_step, faith_recovery_step, harmony_efficiency
from .prng import PCG32

@dataclass
class SimConfig:
    campaign_seed: int = 0xA2B94D10
    days: int = 20
    base_ase_tick: float = 50.0         # abstract "tick" == daily yield unit
    base_ekwan_cost: float = 10.0       # baseline cost per day (scaled by tier)
    realm_tier: int = 1
    fear_per_encounter: float = 5.0
    encounters_per_day: int = 2

def run_economy_sim(cfg: SimConfig) -> Dict[str, Any]:
    rng = PCG32(cfg.campaign_seed)
    sanctum = Sanctum()
    realm = RealmState(tier=cfg.realm_tier)

    log: List[Dict[str, Any]] = []
    morale = 80.0
    fear = 30.0

    for day in range(1, cfg.days + 1):
        # Ase yield with faith modifier and harmony efficiency
        ase_yield = ase_yield_per_tick(cfg.base_ase_tick, sanctum.faith) * harmony_efficiency(sanctum.harmony)

        # Ekwan spending scaled by realm tier
        ekwan_spend = ekwan_cost_for_tier(cfg.base_ekwan_cost, realm.tier)

        sanctum.ase += ase_yield - (ekwan_spend / 10.0)  # abstract sink coupling
        sanctum.ekwan = max(0.0, sanctum.ekwan + (ekwan_spend * 0.1))  # pretend some is banked via drops

        # Run a simple morale/fear day with encounters
        local_morale = morale
        local_fear = fear
        for _ in range(cfg.encounters_per_day):
            local_fear += cfg.fear_per_encounter
            local_morale = morale_decay_step(local_morale, local_fear, guardian=False)
            if local_morale <= 0:
                local_morale = 0

        morale = max(0.0, min(100.0, local_morale))
        fear = min(100.0, local_fear)

        # Faith recovers daily based on harmony
        sanctum.faith = min(100.0, faith_recovery_step(sanctum.faith, sanctum.harmony))

        log.append({
            "day": day,
            "ase": round(sanctum.ase, 2),
            "faith": round(sanctum.faith, 2),
            "harmony": round(sanctum.harmony, 2),
            "morale": round(morale, 2),
            "fear": round(fear, 2),
            "ase_yield": round(ase_yield, 2),
            "ekwan_spend": round(ekwan_spend, 2),
        })

    return {
        "config": cfg.__dict__,
        "final": {
            "ase": round(sanctum.ase, 2),
            "faith": round(sanctum.faith, 2),
            "morale": round(morale, 2),
            "fear": round(fear, 2),
        },
        "log": log
    }

if __name__ == "__main__":
    out = run_economy_sim(SimConfig())
    import json
    print(json.dumps(out, indent=2))
