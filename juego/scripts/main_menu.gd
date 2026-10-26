@tool
extends Control
## Main Menu controller for the black-and-white dodge game prototype.
## Displays the game title, difficulty mode toggle ("Easy", "Normal", "Hard"),
## "Play" button, and "Quit" button with primitive 2D visuals.

enum Difficulty {
	EASY = 0,
	NORMAL = 1,
	HARD = 2,
}

const LEVEL_SCENE_PATH: String = "res://scenes/level.tscn"
const DIFFICULTY_META_KEY: StringName = &"selected_difficulty"
const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard"]
const AudioLibrary: GDScript = preload("res://scripts/audio_library.gd")
const UiStyle: GDScript = preload("res://scripts/ui_style.gd")
const CREDITS_SCENE_PATH: String = "res://scenes/credits.tscn"

@onready var background: ColorRect = $Background
@onready var decor_beam_a: Polygon2D = $DecorativeShapes/DecorBeamA
@onready var decor_beam_b: Polygon2D = $DecorativeShapes/DecorBeamB
@onready var decor_square: Polygon2D = $DecorativeShapes/DecorSquare
@onready var title_label: Label = $CenterContainer/MenuBox/TitleLabel
@onready var subtitle_label: Label = $CenterContainer/MenuBox/SubtitleLabel
@onready var difficulty_button: Button = $CenterContainer/MenuBox/DifficultyButton
@onready var play_button: Button = $CenterContainer/MenuBox/PlayButton
@onready var quit_button: Button = $CenterContainer/MenuBox/QuitButton
@onready var sfx_player: AudioStreamPlayer = $SfxPlayer

var selected_difficulty: int = Difficulty.NORMAL
var sfx_play_count: int = 0
var last_sfx_played: StringName = &""
var _anim_time: float = 0.0
var name_edit: LineEdit = null
var best_label: Label = null
var credits_button: Button = null
var records_button: Button = null
var records_panel: ColorRect = null
var records_player_label: Label = null
var records_highest_label: Label = null
var records_easy_label: Label = null
var records_normal_label: Label = null
var records_hard_label: Label = null
var records_close_button: Button = null
var _play_pulse_tween: Tween = null


func _ready() -> void:
	background = get_node_or_null("Background") as ColorRect
	decor_beam_a = get_node_or_null("DecorativeShapes/DecorBeamA") as Polygon2D
	decor_beam_b = get_node_or_null("DecorativeShapes/DecorBeamB") as Polygon2D
	decor_square = get_node_or_null("DecorativeShapes/DecorSquare") as Polygon2D
	title_label = get_node_or_null("CenterContainer/MenuBox/TitleLabel") as Label
	subtitle_label = get_node_or_null("CenterContainer/MenuBox/SubtitleLabel") as Label
	difficulty_button = get_node_or_null("CenterContainer/MenuBox/DifficultyButton") as Button
	play_button = get_node_or_null("CenterContainer/MenuBox/PlayButton") as Button
	quit_button = get_node_or_null("CenterContainer/MenuBox/QuitButton") as Button
	sfx_player = get_node_or_null("SfxPlayer") as AudioStreamPlayer
	if sfx_player != null and (not is_inside_tree() or not Engine.is_editor_hint()):
		sfx_player.stream = AudioLibrary.menu()

	RenderingServer.set_default_clear_color(Color.BLACK)
	_apply_monochrome_theme()
	_update_difficulty_button_text()

	if difficulty_button != null:
		if not difficulty_button.pressed.is_connected(_on_difficulty_pressed):
			difficulty_button.pressed.connect(_on_difficulty_pressed)

	if play_button != null:
		if not play_button.pressed.is_connected(_on_play_pressed):
			play_button.pressed.connect(_on_play_pressed)
		if is_inside_tree() and not Engine.is_editor_hint():
			play_button.grab_focus()

	if quit_button != null:
		if not quit_button.pressed.is_connected(_on_quit_pressed):
			quit_button.pressed.connect(_on_quit_pressed)

	_build_extras()

	if is_inside_tree() and not Engine.is_editor_hint():
		call_deferred("_prewarm_audio")


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


