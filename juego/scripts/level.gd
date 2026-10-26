@tool
extends Node2D
## 45-second survival level controller.
##
## Spawns the light hazards (beams, filling circles, edge projectiles and
## exploders) plus the newer threats (saws, closing walls and autonomous
## enemies) into BeamContainer. Difficulty scales spawn frequency and threat
## speed while keeping 3 HP and 45 seconds constant. The wave director caps
## simultaneous autonomous threats so the arena always remains dodgeable.

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
const SAW_SCENE: PackedScene = preload("res://scenes/saw.tscn")
const CLOSING_WALL_SCENE: PackedScene = preload("res://scenes/closing_wall.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const HAND_TRACKING_CLIENT_SCRIPT: GDScript = preload("res://scripts/hand_tracking_client.gd")
const AudioLibrary: GDScript = preload("res://scripts/audio_library.gd")
const DEFAULT_BEAM_WIDTH: float = 44.0
const DEFAULT_CIRCLE_RADIUS: float = 78.0
const DEFAULT_PROJECTILE_SPEED: float = 390.0
const DEFAULT_PROJECTILE_RADIUS: float = 10.0
const DEFAULT_EXPLODER_BURST_COUNT: int = 8
const TELEGRAPH_TIME: float = 1.0
const ACTIVE_TIME: float = 0.35

const PALM_POLYGON_INDICES: Array[int] = [0, 1, 5, 9, 13, 17]
const THUMB_BONE_INDICES: Array[int] = [0, 1, 2, 3, 4]
const INDEX_BONE_INDICES: Array[int] = [0, 5, 6, 7, 8]
const MIDDLE_BONE_INDICES: Array[int] = [0, 9, 10, 11, 12]
const RING_BONE_INDICES: Array[int] = [0, 13, 14, 15, 16]
const PINKY_BONE_INDICES: Array[int] = [0, 17, 18, 19, 20]
const PALM_BRIDGE_INDICES: Array[int] = [1, 5, 9, 13, 17, 0]
const FINGERTIP_INDICES: Array[int] = [4, 8, 12, 16, 20]

const DIFFICULTY_META_KEY: StringName = &"selected_difficulty"
const MIN_WALL_GAP: float = 132.0
const SAFE_SPAWN_DISTANCE: float = 250.0
const DEFAULT_ENEMY_WARNING: float = 0.85

## Persists difficulty across scene transitions when MainMenu changes scene to Level.
static var selected_difficulty: int = Difficulty.NORMAL

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

var hand_tracker: Node = null
var hand_shadow_alpha: float = 0.0
var hand_shadow_pulse: float = 0.0
var _last_shadow_landmarks_2d: PackedVector2Array = PackedVector2Array()
var _last_shadow_revision: int = -1
var _last_shadow_fist: bool = false
var _last_shadow_pulse_bucket: int = -1
var _shadow_geometry_dirty: bool = true
var _owns_detached_tracker: bool = false

var _arena_size_cache: Vector2 = Vector2(1152.0, 648.0)
var _nodes_resolved: bool = false
var _hud_timer_bucket: int = -1
var _last_shield_ratio: float = -1.0
var _last_shield_state: String = ""
var _last_hand_state: int = -1
var _last_hand_label: String = ""
var _last_hand_pulse_bucket: int = -1
var _shake_time: float = 0.0
var _shake_duration: float = 0.0
var _shake_strength: float = 0.0
var _shake_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var saws_spawned: int = 0
var walls_spawned: int = 0
var enemies_spawned: int = 0
var autonomous_spawn_cursor: int = 0

@onready var background: ColorRect = $Background
@onready var hand_shadow: Node2D = $HandShadow
@onready var palm_polygon: Polygon2D = $HandShadow/PalmPolygon
@onready var thumb_bone: Line2D = $HandShadow/ThumbBone
@onready var index_bone: Line2D = $HandShadow/IndexBone
@onready var middle_bone: Line2D = $HandShadow/MiddleBone
@onready var ring_bone: Line2D = $HandShadow/RingBone
@onready var pinky_bone: Line2D = $HandShadow/PinkyBone
@onready var palm_bridge_bone: Line2D = $HandShadow/PalmBridgeBone
@onready var fingertip_4: Polygon2D = $HandShadow/Fingertip4
@onready var fingertip_8: Polygon2D = $HandShadow/Fingertip8
@onready var fingertip_12: Polygon2D = $HandShadow/Fingertip12
@onready var fingertip_16: Polygon2D = $HandShadow/Fingertip16
@onready var fingertip_20: Polygon2D = $HandShadow/Fingertip20
@onready var beam_container: Node2D = $BeamContainer
@onready var arena_fx: Node2D = $ArenaFX
@onready var arena_grid: Node2D = $ArenaGrid
@onready var player: CharacterBody2D = $Player
@onready var game_camera: Camera2D = $GameCamera
@onready var progress_bg: ColorRect = $HUD/HUDRoot/ProgressBg
@onready var progress_fill: ColorRect = $HUD/HUDRoot/ProgressFill
@onready var hp_label: Label = $HUD/HUDRoot/HPLabel
@onready var shield_label: Label = $HUD/HUDRoot/ShieldLabel
@onready var shield_bg: ColorRect = $HUD/HUDRoot/ShieldBg
@onready var shield_fill: ColorRect = $HUD/HUDRoot/ShieldFill
@onready var timer_label: Label = $HUD/HUDRoot/TimerLabel
@onready var controls_hint_label: Label = $HUD/HUDRoot/ControlsHintLabel
@onready var hand_status_pill: ColorRect = $HUD/HUDRoot/HandStatusPill
@onready var hand_status_icon: Polygon2D = $HUD/HUDRoot/HandStatusPill/HandStatusIcon
@onready var hand_status_label: Label = $HUD/HUDRoot/HandStatusPill/HandStatusLabel
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
	_refresh_arena_size()
	_shake_rng.randomize()
	_configure_hand_shadow_primitives()
	RenderingServer.set_default_clear_color(Color.BLACK)
	rng.randomize()
	_apply_monochrome_ui_theme()
	if is_inside_tree():
		var viewport: Viewport = get_viewport()
		if viewport != null and not viewport.size_changed.is_connected(_on_viewport_resized):
			viewport.size_changed.connect(_on_viewport_resized)

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
		if player.has_signal("shield_changed") and not player.is_connected("shield_changed", _on_player_shield_changed):
			player.connect("shield_changed", _on_player_shield_changed)
		if player.has_signal("shield_blocked") and not player.is_connected("shield_blocked", _on_player_shield_blocked):
			player.connect("shield_blocked", _on_player_shield_blocked)
		if player.has_signal("shield_broken") and not player.is_connected("shield_broken", _on_player_shield_broken):
			player.connect("shield_broken", _on_player_shield_broken)
		if player.has_signal("damaged") and not player.is_connected("damaged", _on_player_damaged):
			player.connect("damaged", _on_player_damaged)

	if retry_button != null and not retry_button.pressed.is_connected(_on_retry_pressed):
		retry_button.pressed.connect(_on_retry_pressed)
	if game_over_menu_button != null and not game_over_menu_button.pressed.is_connected(_on_main_menu_pressed):
		game_over_menu_button.pressed.connect(_on_main_menu_pressed)
	if replay_button != null and not replay_button.pressed.is_connected(_on_replay_pressed):
		replay_button.pressed.connect(_on_replay_pressed)
	if complete_menu_button != null and not complete_menu_button.pressed.is_connected(_on_main_menu_pressed):
		complete_menu_button.pressed.connect(_on_main_menu_pressed)

	_update_hand_status_hud()
	_update_hand_shadow(0.0)
	_update_shield_hud()
	_sync_background_size()

	if not Engine.is_editor_hint():
		restart_level()
	else:
		is_music_playing = is_level_running


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_screen_shake(delta)


func _exit_tree() -> void:
	if is_inside_tree():
		var viewport: Viewport = get_viewport()
		if viewport != null and viewport.size_changed.is_connected(_on_viewport_resized):
			viewport.size_changed.disconnect(_on_viewport_resized)
	_stop_music()
	if _owns_detached_tracker and hand_tracker != null and is_instance_valid(hand_tracker):
		hand_tracker.free()
		hand_tracker = null
		_owns_detached_tracker = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _owns_detached_tracker and hand_tracker != null and is_instance_valid(hand_tracker):
			hand_tracker.free()
			hand_tracker = null
			_owns_detached_tracker = false


## Injects a custom or mock HandTrackingClient instance for deterministic testing.
func set_hand_tracker(tracker: Node) -> void:
	if _owns_detached_tracker and hand_tracker != null and hand_tracker != tracker and is_instance_valid(hand_tracker):
		hand_tracker.free()
	hand_tracker = tracker
	_owns_detached_tracker = false
	_update_hand_status_hud()


## Decodes and applies a binary UDP hand-tracking packet (<i63f or <i) and syncs player/HUD/shadow.
func ingest_hand_packet(packet: PackedByteArray) -> bool:
	_resolve_nodes()
	if hand_tracker == null or not hand_tracker.has_method("ingest_packet"):
		return false
	var ok: bool = bool(hand_tracker.call("ingest_packet", packet))
	_sync_hand_tracking_to_gameplay(0.016)
	return ok


## Drains a batch of binary UDP packets, applies only the freshest valid packet, and syncs state.
func ingest_hand_packet_batch(packets: Array[PackedByteArray]) -> bool:
	_resolve_nodes()
	if hand_tracker == null or not hand_tracker.has_method("ingest_packet_batch"):
		return false
	var ok: bool = bool(hand_tracker.call("ingest_packet_batch", packets))
	_sync_hand_tracking_to_gameplay(0.016)
	return ok


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
			return 0.55
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


## Speed multiplier applied to autonomous threats (never to the player).
func get_threat_speed_scale() -> float:
	match difficulty_mode:
		Difficulty.EASY:
			return 0.88
		Difficulty.HARD:
			return 1.14
		_:
			return 1.0


## Maximum simultaneous autonomous threats (enemies + saws + closing walls).
func get_max_autonomous_threats() -> int:
	match difficulty_mode:
		Difficulty.EASY:
			return 1
		Difficulty.HARD:
			return 3
		_:
			return 2


func get_max_saws() -> int:
	return 1 if difficulty_mode == Difficulty.EASY else 2


func get_max_enemies() -> int:
	return 1 if difficulty_mode == Difficulty.EASY else 2


func _count_active_threats(group_name: StringName) -> int:
	if beam_container == null:
		return 0
	var count: int = 0
	for child: Node in beam_container.get_children():
		if child.is_queued_for_deletion():
			continue
		if child.is_in_group(group_name):
			count += 1
	return count


func _active_autonomous_threat_count() -> int:
	return (
		_count_active_threats(&"enemies")
		+ _count_active_threats(&"saws")
		+ _count_active_threats(&"closing_walls")
	)


func _can_spawn_autonomous_threat() -> bool:
	return _active_autonomous_threat_count() < get_max_autonomous_threats()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances the level timer, wave spawning, active hazards, hand tracking, and HUD by delta seconds.
func simulate_physics(delta: float) -> void:
	_update_hand_tracking(delta)
	_update_shield_hud()
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
	if arena_fx != null and arena_fx.has_method("clear"):
		arena_fx.call("clear")
	_shake_time = 0.0
	_shake_strength = 0.0
	if game_camera != null:
		game_camera.offset = Vector2.ZERO
	elapsed_time = 0.0
	wave_index = 0
	saws_spawned = 0
	walls_spawned = 0
	enemies_spawned = 0
	autonomous_spawn_cursor = 0
	_hud_timer_bucket = -1
	_last_shield_ratio = -1.0
	_last_shield_state = ""
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
	_update_hand_status_hud()
	_update_hand_shadow(0.0)
	_update_shield_hud()
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


## Spawns a telegraphed pair of walls that closes in from opposite edges,
## leaving a gap large enough to run through.
func spawn_closing_wall(
	axis: int = -1,
	gap_center: float = -1.0,
	gap_size: float = MIN_WALL_GAP,
	warning: float = 1.25
) -> Node2D:
	if beam_container == null:
		return null
	var wall: Node2D = CLOSING_WALL_SCENE.instantiate() as Node2D
	beam_container.add_child(wall)
	var arena: Vector2 = _get_arena_size()
	var chosen_axis: int = axis if axis >= 0 else rng.randi_range(0, 1)
	var axis_span: float = arena.x if chosen_axis == 0 else arena.y
	var player_axis_pos: float = player.global_position.x if chosen_axis == 0 and player != null else (player.global_position.y if player != null else axis_span * 0.5)
	var chosen_center: float = gap_center
	if chosen_center < 0.0:
		chosen_center = player_axis_pos + rng.randf_range(-92.0, 92.0)
	chosen_center = clampf(chosen_center, gap_size * 0.5 + 40.0, axis_span - gap_size * 0.5 - 40.0)
	var close_time: float = 0.76 - 0.06 * float(difficulty_mode)
	var hold_time: float = 1.25 - 0.05 * float(difficulty_mode)
	if wall.has_method("configure"):
		wall.call("configure", chosen_axis, chosen_center, gap_size, 46.0, warning, close_time, hold_time, 0.55)
	walls_spawned += 1
	_spawn_threat_arrival_fx(_get_gap_center_for_axis(chosen_axis, chosen_center, arena))
	return wall


## Spawns a spinning saw. Axis-aligned bounce and sweeping patrol modes are
## supported; the saw telegraphs before its collision turns on.
func spawn_saw(
	mode: int = -1,
	spawn_position: Vector2 = Vector2(-9999.0, -9999.0),
	direction: Vector2 = Vector2.ZERO,
	speed: float = -1.0,
	radius: float = 30.0,
	warning: float = -1.0,
	max_lifetime: float = -1.0
) -> Area2D:
	if beam_container == null:
		return null
	var arena: Vector2 = _get_arena_size()
	var chosen_mode: int = mode if mode >= 0 else rng.randi_range(0, 1)
	var pos: Vector2 = spawn_position
	var dir: Vector2 = direction
	var chosen_speed: float = speed
	if pos.x < -9000.0:
		if chosen_mode == 0:
			var edge: int = rng.randi_range(0, 3)
			match edge:
				0:
					pos = Vector2(rng.randf_range(120.0, arena.x - 120.0), 74.0)
				1:
					pos = Vector2(arena.x - 74.0, rng.randf_range(120.0, arena.y - 120.0))
				2:
					pos = Vector2(rng.randf_range(120.0, arena.x - 120.0), arena.y - 74.0)
				_:
					pos = Vector2(74.0, rng.randf_range(120.0, arena.y - 120.0))
			var target: Vector2 = Vector2(rng.randf_range(arena.x * 0.25, arena.x * 0.75), rng.randf_range(arena.y * 0.25, arena.y * 0.75))
			dir = (target - pos).normalized()
		else:
			var from_left: bool = rng.randf() < 0.5
			pos = Vector2(74.0 if from_left else arena.x - 74.0, rng.randf_range(110.0, arena.y - 110.0))
			dir = Vector2.RIGHT if from_left else Vector2.LEFT
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	if chosen_speed < 0.0:
		chosen_speed = (195.0 + 26.0 * float(difficulty_mode)) * get_threat_speed_scale()
	var chosen_warning: float = warning if warning >= 0.0 else 0.68 - 0.05 * float(difficulty_mode)
	var chosen_lifetime: float = max_lifetime if max_lifetime > 0.0 else rng.randf_range(5.4, 6.4)
	var saw: Area2D = SAW_SCENE.instantiate() as Area2D
	beam_container.add_child(saw)
	if saw.has_method("configure"):
		saw.call("configure", chosen_mode, pos, dir, chosen_speed, radius, chosen_warning, chosen_lifetime)
	saws_spawned += 1
	_spawn_threat_arrival_fx(pos)
	return saw


## Spawns an autonomous enemy at a safe distance from the player.
func spawn_enemy(
	type: int = -1,
	spawn_position: Vector2 = Vector2(-9999.0, -9999.0),
	speed_scale: float = -1.0,
	warning: float = DEFAULT_ENEMY_WARNING,
	max_lifetime: float = 7.0
) -> Area2D:
	if beam_container == null:
		return null
	var chosen_type: int = type if type >= 0 else enemies_spawned % 3
	var pos: Vector2 = spawn_position
	if pos.x < -9000.0:
		pos = _find_safe_spawn_position()
	var chosen_scale: float = speed_scale if speed_scale > 0.0 else get_threat_speed_scale()
	var enemy: Area2D = ENEMY_SCENE.instantiate() as Area2D
	beam_container.add_child(enemy)
	if enemy.has_method("configure_enemy"):
		enemy.call("configure_enemy", chosen_type, pos, player, chosen_scale, warning, max_lifetime)
	if enemy.has_signal("fire_projectile") and not enemy.is_connected("fire_projectile", _on_enemy_fire_projectile):
		enemy.connect("fire_projectile", _on_enemy_fire_projectile)
	enemies_spawned += 1
	_spawn_threat_arrival_fx(pos)
	return enemy


func _find_safe_spawn_position() -> Vector2:
	var arena: Vector2 = _get_arena_size()
	var player_pos: Vector2 = player.global_position if player != null else arena * 0.5
	var best: Vector2 = Vector2(arena.x - 80.0, arena.y - 80.0)
	var best_distance: float = -1.0
	for _attempt: int in range(10):
		var candidate: Vector2 = Vector2(
			rng.randf_range(80.0, arena.x - 80.0),
			rng.randf_range(90.0, arena.y - 90.0)
		)
		var distance: float = candidate.distance_to(player_pos)
		if distance >= SAFE_SPAWN_DISTANCE:
			return candidate
		if distance > best_distance:
			best_distance = distance
			best = candidate
	return best


func _get_gap_center_for_axis(axis: int, center: float, arena: Vector2) -> Vector2:
	return Vector2(center, arena.y * 0.5) if axis == 0 else Vector2(arena.x * 0.5, center)


func _spawn_threat_arrival_fx(at_position: Vector2) -> void:
	if arena_fx == null or not arena_fx.has_method("spawn_ring"):
		return
	arena_fx.call("spawn_ring", at_position, 10.0, 46.0, 0.34, Color(0.72, 0.72, 0.72, 0.7), 2.0)


func _on_enemy_fire_projectile(origin: Vector2, direction: Vector2, speed: float, radius: float) -> void:
	spawn_projectile(origin, direction, speed, radius)
	if arena_fx != null:
		arena_fx.call("spawn_burst", origin, 4, 110.0, Color(0.85, 0.85, 0.85, 1.0), 0.22, 6.0, 1.5)


## Forwards direct 2D viewport coordinates to the player for hand-tracking integration.
func set_hand_tracking_target(screen_pos: Vector2) -> void:
	if player != null and player.has_method("set_target_position"):
		player.call("set_target_position", screen_pos, true)


## Forwards normalized [0..1, 0..1] coordinates to the player for MediaPipe hand tracking.
func set_normalized_hand_tracking_target(normalized_pos: Vector2) -> void:
	if player != null and player.has_method("set_normalized_target_position"):
		player.call("set_normalized_target_position", normalized_pos)


## Releases hand-tracking control on the player so mouse/keyboard fallback resumes immediately.
func release_hand_tracking_target() -> void:
	if player != null and player.has_method("release_external_tracking"):
		player.call("release_external_tracking")


## Stops the level and displays the Level Complete screen.
func trigger_level_complete() -> void:
	if not is_level_running:
		return
	is_level_running = false
	_stop_music()
	elapsed_time = level_duration
	_update_hud_timer()
	_clear_beams()
	_shake_time = 0.0
	_shake_strength = 0.0
	if game_camera != null:
		game_camera.offset = Vector2.ZERO

	if player != null:
		player.set("is_active", false)

	if level_complete_panel != null:
		level_complete_panel.visible = true
	if level_complete_subtitle != null:
		level_complete_subtitle.text = "Survived 45.0s on %s" % get_difficulty_name()
	if replay_button != null and is_inside_tree() and not Engine.is_editor_hint():
		replay_button.grab_focus()

	level_completed.emit()


func _resolve_nodes() -> void:
	if _nodes_resolved:
		return
	if not InputMap.has_action("move_left"):
		InputMap.load_from_project_settings()
	background = get_node_or_null("Background") as ColorRect
	hand_shadow = get_node_or_null("HandShadow") as Node2D
	palm_polygon = get_node_or_null("HandShadow/PalmPolygon") as Polygon2D
	thumb_bone = get_node_or_null("HandShadow/ThumbBone") as Line2D
	index_bone = get_node_or_null("HandShadow/IndexBone") as Line2D
	middle_bone = get_node_or_null("HandShadow/MiddleBone") as Line2D
	ring_bone = get_node_or_null("HandShadow/RingBone") as Line2D
	pinky_bone = get_node_or_null("HandShadow/PinkyBone") as Line2D
	palm_bridge_bone = get_node_or_null("HandShadow/PalmBridgeBone") as Line2D
	fingertip_4 = get_node_or_null("HandShadow/Fingertip4") as Polygon2D
	fingertip_8 = get_node_or_null("HandShadow/Fingertip8") as Polygon2D
	fingertip_12 = get_node_or_null("HandShadow/Fingertip12") as Polygon2D
	fingertip_16 = get_node_or_null("HandShadow/Fingertip16") as Polygon2D
	fingertip_20 = get_node_or_null("HandShadow/Fingertip20") as Polygon2D
	beam_container = get_node_or_null("BeamContainer") as Node2D
	arena_fx = get_node_or_null("ArenaFX") as Node2D
	arena_grid = get_node_or_null("ArenaGrid") as Node2D
	player = get_node_or_null("Player") as CharacterBody2D
	game_camera = get_node_or_null("GameCamera") as Camera2D
	progress_bg = get_node_or_null("HUD/HUDRoot/ProgressBg") as ColorRect
	progress_fill = get_node_or_null("HUD/HUDRoot/ProgressFill") as ColorRect
	hp_label = get_node_or_null("HUD/HUDRoot/HPLabel") as Label
	shield_label = get_node_or_null("HUD/HUDRoot/ShieldLabel") as Label
	shield_bg = get_node_or_null("HUD/HUDRoot/ShieldBg") as ColorRect
	shield_fill = get_node_or_null("HUD/HUDRoot/ShieldFill") as ColorRect
	timer_label = get_node_or_null("HUD/HUDRoot/TimerLabel") as Label
	controls_hint_label = get_node_or_null("HUD/HUDRoot/ControlsHintLabel") as Label
	hand_status_pill = get_node_or_null("HUD/HUDRoot/HandStatusPill") as ColorRect
	hand_status_icon = get_node_or_null("HUD/HUDRoot/HandStatusPill/HandStatusIcon") as Polygon2D
	hand_status_label = get_node_or_null("HUD/HUDRoot/HandStatusPill/HandStatusLabel") as Label
	game_over_panel = get_node_or_null("HUD/HUDRoot/GameOverPanel") as ColorRect
	game_over_title = get_node_or_null("HUD/HUDRoot/GameOverPanel/VBoxContainer/GameOverTitle") as Label
	game_over_subtitle = get_node_or_null("HUD/HUDRoot/GameOverPanel/VBoxContainer/GameOverSubtitle") as Label
	retry_button = get_node_or_null("HUD/HUDRoot/GameOverPanel/VBoxContainer/RetryButton") as Button
	game_over_menu_button = get_node_or_null("HUD/HUDRoot/GameOverPanel/VBoxContainer/GameOverMainMenuButton") as Button
	level_complete_panel = get_node_or_null("HUD/HUDRoot/LevelCompletePanel") as ColorRect
	level_complete_title = get_node_or_null("HUD/HUDRoot/LevelCompletePanel/VBoxContainer/LevelCompleteTitle") as Label
	level_complete_subtitle = get_node_or_null("HUD/HUDRoot/LevelCompletePanel/VBoxContainer/LevelCompleteSubtitle") as Label
	replay_button = get_node_or_null("HUD/HUDRoot/LevelCompletePanel/VBoxContainer/ReplayButton") as Button
	complete_menu_button = get_node_or_null("HUD/HUDRoot/LevelCompletePanel/VBoxContainer/CompleteMenuButton") as Button
	if complete_menu_button == null:
		complete_menu_button = get_node_or_null("HUD/HUDRoot/LevelCompletePanel/VBoxContainer/CompleteMainMenuButton") as Button
	music_player = get_node_or_null("MusicPlayer") as AudioStreamPlayer
	sfx_player = get_node_or_null("SfxPlayer") as AudioStreamPlayer

	if not is_inside_tree() or not Engine.is_editor_hint():
		if music_player != null and music_player.stream == null:
			music_player.stream = AudioLibrary.music()
		if sfx_player != null and sfx_player.stream == null:
			sfx_player.stream = AudioLibrary.menu()

	if hand_tracker == null or not is_instance_valid(hand_tracker):
		if is_inside_tree() and get_tree() != null and get_tree().root != null:
			hand_tracker = get_tree().root.get_node_or_null("HandTrackingClient")
			_owns_detached_tracker = false
		if hand_tracker == null:
			var local_tracker: Node = HAND_TRACKING_CLIENT_SCRIPT.new()
			local_tracker.set("auto_manage_process", false)
			hand_tracker = local_tracker
			_owns_detached_tracker = true
	_nodes_resolved = true
func _configure_hand_shadow_primitives() -> void:
	var tip_poly: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -7.0),
		Vector2(5.0, -5.0),
		Vector2(7.0, 0.0),
		Vector2(5.0, 5.0),
		Vector2(0.0, 7.0),
		Vector2(-5.0, 5.0),
		Vector2(-7.0, 0.0),
		Vector2(-5.0, -5.0),
	])
	for tip_node: Polygon2D in _get_fingertip_nodes():
		if tip_node != null:
			tip_node.polygon = tip_poly
			tip_node.color = Color(0.76, 0.76, 0.76, 0.85)

	for bone_line: Line2D in [thumb_bone, index_bone, middle_bone, ring_bone, pinky_bone]:
		if bone_line != null:
			bone_line.width = 3.0
			bone_line.default_color = Color(0.38, 0.38, 0.38, 0.68)

	if palm_bridge_bone != null:
		palm_bridge_bone.width = 2.0
		palm_bridge_bone.default_color = Color(0.28, 0.28, 0.28, 0.55)

	if palm_polygon != null:
		palm_polygon.color = Color(0.18, 0.18, 0.18, 0.42)

	if hand_status_icon != null:
		hand_status_icon.polygon = PackedVector2Array([
			Vector2(0.0, -6.0),
			Vector2(6.0, 0.0),
			Vector2(0.0, 6.0),
			Vector2(-6.0, 0.0),
		])


