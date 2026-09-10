extends CanvasLayer
class_name ExplorationMenu

signal pause_requested(paused: bool)
signal village_requested(id: String)
signal bookmark_requested(index: int)
signal sensitivity_changed(multiplier: float)
signal fullscreen_changed(enabled: bool)

const VILLAGES := [
	["leaf", "Hidden Leaf"], ["sand", "Hidden Sand"], ["mist", "Hidden Mist"],
	["cloud", "Hidden Cloud"], ["stone", "Hidden Stone"]
]

var _overlay: Control
var _walking_hud: Control
var _status: Label
var _title: Label
var _location: Label
var _landmark_list: VBoxContainer
var _village_buttons: Array[Button] = []
var _hint: Label
var _hint_remaining := 6.0
var _menu_open := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_interface()
	set_process_unhandled_key_input(true)

func _build_interface() -> void:
	var base := Control.new()
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	_walking_hud = Control.new()
	_walking_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_walking_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.add_child(_walking_hud)
	_location = Label.new()
	_location.position = Vector2(18, 16)
	_location.add_theme_font_size_override("font_size", 12)
	_location.modulate = Color(1, 1, 1, 0.42)
	_walking_hud.add_child(_location)
	_hint = Label.new()
	_hint.text = "WASD move   Shift sprint   Space jump   Esc menu"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -240
	_hint.offset_right = 240
	_hint.offset_top = -38
	_hint.offset_bottom = -16
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.modulate = Color(1, 1, 1, 0.45)
	_walking_hud.add_child(_hint)

	_overlay = ColorRect.new()
	_overlay.color = Color(0.018, 0.021, 0.020, 0.84)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	base.add_child(_overlay)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_right = 330
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.047, 0.052, 0.050)
	panel_style.border_width_right = 1
	panel_style.border_color = Color(1, 1, 1, 0.08)
	panel_style.content_margin_left = 28
	panel_style.content_margin_right = 28
	panel_style.content_margin_top = 30
	panel_style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", panel_style)
	_overlay.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	_title = Label.new()
	_title.text = "VILLAGE EXPLORER"
	_title.add_theme_font_size_override("font_size", 17)
	_title.modulate = Color(0.89, 0.91, 0.88)
	column.add_child(_title)
	var rule := HSeparator.new()
	rule.modulate = Color(1, 1, 1, 0.16)
	column.add_child(rule)

	var resume := _button("Resume")
	resume.pressed.connect(func(): pause_requested.emit(false))
	column.add_child(resume)
	column.add_child(_section_label("VILLAGES"))
	for item: Array in VILLAGES:
		var id: String = item[0]
		var button := _button(item[1])
		button.pressed.connect(_emit_village.bind(id))
		_village_buttons.append(button)
		column.add_child(button)

	column.add_child(_section_label("LANDMARKS"))
	var landmark_scroll := ScrollContainer.new()
	landmark_scroll.custom_minimum_size.y = 128
	landmark_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(landmark_scroll)
	_landmark_list = VBoxContainer.new()
	_landmark_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_landmark_list.add_theme_constant_override("separation", 4)
	landmark_scroll.add_child(_landmark_list)

	column.add_child(_section_label("CONTROLS"))
	var sensitivity_row := HBoxContainer.new()
	var sensitivity_name := Label.new()
	sensitivity_name.text = "Look sensitivity"
	sensitivity_name.add_theme_font_size_override("font_size", 12)
	sensitivity_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sensitivity_row.add_child(sensitivity_name)
	var sensitivity := HSlider.new()
	sensitivity.min_value = 0.4
	sensitivity.max_value = 2.0
	sensitivity.step = 0.1
	sensitivity.value = 1.0
	sensitivity.custom_minimum_size.x = 105
	sensitivity.value_changed.connect(func(value: float): sensitivity_changed.emit(value))
	sensitivity_row.add_child(sensitivity)
	column.add_child(sensitivity_row)
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.add_theme_font_size_override("font_size", 12)
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.toggled.connect(func(value: bool): fullscreen_changed.emit(value))
	column.add_child(fullscreen)

	_status = Label.new()
	_status.text = "Preparing exploration…"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 11)
	_status.modulate = Color(0.77, 0.79, 0.75)
	column.add_child(_status)
	set_paused(true)

func _button(text_value: String) -> Button:
	var result := Button.new()
	result.text = text_value
	result.alignment = HORIZONTAL_ALIGNMENT_LEFT
	result.flat = true
	result.add_theme_font_size_override("font_size", 13)
	result.custom_minimum_size.y = 28
	return result

func _section_label(text_value: String) -> Label:
	var result := Label.new()
	result.text = text_value
	result.add_theme_font_size_override("font_size", 10)
	result.modulate = Color(0.67, 0.70, 0.66)
	return result

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		pause_requested.emit(not _menu_open)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _menu_open or _hint_remaining <= 0.0:
		return
	_hint_remaining = maxf(0.0, _hint_remaining - delta)
	_hint.modulate.a = 0.45 * clampf(_hint_remaining / 2.0, 0.0, 1.0)

func set_paused(value: bool) -> void:
	_menu_open = value
	if is_instance_valid(_overlay): _overlay.visible = value
	if is_instance_valid(_walking_hud): _walking_hud.visible = not value

func is_menu_open() -> bool:
	return _menu_open

func set_busy(value: bool) -> void:
	for button: Button in _village_buttons:
		button.disabled = value

func set_loading(id: String, progress: float) -> void:
	set_busy(true)
	_status.text = "Loading %s… %d%%" % [_display_name(id), roundi(progress * 100.0)]

func set_error(message: String) -> void:
	set_busy(false)
	_status.text = message
	_status.modulate = Color(0.91, 0.68, 0.62)

func set_current_village(id: String, display_name: String) -> void:
	set_busy(false)
	_title.text = display_name.to_upper()
	_status.text = "Ready"
	_status.modulate = Color(0.77, 0.79, 0.75)
	_location.text = display_name
	for index in range(VILLAGES.size()):
		_village_buttons[index].disabled = VILLAGES[index][0] == id

func set_bookmarks(items: Array) -> void:
	for child in _landmark_list.get_children():
		child.queue_free()
	for index in range(items.size()):
		var item: Dictionary = items[index]
		var button := _button(str(item.get("name", "Landmark")))
		button.pressed.connect(_emit_bookmark.bind(index))
		_landmark_list.add_child(button)

func _emit_village(id: String) -> void:
	village_requested.emit(id)

func _emit_bookmark(index: int) -> void:
	bookmark_requested.emit(index)

func set_location(name_text: String) -> void:
	_location.text = name_text

func reveal_hint() -> void:
	_hint_remaining = 6.0
	_hint.modulate.a = 0.45

func _display_name(id: String) -> String:
	for item: Array in VILLAGES:
		if item[0] == id: return item[1]
	return id.capitalize()
