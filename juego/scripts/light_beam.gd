@tool
extends Area2D
## Unified monochrome primitive 2D hazard and enemy entity.
## Consolidates all 9 hazard and enemy behaviors into a single scene/script:
## 0. BEAM: Edge-to-edge rectangular light beam (telegraph -> solid white active -> fade out).
## 1. CIRCLE: Multi-pattern filling circle (center-out, outside-in, or angular sweep fill -> active burst -> fade out).
## 2. PROJECTILE: Un-telegraphed solid-white projectile with immediate active collision, despawning outside viewport or on shield impact.
## 3. EXPLODER: Stationary pulsing arena telegraph that detonates into a radial burst of active projectiles.
## 4. CLOSING_WALLS: Opposing arena-border crushing walls that telegraph, slam inward leaving a collision-free safe corridor gap, hold, and retract.
## 5. SAW: Toothed rotating monochrome Polygon2D blade that telegraphs and traverses/bounces across the arena.
## 6. CHASER: Homing drone enemy that telegraphs and steers toward the player for a fixed lifetime (~3.0s-4.0s).
## 7. CHARGER: Dasher enemy that rotates/locks onto the player during telegraph (~1.0s) and lunges rapidly in a straight line.
## 8. TURRET: Stationary sniper turret that tracks the player with an aim telegraph line and fires an aimed projectile burst.

enum Phase {
	TELEGRAPH,
	ACTIVE,
	FADE_OUT,
}

enum HazardType {
	BEAM = 0,
	CIRCLE = 1,
	PROJECTILE = 2,
	EXPLODER = 3,
	CLOSING_WALLS = 4,
	SAW = 5,
	CHASER = 6,
	CHARGER = 7,
	TURRET = 8,
}

enum CircleFillMode {
	CENTER_OUT = 0,
	OUTSIDE_IN = 1,
	ANGULAR_SWEEP = 2,
}

const DEFAULT_LENGTH: float = 3200.0
const DEFAULT_WIDTH: float = 44.0
const DEFAULT_CIRCLE_RADIUS: float = 78.0
const DEFAULT_PROJECTILE_RADIUS: float = 10.0
const DEFAULT_PROJECTILE_SPEED: float = 390.0
const DEFAULT_EXPLODER_RADIUS: float = 24.0
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
const CIRCLE_SEGMENTS: int = 32
const SAW_TEETH_COUNT: int = 12
const PLAYER_COLLISION_RADIUS: float = 12.0
const VIEWPORT_DESPAWN_MARGIN: float = 64.0
const AUDIO_MIX_RATE: int = 22050

static var _laser_sfx_stream: AudioStreamWAV = null
static var _explosion_sfx_stream: AudioStreamWAV = null
static var _self_packed_scene: PackedScene = null

static var _unit_circle_polygon: PackedVector2Array = PackedVector2Array()
static var _default_circle_polygon: PackedVector2Array = PackedVector2Array()
static var _unit_projectile_polygon: PackedVector2Array = PackedVector2Array()
static var _default_projectile_polygon: PackedVector2Array = PackedVector2Array()
static var _unit_octagon_polygon: PackedVector2Array = PackedVector2Array()
static var _default_exploder_polygon: PackedVector2Array = PackedVector2Array()
static var _unit_saw_polygon: PackedVector2Array = PackedVector2Array()
static var _default_saw_polygon: PackedVector2Array = PackedVector2Array()
static var _unit_chaser_polygon: PackedVector2Array = PackedVector2Array()
static var _default_chaser_polygon: PackedVector2Array = PackedVector2Array()
static var _unit_charger_polygon: PackedVector2Array = PackedVector2Array()
static var _default_charger_polygon: PackedVector2Array = PackedVector2Array()
static var _unit_turret_polygon: PackedVector2Array = PackedVector2Array()
static var _default_turret_polygon: PackedVector2Array = PackedVector2Array()
static var _static_polygons_initialized: bool = false

const TELEGRAPH_COLOR: Color = Color(0.32, 0.32, 0.32, 0.55)
const TELEGRAPH_LINE_COLOR: Color = Color(0.62, 0.62, 0.62, 0.85)
const CIRCLE_SHADOW_COLOR: Color = Color(0.28, 0.28, 0.28, 0.45)
const CIRCLE_FILL_COLOR: Color = Color(0.88, 0.88, 0.88, 0.85)
const ACTIVE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const FADE_COLOR: Color = Color(0.75, 0.75, 0.75, 0.6)

@export var telegraph_duration: float = 1.0
@export var active_duration: float = 0.35
@export var fade_duration: float = 0.2
@export var beam_width: float = DEFAULT_WIDTH
@export var beam_length: float = DEFAULT_LENGTH

var hazard_type: HazardType = HazardType.BEAM
var circle_fill_mode: CircleFillMode = CircleFillMode.CENTER_OUT
var circle_radius: float = DEFAULT_CIRCLE_RADIUS
var projectile_velocity: Vector2 = Vector2.ZERO
var projectile_radius: float = DEFAULT_PROJECTILE_RADIUS
var exploder_radius: float = DEFAULT_EXPLODER_RADIUS
var exploder_burst_count: int = DEFAULT_EXPLODER_BURST_COUNT
var exploder_projectile_speed: float = DEFAULT_PROJECTILE_SPEED
var has_detonated: bool = false

var wall_axis: int = 0
var wall_gap_center: float = 324.0
var wall_gap_size: float = DEFAULT_WALL_GAP_SIZE
var wall_a_rect: Rect2 = Rect2()
var wall_b_rect: Rect2 = Rect2()
var safe_corridor_rect: Rect2 = Rect2()

var saw_radius: float = DEFAULT_SAW_RADIUS
var saw_velocity: Vector2 = Vector2(DEFAULT_SAW_SPEED, 0.0)
var saw_spin_speed: float = 9.5
var saw_bounces_remaining: int = 1

var chaser_radius: float = DEFAULT_CHASER_RADIUS
var chaser_speed: float = DEFAULT_CHASER_SPEED
var chaser_turn_rate: float = 7.5
var chaser_velocity: Vector2 = Vector2.ZERO

var charger_radius: float = DEFAULT_CHARGER_RADIUS
var charger_speed: float = DEFAULT_CHARGER_SPEED
var charger_direction: Vector2 = Vector2.RIGHT

var turret_radius: float = DEFAULT_TURRET_RADIUS
var turret_burst_count: int = DEFAULT_TURRET_BURST_COUNT
var turret_projectile_speed: float = DEFAULT_TURRET_PROJECTILE_SPEED
var turret_aim_direction: Vector2 = Vector2.RIGHT
var has_fired: bool = false

var target_player: Node2D = null
var target_position_override: Vector2 = Vector2.ZERO
var use_target_position_override: bool = false

var current_phase: Phase = Phase.TELEGRAPH
var phase_timer: float = 0.0
var is_hazard_active: bool = false
var sfx_play_count: int = 0
var last_sfx_played: StringName = &""

var _wall_a_verts: PackedVector2Array = PackedVector2Array()
var _wall_b_verts: PackedVector2Array = PackedVector2Array()

@onready var beam_visual: Polygon2D = $BeamVisual
@onready var center_line: Polygon2D = $CenterLine
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sfx_player: AudioStreamPlayer = $SfxPlayer
var secondary_visual: Polygon2D = null
var secondary_collision: CollisionShape2D = null


func _ready() -> void:
	_ensure_static_polygons()
	_resolve_nodes()
	add_to_group("light_beams")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_rebuild_geometry()
	if hazard_type == HazardType.PROJECTILE:
		_enter_phase(Phase.ACTIVE)
	else:
		_enter_phase(Phase.TELEGRAPH)


