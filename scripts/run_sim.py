"""Command line harness for the Echoes of the Sankofa MVP sim."""

import argparse
import json
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOG_PATH = PROJECT_ROOT / "simulation_logs" / "latest_run.json"

if PROJECT_ROOT.as_posix() not in sys.path:
    sys.path.insert(0, PROJECT_ROOT.as_posix())

from sankofa_sim import SimConfig, run_economy_sim


def _parse_day_list(value: str) -> tuple[int, ...]:
    """Parse a CLI `day=1,2,3` style option into a tuple of day indices."""

    if not value:
        return ()

    if "=" in value:
        key, _, payload = value.partition("=")
        if key.strip().lower() not in {"day", "days"}:
            raise argparse.ArgumentTypeError(
                f"Expected prefix 'day=' or 'days=', received '{value}'."
            )
    else:
        payload = value

    if not payload:
        raise argparse.ArgumentTypeError("Day list cannot be empty.")

    try:
        days = tuple(sorted({int(part.strip()) for part in payload.split(",") if part.strip()}))
    except ValueError as exc:  # pragma: no cover - argparse surface ensures message
        raise argparse.ArgumentTypeError("Day list must contain integers.") from exc

    if any(day <= 0 for day in days):
        raise argparse.ArgumentTypeError("Days must be positive integers.")

    return days


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the Echoes of the Sankofa deterministic sim")
    parser.add_argument("--days", type=int, default=20, help="Number of in-sim days to process")
    parser.add_argument("--tier", type=int, default=1, help="Realm tier for ekwan scaling")
    parser.add_argument(
        "--encounters",
        type=int,
        default=2,
        help="Expected encounters per day before deterministic flux",
    )
    parser.add_argument("--fear", type=float, default=5.0, help="Fear added per encounter")
    parser.add_argument("--guardian", action="store_true", help="Toggle Guardian presence for morale mitigation")
    parser.add_argument(
        "--seed",
        type=lambda value: int(value, 0),
        default=0xA2B94D10,
        help="Campaign seed (accepts decimal or 0x-prefixed hex)",
    )
    parser.add_argument(
        "--faith_init",
        type=float,
        default=60.0,
        help="Initial Faith value for the Sanctum globals",
    )
    parser.add_argument(
        "--harmony_init",
        type=float,
        default=55.0,
        help="Initial Harmony value for the Sanctum globals",
    )
    parser.add_argument(
        "--favor_init",
        type=float,
        default=20.0,
        help="Initial Favor value for the Sanctum globals",
    )
    parser.add_argument(
        "--use_courage_ritual",
        metavar="day=list",
        type=_parse_day_list,
        default=(),
        help="Comma-separated day list for triggering the Courage ritual (e.g. day=5,12)",
    )
    parser.add_argument(
        "--use_ward_beads",
        metavar="day=list",
        type=_parse_day_list,
        default=(),
        help="Comma-separated day list for Ward Beads mitigation (e.g. day=4,9)",
    )
    parser.add_argument(
        "--log",
        nargs="?",
        type=Path,
        const=DEFAULT_LOG_PATH,
        help=(
            "Persist the JSON report to disk. Provide a path or pass the flag alone to use "
            "simulation_logs/latest_run.json under the repository root."
        ),
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    cfg = SimConfig(
        campaign_seed=args.seed,
        days=args.days,
        realm_tier=args.tier,
        encounters_per_day=args.encounters,
        fear_per_encounter=args.fear,
        guardian_present=args.guardian,
        faith_initial=args.faith_init,
        harmony_initial=args.harmony_init,
        favor_initial=args.favor_init,
        courage_ritual_days=args.use_courage_ritual,
        ward_beads_days=args.use_ward_beads,
    )
    result = run_economy_sim(cfg)

    log_path: Path | None = args.log
    if log_path is not None:
        if not log_path.is_absolute():
            log_path = (PROJECT_ROOT / log_path).resolve()

        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(json.dumps(result, indent=2))

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