## Sets the active difficulty mode (0 = Easy, 1 = Normal, 2 = Hard) and updates the toggle button label.
func set_difficulty(mode: int) -> void:
	selected_difficulty = posmod(mode, DIFFICULTY_NAMES.size())
	if not Engine.is_editor_hint():
		Engine.set_meta(DIFFICULTY_META_KEY, selected_difficulty)
	_update_difficulty_button_text()


## Returns the human-readable name of the currently selected difficulty mode.
func get_difficulty_name() -> String:
	return DIFFICULTY_NAMES[posmod(selected_difficulty, DIFFICULTY_NAMES.size())]


func _on_difficulty_pressed() -> void:
	_play_menu_sfx(false)
	set_difficulty((selected_difficulty + 1) % DIFFICULTY_NAMES.size())


func _on_play_pressed() -> void:
	_play_menu_sfx(true)
	_commit_player_name()
	Engine.set_meta(DIFFICULTY_META_KEY, selected_difficulty)
	var gm: Node = _get_game_manager()
	if gm != null:
		gm.call("set_state", 1)
	if is_inside_tree():
		get_tree().change_scene_to_file(LEVEL_SCENE_PATH)


func _on_quit_pressed() -> void:
	_play_menu_sfx(false)
	if is_inside_tree() and get_tree() != null:
		if get_tree().root != null:
			var tracker: Node = get_tree().root.get_node_or_null("HandTrackingClient")
			if tracker != null and tracker.has_method("stop_tracker_process"):
				tracker.call("stop_tracker_process")
		get_tree().quit()


func _prewarm_audio() -> void:
	# Pay the one-time procedural synthesis cost while the player is still in
	# the menu instead of stalling the first level transition.
	AudioLibrary.prewarm()


func _play_menu_sfx(persist_across_scene: bool = false) -> void:
	if sfx_player == null:
		sfx_player = get_node_or_null("SfxPlayer") as AudioStreamPlayer
	var stream: AudioStreamWAV = AudioLibrary.menu()
	sfx_play_count += 1
	last_sfx_played = &"menu"
	if sfx_player != null:
		sfx_player.stream = stream
	if is_inside_tree() and not Engine.is_editor_hint():
		if persist_across_scene and get_tree() != null and get_tree().root != null:
			var bridge: AudioStreamPlayer = get_tree().root.get_node_or_null("MenuSfxBridge") as AudioStreamPlayer
			if bridge == null:
				bridge = AudioStreamPlayer.new()
				bridge.name = "MenuSfxBridge"
				get_tree().root.add_child(bridge)
			bridge.stream = stream
			bridge.play()
		elif sfx_player != null:
			sfx_player.play()


func _update_difficulty_button_text() -> void:
	if difficulty_button != null:
		difficulty_button.text = "Difficulty: %s" % get_difficulty_name()


func _apply_monochrome_theme() -> void:
	if title_label != null:
		title_label.add_theme_font_size_override("font_size", 42)
		title_label.add_theme_color_override("font_color", Color.WHITE)

	if subtitle_label != null:
		subtitle_label.add_theme_font_size_override("font_size", 16)
		subtitle_label.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68, 1.0))

	var buttons: Array[Button] = [difficulty_button, play_button, quit_button]
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


