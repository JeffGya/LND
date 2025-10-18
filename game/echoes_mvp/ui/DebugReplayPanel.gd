extends Control
class_name DebugReplayPanel

var harness := DemoSimHarness.new()
var _campaign_label: Label
var _realm_input: LineEdit
var _stage_input: LineEdit
var _encounter_input: LineEdit
var _realm_seed_label: Label
var _stage_seed_label: Label
var _enc_seed_label: Label
var _combat_seed_label: Label
var _loot_seed_label: Label
var _log_output: RichTextLabel
var _last_log: String = ""
var _last_run_index: int = 1

func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    var root := VBoxContainer.new()
    root.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_child(root)

    _campaign_label = Label.new()
    root.add_child(_campaign_label)

    var input_row := HBoxContainer.new()
    root.add_child(input_row)

    input_row.add_child(_make_label("Realm"))
    _realm_input = LineEdit.new()
    _realm_input.text = DemoSimHarness.SCENARIO[0]["realm_id"]
    _realm_input.custom_minimum_size.x = 160
    input_row.add_child(_realm_input)

    input_row.add_child(_make_label("Stage"))
    _stage_input = LineEdit.new()
    _stage_input.text = str(DemoSimHarness.SCENARIO[0]["stage"])
    _stage_input.custom_minimum_size.x = 60
    input_row.add_child(_stage_input)

    input_row.add_child(_make_label("Encounter"))
    _encounter_input = LineEdit.new()
    _encounter_input.text = str(DemoSimHarness.SCENARIO[0]["encounter"])
    _encounter_input.custom_minimum_size.x = 60
    input_row.add_child(_encounter_input)

    var lineage_box := VBoxContainer.new()
    lineage_box.add_theme_constant_override("separation", 4)
    root.add_child(lineage_box)

    _realm_seed_label = _make_lineage_label(lineage_box, "Realm seed:")
    _stage_seed_label = _make_lineage_label(lineage_box, "Stage seed:")
    _enc_seed_label = _make_lineage_label(lineage_box, "Encounter seed:")
    _combat_seed_label = _make_lineage_label(lineage_box, "Combat seed:")
    _loot_seed_label = _make_lineage_label(lineage_box, "Loot seed:")

    var button_row := HBoxContainer.new()
    root.add_child(button_row)

    var run_button := Button.new()
    run_button.text = "Run Harness"
    run_button.pressed.connect(_on_run_pressed)
    button_row.add_child(run_button)

    var refresh_button := Button.new()
    refresh_button.text = "Refresh Lineage"
    refresh_button.pressed.connect(_refresh_lineage)
    button_row.add_child(refresh_button)

    var snapshot_button := Button.new()
    snapshot_button.text = "Snapshot"
    snapshot_button.pressed.connect(_on_snapshot_pressed)
    button_row.add_child(snapshot_button)

    var restore_button := Button.new()
    restore_button.text = "Restore Snapshot"
    restore_button.pressed.connect(_on_restore_pressed)
    button_row.add_child(restore_button)

    _log_output = RichTextLabel.new()
    _log_output.fit_content = true
    _log_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(_log_output)

    _run_and_display()

func _make_label(text: String) -> Label:
    var label := Label.new()
    label.text = text
    return label

func _make_lineage_label(parent: VBoxContainer, title: String) -> Label:
    var container := HBoxContainer.new()
    parent.add_child(container)
    var name_label := Label.new()
    name_label.text = title
    container.add_child(name_label)
    var value_label := Label.new()
    value_label.text = "--"
    container.add_child(value_label)
    return value_label

func _on_run_pressed() -> void:
    _last_run_index += 1
    _run_and_display()

func _refresh_lineage() -> void:
    var realm_id := _realm_input.text.strip_edges()
    var stage_index := _parse_int(_stage_input.text, 0)
    var encounter_index := _parse_int(_encounter_input.text, 0)

    harness.seed_service.prng_for_realm(realm_id)
    harness.seed_service.prng_for_stage(realm_id, stage_index)
    harness.seed_service.prng_for_encounter(realm_id, stage_index, encounter_index)
    harness.seed_service.prng_for_combat(realm_id, stage_index, encounter_index, "initiative")
    harness.seed_service.prng_for_loot(realm_id, stage_index, encounter_index)

    var book := harness.seed_service.get_seed_book()
    _campaign_label.text = "Campaign seed: %s" % book.campaign_seed
    _realm_seed_label.text = _format_seed(_safe_get(book.subseeds["realm"], realm_id))
    _stage_seed_label.text = _format_seed(_safe_get_nested(book.subseeds["stage"], [realm_id, stage_index]))
    _enc_seed_label.text = _format_seed(_safe_get_nested(book.subseeds["encounter"], [realm_id, stage_index, encounter_index]))
    _combat_seed_label.text = _format_seed(_safe_get_nested(book.subseeds["combat"], [realm_id, stage_index, encounter_index, "initiative"]))
    _loot_seed_label.text = _format_seed(_safe_get_nested(book.subseeds["loot"], [realm_id, stage_index, encounter_index]))

func _on_snapshot_pressed() -> void:
    var snapshot := harness.snapshot_and_store()
    print(JSON.stringify(snapshot, "  "))
    _refresh_lineage()

func _on_restore_pressed() -> void:
    if harness._cached_snapshot.is_empty():
        push_warning("No snapshot available to restore.")
        return
    harness.restore_cached_snapshot()
    var replay := harness.run_once(harness.seed_service.get_seed_book().campaign_seed, _last_run_index, false)
    var identical := replay == _last_log
    print("Replay identical: %s" % (identical ? "true" : "false"))
    _log_output.text = replay
    _last_log = replay
    if identical:
        _log_output.append_text("\n[replay matched snapshot]")
    else:
        _log_output.append_text("\n[replay mismatch]")
    _refresh_lineage()

func _run_and_display() -> void:
    var campaign_seed := DemoSimHarness.DEFAULT_CAMPAIGN_SEED
    harness.seed_service.init_campaign(campaign_seed)
    harness.snapshot_and_store()
    _last_log = harness.run_once(campaign_seed, _last_run_index, false)
    _log_output.text = _last_log
    _refresh_lineage()

func _format_seed(value) -> String:
    if value == null:
        return "--"
    if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
        var masked := int(value) & 0xFFFFFFFFFFFFFFFF
        return "0x%016X" % masked
    return "--"

func _safe_get(container: Dictionary, key) -> Variant:
    return container.get(key, null)

func _safe_get_nested(container: Dictionary, keys: Array) -> Variant:
    var current: Variant = container
    for key in keys:
        if typeof(current) != TYPE_DICTIONARY:
            return null
        if !current.has(key):
            return null
        current = current[key]
    return current

func _parse_int(text: String, fallback: int) -> int:
    var trimmed := text.strip_edges()
    if trimmed == "":
        return fallback
    return int(trimmed)
