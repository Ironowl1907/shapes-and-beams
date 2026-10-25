@tool
extends Node2D
## 45-second survival level controller.
## Scales attack spawn frequency by selected difficulty mode (Easy, Normal, Hard)
## while spawning four monochrome primitive 2D hazard types (light beams, filling
## circles, un-telegraphed edge projectiles, and stationary exploding objects)
## into BeamContainer.

signal level_completed
signal game_over

enum Difficulty {
	EASY = 0,
	NORMAL = 1,
	HARD = 2,
}

const LEVEL_DURATION: float = 45.0
const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const LIGHT_BEAM_SCENE: PackedScene = preload("res://scenes/light_beam.tscn")
const DEFAULT_BEAM_WIDTH: float = 44.0
const DEFAULT_CIRCLE_RADIUS: float = 78.0
const DEFAULT_PROJECTILE_SPEED: float = 390.0
const DEFAULT_PROJECTILE_RADIUS: float = 10.0
const DEFAULT_EXPLODER_BURST_COUNT: int = 8
const TELEGRAPH_TIME: float = 1.0
const ACTIVE_TIME: float = 0.35

const DIFFICULTY_META_KEY: StringName = &"selected_difficulty"
const MENU_SFX_META_KEY: StringName = &"cached_menu_sfx_stream"
const AUDIO_MIX_RATE: int = 22050

## Persists difficulty across scene transitions when MainMenu changes scene to Level.
static var selected_difficulty: int = Difficulty.NORMAL
static var _music_stream: AudioStreamWAV = null
static var _menu_sfx_stream: AudioStreamWAV = null

@export var level_duration: float = LEVEL_DURATION

var difficulty_mode: int = Difficulty.NORMAL
var elapsed_time: float = 0.0
var is_level_running: bool = true
var is_music_playing: bool = false
var music_restart_count: int = 0
var sfx_play_count: int = 0
var last_sfx_played: StringName = &""
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
@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var sfx_player: AudioStreamPlayer = $SfxPlayer


func _ready() -> void:
	_resolve_nodes()
	RenderingServer.set_default_clear_color(Color.BLACK)
	rng.randomize()
	_apply_monochrome_ui_theme()

	if Engine.has_meta(DIFFICULTY_META_KEY):
		var meta_diff: int = int(Engine.get_meta(DIFFICULTY_META_KEY))
		Engine.remove_meta(DIFFICULTY_META_KEY)
		difficulty_mode = clampi(meta_diff, Difficulty.EASY, Difficulty.HARD)
		selected_difficulty = difficulty_mode
	else:
		difficulty_mode = Difficulty.NORMAL
		selected_difficulty = Difficulty.NORMAL

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
	else:
		is_music_playing = is_level_running


func _exit_tree() -> void:
	_stop_music()


## Sets the active difficulty mode (Easy = 0, Normal = 1, Hard = 2) and updates spawn timing.
func set_difficulty(mode: int) -> void:
	difficulty_mode = clampi(mode, Difficulty.EASY, Difficulty.HARD)
	selected_difficulty = difficulty_mode
	spawn_timer = get_initial_spawn_delay()


## Returns the human-readable name of the current difficulty mode.
func get_difficulty_name() -> String:
	match difficulty_mode:
		Difficulty.EASY:
			return "Easy"
		Difficulty.HARD:
			return "Hard"
		_:
			return "Normal"


## Returns the initial wave spawn delay for the active difficulty mode.
func get_initial_spawn_delay() -> float:
	match difficulty_mode:
		Difficulty.EASY:
			return 0.65
		Difficulty.HARD:
			return 0.30
		_:
			return 0.45


## Returns the wave spawn interval at the given level progress ratio [0.0..1.0].
func get_spawn_interval_for_progress(progress_ratio: float) -> float:
	var clamped: float = clampf(progress_ratio, 0.0, 1.0)
	match difficulty_mode:
		Difficulty.EASY:
			return lerpf(1.65, 1.20, clamped)
		Difficulty.HARD:
			return lerpf(0.78, 0.50, clamped)
		_:
			return lerpf(1.20, 0.82, clamped)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances the level timer, wave spawning, active hazards, and HUD progress by delta seconds.
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
		spawn_timer = get_spawn_interval_for_progress(progress_ratio)


## Starts or restarts the level from the beginning while preserving the active difficulty mode.
func restart_level() -> void:
	_resolve_nodes()
	_clear_beams()
	elapsed_time = 0.0
	wave_index = 0
	spawn_timer = get_initial_spawn_delay()
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
	_start_music()


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