## Adds the persistent-profile UI (name field + best run), the Credits button,
## the pulsing Play animation, ambient particles and responsive scaling.
## Idempotent: calling _ready() twice (tests) never duplicates nodes.
func _build_extras() -> void:
	var box: VBoxContainer = get_node_or_null("CenterContainer/MenuBox") as VBoxContainer
	if box == null or box.has_node("NameEdit"):
		return

	best_label = Label.new()
	best_label.name = "BestLabel"
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best_label.add_theme_font_size_override("font_size", 15)
	best_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	box.add_child(best_label)
	box.move_child(best_label, subtitle_label.get_index() + 1 if subtitle_label != null else 1)

	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.placeholder_text = "Enter your name"
	name_edit.max_length = 12
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.custom_minimum_size = Vector2(240, 46)
	name_edit.add_theme_font_size_override("font_size", 18)
	var edit_style: StyleBoxFlat = UiStyle._box(Color(0.04, 0.04, 0.04, 1.0), Color(0.6, 0.6, 0.6, 1.0), 8)
	var edit_focus: StyleBoxFlat = UiStyle._box(Color(0.08, 0.08, 0.08, 1.0), Color.WHITE, 8)
	edit_focus.shadow_color = Color(1.0, 1.0, 1.0, 0.25)
	edit_focus.shadow_size = 10
	name_edit.add_theme_stylebox_override("normal", edit_style)
	name_edit.add_theme_stylebox_override("focus", edit_focus)
	name_edit.add_theme_color_override("font_color", Color.WHITE)
	name_edit.add_theme_color_override("caret_color", Color.WHITE)
	name_edit.add_theme_color_override("font_placeholder_color", Color(0.45, 0.45, 0.45, 1.0))
	var gm: Node = _get_game_manager()
	if gm != null:
		name_edit.text = str(gm.call("get_player_name"))
	box.add_child(name_edit)
	box.move_child(name_edit, difficulty_button.get_index() if difficulty_button != null else 3)
	name_edit.text_submitted.connect(_on_name_submitted)
	name_edit.focus_exited.connect(_commit_player_name)

	records_button = Button.new()
	records_button.name = "RecordsButton"
	records_button.text = "Records"
	records_button.custom_minimum_size = Vector2(240, 50)
	box.add_child(records_button)
	box.move_child(records_button, quit_button.get_index() if quit_button != null else -1)
	records_button.pressed.connect(_on_records_pressed)

	credits_button = Button.new()
	credits_button.name = "CreditsButton"
	credits_button.text = "Credits"
	credits_button.custom_minimum_size = Vector2(240, 50)
	box.add_child(credits_button)
	box.move_child(credits_button, quit_button.get_index() if quit_button != null else -1)
	credits_button.pressed.connect(_on_credits_pressed)

	for btn: Button in [difficulty_button, play_button, credits_button, records_button, quit_button]:
		if btn == null:
			continue
		UiStyle.style_button(btn)
		btn.mouse_entered.connect(_play_hover_sfx)
		if btn != play_button:
			UiStyle.add_hover_pop(btn)
	if play_button != null:
		# Keep the pulsing "normal" look while focused so the animation stays visible.
		play_button.add_theme_stylebox_override("focus", play_button.get_theme_stylebox("normal"))
		play_button.add_theme_color_override("font_focus_color", Color.WHITE)

	_refresh_best_label()
	_build_records_panel()
	_build_ambient_particles()
	_start_play_pulse()

	if is_inside_tree():
		var vp: Viewport = get_viewport()
		if vp != null and not vp.size_changed.is_connected(_on_resized):
			vp.size_changed.connect(_on_resized)
		_on_resized()


func _refresh_best_label() -> void:
	if best_label == null:
		return
	var gm: Node = _get_game_manager()
	best_label.text = str(gm.call("get_best_summary")) if gm != null else "No runs yet"


func _get_game_manager() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameManager")


func _play_hover_sfx() -> void:
	if not is_inside_tree() or Engine.is_editor_hint():
		return
	var sm: Node = get_node_or_null("/root/SoundManager")
	if sm != null:
		sm.call("play_ui_hover")


func _on_name_submitted(_text: String) -> void:
	_commit_player_name()
	if name_edit != null:
		name_edit.release_focus()
	if play_button != null and is_inside_tree():
		play_button.grab_focus()


func _commit_player_name() -> void:
	var gm: Node = _get_game_manager()
	if gm == null or name_edit == null:
		return
	gm.call("set_player_name", name_edit.text)
	name_edit.text = str(gm.call("get_player_name"))


func _on_credits_pressed() -> void:
	_play_menu_sfx(true)
	_commit_player_name()
	if is_inside_tree():
		var gm: Node = _get_game_manager()
		if gm != null:
			gm.call("go_to_credits")
		else:
			get_tree().change_scene_to_file(CREDITS_SCENE_PATH)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if records_panel != null and records_panel.visible:
			_on_records_close_pressed()


