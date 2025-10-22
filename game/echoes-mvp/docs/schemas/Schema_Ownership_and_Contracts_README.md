# Save Schema — Ownership & Contracts (MVP)

**Goal.** Lock module boundaries and “who writes what,” so every value has a single **authoritative writer** and deterministic replays remain stable. Canon: §13 principles (Schema-first, Modules-not-monoliths, Determinism-by-default) and the example minimal save.

## Root Save (container)

- **Keys:** `schema_version`, `build_id`, `created_utc`, `last_saved_utc`, `content_hash`, `integrity`, `replay_header`, plus all modules.
- **Writes:** `SaveService` (timestamps, content hash, replay_header), never by feature systems.
- **Notes:** Versioning/migrations per §13.3/13.9; local saves, optional cloud later.
- **Hash policy:** `content_hash` is computed over a *canonical* hash view (sorted keys, normalized numbers) and **excludes** `telemetry_log` and `replay_header` to avoid false mismatches.

---

## Ownership Table (one writer per field)

| Module / Field                                   | Reads (examples)                                  | **Single Writer (authoritative)**                  | Valid Range / Notes |
|---|---|---|---|
| `player_profile.keeper_id`, `display_name`, `options.*` | UI, Telemetry                                      | **ProfileSystem** / Settings                       | No PII; opaque IDs. |
| `campaign_run.mode`, `cycle_index`, `realm_selection[]`, `realm_order[]` | RealmRunner, UI                                     | **CampaignSystem**                                 | MVP: 2–3 realms/cycle. |
| `campaign_run.rng_book.*` (campaign seed, subseeds, cursors) | Combat, Loot, Realms                                | **SeedService**                                    | Seed hierarchy per §13.4; store cursors if mid-run. |
| `sanctum_state.wings_unlocked[]`, `upgrades.*`   | Crafting/Research, UI                              | **SanctumSystem**                                  | Unlock lists only grow in MVP. |
| `sanctum_state.emotions.{faith,harmony,favor}`   | Economy, Combat pacing, UI                         | **SanctumSystem**                                  | Faith 0–100; Harmony 0–100; Favor 0–100. Faith ↔ Ase per §12.3.1. |
| `sanctum_state.queues.{healing,research,crafting}` | TimerSystem, UI                                    | **SanctumSystem**                                  | UTC ISO8601 times only. |
| `hero_roster.active[]/recovering[]/retired[]/fallen[]` | Combat, Legacy, UI                                  | **HeroSystem**                                     | Moves between lists are atomic; stats below. |
| `hero_roster.*.stats.{hp,morale,fear}`           | Combat AI, UI                                      | **CombatSystem**                                   | Morale/Fear follow §12 curves; clamp sane bounds. |
| `hero_roster.*.traits`, `conditions`, `bonds`, `lineage_id`, `history.*` | Combat, Legacy, UI                                  | **HeroSystem**                                     | Traits are persistent identity; history is append-only. |
| `realm_states[].{realm_id,tier,realm_seed,stage_index,encounter_cursor,modifiers}` | RealmRunner, Combat                                | **RealmSystem**                                    | Seeds from `rng_book`; stage/encounter cursors advance deterministically. |
| `economy.ase`,`economy.ekwan`,`economy.relics[]` | Crafting, Research, UI                              | **EconomySystem**                                  | Ase↔Faith yield; Ekwan costs scale by Tier (§12). |
| `economy.yields.*`,`economy.sinks.*`             | Telemetry, UI                                      | **EconomySystem**                                  | Derived counters (day totals) for audits. |
| `research_crafting.research_tree`, `active_projects[]`, `known_recipes[]` | UI, Economy                                         | **ResearchCraftingSystem**                         | Queue caps; emotion gates per §11.12. |
| `legacy.fragments[]`, `legacy.lineages[]`, `legacy.memorials[]` | UI, HeroSystem                                      | **LegacySystem**                                   | Filled on permadeath/retirement (§10 lineage). |
| `telemetry_log.{ring,cursor,enabled}`            | QA tools, Balance analysis                          | **TelemetrySystem**                                | O(1) ring buffer; compact events per §15. |
| `content_hash`, `integrity.signed`, `replay_header`               | Loader, Anti-tamper                                | **SaveService**                                    | Canonical hash; excludes telemetry/replay_header. Replay header is regenerated on save. |

