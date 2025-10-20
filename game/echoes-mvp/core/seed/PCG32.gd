# PCG32 XSH-RR (32-bit output, 64-bit state), GDScript 4.x
class_name PCG32
extends RefCounted

const MASK64: int = -1  # two's-complement all-ones (0xFFFFFFFFFFFFFFFF) without literal overflow

var _state: int = 0
var _inc:   int = 0    # must be odd (stream selector)

static func new_with_seed(seed_value: int, stream: int = 54) -> PCG32:
	var rng := PCG32.new()
	# stream encoded as odd increment (<<1 | 1) per PCG spec
	rng._inc = ((stream << 1) | 1) & MASK64
	rng._inc |= 1  # ensure odd increment (defensive)
	# "warm up" state using one step to incorporate seed and stream
	rng._state = 0
	rng._step()                    # advance once with inc
	rng._state = (rng._state + (seed_value & MASK64)) & MASK64
	rng._step()
	return rng

# NOTE:
# GDScript ints are signed 64-bit. The literal 0xFFFFFFFFFFFFFFFF overflows
# at parse-time, so we use -1 which is the same all-ones bitmask in two's complement.
# Using `& MASK64` keeps arithmetic explicitly in the 64-bit lane.
func _step() -> void:
	# state = state * 6364136223846793005 + inc  (mod 2^64)
	_state = (((_state * 6364136223846793005) & MASK64) + _inc) & MASK64

func next_u32() -> int:
	# output function (XSH-RR): xorshift-high, then rotate-right
	var oldstate: int = _state
	_step()
	var xorshifted: int = int(((oldstate >> 18) ^ oldstate) >> 27) & 0xFFFFFFFF
	var rot: int = int(oldstate >> 59) & 31
	# rotate right 32-bit
	var out32: int = ((xorshifted >> rot) | (xorshifted << ((32 - rot) & 31))) & 0xFFFFFFFF
	return out32

func next_float() -> float:
	# Map to [0, 1) using 32-bit resolution
	return float(next_u32()) / 4294967296.0  # 2^32

# (Optional) helpers for later tasks
func get_state() -> Dictionary:
	return { "state": _state, "inc": _inc }

func set_state(d: Dictionary) -> void:
	_state = int(d.get("state", 0)) & MASK64
	_inc   = int(d.get("inc", 1)) & MASK64
