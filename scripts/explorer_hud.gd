extends CanvasLayer
class_name LeafExplorerHUD

signal quality_changed(index: int)
signal bookmark_selected(index: int)
signal paused_changed(paused: bool)

const BOOKMARKS := ["Main Gate", "Ichiraku", "Hokage residence", "Arena", "Academy", "Overlook"]
const INK := Color(0.91, 0.93, 0.87)
const MUTED := Color(0.65, 0.70, 0.65)
const ACCENT := Color(0.58, 0.73, 0.55)

var player: CharacterBody3D
var paused := true
var quality_index := 0
var _built := false
var _has_started := false
var _overlay: Control
var _reticle: ColorRect
var _location: Label
var _help: Label
var _title: Label
var _resume: Button
var _sensitivity_value: Label
var _help_elapsed := 0.0
var _preferences_path := "user://explorer.cfg"
var _preferences_loaded := false
var _sensitivity_multiplier := 1.0
var _fullscreen_enabled := false
var _sensitivity_slider: HSlider
var _graphics_selector: OptionButton
var _fullscreen_toggle: CheckBox

func _ready() -> void:
	layer = 10
	_build()

func setup(controller: CharacterBody3D) -> void:
	player = controller
	if not _built:
		_build()
	if player.has_signal("pause_requested") and not player.pause_requested.is_connected(_on_focus_pause):
		player.pause_requested.connect(_on_focus_pause)
	_sync_preference_widgets()
	set_paused(true)
	# The root connects quality_changed and applies its default after setup().
	# Apply the saved value after that initialization sequence has completed.
	call_deferred("_apply_startup_preferences")

func _load_preferences() -> void:
	if _preferences_loaded:
		return
	_preferences_loaded = true
	_fullscreen_enabled = DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	var config := ConfigFile.new()
	if config.load(_preferences_path) != OK:
		return
	var saved_quality: Variant = config.get_value("display", "quality", 0)
	if typeof(saved_quality) == TYPE_INT and saved_quality >= 0 and saved_quality <= 2:
		quality_index = int(saved_quality)
	var saved_sensitivity: Variant = config.get_value("controls", "sensitivity", 1.0)
	if typeof(saved_sensitivity) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(saved_sensitivity)):
		_sensitivity_multiplier = snappedf(clampf(float(saved_sensitivity), .4, 2.5), .05)
	var saved_fullscreen: Variant = config.get_value("display", "fullscreen", _fullscreen_enabled)
	if typeof(saved_fullscreen) == TYPE_BOOL:
		_fullscreen_enabled = bool(saved_fullscreen)

func _save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "quality", quality_index)
	config.set_value("display", "fullscreen", _fullscreen_enabled)
	config.set_value("controls", "sensitivity", _sensitivity_multiplier)
	var error := config.save(_preferences_path)
	if error != OK:
		push_warning("Unable to save explorer preferences: " + error_string(error))

func _sync_preference_widgets() -> void:
	_sensitivity_slider.set_value_no_signal(_sensitivity_multiplier)
	_sensitivity_value.text = "%.2f×" % _sensitivity_multiplier
	_graphics_selector.select(quality_index)
	_fullscreen_toggle.set_pressed_no_signal(_fullscreen_enabled)
	if is_instance_valid(player):
		player.sensitivity = .0022 * _sensitivity_multiplier

func _apply_window_preference() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var is_fullscreen := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	if is_fullscreen != _fullscreen_enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen_enabled else DisplayServer.WINDOW_MODE_WINDOWED)

func _apply_startup_preferences() -> void:
	# Automated benchmark presets retain the explicit quality selected by main.
	var arguments := OS.get_cmdline_user_args()
	if "--qa" in arguments and "--benchmark" in arguments:
		return
	_apply_window_preference()
	quality_changed.emit(quality_index)

