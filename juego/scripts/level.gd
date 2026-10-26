@tool
extends Node2D
## 45-second survival level controller.
## Scales attack spawn frequency by selected difficulty mode (Easy, Normal, Hard)
## while spawning all 9 monochrome primitive 2D hazard and enemy types (light beams,
## filling circles, edge projectiles, exploders, closing walls, rotating saws,
## chaser drones, chargers, and sniper turrets) into BeamContainer, and drives
## 30-to-60 FPS smoothed hand-tracking player control, HUD status pill, procedural
## grayscale articulated hand shadow, screen shake, and smooth overlay transitions.

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
const HAND_TRACKING_CLIENT_SCRIPT: GDScript = preload("res://scripts/hand_tracking_client.gd")
const DEFAULT_BEAM_WIDTH: float = 44.0
const DEFAULT_CIRCLE_RADIUS: float = 78.0
const DEFAULT_PROJECTILE_SPEED: float = 390.0
const DEFAULT_PROJECTILE_RADIUS: float = 10.0
const DEFAULT_EXPLODER_BURST_COUNT: int = 8
const DEFAULT_WALL_GAP_SIZE: float = 136.0
const DEFAULT_SAW_RADIUS: float = 36.0
const DEFAULT_SAW_SPEED: float = 340.0
const DEFAULT_CHASER_RADIUS: float = 18.0
const DEFAULT_CHASER_SPEED: float = 240.0
const DEFAULT_CHARGER_RADIUS: float = 20.0
const DEFAULT_CHARGER_SPEED: float = 780.0
const DEFAULT_TURRET_RADIUS: float = 22.0
const DEFAULT_TURRET_BURST_COUNT: int = 3
const DEFAULT_TURRET_PROJECTILE_SPEED: float = 480.0
const TELEGRAPH_TIME: float = 1.0
const ACTIVE_TIME: float = 0.35
const HAND_SHADOW_SMOOTH_SPEED: float = 26.0
const OVERLAY_TRANSITION_DURATION: float = 0.25

const PALM_POLYGON_INDICES: Array[int] = [0, 1, 5, 9, 13, 17]
const THUMB_BONE_INDICES: Array[int] = [0, 1, 2, 3, 4]
const INDEX_BONE_INDICES: Array[int] = [0, 5, 6, 7, 8]
const MIDDLE_BONE_INDICES: Array[int] = [0, 9, 10, 11, 12]
const RING_BONE_INDICES: Array[int] = [0, 13, 14, 15, 16]
const PINKY_BONE_INDICES: Array[int] = [0, 17, 18, 19, 20]
const PALM_BRIDGE_INDICES: Array[int] = [1, 5, 9, 13, 17, 0]
const FINGERTIP_INDICES: Array[int] = [4, 8, 12, 16, 20]

const DIFFICULTY_META_KEY: StringName = &"selected_difficulty"
const MENU_SFX_META_KEY: StringName = &"cached_menu_sfx_stream"
const AUDIO_MIX_RATE: int = 22050

## Persists difficulty across scene transitions when MainMenu changes scene to Level.
static var selected_difficulty: int = Difficulty.NORMAL
static var _music_stream: AudioStreamWAV = null
static var _menu_sfx_stream: AudioStreamWAV = null
static var _unit_fingertip_polygon: PackedVector2Array = PackedVector2Array()
static var _unit_status_icon_polygon: PackedVector2Array = PackedVector2Array()

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
var hand_shadow_dash_pulse: float = 0.0
var _target_shadow_landmarks_2d: PackedVector2Array = PackedVector2Array()
var _last_shadow_landmarks_2d: PackedVector2Array = PackedVector2Array()
var _shadow_had_hand: bool = false
var _owns_detached_tracker: bool = false

var _shadow_screen_pts: PackedVector2Array = PackedVector2Array()
var _shadow_palm_verts: PackedVector2Array = PackedVector2Array()
var _shadow_thumb_pts: PackedVector2Array = PackedVector2Array()
var _shadow_index_pts: PackedVector2Array = PackedVector2Array()
var _shadow_middle_pts: PackedVector2Array = PackedVector2Array()
var _shadow_ring_pts: PackedVector2Array = PackedVector2Array()
var _shadow_pinky_pts: PackedVector2Array = PackedVector2Array()
var _shadow_bridge_pts: PackedVector2Array = PackedVector2Array()