func _get_fingertip_nodes() -> Array[Polygon2D]:
	return [fingertip_4, fingertip_8, fingertip_12, fingertip_16, fingertip_20]


func _update_hand_tracking(delta: float) -> void:
	if hand_tracker != null and not is_instance_valid(hand_tracker):
		hand_tracker = null
		_nodes_resolved = false
		_resolve_nodes()
	if hand_tracker != null:
		var tracker_in_tree: bool = hand_tracker.is_inside_tree()
		if not tracker_in_tree or Engine.is_editor_hint():
			if hand_tracker.has_method("poll_and_update"):
				hand_tracker.call("poll_and_update", delta)

	_sync_hand_tracking_to_gameplay(delta)


func _sync_hand_tracking_to_gameplay(delta: float) -> void:
	var has_tracked_hand: bool = hand_tracker != null and bool(hand_tracker.get("has_hand"))

	if is_level_running and player != null:
		if has_tracked_hand:
			var palm_norm: Vector2 = hand_tracker.call("get_mirrored_palm_center") as Vector2
			set_normalized_hand_tracking_target(palm_norm)

			var is_fist_held: bool = bool(hand_tracker.get("is_fist"))
			if player.has_method("set_shield_held"):
				player.call("set_shield_held", is_fist_held)
			var revision: int = int(hand_tracker.get("landmark_revision"))
			if revision != _last_shadow_revision:
				_shadow_geometry_dirty = true
				_last_shadow_revision = revision
				if hand_tracker.has_method("get_mirrored_landmarks_2d"):
					var mirrored: PackedVector2Array = hand_tracker.call("get_mirrored_landmarks_2d") as PackedVector2Array
					if mirrored.size() == 21:
						_last_shadow_landmarks_2d = mirrored
			if is_fist_held and not _last_shadow_fist:
				hand_shadow_pulse = 1.0
				_shadow_geometry_dirty = true
			_last_shadow_fist = is_fist_held
		else:
			_last_shadow_fist = false
			if bool(player.get("external_tracking_active")) or bool(player.get("shield_held")):
				release_hand_tracking_target()

		if not is_inside_tree() and delta > 0.0:
			var needs_step: bool = bool(player.get("external_tracking_active")) or bool(player.get("shield_held")) or bool(player.get("is_shielding"))
			if needs_step and player.has_method("simulate_physics"):
				player.call("simulate_physics", delta)

	_update_hand_status_hud()
	_update_hand_shadow(delta)


