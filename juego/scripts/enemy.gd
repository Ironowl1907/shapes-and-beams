@tool
extends Area2D
## Autonomous, non-destructible enemy threat.
##
## Three behaviours share one lightweight state machine:
## - CHASER lunges at the player after a short wind-up.
## - TURRET holds position, paints an aim line, then fires a small spread.
## - ORBITER circles the player at a safe distance.
## Every enemy telegraphs its arrival and is disabled during that warning.

signal fire_projectile(origin: Vector2, direction: Vector2, speed: float, radius: float)

enum EnemyType {
	CHASER = 0,
	TURRET = 1,
	ORBITER = 2,
}

enum Phase {
	SPAWN,
	ACTIVE,
	FADE_OUT,
}

enum ChaserState {
	CHASE,
	WINDUP,
	LUNGE,
}

const CHASER_RADIUS: float = 22.0
const TURRET_RADIUS: float = 24.0
const ORBITER_RADIUS: float = 20.0
const CHASER_CHASE_SPEED: float = 118.0
const CHASER_LUNGE_SPEED: float = 470.0
const ORBITER_RADIUS_DISTANCE: float = 168.0
const ORBITER_ANGULAR_SPEED: float = 1.25
const TURRET_FIRE_INTERVAL: float = 2.15
const TURRET_AIM_TIME: float = 0.55
const CONTACT_CHECK_INTERVAL: float = 0.12
const FADE_TIME: float = 0.24
const DEFAULT_WARNING: float = 0.85
const DEFAULT_LIFETIME: float = 7.0
const PROJECTILE_SPAWN_RADIUS: float = 28.0

var hazard_type: int = 4
var enemy_type: EnemyType = EnemyType.CHASER
var current_phase: Phase = Phase.SPAWN
var phase_timer: float = 0.0
var age: float = 0.0
var lifetime: float = DEFAULT_LIFETIME
var warning_time: float = DEFAULT_WARNING
var speed_scale: float = 1.0
var is_hazard_active: bool = false
var contact_count: int = 0
var projectiles_fired: int = 0
var target_node: Node2D = null

var _target_position: Vector2 = Vector2.ZERO
var _chaser_state: ChaserState = ChaserState.CHASE
var _lunge_cooldown: float = 0.0
var _lunge_direction: Vector2 = Vector2.RIGHT
var _fire_timer: float = 0.0
var _orbit_center: Vector2 = Vector2.ZERO
var _orbit_angle: float = 0.0
var _orbit_radius: float = ORBITER_RADIUS_DISTANCE
var _contact_check_timer: float = 0.0
var _arena_size: Vector2 = Vector2(1152.0, 648.0)
var _recoil: float = 0.0

@onready var outer_polygon: Polygon2D = $OuterPolygon
@onready var core_polygon: Polygon2D = $CorePolygon
@onready var aim_line: Line2D = $AimLine
@onready var trail: Line2D = $Trail
@onready var ring: Line2D = $Ring
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_resolve_nodes()
	_arena_size = _get_arena_size()
	add_to_group("enemies")
	add_to_group("hazards")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_configure_common_visuals()
	_build_visual()
	_enter_phase(Phase.SPAWN)


## Configures a new enemy. Call after adding the enemy to the scene tree.
func configure_enemy(
	type: int = EnemyType.CHASER,
	spawn_pos: Vector2 = Vector2.ZERO,
	target: Node2D = null,
	requested_speed_scale: float = 1.0,
	warning: float = DEFAULT_WARNING,
	max_lifetime: float = DEFAULT_LIFETIME
) -> void:
	_resolve_nodes()
	_arena_size = _get_arena_size()
	enemy_type = clampi(type, EnemyType.CHASER, EnemyType.ORBITER)
	global_position = spawn_pos
	target_node = target
	speed_scale = clampf(requested_speed_scale, 0.75, 1.45)
	warning_time = maxf(warning, 0.35)
	lifetime = maxf(max_lifetime, warning_time + 1.0)
	age = 0.0
	phase_timer = 0.0
	contact_count = 0
	projectiles_fired = 0
	_recoil = 0.0
	_chaser_state = ChaserState.CHASE
	_lunge_cooldown = 0.85
	_fire_timer = 0.95
	_orbit_angle = 0.0
	_orbit_radius = ORBITER_RADIUS_DISTANCE
	_target_position = _get_target_position()
	_orbit_center = _target_position
	if target_node != null:
		_orbit_center = target_node.global_position
	_orbit_angle = (_orbit_center - global_position).angle()
	_orbit_radius = clampf(global_position.distance_to(_orbit_center), 150.0, 280.0)
	if enemy_type == EnemyType.TURRET:
		_fire_timer = 1.05
		rotation = 0.0
	else:
		rotation = (_target_position - global_position).angle()
	visible = true
	modulate = Color.WHITE
	scale = Vector2.ONE * 0.45
	if target_node != null:
		_chaser_state = ChaserState.CHASE
	_build_visual()
	_enter_phase(Phase.SPAWN)


