extends RefCounted
class_name XXHash64

const PRIME1: int = -7046029288634856825 # 11400714785074694791 modulo 2^64
const PRIME2: int = -4417276706812531889 # 14029467366897019727 modulo 2^64
const PRIME3: int = 1609587929392839161
const PRIME4: int = -8796714831421723037 # 9650029242287828579 modulo 2^64
const PRIME5: int = 2870177450012600261
const UINT64_MASK: int = -1 # bit pattern 0xFFFFFFFFFFFFFFFF in two's complement

static func xxh64(data: PackedByteArray, seed: int = 0) -> int:
    var length: int = data.size()
    var remaining: int = length
    var idx: int = 0
    var hash: int
    var seed64: int = seed & UINT64_MASK

    if length >= 32:
        var v1: int = (seed64 + PRIME1 + PRIME2) & UINT64_MASK
        var v2: int = (seed64 + PRIME2) & UINT64_MASK
        var v3: int = seed64 & UINT64_MASK
        var v4: int = (seed64 - PRIME1) & UINT64_MASK
        while remaining >= 32:
            v1 = _round(v1, _read64(data, idx))
            idx += 8
            v2 = _round(v2, _read64(data, idx))
            idx += 8
            v3 = _round(v3, _read64(data, idx))
            idx += 8
            v4 = _round(v4, _read64(data, idx))
            idx += 8
            remaining -= 32
        hash = (_rotl64(v1, 1) + _rotl64(v2, 7) + _rotl64(v3, 12) + _rotl64(v4, 18)) & UINT64_MASK
    else:
        hash = (seed64 + PRIME5) & UINT64_MASK

    hash = (hash + length) & UINT64_MASK

    while remaining >= 8:
        var k1: int = _round(0, _read64(data, idx))
        hash ^= k1
        hash = (_rotl64(hash, 27) * PRIME1 + PRIME4) & UINT64_MASK
        idx += 8
        remaining -= 8

    while remaining >= 4:
        hash ^= ((_read32(data, idx) & 0xFFFFFFFF) * PRIME1) & UINT64_MASK
        hash = (_rotl64(hash, 23) * PRIME2 + PRIME3) & UINT64_MASK
        idx += 4
        remaining -= 4

    while remaining > 0:
        hash ^= ((data[idx] & 0xFF) * PRIME5) & UINT64_MASK
        hash = (_rotl64(hash, 11) * PRIME1) & UINT64_MASK
        idx += 1
        remaining -= 1

    hash ^= hash >> 33
    hash = (hash * PRIME2) & UINT64_MASK
    hash ^= hash >> 29
    hash = (hash * PRIME3) & UINT64_MASK
    hash ^= hash >> 32

    return hash & UINT64_MASK

static func xxh64_string(s: String, seed: int = 0) -> int:
    var data := s.to_utf8_buffer()
    return xxh64(data, seed)

static func _round(acc: int, input: int) -> int:
    acc = (acc + (input & UINT64_MASK) * PRIME2) & UINT64_MASK
    acc = _rotl64(acc, 31)
    acc = (acc * PRIME1) & UINT64_MASK
    return acc & UINT64_MASK

static func _read32(data: PackedByteArray, offset: int) -> int:
    var result: int = 0
    for i in range(4):
        result |= (data[offset + i] & 0xFF) << (8 * i)
    return result & 0xFFFFFFFF

static func _read64(data: PackedByteArray, offset: int) -> int:
    var result: int = 0
    for i in range(8):
        result |= (data[offset + i] & 0xFF) << (8 * i)
    return result & UINT64_MASK

static func _rotl64(value: int, count: int) -> int:
    count &= 63
    return ((value << count) & UINT64_MASK) | ((value & UINT64_MASK) >> (64 - count))