func _update_hand_status_hud() -> void:
	var state: int = 0
	var label_str: String = "HAND: OFFLINE"
	if hand_tracker != null:
		state = int(hand_tracker.get("tracking_state"))
		if hand_tracker.has_method("get_status_label_text"):
			label_str = str(hand_tracker.call("get_status_label_text"))

	if hand_status_label != null:
		if hand_status_label.text != label_str:
			hand_status_label.text = label_str
		if state != _last_hand_state or label_str != _last_hand_label:
			match state:
				2: # TRACKING
					hand_status_label.add_theme_color_override("font_color", Color.WHITE)
				1: # NO_HAND
					hand_status_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1.0))
				_: # OFFLINE
					hand_status_label.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50, 1.0))

	if hand_status_icon != null and state != _last_hand_state:
		match state:
			2: # TRACKING
				hand_status_icon.color = Color.WHITE
			1: # NO_HAND
				hand_status_icon.color = Color(0.68, 0.68, 0.68, 1.0)
			_: # OFFLINE
				hand_status_icon.color = Color(0.38, 0.38, 0.38, 1.0)
		hand_status_icon.scale = Vector2.ONE

	if hand_status_pill != null and state != _last_hand_state:
		var pill_gray: float = 0.16 if state == 2 else 0.12
		hand_status_pill.color = Color(pill_gray, pill_gray, pill_gray, 0.92)

	var pulse_bucket: int = int(hand_shadow_pulse * 8.0)
	if hand_status_icon != null and pulse_bucket != _last_hand_pulse_bucket:
		var icon_scale: float = 1.0 + 0.25 * hand_shadow_pulse if state == 2 else 1.0
		hand_status_icon.scale = Vector2(icon_scale, icon_scale)

	_last_hand_state = state
	_last_hand_label = label_str
	_last_hand_pulse_bucket = pulse_bucket