func set_target_node(target: Node2D) -> void:
	target_node = target
	_target_position = _get_target_position()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances the enemy by delta seconds. Safe for deterministic tests.
func simulate_physics(delta: float) -> void:
	var safe_delta: float = maxf(delta, 0.0)
	phase_timer += safe_delta
	age += safe_delta
	if _recoil > 0.0:
		_recoil = maxf(0.0, _recoil - safe_delta * 4.0)

	if target_node != null and is_instance_valid(target_node):
		_target_position = target_node.global_position

	match current_phase:
		Phase.SPAWN:
			_update_spawn_visual()
			if phase_timer >= warning_time:
				_enter_phase(Phase.ACTIVE)
		Phase.ACTIVE:
			match enemy_type:
				EnemyType.CHASER:
					_simulate_chaser(safe_delta)
				EnemyType.TURRET:
					_simulate_turret(safe_delta)
				EnemyType.ORBITER:
					_simulate_orbiter(safe_delta)
			_check_contact(safe_delta)
			if age >= lifetime:
				_enter_phase(Phase.FADE_OUT)
		Phase.FADE_OUT:
			var progress: float = clampf(phase_timer / FADE_TIME, 0.0, 1.0)
			modulate.a = 1.0 - progress
			scale = Vector2.ONE * lerpf(1.0, 0.25, progress)
			if progress >= 1.0:
				_despawn()
	_update_trail()
	_update_core_motion(safe_delta)


func _simulate_chaser(delta: float) -> void:
	match _chaser_state:
		ChaserState.CHASE:
			_lunge_cooldown = maxf(0.0, _lunge_cooldown - delta)
			var to_target: Vector2 = _target_position - global_position
			var distance: float = to_target.length()
			var desired: Vector2 = to_target.normalized() * CHASER_CHASE_SPEED * speed_scale if distance > 6.0 else Vector2.ZERO
			global_position += desired * delta
			if distance > 0.001:
				rotation = lerp_angle(rotation, desired.angle() if desired.length_squared() > 0.001 else rotation, minf(8.0 * delta, 1.0))
			aim_line.visible = false
			if _lunge_cooldown <= 0.0 and distance < 520.0:
				_chaser_state = ChaserState.WINDUP
				phase_timer = 0.0
				_lunge_direction = to_target.normalized() if distance > 0.001 else Vector2.RIGHT
		ChaserState.WINDUP:
			var windup_duration: float = 0.44 / maxf(speed_scale, 0.75)
			core_polygon.scale = Vector2.ONE * (1.0 + 0.35 * clampf(phase_timer / windup_duration, 0.0, 1.0))
			outer_polygon.color = Color(0.98, 0.98, 0.98, 1.0)
			aim_line.visible = true
			var local_lunge: Vector2 = _lunge_direction.rotated(-rotation)
			aim_line.points = PackedVector2Array([Vector2.ZERO, local_lunge * 74.0])
			aim_line.default_color = Color(0.58, 0.58, 0.58, 0.62)
			if phase_timer >= windup_duration:
				_chaser_state = ChaserState.LUNGE
				phase_timer = 0.0
				rotation = _lunge_direction.angle()
		ChaserState.LUNGE:
			var lunge_duration: float = 0.26
			global_position += _lunge_direction * CHASER_LUNGE_SPEED * speed_scale * delta
			aim_line.visible = false
			if phase_timer >= lunge_duration:
				_chaser_state = ChaserState.CHASE
				_lunge_cooldown = 2.05 / maxf(speed_scale, 0.75)
				phase_timer = 0.0
	_constrain_to_arena(CHASER_RADIUS + 4.0)