var screen_shake_intensity: float = 0.0
var screen_shake_timer: float = 0.0
var screen_shake_duration: float = 0.20
var screen_shake_offset: Vector2 = Vector2.ZERO
var overlay_transition_progress: float = 0.0
var _last_recorded_hp: int = 3

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
@onready var player: CharacterBody2D = $Player
@onready var progress_bg: ColorRect = $HUD/HUDRoot/ProgressBg
@onready var progress_fill: ColorRect = $HUD/HUDRoot/ProgressFill
@onready var hp_label: Label = $HUD/HUDRoot/HPLabel
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
	_init_reusable_shadow_buffers()
	_resolve_nodes()
	_configure_hand_shadow_primitives()
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
		if player.has_signal("shield_blocked") and not player.is_connected("shield_blocked", _on_player_shield_blocked):
			player.connect("shield_blocked", _on_player_shield_blocked)

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

	if not Engine.is_editor_hint():
		restart_level()
	else:
		is_music_playing = is_level_running


func _init_reusable_shadow_buffers() -> void:
	if _unit_fingertip_polygon.is_empty():
		_unit_fingertip_polygon = PackedVector2Array([
			Vector2(0.0, -7.0),
			Vector2(5.0, -5.0),
			Vector2(7.0, 0.0),
			Vector2(5.0, 5.0),
			Vector2(0.0, 7.0),
			Vector2(-5.0, 5.0),
			Vector2(-7.0, 0.0),
			Vector2(-5.0, -5.0),
		])
	if _unit_status_icon_polygon.is_empty():
		_unit_status_icon_polygon = PackedVector2Array([
			Vector2(0.0, -6.0),
			Vector2(6.0, 0.0),
			Vector2(0.0, 6.0),
			Vector2(-6.0, 0.0),
		])
	_shadow_screen_pts.resize(21)
	_shadow_palm_verts.resize(PALM_POLYGON_INDICES.size())
	_shadow_thumb_pts.resize(THUMB_BONE_INDICES.size())
	_shadow_index_pts.resize(INDEX_BONE_INDICES.size())
	_shadow_middle_pts.resize(MIDDLE_BONE_INDICES.size())
	_shadow_ring_pts.resize(RING_BONE_INDICES.size())
	_shadow_pinky_pts.resize(PINKY_BONE_INDICES.size())
	_shadow_bridge_pts.resize(PALM_BRIDGE_INDICES.size())


func _exit_tree() -> void:
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
			return lerpf(1.36, 1.04, clamped)
		Difficulty.HARD:
			return lerpf(0.72, 0.46, clamped)
		_:
			return lerpf(1.04, 0.74, clamped)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances the level timer, wave spawning, active hazards, hand tracking, screen shake, and HUD by delta seconds.
func simulate_physics(delta: float) -> void:
	_sync_background_size()
	_update_hand_tracking(delta)
	_update_screen_shake(delta)
	if not is_level_running:
		_update_overlay_transitions(delta)
		return

	if not is_inside_tree() and beam_container != null and delta > 0.0:
		var snapshot: Array[Node] = beam_container.get_children()
		for child: Node in snapshot:
			if is_instance_valid(child) and child.get_parent() == beam_container and child.has_method("simulate_physics"):
				child.call("simulate_physics", delta)
				if is_instance_valid(child) and child.get_parent() == null:
					child.free()
				if not is_level_running:
					_update_overlay_transitions(delta)
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
	_last_recorded_hp = 3
	_reset_screen_shake()
	_reset_overlay_panels()

	var viewport_size: Vector2 = _get_arena_size()
	var center_pos: Vector2 = viewport_size * 0.5

	if player != null and player.has_method("reset_player"):
		player.call("reset_player", center_pos)

	_update_hud_timer()
	_on_player_hp_changed(3, 3)
	_update_hand_status_hud()
	_update_hand_shadow(0.0)
	_start_music()


func _instantiate_hazard() -> Area2D:
	if beam_container == null:
		return null
	var hazard: Area2D = LIGHT_BEAM_SCENE.instantiate() as Area2D
	if hazard != null:
		hazard.set("target_player", player)
		beam_container.add_child(hazard)
	return hazard