static func _ensure_static_polygons() -> void:
	if _static_polygons_initialized:
		return
	_unit_circle_polygon = _create_regular_polygon(1.0, CIRCLE_SEGMENTS)
	_default_circle_polygon = _scale_polygon(_unit_circle_polygon, DEFAULT_CIRCLE_RADIUS)
	_unit_projectile_polygon = _create_regular_polygon(1.0, 12)
	_default_projectile_polygon = _scale_polygon(_unit_projectile_polygon, DEFAULT_PROJECTILE_RADIUS)
	_unit_octagon_polygon = _create_regular_polygon(1.0, 8)
	_default_exploder_polygon = _scale_polygon(_unit_octagon_polygon, DEFAULT_EXPLODER_RADIUS)

	var saw_pts: PackedVector2Array = PackedVector2Array()
	var total_saw_verts: int = SAW_TEETH_COUNT * 2
	saw_pts.resize(total_saw_verts)
	for i: int in range(total_saw_verts):
		var angle: float = (TAU * float(i)) / float(total_saw_verts)
		var r: float = 1.0 if (i % 2 == 0) else 0.68
		saw_pts[i] = Vector2.from_angle(angle) * r
	_unit_saw_polygon = saw_pts
	_default_saw_polygon = _scale_polygon(_unit_saw_polygon, DEFAULT_SAW_RADIUS)

	_unit_chaser_polygon = PackedVector2Array([
		Vector2(1.15, 0.0),
		Vector2(0.25, 0.72),
		Vector2(-0.85, 0.88),
		Vector2(-0.45, 0.22),
		Vector2(-0.95, 0.0),
		Vector2(-0.45, -0.22),
		Vector2(-0.85, -0.88),
		Vector2(0.25, -0.72),
	])
	_default_chaser_polygon = _scale_polygon(_unit_chaser_polygon, DEFAULT_CHASER_RADIUS)

	_unit_charger_polygon = PackedVector2Array([
		Vector2(1.35, 0.0),
		Vector2(-0.55, 0.85),
		Vector2(-0.30, 0.28),
		Vector2(-1.05, 0.0),
		Vector2(-0.30, -0.28),
		Vector2(-0.55, -0.85),
	])
	_default_charger_polygon = _scale_polygon(_unit_charger_polygon, DEFAULT_CHARGER_RADIUS)

	_unit_turret_polygon = PackedVector2Array([
		Vector2(1.25, -0.22),
		Vector2(1.25, 0.22),
		Vector2(0.72, 0.42),
		Vector2(0.0, 0.95),
		Vector2(-0.82, 0.72),
		Vector2(-0.95, 0.0),
		Vector2(-0.82, -0.72),
		Vector2(0.0, -0.95),
		Vector2(0.72, -0.42),
	])
	_default_turret_polygon = _scale_polygon(_unit_turret_polygon, DEFAULT_TURRET_RADIUS)
	_static_polygons_initialized = true


