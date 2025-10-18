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
    courage_auto_days: tuple[int, ...] = (5, 15)
    ward_beads_auto_days: tuple[int, ...] = (5, 15)
    ward_beads_charges: int = 2
    skip_courage_when_comfortable: bool = True
    spike_guard_enabled: bool = True
    spike_guard_threshold: float = 90.0
    faith_guardrail_threshold: float = 60.0
    faith_guardrail_required_days: int = 2
    faith_guardrail_floor: float = 62.0
    faith_guardrail_ase_cost: float = 15.0
    retirement_rite_enabled: bool = True
    retirement_rite_min_streak: int = 10
    retirement_rite_favor_cost: float = 3.0


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
    courage_ritual_skipped: bool
    spike_guard_used: bool
    reflection_prayer_used: bool
    voluntary_retirement: bool


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
    if not courage_days:
        courage_days = set(cfg.courage_auto_days)
    auto_ward_schedule: set[int] = set()
    if not ward_beads_days and cfg.ward_beads_charges > 0:
        auto_ward_schedule = set(cfg.ward_beads_auto_days)

    ward_bead_charges_remaining = max(0, cfg.ward_beads_charges)
    courage_resistance_remaining = 0
    spike_guard_prevented_days = 0
    voluntary_retirements = 0
    faith_guardrail_streak = 0

    for day in range(1, cfg.days + 1):
        fear = _clamp(fear - 5.0, 0.0, 100.0)
        morale = _clamp(morale + 5.0, 0.0, 100.0)

        encounter_flux = 0.9 + 0.2 * rng.random()
        encounters_today = max(1, int(round(cfg.encounters_per_day * encounter_flux)))

        planned_courage = day in courage_days
        courage_ritual_skipped = False
        if (
            planned_courage
            and cfg.skip_courage_when_comfortable
            and fear < 60.0
            and morale > 70.0
        ):
            courage_ritual_skipped = True
            planned_courage = False

        ward_beads_today = False
        if day in ward_beads_days or day in auto_ward_schedule:
            if ward_bead_charges_remaining > 0:
                ward_beads_today = True
                ward_bead_charges_remaining -= 1

        forecast_fear_gain = encounters_today * cfg.fear_per_encounter
        forecast_fear = _clamp(fear + forecast_fear_gain, 0.0, 100.0)
        spike_guard_today = False
        if cfg.spike_guard_enabled and forecast_fear >= cfg.spike_guard_threshold:
            spike_guard_today = True
            fear = _clamp(fear - 18.0, 0.0, 100.0)
            morale = _clamp(morale + 12.0, 0.0, 100.0)
            spike_guard_prevented_days += 1

        harmony_eff = harmony_efficiency(sanctum.harmony)

        # Ase generation: Faith resonance first, Harmony lifts second (canon §12.1, §12.5)
        ase_tick = ase_yield_per_tick(cfg.base_ase_tick, sanctum.faith)
        ase_yield = ase_tick * harmony_eff

        # Realm upkeep: spend ekwan, upkeep drains ase reserves (canon §12.2)
        ekwan_spend = ekwan_cost_for_tier(cfg.base_ekwan_cost, realm.tier)
        sanctum.ekwan = _clamp(sanctum.ekwan - ekwan_spend, 0.0, 9999.0)
        sanctum.ase = max(0.0, sanctum.ase + ase_yield - ekwan_spend * 0.35)

        # Courage rituals fire before the encounters begin; they pre-buffer morale and reduce fear
        courage_ritual_today = planned_courage
        if courage_ritual_today:
            fear = _clamp(fear - 20.0, 0.0, 100.0)
            morale = _clamp(morale + 25.0, 0.0, 100.0)
            courage_resistance_remaining = max(courage_resistance_remaining, 8)

        # Fear pressure shaped by encounters; Guardians mitigate decay (canon §12.3)
        guardian_today = cfg.guardian_present or sanctum.favor >= 65.0
        fear_gain_multiplier = 1.0
        if guardian_today:
            fear_gain_multiplier *= 0.85
        if courage_resistance_remaining > 0:
            fear_gain_multiplier *= 0.5
        if ward_beads_today:
            fear_gain_multiplier *= 0.8
        if spike_guard_today:
            fear_gain_multiplier *= 0.7
        fear_gain = encounters_today * cfg.fear_per_encounter * fear_gain_multiplier
        fear = _clamp(fear + fear_gain, 0.0, 100.0)
        morale = _clamp(morale_decay_step(morale, fear, guardian=guardian_today), 0.0, 100.0)

        if courage_resistance_remaining > 0:
            fear = _clamp(fear - 5.0, 0.0, 100.0)

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

        reflection_prayer_used = False
        if sanctum.faith < cfg.faith_guardrail_threshold:
            faith_guardrail_streak += 1
        else:
            faith_guardrail_streak = 0
        if (
            cfg.faith_guardrail_required_days > 0
            and faith_guardrail_streak >= cfg.faith_guardrail_required_days
        ):
            sanctum.faith = max(sanctum.faith, cfg.faith_guardrail_floor)
            sanctum.ase = max(0.0, sanctum.ase - cfg.faith_guardrail_ase_cost)
            reflection_prayer_used = True
            faith_guardrail_streak = 0

        voluntary_retirement_today = False
        if (
            cfg.retirement_rite_enabled
            and spike_guard_today
            and spike_guard_prevented_days >= cfg.retirement_rite_min_streak
        ):
            legacy_fragments += 1
            voluntary_retirements += 1
            sanctum.favor = _clamp(
                sanctum.favor - cfg.retirement_rite_favor_cost, 0.0, 100.0
            )
            voluntary_retirement_today = True
            spike_guard_prevented_days = 0

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
                courage_ritual_skipped=courage_ritual_skipped,
                spike_guard_used=spike_guard_today,
                reflection_prayer_used=reflection_prayer_used,
                voluntary_retirement=voluntary_retirement_today,
            )
        )

        if courage_resistance_remaining > 0:
            courage_resistance_remaining -= 1

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
            "voluntary_retirements": voluntary_retirements,
        },
        "log": [asdict(entry) for entry in log],
    }


if __name__ == "__main__":
    import json

    result = run_economy_sim(SimConfig())
    print(json.dumps(result, indent=2))