## Spawns a single edge-to-edge light beam obstacle at the given position and angle.
func spawn_beam(
	spawn_pos: Vector2,
	angle_radians: float,
	width: float = DEFAULT_BEAM_WIDTH,
	warning_time: float = TELEGRAPH_TIME,
	active_time: float = ACTIVE_TIME
) -> Area2D:
	var beam: Area2D = _instantiate_hazard()
	if beam != null and beam.has_method("configure"):
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
	var hazard: Area2D = _instantiate_hazard()
	if hazard != null and hazard.has_method("configure_circle"):
		hazard.call("configure_circle", spawn_pos, radius, fill_mode, warning_time, active_time)
	return hazard


## Spawns an un-telegraphed projectile obstacle moving in a straight line.
func spawn_projectile(
	spawn_pos: Vector2,
	direction: Vector2,
	speed: float = DEFAULT_PROJECTILE_SPEED,
	radius: float = DEFAULT_PROJECTILE_RADIUS
) -> Area2D:
	var hazard: Area2D = _instantiate_hazard()
	if hazard != null and hazard.has_method("configure_projectile"):
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
	if player != null and is_inside_tree() and rng.randf() < 0.55:
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
	var hazard: Area2D = _instantiate_hazard()
	if hazard != null and hazard.has_method("configure_exploder"):
		hazard.call("configure_exploder", spawn_pos, warning_time, burst_count, projectile_speed)
	return hazard


## Spawns opposing closing walls along arena borders leaving a collision-free safe corridor gap (AC3).
func spawn_closing_walls(
	axis: int = 0,
	gap_center: float = -1.0,
	gap_size: float = DEFAULT_WALL_GAP_SIZE,
	warning_time: float = TELEGRAPH_TIME,
	active_time: float = 0.45
) -> Area2D:
	var hazard: Area2D = _instantiate_hazard()
	if hazard != null and hazard.has_method("configure_closing_walls"):
		hazard.call("configure_closing_walls", axis, gap_center, gap_size, warning_time, active_time)
	return hazard


## Spawns a rotating toothed saw hazard that telegraphs and traverses/bounces across the arena (AC4).
func spawn_saw(
	spawn_pos: Vector2,
	direction: Vector2 = Vector2.RIGHT,
	speed: float = DEFAULT_SAW_SPEED,
	radius: float = DEFAULT_SAW_RADIUS,
	warning_time: float = 0.85,
	active_time: float = 3.2,
	bounces: int = 1
) -> Area2D:
	var hazard: Area2D = _instantiate_hazard()
	if hazard != null and hazard.has_method("configure_saw"):
		hazard.call("configure_saw", spawn_pos, direction, speed, radius, warning_time, active_time, bounces)
	return hazard


## Spawns a Chaser / Homing Drone enemy that telegraphs and steers toward the player for a fixed lifetime (AC5a).
func spawn_chaser(
	spawn_pos: Vector2,
	speed: float = DEFAULT_CHASER_SPEED,
	warning_time: float = 0.85,
	active_time: float = 3.2,
	radius: float = DEFAULT_CHASER_RADIUS
) -> Area2D:
	var hazard: Area2D = _instantiate_hazard()
	if hazard != null and hazard.has_method("configure_chaser"):
		hazard.call("configure_chaser", spawn_pos, speed, warning_time, active_time, radius)
	return hazard


## Spawns a Charger / Dasher enemy that rotates/locks onto the player during telegraph and lunges in a straight line (AC5b).
func spawn_charger(
	spawn_pos: Vector2,
	speed: float = DEFAULT_CHARGER_SPEED,
	warning_time: float = TELEGRAPH_TIME,
	active_time: float = 0.85,
	radius: float = DEFAULT_CHARGER_RADIUS
) -> Area2D:
	var hazard: Area2D = _instantiate_hazard()
	if hazard != null and hazard.has_method("configure_charger"):
		hazard.call("configure_charger", spawn_pos, speed, warning_time, active_time, radius)
	return hazard


## Spawns a stationary Turret / Sniper enemy that tracks the player with an aim line and fires an aimed projectile burst (AC5c).
func spawn_turret(
	spawn_pos: Vector2,
	warning_time: float = TELEGRAPH_TIME,
	burst_count: int = DEFAULT_TURRET_BURST_COUNT,
	projectile_speed: float = DEFAULT_TURRET_PROJECTILE_SPEED,
	active_time: float = ACTIVE_TIME,
	radius: float = DEFAULT_TURRET_RADIUS
) -> Area2D:
	var hazard: Area2D = _instantiate_hazard()
	if hazard != null and hazard.has_method("configure_turret"):
		hazard.call("configure_turret", spawn_pos, warning_time, burst_count, projectile_speed, active_time, radius)
	return hazard


