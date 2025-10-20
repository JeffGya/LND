extends Panel

# DebugReplayPanel.gd — UI to initialize seed, snapshot/restore RNG, and run the demo log
# Godot 4.5 — uses Container Sizing (Fill/Expand) in the Inspector for layout.
# NOTE: SeedService is an AutoLoad singleton; call SeedService.* directly (do NOT preload it).

const DemoSimHarness = preload("res://core/sim/demo_sim_harness.gd")

# --- [3] Expose controls (onready references) ---
@onready var seed_input: LineEdit   = $Root/SeedRow/SeedInput
@onready var init_btn: Button       = $Root/SeedRow/InitBtn
@onready var snapshot_btn: Button   = $Root/SnapRow/SnapshotBtn
@onready var restore_btn: Button    = $Root/SnapRow/RestoreBtn
@onready var run_demo_btn: Button   = $Root/SnapRow/RunDemoBtn
@onready var output: RichTextLabel  = $Root/Output

# Keep snapshot in memory for MVP (no file I/O)
var _snapshot: Dictionary = {}

func _ready() -> void:
	# Prefill a known-stable seed so first run is deterministic.
	seed_input.text = "885677476959259660"
	output.text = "[Debug Replay Panel]\nEnter a campaign_seed, click Init, then Run Demo.\n"

	# --- [4] Wire button signals ---
	init_btn.pressed.connect(_on_init_pressed)
	snapshot_btn.pressed.connect(_on_snapshot_pressed)
	restore_btn.pressed.connect(_on_restore_pressed)
	run_demo_btn.pressed.connect(_on_run_demo_pressed)

# --- [5] Button behaviors ---
func _on_init_pressed() -> void:
	var seed_value: int = _parse_seed(seed_input.text)
	SeedService.init_with_campaign(seed_value)
	_append("[Init] campaign_seed set to %d" % seed_value)

func _on_snapshot_pressed() -> void:
	_snapshot = SeedService.snapshot_state()
	var count := int((_snapshot.get("rng_states", {}) as Dictionary).size())
	_append("[Snapshot] captured %d stream(s)" % count)

func _on_restore_pressed() -> void:
	if _snapshot.is_empty():
		_append("[Restore] No snapshot yet. Click Snapshot first.")
		return
	SeedService.restore_state(_snapshot)
	_append("[Restore] state reapplied.")

func _on_run_demo_pressed() -> void:
	var seed_value: int = _parse_seed(seed_input.text)
	# Build (don’t print) the deterministic multiline log, then show it in the panel
	var log_text: String = DemoSimHarness.build_log(seed_value)
	output.text = log_text

# --- Helpers ---
func _append(line: String) -> void:
	output.text += line + "\n"

# Robust parsing: allow decimal or 0x-prefixed hex; trims whitespace.
func _parse_seed(s: String) -> int:
	s = s.strip_edges()
	if s.begins_with("0x") or s.begins_with("0X"):
		var hex_body := s.substr(2)
		return hex_body.hex_to_int()
	return s.to_int() if s.is_valid_int() else 0
