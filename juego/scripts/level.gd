@tool
extends Node2D
## 45-second survival level controller.
## Spawns telegraphed edge-to-edge rectangular light beams at varied positions
## and angles, manages HUD state, and handles Game Over / Level Complete screens.

signal level_completed
signal game_over

const LEVEL_DURATION: float = 45.0
const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const LIGHT_BEAM_SCENE: PackedScene = preload("res://scenes/light_beam.tscn")
const DEFAULT_BEAM_WIDTH: float = 44.0
const TELEGRAPH_TIME: float = 1.0
const ACTIVE_TIME: float = 0.35

@export var level_duration: float = LEVEL_DURATION

var elapsed_time: float = 0.0
var is_level_running: bool = true
var spawn_timer: float = 0.45
var wave_index: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var background: ColorRect = $Background
@onready var beam_container: Node2D = $BeamContainer
@onready var player: CharacterBody2D = $Player
@onready var progress_bg: ColorRect = $HUD/HUDRoot/ProgressBg
@onready var progress_fill: ColorRect = $HUD/HUDRoot/ProgressFill
@onready var hp_label: Label = $HUD/HUDRoot/HPLabel
@onready var timer_label: Label = $HUD/HUDRoot/TimerLabel
@onready var controls_hint_label: Label = $HUD/HUDRoot/ControlsHintLabel
@onready var game_over_panel: ColorRect = $HUD/HUDRoot/GameOverPanel
@onready var game_over_title: Label = $HUD/HUDRoot/GameOverPanel/VBoxContainer/GameOverTitle
@onready var game_over_subtitle: Label = $HUD/HUDRoot/GameOverPanel/VBoxContainer/GameOverSubtitle
@onready var retry_button: Button = $HUD/HUDRoot/GameOverPanel/VBoxContainer/RetryButton
@onready var game_over_menu_button: Button = $HUD/HUDRoot/GameOverPanel/VBoxContainer/GameOverMainMenuButton
@onready var level_complete_panel: ColorRect = $HUD/HUDRoot/LevelCompletePanel
@onready var level_complete_title: Label = $HUD/HUDRoot/LevelCompletePanel/VBoxContainer/LevelCompleteTitle
@onready var level_complete_subtitle: Label = $HUD/HUDRoot/LevelCompletePanel/VBoxContainer/LevelCompleteSubtitle
@onready var replay_button: Button = $HUD/HUDRoot/LevelCompletePanel/VBoxContainer/ReplayButton
@onready var complete_menu_button: Button = $HUD/HUDRoot/LevelCompletePanel/VBoxContainer/CompleteMainMenuButton


func _ready() -> void:
	_resolve_nodes()
	RenderingServer.set_default_clear_color(Color.BLACK)
	rng.randomize()
	_apply_monochrome_ui_theme()

	if player != null:
		if not player.is_connected("hp_changed", _on_player_hp_changed):
			player.connect("hp_changed", _on_player_hp_changed)
		if not player.is_connected("died", _on_player_died):
			player.connect("died", _on_player_died)

	if retry_button != null and not retry_button.pressed.is_connected(_on_retry_pressed):
		retry_button.pressed.connect(_on_retry_pressed)
	if game_over_menu_button != null and not game_over_menu_button.pressed.is_connected(_on_main_menu_pressed):
		game_over_menu_button.pressed.connect(_on_main_menu_pressed)
	if replay_button != null and not replay_button.pressed.is_connected(_on_replay_pressed):
		replay_button.pressed.connect(_on_replay_pressed)
	if complete_menu_button != null and not complete_menu_button.pressed.is_connected(_on_main_menu_pressed):
		complete_menu_button.pressed.connect(_on_main_menu_pressed)

	if not Engine.is_editor_hint():
		restart_level()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances the level timer, wave spawning, and HUD progress by delta seconds.