## Triggers a decaying monochrome arena screen shake offset without displacing player coordinates (AC7 / O5).
func trigger_screen_shake(intensity: float = 7.0, duration: float = 0.20) -> void:
	screen_shake_intensity = maxf(screen_shake_intensity, intensity)
	screen_shake_duration = maxf(0.05, duration)
	screen_shake_timer = maxf(screen_shake_timer, duration)
	_update_screen_shake(0.001)


func _update_screen_shake(delta: float) -> void:
	if screen_shake_timer > 0.0:
		screen_shake_timer = maxf(0.0, screen_shake_timer - maxf(0.0, delta))
		if screen_shake_timer > 0.0:
			var ratio: float = clampf(screen_shake_timer / maxf(screen_shake_duration, 0.001), 0.0, 1.0)
			var mag: float = screen_shake_intensity * ratio
			var phase: float = (screen_shake_duration - screen_shake_timer) * 58.0
			screen_shake_offset = Vector2(sin(phase * 1.3) * mag, cos(phase * 1.9) * mag)
		else:
			screen_shake_intensity = 0.0
			screen_shake_offset = Vector2.ZERO
	else:
		screen_shake_offset = Vector2.ZERO

	if beam_container != null:
		beam_container.position = screen_shake_offset
	if hand_shadow != null:
		hand_shadow.position = screen_shake_offset


func _reset_screen_shake() -> void:
	screen_shake_intensity = 0.0
	screen_shake_timer = 0.0
	screen_shake_offset = Vector2.ZERO
	if beam_container != null:
		beam_container.position = Vector2.ZERO
	if hand_shadow != null:
		hand_shadow.position = Vector2.ZERO


func _begin_overlay_transition(panel: ColorRect) -> void:
	if panel == null:
		return
	var arena: Vector2 = _get_arena_size()
	panel.pivot_offset = arena * 0.5
	panel.visible = true
	overlay_transition_progress = 0.0
	_apply_overlay_transition_state(panel, 0.0)


func _apply_overlay_transition_state(panel: ColorRect, progress: float) -> void:
	if panel == null:
		return
	var clamped: float = clampf(progress, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - clamped, 3.0)
	var alpha: float = lerpf(0.22, 1.0, eased)
	var s: float = lerpf(0.92, 1.0, eased)
	panel.modulate = Color(1.0, 1.0, 1.0, alpha)
	panel.scale = Vector2(s, s)


func _update_overlay_transitions(delta: float) -> void:
	if overlay_transition_progress < 1.0:
		overlay_transition_progress = clampf(overlay_transition_progress + maxf(delta, 0.0) / OVERLAY_TRANSITION_DURATION, 0.0, 1.0)
	if game_over_panel != null and game_over_panel.visible:
		_apply_overlay_transition_state(game_over_panel, overlay_transition_progress)
	if level_complete_panel != null and level_complete_panel.visible:
		_apply_overlay_transition_state(level_complete_panel, overlay_transition_progress)


func _reset_overlay_panels() -> void:
	overlay_transition_progress = 0.0
	for panel: ColorRect in [game_over_panel, level_complete_panel]:
		if panel != null:
			panel.visible = false
			panel.modulate = Color.WHITE
			panel.scale = Vector2.ONE


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


## Stops the level and displays the Level Complete screen with smooth fade/scale transition.
func trigger_level_complete() -> void:
	if not is_level_running:
		return
	is_level_running = false
	_stop_music()
	elapsed_time = level_duration
	_update_hud_timer()
	_clear_beams()
	_reset_screen_shake()

	if player != null:
		player.set("is_active", false)

	_begin_overlay_transition(level_complete_panel)
	if replay_button != null and is_inside_tree() and not Engine.is_editor_hint():
		replay_button.grab_focus()

	level_completed.emit()