func _update_hand_shadow(delta: float) -> void:
	if hand_shadow == null:
		return

	var has_tracked_hand: bool = hand_tracker != null and bool(hand_tracker.get("has_hand"))
	var is_fist_held: bool = hand_tracker != null and bool(hand_tracker.get("is_fist"))

	if hand_shadow_pulse > 0.0:
		hand_shadow_pulse = maxf(0.0, hand_shadow_pulse - maxf(0.0, delta) * 3.8)

	if has_tracked_hand:
		hand_shadow_alpha = clampf(maxf(0.55, hand_shadow_alpha + maxf(0.016, delta) * 6.0), 0.0, 1.0)
	else:
		hand_shadow_alpha = maxf(0.0, hand_shadow_alpha - maxf(0.0, delta) * 3.2)

	hand_shadow.modulate = Color(1.0, 1.0, 1.0, hand_shadow_alpha)
	hand_shadow.visible = hand_shadow_alpha > 0.001 and _last_shadow_landmarks_2d.size() == 21
	if _last_shadow_landmarks_2d.size() < 21:
		return

	var pulse_bucket: int = int(hand_shadow_pulse * 20.0)
	var geometry_dirty: bool = _shadow_geometry_dirty or is_fist_held != _last_shadow_fist or pulse_bucket != _last_shadow_pulse_bucket
	if not geometry_dirty:
		return
	_last_shadow_fist = is_fist_held
	_last_shadow_pulse_bucket = pulse_bucket
	_shadow_geometry_dirty = false

	var arena_size: Vector2 = _get_arena_size()
	var screen_pts: PackedVector2Array = PackedVector2Array()
	screen_pts.resize(21)
	for i: int in range(21):
		var norm_pt: Vector2 = _last_shadow_landmarks_2d[i]
		screen_pts[i] = Vector2(norm_pt.x * arena_size.x, norm_pt.y * arena_size.y)

	var palm_center_screen: Vector2 = Vector2.ZERO
	for p_idx: int in [0, 5, 9, 13, 17]:
		palm_center_screen += screen_pts[p_idx]
	palm_center_screen /= 5.0

	var contract_factor: float = clampf(hand_shadow_pulse * 0.25 + (0.12 if is_fist_held else 0.0), 0.0, 0.35)
	if contract_factor > 0.0:
		for tip_idx: int in FINGERTIP_INDICES:
			screen_pts[tip_idx] = screen_pts[tip_idx].lerp(palm_center_screen, contract_factor)

	if palm_polygon != null:
		var palm_verts: PackedVector2Array = PackedVector2Array()
		palm_verts.resize(PALM_POLYGON_INDICES.size())
		for i: int in range(PALM_POLYGON_INDICES.size()):
			palm_verts[i] = screen_pts[PALM_POLYGON_INDICES[i]]
		palm_polygon.polygon = palm_verts
		var palm_gray: float = lerpf(0.18, 0.40, hand_shadow_pulse)
		palm_polygon.color = Color(palm_gray, palm_gray, palm_gray, 0.42)

	_set_bone_line_points(thumb_bone, screen_pts, THUMB_BONE_INDICES)
	_set_bone_line_points(index_bone, screen_pts, INDEX_BONE_INDICES)
	_set_bone_line_points(middle_bone, screen_pts, MIDDLE_BONE_INDICES)
	_set_bone_line_points(ring_bone, screen_pts, RING_BONE_INDICES)
	_set_bone_line_points(pinky_bone, screen_pts, PINKY_BONE_INDICES)
	_set_bone_line_points(palm_bridge_bone, screen_pts, PALM_BRIDGE_INDICES)

	var bone_gray: float = lerpf(0.38, 0.78, hand_shadow_pulse)
	for bone_line: Line2D in [thumb_bone, index_bone, middle_bone, ring_bone, pinky_bone]:
		if bone_line != null:
			bone_line.default_color = Color(bone_gray, bone_gray, bone_gray, 0.68)

	var tip_nodes: Array[Polygon2D] = _get_fingertip_nodes()
	var tip_gray: float = lerpf(0.76, 1.0, maxf(hand_shadow_pulse, 0.5 if is_fist_held else 0.0))
	var tip_scale: float = 1.0 + 0.45 * hand_shadow_pulse
	for i: int in range(FINGERTIP_INDICES.size()):
		var tip_node: Polygon2D = tip_nodes[i]
		if tip_node != null:
			tip_node.position = screen_pts[FINGERTIP_INDICES[i]]
			tip_node.color = Color(tip_gray, tip_gray, tip_gray, 0.88)
			tip_node.scale = Vector2(tip_scale, tip_scale)