func simulate_physics(delta: float) -> void:
	_sync_background_size()
	if not is_level_running:
		return

	elapsed_time += delta
	_update_hud_timer()

	if elapsed_time >= level_duration:
		trigger_level_complete()
		return

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_next_wave()
		var progress_ratio: float = clampf(elapsed_time / maxf(level_duration, 0.001), 0.0, 1.0)
		spawn_timer = lerpf(1.2, 0.82, progress_ratio)


## Starts or restarts the level from the beginning.
func restart_level() -> void:
	_resolve_nodes()
	_clear_beams()
	elapsed_time = 0.0
	wave_index = 0
	spawn_timer = 0.45
	is_level_running = true

	if game_over_panel != null:
		game_over_panel.visible = false
	if level_complete_panel != null:
		level_complete_panel.visible = false

	var viewport_size: Vector2 = _get_arena_size()
	var center_pos: Vector2 = viewport_size * 0.5

	if player != null and player.has_method("reset_player"):
		player.call("reset_player", center_pos)

	_update_hud_timer()
	_on_player_hp_changed(3, 3)


## Spawns a single edge-to-edge light beam obstacle at the given position and angle.
func spawn_beam(
	spawn_pos: Vector2,
	angle_radians: float,
	width: float = DEFAULT_BEAM_WIDTH,
	warning_time: float = TELEGRAPH_TIME,
	active_time: float = ACTIVE_TIME
) -> Area2D:
	if beam_container == null:
		return null
	var beam: Area2D = LIGHT_BEAM_SCENE.instantiate() as Area2D
	beam_container.add_child(beam)
	if beam.has_method("configure"):
		beam.call("configure", spawn_pos, angle_radians, width, warning_time, active_time)
	return beam


## Forwards direct 2D viewport coordinates to the player for hand-tracking integration.
func set_hand_tracking_target(screen_pos: Vector2) -> void:
	if player != null and player.has_method("set_target_position"):
		player.call("set_target_position", screen_pos, true)


## Forwards normalized [0..1, 0..1] coordinates to the player for MediaPipe hand tracking.
func set_normalized_hand_tracking_target(normalized_pos: Vector2) -> void:
	if player != null and player.has_method("set_normalized_target_position"):
		player.call("set_normalized_target_position", normalized_pos)


## Stops the level and displays the Level Complete screen.
func trigger_level_complete() -> void:
	if not is_level_running:
		return
	is_level_running = false
	elapsed_time = level_duration
	_update_hud_timer()
	_clear_beams()

	if player != null:
		player.set("is_active", false)

	if level_complete_panel != null:
		level_complete_panel.visible = true
	if replay_button != null and is_inside_tree() and not Engine.is_editor_hint():
		replay_button.grab_focus()

	level_completed.emit()


func _resolve_nodes() -> void:
	background = get_node_or_null("Background") as ColorRect
	beam_container = get_node_or_null("BeamContainer") as Node2D
	player = get_node_or_null("Player") as CharacterBody2D
	progress_bg = get_node_or_null("HUD/HUDRoot/ProgressBg") as ColorRect
	progress_fill = get_node_or_null("HUD/HUDRoot/ProgressFill") as ColorRect
	hp_label = get_node_or_null("HUD/HUDRoot/HPLabel") as Label
	timer_label = get_node_or_null("HUD/HUDRoot/TimerLabel") as Label
	controls_hint_label = get_node_or_null("HUD/HUDRoot/ControlsHintLabel") as Label
	game_over_panel = get_node_or_null("HUD/HUDRoot/GameOverPanel") as ColorRect
	game_over_title = get_node_or_null("HUD/HUDRoot/GameOverPanel/VBoxContainer/GameOverTitle") as Label
	game_over_subtitle = get_node_or_null("HUD/HUDRoot/GameOverPanel/VBoxContainer/GameOverSubtitle") as Label
	retry_button = get_node_or_null("HUD/HUDRoot/GameOverPanel/VBoxContainer/RetryButton") as Button
	game_over_menu_button = get_node_or_null("HUD/HUDRoot/GameOverPanel/VBoxContainer/GameOverMainMenuButton") as Button
	level_complete_panel = get_node_or_null("HUD/HUDRoot/LevelCompletePanel") as ColorRect
	level_complete_title = get_node_or_null("HUD/HUDRoot/LevelCompletePanel/VBoxContainer/LevelCompleteTitle") as Label
	level_complete_subtitle = get_node_or_null("HUD/HUDRoot/LevelCompletePanel/VBoxContainer/LevelCompleteSubtitle") as Label
	replay_button = get_node_or_null("HUD/HUDRoot/LevelCompletePanel/VBoxContainer/ReplayButton") as Button
	complete_menu_button = get_node_or_null("HUD/HUDRoot/LevelCompletePanel/VBoxContainer/CompleteMainMenuButton") as Button


