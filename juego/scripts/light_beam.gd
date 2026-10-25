@tool
extends Area2D
## Unified monochrome primitive 2D hazard entity.
## Consolidates four hazard behaviors into a single scene/script:
## 0. BEAM: Edge-to-edge rectangular light beam (telegraph -> solid white active -> fade out).
## 1. CIRCLE: Multi-pattern filling circle (center-out, outside-in, or angular sweep fill -> active burst -> fade out).
## 2. PROJECTILE: Un-telegraphed solid-white projectile with immediate active collision, despawning outside viewport.
## 3. EXPLODER: Stationary pulsing arena telegraph that detonates into a radial burst of active projectiles.

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
const CIRCLE_SEGMENTS: int = 32
const VIEWPORT_DESPAWN_MARGIN: float = 64.0

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

var current_phase: Phase = Phase.TELEGRAPH
var phase_timer: float = 0.0
var is_hazard_active: bool = false

@onready var beam_visual: Polygon2D = $BeamVisual
@onready var center_line: Polygon2D = $CenterLine
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_resolve_nodes()
	add_to_group("light_beams")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_rebuild_geometry()
	if hazard_type == HazardType.PROJECTILE:
		_enter_phase(Phase.ACTIVE)
	else:
		_enter_phase(Phase.TELEGRAPH)


func _resolve_nodes() -> void:
	if beam_visual == null:
		beam_visual = get_node_or_null("BeamVisual") as Polygon2D
	if center_line == null:
		center_line = get_node_or_null("CenterLine") as Polygon2D
	if collision_shape == null:
		collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D


## Configures the hazard as an edge-to-edge rectangular light beam (default backward-compatible contract).
func configure(
	spawn_pos: Vector2,
	angle_radians: float,
	width: float = DEFAULT_WIDTH,
	warning_time: float = 1.0,
	active_time: float = 0.35
) -> void:
	_resolve_nodes()
	hazard_type = HazardType.BEAM
	global_position = spawn_pos
	rotation = angle_radians
	beam_width = width
	telegraph_duration = warning_time
	active_duration = active_time
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
	hazard_type = HazardType.CIRCLE
	circle_radius = maxf(radius, 8.0)
	circle_fill_mode = clampi(fill_mode, 0, 2) as CircleFillMode
	global_position = spawn_pos
	rotation = 0.0
	telegraph_duration = warning_time
	active_duration = active_time
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
	hazard_type = HazardType.PROJECTILE
	global_position = spawn_pos
	var dir: Vector2 = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	projectile_velocity = dir * speed
	projectile_radius = maxf(radius, 4.0)
	rotation = dir.angle()
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
	hazard_type = HazardType.EXPLODER
	global_position = spawn_pos
	rotation = 0.0
	telegraph_duration = warning_time
	exploder_burst_count = maxi(burst_count, 3)
	exploder_projectile_speed = projectile_speed
	exploder_radius = maxf(radius, 8.0)
	has_detonated = false
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances the hazard lifecycle and movement by delta seconds.
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


func _detonate_exploder() -> void:
	if has_detonated:
		return
	has_detonated = true
	is_hazard_active = false
	if collision_shape != null:
		collision_shape.disabled = true

	var parent_node: Node = get_parent()
	if parent_node != null:
		var packed: PackedScene = load("res://scenes/light_beam.tscn") as PackedScene
		if packed != null:
			for i: int in range(exploder_burst_count):
				var angle: float = (TAU * float(i)) / float(exploder_burst_count)
				var dir: Vector2 = Vector2.from_angle(angle)
				var proj: Area2D = packed.instantiate() as Area2D
				if proj != null:
					parent_node.add_child(proj)
					proj.call("configure_projectile", global_position, dir, exploder_projectile_speed, DEFAULT_PROJECTILE_RADIUS)

	_enter_phase(Phase.FADE_OUT)
	_despawn()


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


