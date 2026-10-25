@tool
extends CharacterBody2D
## Player entity for the black-and-white dodge game prototype.
## Supports keyboard movement (WASD/Arrows), direct 2D target-position following
## (mouse cursor now, MediaPipe hand-tracking coordinates later), and an
## invincible dash burst.

signal hp_changed(new_hp: int, max_hp: int)
signal died
signal dashed

const MAX_HP: int = 3
const MOVE_SPEED: float = 420.0
const TARGET_FOLLOW_SPEED: float = 950.0
const TARGET_STOP_DISTANCE: float = 4.0
const DASH_SPEED: float = 1150.0
const DASH_DURATION: float = 0.18
const DASH_COOLDOWN: float = 0.45
const HIT_INVINCIBILITY_DURATION: float = 1.2
const PLAYER_HALF_SIZE: float = 14.0

@export var move_speed: float = MOVE_SPEED
@export var target_follow_speed: float = TARGET_FOLLOW_SPEED

var current_hp: int = MAX_HP
var is_active: bool = true
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector2 = Vector2.RIGHT
var last_move_direction: Vector2 = Vector2.RIGHT
var hit_invincibility_timer: float = 0.0

## Target position used for mouse or external 2D hand-tracking input.
var target_position: Vector2 = Vector2.ZERO
var use_target_position: bool = false
var external_tracking_active: bool = false

@onready var outer_polygon: Polygon2D = $OuterPolygon
@onready var inner_polygon: Polygon2D = $InnerPolygon
@onready var dash_ring: Polygon2D = $DashRing
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	outer_polygon = get_node_or_null("OuterPolygon") as Polygon2D
	inner_polygon = get_node_or_null("InnerPolygon") as Polygon2D
	dash_ring = get_node_or_null("DashRing") as Polygon2D
	collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	add_to_group("player")
	target_position = global_position
	_update_visuals(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not is_active:
		return

	if event is InputEventMouseMotion and not external_tracking_active:
		var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		set_target_position(motion_event.position)

	if event.is_action_pressed("dash"):
		trigger_dash()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances player movement, timers, bounds clamping, and visuals by delta seconds.
func simulate_physics(delta: float) -> void:
	if not is_active:
		velocity = Vector2.ZERO
		return

	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - delta)

	if hit_invincibility_timer > 0.0:
		hit_invincibility_timer = maxf(0.0, hit_invincibility_timer - delta)

	var keyboard_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if keyboard_dir.length_squared() > 0.001 and not external_tracking_active:
		use_target_position = false
		last_move_direction = keyboard_dir.normalized()

	if is_dashing:
		dash_timer -= delta
		velocity = dash_direction * DASH_SPEED
		if dash_timer <= 0.0:
			is_dashing = false
			if use_target_position and not external_tracking_active:
				target_position = global_position
	else:
		if use_target_position:
			var to_target: Vector2 = target_position - global_position
			var distance: float = to_target.length()
			if distance > TARGET_STOP_DISTANCE:
				var dir: Vector2 = to_target / distance
				last_move_direction = dir
				var desired_speed: float = minf(target_follow_speed, distance / maxf(delta, 0.001))
				velocity = dir * desired_speed
			else:
				global_position = target_position
				velocity = Vector2.ZERO
		else:
			velocity = keyboard_dir * move_speed

	if is_inside_tree() and not Engine.is_editor_hint():
		move_and_slide()
	else:
		global_position += velocity * delta

	_constrain_to_viewport()
	_update_visuals(delta)


## Sets the 2D target position in viewport coordinates for the player to follow.
## Used by mouse input now and replaceable by external MediaPipe hand tracking.
func set_target_position(new_target: Vector2, is_external: bool = false) -> void:
	var viewport_size: Vector2 = _get_arena_size()
	target_position = Vector2(
		clampf(new_target.x, PLAYER_HALF_SIZE, viewport_size.x - PLAYER_HALF_SIZE),
		clampf(new_target.y, PLAYER_HALF_SIZE, viewport_size.y - PLAYER_HALF_SIZE)
	)
	use_target_position = true
	if is_external:
		external_tracking_active = true