func _get_arena_size() -> Vector2:
	if is_inside_tree():
		var rect_size: Vector2 = get_viewport_rect().size
		if rect_size.x > 0.0 and rect_size.y > 0.0:
			return rect_size
	return Vector2(1152.0, 648.0)


func _spawn_next_wave() -> void:
	var viewport_size: Vector2 = _get_arena_size()
	var player_pos: Vector2 = player.global_position if player != null else viewport_size * 0.5
	var pattern: int = wave_index % 4
	wave_index += 1

	match pattern:
		0:
			var angle: float = rng.randf_range(-PI, PI)
			var offset: Vector2 = Vector2.from_angle(angle + PI * 0.5) * rng.randf_range(-35.0, 35.0)
			var pos: Vector2 = Vector2(
				clampf(player_pos.x + offset.x, 80.0, viewport_size.x - 80.0),
				clampf(player_pos.y + offset.y, 80.0, viewport_size.y - 80.0)
			)
			spawn_beam(pos, angle)

		1:
			var is_horizontal: bool = (wave_index % 2 == 0)
			if is_horizontal:
				var y1: float = rng.randf_range(110.0, viewport_size.y * 0.42)
				var y2: float = rng.randf_range(viewport_size.y * 0.62, viewport_size.y - 110.0)
				spawn_beam(Vector2(viewport_size.x * 0.5, y1), 0.0)
				spawn_beam(Vector2(viewport_size.x * 0.5, y2), 0.0)
			else:
				var x1: float = rng.randf_range(140.0, viewport_size.x * 0.42)
				var x2: float = rng.randf_range(viewport_size.x * 0.62, viewport_size.x - 140.0)
				spawn_beam(Vector2(x1, viewport_size.y * 0.5), PI * 0.5)
				spawn_beam(Vector2(x2, viewport_size.y * 0.5), PI * 0.5)

		2:
			var pivot: Vector2 = Vector2(
				rng.randf_range(viewport_size.x * 0.28, viewport_size.x * 0.72),
				rng.randf_range(viewport_size.y * 0.28, viewport_size.y * 0.72)
			)
			var base_angle: float = rng.randf_range(0.45, 0.95)
			spawn_beam(pivot, base_angle)
			spawn_beam(pivot, -base_angle)

		3:
			var angle_a: float = rng.randf_range(-PI, PI)
			spawn_beam(player_pos, angle_a)
			var normal_vec: Vector2 = Vector2.from_angle(angle_a + PI * 0.5)
			var second_pos: Vector2 = player_pos + normal_vec * 210.0
			second_pos.x = wrapf(second_pos.x, 100.0, viewport_size.x - 100.0)
			second_pos.y = wrapf(second_pos.y, 100.0, viewport_size.y - 100.0)
			spawn_beam(second_pos, angle_a + rng.randf_range(-0.35, 0.35))


func _on_player_hp_changed(new_hp: int, max_hp: int) -> void:
	if hp_label == null:
		return
	var blocks: String = ""
	for i: int in range(max_hp):
		blocks += "■ " if i < new_hp else "□ "
	hp_label.text = "HP: %s(%d/%d)" % [blocks, new_hp, max_hp]


