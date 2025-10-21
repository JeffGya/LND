extends Resource
class_name PlayerProfileIO

## PlayerProfileIO — packs/unpacks the `player_profile` module for SaveService (Task 4)
## Schema (docs/schemas/json/player_profile.schema.json):
##   keeper_id:    string (^[a-z0-9_\-]{3,64}$)
##   display_name: string (1..40)
##   options: {
##     ui: {
##       lang:       enum["en","nl","lt","fr"],
##       text_speed: int 0..200,
##       theme?:     enum["system","light","dark"] (default "system"),
##       font_scale?:number 0.8..1.6 (default 1.0)
##     }
##   }
## Design notes (Task 4 scope):
##   • Stateless adapter with static methods so SaveService can call directly.
##   • pack_default()/pack_current() return safe defaults (no dependency yet).
##   • unpack() validates payload; wiring to a real Profile/Settings system is a later task.

const LANGS := ["en","nl","lt","fr"]
const THEMES := ["system","light","dark"]

# -------------------------------------------------------------
# Public API used by SaveService (stateless)
# -------------------------------------------------------------

## Default profile for a brand new game (used by SaveService.new_game)
static func pack_default() -> Dictionary:
	return {
		"keeper_id": "kp_demo",
		"display_name": "Keeper",
		"options": {
			"ui": { "lang": "en", "text_speed": 30, "theme": "system", "font_scale": 1.0 }
		}
	}

## Export current runtime profile.
## Task 4: stateless → return defaults.
## Later: read from your real Profile/Settings subsystem.
static func pack_current() -> Dictionary:
	return pack_default()

## Import a saved profile back into runtime.
## Task 4: validate only; real writes happen when the subsystem exists.
static func unpack(d: Dictionary) -> void:
	var res := _validate(d)
	if not res.ok:
		push_warning("PlayerProfileIO.unpack: invalid data: %s" % res.message)
		return
	# TODO (later): write values into your Settings/Profile subsystem
	pass

# -------------------------------------------------------------
# Validation (schema-inspired, fast, no deps)
# -------------------------------------------------------------
static func _validate(d: Dictionary) -> Dictionary:
	for k in ["keeper_id","display_name","options"]:
		if not d.has(k):
			return {"ok": false, "message": "Missing key: %s" % k}

	# keeper_id pattern
	if typeof(d.keeper_id) != TYPE_STRING:
		return {"ok": false, "message": "keeper_id must be string"}
	var re: RegEx = RegEx.new()
	re.compile("^[a-z0-9_\\-]{3,64}$")
	if re.search(d.keeper_id as String) == null:
		return {"ok": false, "message": "keeper_id format invalid"}

	# display_name length 1..40
	if typeof(d.display_name) != TYPE_STRING:
		return {"ok": false, "message": "display_name must be string"}
	var name_str: String = String(d.display_name)
	var ln: int = name_str.length()
	if ln < 1 or ln > 40:
		return {"ok": false, "message": "display_name length out of range"}

	# options.ui
	if typeof(d.options) != TYPE_DICTIONARY:
		return {"ok": false, "message": "options must be object"}
	var ui: Dictionary = ((d.options as Dictionary).get("ui", {}) as Dictionary)

	# ui must be a dictionary already (typed above); a missing ui will be {}.
	# ui.lang enum
	var lang: String = String((ui as Dictionary).get("lang", ""))
	if not LANGS.has(lang):
		return {"ok": false, "message": "options.ui.lang not allowed"}

	# ui.text_speed int 0..200
	var ts: int = int((ui as Dictionary).get("text_speed", -1))
	if ts < 0 or ts > 200:
		return {"ok": false, "message": "options.ui.text_speed out of range"}

	# ui.theme enum (optional)
	if (ui as Dictionary).has("theme"):
		var theme: String = String((ui as Dictionary).get("theme", "system"))
		if not THEMES.has(theme):
			return {"ok": false, "message": "options.ui.theme not allowed"}

	# ui.font_scale number 0.8..1.6 (optional)
	if (ui as Dictionary).has("font_scale"):
		var fs: float = float((ui as Dictionary).get("font_scale", 1.0))
		if fs < 0.8 or fs > 1.6:
			return {"ok": false, "message": "options.ui.font_scale out of range"}

	return {"ok": true, "message": "OK"}