## Spawns a filling circle obstacle at the given arena position with one of 3 fill modes (0..2).
func spawn_circle(
	spawn_pos: Vector2,
	radius: float = DEFAULT_CIRCLE_RADIUS,
	fill_mode: int = 0,
	warning_time: float = TELEGRAPH_TIME,
	active_time: float = ACTIVE_TIME
) -> Area2D:
	if beam_container == null:
		return null
	var hazard: Area2D = LIGHT_BEAM_SCENE.instantiate() as Area2D
	beam_container.add_child(hazard)
	if hazard.has_method("configure_circle"):
		hazard.call("configure_circle", spawn_pos, radius, fill_mode, warning_time, active_time)
	return hazard


## Spawns an un-telegraphed projectile obstacle moving in a straight line.
func spawn_projectile(
	spawn_pos: Vector2,
	direction: Vector2,
	speed: float = DEFAULT_PROJECTILE_SPEED,
	radius: float = DEFAULT_PROJECTILE_RADIUS
) -> Area2D:
	if beam_container == null:
		return null
	var hazard: Area2D = LIGHT_BEAM_SCENE.instantiate() as Area2D
	beam_container.add_child(hazard)
	if hazard.has_method("configure_projectile"):
		hazard.call("configure_projectile", spawn_pos, direction, speed, radius)
	return hazard


## Spawns an un-telegraphed projectile along one of the four viewport edges (0=Top, 1=Right, 2=Bottom, 3=Left).
func spawn_edge_projectile(
	edge_index: int = -1,
	speed: float = DEFAULT_PROJECTILE_SPEED,
	radius: float = DEFAULT_PROJECTILE_RADIUS
) -> Area2D:
	var viewport_size: Vector2 = _get_arena_size()
	var chosen_edge: int = edge_index if edge_index >= 0 else rng.randi_range(0, 3)
	chosen_edge = posmod(chosen_edge, 4)

	var spawn_pos: Vector2 = Vector2.ZERO
	match chosen_edge:
		0: # Top edge
			spawn_pos = Vector2(rng.randf_range(40.0, viewport_size.x - 40.0), 0.0)
		1: # Right edge
			spawn_pos = Vector2(viewport_size.x, rng.randf_range(40.0, viewport_size.y - 40.0))
		2: # Bottom edge
			spawn_pos = Vector2(rng.randf_range(40.0, viewport_size.x - 40.0), viewport_size.y)
		3: # Left edge
			spawn_pos = Vector2(0.0, rng.randf_range(40.0, viewport_size.y - 40.0))

	var target_point: Vector2 = Vector2(
		rng.randf_range(viewport_size.x * 0.2, viewport_size.x * 0.8),
		rng.randf_range(viewport_size.y * 0.2, viewport_size.y * 0.8)
	)
	if player != null and rng.randf() < 0.55:
		target_point = player.global_position + Vector2(
			rng.randf_range(-90.0, 90.0),
			rng.randf_range(-90.0, 90.0)
		)
	var dir: Vector2 = (target_point - spawn_pos).normalized()
	if dir.length_squared() <= 0.0001:
		dir = Vector2.DOWN
	return spawn_projectile(spawn_pos, dir, speed, radius)


## Spawns a stationary exploding object inside the arena that telegraphs (~1.0s) and bursts into radial projectiles.
func spawn_exploder(
	spawn_pos: Vector2,
	warning_time: float = TELEGRAPH_TIME,
	burst_count: int = DEFAULT_EXPLODER_BURST_COUNT,
	projectile_speed: float = DEFAULT_PROJECTILE_SPEED
) -> Area2D:
	if beam_container == null:
		return null
	var hazard: Area2D = LIGHT_BEAM_SCENE.instantiate() as Area2D
	beam_container.add_child(hazard)
	if hazard.has_method("configure_exploder"):
		hazard.call("configure_exploder", spawn_pos, warning_time, burst_count, projectile_speed)
	return hazard


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
	_stop_music()
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
	music_player = get_node_or_null("MusicPlayer") as AudioStreamPlayer
	sfx_player = get_node_or_null("SfxPlayer") as AudioStreamPlayer
	if music_player != null and music_player.stream == null:
		music_player.stream = _get_music_stream()
	if sfx_player != null and sfx_player.stream == null:
		sfx_player.stream = _get_menu_sfx_stream()


func _get_arena_size() -> Vector2:
	if is_inside_tree():
		var rect_size: Vector2 = get_viewport_rect().size
		if rect_size.x > 0.0 and rect_size.y > 0.0:
			return rect_size
	return Vector2(1152.0, 648.0)


