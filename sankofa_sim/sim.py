"""Deterministic MVP simulation loop for Echoes of the Sankofa."""

from dataclasses import dataclass, asdict
from typing import Any, Dict, List

from .curves import (
    ase_yield_per_tick,
    ekwan_cost_for_tier,
    faith_recovery_step,
    harmony_efficiency,
    morale_decay_step,
)
from .models import RealmState, Sanctum
from .prng import PCG32


def _clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


@dataclass
class SimConfig:
    """Configuration for the deterministic loop."""

    campaign_seed: int = 0xA2B94D10
    days: int = 20
    base_ase_tick: float = 50.0  # canon §12.1 baseline resonance
    base_ekwan_cost: float = 10.0  # canon §12.2 tier upkeep seed
    realm_tier: int = 1
    fear_per_encounter: float = 5.0
    encounters_per_day: int = 2
    guardian_present: bool = False
    faith_initial: float = 60.0
    harmony_initial: float = 55.0
    favor_initial: float = 20.0
    courage_ritual_days: tuple[int, ...] = ()
    ward_beads_days: tuple[int, ...] = ()


@dataclass
class DailyLog:
    day: int
    ase: float
    faith: float
    harmony: float
    favor: float
    morale: float
    fear: float
    ase_yield: float
    ekwan_spend: float
    harmony_efficiency: float
    faith_recovered: float
    legacy_fragments: int
    courage_ritual_used: bool
    ward_beads_used: bool


def run_economy_sim(cfg: SimConfig) -> Dict[str, Any]:
    """Execute the MVP loop, fully driven by the campaign seed."""

    rng = PCG32(cfg.campaign_seed)
    sanctum = Sanctum()
    sanctum.faith = _clamp(cfg.faith_initial, 0.0, 100.0)
    sanctum.harmony = _clamp(cfg.harmony_initial, 10.0, 100.0)
    sanctum.favor = _clamp(cfg.favor_initial, 0.0, 100.0)
    realm = RealmState(tier=cfg.realm_tier)

    morale = 80.0
    fear = 25.0
    legacy_fragments = 0
    log: List[DailyLog] = []

    courage_days = set(cfg.courage_ritual_days)
    ward_beads_days = set(cfg.ward_beads_days)

    for day in range(1, cfg.days + 1):
        harmony_eff = harmony_efficiency(sanctum.harmony)

        # Ase generation: Faith resonance first, Harmony lifts second (canon §12.1, §12.5)
        ase_tick = ase_yield_per_tick(cfg.base_ase_tick, sanctum.faith)
        ase_yield = ase_tick * harmony_eff

        # Deterministic encounter variance uses the seeded PRNG for fairness (canon §12 fairness note)
        encounter_flux = 0.9 + 0.2 * rng.random()
        encounters_today = max(1, int(round(cfg.encounters_per_day * encounter_flux)))

        # Realm upkeep: spend ekwan, upkeep drains ase reserves (canon §12.2)
        ekwan_spend = ekwan_cost_for_tier(cfg.base_ekwan_cost, realm.tier)
        sanctum.ekwan = _clamp(sanctum.ekwan - ekwan_spend, 0.0, 9999.0)
        sanctum.ase = max(0.0, sanctum.ase + ase_yield - ekwan_spend * 0.35)

        # Fear pressure shaped by encounters; Guardians mitigate decay (canon §12.3)
        guardian_today = cfg.guardian_present or sanctum.favor >= 65.0
        ward_beads_today = day in ward_beads_days
        fear_gain = encounters_today * cfg.fear_per_encounter * (1.0 - (0.15 if guardian_today else 0.0))
        if ward_beads_today:
            fear_gain *= 0.8
        fear = _clamp(fear + fear_gain, 0.0, 100.0)
        morale = _clamp(morale_decay_step(morale, fear, guardian=guardian_today), 0.0, 100.0)

        courage_ritual_today = day in courage_days
        if courage_ritual_today:
            fear = _clamp(fear - 20.0, 0.0, 100.0)
            morale = _clamp(morale + 25.0, 0.0, 100.0)

        # Legacy continuity: morale collapse becomes fragments and a reset (canon §12.6)
        if morale <= 0.0:
            legacy_fragments += 1
            morale = 45.0
            fear = _clamp(fear * 0.6, 0.0, 100.0)

        # Faith rebounds with harmony; track recovery delta (canon §12.4)
        prior_faith = sanctum.faith
        sanctum.faith = _clamp(faith_recovery_step(sanctum.faith, sanctum.harmony), 0.0, 100.0)
        faith_recovered = sanctum.faith - prior_faith

        # Emotional globals remain consistent and interdependent (canon §12.5)
        harmony_shift = (sanctum.favor - 50.0) / 220.0 - fear / 500.0
        sanctum.harmony = _clamp(sanctum.harmony + harmony_shift, 10.0, 100.0)

        favor_shift = (sanctum.faith - 60.0) / 180.0 - encounters_today * 0.05
        sanctum.favor = _clamp(sanctum.favor + favor_shift, 0.0, 100.0)

        log.append(
            DailyLog(
                day=day,
                ase=round(sanctum.ase, 2),
                faith=round(sanctum.faith, 2),
                harmony=round(sanctum.harmony, 2),
                favor=round(sanctum.favor, 2),
                morale=round(morale, 2),
                fear=round(fear, 2),
                ase_yield=round(ase_yield, 2),
                ekwan_spend=round(ekwan_spend, 2),
                harmony_efficiency=round(harmony_eff, 3),
                faith_recovered=round(faith_recovered, 2),
                legacy_fragments=legacy_fragments,
                courage_ritual_used=courage_ritual_today,
                ward_beads_used=ward_beads_today,
            )
        )

    return {
        "config": asdict(cfg),
        "final": {
            "ase": round(sanctum.ase, 2),
            "faith": round(sanctum.faith, 2),
            "harmony": round(sanctum.harmony, 2),
            "favor": round(sanctum.favor, 2),
            "morale": round(morale, 2),
            "fear": round(fear, 2),
            "legacy_fragments": legacy_fragments,
        },
        "log": [asdict(entry) for entry in log],
    }


if __name__ == "__main__":
    import json

    result = run_economy_sim(SimConfig())
    print(json.dumps(result, indent=2))
