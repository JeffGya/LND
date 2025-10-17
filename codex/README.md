
# Echoes of the Sankofa — Project Codex (Starter)

This folder is your **Codex** — the living index of canon, systems, and runnable sims.
Full project Game design document is in docs/canon. Read that to get a full understanding of the project. Always refer to that first. 

## What’s inside
- `Canon Map.md` — crosswalk back to the canonical **Legacy Never Dies** GDD.
- `Simulation Guide.md` — how to run and extend the MVP economy/morale sim.
- `Data Contracts.md` — JSON shapes used by the sim (kept minimal).

## Quick start (local)
```bash
# 1) Extract the zip, then:
cd echoes_codex_starter
python -m venv .venv && source .venv/bin/activate  # Windows: .venv\Scripts\activate
python -m pip install --upgrade pip

# 2) Run a 20-day Tier-1 baseline
python scripts/run_sim.py --days 20 --tier 1 --seed 0xA2B94D10

# 3) Try a harsher world (Tier 5)
python scripts/run_sim.py --days 20 --tier 5
```

The output JSON includes a daily log you can graph or ingest into Notion.
