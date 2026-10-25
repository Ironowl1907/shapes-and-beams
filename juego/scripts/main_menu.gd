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
const MENU_SFX_META_KEY: StringName = &"cached_menu_sfx_stream"
const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard"]
const AUDIO_MIX_RATE: int = 22050

static var _menu_sfx_stream: AudioStreamWAV = null

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
		sfx_player.stream = _get_menu_sfx_stream()

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
	Engine.set_meta(DIFFICULTY_META_KEY, selected_difficulty)
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


func _play_menu_sfx(persist_across_scene: bool = false) -> void:
	if sfx_player == null:
		sfx_player = get_node_or_null("SfxPlayer") as AudioStreamPlayer
	var stream: AudioStreamWAV = _get_menu_sfx_stream()
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


static func _get_menu_sfx_stream() -> AudioStreamWAV:
	if _menu_sfx_stream != null and _menu_sfx_stream.resource_path.is_empty():
		return _menu_sfx_stream
	_menu_sfx_stream = null
	if Engine.has_meta(MENU_SFX_META_KEY):
		var cached: Variant = Engine.get_meta(MENU_SFX_META_KEY)
		if cached is AudioStreamWAV and (cached as AudioStreamWAV).resource_path.is_empty():
			_menu_sfx_stream = cached as AudioStreamWAV
			return _menu_sfx_stream
	var sample_count: int = int(AUDIO_MIX_RATE * 0.07)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = 660.0 if progress < 0.45 else 880.0
		phase += TAU * freq / float(AUDIO_MIX_RATE)
		var wave: float = 0.75 * sin(phase) + 0.25 * signf(sin(phase))
		var env: float = minf(progress * 20.0, 1.0) * pow(1.0 - progress, 1.5)
		var sample: float = clampf(wave * env * 0.45, -1.0, 1.0)
		data.encode_s16(i * 2, clampi(int(round(sample * 32767.0)), -32768, 32767))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = AUDIO_MIX_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = data
	_menu_sfx_stream = wav
	Engine.set_meta(MENU_SFX_META_KEY, wav)
	return _menu_sfx_stream


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