func _set_bone_line_points(line: Line2D, screen_pts: PackedVector2Array, indices: Array[int]) -> void:
	if line == null:
		return
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(indices.size())
	for i: int in range(indices.size()):
		pts[i] = screen_pts[indices[i]]
	line.points = pts


func _get_arena_size() -> Vector2:
	return _arena_size_cache


func _refresh_arena_size() -> void:
	if is_inside_tree():
		var rect_size: Vector2 = get_viewport_rect().size
		if rect_size.x > 0.0 and rect_size.y > 0.0:
			_arena_size_cache = rect_size
			return
	_arena_size_cache = Vector2(1152.0, 648.0)


func _on_viewport_resized() -> void:
	_refresh_arena_size()
	_sync_background_size()
	if game_camera != null:
		game_camera.position = _arena_size_cache * 0.5
	if arena_grid != null and arena_grid.has_method("set_arena_size"):
		arena_grid.call("set_arena_size", _arena_size_cache)


func _spawn_next_wave() -> void:
	var viewport_size: Vector2 = _get_arena_size()
	var player_pos: Vector2 = player.global_position if player != null else viewport_size * 0.5
	var current_wave: int = wave_index
	var pattern: int = current_wave % 7
	wave_index += 1

	# Waves 4..6 are autonomous slots. Rotate enemy -> saw -> wall so every
	# difficulty sees all threat types while the simultaneous cap stays intact.
	if pattern >= 4:
		if _spawn_rotating_autonomous_threat():
			return
		pattern = current_wave % 4

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
			var fill_mode: int = int(floor(float(current_wave) / 7.0)) % 3
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
			var edge_a: int = int(floor(float(current_wave) / 7.0)) % 4
			var edge_b: int = (edge_a + 2) % 4
			spawn_edge_projectile(edge_a)
			spawn_edge_projectile(edge_b)

		3: # Hazard Type 3: Stationary Exploding Object inside arena
			var exp_pos: Vector2 = _find_safe_spawn_position()
			spawn_exploder(exp_pos)