func _spawn_next_wave() -> void:
	var viewport_size: Vector2 = _get_arena_size()
	var player_pos: Vector2 = player.global_position if player != null else viewport_size * 0.5
	var current_wave: int = wave_index
	var pattern: int = current_wave % 4
	wave_index += 1

	match pattern:
		0: # Hazard Type 0: Edge-to-edge Light Beam
			var angle: float = rng.randf_range(-PI, PI)
			var offset: Vector2 = Vector2.from_angle(angle + PI * 0.5) * rng.randf_range(-35.0, 35.0)
			var pos: Vector2 = Vector2(
				clampf(player_pos.x + offset.x, 80.0, viewport_size.x - 80.0),
				clampf(player_pos.y + offset.y, 80.0, viewport_size.y - 80.0)
			)
			spawn_beam(pos, angle)

		1: # Hazard Type 1: Filling Circle (cycles CENTER_OUT, OUTSIDE_IN, ANGULAR_SWEEP)
			var fill_mode: int = int(floor(float(current_wave) / 4.0)) % 3
			var offset_c: Vector2 = Vector2(
				rng.randf_range(-120.0, 120.0),
				rng.randf_range(-100.0, 100.0)
			)
			var circle_pos: Vector2 = Vector2(
				clampf(player_pos.x + offset_c.x, 110.0, viewport_size.x - 110.0),
				clampf(player_pos.y + offset_c.y, 110.0, viewport_size.y - 110.0)
			)
			spawn_circle(circle_pos, DEFAULT_CIRCLE_RADIUS, fill_mode)

		2: # Hazard Type 2: Un-telegraphed Edge Projectiles (spawns along screen edges)
			var edge_a: int = int(floor(float(current_wave) / 4.0)) % 4
			var edge_b: int = (edge_a + 2) % 4
			spawn_edge_projectile(edge_a)
			spawn_edge_projectile(edge_b)

		3: # Hazard Type 3: Stationary Exploding Object inside arena
			var exp_pos: Vector2 = Vector2(
				rng.randf_range(viewport_size.x * 0.22, viewport_size.x * 0.78),
				rng.randf_range(viewport_size.y * 0.22, viewport_size.y * 0.78)
			)
			spawn_exploder(exp_pos)


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
	_stop_music()
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
	_play_menu_sfx(false)
	restart_level()


func _on_replay_pressed() -> void:
	_play_menu_sfx(false)
	restart_level()


func _on_main_menu_pressed() -> void:
	is_level_running = false
	_stop_music()
	_play_menu_sfx(true)
	if is_inside_tree():
		get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


## Plays a hazard sound effect (e.g., exploder detonation) on the Level's persistent SFX player.
func play_hazard_sfx(sfx_name: StringName, stream: AudioStreamWAV) -> void:
	_resolve_nodes()
	sfx_play_count += 1
	last_sfx_played = sfx_name
	if sfx_player != null:
		sfx_player.stream = stream
		if is_inside_tree() and not Engine.is_editor_hint():
			sfx_player.play()


func _start_music() -> void:
	_resolve_nodes()
	var stream: AudioStreamWAV = _get_music_stream()
	if music_player != null:
		music_player.stream = stream
		music_player.stop()
		if is_inside_tree() and not Engine.is_editor_hint():
			music_player.play(0.0)
	is_music_playing = true
	music_restart_count += 1


func _stop_music() -> void:
	is_music_playing = false
	if music_player != null:
		music_player.stop()


func _play_menu_sfx(persist_across_scene: bool = false) -> void:
	_resolve_nodes()
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


static func _get_music_stream() -> AudioStreamWAV:
	if _music_stream != null:
		return _music_stream
	var notes: Array[float] = [220.0, 261.63, 329.63, 392.0, 293.66, 349.23, 329.63, 246.94]
	var step_duration: float = 0.20
	var step_samples: int = int(AUDIO_MIX_RATE * step_duration)
	var total_samples: int = step_samples * notes.size()
	var data: PackedByteArray = PackedByteArray()
	data.resize(total_samples * 2)
	var lead_phase: float = 0.0
	var bass_phase: float = 0.0
	for i: int in range(total_samples):
		var step_idx: int = mini(i / step_samples, notes.size() - 1)
		var step_pos: float = float(i % step_samples) / float(step_samples)
		var lead_freq: float = notes[step_idx]
		var bass_freq: float = lead_freq * 0.5
		lead_phase += TAU * lead_freq / float(AUDIO_MIX_RATE)
		bass_phase += TAU * bass_freq / float(AUDIO_MIX_RATE)
		var env: float = minf(step_pos * 16.0, 1.0) * pow(1.0 - step_pos, 0.75)
		var lead: float = (0.7 * sin(lead_phase) + 0.3 * signf(sin(lead_phase))) * env
		var bass: float = sin(bass_phase) * (1.0 - step_pos * 0.5)
		var sample: float = clampf((lead * 0.55 + bass * 0.45) * 0.30, -1.0, 1.0)
		data.encode_s16(i * 2, clampi(int(round(sample * 32767.0)), -32768, 32767))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = AUDIO_MIX_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = total_samples
	wav.data = data
	_music_stream = wav
	return _music_stream


static func _get_menu_sfx_stream() -> AudioStreamWAV:
	if _menu_sfx_stream != null:
		return _menu_sfx_stream
	if Engine.has_meta(MENU_SFX_META_KEY):
		var cached: Variant = Engine.get_meta(MENU_SFX_META_KEY)
		if cached is AudioStreamWAV:
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