func _resolve_nodes() -> void:
	if not InputMap.has_action("move_left"):
		InputMap.load_from_project_settings()
	_init_reusable_shadow_buffers()
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
	player = get_node_or_null("Player") as CharacterBody2D
	progress_bg = get_node_or_null("HUD/HUDRoot/ProgressBg") as ColorRect
	progress_fill = get_node_or_null("HUD/HUDRoot/ProgressFill") as ColorRect
	hp_label = get_node_or_null("HUD/HUDRoot/HPLabel") as Label
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
	complete_menu_button = get_node_or_null("HUD/HUDRoot/LevelCompletePanel/VBoxContainer/CompleteMainMenuButton") as Button
	music_player = get_node_or_null("MusicPlayer") as AudioStreamPlayer
	sfx_player = get_node_or_null("SfxPlayer") as AudioStreamPlayer

	if not is_inside_tree() or not Engine.is_editor_hint():
		if music_player != null and music_player.stream == null:
			music_player.stream = _get_music_stream()
		if sfx_player != null and sfx_player.stream == null:
			sfx_player.stream = _get_menu_sfx_stream()

	if hand_tracker == null or not is_instance_valid(hand_tracker):
		if is_inside_tree() and get_tree() != null and get_tree().root != null:
			hand_tracker = get_tree().root.get_node_or_null("HandTrackingClient")
			_owns_detached_tracker = false
		if hand_tracker == null:
			var local_tracker: Node = HAND_TRACKING_CLIENT_SCRIPT.new()
			local_tracker.set("auto_manage_process", false)
			hand_tracker = local_tracker
			_owns_detached_tracker = true


func _configure_hand_shadow_primitives() -> void:
	_init_reusable_shadow_buffers()
	for tip_node: Polygon2D in _get_fingertip_nodes():
		if tip_node != null:
			tip_node.polygon = _unit_fingertip_polygon
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
		hand_status_icon.polygon = _unit_status_icon_polygon


func _get_fingertip_nodes() -> Array[Polygon2D]:
	return [fingertip_4, fingertip_8, fingertip_12, fingertip_16, fingertip_20]


func _update_hand_tracking(delta: float) -> void:
	_resolve_nodes()
	if hand_tracker != null:
		var tracker_in_tree: bool = hand_tracker.is_inside_tree()
		if not tracker_in_tree or Engine.is_editor_hint():
			if hand_tracker.has_method("poll_and_update"):
				hand_tracker.call("poll_and_update", delta)

	_sync_hand_tracking_to_gameplay(delta)


func _sync_hand_tracking_to_gameplay(delta: float) -> void:
	var has_tracked_hand: bool = false
	if hand_tracker != null:
		has_tracked_hand = bool(hand_tracker.get("has_hand"))

	if is_level_running and player != null:
		if has_tracked_hand:
			var palm_norm: Vector2 = hand_tracker.call("get_mirrored_palm_center") as Vector2
			set_normalized_hand_tracking_target(palm_norm)
			if hand_tracker.has_method("consume_fist_dash_trigger") and bool(hand_tracker.call("consume_fist_dash_trigger")):
				if player.has_method("trigger_shield"):
					player.call("trigger_shield")
				else:
					player.call("trigger_dash")
				hand_shadow_dash_pulse = 1.0
		else:
			if bool(player.get("external_tracking_active")):
				release_hand_tracking_target()

		if not is_inside_tree() and delta > 0.0:
			if bool(player.get("external_tracking_active")) or bool(player.get("is_dashing")) or bool(player.get("is_shield_active")):
				if player.has_method("simulate_physics"):
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
		hand_status_label.text = label_str
		match state:
			2: # TRACKING
				hand_status_label.add_theme_color_override("font_color", Color.WHITE)
			1: # NO_HAND
				hand_status_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1.0))
			_: # OFFLINE
				hand_status_label.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50, 1.0))

	if hand_status_icon != null:
		match state:
			2: # TRACKING
				hand_status_icon.color = Color.WHITE
				var icon_scale: float = 1.0 + 0.25 * hand_shadow_dash_pulse
				hand_status_icon.scale = Vector2(icon_scale, icon_scale)
			1: # NO_HAND
				hand_status_icon.color = Color(0.68, 0.68, 0.68, 1.0)
				hand_status_icon.scale = Vector2.ONE
			_: # OFFLINE
				hand_status_icon.color = Color(0.38, 0.38, 0.38, 1.0)
				hand_status_icon.scale = Vector2.ONE

	if hand_status_pill != null:
		var pill_gray: float = 0.16 if state == 2 else 0.12
		hand_status_pill.color = Color(pill_gray, pill_gray, pill_gray, 0.92)


