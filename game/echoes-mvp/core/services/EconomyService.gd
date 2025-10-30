extends Node
class_name EconomyService

const EconBal = preload("res://core/config/GameBalance_EconomySanctum.gd")

## EconomyService — deterministic Ase↔Ekwan conversion façade
## Canon: fixed-rate batches (v1), integer-only, no negatives.
## Depends on: SaveService, EconomyConstants

# -------------------------------------------------------------
# Private helpers
# -------------------------------------------------------------
static func _get_rate() -> int:
	return int(EconBal.EXCHANGE_ASE_TO_EKWAN_RATE)

static func get_tick_config() -> Dictionary:
	return {
		"tick": EconBal.ASE_TICK_BASE,
		"bank_pulse": EconBal.ASE_BANK_PULSE,
		"min": EconBal.ASE_MIN,
		"max": EconBal.ASE_MAX,
	}

static func _result_fail(reason: String, rate: int) -> Dictionary:
	var d := {}
	d["ok"] = false
	d["reason"] = reason
	d["rate"] = rate
	return d

static func _result_success(pairs: Dictionary) -> Dictionary:
	# Shallow copy to avoid leaking references
	return pairs.duplicate(false)

static func _compute_ase_cost(requested_ase: int, rate: int) -> Dictionary:
	# Returns { batches:int, cost:int, leftover:int }
	var batches: int = 0
	var cost: int = 0
	var leftover: int = 0
	if rate <= 0:
		return {"batches": 0, "cost": 0, "leftover": requested_ase}
	if requested_ase <= 0:
		return {"batches": 0, "cost": 0, "leftover": 0}
	batches = requested_ase / rate    # integer division
	cost = batches * rate
	leftover = requested_ase - cost
	return {"batches": batches, "cost": cost, "leftover": leftover}

# Thin pass-through getters so callers only import EconomyService
static func get_ase_banked() -> int:
	return SaveService.economy_get_ase_int()

static func get_ase_effective() -> float:
	return SaveService.economy_get_ase_effective()

static func get_ekwan_banked() -> int:
	return SaveService.economy_get_ekwan()

static func get_ase_buffer() -> float:
	return SaveService.economy_get_ase_buffer()

# -------------------------------------------------------------
# Convenience primitives (single-currency deposit/spend)
# -------------------------------------------------------------
static func deposit_ase(amount: int) -> int:
	if amount <= 0:
		return SaveService.economy_get_ase_int()
	return SaveService.economy_adjust_ase(amount)

static func try_spend_ase(amount: int) -> Dictionary:
	var have: int = SaveService.economy_get_ase_int()
	if amount <= 0:
		return {"ok": true, "spent": 0, "remaining": have}
	if have < amount:
		return {"ok": false, "reason": "insufficient_funds", "have": have, "need": amount}
	var remaining: int = SaveService.economy_adjust_ase(-amount)
	return {"ok": true, "spent": amount, "remaining": remaining}

static func deposit_ekwan(amount: int) -> int:
	if amount <= 0:
		return SaveService.economy_get_ekwan()
	return SaveService.economy_adjust_ekwan(amount)

static func try_spend_ekwan(amount: int) -> Dictionary:
	var have: int = SaveService.economy_get_ekwan()
	if amount <= 0:
		return {"ok": true, "spent": 0, "remaining": have}
	if have < amount:
		return {"ok": false, "reason": "insufficient_funds", "have": have, "need": amount}
	var remaining: int = SaveService.economy_adjust_ekwan(-amount)
	return {"ok": true, "spent": amount, "remaining": remaining}

# -------------------------------------------------------------
# Public API
# -------------------------------------------------------------
## Convert Ase → Ekwan using strict integer batches.
## Returns on success:
##   { ok=true, ekwan_gained:int, ase_spent:int, leftover_ase_requested:int, rate:int }
## On failure:
##   { ok=false, reason:"insufficient_batch"|"insufficient_funds", rate:int }
static func trade_ase_to_ekwan(ase_to_spend: int) -> Dictionary:
	var rate: int = _get_rate()
	# Must meet at least one batch
	if ase_to_spend < rate:
		return _result_fail("insufficient_batch", rate)

	var have_ase: int = SaveService.economy_get_ase_int()
	var calc: Dictionary = _compute_ase_cost(ase_to_spend, rate)
	var batches: int = int(calc.get("batches", 0))
	var cost: int = int(calc.get("cost", 0))
	var leftover: int = int(calc.get("leftover", 0))
	if batches <= 0:
		return _result_fail("insufficient_batch", rate)
	if have_ase < cost:
		return _result_fail("insufficient_funds", rate)

	# Apply atomically: spend Ase, gain Ekwan
	var after_ase: int = SaveService.economy_adjust_ase(-cost)
	var ekwan_gained: int = batches
	var after_ekwan: int = SaveService.economy_adjust_ekwan(ekwan_gained)
	# after_* values are available if needed; we return deltas as per spec
	var out := {}
	out["ok"] = true
	out["ekwan_gained"] = ekwan_gained
	out["ase_spent"] = cost
	out["leftover_ase_requested"] = leftover
	out["rate"] = rate
	# Telemetry: record successful trade (INFO)
	SaveService.telemetry_append(
		"economy",
		"trade",
		{
			"dir": "ase_to_ekwan",
			"ase_delta": -cost,
			"ekwan_delta": ekwan_gained,
			"rate": rate
		},
		1
	)
	return _result_success(out)

## Convert Ekwan → Ase using strict integer math.
## Success: { ok=true, ase_gained:int, ekwan_spent:int, rate:int }
## Failure: { ok=false, reason:"insufficient_funds", rate:int }
static func trade_ekwan_to_ase(ekwan_to_spend: int) -> Dictionary:
	var rate: int = _get_rate()
	if ekwan_to_spend <= 0:
		return _result_fail("insufficient_batch", rate)
	var have_ekwan: int = SaveService.economy_get_ekwan()
	if have_ekwan < ekwan_to_spend:
		return _result_fail("insufficient_funds", rate)

	var ase_gain: int = ekwan_to_spend * rate
	var after_ekwan: int = SaveService.economy_adjust_ekwan(-ekwan_to_spend)
	var after_ase: int = SaveService.economy_adjust_ase(ase_gain)
	var out := {}
	out["ok"] = true
	out["ase_gained"] = ase_gain
	out["ekwan_spent"] = ekwan_to_spend
	out["rate"] = rate
	# Telemetry: record successful trade (INFO)
	SaveService.telemetry_append(
		"economy",
		"trade",
		{
			"dir": "ekwan_to_ase",
			"ase_delta": ase_gain,
			"ekwan_delta": -ekwan_to_spend,
			"rate": rate
		},
		1
	)
	return _result_success(out)

# -------------------------------------------------------------
# Instance wrappers (for contexts where the global class is unavailable)
# -------------------------------------------------------------
func trade_ase_to_ekwan_inst(ase_to_spend: int) -> Dictionary:
	return trade_ase_to_ekwan(ase_to_spend)

func trade_ekwan_to_ase_inst(ekwan_to_spend: int) -> Dictionary:
	return trade_ekwan_to_ase(ekwan_to_spend)

func add_ase_float(delta: float) -> float:
	return SaveService.economy_add_ase_float(delta)

func deposit_ase_inst(amount: int) -> int:
	return deposit_ase(amount)

func try_spend_ase_inst(amount: int) -> Dictionary:
	return try_spend_ase(amount)

func deposit_ekwan_inst(amount: int) -> int:
	return deposit_ekwan(amount)

func try_spend_ekwan_inst(amount: int) -> Dictionary:
	return try_spend_ekwan(amount)