## Spawns the next available autonomous threat in enemy -> saw -> wall order.
## Returns false when the global or per-type caps leave no threat available.
func _spawn_rotating_autonomous_threat() -> bool:
	if not _can_spawn_autonomous_threat():
		return false
	for offset: int in range(3):
		var threat_kind: int = (autonomous_spawn_cursor + offset) % 3
		match threat_kind:
			0:
				if _count_active_threats(&"enemies") < get_max_enemies():
					spawn_enemy(enemies_spawned % 3)
					autonomous_spawn_cursor = (threat_kind + 1) % 3
					return true
			1:
				if _count_active_threats(&"saws") < get_max_saws():
					spawn_saw(saws_spawned % 2)
					autonomous_spawn_cursor = (threat_kind + 1) % 3
					return true
			2:
				if _count_active_threats(&"closing_walls") < 1:
					var wall_gap: float = MIN_WALL_GAP + float(2 - difficulty_mode) * 4.0
					var wall_warning: float = 1.35 - 0.10 * float(difficulty_mode)
					spawn_closing_wall(-1, -1.0, wall_gap, wall_warning)
					autonomous_spawn_cursor = (threat_kind + 1) % 3
					return true
	return false


func _on_player_hp_changed(new_hp: int, max_hp: int) -> void:
	if hp_label == null:
		return
	var blocks: String = ""
	for i: int in range(max_hp):
		blocks += "■ " if i < new_hp else "□ "
	hp_label.text = "HP: %s(%d/%d)" % [blocks, new_hp, max_hp]