func _set_quality(index: int) -> void:
	var selected := clampi(index, 0, 2)
	if selected == quality_index:
		return
	quality_index = selected
	_graphics_selector.select(selected)
	quality_changed.emit(selected)
	_save_preferences()

func _set_fullscreen(value: bool) -> void:
	if value == _fullscreen_enabled:
		return
	_fullscreen_enabled = value
	_fullscreen_toggle.set_pressed_no_signal(value)
	_apply_window_preference()
	_save_preferences()

func _style(background: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(5)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style

func _label(body: String, size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = body
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(body: String) -> Button:
	var button := Button.new()
	button.text = body
	button.custom_minimum_size.y = 39
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_stylebox_override("normal", _style(Color(0.115, 0.15, 0.13), Color(0.22, 0.28, 0.24)))
	button.add_theme_stylebox_override("hover", _style(Color(0.19, 0.25, 0.19), ACCENT.darkened(0.25)))
	button.add_theme_stylebox_override("pressed", _style(Color(0.24, 0.31, 0.23), ACCENT))
	button.add_theme_stylebox_override("focus", _style(Color(0,0,0,0), ACCENT))
	return button

func _build() -> void:
	if _built:
		return
	_load_preferences()
	_built = true
	var root := Control.new()
	root.name = "ExplorerInterface"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var location_box := VBoxContainer.new()
	location_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	location_box.name = "LocationSummary"
	location_box.offset_left = 34
	location_box.offset_right = 634
	location_box.offset_top = -97
	location_box.offset_bottom = -31
	location_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	location_box.add_theme_constant_override("separation", 3)
	root.add_child(location_box)
	var brand := _label("K O N O H A", 14, Color(0.83, 0.88, 0.80, 0.9))
	brand.add_theme_color_override("font_shadow_color", Color(0,0,0,.8))
	brand.add_theme_constant_override("shadow_offset_x", 1)
	brand.add_theme_constant_override("shadow_offset_y", 1)
	location_box.add_child(brand)
	_location = _label("Main Gate", 23)
	_location.add_theme_color_override("font_shadow_color", Color(0,0,0,.9))
	_location.add_theme_constant_override("shadow_offset_x", 1)
	_location.add_theme_constant_override("shadow_offset_y", 2)
	location_box.add_child(_location)
	_help = _label("W A S D   Move     Shift   Run     Space   Jump     Esc   Menu", 15, Color(0.89,0.92,0.86,.95))
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.name = "ControlHints"
	_help.offset_left = 34
	_help.offset_right = 934
	_help.offset_top = -36
	_help.offset_bottom = -12
	_help.add_theme_color_override("font_shadow_color", Color(0,0,0,.9))
	_help.add_theme_constant_override("shadow_offset_y", 1)
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_help)
	_reticle = ColorRect.new()
	_reticle.color = Color(0.94,0.96,0.9,.78)
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_reticle.name = "Reticle"
	_reticle.offset_left = -1
	_reticle.offset_top = -1
	_reticle.offset_right = 1
	_reticle.offset_bottom = 1
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_reticle)
	_overlay = Control.new()
	_overlay.name = "PauseMenu"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.026, 0.024, 0.72)
	_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 466
	panel.add_theme_stylebox_override("panel", _style(Color(0.050,0.073,0.061,.98), Color(.22,.28,.23)))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side, 20)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 13)
	margin.add_child(column)
	_title = _label("KONOHA", 31)
	column.add_child(_title)
	column.add_child(_label("Hidden Leaf Village", 16, MUTED))
	_resume = _button("Explore village")
	_resume.custom_minimum_size.y = 47
	_resume.add_theme_font_size_override("font_size", 18)
	_resume.pressed.connect(func(): set_paused(false))
	column.add_child(_resume)
	column.add_child(HSeparator.new())
	column.add_child(_label("LANDMARKS", 13, MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for i in range(BOOKMARKS.size()):
		var button := _button(BOOKMARKS[i])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_visit_bookmark.bind(i))
		grid.add_child(button)
	column.add_child(HSeparator.new())
	var look_row := HBoxContainer.new()
	look_row.add_theme_constant_override("separation", 10)
	column.add_child(look_row)
	var look_label := _label("Look sensitivity", 16)
	look_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	look_row.add_child(look_label)
	_sensitivity_value = _label("1.00×", 14, MUTED)
	look_row.add_child(_sensitivity_value)
	_sensitivity_slider = HSlider.new()
	_sensitivity_slider.name = "LookSensitivity"
	_sensitivity_slider.min_value = .4
	_sensitivity_slider.max_value = 2.5
	_sensitivity_slider.step = .05
	_sensitivity_slider.value = _sensitivity_multiplier
	_sensitivity_slider.custom_minimum_size.y = 20
	_sensitivity_slider.value_changed.connect(_set_sensitivity)
	column.add_child(_sensitivity_slider)
	var graphics_row := HBoxContainer.new()
	graphics_row.add_theme_constant_override("separation", 16)
	column.add_child(graphics_row)
	var graphics_label := _label("Graphics", 16)
	graphics_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graphics_row.add_child(graphics_label)
	_graphics_selector = OptionButton.new()
	_graphics_selector.name = "GraphicsQuality"
	_graphics_selector.custom_minimum_size = Vector2(190,36)
	_graphics_selector.add_theme_font_size_override("font_size",16)
	for item in ["Balanced", "High", "Performance"]:
		_graphics_selector.add_item(item)
	_graphics_selector.select(quality_index)
	_graphics_selector.item_selected.connect(_set_quality)
	graphics_row.add_child(_graphics_selector)
	_fullscreen_toggle = CheckBox.new()
	_fullscreen_toggle.name = "Fullscreen"
	_fullscreen_toggle.text = "Fullscreen"
	_fullscreen_toggle.add_theme_font_size_override("font_size",16)
	_fullscreen_toggle.button_pressed = _fullscreen_enabled
	_fullscreen_toggle.toggled.connect(_set_fullscreen)
	column.add_child(_fullscreen_toggle)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	var hint := _label("Esc to pause or return", 15, MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(hint)
	var quit := _button("Quit")
	quit.custom_minimum_size.x = 90
	quit.pressed.connect(func(): get_tree().quit())
	footer.add_child(quit)
	_reticle.hide()
	_help.hide()

func _set_sensitivity(value: float) -> void:
	var selected := snappedf(clampf(value, .4, 2.5), .05)
	if is_equal_approx(selected, _sensitivity_multiplier):
		return
	_sensitivity_multiplier = selected
	_sensitivity_slider.set_value_no_signal(selected)
	_sensitivity_value.text = "%.2f×" % selected
	if is_instance_valid(player):
		player.sensitivity = .0022 * selected
	_save_preferences()

func _visit_bookmark(index: int) -> void:
	bookmark_selected.emit(index)
	set_paused(false)

func update_location(location_name: String) -> void:
	if is_instance_valid(_location):
		_location.text = location_name

func set_paused(value: bool) -> void:
	paused = value
	if is_instance_valid(player):
		player.set_paused(value)
	_overlay.visible = value
	_reticle.visible = not value
	_help.visible = not value
	if not value:
		_has_started = true
		get_viewport().gui_release_focus()
	else:
		_title.text = "Paused" if _has_started else "KONOHA"
		_resume.text = "Resume" if _has_started else "Explore village"
		_resume.grab_focus()
	paused_changed.emit(value)

func _on_focus_pause() -> void:
	set_paused(true)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		# Before the first deliberate start, Escape simply keeps the entry panel open.
		if _has_started:
			set_paused(not paused)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not paused:
		_help_elapsed += delta
		_help.modulate.a = 1.0 - clampf((_help_elapsed - 9.0) / 2.0, 0.0, 1.0)
