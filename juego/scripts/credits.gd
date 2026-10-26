extends Control
## Credits screen: animated scrolling credits with ambient particles.

const UiStyle: GDScript = preload("res://scripts/ui_style.gd")
const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const CREDIT_LINES: Array[Array] = [
	["SHAPES & BEAMS", 56, 1.0],
	["Monochrome Dodge Game", 18, 0.6],
	["", 20, 0.0],
	["DEVELOPED BY", 16, 0.5],
	["Facundo Guiñazú", 34, 1.0],
	["Bautista Prieto", 34, 1.0],
	["", 20, 0.0],
	["BUILT WITH", 16, 0.5],
	["Godot Engine 4.7", 26, 0.9],
	["MediaPipe Hand Tracking", 26, 0.9],
	["OpenCV", 26, 0.9],
	["", 20, 0.0],
	["AUDIO", 16, 0.5],
	["Procedurally synthesized in code", 22, 0.85],
	["", 20, 0.0],
	["Thanks for playing!", 30, 1.0],
]

var _scroll_time: float = 0.0
var _scroll_tween: Tween = null
var _decor_square: Polygon2D = null
var _clip: Control = null
var _column: VBoxContainer = null
var _back_button: Button = null


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	_build_ui()
	_build_particles()
	get_viewport().size_changed.connect(_on_resized)
	_on_resized()
	_start_scroll()


func _process(delta: float) -> void:
	_scroll_time += delta
	if _decor_square != null:
		_decor_square.rotation = _scroll_time * 0.4
		var g: float = 0.10 + 0.05 * sin(_scroll_time * 1.4)
		_decor_square.color = Color(g, g, g, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()


func _build_ui() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.name = "Background"
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_decor_square = Polygon2D.new()
	_decor_square.name = "DecorSquare"
	_decor_square.polygon = PackedVector2Array([Vector2(-90, -90), Vector2(90, -90), Vector2(90, 90), Vector2(-90, 90)])
	_decor_square.color = Color(0.1, 0.1, 0.1, 1.0)
	add_child(_decor_square)

	_clip = Control.new()
	_clip.name = "ScrollClip"
	_clip.clip_contents = true
	_clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_clip.offset_bottom = -90.0
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)

	_column = VBoxContainer.new()
	_column.name = "CreditsColumn"
	_column.add_theme_constant_override("separation", 14)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_column)
	for entry: Array in CREDIT_LINES:
		var label: Label = Label.new()
		label.text = str(entry[0])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", int(entry[1]))
		var g: float = float(entry[2])
		label.add_theme_color_override("font_color", Color(g, g, g, 1.0))
		label.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.18 * g))
		label.add_theme_constant_override("shadow_outline_size", 8)
		_column.add_child(label)

	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "Back"
	_back_button.custom_minimum_size = Vector2(200, 48)
	_back_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_back_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_back_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_back_button.offset_top = -66.0
	_back_button.offset_bottom = -18.0
	_back_button.offset_left = -100.0
	_back_button.offset_right = 100.0
	UiStyle.style_button(_back_button)
	UiStyle.add_hover_pop(_back_button)
	_back_button.pressed.connect(_on_back_pressed)
	_back_button.mouse_entered.connect(_play_hover)
	add_child(_back_button)
	_back_button.grab_focus()


func _build_particles() -> void:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.name = "AmbientParticles"
	p.amount = 40
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(700, 4)
	p.direction = Vector2.UP
	p.spread = 12.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 48.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 4.0
	p.color = Color(1.0, 1.0, 1.0, 0.35)
	p.position = Vector2(576, 700)
	p.z_index = -1
	add_child(p)
	move_child(p, 2)


func _on_resized() -> void:
	var view: Vector2 = get_viewport_rect().size
	if _decor_square != null:
		_decor_square.position = view * 0.5
		_decor_square.scale = Vector2.ONE * clampf(view.y / 648.0, 0.6, 2.0)
	var ambient: Node = get_node_or_null("AmbientParticles")
	if ambient is CPUParticles2D:
		(ambient as CPUParticles2D).position = Vector2(view.x * 0.5, view.y + 10.0)
		(ambient as CPUParticles2D).emission_rect_extents = Vector2(view.x * 0.5, 4.0)
	if _column != null and _clip != null:
		_column.size.x = _clip.size.x
		_column.position.x = 0.0


func _start_scroll() -> void:
	await get_tree().process_frame
	if _column == null or _clip == null:
		return
	_column.size.x = _clip.size.x
	var view_h: float = _clip.size.y
	var col_h: float = _column.get_combined_minimum_size().y
	_column.position.y = view_h
	var distance: float = view_h + col_h
	if _scroll_tween != null:
		_scroll_tween.kill()
	_scroll_tween = create_tween().set_loops()
	_scroll_tween.tween_property(_column, "position:y", -col_h, distance / 48.0).from(view_h)


func _play_hover() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	if sm != null:
		sm.call("play_ui_hover")


func _on_back_pressed() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	if sm != null:
		sm.call("play_ui_click")
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.call("go_to_menu")
	elif is_inside_tree():
		get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