func _update_shield_hud() -> void:
	if player == null or shield_fill == null or shield_bg == null:
		return
	var ratio: float = 1.0
	if player.has_method("get_shield_energy_ratio"):
		ratio = clampf(float(player.call("get_shield_energy_ratio")), 0.0, 1.0)
	var is_active: bool = bool(player.get("is_shielding"))
	var is_exhausted: bool = bool(player.get("shield_exhausted"))
	var state_text: String = "SHIELD: READY"
	var state_gray: float = 0.82
	if is_active:
		state_text = "SHIELD: ACTIVE"
		state_gray = 1.0
	elif is_exhausted:
		state_text = "SHIELD: EMPTY"
		state_gray = 0.45
	elif ratio < 0.999:
		state_text = "SHIELD: RECHARGING"
		state_gray = 0.65

	if absf(ratio - _last_shield_ratio) > 0.008:
		shield_fill.size.x = maxf(0.0, shield_bg.size.x * ratio)
		var fill_gray: float = 0.42 if is_exhausted else lerpf(0.60, 1.0, ratio)
		shield_fill.color = Color(fill_gray, fill_gray, fill_gray, 1.0)
		_last_shield_ratio = ratio

	if state_text != _last_shield_state:
		if shield_label != null:
			shield_label.text = state_text
			shield_label.add_theme_color_override("font_color", Color(state_gray, state_gray, state_gray, 1.0))
		_last_shield_state = state_text


