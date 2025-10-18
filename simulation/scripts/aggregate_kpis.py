"""Aggregate Pass-02 simulation KPIs and emit MVP-ready number sheets."""

from __future__ import annotations

import csv
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List

SIMULATION_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = SIMULATION_ROOT.parent
LOG_DIR = SIMULATION_ROOT / "logs"
DOCS_DIR = PROJECT_ROOT / "docs" / "simulation"

RUN_FILES = {
    "ritual_preload": "_reg_preload.json",
    "faith_floor": "_reg_faithfloor.json",
    "harmony_low": "_reg_harm_low.json",
    "harmony_high": "_reg_harm_high.json",
    "spike_guard_stress": "_reg_stress.json",
}

READY_DEFAULTS = {
    "SPIKE_GUARD_THRESHOLD": 90,
    "WARD_BEADS_CHARGES_PER_20D": 2,
    "COURAGE_SKIP_CONDITION": "(fear < 60) AND (morale > 70)",
    "FAITH_GUARDRAIL": {
        "threshold": 60,
        "floor": 62,
        "ase_cost": 15,
        "required_days": 2,
    },
    "RETIREMENT_RITE": {
        "min_streak": 10,
        "favor_cost": 3,
    },
    "HARMONY_BRIGHT_ZONE": "55–60 (target ≥55)",
}


@dataclass
class RunSummary:
    name: str
    final_ase: float
    final_faith: float
    final_harmony: float
    final_favor: float
    final_morale: float
    final_fear: float
    legacy_fragments: int
    voluntary_retirements: int
    ase_yield_day1: float
    ase_yield_day20: float
    morale_min: float
    fear_max: float
    spike_guard_used: int
    courage_ritual_used: int
    courage_ritual_skipped: int
    ward_beads_used: int
    reflection_prayer_used: int
    voluntary_retirement_flags: int

    @classmethod
    def from_payload(cls, name: str, payload: dict) -> "RunSummary":
        final = payload["final"]
        log = payload["log"]

        def _count(flag: str) -> int:
            return sum(1 for entry in log if entry.get(flag))

        morale_min = min(entry["morale"] for entry in log)
        fear_max = max(entry["fear"] for entry in log)

        return cls(
            name=name,
            final_ase=final["ase"],
            final_faith=final["faith"],
            final_harmony=final["harmony"],
            final_favor=final["favor"],
            final_morale=final["morale"],
            final_fear=final["fear"],
            legacy_fragments=final["legacy_fragments"],
            voluntary_retirements=final["voluntary_retirements"],
            ase_yield_day1=log[0]["ase_yield"],
            ase_yield_day20=log[-1]["ase_yield"],
            morale_min=morale_min,
            fear_max=fear_max,
            spike_guard_used=_count("spike_guard_used"),
            courage_ritual_used=_count("courage_ritual_used"),
            courage_ritual_skipped=_count("courage_ritual_skipped"),
            ward_beads_used=_count("ward_beads_used"),
            reflection_prayer_used=_count("reflection_prayer_used"),
            voluntary_retirement_flags=_count("voluntary_retirement"),
        )

    def as_csv_row(self) -> List[str]:
        return [
            self.name,
            f"{self.final_ase:.2f}",
            f"{self.final_faith:.2f}",
            f"{self.final_harmony:.2f}",
            f"{self.final_favor:.2f}",
            f"{self.final_morale:.2f}",
            f"{self.final_fear:.2f}",
            str(self.legacy_fragments),
            str(self.voluntary_retirements),
            f"{self.ase_yield_day1:.2f}",
            f"{self.ase_yield_day20:.2f}",
            f"{self.morale_min:.2f}",
            f"{self.fear_max:.2f}",
            str(self.spike_guard_used),
            str(self.courage_ritual_used),
            str(self.courage_ritual_skipped),
            str(self.ward_beads_used),
            str(self.reflection_prayer_used),
            str(self.voluntary_retirement_flags),
        ]


def _ensure_dirs() -> None:
    DOCS_DIR.mkdir(parents=True, exist_ok=True)