func _update_hand_shadow(delta: float) -> void:
	if hand_shadow == null:
		return

	_init_reusable_shadow_buffers()
	var has_tracked_hand: bool = hand_tracker != null and bool(hand_tracker.get("has_hand"))
	var is_fist_held: bool = hand_tracker != null and bool(hand_tracker.get("is_fist"))

	if hand_shadow_dash_pulse > 0.0:
		hand_shadow_dash_pulse = maxf(0.0, hand_shadow_dash_pulse - maxf(0.0, delta) * 3.8)

	if has_tracked_hand:
		hand_shadow_alpha = clampf(maxf(0.55, hand_shadow_alpha + maxf(0.016, delta) * 6.0), 0.0, 1.0)
		if hand_tracker.has_method("get_mirrored_landmarks_2d"):
			var mirrored: PackedVector2Array = hand_tracker.call("get_mirrored_landmarks_2d") as PackedVector2Array
			if mirrored.size() == 21:
				_target_shadow_landmarks_2d = mirrored
				if not _shadow_had_hand or _last_shadow_landmarks_2d.size() != 21 or delta <= 0.0:
					_last_shadow_landmarks_2d = mirrored.duplicate()
				else:
					var smooth_t: float = 1.0 - exp(-HAND_SHADOW_SMOOTH_SPEED * maxf(delta, 0.001))
					for i: int in range(21):
						_last_shadow_landmarks_2d[i] = _last_shadow_landmarks_2d[i].lerp(_target_shadow_landmarks_2d[i], smooth_t)
		_shadow_had_hand = true
	else:
		_shadow_had_hand = false
		hand_shadow_alpha = maxf(0.0, hand_shadow_alpha - maxf(0.0, delta) * 3.2)

	hand_shadow.modulate = Color(1.0, 1.0, 1.0, hand_shadow_alpha)
	hand_shadow.visible = hand_shadow_alpha > 0.001 and _last_shadow_landmarks_2d.size() == 21
	if _last_shadow_landmarks_2d.size() < 21:
		return

	var arena_size: Vector2 = _get_arena_size()
	for i: int in range(21):
		var norm_pt: Vector2 = _last_shadow_landmarks_2d[i]
		_shadow_screen_pts[i] = Vector2(norm_pt.x * arena_size.x, norm_pt.y * arena_size.y)

	var palm_center_screen: Vector2 = Vector2.ZERO
	for p_idx: int in [0, 5, 9, 13, 17]:
		palm_center_screen += _shadow_screen_pts[p_idx]
	palm_center_screen /= 5.0

	var contract_factor: float = clampf(hand_shadow_dash_pulse * 0.25 + (0.12 if is_fist_held else 0.0), 0.0, 0.35)
	if contract_factor > 0.0:
		for tip_idx: int in FINGERTIP_INDICES:
			_shadow_screen_pts[tip_idx] = _shadow_screen_pts[tip_idx].lerp(palm_center_screen, contract_factor)

	if palm_polygon != null:
		for i: int in range(PALM_POLYGON_INDICES.size()):
			_shadow_palm_verts[i] = _shadow_screen_pts[PALM_POLYGON_INDICES[i]]
		palm_polygon.polygon = _shadow_palm_verts
		var palm_gray: float = lerpf(0.18, 0.40, hand_shadow_dash_pulse)
		palm_polygon.color = Color(palm_gray, palm_gray, palm_gray, 0.42)

	_fill_bone_line_points(thumb_bone, _shadow_thumb_pts, _shadow_screen_pts, THUMB_BONE_INDICES)
	_fill_bone_line_points(index_bone, _shadow_index_pts, _shadow_screen_pts, INDEX_BONE_INDICES)
	_fill_bone_line_points(middle_bone, _shadow_middle_pts, _shadow_screen_pts, MIDDLE_BONE_INDICES)
	_fill_bone_line_points(ring_bone, _shadow_ring_pts, _shadow_screen_pts, RING_BONE_INDICES)
	_fill_bone_line_points(pinky_bone, _shadow_pinky_pts, _shadow_screen_pts, PINKY_BONE_INDICES)
	_fill_bone_line_points(palm_bridge_bone, _shadow_bridge_pts, _shadow_screen_pts, PALM_BRIDGE_INDICES)

	var bone_gray: float = lerpf(0.38, 0.78, hand_shadow_dash_pulse)
	for bone_line: Line2D in [thumb_bone, index_bone, middle_bone, ring_bone, pinky_bone]:
		if bone_line != null:
			bone_line.default_color = Color(bone_gray, bone_gray, bone_gray, 0.68)

	var tip_nodes: Array[Polygon2D] = _get_fingertip_nodes()
	var tip_gray: float = lerpf(0.76, 1.0, maxf(hand_shadow_dash_pulse, 0.5 if is_fist_held else 0.0))
	var tip_scale: float = 1.0 + 0.45 * hand_shadow_dash_pulse
	for i: int in range(FINGERTIP_INDICES.size()):
		var tip_node: Polygon2D = tip_nodes[i]
		if tip_node != null:
			tip_node.position = _shadow_screen_pts[FINGERTIP_INDICES[i]]
			tip_node.color = Color(tip_gray, tip_gray, tip_gray, 0.88)
			tip_node.scale = Vector2(tip_scale, tip_scale)


