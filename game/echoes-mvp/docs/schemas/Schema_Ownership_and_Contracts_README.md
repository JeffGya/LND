# Save Schema — Ownership & Contracts (MVP)

**Goal.** Lock module boundaries and “who writes what,” so every value has a single **authoritative writer** and deterministic replays remain stable. Canon: §13 principles (Schema-first, Modules-not-monoliths, Determinism-by-default) and the example minimal save.

## Root Save (container)

- **Keys:** `schema_version`, `build_id`, `created_utc`, `last_saved_utc`, `content_hash`, `integrity`, plus all modules.
- **Writes:** `SaveService` (timestamps, content hash), never by feature systems.
- **Notes:** Versioning/migrations per §13.3/13.9; local saves, optional cloud later.

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
| `content_hash`, `integrity.signed`               | Loader, Anti-tamper                                 | **SaveService**                                    | Hash over canonical order; optional signing later. |

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
- **telemetry_log**: `ring[]`, `cursor`, `enabled`  
- **rng_book**: `campaign_seed` (top), optional `subseeds{system→seed}`, optional `cursors{system→pcg_state}` when mid-run  

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
  "telemetry_log": { "ring": [], "cursor": 0, "enabled": true },
  "content_hash": "",
  "integrity": { "signed": false }
}
```