def _load_runs() -> List[RunSummary]:
    runs: List[RunSummary] = []
    for name, filename in RUN_FILES.items():
        payload_path = LOG_DIR / filename
        if not payload_path.exists():
            raise FileNotFoundError(f"Missing required log: {payload_path}")
        payload = json.loads(payload_path.read_text())
        runs.append(RunSummary.from_payload(name, payload))
    return runs


def _write_csv(runs: Iterable[RunSummary]) -> None:
    csv_path = DOCS_DIR / "mvp_ready_numbers.csv"
    header = [
        "run_name",
        "final_ase",
        "final_faith",
        "final_harmony",
        "final_favor",
        "final_morale",
        "final_fear",
        "legacy_fragments",
        "voluntary_retirements",
        "ase_yield_day1",
        "ase_yield_day20",
        "morale_min",
        "fear_max",
        "spike_guard_used",
        "courage_ritual_used",
        "courage_ritual_skipped",
        "ward_beads_used",
        "reflection_prayer_used",
        "voluntary_retirement_flags",
    ]
    with csv_path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        for run in runs:
            writer.writerow(run.as_csv_row())


def _format_defaults_md() -> str:
    lines = ["**Ship-these defaults (Pass-02):**"]
    lines.append("- `SPIKE_GUARD_THRESHOLD = 90`")
    lines.append("- `WARD_BEADS_CHARGES_PER_20D = 2`")
    lines.append("- `COURAGE_SKIP_CONDITION = (fear < 60) AND (morale > 70)`")
    lines.append(
        "- `FAITH_GUARDRAIL = {threshold: 60, floor: 62, ase_cost: 15, required_days: 2}`"
    )
    lines.append("- `RETIREMENT_RITE = {min_streak: 10, favor_cost: 3}`")
    lines.append("- `HARMONY_BRIGHT_ZONE = 55–60 (target ≥55)`")
    return "\n".join(lines)


def _write_md(runs: Iterable[RunSummary]) -> None:
    md_path = DOCS_DIR / "mvp_ready_numbers.md"
    runs_list = list(runs)
    table_header = (
        "| Run | Final Ase | Morale Min | Fear Max | Fragments | Voluntary Retirements |\n"
        "| --- | --- | --- | --- | --- | --- |"
    )
    table_rows = [
        "| {name} | {ase:.2f} | {morale_min:.2f} | {fear_max:.2f} | {fragments} | {vol_ret} |".format(
            name=run.name,
            ase=run.final_ase,
            morale_min=run.morale_min,
            fear_max=run.fear_max,
            fragments=run.legacy_fragments,
            vol_ret=run.voluntary_retirements,
        )
        for run in runs_list
    ]

    detail_lines = [
        "", "**Key KPIs (Ase/Faith/Harmony/Favor/Morale/Fear/Flags)**", ""
    ]
    for run in runs_list:
        detail_lines.append(
            f"- **{run.name}** → Final Ase {run.final_ase:.2f}, Faith {run.final_faith:.2f}, "
            f"Harmony {run.final_harmony:.2f}, Favor {run.final_favor:.2f}, "
            f"Morale {run.final_morale:.2f}, Fear {run.final_fear:.2f}; "
            f"Spike Guard {run.spike_guard_used}x, Courage used {run.courage_ritual_used}x "
            f"(skipped {run.courage_ritual_skipped}x), Ward Beads {run.ward_beads_used}x, "
            f"Reflection/Prayer {run.reflection_prayer_used}x, Voluntary retirements {run.voluntary_retirement_flags}x."
        )

    content = [
        "# MVP-ready Numbers (Pass-02)",
        "",
        table_header,
        *table_rows,
        "",
        _format_defaults_md(),
        *detail_lines,
    ]
    md_path.write_text("\n".join(content) + "\n")


def main() -> None:
    _ensure_dirs()
    runs = _load_runs()
    _write_csv(runs)
    _write_md(runs)


if __name__ == "__main__":
    main()
