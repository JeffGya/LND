

extends Node

# Economy trade tests (MVP)
# Runs via TestRunner by reflecting functions starting with `test_`.
# Uses EconomyService instance wrappers to avoid global class resolution issues.

const EconomyServiceScript = preload("res://core/services/EconomyService.gd")
@onready var _econ := EconomyServiceScript.new()

# ------------------------
# Helpers
# ------------------------
func _reset_economy() -> void:
	# Zero banked Ase
	var have_ase: int = int(EconomyServiceScript.get_ase_banked())
	if have_ase > 0:
		EconomyServiceScript.try_spend_ase(have_ase)
	elif have_ase < 0:
		EconomyServiceScript.deposit_ase(-have_ase)
	# Zero banked Ekwan
	var have_ek: int = int(EconomyServiceScript.get_ekwan_banked())
	if have_ek > 0:
		EconomyServiceScript.try_spend_ekwan(have_ek)
	elif have_ek < 0:
		EconomyServiceScript.deposit_ekwan(-have_ek)
	# Zero fractional buffer (runtime-only)
	var buf: float = float(EconomyServiceScript.get_ase_buffer())
	if absf(buf) > 0.0001:
		_econ.add_ase_float(-buf)

func _pass(name: String) -> void:
	print("[", name, "] PASS")

func _fail(name: String, msg: String) -> void:
	push_error("[" + name + "] FAIL: " + msg)

# ------------------------
# Tests
# ------------------------
func test_happy_path() -> bool:
	var NAME := "TestTrade: happy_path 500→1"
	_reset_economy()
	EconomyServiceScript.deposit_ase(500)
	var res: Dictionary = _econ.trade_ase_to_ekwan_inst(500)
	var ase: int = EconomyServiceScript.get_ase_banked()
	var ek: int = EconomyServiceScript.get_ekwan_banked()
	var ok := bool(res.get("ok", false)) and ase == 0 and ek == 1 and int(res.get("ekwan_gained", -1)) == 1
	if ok:
		_pass(NAME)
		return true
	_fail(NAME, "expected ok with ase=0, ekwan=1; got ase=%d ek=%d res=%s" % [ase, ek, str(res)])
	return false

func test_insufficient_batch() -> bool:
	var NAME := "TestTrade: insufficient_batch 499"
	_reset_economy()
	EconomyServiceScript.deposit_ase(500)
	var res: Dictionary = _econ.trade_ase_to_ekwan_inst(499)
	var ase: int = EconomyServiceScript.get_ase_banked()
	var ek: int = EconomyServiceScript.get_ekwan_banked()
	var ok := (not bool(res.get("ok", true))) and String(res.get("reason", "")) == "insufficient_batch" and ase == 500 and ek == 0
	if ok:
		_pass(NAME)
		return true
	_fail(NAME, "expected insufficient_batch; balances unchanged; got ase=%d ek=%d res=%s" % [ase, ek, str(res)])
	return false

func test_insufficient_funds() -> bool:
	var NAME := "TestTrade: insufficient_funds"
	_reset_economy()
	EconomyServiceScript.deposit_ase(400)
	var res: Dictionary = _econ.trade_ase_to_ekwan_inst(1000)
	var ase: int = EconomyServiceScript.get_ase_banked()
	var ek: int = EconomyServiceScript.get_ekwan_banked()
	var ok := (not bool(res.get("ok", true))) and String(res.get("reason", "")) == "insufficient_funds" and ase == 400 and ek == 0
	if ok:
		_pass(NAME)
		return true
	_fail(NAME, "expected insufficient_funds; balances unchanged; got ase=%d ek=%d res=%s" % [ase, ek, str(res)])
	return false

func test_inverse_trade() -> bool:
	var NAME := "TestTrade: inverse 2→1000"
	_reset_economy()
	EconomyServiceScript.deposit_ekwan(2)
	var res: Dictionary = _econ.trade_ekwan_to_ase_inst(2)
	var ase: int = EconomyServiceScript.get_ase_banked()
	var ek: int = EconomyServiceScript.get_ekwan_banked()
	var rate: int = int(res.get("rate", EconomyConstants.ASE_PER_EKWAN))
	var ok := bool(res.get("ok", false)) and int(res.get("ase_gained", -1)) == (2 * rate) and ase == (2 * rate) and ek == 0
	if ok:
		_pass(NAME)
		return true
	_fail(NAME, "expected ok; ase=%d ek=%d res=%s" % [ase, ek, str(res)])
	return false

func test_buffer_not_spendable() -> bool:
	var NAME := "TestTrade: buffer_not_spendable"
	_reset_economy()
	# Add fractional Ase that does not reach 1.0 in buffer
	_econ.add_ase_float(0.42)
	_econ.add_ase_float(0.41)
	# Try to trade 500 while banked=0
	var res: Dictionary = _econ.trade_ase_to_ekwan_inst(500)
	var ase_banked: int = EconomyServiceScript.get_ase_banked()
	var eff: float = EconomyServiceScript.get_ase_effective()
	var ok := (not bool(res.get("ok", true))) and String(res.get("reason", "")) == "insufficient_funds" and ase_banked == 0 and eff < 1.0
	if ok:
		_pass(NAME)
		return true
	_fail(NAME, "expected insufficient_funds with banked=0, eff<1.0; got banked=%d eff=%.2f res=%s" % [ase_banked, eff, str(res)])
	return false

func test_leftover_path() -> bool:
	var NAME := "TestTrade: leftover 750→{1 ek, ase 250}"
	_reset_economy()
	EconomyServiceScript.deposit_ase(750)
	var res: Dictionary = _econ.trade_ase_to_ekwan_inst(750)
	var ase: int = EconomyServiceScript.get_ase_banked()
	var ek: int = EconomyServiceScript.get_ekwan_banked()
	var ek_gained: int = int(res.get("ekwan_gained", -1))
	var cost: int = int(res.get("ase_spent", -1))
	var leftover: int = int(res.get("leftover_ase_requested", -1))
	var rate: int = int(res.get("rate", EconomyConstants.ASE_PER_EKWAN))
	var ok := bool(res.get("ok", false)) and ek_gained == 1 and cost == rate and leftover == 250 and ase == 250 and ek == 1
	if ok:
		_pass(NAME)
		return true
	_fail(NAME, "expected ok with ek=1, ase=250; got ase=%d ek=%d res=%s" % [ase, ek, str(res)])
	return false

# Optional: suite listing for TestRunner discovery
func build_suite() -> Array:
	return [
		{"name": "happy_path", "fn": Callable(self, "test_happy_path")},
		{"name": "insufficient_batch", "fn": Callable(self, "test_insufficient_batch")},
		{"name": "insufficient_funds", "fn": Callable(self, "test_insufficient_funds")},
		{"name": "inverse_trade", "fn": Callable(self, "test_inverse_trade")},
		{"name": "buffer_not_spendable", "fn": Callable(self, "test_buffer_not_spendable")},
		{"name": "leftover_path", "fn": Callable(self, "test_leftover_path")},
	]