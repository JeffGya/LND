

extends Resource
class_name Echo

## Echo.gd — MVP hero schema (dictionary-first) + helpers (Subtask 4)
## Purpose
##   Define a minimal, stable record for a freshly summoned Echo (Rank 1 / Uncalled),
##   and provide small helpers to build and validate records. Gender is metadata-only.
##   This file does NOT persist; SaveService/HeroesIO handle that.
##
## Determinism contract
##   • name, gender, traits, seed are derived in EchoFactory from a local RNG seeded with
##     (campaign_seed + EconomyConstants.RNG_CHANNEL_SUMMON + roster_count).
##   • id is assigned by HeroesIO.append_hero() at persistence time (1..N).
##
## Backward compatibility
##   • Older saves without `gender` must still validate (treated as present-but-unknown by UI).

# ----------------------
# Helpers: construction
# ----------------------
static func make(
	id: int,
	name: String,
	rank: int,
	class_code: String,
	gender: String,
	traits: Dictionary,
	seed: int,
	created_utc: String
) -> Dictionary:
	# Build a sanitized hero dictionary. Does not auto-assign id.
	# Normal flow: EchoFactory creates without id, HeroesIO assigns id.
	var hero := {
		"id": id,
		"name": name,
		"rank": rank,
		"class": class_code,
		"gender": gender, # "female" | "male" (metadata only)
		"traits": traits,
		"seed": seed,
		"created_utc": created_utc
	}
	return hero

# ----------------------
# Helpers: validation
# ----------------------
static func validate(h: Dictionary) -> Dictionary:
	# Returns { ok: bool, message: String }
	if typeof(h) != TYPE_DICTIONARY:
		return {"ok": false, "message": "echo must be a Dictionary"}

	# Required fields at summon birth (id may be missing before append_hero)
	var name_ok := typeof(h.get("name", null)) == TYPE_STRING and String(h.name) != ""
	var rank_ok := typeof(h.get("rank", null)) == TYPE_INT and int(h.rank) >= 1
	var class_ok := typeof(h.get("class", null)) == TYPE_STRING
	var traits_ok := typeof(h.get("traits", null)) == TYPE_DICTIONARY
	var seed_ok := typeof(h.get("seed", null)) == TYPE_INT
	var created_ok := typeof(h.get("created_utc", null)) == TYPE_STRING and String(h.created_utc) != ""

	if not name_ok:
		return {"ok": false, "message": "name must be non-empty string"}
	if not rank_ok:
		return {"ok": false, "message": "rank must be int >= 1"}
	if not class_ok:
		return {"ok": false, "message": "class must be string code"}
	if not traits_ok:
		return {"ok": false, "message": "traits must be Dictionary"}
	if not seed_ok:
		return {"ok": false, "message": "seed must be int"}
	if not created_ok:
		return {"ok": false, "message": "created_utc must be non-empty string"}

	# Class code check against EchoConstants (if available globally)
	var class_code: String = String(h.class)
	var allowed_classes := [
		EchoConstants.CLASS_NONE,
		EchoConstants.CLASS_GUARDIAN,
		EchoConstants.CLASS_WARRIOR,
		EchoConstants.CLASS_ARCHER
	]
	if not (class_code in allowed_classes):
		return {"ok": false, "message": "class code not recognized: %s" % class_code}

	# Gender (metadata-only): allow missing for back-compat; if present, must be valid.
	if h.has("gender"):
		var g := String(h.gender)
		var allowed_genders := [EchoConstants.GENDER_FEMALE, EchoConstants.GENDER_MALE]
		if not (g in allowed_genders):
			return {"ok": false, "message": "gender must be 'female' or 'male' if present"}
	else:
		# Back-compat: allow missing gender
		pass

	# Traits: require courage/wisdom/faith ints; allow 0..100 at validator level
	var tr := h.traits as Dictionary
	for key in ["courage", "wisdom", "faith"]:
		if typeof(tr.get(key, null)) != TYPE_INT:
			return {"ok": false, "message": "traits.%s must be int" % key}
		var v: int = int(tr[key])
		if v < 0 or v > 100:
			return {"ok": false, "message": "traits.%s out of range 0..100" % key}

	# Optional fields accepted without further checks (future-friendly)
	# - suggested_class: String
	# - tags: Array[String]

	return {"ok": true, "message": "OK"}