func _rebuild_geometry() -> void:
	match hazard_type:
		HazardType.BEAM:
			_rebuild_beam_geometry()
		HazardType.CIRCLE:
			_rebuild_circle_geometry()
		HazardType.PROJECTILE:
			_rebuild_projectile_geometry()
		HazardType.EXPLODER:
			_rebuild_exploder_geometry()


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
		var rect_shape: RectangleShape2D = RectangleShape2D.new()
		rect_shape.size = Vector2(beam_length, beam_width)
		collision_shape.shape = rect_shape


func _rebuild_circle_geometry() -> void:
	var full_circle: PackedVector2Array = _build_circle_polygon(circle_radius, CIRCLE_SEGMENTS)
	if beam_visual != null:
		beam_visual.polygon = full_circle
	if center_line != null:
		center_line.polygon = PackedVector2Array()
	if collision_shape != null:
		var circle_shape: CircleShape2D = CircleShape2D.new()
		circle_shape.radius = circle_radius
		collision_shape.shape = circle_shape


func _rebuild_projectile_geometry() -> void:
	var poly: PackedVector2Array = _build_circle_polygon(projectile_radius, 12)
	if beam_visual != null:
		beam_visual.polygon = poly
	if center_line != null:
		center_line.polygon = PackedVector2Array()
	if collision_shape != null:
		var circle_shape: CircleShape2D = CircleShape2D.new()
		circle_shape.radius = projectile_radius
		collision_shape.shape = circle_shape


func _rebuild_exploder_geometry() -> void:
	var oct_poly: PackedVector2Array = _build_circle_polygon(exploder_radius, 8)
	if beam_visual != null:
		beam_visual.polygon = oct_poly
	if center_line != null:
		center_line.polygon = oct_poly
	if collision_shape != null:
		var circle_shape: CircleShape2D = CircleShape2D.new()
		circle_shape.radius = exploder_radius
		collision_shape.shape = circle_shape


func _update_circle_fill_visual(progress: float) -> void:
	if center_line == null:
		return
	var clamped: float = clampf(progress, 0.0, 1.0)
	match circle_fill_mode:
		CircleFillMode.CENTER_OUT:
			var r: float = maxf(circle_radius * clamped, 1.0)
			center_line.polygon = _build_circle_polygon(r, CIRCLE_SEGMENTS)

		CircleFillMode.OUTSIDE_IN:
			var inner_r: float = circle_radius * (1.0 - clamped)
			center_line.polygon = _build_annulus_polygon(inner_r, circle_radius, CIRCLE_SEGMENTS)

		CircleFillMode.ANGULAR_SWEEP:
			var sweep_angle: float = TAU * clamped
			center_line.polygon = _build_sector_polygon(circle_radius, sweep_angle, CIRCLE_SEGMENTS)


func _build_circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var count: int = maxi(segments, 3)
	pts.resize(count)
	for i: int in range(count):
		var angle: float = (TAU * float(i)) / float(count)
		pts[i] = Vector2.from_angle(angle) * radius
	return pts


func _build_annulus_polygon(inner_radius: float, outer_radius: float, segments: int) -> PackedVector2Array:
	if inner_radius <= 0.5:
		return _build_circle_polygon(outer_radius, segments)
	var count: int = maxi(segments, 6)
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(count + 1):
		var angle: float = (TAU * float(i)) / float(count)
		pts.append(Vector2.from_angle(angle) * outer_radius)
	for i: int in range(count, -1, -1):
		var angle: float = (TAU * float(i)) / float(count)
		pts.append(Vector2.from_angle(angle) * inner_radius)
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
	pts.append(Vector2.ZERO)
	for i: int in range(count + 1):
		var angle: float = -PI * 0.5 + (sweep_angle * float(i)) / float(count)
		pts.append(Vector2.from_angle(angle) * radius)
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


func _check_player_overlap() -> void:
	if not is_hazard_active or not is_inside_tree():
		return
	for body: Node2D in get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.call("take_damage", 1)


func _on_body_entered(body: Node2D) -> void:
	if is_hazard_active and body.is_in_group("player") and body.has_method("take_damage"):
		body.call("take_damage", 1)
