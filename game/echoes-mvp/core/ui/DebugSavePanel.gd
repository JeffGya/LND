extends Control

@onready var seed_edit: LineEdit     = $Frame/VBox/RowA/SeedEdit
@onready var tel_check: CheckBox     = $Frame/VBox/RowB/TelCheck
@onready var out_box: RichTextLabel  = $Frame/VBox/Out
@onready var new_btn: Button         = $Frame/VBox/RowA/NewBtn
@onready var save_btn: Button        = $Frame/VBox/RowA/SaveBtn
@onready var load_btn: Button        = $Frame/VBox/RowA/LoadBtn
@onready var validate_btn: Button    = $Frame/VBox/RowA/ValidateBtn
@onready var snap_btn: Button        = $Frame/VBox/RowB/SnapBtn
const Seedbook = preload("res://core/seed/Seedbook.gd")
@onready var show_seeds_btn: Button = get_node_or_null("Frame/VBox/RowB/ShowSeedsBtn")

const SAVE_PATH := "user://echoes.save"
const STREAM_KEY := "combat/battle/alpha"

func _ready() -> void:
	# Wire buttons
	new_btn.pressed.connect(_on_new_pressed)
	save_btn.pressed.connect(_on_save_pressed)
	load_btn.pressed.connect(_on_load_pressed)
	validate_btn.pressed.connect(_on_validate_pressed)
	snap_btn.pressed.connect(_on_snapshot_pressed)
	tel_check.toggled.connect(_on_tel_toggled)
	if show_seeds_btn:
		show_seeds_btn.pressed.connect(_on_show_seeds_pressed)
	_append("[color=#6cf]Panel ready[/color].")

func _on_tel_toggled(v: bool) -> void:
	if "TelemetryIO" in ProjectSettings.globalize_path("res://"): # not reliable; just call
		# Our TelemetryIO.gd exposes static set_enabled()
		# No-op if someone replaced it with a stub.
		TelemetryIO.set_enabled(v)
	_append("Telemetry: %s" % ("ON" if v else "OFF"))

func _on_new_pressed() -> void:
	var seed_str: String = seed_edit.text.strip_edges()
	var campaign_seed_i: int = int(seed_str)
	SaveService.new_game(campaign_seed_i)
	_append("[b]New game[/b] with seed [code]%d[/code]" % campaign_seed_i)
	# Log a smoke event so you can see the ring move
	TelemetryIO.log_realm_enter("ase-forest", 0)

func _on_save_pressed() -> void:
	var ok := SaveService.save_game()
	_append("[color=green]Save OK[/color]" if ok else "[color=red]Save FAILED[/color]")
	if ok:
		_show_file_info(SAVE_PATH)

func _on_load_pressed() -> void:
	var ok: bool = SaveService.load_game()
	_append("[color=green]Load OK[/color]" if ok else "[color=red]Load FAILED[/color]")
	if ok:
		var rb: Dictionary = RNCatalogIO.pack_current() as Dictionary
		var cur: int = int((rb.get("cursors", {}) as Dictionary).get(STREAM_KEY, -1))
		_append("RNG cursor (%s): %d" % [STREAM_KEY, cur])

func _on_validate_pressed() -> void:
	var snap := SaveService.snapshot()
	var res := SaveService.validate(snap)
	_append("[b]Validate()[/b]: " + JSON.stringify(res))
	if bool(res.get("ok", false)):
		_append("[color=green]OK[/color]")
	else:
		_append("[color=red]INVALID[/color]")

func _on_snapshot_pressed() -> void:
	var snap := SaveService.snapshot()
	var rh: Dictionary = (snap.get("replay_header", {}) as Dictionary)
	var tel: Dictionary = (snap.get("telemetry_log", {}) as Dictionary)
	var tail: Dictionary = {}
	var ring: Array = (tel.get("ring", []) as Array)
	if ring.size() > 0:
		tail = ring[ring.size() - 1]
	_append("[b]Snapshot[/b] keys=" + str(snap.keys()))
	_append("Replay header: " + JSON.stringify(rh))
	_append("Telemetry.cursor=%s tail=%s" % [str(tel.get("cursor", -1)), JSON.stringify(tail)])

func _show_file_info(path: String) -> void:
	var exists := FileAccess.file_exists(path)
	_append("File %s exists=%s" % [path, str(exists)])
	if not exists: return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return
	var txt := f.get_as_text(); f.close()
	_append("bytes=%d" % txt.length())
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		var d: Dictionary = parsed
		var rh: Dictionary = d.get("replay_header", {}) as Dictionary
		var tel: Dictionary = d.get("telemetry_log", {}) as Dictionary
		_append("on-disk replay_header keys=" + str((rh as Dictionary).keys()))
		_append("on-disk telemetry.cursor=" + str((tel as Dictionary).get("cursor", -1)))

func _on_show_seeds_pressed() -> void:
	_render_seed_info()

func _render_seed_info() -> void:
	var info: Dictionary = Seedbook.get_all_seed_info()
	_append("[b]Campaign Seed[/b]: %s" % String(info.get("campaign_seed", "")))
	_append("[b]Realm Seeds[/b]:")
	for r in (info.get("realms", []) as Array):
		var rd := r as Dictionary
		_append(" - %s: %s (stage=%d)" % [String(rd.get("realm_id","?")), String(rd.get("realm_seed","")), int(rd.get("stage_index",0))])
	_append("[b]Stage Seeds[/b]:")
	for s in (info.get("stages", []) as Array):
		var sd := s as Dictionary
		_append(" - %s[%d]: %s" % [String(sd.get("realm_id","?")), int(sd.get("stage_index",0)), String(sd.get("stage_seed",""))])
	_append("[b]Cursors[/b]:")
	for k in (info.get("cursors", {}) as Dictionary).keys():
		_append(" - %s: %d" % [String(k), int((info.get("cursors", {}) as Dictionary)[k])])
	# optional telemetry hook
	if Engine.has_singleton("Telemetry"):
		var t = Engine.get_singleton("Telemetry")
		if t and t.has_method("log"):
			t.log("seed_info", info)

func _append(line: String) -> void:
	out_box.append_text("\n" + line)