func _on_player_died() -> void:
	if not is_level_running:
		return
	is_level_running = false
	_clear_beams()

	if game_over_panel != null:
		game_over_panel.visible = true
	if retry_button != null and is_inside_tree() and not Engine.is_editor_hint():
		retry_button.grab_focus()

	game_over.emit()


func _update_hud_timer() -> void:
	var remaining: float = maxf(0.0, level_duration - elapsed_time)
	if timer_label != null:
		timer_label.text = "TIME: %.1fs" % remaining
	if progress_bg != null and progress_fill != null:
		var ratio: float = clampf(elapsed_time / maxf(level_duration, 0.001), 0.0, 1.0)
		progress_fill.size.x = progress_bg.size.x * ratio


func _clear_beams() -> void:
	if beam_container == null:
		return
	for child: Node in beam_container.get_children():
		child.set("is_hazard_active", false)
		if child is CanvasItem:
			(child as CanvasItem).visible = false
		if is_inside_tree() and not Engine.is_editor_hint():
			child.queue_free()
		else:
			beam_container.remove_child(child)
			child.free()


func _sync_background_size() -> void:
	var viewport_size: Vector2 = _get_arena_size()
	if background != null:
		background.size = viewport_size
	if progress_bg != null and viewport_size.x > 48.0:
		progress_bg.size.x = viewport_size.x - 48.0
	if timer_label != null and viewport_size.x > 160.0:
		timer_label.position.x = viewport_size.x - 150.0
	if controls_hint_label != null and viewport_size.y > 40.0:
		controls_hint_label.position.y = viewport_size.y - 34.0


func _on_retry_pressed() -> void:
	restart_level()


func _on_replay_pressed() -> void:
	restart_level()


func _on_main_menu_pressed() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _apply_monochrome_ui_theme() -> void:
	for title: Label in [game_over_title, level_complete_title]:
		if title != null:
			title.add_theme_font_size_override("font_size", 36)
			title.add_theme_color_override("font_color", Color.WHITE)

	for subtitle: Label in [game_over_subtitle, level_complete_subtitle]:
		if subtitle != null:
			subtitle.add_theme_font_size_override("font_size", 16)
			subtitle.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68, 1.0))

	for hud_lbl: Label in [hp_label, timer_label]:
		if hud_lbl != null:
			hud_lbl.add_theme_font_size_override("font_size", 18)
			hud_lbl.add_theme_color_override("font_color", Color.WHITE)

	if controls_hint_label != null:
		controls_hint_label.add_theme_font_size_override("font_size", 14)
		controls_hint_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1.0))

	var buttons: Array[Button] = [
		retry_button,
		game_over_menu_button,
		replay_button,
		complete_menu_button,
	]
	for btn: Button in buttons:
		if btn == null:
			continue
		var normal_style: StyleBoxFlat = StyleBoxFlat.new()
		normal_style.bg_color = Color(0.12, 0.12, 0.12, 1.0)
		normal_style.border_color = Color(0.85, 0.85, 0.85, 1.0)
		normal_style.set_border_width_all(2)
		normal_style.set_content_margin_all(10)

		var hover_style: StyleBoxFlat = StyleBoxFlat.new()
		hover_style.bg_color = Color(0.9, 0.9, 0.9, 1.0)
		hover_style.border_color = Color.WHITE
		hover_style.set_border_width_all(2)
		hover_style.set_content_margin_all(10)

		var pressed_style: StyleBoxFlat = StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.65, 0.65, 0.65, 1.0)
		pressed_style.border_color = Color.WHITE
		pressed_style.set_border_width_all(2)
		pressed_style.set_content_margin_all(10)

		btn.add_theme_stylebox_override("normal", normal_style)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("focus", normal_style)
		btn.add_theme_stylebox_override("pressed", pressed_style)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_focus_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.BLACK)
		btn.add_theme_color_override("font_pressed_color", Color.BLACK)