func _simulate_turret(delta: float) -> void:
	aim_line.points = PackedVector2Array()
	var to_target: Vector2 = _target_position - global_position
	_fire_timer -= delta
	if _fire_timer <= TURRET_AIM_TIME:
		aim_line.visible = true
		aim_line.points = PackedVector2Array([Vector2.ZERO, to_target.limit_length(460.0)])
		var aim_progress: float = clampf(1.0 - _fire_timer / TURRET_AIM_TIME, 0.0, 1.0)
		aim_line.default_color = Color(0.55 + 0.35 * aim_progress, 0.55 + 0.35 * aim_progress, 0.55 + 0.35 * aim_progress, 0.45 + 0.4 * aim_progress)
	else:
		aim_line.visible = false
	if _fire_timer <= 0.0:
		_fire_timer = TURRET_FIRE_INTERVAL / maxf(speed_scale, 0.75)
		var base_dir: Vector2 = to_target.normalized() if to_target.length_squared() > 0.001 else Vector2.DOWN
		var spread: float = 0.20
		for offset: float in [-spread, 0.0, spread]:
			var dir: Vector2 = base_dir.rotated(offset)
			fire_projectile.emit(global_position + dir * PROJECTILE_SPAWN_RADIUS, dir, 300.0 * speed_scale, 8.0)
			projectiles_fired += 1
		_recoil = 1.0
		core_polygon.scale = Vector2.ONE * 1.35


func _simulate_orbiter(delta: float) -> void:
	_orbit_center = _orbit_center.move_toward(_target_position, 74.0 * delta)
	_orbit_radius = move_toward(_orbit_radius, ORBITER_RADIUS_DISTANCE, 42.0 * delta)
	_orbit_angle += ORBITER_ANGULAR_SPEED * speed_scale * delta
	var radius_pulse: float = _orbit_radius * (1.0 + 0.10 * sin(age * 2.2))
	global_position = _orbit_center + Vector2.from_angle(_orbit_angle) * radius_pulse
	_constrain_to_arena(ORBITER_RADIUS + 6.0)
	rotation += 1.8 * delta
	aim_line.visible = false


func _enter_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_timer = 0.0
	match new_phase:
		Phase.SPAWN:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			scale = Vector2.ONE * 0.45
			modulate = Color(1.0, 1.0, 1.0, 0.52)
			aim_line.visible = false
			outer_polygon.color = Color(0.48, 0.48, 0.48, 0.9)
			core_polygon.color = Color(0.72, 0.72, 0.72, 0.9)
			ring.visible = false
		Phase.ACTIVE:
			is_hazard_active = true
			scale = Vector2.ONE
			modulate = Color.WHITE
			if collision_shape != null:
				collision_shape.disabled = false
			outer_polygon.color = Color(0.88, 0.88, 0.88, 1.0)
			core_polygon.color = Color.WHITE
			ring.visible = enemy_type == EnemyType.ORBITER
			_chaser_state = ChaserState.CHASE
			_lunge_cooldown = 1.0
			phase_timer = 0.0
		Phase.FADE_OUT:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			aim_line.visible = false
			ring.visible = false


