@tool
extends Area2D
## Spinning saw hazard.
##
## Two movement modes keep the threat readable:
## - BOUNCE: travels in a straight line and rebounds off the arena edges.
## - PATROL: sweeps across the arena with a small sine offset.
## Both modes telegraph briefly before becoming lethal.

enum SawMode {
	BOUNCE = 0,
	PATROL = 1,
}

enum Phase {
	TELEGRAPH,
	ACTIVE,
	FADE_OUT,
}

const DEFAULT_RADIUS: float = 32.0
const DEFAULT_SPEED: float = 230.0
const DEFAULT_WARNING: float = 0.65
const DEFAULT_LIFETIME: float = 6.0
const MAX_BOUNCES: int = 3
const VIEWPORT_MARGIN: float = 90.0

const TELEGRAPH_COLOR: Color = Color(0.30, 0.30, 0.30, 0.75)
const ACTIVE_COLOR: Color = Color(0.95, 0.95, 0.95, 1.0)

var hazard_type: int = 5
var saw_mode: SawMode = SawMode.BOUNCE
var current_phase: Phase = Phase.TELEGRAPH
var phase_timer: float = 0.0
var age: float = 0.0
var lifetime: float = DEFAULT_LIFETIME
var warning_time: float = DEFAULT_WARNING
var fade_time: float = 0.22
var is_hazard_active: bool = false
var saw_radius: float = DEFAULT_RADIUS
var velocity: Vector2 = Vector2.RIGHT
var spin_speed: float = 7.2
var bounces_remaining: int = MAX_BOUNCES
var bounces_count: int = 0
var contact_count: int = 0
var patrol_base_y: float = 0.0

@onready var glow: Polygon2D = $Glow
@onready var blade: Polygon2D = $Blade
@onready var hub: Polygon2D = $Hub
@onready var trail: Line2D = $Trail
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	glow = get_node_or_null("Glow") as Polygon2D
	blade = get_node_or_null("Blade") as Polygon2D
	hub = get_node_or_null("Hub") as Polygon2D
	trail = get_node_or_null("Trail") as Line2D
	collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	add_to_group("saws")
	add_to_group("hazards")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if trail != null:
		trail.top_level = true
		trail.width = 4.0
		trail.default_color = Color(0.55, 0.55, 0.55, 0.35)
		trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
		trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


## Configures the saw's movement, appearance and lifetime.
func configure(
	mode: int = SawMode.BOUNCE,
	spawn_pos: Vector2 = Vector2.ZERO,
	direction: Vector2 = Vector2.RIGHT,
	speed: float = DEFAULT_SPEED,
	radius: float = DEFAULT_RADIUS,
	warning: float = DEFAULT_WARNING,
	max_lifetime: float = DEFAULT_LIFETIME
) -> void:
	global_position = spawn_pos
	saw_mode = clampi(mode, 0, 1)
	var dir: Vector2 = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	velocity = dir * maxf(speed, 40.0)
	saw_radius = maxf(radius, 16.0)
	warning_time = maxf(warning, 0.15)
	lifetime = maxf(max_lifetime, warning_time + 0.5)
	patrol_base_y = spawn_pos.y
	age = 0.0
	bounces_remaining = MAX_BOUNCES
	bounces_count = 0
	rotation = 0.0
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances the saw by delta seconds. Safe to call from deterministic tests.
func simulate_physics(delta: float) -> void:
	var safe_delta: float = maxf(delta, 0.0)
	age += safe_delta
	phase_timer += safe_delta
	rotation += spin_speed * safe_delta * (0.35 if current_phase == Phase.TELEGRAPH else 1.0)

	match current_phase:
		Phase.TELEGRAPH:
			_update_telegraph_visual()
			if phase_timer >= warning_time:
				_enter_phase(Phase.ACTIVE)
		Phase.ACTIVE:
			_update_active_motion(safe_delta)
			_check_player_overlap()
			if age >= lifetime:
				_enter_phase(Phase.FADE_OUT)
		Phase.FADE_OUT:
			var progress: float = clampf(phase_timer / maxf(fade_time, 0.001), 0.0, 1.0)
			scale = Vector2.ONE * lerpf(1.0, 0.25, progress)
			modulate.a = 1.0 - progress
			if phase_timer >= fade_time:
				_despawn()
	_update_trail()


