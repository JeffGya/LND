extends Node
const XXHash64 = preload("res://core/seed/XXHash64.gd")
const PCG32    = preload("res://core/seed/PCG32.gd")

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
