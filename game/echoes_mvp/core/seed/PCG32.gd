extends RefCounted
class_name PCG32

const MULTIPLIER: int = 6364136223846793005
const DEFAULT_INC: int = 1442695040888963407
const UINT32_MASK: int = 0xFFFFFFFF
const UINT64_MASK: int = -1 # bit pattern 0xFFFFFFFFFFFFFFFF in two's complement

var _state: int = 0
var _inc: int = DEFAULT_INC

static func new_with_seed(seed64: int) -> PCG32:
    var prng := PCG32.new()
    prng._state = 0
    prng._inc = ((seed64 & UINT64_MASK) << 1 | 1) & UINT64_MASK
    prng.next_u32()
    prng._state = (prng._state + (seed64 & UINT64_MASK)) & UINT64_MASK
    prng.next_u32()
    return prng

func next_u32() -> int:
    return _advance()

func next_float() -> float:
    return float(next_u32()) / 4294967296.0

func jump(delta: int) -> void:
    if delta <= 0:
        return
    var cur_mult: int = MULTIPLIER
    var cur_plus: int = _inc & UINT64_MASK
    var acc_mult: int = 1
    var acc_plus: int = 0
    var steps: int = delta
    while steps > 0:
        if (steps & 1) == 1:
            acc_mult = (acc_mult * cur_mult) & UINT64_MASK
            acc_plus = (acc_plus * cur_mult + cur_plus) & UINT64_MASK
        cur_plus = ((cur_mult + 1) * cur_plus) & UINT64_MASK
        cur_mult = (cur_mult * cur_mult) & UINT64_MASK
        steps >>= 1
    _state = (acc_mult * _state + acc_plus) & UINT64_MASK

func get_state() -> Dictionary:
    return {
        "state": _state & UINT64_MASK,
        "inc": _inc & UINT64_MASK,
    }

func set_state(d: Dictionary) -> void:
    _state = int(d.get("state", 0)) & UINT64_MASK
    _inc = int(d.get("inc", DEFAULT_INC)) & UINT64_MASK
    if (_inc & 1) == 0:
        _inc |= 1

func _advance() -> int:
    var oldstate: int = _state
    _state = (oldstate * MULTIPLIER + _inc) & UINT64_MASK
    var xorshifted: int = int(((oldstate >> 18) ^ oldstate) >> 27) & UINT32_MASK
    var rot: int = int(oldstate >> 59) & 31
    var result: int = (xorshifted >> rot) | ((xorshifted << ((32 - rot) & 31)) & UINT32_MASK)
    return result & UINT32_MASK