func _update_active_motion(delta: float) -> void:
	global_position += velocity * delta
	var arena: Vector2 = _get_arena_size()
	if saw_mode == SawMode.PATROL:
		var patrol_margin: float = saw_radius + 4.0
		if global_position.x < patrol_margin and velocity.x < 0.0:
			global_position.x = patrol_margin
			velocity.x = -velocity.x
		elif global_position.x > arena.x - patrol_margin and velocity.x > 0.0:
			global_position.x = arena.x - patrol_margin
			velocity.x = -velocity.x
		global_position.y = patrol_base_y + sin(age * 2.4) * 24.0
		return

	var margin: float = saw_radius + 4.0
	var bounced: bool = false
	if global_position.x < margin and velocity.x < 0.0:
		global_position.x = margin
		velocity.x = -velocity.x
		bounced = true
	elif global_position.x > arena.x - margin and velocity.x > 0.0:
		global_position.x = arena.x - margin
		velocity.x = -velocity.x
		bounced = true
	if global_position.y < margin and velocity.y < 0.0:
		global_position.y = margin
		velocity.y = -velocity.y
		bounced = true
	elif global_position.y > arena.y - margin and velocity.y > 0.0:
		global_position.y = arena.y - margin
		velocity.y = -velocity.y
		bounced = true

	if bounced:
		bounces_count += 1
		bounces_remaining -= 1
		if bounces_remaining <= 0:
			_enter_phase(Phase.FADE_OUT)


func _enter_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_timer = 0.0
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if glow != null:
				glow.color = TELEGRAPH_COLOR
			if blade != null:
				blade.color = Color(0.34, 0.34, 0.34, 0.85)
			if hub != null:
				hub.color = Color(0.52, 0.52, 0.52, 0.9)
			if trail != null:
				trail.visible = false
			scale = Vector2.ONE * 0.72
			modulate.a = 1.0
		Phase.ACTIVE:
			is_hazard_active = true
			scale = Vector2.ONE
			modulate.a = 1.0
			if collision_shape != null:
				collision_shape.disabled = false
			if glow != null:
				glow.color = Color(0.55, 0.55, 0.55, 0.24)
			if blade != null:
				blade.color = ACTIVE_COLOR
			if hub != null:
				hub.color = Color(0.20, 0.20, 0.20, 1.0)
			if trail != null:
				trail.visible = true
			_check_player_overlap()
		Phase.FADE_OUT:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if trail != null:
				trail.visible = false


func _update_telegraph_visual() -> void:
	var progress: float = clampf(phase_timer / maxf(warning_time, 0.001), 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(progress * TAU * 2.0)
	scale = Vector2.ONE * lerpf(0.72, 1.0, progress)
	if blade != null:
		var gray: float = lerpf(0.34, 0.65, pulse)
		blade.color = Color(gray, gray, gray, 0.9)
	if glow != null:
		glow.color = Color(0.34, 0.34, 0.34, 0.18 + 0.18 * pulse)


func _update_trail() -> void:
	if trail == null or not trail.visible:
		return
	trail.add_point(global_position)
	if trail.get_point_count() > 8:
		trail.remove_point(0)


func _rebuild_geometry() -> void:
	var r: float = saw_radius
	if blade != null:
		blade.polygon = _build_saw_polygon(r, 16, 0.72)
	if glow != null:
		glow.polygon = _build_saw_polygon(r * 1.35, 16, 0.62)
		glow.z_index = -2
	if hub != null:
		hub.polygon = _build_circle_polygon(r * 0.42, 14)
	if collision_shape != null:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = r * 0.92
		collision_shape.shape = circle


func _build_saw_polygon(radius: float, teeth: int, inner_ratio: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var total: int = maxi(teeth * 2, 8)
	for i: int in range(total):
		var angle: float = TAU * float(i) / float(total)
		var point_radius: float = radius if i % 2 == 0 else radius * inner_ratio
		points.append(Vector2.from_angle(angle) * point_radius)
	return points


func _build_circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(maxi(segments, 3)):
		points.append(Vector2.from_angle(TAU * float(i) / float(segments)) * radius)
	return points


func _get_arena_size() -> Vector2:
	if is_inside_tree():
		var rect_size: Vector2 = get_viewport_rect().size
		if rect_size.x > 0.0 and rect_size.y > 0.0:
			return rect_size
	return Vector2(1152.0, 648.0)


func _check_player_overlap() -> void:
	if not is_hazard_active or not is_inside_tree():
		return
	for body: Node2D in get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.call("take_damage", 1)
			contact_count += 1
			return


func _on_body_entered(body: Node2D) -> void:
	if is_hazard_active and body.is_in_group("player") and body.has_method("take_damage"):
		body.call("take_damage", 1)
		contact_count += 1


func _despawn() -> void:
	if is_inside_tree() and not Engine.is_editor_hint():
		queue_free()
	else:
		var parent: Node = get_parent()
		if parent != null:
			parent.remove_child(self)
		queue_free()
