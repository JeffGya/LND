

# core/combat/EnemyFactory.gd
# -----------------------------------------------------------------------------
# MVP enemy generator: deterministic dummy packs for early combat testing.
# This module is pure (no singletons, no IO) so the same inputs → same outputs.
#
# Canon notes
#  - §3 Round cadence visibility: simple, readable enemies for early logs.
#  - §6 Realms later: we keep the API so internals can swap to realm packs.
#  - §9 Determinism: explicit seed; stable id order; no hidden randomness.
#  - §12 Balance: numbers are gentle placeholders until curves are wired.
# -----------------------------------------------------------------------------
class_name EnemyFactory

## MVP baseline stats for dummy enemies. Easy to read in logs.
const DUMMY_BASE := {
	"rank": 1,
	"hp": 10,
	"max_hp": 10,
	"atk": 3,
	"def": 1,
	"morale": 50,
	"fear": 0,
}

## Generates a deterministic array of dummy enemies for testing the round loop.
##
## @param count int - number of enemies desired (negative → clamped to 0)
## @param seed  int - explicit seed to ensure reproducible outputs
## @return Array[Dictionary] - enemies in stable order (id asc)
static func spawn_dummy_pack(count: int, seed: int) -> Array[Dictionary]:
	var n := max(count, 0)
	# We set up an RNG for future tiny variations, but keep MVP dummies fixed.
	# Keeping the RNG seeded ensures we can introduce realm-based variance later
	# without breaking the signature or determinism guarantees.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var out: Array[Dictionary] = []
	for i in range(n):
		var local_id := 1000 + i  # avoid clashing with typical hero ids
		var name := "Training Wraith #%d" % (i + 1)

		# Copy baseline and build the dictionary explicitly (no mutation of const)
		var enemy := {
			"id": local_id,
			"name": name,
			"rank": DUMMY_BASE.rank,
			"hp": DUMMY_BASE.hp,
			"max_hp": DUMMY_BASE.max_hp,
			"atk": DUMMY_BASE.atk,
			"def": DUMMY_BASE.def,
			"morale": DUMMY_BASE.morale,
			"fear": DUMMY_BASE.fear,
			"tags": ["dummy"],
		}

		out.append(enemy)

	# Defensive: ensure stable order by id even if future variants add shuffling.
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out