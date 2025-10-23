

## EconomyConstants.gd
## Canon trace: Implements §12 "Ase Yield Curve" from Legacy Never Dies.
## Formula: piecewise — low slope up to FAITH_KNEE, then high slope to hit 100→2.0 exactly,
## with continuity at the knee;
## final result clamped to [FAITH_MULT_MIN, FAITH_MULT_MAX].
## Targets for sanity checks: Faith 30≈0.7x; 50=1.0x; 70≈1.3x; 100=2.0x.

class_name EconomyConstants
extends Object

# --- Faith → Ase yield curve knobs (single source of truth) ---
const FAITH_SLOPE: float = 0.015
const FAITH_MULT_MIN: float = 0.5
const FAITH_MULT_MAX: float = 2.0
const FAITH_NEUTRAL: int = 50  # pivot around which 1.0x sits
const FAITH_KNEE: int = 70
const FAITH_HIGH_SLOPE: float = (FAITH_MULT_MAX - (1.0 + FAITH_SLOPE * float(FAITH_KNEE - FAITH_NEUTRAL))) / float(100 - FAITH_KNEE)

## Converts Faith (0–100) to an Ase yield multiplier per canon §12.
## Piecewise curve to hit targets exactly: 30→0.7, 50→1.0, 70→1.3, 100→2.0.
static func faith_to_multiplier(faith: int) -> float:
	var f := float(faith)
	var raw: float
	if f <= float(FAITH_KNEE):
		raw = 1.0 + FAITH_SLOPE * (f - float(FAITH_NEUTRAL))
	else:
		var knee_value := 1.0 + FAITH_SLOPE * float(FAITH_KNEE - FAITH_NEUTRAL)  # 1.3 at knee
		raw = knee_value + FAITH_HIGH_SLOPE * (f - float(FAITH_KNEE))
	return clampf(raw, FAITH_MULT_MIN, FAITH_MULT_MAX)