func _fill_bone_line_points(line: Line2D, buf: PackedVector2Array, screen_pts: PackedVector2Array, indices: Array[int]) -> void:
	if line == null:
		return
	var count: int = indices.size()
	if buf.size() != count:
		buf.resize(count)
	for i: int in range(count):
		buf[i] = screen_pts[indices[i]]
	line.points = buf


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
	var pattern: int = current_wave % 9
	wave_index += 1
	var detached_safe_mode: bool = not is_inside_tree()

	match pattern:
		0: # Hazard Type 0: Edge-to-edge Light Beam
			var angle: float = 0.0 if detached_safe_mode else rng.randf_range(-PI, PI)
			var pos: Vector2
			if detached_safe_mode:
				pos = Vector2(viewport_size.x * 0.5, 96.0)
			else:
				var offset: Vector2 = Vector2.from_angle(angle + PI * 0.5) * rng.randf_range(-35.0, 35.0)
				pos = Vector2(
					clampf(player_pos.x + offset.x, 80.0, viewport_size.x - 80.0),
					clampf(player_pos.y + offset.y, 80.0, viewport_size.y - 80.0)
				)
			spawn_beam(pos, angle)

		1: # Hazard Type 1: Filling Circle (cycles CENTER_OUT, OUTSIDE_IN, ANGULAR_SWEEP)
			var fill_mode: int = int(floor(float(current_wave) / 9.0)) % 3
			var circle_pos: Vector2
			if detached_safe_mode:
				circle_pos = Vector2(220.0, 140.0)
			else:
				var offset_c: Vector2 = Vector2(
					rng.randf_range(-120.0, 120.0),
					rng.randf_range(-100.0, 100.0)
				)
				circle_pos = Vector2(
					clampf(player_pos.x + offset_c.x, 110.0, viewport_size.x - 110.0),
					clampf(player_pos.y + offset_c.y, 110.0, viewport_size.y - 110.0)
				)
			spawn_circle(circle_pos, DEFAULT_CIRCLE_RADIUS, fill_mode)

		2: # Hazard Type 2: Un-telegraphed Edge Projectiles
			if detached_safe_mode:
				spawn_projectile(Vector2(120.0, 0.0), Vector2.DOWN, DEFAULT_PROJECTILE_SPEED, DEFAULT_PROJECTILE_RADIUS)
				spawn_projectile(Vector2(viewport_size.x - 120.0, viewport_size.y), Vector2.UP, DEFAULT_PROJECTILE_SPEED, DEFAULT_PROJECTILE_RADIUS)
			else:
				var edge_a: int = int(floor(float(current_wave) / 9.0)) % 4
				var edge_b: int = (edge_a + 2) % 4
				spawn_edge_projectile(edge_a)
				spawn_edge_projectile(edge_b)

		3: # Hazard Type 3: Stationary Exploding Object inside arena
			var exp_pos: Vector2
			if detached_safe_mode:
				exp_pos = Vector2(210.0, 140.0)
			else:
				exp_pos = Vector2(
					rng.randf_range(viewport_size.x * 0.22, viewport_size.x * 0.78),
					rng.randf_range(viewport_size.y * 0.22, viewport_size.y * 0.78)
				)
			spawn_exploder(exp_pos)

		4: # Hazard Type 4: Closing Walls / Crushing Hazard
			var axis: int = int(floor(float(current_wave) / 9.0)) % 2
			var gap_center: float
			if detached_safe_mode:
				gap_center = (viewport_size.y * 0.5) if axis == 0 else (viewport_size.x * 0.5)
			else:
				var base_c: float = player_pos.y if axis == 0 else player_pos.x
				gap_center = base_c + rng.randf_range(-65.0, 65.0)
			spawn_closing_walls(axis, gap_center, DEFAULT_WALL_GAP_SIZE)

		5: # Hazard Type 5: Rotating Hazard Saw
			var saw_pos: Vector2 = Vector2(140.0, 110.0) if detached_safe_mode else Vector2(
				90.0 if rng.randf() < 0.5 else viewport_size.x - 90.0,
				rng.randf_range(110.0, viewport_size.y - 110.0)
			)
			var saw_dir: Vector2 = Vector2.RIGHT if detached_safe_mode else (player_pos - saw_pos).normalized()
			spawn_saw(saw_pos, saw_dir, DEFAULT_SAW_SPEED, DEFAULT_SAW_RADIUS)

		6: # Hazard Type 6: Chaser / Homing Drone Enemy
			var chaser_pos: Vector2 = Vector2(140.0, 110.0) if detached_safe_mode else Vector2(
				rng.randf_range(90.0, viewport_size.x - 90.0),
				90.0 if rng.randf() < 0.5 else viewport_size.y - 90.0
			)
			var chaser: Area2D = spawn_chaser(chaser_pos, DEFAULT_CHASER_SPEED)
			if detached_safe_mode and chaser != null:
				chaser.set("use_target_position_override", true)
				chaser.set("target_position_override", Vector2(viewport_size.x - 140.0, 110.0))

		7: # Hazard Type 7: Charger / Dasher Enemy
			var charger_pos: Vector2 = Vector2(160.0, 540.0) if detached_safe_mode else Vector2(
				100.0 if rng.randf() < 0.5 else viewport_size.x - 100.0,
				rng.randf_range(100.0, viewport_size.y - 100.0)
			)
			var charger: Area2D = spawn_charger(charger_pos, DEFAULT_CHARGER_SPEED)
			if detached_safe_mode and charger != null:
				charger.set("use_target_position_override", true)
				charger.set("target_position_override", Vector2(viewport_size.x - 160.0, 540.0))

		8: # Hazard Type 8: Turret / Sniper Enemy
			var turret_pos: Vector2 = Vector2(980.0, 120.0) if detached_safe_mode else Vector2(
				rng.randf_range(140.0, viewport_size.x - 140.0),
				rng.randf_range(110.0, viewport_size.y - 110.0)
			)
			var turret: Area2D = spawn_turret(turret_pos)
			if detached_safe_mode and turret != null:
				turret.set("use_target_position_override", true)
				turret.set("target_position_override", Vector2(160.0, 120.0))