> **Rule:** Every field has exactly **one** writer. All other systems **read-only**. This avoids “last write wins” bugs and protects determinism.

---

## Minimal Field Lists (what must exist in MVP)

- **player_profile**: `keeper_id`, `display_name`, `options.ui.lang`  
- **campaign_run**: `mode`, `cycle_index`, `realm_selection[]`, `realm_order[]`, `rng_book{campaign_seed, subseeds, cursors?}`  
- **sanctum_state**: `wings_unlocked[]`, `emotions{faith,harmony,favor}`, `upgrades{}`, `queues{healing[],research[],crafting[]}`  
- **hero_roster**: `active[]/recovering[]/retired[]/fallen[]` with each hero matching §13.5.1  
- **realm_states[]**: `realm_id`, `tier`, `realm_seed`, `stage_index`, `encounter_cursor`, `modifiers{}`  
- **economy**: `ase`, `ekwan`, `relics[]`, `yields{daily_ase}`, `sinks{...}`. Faith↔Ase influence per §12.3.1  
- **research_crafting**: `research_tree`, `active_projects[]`, `known_recipes[]`  
- **legacy**: `fragments[]`, `lineages[]`, `memorials[]`  
- **replay_header** (written on save): `at_cursor{}`, `build_id`, `campaign_seed`, `realm_order[]`, `schema_version`
- **telemetry_log**: `ring[]`, `cursor`, `enabled`  

---

## Read/Write Contracts (practical rules)

1. **Seed & Replay:** Only `SeedService` derives/stores seeds; consumers get PRNGs via API, not by constructing their own.  
2. **Emotions are systemic:** Only `SanctumSystem` mutates Faith/Harmony/Favor; Economy/Combat read them to compute yields/risks per §12.  
3. **Economy invariants:** Ase/Ekwan deltas must flow through `EconomySystem` so sources/sinks ledger remains truthful.  
4. **Hero lifecycle:** Combat moves heroes between `active/recovering/fallen`; Legacy consumes `fallen/retired` to emit fragments/lineages.  
5. **Queues are authoritative:** Timed actions live under `sanctum_state.queues.*`; other systems may reference IDs but cannot mutate timers directly.  
6. **Telemetry is append-only:** Only TelemetrySystem appends to `ring`; no edits in place. Size is bounded; cursor wraps.  
7. **Save atomicity:** Only `SaveService` writes disk; it assembles modules via `pack_*` calls and validates shape before commit.  

---

## Example Skeleton (hand-craft once to guide schemas)

```json
{
  "schema_version": "13.0.0",
  "build_id": "0.1.0-mvp",
  "created_utc": "2025-10-21T00:00:00Z",
  "last_saved_utc": "",
  "player_profile": { "keeper_id": "kp_xxx", "display_name": "Keeper", "options": { "ui": { "lang": "en" } } },
  "campaign_run": { "mode": "MVP", "cycle_index": 1, "realm_selection": [], "realm_order": [], "rng_book": { "campaign_seed": "A2B9-4D10", "subseeds": {}, "cursors": {} } },
  "sanctum_state": { "wings_unlocked": [], "emotions": { "faith": 60, "harmony": 55, "favor": 10 }, "upgrades": {}, "queues": { "healing": [], "research": [], "crafting": [] } },
  "hero_roster": { "active": [], "recovering": [], "retired": [], "fallen": [] },
  "realm_states": [],
  "economy": { "ase": 0, "ekwan": 0, "relics": [], "yields": { "daily_ase": 0 }, "sinks": {} },
  "research_crafting": { "research_tree": { "faith": [], "war": [], "knowledge": [] }, "active_projects": [], "known_recipes": [] },
  "legacy": { "fragments": [], "lineages": [], "memorials": [] },
  "replay_header": { "campaign_seed": "2730052880", "realm_order": [], "build_id": "0.1.0-mvp", "schema_version": "13.0.0", "at_cursor": { "combat/battle/alpha": 10 } },
  "telemetry_log": { "ring": [], "cursor": 0, "enabled": true },
  "content_hash": "",
  "integrity": { "signed": false }
}
```