func _on_records_pressed() -> void:
	_play_menu_sfx(false)
	_commit_player_name()
	_refresh_records_display()
	if records_panel != null:
		records_panel.visible = true
	if records_close_button != null and is_inside_tree() and not Engine.is_editor_hint():
		records_close_button.grab_focus()


func _on_records_close_pressed() -> void:
	_play_menu_sfx(false)
	if records_panel != null:
		records_panel.visible = false
	if records_button != null and is_inside_tree() and not Engine.is_editor_hint():
		records_button.grab_focus()


func _build_records_panel() -> void:
	if has_node("RecordsPanel"):
		return
	records_panel = ColorRect.new()
	records_panel.name = "RecordsPanel"
	records_panel.color = Color(0.0, 0.0, 0.0, 0.92)
	records_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	records_panel.visible = false
	records_panel.z_index = 10
	add_child(records_panel)

	var center: CenterContainer = CenterContainer.new()
	center.name = "RecordsCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	records_panel.add_child(center)

	var panel_box: PanelContainer = PanelContainer.new()
	panel_box.name = "RecordsBox"
	panel_box.custom_minimum_size = Vector2(380, 320)
	var box_style: StyleBoxFlat = UiStyle._box(Color(0.06, 0.06, 0.06, 1.0), Color.WHITE, 20)
	panel_box.add_theme_stylebox_override("panel", box_style)
	center.add_child(panel_box)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel_box.add_child(content)

	var title: Label = Label.new()
	title.text = "RECORD HISTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(title)

	records_player_label = Label.new()
	records_player_label.name = "RecordsPlayerLabel"
	records_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	records_player_label.add_theme_font_size_override("font_size", 16)
	records_player_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82, 1.0))
	content.add_child(records_player_label)

	records_highest_label = Label.new()
	records_highest_label.name = "RecordsHighestLabel"
	records_highest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	records_highest_label.add_theme_font_size_override("font_size", 15)
	records_highest_label.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(records_highest_label)

	var sep: HSeparator = HSeparator.new()
	var sep_style: StyleBoxLine = StyleBoxLine.new()
	sep_style.color = Color(0.35, 0.35, 0.35, 1.0)
	sep_style.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	content.add_child(sep)

	records_easy_label = Label.new()
	records_easy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	records_easy_label.add_theme_font_size_override("font_size", 15)
	records_easy_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	content.add_child(records_easy_label)

	records_normal_label = Label.new()
	records_normal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	records_normal_label.add_theme_font_size_override("font_size", 15)
	records_normal_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	content.add_child(records_normal_label)

	records_hard_label = Label.new()
	records_hard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	records_hard_label.add_theme_font_size_override("font_size", 15)
	records_hard_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	content.add_child(records_hard_label)

	var sep2: HSeparator = HSeparator.new()
	sep2.add_theme_stylebox_override("separator", sep_style)
	content.add_child(sep2)

	records_close_button = Button.new()
	records_close_button.name = "RecordsCloseButton"
	records_close_button.text = "Back to Menu"
	records_close_button.custom_minimum_size = Vector2(200, 44)
	UiStyle.style_button(records_close_button, 18, 10)
	UiStyle.add_hover_pop(records_close_button)
	records_close_button.pressed.connect(_on_records_close_pressed)
	records_close_button.mouse_entered.connect(_play_hover_sfx)
	content.add_child(records_close_button)


func _refresh_records_display() -> void:
	var gm: Node = _get_game_manager()
	var player_name_str: String = str(gm.call("get_player_name")) if gm != null else "PLAYER"
	if records_player_label != null:
		records_player_label.text = "PLAYER: %s" % player_name_str.to_upper()
	if records_highest_label != null:
		records_highest_label.text = str(gm.call("get_best_summary")) if gm != null else "No runs recorded"

	var data: Resource = gm.get("save_data") as Resource if gm != null else null
	var format_diff: Callable = func(diff_idx: int, diff_name: String) -> String:
		if data == null:
			return "%s:  No runs recorded" % diff_name
		var rec: Dictionary = data.call("get_record", diff_idx) as Dictionary
		if rec.is_empty():
			return "%s:  No runs recorded" % diff_name
		var is_comp: bool = bool(rec.get("completed", false))
		var time_val: float = float(rec.get("time", 0.0))
		if is_comp:
			return "%s:  COMPLETED (45.0s) ★" % diff_name
		return "%s:  Survived %.1fs" % [diff_name, time_val]

	if records_easy_label != null:
		records_easy_label.text = format_diff.call(0, "EASY  ")
	if records_normal_label != null:
		records_normal_label.text = format_diff.call(1, "NORMAL")
	if records_hard_label != null:
		records_hard_label.text = format_diff.call(2, "HARD  ")