## Accepts normalized [0..1, 0..1] coordinates (e.g. from MediaPipe hand tracking)
## and maps them to the current viewport dimensions.
func set_normalized_target_position(normalized_target: Vector2) -> void:
	var viewport_size: Vector2 = _get_arena_size()
	var mapped: Vector2 = Vector2(
		normalized_target.x * viewport_size.x,
		normalized_target.y * viewport_size.y
	)
	set_target_position(mapped, true)


## Triggers a brief movement burst with temporary invincibility.
func trigger_dash(override_direction: Vector2 = Vector2.ZERO) -> bool:
	if not is_active or is_dashing or dash_cooldown_timer > 0.0:
		return false

	var dir: Vector2 = override_direction
	if dir.length_squared() <= 0.001:
		var keyboard_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if keyboard_dir.length_squared() > 0.001:
			dir = keyboard_dir.normalized()
		elif use_target_position and global_position.distance_to(target_position) > TARGET_STOP_DISTANCE:
			dir = (target_position - global_position).normalized()
		elif last_move_direction.length_squared() > 0.001:
			dir = last_move_direction.normalized()
		else:
			dir = Vector2.RIGHT

	dash_direction = dir.normalized()
	last_move_direction = dash_direction
	is_dashing = true
	dash_timer = DASH_DURATION
	dash_cooldown_timer = DASH_COOLDOWN
	dashed.emit()
	return true


## Returns true when the player cannot take damage (during dash or post-hit i-frames).
func is_invincible() -> bool:
	return is_dashing or hit_invincibility_timer > 0.0


## Applies damage if the player is not currently invincible.
func take_damage(amount: int = 1) -> void:
	if not is_active or is_invincible() or current_hp <= 0:
		return

	current_hp = maxi(0, current_hp - amount)
	hit_invincibility_timer = HIT_INVINCIBILITY_DURATION
	hp_changed.emit(current_hp, MAX_HP)

	if current_hp <= 0:
		is_active = false
		velocity = Vector2.ZERO
		died.emit()


## Resets player health, position, and states for a fresh level run.
func reset_player(spawn_position: Vector2) -> void:
	global_position = spawn_position
	target_position = spawn_position
	use_target_position = false
	velocity = Vector2.ZERO
	current_hp = MAX_HP
	is_active = true
	is_dashing = false
	dash_timer = 0.0
	dash_cooldown_timer = 0.0
	hit_invincibility_timer = 0.0
	hp_changed.emit(current_hp, MAX_HP)
	_update_visuals(0.0)


func _get_arena_size() -> Vector2:
	if is_inside_tree():
		var rect_size: Vector2 = get_viewport_rect().size
		if rect_size.x > 0.0 and rect_size.y > 0.0:
			return rect_size
	return Vector2(1152.0, 648.0)


func _constrain_to_viewport() -> void:
	var viewport_size: Vector2 = _get_arena_size()
	global_position.x = clampf(global_position.x, PLAYER_HALF_SIZE, viewport_size.x - PLAYER_HALF_SIZE)
	global_position.y = clampf(global_position.y, PLAYER_HALF_SIZE, viewport_size.y - PLAYER_HALF_SIZE)


func _update_visuals(_delta: float) -> void:
	if outer_polygon == null or inner_polygon == null or dash_ring == null:
		return

	dash_ring.visible = is_dashing
	if is_dashing:
		outer_polygon.color = Color.WHITE
		scale = Vector2(1.2, 1.2)
	else:
		scale = Vector2.ONE
		if hit_invincibility_timer > 0.0:
			var blink_on: bool = int(hit_invincibility_timer * 16.0) % 2 == 0
			outer_polygon.color = Color(0.35, 0.35, 0.35, 1.0) if blink_on else Color.WHITE
		else:
			outer_polygon.color = Color.WHITE

	# Inner black core grows as HP decreases to visually reflect damage in monochrome
	if current_hp >= 3:
		inner_polygon.visible = false
	elif current_hp == 2:
		inner_polygon.visible = true
		inner_polygon.scale = Vector2(0.45, 0.45)
	elif current_hp == 1:
		inner_polygon.visible = true
		inner_polygon.scale = Vector2(0.75, 0.75)
	else:
		inner_polygon.visible = true
		inner_polygon.scale = Vector2(0.9, 0.9)