func _on_player_shield_changed(active: bool) -> void:
	if player == null or arena_fx == null:
		return
	if active and is_level_running:
		arena_fx.call("spawn_ring", player.global_position, 16.0, 34.0, 0.22, Color(0.82, 0.82, 0.82, 0.7), 1.5)


func _on_player_shield_blocked() -> void:
	if player == null:
		return
	if arena_fx != null:
		arena_fx.call("spawn_ring", player.global_position, 16.0, 54.0, 0.30, Color(1.0, 1.0, 1.0, 0.9), 2.0)
		arena_fx.call("spawn_burst", player.global_position, 6, 190.0, Color(0.92, 0.92, 0.92, 1.0), 0.28, 8.0, 1.5)
	if arena_grid != null and arena_grid.has_method("pulse"):
		arena_grid.call("pulse", 0.45)
	trigger_screen_shake(2.6, 0.14)


func _on_player_shield_broken() -> void:
	if player == null:
		return
	if arena_fx != null:
		arena_fx.call("spawn_ring", player.global_position, 22.0, 92.0, 0.46, Color(0.92, 0.92, 0.92, 1.0), 2.5)
		arena_fx.call("spawn_burst", player.global_position, 18, 260.0, Color(0.85, 0.85, 0.85, 1.0), 0.42, 11.0, 2.0)
	if arena_grid != null and arena_grid.has_method("pulse"):
		arena_grid.call("pulse", 0.7)
	trigger_screen_shake(5.0, 0.30)


func _on_player_damaged(_amount: int) -> void:
	if player == null:
		return
	if arena_fx != null:
		arena_fx.call("spawn_burst", player.global_position, 12, 240.0, Color(0.95, 0.95, 0.95, 1.0), 0.36, 10.0, 2.0)
		arena_fx.call("spawn_ring", player.global_position, 8.0, 48.0, 0.34, Color(0.82, 0.82, 0.82, 1.0), 2.0)
	if arena_grid != null and arena_grid.has_method("pulse"):
		arena_grid.call("pulse", 0.55)
	trigger_screen_shake(4.2, 0.24)


func trigger_screen_shake(strength: float = 3.0, duration: float = 0.2) -> void:
	_shake_strength = maxf(_shake_strength, maxf(strength, 0.0))
	_shake_duration = maxf(duration, 0.05)
	_shake_time = maxf(_shake_time, _shake_duration)


func _update_screen_shake(delta: float) -> void:
	if game_camera == null:
		return
	if _shake_time <= 0.0:
		if game_camera.offset != Vector2.ZERO:
			game_camera.offset = Vector2.ZERO
		return
	_shake_time = maxf(0.0, _shake_time - maxf(delta, 0.0))
	var falloff: float = _shake_time / maxf(_shake_duration, 0.001)
	var offset: Vector2 = Vector2(
		_shake_rng.randf_range(-1.0, 1.0),
		_shake_rng.randf_range(-1.0, 1.0)
	) * _shake_strength * falloff
	game_camera.offset = offset
	if _shake_time <= 0.0:
		game_camera.offset = Vector2.ZERO
		_shake_strength = 0.0


func _on_player_died() -> void:
	if not is_level_running:
		return
	is_level_running = false
	_stop_music()
	_clear_beams()

	if game_over_panel != null:
		game_over_panel.visible = true
	if game_over_subtitle != null:
		game_over_subtitle.text = "Survived %.1fs on %s" % [elapsed_time, get_difficulty_name()]
	if retry_button != null and is_inside_tree() and not Engine.is_editor_hint():
		retry_button.grab_focus()
	if arena_grid != null and arena_grid.has_method("pulse"):
		arena_grid.call("pulse", 0.8)
	trigger_screen_shake(6.0, 0.35)

	game_over.emit()


func _update_hud_timer() -> void:
	var remaining: float = maxf(0.0, level_duration - elapsed_time)
	var tenths: int = int(round(remaining * 10.0))
	if timer_label != null and tenths != _hud_timer_bucket:
		timer_label.text = "TIME: %.1fs" % remaining
		_hud_timer_bucket = tenths
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
	if hand_status_pill != null and viewport_size.x > 240.0:
		hand_status_pill.position.x = (viewport_size.x - hand_status_pill.size.x) * 0.5
	if controls_hint_label != null and viewport_size.y > 40.0:
		controls_hint_label.position.y = viewport_size.y - 34.0
	if game_camera != null:
		game_camera.position = viewport_size * 0.5
	if arena_grid != null and arena_grid.has_method("set_arena_size"):
		arena_grid.call("set_arena_size", viewport_size)


func _on_retry_pressed() -> void:
	_play_menu_sfx(false)
	restart_level()


func _on_replay_pressed() -> void:
	_play_menu_sfx(false)
	restart_level()


func _on_main_menu_pressed() -> void:
	is_level_running = false
	_shake_time = 0.0
	if game_camera != null:
		game_camera.offset = Vector2.ZERO
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
	var stream: AudioStreamWAV = AudioLibrary.music()
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

	if shield_label != null:
		shield_label.add_theme_font_size_override("font_size", 13)
		shield_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82, 1.0))
	if shield_bg != null:
		shield_bg.color = Color(0.20, 0.20, 0.20, 1.0)
	if shield_fill != null:
		shield_fill.color = Color.WHITE
	if progress_fill != null:
		progress_fill.color = Color(0.92, 0.92, 0.92, 1.0)

	if hand_status_label != null:
		hand_status_label.add_theme_font_size_override("font_size", 14)
		hand_status_label.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50, 1.0))

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
