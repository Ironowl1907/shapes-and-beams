@tool
extends Control
## Main Menu controller for the black-and-white dodge game prototype.
## Displays the game title, "Play" button, and "Quit" button with primitive 2D visuals.

const LEVEL_SCENE_PATH: String = "res://scenes/level.tscn"

@onready var background: ColorRect = $Background
@onready var decor_beam_a: Polygon2D = $DecorativeShapes/DecorBeamA
@onready var decor_beam_b: Polygon2D = $DecorativeShapes/DecorBeamB
@onready var decor_square: Polygon2D = $DecorativeShapes/DecorSquare
@onready var title_label: Label = $CenterContainer/MenuBox/TitleLabel
@onready var subtitle_label: Label = $CenterContainer/MenuBox/SubtitleLabel
@onready var play_button: Button = $CenterContainer/MenuBox/PlayButton
@onready var quit_button: Button = $CenterContainer/MenuBox/QuitButton

var _anim_time: float = 0.0


func _ready() -> void:
	background = get_node_or_null("Background") as ColorRect
	decor_beam_a = get_node_or_null("DecorativeShapes/DecorBeamA") as Polygon2D
	decor_beam_b = get_node_or_null("DecorativeShapes/DecorBeamB") as Polygon2D
	decor_square = get_node_or_null("DecorativeShapes/DecorSquare") as Polygon2D
	title_label = get_node_or_null("CenterContainer/MenuBox/TitleLabel") as Label
	subtitle_label = get_node_or_null("CenterContainer/MenuBox/SubtitleLabel") as Label
	play_button = get_node_or_null("CenterContainer/MenuBox/PlayButton") as Button
	quit_button = get_node_or_null("CenterContainer/MenuBox/QuitButton") as Button

	RenderingServer.set_default_clear_color(Color.BLACK)
	_apply_monochrome_theme()

	if play_button != null:
		if not play_button.pressed.is_connected(_on_play_pressed):
			play_button.pressed.connect(_on_play_pressed)
		if is_inside_tree() and not Engine.is_editor_hint():
			play_button.grab_focus()

	if quit_button != null:
		if not quit_button.pressed.is_connected(_on_quit_pressed):
			quit_button.pressed.connect(_on_quit_pressed)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_anim_time += delta
	if decor_square != null:
		decor_square.rotation = _anim_time * 0.45
	if decor_beam_a != null:
		var pulse_a: float = 0.16 + 0.06 * sin(_anim_time * 2.0)
		decor_beam_a.color = Color(pulse_a, pulse_a, pulse_a, 1.0)
	if decor_beam_b != null:
		var pulse_b: float = 0.12 + 0.05 * cos(_anim_time * 1.6)
		decor_beam_b.color = Color(pulse_b, pulse_b, pulse_b, 1.0)


func _on_play_pressed() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file(LEVEL_SCENE_PATH)


func _on_quit_pressed() -> void:
	if is_inside_tree():
		get_tree().quit()


func _apply_monochrome_theme() -> void:
	if title_label != null:
		title_label.add_theme_font_size_override("font_size", 42)
		title_label.add_theme_color_override("font_color", Color.WHITE)

	if subtitle_label != null:
		subtitle_label.add_theme_font_size_override("font_size", 16)
		subtitle_label.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68, 1.0))

	var buttons: Array[Button] = [play_button, quit_button]
	for btn: Button in buttons:
		if btn == null:
			continue
		var normal_style: StyleBoxFlat = StyleBoxFlat.new()
		normal_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
		normal_style.border_color = Color.WHITE
		normal_style.set_border_width_all(2)
		normal_style.set_content_margin_all(12)

		var hover_style: StyleBoxFlat = StyleBoxFlat.new()
		hover_style.bg_color = Color.WHITE
		hover_style.border_color = Color.WHITE
		hover_style.set_border_width_all(2)
		hover_style.set_content_margin_all(12)

		var pressed_style: StyleBoxFlat = StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.7, 0.7, 0.7, 1.0)
		pressed_style.border_color = Color.WHITE
		pressed_style.set_border_width_all(2)
		pressed_style.set_content_margin_all(12)

		btn.add_theme_stylebox_override("normal", normal_style)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("focus", normal_style)
		btn.add_theme_stylebox_override("pressed", pressed_style)
		btn.add_theme_font_size_override("font_size", 20)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_focus_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.BLACK)
		btn.add_theme_color_override("font_pressed_color", Color.BLACK)
