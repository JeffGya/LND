"""Command line harness for the Echoes of the Sankofa MVP sim."""

import argparse
import json

from sankofa_sim import SimConfig, run_economy_sim


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
    )
    result = run_economy_sim(cfg)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
