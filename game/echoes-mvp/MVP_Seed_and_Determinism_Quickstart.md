
# Echoes of the Sankofa — Project Seed & Determinism (MVP Quickstart)

This document is the **plain‑English quickstart** and working record for the deterministic
randomness backbone of *Echoes of the Sankofa*. It captures the goal, golden outputs,
tests, and a step‑by‑step plan you can follow when you come back later.

> Stack: **Godot 4.5.1**, GDScript 2.0

---

## User Story
**As the Keeper**, I want a **project seed** so that **every run is reproducible**.

- **Epic:** Core Architecture  
- **Description:** Implement deterministic PRNG keyed by `campaign_seed` and `realm_index`.  
- **Definition of Done:** Same seed + inputs yield identical combat/economy results across 3 runs.  
- **Test Goal:** 3 identical logs for same seed; diffs = 0.  
- **Status:** ✅ Completed

---

## Golden Outputs (Captured)

### xxHash64 — inputs → outputs

```gdscript
print("---xxHash64---")
var samples := {
    "empty": "",
    "unicode": "🔥Kɔmfo Anokye",
    "long": "a".repeat(10000)
}
for label in samples.keys():
    var input: String = samples[label] as String
    var result := XXHash64.xxh64_string(input)
    print("Case:", label, " | Len:", input.length(), " | Hash:", result)
```

```
Case:empty   | Len:0    | Hash:0
Case:unicode | Len:13   | Hash:8496348338565623266
Case:long    | Len:10000| Hash:6893206685342155747
```

---

### PCG32 — first 5 values (seed=1234, stream=54)

```gdscript
print("---PCG32---")
var rng := PCG32.new_with_seed(1234, 54)
for i in 5:
    var u := rng.next_u32()
    var f := rng.next_float()
    print("%d) u32=%d  float=%.9f" % [i, u, f])
```

```
0) u32=4193222502  float=0.376567555
1) u32=242571458   float=0.707251755
2) u32=2891569919  float=0.955728725
3) u32=4174923486  float=0.839528796
4) u32=3000596469  float=0.717952453
```

---

### PCG32 — State Snapshot / Restore

```gdscript
print("---PCG32 State Snapshot/Restore Test---")
var rng := PCG32.new_with_seed(1234, 54)

# A) Generate a few numbers, then snapshot
var a := [rng.next_u32(), rng.next_u32(), rng.next_u32()]
var snap := rng.get_state()
print("A:", a)
print("SNAP:", snap)

# B) Target-after-restore (generate a few more)
var b := [rng.next_u32(), rng.next_u32(), rng.next_u32()]
print("B (target after restore):", b)

# C) Restore and re-generate the continuation
rng.set_state(snap)
var c := [rng.next_u32(), rng.next_u32(), rng.next_u32()]
print("C (post-restore):", c)

# D) Assert: B must equal C
var ok := true
for i in b.size():
    if b[i] != c[i]:
        ok = false
print(ok ? "✅ MATCH" : "❌ MISMATCH") # in your project, use: print("✅ MATCH" if ok else "❌ MISMATCH")
```

```
A:[3826417493, 4102556865, 474782379]
SNAP:{ "state": 1377691269448988657, "inc": 109 }
B (target after restore):[418673013, 2950122839, 2803101778]
C (post-restore):[418673013, 2950122839, 2803101778]
✅ MATCH
```

---

### PRNG Jump/Advance — Golden Proof

- `n = 5`  
- Manual (n+1)th: `4104823617`  
- After `advance(5)`: `4104823617`  
- **Result:** ✅ MATCH

---

### SeedBook — Stable Fixture Table (excerpt)

```
--- SeedBook Fixture Table (stable) ---
system        | combat                      | dec:1195301280834276115 | hex:0x1096902e93b24b13
system        | economy                     | dec:4463852070861744932 | hex:0x3df2c9ced59b2b24
realm         | index=0                     | dec:2770344413565040869 | hex:0x26723d90f40838e5
realm         | index=1                     | dec:887037025251806833  | hex:0x0c4f637988c0ce71
scope         | realm/0/encounter/5/loot    | dec:9130591803003094695 | hex:0x7eb660de6f17c6a7
salt          | combat:damage               | dec:9218301653111611244 | hex:0x7fedfc834a1d1f6c
salt          | combat:ai                   | dec:4869069954819743916 | hex:0x43926953938ee0ac
--- END SeedBook Fixture Table ---
```

---

### SeedService — Snapshot & Restore

```gdscript
func _test_seed_snapshot() -> void:
    print("--- SeedService Snapshot/Restore Test ---")
    var cs: int = 885677476959259660
    SeedService.init_with_campaign(cs)

    var rc := SeedService.rng_for_system("combat")
    var re := SeedService.rng_for_system("economy")
    for i in 3: rc.next_u32()
    for i in 2: re.next_u32()

    # ✅ snapshot BEFORE consuming target values
    var snap := SeedService.snapshot_state()

    var target := {
        "combat": [rc.next_u32(), rc.next_u32()],
        "economy": [re.next_u32(), re.next_u32()]
    }

    # advance more (prove we really rewind)
    rc.next_u32(); re.next_u32()

    # restore + replay
    SeedService.restore_state(snap)
    var rc2 := SeedService.rng_for_system("combat")
    var re2 := SeedService.rng_for_system("economy")
    var post := {
        "combat": [rc2.next_u32(), rc2.next_u32()],
        "economy": [re2.next_u32(), re2.next_u32()]
    }

    var ok: bool = (target["combat"] == post["combat"] and target["economy"] == post["economy"])
    print("targets:", target)
    print("post:   ", post)
    print("✅ MATCH" if ok else "❌ MISMATCH")
```

