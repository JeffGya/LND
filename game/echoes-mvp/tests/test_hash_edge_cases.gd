extends Node
# NOTE: SeedService is an AutoLoad singleton (Project Settings → AutoLoad). Call it directly.
const XXHash64 = preload("res://core/seed/XXHash64.gd")
const PCG32    = preload("res://core/seed/PCG32.gd")
const SeedBook = preload("res://core/seed/SeedBook.gd")

func _ready():
	print("[TestHashEdgeCases] _ready")

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

	print("---PCG32---")
	var rng := PCG32.new_with_seed(1234, 54)
	for i in 5:
		var u := rng.next_u32()
		var f := rng.next_float()
		print("%d) u32=%d  float=%.9f" % [i, u, f])

	print("--PCG32 Complete--")
	
	print("---PCG32 State Snapshot/Restore Test---")

	# 	A) Generate a few numbers, then snapshot
	var a := [rng.next_u32(), rng.next_u32(), rng.next_u32()]
	var snap := rng.get_state()
	print("A:", a)
	print("SNAP:", snap)

	# B) Generate the next few numbers (these are the target-after-restore)
	var b := [rng.next_u32(), rng.next_u32(), rng.next_u32()]
	print("B (target after restore):", b)

	# C) Restore and re-generate the continuation
	rng.set_state(snap)
	var c := [rng.next_u32(), rng.next_u32(), rng.next_u32()]
	print("C (post-restore):", c)

	# D) Simple assertions (manual): B must equal C element-for-element
	var ok := true
	for i in b.size():
		if b[i] != c[i]: ok = false
	# Godot 4 uses Python-style inline if-else, not C-style ternary
	print("✅ MATCH" if ok else "❌ MISMATCH")

	print("--PCG32 State Snapshot/Restore Test Complete--")

	# --- PCG32 Advance(n) Test ---
	print("---PCG32 Advance(n) Test---")

	# 1) Start two identical generators
	var seed_val := 1234
	var stream_id := 54
	var base_a := PCG32.new_with_seed(seed_val, stream_id)
	var base_b := PCG32.new_with_seed(seed_val, stream_id)

	# 2) Manual path: call next_u32() n times, then take the (n+1)th as target
	var n: int = 5
	var manual_values := []
	for i in n + 1:
		manual_values.append(base_a.next_u32())
	var manual_target: int = manual_values.back()  # the value after n advances

	# 3) Advance path: skip n steps, then take the next_u32()
	base_b.advance(n)
	var advanced_value := base_b.next_u32()

	print("n =", n)
	print("Manual target after n steps:", manual_target)
	print("Advanced value:", advanced_value)
	print("✅ MATCH" if manual_target == advanced_value else "❌ MISMATCH")

	# 4) Quick edge cases
	# n == 0 should not move the generator
	var r0 := PCG32.new_with_seed(seed_val, stream_id)
	var r1 := PCG32.new_with_seed(seed_val, stream_id)
	r0.advance(0)
	print("n=0 same first value?",
		"✅" if r0.next_u32() == r1.next_u32() else "❌"
	)

	# n == 1 is just one step
	var r2 := PCG32.new_with_seed(seed_val, stream_id)
	var _v_manual_1 := r2.next_u32()  # discard first value
	var r3 := PCG32.new_with_seed(seed_val, stream_id)
	r3.advance(1)
	var v_advanced_1 := r3.next_u32() # should equal second manual value
	# Rebuild to get the second manual for clarity
	var r4 := PCG32.new_with_seed(seed_val, stream_id)
	r4.next_u32()  # discard first
	var second_manual := r4.next_u32()
	print("n=1 aligns with second manual?",
		"✅" if v_advanced_1 == second_manual else "❌"
	)

	# --- SeedBook Tests (pure derivations) ---

	print("---SeedBook Derivation Test---")
	var campaign_seed := SeedBook.campaign_seed_from_inputs("Player42", "Normal", "world:ghana")  # stable
	print("campaign_seed:", campaign_seed)

	var sys_combat := SeedBook.derive_for_system(campaign_seed, "Combat")
	var sys_econ   := SeedBook.derive_for_system(campaign_seed, "Economy")
	var realm0     := SeedBook.derive_for_realm(campaign_seed, 0)
	var realm1     := SeedBook.derive_for_realm(campaign_seed, 1)
	var scope_path := SeedBook.derive_for_scope(campaign_seed, "realm/1/encounter/5/loot")
	var combat_damage := SeedBook.derive_with_salt(campaign_seed, "combat", "damage")
	var combat_ai     := SeedBook.derive_with_salt(campaign_seed, "combat", "ai")

	print("sys_combat:", sys_combat)
	print("sys_econ:",   sys_econ)
	print("realm0:",     realm0)
	print("realm1:",     realm1)
	print("scope_path:", scope_path)
	print("combat_damage:", combat_damage)
	print("combat_ai:",     combat_ai)

	# Quick invariants (manual checks)
	# - Re-running should print EXACTLY the same numbers.
	# - Changing only the text (e.g., "Economy" -> "ECONOMY") should NOT change the value (canonicalization).
	# - Changing campaign_seed should change all derived values.
	
	_test_seed_service()

# --- SeedService Smoke Test ---
func _test_seed_service() -> void:
	print("--- SeedService Test ---")
	var cs: int = 885677476959259660  # paste your stable campaign seed here
	SeedService.init_with_campaign(cs)

	# 1) Fetch two different systems. They should not affect each other.
	var rng_combat := SeedService.rng_for_system("combat")
	var rng_econ   := SeedService.rng_for_system("economy")

	# Draw a couple values from each.
	var combat_vals := [rng_combat.next_u32(), rng_combat.next_u32()]
	var econ_vals   := [rng_econ.next_u32(),   rng_econ.next_u32()]
	print("combat:", combat_vals)
	print("economy:", econ_vals)

	# 2) Fetch the same system again. Should be the SAME instance (sequence continues).
	var rng_combat_again := SeedService.rng_for_system("combat")
	var combat_more := [rng_combat_again.next_u32()]
	print("combat (continued):", combat_more)

	# 3) Realms are independent from systems and from each other.
	var r0 := SeedService.rng_for_realm(0)
	var r1 := SeedService.rng_for_realm(1)
	print("realm0:", [r0.next_u32()])
	print("realm1:", [r1.next_u32()])

# Call this from your _ready() in the test scene after other tests, e.g.:
# _test_seed_service()