static func _create_regular_polygon(radius: float, segments: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var count: int = maxi(segments, 3)
	pts.resize(count)
	for i: int in range(count):
		var angle: float = (TAU * float(i)) / float(count)
		pts[i] = Vector2.from_angle(angle) * radius
	return pts


static func _scale_polygon(unit_poly: PackedVector2Array, scale_factor: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var count: int = unit_poly.size()
	pts.resize(count)
	for i: int in range(count):
		pts[i] = unit_poly[i] * scale_factor
	return pts


## Returns the precomputed static unit polygon for the given HazardType (O6).
static func get_static_unit_polygon(type: int) -> PackedVector2Array:
	_ensure_static_polygons()
	match type:
		HazardType.CIRCLE:
			return _unit_circle_polygon
		HazardType.PROJECTILE:
			return _unit_projectile_polygon
		HazardType.EXPLODER:
			return _unit_octagon_polygon
		HazardType.SAW:
			return _unit_saw_polygon
		HazardType.CHASER:
			return _unit_chaser_polygon
		HazardType.CHARGER:
			return _unit_charger_polygon
		HazardType.TURRET:
			return _unit_turret_polygon
		_:
			return _unit_octagon_polygon


func _resolve_nodes() -> void:
	_ensure_static_polygons()
	if beam_visual == null:
		beam_visual = get_node_or_null("BeamVisual") as Polygon2D
	if center_line == null:
		center_line = get_node_or_null("CenterLine") as Polygon2D
	if collision_shape == null:
		collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if sfx_player == null:
		sfx_player = get_node_or_null("SfxPlayer") as AudioStreamPlayer
	if sfx_player != null and sfx_player.stream == null:
		sfx_player.stream = _get_laser_sfx_stream()

	if secondary_visual == null:
		secondary_visual = get_node_or_null("SecondaryVisual") as Polygon2D
	if secondary_collision == null:
		secondary_collision = get_node_or_null("SecondaryCollision") as CollisionShape2D


func _reset_secondary_nodes() -> void:
	if secondary_visual != null:
		secondary_visual.visible = false
		secondary_visual.scale = Vector2.ONE
		secondary_visual.position = Vector2.ZERO
	if secondary_collision != null:
		secondary_collision.disabled = true
		secondary_collision.position = Vector2.ZERO
	if collision_shape != null:
		collision_shape.position = Vector2.ZERO


## Configures the hazard as an edge-to-edge rectangular light beam (default backward-compatible contract).
func configure(
	spawn_pos: Vector2,
	angle_radians: float,
	width: float = DEFAULT_WIDTH,
	warning_time: float = 1.0,
	active_time: float = 0.35
) -> void:
	_resolve_nodes()
	_reset_secondary_nodes()
	hazard_type = HazardType.BEAM
	global_position = spawn_pos
	rotation = angle_radians
	beam_width = width
	telegraph_duration = warning_time
	active_duration = active_time
	fade_duration = 0.2
	sfx_play_count = 0
	last_sfx_played = &""
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


## Configures the hazard as a filling circle with one of three fill patterns:
## 0 = CENTER_OUT, 1 = OUTSIDE_IN, 2 = ANGULAR_SWEEP.
func configure_circle(
	spawn_pos: Vector2,
	radius: float = DEFAULT_CIRCLE_RADIUS,
	fill_mode: int = CircleFillMode.CENTER_OUT,
	warning_time: float = 1.0,
	active_time: float = 0.35
) -> void:
	_resolve_nodes()
	_reset_secondary_nodes()
	hazard_type = HazardType.CIRCLE
	circle_radius = maxf(radius, 8.0)
	circle_fill_mode = clampi(fill_mode, 0, 2) as CircleFillMode
	global_position = spawn_pos
	rotation = 0.0
	telegraph_duration = warning_time
	active_duration = active_time
	fade_duration = 0.2
	sfx_play_count = 0
	last_sfx_played = &""
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


## Configures the hazard as an un-telegraphed solid-white projectile with immediate active collision.
func configure_projectile(
	spawn_pos: Vector2,
	direction: Vector2,
	speed: float = DEFAULT_PROJECTILE_SPEED,
	radius: float = DEFAULT_PROJECTILE_RADIUS
) -> void:
	_resolve_nodes()
	_reset_secondary_nodes()
	hazard_type = HazardType.PROJECTILE
	global_position = spawn_pos
	var dir: Vector2 = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	projectile_velocity = dir * speed
	projectile_radius = maxf(radius, 4.0)
	rotation = dir.angle()
	sfx_play_count = 0
	last_sfx_played = &""
	_rebuild_geometry()
	_enter_phase(Phase.ACTIVE)


## Configures the hazard as a stationary pulsing arena object that detonates into radial projectiles.
func configure_exploder(
	spawn_pos: Vector2,
	warning_time: float = 1.0,
	burst_count: int = DEFAULT_EXPLODER_BURST_COUNT,
	projectile_speed: float = DEFAULT_PROJECTILE_SPEED,
	radius: float = DEFAULT_EXPLODER_RADIUS
) -> void:
	_resolve_nodes()
	_reset_secondary_nodes()
	hazard_type = HazardType.EXPLODER
	global_position = spawn_pos
	rotation = 0.0
	telegraph_duration = warning_time
	exploder_burst_count = maxi(burst_count, 3)
	exploder_projectile_speed = projectile_speed
	exploder_radius = maxf(radius, 8.0)
	has_detonated = false
	sfx_play_count = 0
	last_sfx_played = &""
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


## Configures the hazard as opposing closing walls along arena borders leaving a safe corridor gap (AC3 / O3).
## axis: 0 = Top/Bottom walls closing vertically toward horizontal corridor at Y = gap_center;
##       1 = Left/Right walls closing horizontally toward vertical corridor at X = gap_center.
func configure_closing_walls(
	axis: int = 0,
	gap_center: float = -1.0,
	gap_size: float = DEFAULT_WALL_GAP_SIZE,
	warning_time: float = 1.0,
	active_time: float = 0.45
) -> void:
	_resolve_nodes()
	_reset_secondary_nodes()
	hazard_type = HazardType.CLOSING_WALLS
	wall_axis = posmod(axis, 2)
	var arena: Vector2 = _get_arena_size()
	var max_coord: float = arena.y if wall_axis == 0 else arena.x
	wall_gap_size = clampf(gap_size, 64.0, max_coord - 80.0)
	var default_center: float = max_coord * 0.5
	var raw_center: float = gap_center if gap_center >= 0.0 else default_center
	wall_gap_center = clampf(raw_center, wall_gap_size * 0.5 + 24.0, max_coord - wall_gap_size * 0.5 - 24.0)
	global_position = Vector2.ZERO
	rotation = 0.0
	telegraph_duration = warning_time
	active_duration = active_time
	fade_duration = 0.22
	sfx_play_count = 0
	last_sfx_played = &""
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


## Configures the hazard as a rotating toothed saw blade that telegraphs and traverses/bounces across the arena (AC4).
func configure_saw(
	spawn_pos: Vector2,
	direction: Vector2 = Vector2.RIGHT,
	speed: float = DEFAULT_SAW_SPEED,
	radius: float = DEFAULT_SAW_RADIUS,
	warning_time: float = 0.85,
	active_time: float = 3.2,
	bounces: int = 1
) -> void:
	_resolve_nodes()
	_reset_secondary_nodes()
	hazard_type = HazardType.SAW
	global_position = spawn_pos
	rotation = 0.0
	saw_radius = maxf(radius, 12.0)
	var dir: Vector2 = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	saw_velocity = dir * speed
	saw_bounces_remaining = maxi(0, bounces)
	telegraph_duration = warning_time
	active_duration = active_time
	fade_duration = 0.2
	sfx_play_count = 0
	last_sfx_played = &""
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


## Configures the entity as a Chaser / Homing Drone enemy that steers toward the player for a fixed lifetime (AC5a).
func configure_chaser(
	spawn_pos: Vector2,
	speed: float = DEFAULT_CHASER_SPEED,
	warning_time: float = 0.85,
	active_time: float = 3.2,
	radius: float = DEFAULT_CHASER_RADIUS
) -> void:
	_resolve_nodes()
	_reset_secondary_nodes()
	hazard_type = HazardType.CHASER
	global_position = spawn_pos
	chaser_speed = maxf(speed, 40.0)
	chaser_radius = maxf(radius, 8.0)
	var to_target: Vector2 = _get_target_player_position() - global_position
	var dir: Vector2 = to_target.normalized() if to_target.length_squared() > 0.0001 else Vector2.RIGHT
	chaser_velocity = dir * chaser_speed
	rotation = dir.angle()
	telegraph_duration = warning_time
	active_duration = active_time
	fade_duration = 0.2
	sfx_play_count = 0
	last_sfx_played = &""
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


## Configures the entity as a Charger / Dasher enemy that locks onto the player during telegraph and lunges in a straight line (AC5b).
func configure_charger(
	spawn_pos: Vector2,
	speed: float = DEFAULT_CHARGER_SPEED,
	warning_time: float = 1.0,
	active_time: float = 0.85,
	radius: float = DEFAULT_CHARGER_RADIUS
) -> void:
	_resolve_nodes()
	_reset_secondary_nodes()
	hazard_type = HazardType.CHARGER
	global_position = spawn_pos
	charger_speed = maxf(speed, 100.0)
	charger_radius = maxf(radius, 8.0)
	var to_target: Vector2 = _get_target_player_position() - global_position
	charger_direction = to_target.normalized() if to_target.length_squared() > 0.0001 else Vector2.RIGHT
	rotation = charger_direction.angle()
	telegraph_duration = warning_time
	active_duration = active_time
	fade_duration = 0.2
	sfx_play_count = 0
	last_sfx_played = &""
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


## Configures the entity as a stationary Turret / Sniper enemy that tracks the player with an aim line and fires an aimed projectile burst (AC5c).
func configure_turret(
	spawn_pos: Vector2,
	warning_time: float = 1.0,
	burst_count: int = DEFAULT_TURRET_BURST_COUNT,
	projectile_speed: float = DEFAULT_TURRET_PROJECTILE_SPEED,
	active_time: float = 0.35,
	radius: float = DEFAULT_TURRET_RADIUS
) -> void:
	_resolve_nodes()
	_reset_secondary_nodes()
	hazard_type = HazardType.TURRET
	global_position = spawn_pos
	turret_burst_count = maxi(1, burst_count)
	turret_projectile_speed = maxf(projectile_speed, 80.0)
	turret_radius = maxf(radius, 8.0)
	has_fired = false
	var to_target: Vector2 = _get_target_player_position() - global_position
	turret_aim_direction = to_target.normalized() if to_target.length_squared() > 0.0001 else Vector2.RIGHT
	rotation = turret_aim_direction.angle()
	telegraph_duration = warning_time
	active_duration = active_time
	fade_duration = 0.2
	sfx_play_count = 0
	last_sfx_played = &""
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances the hazard/enemy lifecycle, steering, movement, and overlap checks by delta seconds.
func simulate_physics(delta: float) -> void:
	phase_timer += delta

	match hazard_type:
		HazardType.BEAM:
			_simulate_beam(delta)
		HazardType.CIRCLE:
			_simulate_circle(delta)
		HazardType.PROJECTILE:
			_simulate_projectile(delta)
		HazardType.EXPLODER:
			_simulate_exploder(delta)
		HazardType.CLOSING_WALLS:
			_simulate_closing_walls(delta)
		HazardType.SAW:
			_simulate_saw(delta)
		HazardType.CHASER:
			_simulate_chaser(delta)
		HazardType.CHARGER:
			_simulate_charger(delta)
		HazardType.TURRET:
			_simulate_turret(delta)


func _simulate_beam(_delta: float) -> void:
	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				var pulse_alpha: float = lerpf(0.35, 0.68, progress)
				beam_visual.color = Color(0.35, 0.35, 0.35, pulse_alpha)
				beam_visual.scale.y = lerpf(0.85, 1.0, progress)
			if phase_timer >= telegraph_duration:
				_enter_phase(Phase.ACTIVE)

		Phase.ACTIVE:
			_check_player_overlap()
			if phase_timer >= active_duration:
				_enter_phase(Phase.FADE_OUT)

		Phase.FADE_OUT:
			var fade_progress: float = clampf(phase_timer / maxf(fade_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				beam_visual.scale.y = lerpf(1.0, 0.0, fade_progress)
				beam_visual.color = Color(0.75, 0.75, 0.75, lerpf(0.8, 0.0, fade_progress))
			if phase_timer >= fade_duration:
				_despawn()


func _simulate_circle(_delta: float) -> void:
	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
			_update_circle_fill_visual(progress)
			if phase_timer >= telegraph_duration:
				_enter_phase(Phase.ACTIVE)

		Phase.ACTIVE:
			_check_player_overlap()
			if phase_timer >= active_duration:
				_enter_phase(Phase.FADE_OUT)

		Phase.FADE_OUT:
			var fade_progress: float = clampf(phase_timer / maxf(fade_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				var s: float = lerpf(1.0, 0.0, fade_progress)
				beam_visual.scale = Vector2(s, s)
				beam_visual.color = Color(0.75, 0.75, 0.75, lerpf(0.8, 0.0, fade_progress))
			if phase_timer >= fade_duration:
				_despawn()


func _simulate_projectile(delta: float) -> void:
	global_position += projectile_velocity * delta
	_check_player_overlap()
	if not is_hazard_active:
		return
	if _is_outside_viewport():
		is_hazard_active = false
		if collision_shape != null:
			collision_shape.disabled = true
		_despawn()


func _simulate_exploder(_delta: float) -> void:
	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				var pulse: float = 0.35 + 0.35 * (0.5 + 0.5 * sin(phase_timer * 18.0))
				beam_visual.color = Color(pulse, pulse, pulse, 0.75)
				var s: float = lerpf(0.85, 1.15, 0.5 + 0.5 * sin(phase_timer * 18.0))
				beam_visual.scale = Vector2(s, s)
			if center_line != null:
				var core_scale: float = lerpf(0.25, 1.0, progress)
				center_line.scale = Vector2(core_scale, core_scale)
				center_line.color = Color(0.9, 0.9, 0.9, lerpf(0.4, 0.95, progress))
			if phase_timer >= telegraph_duration:
				_detonate_exploder()

		Phase.FADE_OUT:
			_despawn()


func _simulate_closing_walls(_delta: float) -> void:
	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
			var telegraph_extension: float = lerpf(0.18, 0.42, progress)
			_update_closing_walls_geometry(telegraph_extension)
			var gray: float = lerpf(0.30, 0.58, progress)
			var col: Color = Color(gray, gray, gray, lerpf(0.45, 0.78, progress))
			if beam_visual != null:
				beam_visual.color = col
			if secondary_visual != null:
				secondary_visual.color = col
			if phase_timer >= telegraph_duration:
				_enter_phase(Phase.ACTIVE)

		Phase.ACTIVE:
			_check_player_overlap()
			if phase_timer >= active_duration:
				_enter_phase(Phase.FADE_OUT)

		Phase.FADE_OUT:
			var fade_progress: float = clampf(phase_timer / maxf(fade_duration, 0.001), 0.0, 1.0)
			var retract_extension: float = lerpf(1.0, 0.0, fade_progress)
			_update_closing_walls_geometry(retract_extension)
			var fade_col: Color = Color(0.75, 0.75, 0.75, lerpf(0.85, 0.0, fade_progress))
			if beam_visual != null:
				beam_visual.color = fade_col
			if secondary_visual != null:
				secondary_visual.color = fade_col
			if phase_timer >= fade_duration:
				_despawn()


func _simulate_saw(delta: float) -> void:
	match current_phase:
		Phase.TELEGRAPH:
			rotation += saw_spin_speed * 0.45 * delta
			var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				var gray: float = lerpf(0.32, 0.68, progress)
				beam_visual.color = Color(gray, gray, gray, lerpf(0.5, 0.85, progress))
				var s: float = lerpf(0.78, 1.0, progress)
				beam_visual.scale = Vector2(s, s)
			if phase_timer >= telegraph_duration:
				_enter_phase(Phase.ACTIVE)

		Phase.ACTIVE:
			rotation += saw_spin_speed * delta
			global_position += saw_velocity * delta
			var arena: Vector2 = _get_arena_size()
			if saw_bounces_remaining > 0:
				var bounced: bool = false
				if global_position.x <= saw_radius and saw_velocity.x < 0.0:
					global_position.x = saw_radius
					saw_velocity.x = -saw_velocity.x
					bounced = true
				elif global_position.x >= arena.x - saw_radius and saw_velocity.x > 0.0:
					global_position.x = arena.x - saw_radius
					saw_velocity.x = -saw_velocity.x
					bounced = true
				if global_position.y <= saw_radius and saw_velocity.y < 0.0:
					global_position.y = saw_radius
					saw_velocity.y = -saw_velocity.y
					bounced = true
				elif global_position.y >= arena.y - saw_radius and saw_velocity.y > 0.0:
					global_position.y = arena.y - saw_radius
					saw_velocity.y = -saw_velocity.y
					bounced = true
				if bounced:
					saw_bounces_remaining -= 1
			_check_player_overlap()
			if phase_timer >= active_duration or (saw_bounces_remaining <= 0 and _is_outside_viewport()):
				_enter_phase(Phase.FADE_OUT)

		Phase.FADE_OUT:
			rotation += saw_spin_speed * 0.5 * delta
			var fade_progress: float = clampf(phase_timer / maxf(fade_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				var s: float = lerpf(1.0, 0.0, fade_progress)
				beam_visual.scale = Vector2(s, s)
				beam_visual.color = Color(0.75, 0.75, 0.75, lerpf(0.85, 0.0, fade_progress))
			if phase_timer >= fade_duration:
				_despawn()


func _simulate_chaser(delta: float) -> void:
	match current_phase:
		Phase.TELEGRAPH:
			var to_player: Vector2 = _get_target_player_position() - global_position
			if to_player.length_squared() > 0.0001:
				var dir: Vector2 = to_player.normalized()
				chaser_velocity = dir * chaser_speed
				rotation = dir.angle()
			var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				var gray: float = lerpf(0.34, 0.72, progress)
				beam_visual.color = Color(gray, gray, gray, lerpf(0.5, 0.88, progress))
			if phase_timer >= telegraph_duration:
				_enter_phase(Phase.ACTIVE)

		Phase.ACTIVE:
			var to_player: Vector2 = _get_target_player_position() - global_position
			if to_player.length_squared() > 0.0001:
				var desired_dir: Vector2 = to_player.normalized()
				var current_dir: Vector2 = chaser_velocity.normalized() if chaser_velocity.length_squared() > 0.0001 else desired_dir
				var steer_weight: float = clampf(chaser_turn_rate * delta, 0.0, 1.0)
				var new_dir: Vector2 = current_dir.lerp(desired_dir, steer_weight).normalized()
				if new_dir.length_squared() <= 0.0001:
					new_dir = desired_dir
				chaser_velocity = new_dir * chaser_speed
				rotation = new_dir.angle()
			global_position += chaser_velocity * delta
			_check_player_overlap()
			if phase_timer >= active_duration:
				_enter_phase(Phase.FADE_OUT)

		Phase.FADE_OUT:
			var fade_progress: float = clampf(phase_timer / maxf(fade_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				var s: float = lerpf(1.0, 0.0, fade_progress)
				beam_visual.scale = Vector2(s, s)
				beam_visual.color = Color(0.75, 0.75, 0.75, lerpf(0.85, 0.0, fade_progress))
			if phase_timer >= fade_duration:
				_despawn()


func _simulate_charger(delta: float) -> void:
	match current_phase:
		Phase.TELEGRAPH:
			var to_player: Vector2 = _get_target_player_position() - global_position
			if to_player.length_squared() > 0.0001:
				charger_direction = to_player.normalized()
				rotation = charger_direction.angle()
			var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				var gray: float = lerpf(0.35, 0.78, progress)
				beam_visual.color = Color(gray, gray, gray, lerpf(0.55, 0.90, progress))
			if center_line != null:
				center_line.visible = true
				var line_gray: float = lerpf(0.45, 0.88, progress)
				center_line.color = Color(line_gray, line_gray, line_gray, lerpf(0.35, 0.85, progress))
			if phase_timer >= telegraph_duration:
				_enter_phase(Phase.ACTIVE)

		Phase.ACTIVE:
			global_position += charger_direction * charger_speed * delta
			_check_player_overlap()
			if phase_timer >= active_duration or _is_outside_viewport():
				_enter_phase(Phase.FADE_OUT)

		Phase.FADE_OUT:
			var fade_progress: float = clampf(phase_timer / maxf(fade_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				var s: float = lerpf(1.0, 0.0, fade_progress)
				beam_visual.scale = Vector2(s, s)
				beam_visual.color = Color(0.75, 0.75, 0.75, lerpf(0.85, 0.0, fade_progress))
			if phase_timer >= fade_duration:
				_despawn()


func _simulate_turret(_delta: float) -> void:
	match current_phase:
		Phase.TELEGRAPH:
			var to_player: Vector2 = _get_target_player_position() - global_position
			if to_player.length_squared() > 0.0001:
				turret_aim_direction = to_player.normalized()
				rotation = turret_aim_direction.angle()
			var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				var gray: float = lerpf(0.36, 0.78, progress)
				beam_visual.color = Color(gray, gray, gray, lerpf(0.55, 0.90, progress))
			if center_line != null:
				center_line.visible = true
				var line_gray: float = lerpf(0.48, 0.92, progress)
				center_line.color = Color(line_gray, line_gray, line_gray, lerpf(0.35, 0.90, progress))
				center_line.scale.y = lerpf(1.4, 0.65, progress)
			if phase_timer >= telegraph_duration:
				_enter_phase(Phase.ACTIVE)

		Phase.ACTIVE:
			_check_player_overlap()
			if phase_timer >= active_duration:
				_enter_phase(Phase.FADE_OUT)

		Phase.FADE_OUT:
			var fade_progress: float = clampf(phase_timer / maxf(fade_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				var s: float = lerpf(1.0, 0.0, fade_progress)
				beam_visual.scale = Vector2(s, s)
				beam_visual.color = Color(0.75, 0.75, 0.75, lerpf(0.85, 0.0, fade_progress))
			if phase_timer >= fade_duration:
				_despawn()


func _get_packed_self_scene() -> PackedScene:
	if _self_packed_scene == null:
		_self_packed_scene = load("res://scenes/light_beam.tscn") as PackedScene
	return _self_packed_scene


func _detonate_exploder() -> void:
	if has_detonated:
		return
	has_detonated = true
	is_hazard_active = false
	if collision_shape != null:
		collision_shape.disabled = true

	var parent_node: Node = get_parent()
	if parent_node != null:
		var packed: PackedScene = _get_packed_self_scene()
		if packed != null:
			for i: int in range(exploder_burst_count):
				var angle: float = (TAU * float(i)) / float(exploder_burst_count)
				var dir: Vector2 = Vector2.from_angle(angle)
				var proj: Area2D = packed.instantiate() as Area2D
				if proj != null:
					proj.set("target_player", target_player)
					parent_node.add_child(proj)
					proj.call("configure_projectile", global_position, dir, exploder_projectile_speed, DEFAULT_PROJECTILE_RADIUS)

	_play_hazard_sfx(&"explosion", _get_explosion_sfx_stream(), true)
	_enter_phase(Phase.FADE_OUT)
	_despawn()


func _fire_turret_burst() -> void:
	if has_fired:
		return
	has_fired = true
	var parent_node: Node = get_parent()
	if parent_node == null:
		return
	var packed: PackedScene = _get_packed_self_scene()
	if packed == null:
		return

	var base_angle: float = turret_aim_direction.angle()
	var spread_step: float = 0.14
	for i: int in range(turret_burst_count):
		var offset_idx: float = float(i) - float(turret_burst_count - 1) * 0.5
		var shot_angle: float = base_angle + offset_idx * spread_step
		var shot_dir: Vector2 = Vector2.from_angle(shot_angle)
		var proj: Area2D = packed.instantiate() as Area2D
		if proj != null:
			proj.set("target_player", target_player)
			parent_node.add_child(proj)
			proj.call("configure_projectile", global_position + shot_dir * (turret_radius + 4.0), shot_dir, turret_projectile_speed, DEFAULT_PROJECTILE_RADIUS)


func _enter_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_timer = 0.0

	match hazard_type:
		HazardType.BEAM:
			_enter_beam_phase(new_phase)
		HazardType.CIRCLE:
			_enter_circle_phase(new_phase)
		HazardType.PROJECTILE:
			_enter_projectile_phase(new_phase)
		HazardType.EXPLODER:
			_enter_exploder_phase(new_phase)
		HazardType.CLOSING_WALLS:
			_enter_closing_walls_phase(new_phase)
		HazardType.SAW:
			_enter_saw_phase(new_phase)
		HazardType.CHASER:
			_enter_chaser_phase(new_phase)
		HazardType.CHARGER:
			_enter_charger_phase(new_phase)
		HazardType.TURRET:
			_enter_turret_phase(new_phase)


func _enter_beam_phase(new_phase: Phase) -> void:
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = TELEGRAPH_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = true
				center_line.scale = Vector2.ONE
				center_line.color = TELEGRAPH_LINE_COLOR

		Phase.ACTIVE:
			is_hazard_active = true
			if collision_shape != null:
				collision_shape.disabled = false
			if beam_visual != null:
				beam_visual.color = ACTIVE_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = false
			_play_hazard_sfx(&"laser", _get_laser_sfx_stream(), false)
			_check_player_overlap()

		Phase.FADE_OUT:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = FADE_COLOR
			if center_line != null:
				center_line.visible = false


func _enter_circle_phase(new_phase: Phase) -> void:
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = CIRCLE_SHADOW_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = true
				center_line.scale = Vector2.ONE
				center_line.color = CIRCLE_FILL_COLOR
			_update_circle_fill_visual(0.0)

		Phase.ACTIVE:
			is_hazard_active = true
			if collision_shape != null:
				collision_shape.disabled = false
			if beam_visual != null:
				beam_visual.color = ACTIVE_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = false
			_play_hazard_sfx(&"laser", _get_laser_sfx_stream(), false)
			_check_player_overlap()

		Phase.FADE_OUT:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = FADE_COLOR
			if center_line != null:
				center_line.visible = false


func _enter_projectile_phase(_new_phase: Phase) -> void:
	current_phase = Phase.ACTIVE
	is_hazard_active = true
	if collision_shape != null:
		collision_shape.disabled = false
	if beam_visual != null:
		beam_visual.color = ACTIVE_COLOR
		beam_visual.scale = Vector2.ONE
	if center_line != null:
		center_line.visible = false
	_check_player_overlap()


func _enter_exploder_phase(new_phase: Phase) -> void:
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = TELEGRAPH_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = true
				center_line.scale = Vector2(0.25, 0.25)
				center_line.color = CIRCLE_FILL_COLOR

		Phase.ACTIVE, Phase.FADE_OUT:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if center_line != null:
				center_line.visible = false


func _enter_closing_walls_phase(new_phase: Phase) -> void:
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if secondary_collision != null:
				secondary_collision.disabled = true
			if beam_visual != null:
				beam_visual.color = TELEGRAPH_COLOR
				beam_visual.scale = Vector2.ONE
			if secondary_visual != null:
				secondary_visual.visible = true
				secondary_visual.color = TELEGRAPH_COLOR
				secondary_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = true
				center_line.scale = Vector2.ONE
				center_line.color = TELEGRAPH_LINE_COLOR
			_update_closing_walls_geometry(0.22)

		Phase.ACTIVE:
			is_hazard_active = true
			_update_closing_walls_geometry(1.0)
			if collision_shape != null:
				collision_shape.disabled = false
			if secondary_collision != null:
				secondary_collision.disabled = false
			if beam_visual != null:
				beam_visual.color = ACTIVE_COLOR
				beam_visual.scale = Vector2.ONE
			if secondary_visual != null:
				secondary_visual.visible = true
				secondary_visual.color = ACTIVE_COLOR
				secondary_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = false
			_play_hazard_sfx(&"laser", _get_laser_sfx_stream(), false)
			_check_player_overlap()

		Phase.FADE_OUT:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if secondary_collision != null:
				secondary_collision.disabled = true
			if beam_visual != null:
				beam_visual.color = FADE_COLOR
			if secondary_visual != null:
				secondary_visual.color = FADE_COLOR
			if center_line != null:
				center_line.visible = false


func _enter_saw_phase(new_phase: Phase) -> void:
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = TELEGRAPH_COLOR
				beam_visual.scale = Vector2(0.82, 0.82)
			if center_line != null:
				center_line.visible = true
				center_line.scale = Vector2(0.32, 0.32)
				center_line.color = TELEGRAPH_LINE_COLOR

		Phase.ACTIVE:
			is_hazard_active = true
			if collision_shape != null:
				collision_shape.disabled = false
			if beam_visual != null:
				beam_visual.color = ACTIVE_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = true
				center_line.scale = Vector2(0.28, 0.28)
				center_line.color = Color(0.18, 0.18, 0.18, 1.0)
			_play_hazard_sfx(&"laser", _get_laser_sfx_stream(), false)
			_check_player_overlap()

		Phase.FADE_OUT:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = FADE_COLOR
			if center_line != null:
				center_line.visible = false


func _enter_chaser_phase(new_phase: Phase) -> void:
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = TELEGRAPH_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = true
				center_line.scale = Vector2(0.45, 0.45)
				center_line.color = TELEGRAPH_LINE_COLOR

		Phase.ACTIVE:
			is_hazard_active = true
			if collision_shape != null:
				collision_shape.disabled = false
			if beam_visual != null:
				beam_visual.color = ACTIVE_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = true
				center_line.scale = Vector2(0.38, 0.38)
				center_line.color = Color(0.22, 0.22, 0.22, 1.0)
			_play_hazard_sfx(&"laser", _get_laser_sfx_stream(), false)
			_check_player_overlap()

		Phase.FADE_OUT:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = FADE_COLOR
			if center_line != null:
				center_line.visible = false


func _enter_charger_phase(new_phase: Phase) -> void:
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = TELEGRAPH_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = true
				center_line.scale = Vector2.ONE
				center_line.color = TELEGRAPH_LINE_COLOR

		Phase.ACTIVE:
			is_hazard_active = true
			if collision_shape != null:
				collision_shape.disabled = false
			if beam_visual != null:
				beam_visual.color = ACTIVE_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = false
			_play_hazard_sfx(&"laser", _get_laser_sfx_stream(), false)
			_check_player_overlap()

		Phase.FADE_OUT:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = FADE_COLOR
			if center_line != null:
				center_line.visible = false


func _enter_turret_phase(new_phase: Phase) -> void:
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = TELEGRAPH_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = true
				center_line.scale = Vector2.ONE
				center_line.color = TELEGRAPH_LINE_COLOR

		Phase.ACTIVE:
			is_hazard_active = true
			if collision_shape != null:
				collision_shape.disabled = false
			if beam_visual != null:
				beam_visual.color = ACTIVE_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = false
			_play_hazard_sfx(&"laser", _get_laser_sfx_stream(), false)
			_fire_turret_burst()
			_check_player_overlap()

		Phase.FADE_OUT:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = FADE_COLOR
			if center_line != null:
				center_line.visible = false


func _rebuild_geometry() -> void:
	_ensure_static_polygons()
	match hazard_type:
		HazardType.BEAM:
			_rebuild_beam_geometry()
		HazardType.CIRCLE:
			_rebuild_circle_geometry()
		HazardType.PROJECTILE:
			_rebuild_projectile_geometry()
		HazardType.EXPLODER:
			_rebuild_exploder_geometry()
		HazardType.CLOSING_WALLS:
			_rebuild_closing_walls_geometry()
		HazardType.SAW:
			_rebuild_saw_geometry()
		HazardType.CHASER:
			_rebuild_chaser_geometry()
		HazardType.CHARGER:
			_rebuild_charger_geometry()
		HazardType.TURRET:
			_rebuild_turret_geometry()


func _rebuild_beam_geometry() -> void:
	var half_len: float = beam_length * 0.5
	var half_width: float = beam_width * 0.5

	if beam_visual != null:
		beam_visual.polygon = PackedVector2Array([
			Vector2(-half_len, -half_width),
			Vector2(half_len, -half_width),
			Vector2(half_len, half_width),
			Vector2(-half_len, half_width),
		])

	if center_line != null:
		center_line.polygon = PackedVector2Array([
			Vector2(-half_len, -1.5),
			Vector2(half_len, -1.5),
			Vector2(half_len, 1.5),
			Vector2(-half_len, 1.5),
		])

	if collision_shape != null:
		var rect_shape: RectangleShape2D = collision_shape.shape as RectangleShape2D
		if rect_shape == null:
			rect_shape = RectangleShape2D.new()
			collision_shape.shape = rect_shape
		rect_shape.size = Vector2(beam_length, beam_width)


func _rebuild_circle_geometry() -> void:
	var full_circle: PackedVector2Array = _default_circle_polygon if is_equal_approx(circle_radius, DEFAULT_CIRCLE_RADIUS) else _scale_polygon(_unit_circle_polygon, circle_radius)
	if beam_visual != null:
		beam_visual.polygon = full_circle
	if center_line != null:
		center_line.polygon = full_circle if circle_fill_mode == CircleFillMode.CENTER_OUT else PackedVector2Array()
	if collision_shape != null:
		var circle_shape: CircleShape2D = collision_shape.shape as CircleShape2D
		if circle_shape == null:
			circle_shape = CircleShape2D.new()
			collision_shape.shape = circle_shape
		circle_shape.radius = circle_radius


func _rebuild_projectile_geometry() -> void:
	var poly: PackedVector2Array = _default_projectile_polygon if is_equal_approx(projectile_radius, DEFAULT_PROJECTILE_RADIUS) else _scale_polygon(_unit_projectile_polygon, projectile_radius)
	if beam_visual != null:
		beam_visual.polygon = poly
	if center_line != null:
		center_line.polygon = PackedVector2Array()
	if collision_shape != null:
		var circle_shape: CircleShape2D = collision_shape.shape as CircleShape2D
		if circle_shape == null:
			circle_shape = CircleShape2D.new()
			collision_shape.shape = circle_shape
		circle_shape.radius = projectile_radius


func _rebuild_exploder_geometry() -> void:
	var oct_poly: PackedVector2Array = _default_exploder_polygon if is_equal_approx(exploder_radius, DEFAULT_EXPLODER_RADIUS) else _scale_polygon(_unit_octagon_polygon, exploder_radius)
	if beam_visual != null:
		beam_visual.polygon = oct_poly
	if center_line != null:
		center_line.polygon = oct_poly
	if collision_shape != null:
		var circle_shape: CircleShape2D = collision_shape.shape as CircleShape2D
		if circle_shape == null:
			circle_shape = CircleShape2D.new()
			collision_shape.shape = circle_shape
		circle_shape.radius = exploder_radius


func _rebuild_closing_walls_geometry() -> void:
	_update_closing_walls_geometry(1.0)


func _update_closing_walls_geometry(extension_ratio: float) -> void:
	var arena: Vector2 = _get_arena_size()
	var ratio: float = clampf(extension_ratio, 0.02, 1.0)
	var half_gap: float = wall_gap_size * 0.5

	if wall_axis == 0:
		var full_top_h: float = maxf(0.0, wall_gap_center - half_gap)
		var full_bot_h: float = maxf(0.0, arena.y - (wall_gap_center + half_gap))
		var cur_top_h: float = full_top_h * ratio
		var cur_bot_h: float = full_bot_h * ratio
		wall_a_rect = Rect2(Vector2(0.0, 0.0), Vector2(arena.x, cur_top_h))
		wall_b_rect = Rect2(Vector2(0.0, arena.y - cur_bot_h), Vector2(arena.x, cur_bot_h))
		safe_corridor_rect = Rect2(Vector2(0.0, wall_gap_center - half_gap), Vector2(arena.x, wall_gap_size))
		if center_line != null:
			var y_line: float = wall_gap_center - half_gap - global_position.y
			center_line.polygon = PackedVector2Array([
				Vector2(-global_position.x, y_line - 1.5),
				Vector2(arena.x - global_position.x, y_line - 1.5),
				Vector2(arena.x - global_position.x, y_line + 1.5),
				Vector2(-global_position.x, y_line + 1.5),
			])
	else:
		var full_left_w: float = maxf(0.0, wall_gap_center - half_gap)
		var full_right_w: float = maxf(0.0, arena.x - (wall_gap_center + half_gap))
		var cur_left_w: float = full_left_w * ratio
		var cur_right_w: float = full_right_w * ratio
		wall_a_rect = Rect2(Vector2(0.0, 0.0), Vector2(cur_left_w, arena.y))
		wall_b_rect = Rect2(Vector2(arena.x - cur_right_w, 0.0), Vector2(cur_right_w, arena.y))
		safe_corridor_rect = Rect2(Vector2(wall_gap_center - half_gap, 0.0), Vector2(wall_gap_size, arena.y))
		if center_line != null:
			var x_line: float = wall_gap_center - half_gap - global_position.x
			center_line.polygon = PackedVector2Array([
				Vector2(x_line - 1.5, -global_position.y),
				Vector2(x_line + 1.5, -global_position.y),
				Vector2(x_line + 1.5, arena.y - global_position.y),
				Vector2(x_line - 1.5, arena.y - global_position.y),
			])

	_set_rect_to_polygon(_wall_a_verts, wall_a_rect, global_position)
	_set_rect_to_polygon(_wall_b_verts, wall_b_rect, global_position)
	if beam_visual != null:
		beam_visual.polygon = _wall_a_verts
	if secondary_visual != null:
		secondary_visual.polygon = _wall_b_verts

	if collision_shape != null:
		var shape_a: RectangleShape2D = collision_shape.shape as RectangleShape2D
		if shape_a == null:
			shape_a = RectangleShape2D.new()
			collision_shape.shape = shape_a
		shape_a.size = Vector2(maxf(wall_a_rect.size.x, 1.0), maxf(wall_a_rect.size.y, 1.0))
		collision_shape.position = wall_a_rect.get_center() - global_position

	if secondary_collision != null:
		var shape_b: RectangleShape2D = secondary_collision.shape as RectangleShape2D
		if shape_b == null:
			shape_b = RectangleShape2D.new()
			secondary_collision.shape = shape_b
		shape_b.size = Vector2(maxf(wall_b_rect.size.x, 1.0), maxf(wall_b_rect.size.y, 1.0))
		secondary_collision.position = wall_b_rect.get_center() - global_position


static func _set_rect_to_polygon(buf: PackedVector2Array, rect: Rect2, origin: Vector2) -> void:
	buf.resize(4)
	var p0: Vector2 = rect.position - origin
	var p1: Vector2 = rect.end - origin
	buf[0] = Vector2(p0.x, p0.y)
	buf[1] = Vector2(p1.x, p0.y)
	buf[2] = Vector2(p1.x, p1.y)
	buf[3] = Vector2(p0.x, p1.y)


## Returns true if the given arena-space point lies strictly inside the safe corridor gap.
func is_point_in_safe_corridor(arena_point: Vector2) -> bool:
	return safe_corridor_rect.has_point(arena_point)


func _rebuild_saw_geometry() -> void:
	var poly: PackedVector2Array = _default_saw_polygon if is_equal_approx(saw_radius, DEFAULT_SAW_RADIUS) else _scale_polygon(_unit_saw_polygon, saw_radius)
	if beam_visual != null:
		beam_visual.polygon = poly
	if center_line != null:
		center_line.polygon = _default_exploder_polygon
	if collision_shape != null:
		var circle_shape: CircleShape2D = collision_shape.shape as CircleShape2D
		if circle_shape == null:
			circle_shape = CircleShape2D.new()
			collision_shape.shape = circle_shape
		circle_shape.radius = saw_radius


func _rebuild_chaser_geometry() -> void:
	var poly: PackedVector2Array = _default_chaser_polygon if is_equal_approx(chaser_radius, DEFAULT_CHASER_RADIUS) else _scale_polygon(_unit_chaser_polygon, chaser_radius)
	if beam_visual != null:
		beam_visual.polygon = poly
	if center_line != null:
		center_line.polygon = _default_projectile_polygon
	if collision_shape != null:
		var circle_shape: CircleShape2D = collision_shape.shape as CircleShape2D
		if circle_shape == null:
			circle_shape = CircleShape2D.new()
			collision_shape.shape = circle_shape
		circle_shape.radius = chaser_radius


func _rebuild_charger_geometry() -> void:
	var poly: PackedVector2Array = _default_charger_polygon if is_equal_approx(charger_radius, DEFAULT_CHARGER_RADIUS) else _scale_polygon(_unit_charger_polygon, charger_radius)
	if beam_visual != null:
		beam_visual.polygon = poly
	if center_line != null:
		center_line.polygon = PackedVector2Array([
			Vector2(charger_radius * 0.8, -1.5),
			Vector2(900.0, -1.5),
			Vector2(900.0, 1.5),
			Vector2(charger_radius * 0.8, 1.5),
		])
	if collision_shape != null:
		var circle_shape: CircleShape2D = collision_shape.shape as CircleShape2D
		if circle_shape == null:
			circle_shape = CircleShape2D.new()
			collision_shape.shape = circle_shape
		circle_shape.radius = charger_radius


func _rebuild_turret_geometry() -> void:
	var poly: PackedVector2Array = _default_turret_polygon if is_equal_approx(turret_radius, DEFAULT_TURRET_RADIUS) else _scale_polygon(_unit_turret_polygon, turret_radius)
	if beam_visual != null:
		beam_visual.polygon = poly
	if center_line != null:
		center_line.polygon = PackedVector2Array([
			Vector2(turret_radius, -1.5),
			Vector2(1100.0, -1.5),
			Vector2(1100.0, 1.5),
			Vector2(turret_radius, 1.5),
		])
	if collision_shape != null:
		var circle_shape: CircleShape2D = collision_shape.shape as CircleShape2D
		if circle_shape == null:
			circle_shape = CircleShape2D.new()
			collision_shape.shape = circle_shape
		circle_shape.radius = turret_radius


func _update_circle_fill_visual(progress: float) -> void:
	if center_line == null:
		return
	var clamped: float = clampf(progress, 0.0, 1.0)
	match circle_fill_mode:
		CircleFillMode.CENTER_OUT:
			if center_line.polygon.size() < 3 and beam_visual != null:
				center_line.polygon = beam_visual.polygon
			var s: float = maxf(clamped, 0.02)
			center_line.scale = Vector2(s, s)

		CircleFillMode.OUTSIDE_IN:
			center_line.scale = Vector2.ONE
			var inner_r: float = circle_radius * (1.0 - clamped)
			center_line.polygon = _build_annulus_polygon(inner_r, circle_radius, CIRCLE_SEGMENTS)

		CircleFillMode.ANGULAR_SWEEP:
			center_line.scale = Vector2.ONE
			var sweep_angle: float = TAU * clamped
			center_line.polygon = _build_sector_polygon(circle_radius, sweep_angle, CIRCLE_SEGMENTS)


func _build_circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	if segments == CIRCLE_SEGMENTS:
		_ensure_static_polygons()
		if is_equal_approx(radius, DEFAULT_CIRCLE_RADIUS):
			return _default_circle_polygon
		return _scale_polygon(_unit_circle_polygon, radius)
	return _create_regular_polygon(radius, segments)


func _build_annulus_polygon(inner_radius: float, outer_radius: float, segments: int) -> PackedVector2Array:
	if inner_radius <= 0.5:
		return _build_circle_polygon(outer_radius, segments)
	var count: int = maxi(segments, 6)
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize((count + 1) * 2)
	for i: int in range(count + 1):
		var angle: float = (TAU * float(i)) / float(count)
		var unit_v: Vector2 = Vector2.from_angle(angle)
		pts[i] = unit_v * outer_radius
		pts[(count + 1) * 2 - 1 - i] = unit_v * inner_radius
	return pts


func _build_sector_polygon(radius: float, sweep_angle: float, segments: int) -> PackedVector2Array:
	if sweep_angle <= 0.02:
		return PackedVector2Array([
			Vector2.ZERO,
			Vector2(radius, 0.0),
			Vector2.from_angle(0.02) * radius,
		])
	if sweep_angle >= TAU - 0.001:
		return _build_circle_polygon(radius, segments)
	var count: int = maxi(int(ceil(float(segments) * (sweep_angle / TAU))), 2)
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(count + 2)
	pts[0] = Vector2.ZERO
	for i: int in range(count + 1):
		var angle: float = -PI * 0.5 + (sweep_angle * float(i)) / float(count)
		pts[i + 1] = Vector2.from_angle(angle) * radius
	return pts


func _get_arena_size() -> Vector2:
	if is_inside_tree():
		var rect_size: Vector2 = get_viewport_rect().size
		if rect_size.x > 0.0 and rect_size.y > 0.0:
			return rect_size
	return Vector2(1152.0, 648.0)


func _is_outside_viewport() -> bool:
	var arena: Vector2 = _get_arena_size()
	return (
		global_position.x < -VIEWPORT_DESPAWN_MARGIN
		or global_position.x > arena.x + VIEWPORT_DESPAWN_MARGIN
		or global_position.y < -VIEWPORT_DESPAWN_MARGIN
		or global_position.y > arena.y + VIEWPORT_DESPAWN_MARGIN
	)


func _despawn() -> void:
	if is_inside_tree() and not Engine.is_editor_hint():
		queue_free()
	else:
		var p: Node = get_parent()
		if p != null:
			p.remove_child(self)
		queue_free()


func _resolve_player_node() -> Node2D:
	if target_player != null and is_instance_valid(target_player):
		return target_player
	var p: Node = get_parent()
	if p != null:
		var direct_player: Node2D = p.get_node_or_null("Player") as Node2D
		if direct_player != null:
			target_player = direct_player
			return target_player
		var gp: Node = p.get_parent()
		if gp != null:
			var level_player: Node2D = gp.get_node_or_null("Player") as Node2D
			if level_player != null:
				target_player = level_player
				return target_player
		for sibling: Node in p.get_children():
			if sibling != self and sibling is Node2D and (sibling.is_in_group("player") or sibling.has_method("take_damage")):
				target_player = sibling as Node2D
				return target_player
	if is_inside_tree() and get_tree() != null:
		var group_nodes: Array[Node] = get_tree().get_nodes_in_group("player")
		if not group_nodes.is_empty() and group_nodes[0] is Node2D:
			target_player = group_nodes[0] as Node2D
			return target_player
	return null


func _get_target_player_position() -> Vector2:
	if use_target_position_override:
		return target_position_override
	var p_node: Node2D = _resolve_player_node()
	if p_node != null:
		return p_node.global_position
	return _get_arena_size() * 0.5


func _is_overlapping_point(pt: Vector2, body_radius: float = PLAYER_COLLISION_RADIUS) -> bool:
	match hazard_type:
		HazardType.BEAM:
			var local_pt: Vector2 = (pt - global_position).rotated(-rotation)
			return absf(local_pt.x) <= (beam_length * 0.5 + body_radius) and absf(local_pt.y) <= (beam_width * 0.5 + body_radius)
		HazardType.CIRCLE:
			return global_position.distance_to(pt) <= (circle_radius + body_radius)
		HazardType.PROJECTILE:
			return global_position.distance_to(pt) <= (projectile_radius + body_radius)
		HazardType.EXPLODER:
			return global_position.distance_to(pt) <= (exploder_radius + body_radius)
		HazardType.CLOSING_WALLS:
			return wall_a_rect.grow(body_radius).has_point(pt) or wall_b_rect.grow(body_radius).has_point(pt)
		HazardType.SAW:
			return global_position.distance_to(pt) <= (saw_radius + body_radius)
		HazardType.CHASER:
			return global_position.distance_to(pt) <= (chaser_radius + body_radius)
		HazardType.CHARGER:
			return global_position.distance_to(pt) <= (charger_radius + body_radius)
		HazardType.TURRET:
			return global_position.distance_to(pt) <= (turret_radius + body_radius)
	return false


func _handle_player_contact(body: Node2D) -> void:
	if not is_hazard_active or body == null or not is_instance_valid(body):
		return
	var active_val: Variant = body.get("is_active")
	if active_val != null and not bool(active_val):
		return
	var shield_up: bool = bool(body.get("is_shield_active")) or bool(body.get("is_dashing"))
	if shield_up:
		if hazard_type == HazardType.PROJECTILE:
			if body.has_method("on_shield_block"):
				body.call("on_shield_block", global_position)
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			_despawn()
		return
	if body.has_method("take_damage"):
		body.call("take_damage", 1)


func _check_player_overlap() -> void:
	if not is_hazard_active:
		return
	if is_inside_tree() and not Engine.is_editor_hint():
		for body: Node2D in get_overlapping_bodies():
			if body.is_in_group("player") or body.has_method("take_damage"):
				if hazard_type != HazardType.CLOSING_WALLS or _is_overlapping_point(body.global_position):
					_handle_player_contact(body)
					if not is_hazard_active:
						return

	var p_node: Node2D = _resolve_player_node()
	if p_node != null and _is_overlapping_point(p_node.global_position):
		_handle_player_contact(p_node)


func _on_body_entered(body: Node2D) -> void:
	if is_hazard_active and (body.is_in_group("player") or body.has_method("take_damage")):
		if hazard_type != HazardType.CLOSING_WALLS or _is_overlapping_point(body.global_position):
			_handle_player_contact(body)


func _play_hazard_sfx(sfx_name: StringName, stream: AudioStreamWAV, persist_on_despawn: bool) -> void:
	_resolve_nodes()
	sfx_play_count += 1
	last_sfx_played = sfx_name
	if sfx_player != null:
		sfx_player.stream = stream
	var parent_node: Node = get_parent()
	var level_node: Node = parent_node.get_parent() if parent_node != null else null
	if persist_on_despawn and level_node != null and level_node.has_method("play_hazard_sfx"):
		level_node.call("play_hazard_sfx", sfx_name, stream)
		return
	if is_inside_tree() and not Engine.is_editor_hint() and sfx_player != null:
		sfx_player.play()


static func _get_laser_sfx_stream() -> AudioStreamWAV:
	if _laser_sfx_stream != null:
		return _laser_sfx_stream
	var sample_count: int = int(AUDIO_MIX_RATE * 0.16)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(1080.0, 240.0, pow(progress, 0.65))
		phase += TAU * freq / float(AUDIO_MIX_RATE)
		var wave: float = 0.65 * sin(phase) + 0.35 * sin(phase * 2.0)
		var env: float = minf(progress * 18.0, 1.0) * pow(1.0 - progress, 1.35)
		var sample: float = clampf(wave * env * 0.42, -1.0, 1.0)
		data.encode_s16(i * 2, clampi(int(round(sample * 32767.0)), -32768, 32767))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = AUDIO_MIX_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = data
	_laser_sfx_stream = wav
	return _laser_sfx_stream


static func _get_explosion_sfx_stream() -> AudioStreamWAV:
	if _explosion_sfx_stream != null:
		return _explosion_sfx_stream
	var sample_count: int = int(AUDIO_MIX_RATE * 0.28)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(165.0, 38.0, pow(progress, 0.55))
		phase += TAU * freq / float(AUDIO_MIX_RATE)
		var sub_bass: float = sin(phase) + 0.4 * signf(sin(phase * 0.5))
		var rumble: float = sin(float(i * 97 + 19) * 0.37) * cos(float(i * 53 + 7) * 0.23)
		var env: float = pow(1.0 - progress, 1.45)
		var sample: float = clampf((sub_bass * 0.6 + rumble * 0.4) * env * 0.55, -1.0, 1.0)
		data.encode_s16(i * 2, clampi(int(round(sample * 32767.0)), -32768, 32767))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = AUDIO_MIX_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = data
	_explosion_sfx_stream = wav
	return _explosion_sfx_stream