func _on_player_hp_changed(new_hp: int, max_hp: int) -> void:
	if new_hp < _last_recorded_hp and is_level_running:
		trigger_screen_shake(9.0, 0.24)
	_last_recorded_hp = new_hp
	if hp_label == null:
		return
	var blocks: String = ""
	for i: int in range(max_hp):
		blocks += "■ " if i < new_hp else "□ "
	hp_label.text = "HP: %s(%d/%d)" % [blocks, new_hp, max_hp]


func _on_player_shield_blocked() -> void:
	if is_level_running:
		trigger_screen_shake(4.5, 0.14)


func _on_player_died() -> void:
	if not is_level_running:
		return
	is_level_running = false
	_stop_music()
	_clear_beams()
	_reset_screen_shake()

	_begin_overlay_transition(game_over_panel)
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
	if hand_status_pill != null and viewport_size.x > 240.0:
		hand_status_pill.position.x = (viewport_size.x - hand_status_pill.size.x) * 0.5
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
	if sfx_name == &"explosion" and is_level_running:
		trigger_screen_shake(6.0, 0.18)
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
	if _music_stream != null and _music_stream.resource_path.is_empty():
		return _music_stream
	_music_stream = null
	var notes: Array[float] = [220.0, 261.63, 329.63, 392.0, 293.66, 349.23, 329.63, 246.94]
	var step_duration: float = 0.20
	var step_samples: int = int(AUDIO_MIX_RATE * step_duration)
	var total_samples: int = step_samples * notes.size()
	var data: PackedByteArray = PackedByteArray()
	data.resize(total_samples * 2)
	var lead_phase: float = 0.0
	var bass_phase: float = 0.0
	for i: int in range(total_samples):
		var step_idx: int = mini(int(floor(float(i) / float(step_samples))), notes.size() - 1)
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

	if hand_status_label != null:
		hand_status_label.add_theme_font_size_override("font_size", 14)
		hand_status_label.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50, 1.0))

	if controls_hint_label != null:
		controls_hint_label.text = "MOVE: WASD / Arrows / Mouse / Hand   |   SHIELD: Space / Shift / Click / Fist"
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
