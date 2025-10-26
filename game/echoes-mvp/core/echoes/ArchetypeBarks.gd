# res://core/echoes/ArchetypeBarks.gd
# Tiny, deterministic helper for MVP arrival barks (intro lines).
# - Pure: no RNG, no state, no services.
# - Deterministic: same input archetype -> same output string.
# - Display-only: does not affect gameplay or saves.
# - Localization-ready: central table for easy future swap.

class_name ArchetypeBarks

# One-line arrival bark per archetype.
# Params:
#   arch:      String archetype key (e.g., "loyal", "canny")
#   hero_name: Provided for future formatting; unused in MVP to keep lines timeless.
# Returns:
#   A short, flavorful line. Fallback used for unknown keys.
static func arrival(arch: String, hero_name: String) -> String:
	# Canonical, lowercase keys expected. Guard against null/empty.
	var key := (arch if arch != null else "").strip_edges().to_lower()

	# Central table. Keep lines short, timeless, and non-modern slang.
	# Tone: confident, mythic-minimal, supportive of the Keeper role.
	# IMPORTANT: Do not include hero_name yet to keep lines reusable across locales.
	var LINES := {
		"loyal":      "I’ll hold the line. Say the word.",
		"proud":      "Watch closely—this will be done right.",
		"reflective": "I have questions… but I will walk with you.",
		"valiant":    "For the cause—point me to the breach.",
		"canny":      "We’ll take the smart path—fewer wounds, more wins.",
		"devout":     "Asé guides us. I will not falter.",
		"stoic":      "I’ve stood through worse. Let’s move.",
		"empathic":   "I’ll keep an eye on the others. We rise together.",
		"ambitious":  "Give me a challenge worth remembering."
	}

	# Deterministic fallback for unknown/missing keys.
	if not LINES.has(key):
		return "I’ll do my part."

	return LINES[key]