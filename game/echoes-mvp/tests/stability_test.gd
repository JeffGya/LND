# --- SeedBook Fixture Table Test ---
extends Node

const SeedBook = preload("res://core/seed/SeedBook.gd")

# Utility: print a row in a consistent format
static func _row(label: String, key: String, seed_val: int) -> void:
	# Fixed-width-ish formatting + hex for easy diffing
	var hex := "0x%016x" % [seed_val & 0xFFFFFFFFFFFFFFFF]
	var lbl := label.rpad(14, " ")
	var kpad := key.rpad(28, " ")
	print(lbl, "| ", kpad, "| dec:", str(seed_val), " | hex:", hex)

func _ready():
	print("--- SeedBook Fixture Table (stable) ---")

	# 1) Campaign seeds from human inputs (canonicalization check included)
	var campaigns: Array = [
		["Player42", "Normal", "world:ghana"],
		["player42", " normal ", "WORLD:GHANA"], # same after _canon
		["Kɔmfo🔥", "Hard", "world:odum"],
	]

	# Keep a small array to reuse below
	var campaign_seeds: Array[int] = []

	# Stable header
	print("Label         | Input                       | dec(64)               | hex(64)")
	print("--------------+----------------------------+-----------------------+----------------------")

	# A) campaign_seed_from_inputs
	for i in campaigns.size():
		var pid: String = campaigns[i][0]
		var mode: String = campaigns[i][1]
		var world: String = campaigns[i][2]
		var cs: int = SeedBook.campaign_seed_from_inputs(pid, mode, world)
		campaign_seeds.append(cs)
		_row("campaign["+str(i)+"]", "pid="+pid+"|mode="+mode+"|world="+world, cs)

	# B) derive_for_system (use first campaign as baseline)
	var cs0: int = campaign_seeds[0]
	var systems: Array[String] = ["combat", "economy", "ai", "Economy"] # last one should equal "economy"
	for sys in systems:
		var s := SeedBook.derive_for_system(cs0, sys)
		_row("system", sys, s)

	# C) derive_for_realm (0..3)
	for r in range(0, 4):
		var sr := SeedBook.derive_for_realm(cs0, r)
		_row("realm", "index="+str(r), sr)

	# D) derive_for_scope (hierarchical paths)
	var scopes: Array[String] = [
		"realm/0/encounter/5/loot",
		"realm/0/encounter/5/LOOT", # canonicalized to same
		"realm/1/encounter/12/reward"
	]
	for sc in scopes:
		var ss := SeedBook.derive_for_scope(cs0, sc)
		_row("scope", sc, ss)

	# E) derive_with_salt (split substreams)
	var salts: Array = [
		["combat", "damage"],
		["combat", "ai"],
		["economy", "shop"],
	]
	for pair in salts:
		var sw := SeedBook.derive_with_salt(cs0, pair[0], pair[1])
		_row("salt", pair[0]+":"+pair[1], sw)

	print("--- END SeedBook Fixture Table ---")
