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


def _parse_bool(value: str) -> bool:
    """Accept a variety of truthy / falsy CLI inputs."""

    if isinstance(value, bool):  # argparse may pass in already parsed bools
        return value

    normalized = value.strip().lower()
    if normalized in {"1", "true", "t", "yes", "y", "on"}:
        return True
    if normalized in {"0", "false", "f", "no", "n", "off"}:
        return False
    raise argparse.ArgumentTypeError(
        "Expected a boolean value (true/false). Received: %s" % value
    )


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
        "--courage_auto_days",
        dest="courage_auto_days",
        metavar="day=list",
        type=_parse_day_list,
        default=(5, 15),
        help="Default Courage ritual cadence when no explicit day list is provided",
    )
    parser.add_argument(
        "--auto_courage_days",
        dest="courage_auto_days",
        metavar="day=list",
        type=_parse_day_list,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--ward_beads_auto_days",
        dest="ward_beads_auto_days",
        metavar="day=list",
        type=_parse_day_list,
        default=(5, 15),
        help="Default Ward Beads cadence when no explicit day list is provided",
    )
    parser.add_argument(
        "--auto_ward_beads_days",
        dest="ward_beads_auto_days",
        metavar="day=list",
        type=_parse_day_list,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--ward_beads_charges",
        dest="ward_beads_charges",
        type=int,
        default=2,
        help="Total Ward Beads charges available for the campaign",
    )
    parser.add_argument(
        "--ward_bead_charges",
        dest="ward_beads_charges",
        type=int,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--skip_courage_when_comfortable",
        type=_parse_bool,
        default=True,
        help="Whether to skip Courage rituals when fear is low and morale is high",
    )
    parser.add_argument(
        "--disable_courage_skip",
        action="store_true",
        help="Deprecated. Use --skip_courage_when_comfortable=false to force rituals",
    )
    parser.add_argument(
        "--spike_guard_enabled",
        type=_parse_bool,
        default=True,
        help="Toggle the automatic Spike Guard fear mitigation",
    )
    parser.add_argument(
        "--disable_spike_guard",
        action="store_true",
        help="Deprecated. Use --spike_guard_enabled=false instead",
    )
    parser.add_argument(
        "--spike_guard_threshold",
        type=float,
        default=90.0,
        help="Fear forecast value that triggers the Spike Guard auto-ritual",
    )
    parser.add_argument(
        "--faith_guardrail_threshold",
        type=float,
        default=60.0,
        help="Faith value that the guardrail monitors",
    )
    parser.add_argument(
        "--faith_guardrail_required_days",
        dest="faith_guardrail_required_days",
        type=int,
        default=2,
        help="Consecutive days below the threshold before Reflection/Prayer fires",
    )
    parser.add_argument(
        "--faith_guardrail_days",
        dest="faith_guardrail_required_days",
        type=int,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--faith_guardrail_floor",
        type=float,
        default=62.0,
        help="Faith floor applied when the guardrail triggers",
    )
    parser.add_argument(
        "--faith_guardrail_ase_cost",
        dest="faith_guardrail_ase_cost",
        type=float,
        default=15.0,
        help="Ase cost of triggering the Reflection/Prayer guardrail",
    )
    parser.add_argument(
        "--faith_guardrail_cost",
        dest="faith_guardrail_ase_cost",
        type=float,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--retirement_rite_enabled",
        type=_parse_bool,
        default=True,
        help="Toggle the voluntary retirement rite unlocked by Spike Guard streaks",
    )
    parser.add_argument(
        "--disable_retirement_rite",
        action="store_true",
        help="Deprecated. Use --retirement_rite_enabled=false instead",
    )
    parser.add_argument(
        "--retirement_rite_min_streak",
        dest="retirement_rite_min_streak",
        type=int,
        default=10,
        help="Number of Spike Guard days required before the retirement rite unlocks",
    )
    parser.add_argument(
        "--retirement_rite_streak",
        dest="retirement_rite_min_streak",
        type=int,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--retirement_rite_favor_cost",
        type=float,
        default=3.0,
        help="Favor spent when the retirement rite is performed",
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

    skip_courage_when_comfortable = args.skip_courage_when_comfortable
    if getattr(args, "disable_courage_skip", False):
        skip_courage_when_comfortable = False

    spike_guard_enabled = args.spike_guard_enabled
    if getattr(args, "disable_spike_guard", False):
        spike_guard_enabled = False

    retirement_rite_enabled = args.retirement_rite_enabled
    if getattr(args, "disable_retirement_rite", False):
        retirement_rite_enabled = False

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
        courage_auto_days=args.courage_auto_days,
        ward_beads_auto_days=args.ward_beads_auto_days,
        ward_beads_charges=args.ward_beads_charges,
        skip_courage_when_comfortable=skip_courage_when_comfortable,
        spike_guard_enabled=spike_guard_enabled,
        spike_guard_threshold=args.spike_guard_threshold,
        faith_guardrail_threshold=args.faith_guardrail_threshold,
        faith_guardrail_required_days=args.faith_guardrail_required_days,
        faith_guardrail_floor=args.faith_guardrail_floor,
        faith_guardrail_ase_cost=args.faith_guardrail_ase_cost,
        retirement_rite_enabled=retirement_rite_enabled,
        retirement_rite_min_streak=args.retirement_rite_min_streak,
        retirement_rite_favor_cost=args.retirement_rite_favor_cost,
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