func _update_spawn_visual() -> void:
	var progress: float = clampf(phase_timer / maxf(warning_time, 0.001), 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(progress * TAU * 2.5)
	scale = Vector2.ONE * lerpf(0.45, 1.0, progress)
	modulate.a = 0.52 + 0.38 * pulse
	if aim_line.visible:
		aim_line.visible = false


func _update_core_motion(delta: float) -> void:
	if current_phase != Phase.ACTIVE:
		return
	match enemy_type:
		EnemyType.TURRET:
			core_polygon.rotation += 1.8 * delta
			outer_polygon.rotation -= 0.8 * delta
			core_polygon.scale = core_polygon.scale.move_toward(Vector2.ONE, delta * 3.0)
			scale = Vector2.ONE * (1.0 - 0.06 * _recoil)
		EnemyType.ORBITER:
			core_polygon.rotation -= 2.6 * delta
			outer_polygon.rotation += 1.4 * delta
			ring.rotation += 2.2 * delta
		EnemyType.CHASER:
			core_polygon.rotation += 1.2 * delta
			core_polygon.scale = core_polygon.scale.move_toward(Vector2.ONE, delta * 4.0)


func _update_trail() -> void:
	if trail == null:
		return
	trail.visible = current_phase == Phase.ACTIVE and enemy_type != EnemyType.TURRET
	if not trail.visible:
		return
	trail.add_point(global_position)
	if trail.get_point_count() > 9:
		trail.remove_point(0)


func _configure_common_visuals() -> void:
	if aim_line != null:
		aim_line.width = 2.0
		aim_line.default_color = Color(0.58, 0.58, 0.58, 0.55)
		aim_line.visible = false
	if trail != null:
		trail.top_level = true
		trail.width = 5.0
		trail.default_color = Color(0.55, 0.55, 0.55, 0.28)
		trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
		trail.end_cap_mode = Line2D.LINE_CAP_ROUND
		trail.visible = false
	if ring != null:
		ring.width = 2.0
		ring.default_color = Color(0.55, 0.55, 0.55, 0.45)
		ring.closed = true
		ring.visible = false


func _build_visual() -> void:
	var radius: float = CHASER_RADIUS
	match enemy_type:
		EnemyType.TURRET:
			radius = TURRET_RADIUS
		EnemyType.ORBITER:
			radius = ORBITER_RADIUS
		_:
			radius = CHASER_RADIUS

	if outer_polygon != null:
		match enemy_type:
			EnemyType.TURRET:
				outer_polygon.polygon = _build_regular_polygon(radius, 6)
			EnemyType.ORBITER:
				outer_polygon.polygon = _build_diamond(radius)
			_:
				outer_polygon.polygon = _build_triangle(radius)
	if core_polygon != null:
		match enemy_type:
			EnemyType.TURRET:
				core_polygon.polygon = _build_triangle(radius * 0.42)
			EnemyType.ORBITER:
				core_polygon.polygon = _build_diamond(radius * 0.38)
			_:
				core_polygon.polygon = _build_triangle(radius * 0.46)
	if ring != null:
		var ring_radius: float = radius * 1.9
		var points: PackedVector2Array = PackedVector2Array()
		for i: int in range(16):
			points.append(Vector2.from_angle(TAU * float(i) / 16.0) * ring_radius)
		ring.points = points
	if collision_shape != null:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = radius * 0.92
		collision_shape.shape = circle


func _build_triangle(radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(radius, 0.0),
		Vector2(-radius * 0.78, -radius * 0.82),
		Vector2(-radius * 0.78, radius * 0.82),
	])


func _build_diamond(radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(radius, 0.0),
		Vector2(0.0, -radius),
		Vector2(-radius, 0.0),
		Vector2(0.0, radius),
	])


func _build_regular_polygon(radius: float, sides: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(maxi(sides, 3)):
		points.append(Vector2.from_angle(TAU * float(i) / float(sides)) * radius)
	return points


func _constrain_to_arena(margin: float) -> void:
	global_position.x = clampf(global_position.x, margin, maxf(margin, _arena_size.x - margin))
	global_position.y = clampf(global_position.y, margin, maxf(margin, _arena_size.y - margin))


func _get_target_position() -> Vector2:
	if target_node != null and is_instance_valid(target_node):
		return target_node.global_position
	return _arena_size * 0.5


func _check_contact(delta: float) -> void:
	_contact_check_timer -= delta
	if _contact_check_timer > 0.0:
		return
	_contact_check_timer = CONTACT_CHECK_INTERVAL
	if not is_inside_tree() or not is_hazard_active:
		return
	for body: Node2D in get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.call("take_damage", 1)
			contact_count += 1
			return


func _on_body_entered(body: Node2D) -> void:
	if not is_hazard_active or body == null:
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.call("take_damage", 1)
		contact_count += 1


func _get_arena_size() -> Vector2:
	if is_inside_tree():
		var rect_size: Vector2 = get_viewport_rect().size
		if rect_size.x > 0.0 and rect_size.y > 0.0:
			return rect_size
	return Vector2(1152.0, 648.0)


func _despawn() -> void:
	if is_inside_tree() and not Engine.is_editor_hint():
		queue_free()
	else:
		var parent: Node = get_parent()
		if parent != null:
			parent.remove_child(self)
		queue_free()


func _resolve_nodes() -> void:
	outer_polygon = get_node_or_null("OuterPolygon") as Polygon2D
	core_polygon = get_node_or_null("CorePolygon") as Polygon2D
	aim_line = get_node_or_null("AimLine") as Line2D
	trail = get_node_or_null("Trail") as Line2D
	ring = get_node_or_null("Ring") as Line2D
	collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
