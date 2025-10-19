extends Node

class_name XXHash64
#

const PRIME64_1: int = -7046029288634856825
const PRIME64_2: int = -4417276706812531889
const PRIME64_3: int = 1609587929392839161
const PRIME64_4: int = -8796714831421723037
const PRIME64_5: int = 2870177450012600261
# All 64 bits set. Using -1 avoids an overflow when parsing unsigned hex.
const MASK64: int   = -1

static func _rotl164(x:int, r: int) -> int:
	var n = ((x << r) & MASK64) | ((x & MASK64) >> (64 - r))
	return n & MASK64

static func _read64_le(b: PackedByteArray, i: int) -> int:
	var v: int = 0
	#build litte-endian 64-bit int from 8 bytes
	v |= int (b[i + 0]) << 0
	v |= int (b[i + 1]) << 8
	v |= int (b[i + 2]) << 16
	v |= int (b[i + 3]) << 24
	v |= int (b[i + 4]) << 32
	v |= int (b[i + 5]) << 40
	v |= int (b[i + 6]) << 48
	v |= int (b[i + 7]) << 56
	return v & MASK64
	
static func _read32_le(b: PackedByteArray, i:int) -> int:
	var v: int = 0
	#build litte-endian 32-bit in from 8 bytes
	v |= int (b[i + 0]) << 0
	v |= int (b[i + 1]) << 8
	v |= int (b[i + 2]) << 16
	v |= int (b[i + 3]) << 24
	return v & MASK64
	
static func xxh64_string(s: String, seed: int = 0) -> int:
	return xxh64(s.to_utf8_buffer(), seed)
	#Helper to hash a string directly
	
static func xxh64(data: PackedByteArray, seed: int = 0) -> int:
	#XXH64 algorithm implementation
	var p: int = 0
	var len: int = data.size()
	var h: int
	
	# Main loop
	if len >= 32:
		var v1 = (seed + PRIME64_1 + PRIME64_2) & MASK64
		var v2 = (seed + PRIME64_2) & MASK64
		var v3 = (seed + 0) & MASK64
		var v4 = (seed - PRIME64_1) & MASK64
		
		var limit = len - 32
		while p <= limit:
			var m1 = _read64_le(data, p);   p += 8
			v1 = (v1 + (m1 * PRIME64_2 & MASK64)) & MASK64
			v1 = _rotl164(v1, 31)
			v1 = (v1 + PRIME64_1) & MASK64
			
			var m2 = _read64_le(data, p);   p += 8
			v2 = (v2 + (m2 * PRIME64_2 & MASK64)) & MASK64
			v2 = _rotl164(v2, 31)
			v2 = (v2 + PRIME64_1) & MASK64
			
			var m3 = _read64_le(data, p);   p += 8
			v3 = (v3 + (m3 * PRIME64_2 & MASK64)) & MASK64
			v3 = _rotl164(v3, 31)
			v3 = (v3 + PRIME64_1) & MASK64
			
			var m4 = _read64_le(data, p);   p += 8
			v4 = (v4 + (m4 * PRIME64_2 & MASK64)) & MASK64
			v4 = _rotl164(v4, 31)
			v4 = (v4 + PRIME64_1) & MASK64

		h = (_rotl164(v1, 1) + _rotl164(v2, 7) + _rotl164(v3, 12) + _rotl164(v4, 18)) & MASK64
		# Merge round
	else: 
		h = (seed + PRIME64_5) & MASK64

	# Process remaining block (up to 32 bytes already consumed). Each block is 8 bytes.
	# 8-byte chunks
	while (p + 8) <= len:
		var k1 = _read64_le(data, p);  p += 8
		h = (h ^ (_rotl164((k1 * PRIME64_2) & MASK64, 31) * PRIME64_1 & MASK64)) & MASK64
		h = ((_rotl164(h, 27) * PRIME64_1) + PRIME64_4) & MASK64
		# Process remaining bytes (0 to 7 bytes)

	# 4-byte chunk
	if (p + 4) <= len:
		var k2 = _read32_le(data, p);  p += 4
		h = (h ^ ((k2 * PRIME64_1) & MASK64)) & MASK64
		h = ((_rotl164(h, 23) + PRIME64_2) + PRIME64_3) & MASK64

	# Remaining tail bytes
	while p < len:
		var k3 = int(data[p]);  p += 1
		h = (h ^ ((k3 * PRIME64_5) & MASK64)) & MASK64
		h = _rotl164(h, 11)
		h = (h * PRIME64_1) & MASK64
	
	# avalanche (final mix)
	h ^= (h >> 33)
	h = (h * PRIME64_2) & MASK64
	h ^= (h >> 29)
	h = (h * PRIME64_3) & MASK64
	h ^= (h >> 32)
	return h & MASK64

		
		
		
