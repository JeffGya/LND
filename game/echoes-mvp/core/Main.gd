extends Node

func roll_faith(base: int, bonus: int) -> int:
	return base + bonus
	
func _ready():
	var	courage = 5
	var fear = 2
	var faith = courage - fear
	print("Faith:", faith)

	var heroes = ["Odo", "Anansi", "Agyanka"]
	var stats = {"faith": 10, "harmony": 6, "favor": 4}
	print("Heroes:", heroes)
	print("Faith stat:", stats["faith"])
	
	for h in heroes:
		if h == "Anansi":
			print(h, " is the Trickster.")
		else:
			print(h, " is loyal to the Web.")
			
	var result = roll_faith(5, 3)
	print("faith roll result:", result) 
	print("------------------")

	print("--- xxh64 quick test ---")
	print("'' => ", XXHash64.xxh64_string(""))
	print("'Echoes' => ", XXHash64.xxh64_string("Echoes"))
	print("'ɔ' => ", XXHash64.xxh64_string("ɔ"))
	
	var h = XXHash64.xxh64_string("Echoes")
	print("Echoes (hex) => ", "0x%016X" % h)
