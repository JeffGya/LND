# Echoes of the Sankofa — Godot MVP

This folder now contains the determinism layer for the playable MVP. Drop the `echoes_mvp` project into your Godot 4 workspace to explore the procedural harness and replay tooling.

## Project layout

```
echoes_mvp/
  project.godot              # Autoload and project settings
  core/
    seed/                    # Seed derivation + PRNG implementations
    sim/                     # DemoSimHarness scene + script
  tests/                     # Determinism self-check scene/script
  ui/                        # DebugReplayPanel scene/script
```

### Autoload configuration

The project ships with the `SeedService` autoload registered in `project.godot`. If you add the scripts to an existing project copy the snippet below into your own `project.godot`:

```ini
[autoload]
SeedService="*res://core/seed/SeedService.gd"
```

This ensures every scene can retrieve deterministic PRNG instances that follow the GDD lineage.

## Running the demo harness

1. Open the `echoes_mvp` project in Godot 4.x.
2. Launch the `res://core/sim/DemoSimHarness.tscn` scene. It prints deterministic loot/initiative/enemy pack logs to the console for three encounters.
3. Re-run the scene multiple times—the output is byte-identical for the same campaign seed (`0xA2B94D10`).

## Determinism regression test

Run the `res://tests/TestDeterminism.tscn` scene to execute the acceptance test described in the GDD. It programmatically runs the harness three times, verifies the logs match, then swaps the campaign seed and ensures divergence.

## Debugging seeds interactively

Load `res://ui/DebugReplayPanel.tscn` alongside the harness (e.g., add it as a child of the root node) to inspect the seed lineage and exercise snapshot/restore. The “Snapshot” button prints the service state as JSON, and “Restore Snapshot” replays the harness from the captured state and confirms that the regenerated log matches the original.