```
--- SeedService Snapshot/Restore Test ---
targets:{ "combat": [3600588411, 2914913640], "economy": [3260992829, 435540303] }
post:   { "combat": [3600588411, 2914913640], "economy": [3260992829, 435540303] }
✅ MATCH
```

---

### Demo Simulation Harness — Log (seed = 885677476959259660)

```
=== Demo Simulation Log ===
Campaign seed: 885677476959259660
----------------------------
Realm 0 rolls: 2093865368 1420137437 1993308040
Realm 1 rolls: 1741053570 1135886616 1993624344
Combat rolls: 4185992746 2362145864 3185324784
Economy rolls: 3618154731 2696923235 3260992829
Loot table rolls: 3685681655 3645414381 3467428717 639901778 3875161794
----------------------------
Simulation complete.
```

---

## Subtasks & Plan of Attack (Quick Reference)

### Phase 2 — PRNG (PCG32)
5) **PCG32.gd** (core): state, `new_with_seed(seed, stream)`, `next_u32()`, `next_float()`  
   - Mask with `MASK64 = -1` after `+`, `*`, and shifts.  
6) **PCG32 State Save/Restore**: `get_state()`/`set_state(d)` — continuation identical after restore.  
7) **PRNG Jump/Advance**: `advance(n)` naive loop; equality holds for `n = 1, 5, 20`.

### Phase 3 — Seed Derivation (pure)
8) **SeedBook.gd**: `derive_for_realm`, `derive_for_system`, `derive_for_scope` via `XXHash64.xxh64_string`.  
9) **SeedBook Fixtures**: print table; re-run is byte‑identical.

### Phase 4 — Seed Service (AutoLoad)
10) **SeedService.gd**: `init_with_campaign(seed)`, factories `rng_for_*`, cache by key.  
11) **SeedService Snapshot/Restore**: `snapshot_state()`, `restore_state(d)` — streams continue identically.

### Phase 5 — Demo & Acceptance
12) **DemoSimHarness.gd/.tscn**: build one deterministic multiline log; two runs identical.  
13) **Determinism Test** (later): run 3× with same seed (equal) and once with different seed (diverges).

### Phase 6 — Debug UI & Docs
14) **DebugReplayPanel.tscn/.gd**: UI to Init / Snapshot / Restore / Run Demo log.  
15) **README & How‑to**: this file.

---

## Troubleshooting Cheatsheet (Godot 4.5)

- **AutoLoad Collision:** “Invalid name. Must not collide…” → remove `class_name SeedService` from the script before adding AutoLoad named `SeedService`.
- **Non‑static call error:** Don’t `preload("SeedService.gd")` when using AutoLoad; call `SeedService.*` directly.
- **UI Sizing:** In Godot 4.5, **Size Flags** appear as **Container Sizing**. Set Horizontal=`Fill`, Vertical=`Expand`. Add **Custom Min Size Y=280** to the log box.
- **Ternary `?:` not supported:** Use Python-style: `A if cond else B`.
- **64‑bit mask:** Use `const MASK64: int = -1` (two’s complement) instead of `0xFFFFFFFFFFFFFFFF` to avoid warnings.
- **All zeros from PRNG:** Check `_step()` math and ensure `_inc` is odd. Example step:
  ```gdscript
  _state = (((_state * 6364136223846793005) & MASK64) + _inc) & MASK64
  ```
- **Advance mismatch:** Compare `advance(n); next_u32()` to the manual `(n+1)`th from the same start.
- **Snapshot mismatch:** **Snapshot first**, then record target rolls; restore should reproduce those exact next values.

---

## File Map (where things live)

```
echoes-mvp/
├─ core/
│  ├─ seed/
│  │  ├─ XXHash64.gd
│  │  ├─ PCG32.gd
│  │  ├─ SeedBook.gd
│  │  └─ SeedService.gd   # AutoLoad name: SeedService
│  ├─ sim/
│  │  ├─ DemoSimHarness.tscn
│  │  └─ demo_sim_harness.gd  # has static build_log(seed)
│  └─ ui/
│     ├─ DebugReplayPanel.tscn
│     └─ DebugReplayPanel.gd
└─ tests/
   ├─ test_hash_edge_cases.gd
   └─ stability_test.gd
```

---

## Next (later) — Optional Quality of Life
- Panel button **Copy Log** → `DisplayServer.clipboard_set(Output.text)`
- Button **Run Twice (Compare)** using `DemoSimHarness.build_log()` → print `✅ MATCH` if identical strings
- JSON save/load wrappers for `SeedService` state (persistence task)
- Persist last seed in config or ProjectSettings

---

**That’s it.** If you forget everything: run `DemoSimHarness.tscn` twice with the same seed.  
If the logs match byte‑for‑byte, your deterministic backbone is green.