---

## Versioning & Migrations (SemVer, runtime policy)

**Single source of truth:** `SCHEMA_VERSION` is defined in `core/save/SaveService.gd` and written into every save under `schema_version`. The loader compares the incoming version against the code’s `SCHEMA_VERSION` and applies the rules below.

### SemVer rules
- **MAJOR** (breaking shape/meaning changes):
  - Different MAJOR in the save → **load is blocked** unless a specific migrator exists.
  - The current migrator stub returns an empty object to signal “blocked,” and the loader falls back to `.bak`.
- **MINOR** (additive, backward‑compatible):
  - Older MINOR (same MAJOR) → **allowed with a warning**; defaults for new optional fields are injected (e.g., `telemetry_log.enabled`, `cursor`, `ring`).
- **PATCH** (no shape change):
  - Always accepted silently.

### Determinism guarantees
- `campaign_run.rng_book` (campaign seed, subseeds, cursors) is **never modified** by generic migrations. Any change to seeds/cursors requires a dedicated migrator and a determinism test.

### Loader flow (SaveService)
1. Parse JSON → validate required modules & ranges.
2. Verify `content_hash` against the canonical hash view (sorted keys, normalized numbers, excludes telemetry/replay_header). If mismatch → try `.bak`.
3. `migrate(save)` → may enrich optional fields, or **block** (future/different MAJOR). If blocked or invalid after migration → try `.bak`.
4. On success → `_apply_unpack()` restores runtime state.

### Canonical hashing
Keys in dictionaries are sorted lexicographically and floats that represent whole numbers are normalized to integers before hashing. The hash view excludes `telemetry_log` and `replay_header` to keep integrity checks stable across parse/stringify and logging.

---

## Telemetry Log & Replay Header (v13.0.0 runtime format)

**Purpose:**  
Provide a bounded event log for lightweight observability and a small replay header
that external tools can use to reproduce deterministic runs.

### telemetry_log

- **Shape**
  ```json
  {
    "ring": [ { "t": "encounter_end", "utc": "2025-10-22T12:14:42Z", "realm": "ase-forest", "stage": 0, "encounter": 0, "seed": "combat/battle/alpha@10", "notes": "ok" } ],
    "cursor": 2,
    "enabled": true
  }
  ```
- **Behavior**
  - Fixed capacity = 256 events (oldest overwritten when full).  
  - `cursor` is the next write index → monotonic counter.  
  - `enabled` = false disables writes but preserves existing ring.  
  - Events are append-only; logging never mutates game state.

### replay_header

Written once per save by `SaveService` for debugging and replay indexing.

```json
{
  "campaign_seed": "2730052880",
  "realm_order": [],
  "build_id": "0.1.0-mvp",
  "schema_version": "13.0.0",
  "at_cursor": { "combat/battle/alpha": 10 }
}
```

- **Purpose:** Metadata for deterministic replays and QA audits.  
- **Authorship:** `SaveService` (assembled from `campaign_run.rng_book` and `CampaignRunIO`).  
- **Read-only:** ignored on load; regenerated on each save.  
- **Compatibility:** Additive (safe for MINOR version bumps).

### Validation Rules

- `ring` must be an array of objects.  
- `cursor` must be ≥ 0 (integer-like).  
- `enabled` must be boolean or 0/1.  
- `replay_header` is optional; if present, keys should match the shape above.

### Determinism Notes

Telemetry and replay_header are *observational only* and are excluded from
round-trip equality tests. They record, never influence, simulation outcomes.  
Additionally, both blocks are excluded from the `content_hash` integrity computation.

---

## Debug Save Panel (Task 10)
A minimal in-engine panel for QA to click **New / Save / Load / Validate / Snapshot** without running the script harness.

- **Files:** `core/ui/DebugSavePanel.tscn`, `core/ui/DebugSavePanel.gd`
- **What it shows:** RNG cursor for `combat/battle/alpha`, on-disk file summary, latest telemetry tail, and the `replay_header`.
- **Notes:** Uses the same `SaveService` pipeline (atomic write, backup, canonical hash) and respects the telemetry `enabled` flag.