## Looping pulse on the Play button: scale breathing plus glowing border/shadow.
func _start_play_pulse() -> void:
	if play_button == null or not is_inside_tree() or Engine.is_editor_hint():
		return
	if _play_pulse_tween != null:
		_play_pulse_tween.kill()
	play_button.pivot_offset = play_button.size * 0.5
	if not play_button.resized.is_connected(_center_play_pivot):
		play_button.resized.connect(_center_play_pivot)
	var normal_box: StyleBoxFlat = play_button.get_theme_stylebox("normal") as StyleBoxFlat
	_play_pulse_tween = create_tween().set_loops()
	_play_pulse_tween.set_parallel(true)
	_play_pulse_tween.tween_property(play_button, "scale", Vector2.ONE * 1.06, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if normal_box != null:
		normal_box.shadow_color = Color(1.0, 1.0, 1.0, 0.0)
		_play_pulse_tween.tween_property(normal_box, "shadow_size", 18, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_play_pulse_tween.tween_property(normal_box, "shadow_color:a", 0.5, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_play_pulse_tween.chain().tween_property(play_button, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if normal_box != null:
		_play_pulse_tween.parallel().tween_property(normal_box, "shadow_size", 0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_play_pulse_tween.parallel().tween_property(normal_box, "shadow_color:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _center_play_pivot() -> void:
	if play_button != null:
		play_button.pivot_offset = play_button.size * 0.5


func _build_ambient_particles() -> void:
	if has_node("AmbientParticles"):
		return
	var p: CPUParticles2D = CPUParticles2D.new()
	p.name = "AmbientParticles"
	p.amount = 36
	p.lifetime = 8.0
	p.preprocess = 8.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(576, 4)
	p.direction = Vector2.UP
	p.spread = 15.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 40.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.color = Color(1.0, 1.0, 1.0, 0.3)
	p.position = Vector2(576, 660)
	add_child(p)
	move_child(p, 2)


## Scales fonts, minimum sizes and decor to the current window for a responsive layout.
func _on_resized() -> void:
	if not is_inside_tree():
		return
	var view: Vector2 = get_viewport_rect().size
	var s: float = clampf(minf(view.x / 1152.0, view.y / 648.0), 0.6, 2.0)
	if title_label != null:
		title_label.add_theme_font_size_override("font_size", int(42.0 * s))
	if subtitle_label != null:
		subtitle_label.add_theme_font_size_override("font_size", int(16.0 * s))
	if best_label != null:
		best_label.add_theme_font_size_override("font_size", int(15.0 * s))
	for btn: Button in [difficulty_button, play_button, credits_button, records_button, quit_button]:
		if btn != null:
			btn.custom_minimum_size = Vector2(240.0, 50.0) * s
			btn.add_theme_font_size_override("font_size", int(20.0 * s))
	if name_edit != null:
		name_edit.custom_minimum_size = Vector2(240.0, 46.0) * s
		name_edit.add_theme_font_size_override("font_size", int(18.0 * s))
	if decor_beam_a != null:
		decor_beam_a.position = Vector2(view.x * 0.5, view.y * 0.28)
	if decor_beam_b != null:
		decor_beam_b.position = Vector2(view.x * 0.5, view.y * 0.77)
	if decor_square != null:
		decor_square.position = Vector2(view.x * 0.5, view.y * 0.14)
		decor_square.scale = Vector2.ONE * s
	var particles: Node = get_node_or_null("AmbientParticles")
	if particles is CPUParticles2D:
		(particles as CPUParticles2D).position = Vector2(view.x * 0.5, view.y + 12.0)
		(particles as CPUParticles2D).emission_rect_extents = Vector2(view.x * 0.5, 4.0)
