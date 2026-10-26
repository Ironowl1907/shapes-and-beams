@tool
extends CharacterBody2D
## Player entity for the black-and-white dodge game.
##
## Supports keyboard movement (WASD/Arrows), direct 2D target-position following
## (mouse or MediaPipe hand tracking), and an energy-based shield. The shield is
## held while the shield input (or closed fist) remains active and blocks all
## incoming damage until its energy is depleted.

signal hp_changed(new_hp: int, max_hp: int)
signal damaged(amount: int)
signal died
signal shield_changed(active: bool)
signal shield_blocked
signal shield_broken

const MAX_HP: int = 3
const MOVE_SPEED: float = 420.0
const MOVE_ACCELERATION: float = 9000.0
const TARGET_FOLLOW_SPEED: float = 950.0
const TARGET_STOP_DISTANCE: float = 4.0
const HIT_INVINCIBILITY_DURATION: float = 1.2
const PLAYER_HALF_SIZE: float = 14.0

const SHIELD_MAX_ENERGY: float = 1.0
const SHIELD_DRAIN_PER_SEC: float = 1.0 / 1.65
const SHIELD_RECHARGE_PER_SEC: float = 1.0 / 1.35
const SHIELD_RECHARGE_DELAY: float = 0.40
const SHIELD_BLOCK_FEEDBACK_COOLDOWN: float = 0.12
const SHIELD_BREAK_GRACE: float = 0.35

const AudioLibrary: GDScript = preload("res://scripts/audio_library.gd")

@export var move_speed: float = MOVE_SPEED
@export var target_follow_speed: float = TARGET_FOLLOW_SPEED

var current_hp: int = MAX_HP
var is_active: bool = true
var is_shielding: bool = false
var shield_held: bool = false
var shield_energy: float = SHIELD_MAX_ENERGY
var shield_exhausted: bool = false
var shield_recharge_timer: float = 0.0
var shield_block_feedback_timer: float = 0.0
var shield_block_flash: float = 0.0
var hit_invincibility_timer: float = 0.0
var hit_flash_timer: float = 0.0
var shield_activation_flash: float = 0.0
var _light_pulse_time: float = 0.0

var hit_sfx_play_count: int = 0
var shield_sfx_play_count: int = 0
var last_sfx_played: StringName = &""

## Target position used for mouse or external 2D hand-tracking input.
var target_position: Vector2 = Vector2.ZERO
var use_target_position: bool = false
var external_tracking_active: bool = false

@onready var player_glow: Polygon2D = $PlayerGlow
@onready var player_light: PointLight2D = $PlayerLight
@onready var outer_polygon: Polygon2D = $OuterPolygon
@onready var inner_polygon: Polygon2D = $InnerPolygon
@onready var shield_ring: Line2D = $ShieldRing
@onready var shield_glow: Polygon2D = $ShieldGlow
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sfx_player: AudioStreamPlayer = $SfxPlayer
@onready var shield_sfx_player: AudioStreamPlayer = $ShieldSfxPlayer


func _ready() -> void:
	if not InputMap.has_action("move_left"):
		InputMap.load_from_project_settings()
	player_glow = get_node_or_null("PlayerGlow") as Polygon2D
	player_light = get_node_or_null("PlayerLight") as PointLight2D
	outer_polygon = get_node_or_null("OuterPolygon") as Polygon2D
	inner_polygon = get_node_or_null("InnerPolygon") as Polygon2D
	shield_ring = get_node_or_null("ShieldRing") as Line2D
	shield_glow = get_node_or_null("ShieldGlow") as Polygon2D
	collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	sfx_player = get_node_or_null("SfxPlayer") as AudioStreamPlayer
	shield_sfx_player = get_node_or_null("ShieldSfxPlayer") as AudioStreamPlayer
	if sfx_player != null and (not is_inside_tree() or not Engine.is_editor_hint()):
		sfx_player.stream = AudioLibrary.hit()
	if shield_sfx_player != null and (not is_inside_tree() or not Engine.is_editor_hint()):
		shield_sfx_player.stream = AudioLibrary.shield_on()
	_configure_player_lighting()
	if shield_ring != null:
		shield_ring.closed = true
		shield_ring.width = 3.0
		shield_ring.default_color = Color.WHITE
		shield_ring.points = _build_ring_points(20.0, 8, 0.0)
		shield_ring.visible = false
	if shield_glow != null:
		shield_glow.polygon = _build_polygon(20.0, 8)
		shield_glow.color = Color(0.55, 0.55, 0.55, 0.0)
		shield_glow.visible = false
	add_to_group("player")
	target_position = global_position
	_update_visuals(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not is_active:
		return
	if event is InputEventMouseMotion and not external_tracking_active:
		var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		set_target_position(motion_event.position)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances player movement, shield state, timers, bounds clamping, and visuals.
func simulate_physics(delta: float) -> void:
	if not is_active:
		velocity = Vector2.ZERO
		return

	if hit_invincibility_timer > 0.0:
		hit_invincibility_timer = maxf(0.0, hit_invincibility_timer - delta)
	if hit_flash_timer > 0.0:
		hit_flash_timer = maxf(0.0, hit_flash_timer - delta * 4.0)
	if shield_block_flash > 0.0:
		shield_block_flash = maxf(0.0, shield_block_flash - delta * 5.0)
	if shield_activation_flash > 0.0:
		shield_activation_flash = maxf(0.0, shield_activation_flash - delta * 4.0)
	if shield_block_feedback_timer > 0.0:
		shield_block_feedback_timer = maxf(0.0, shield_block_feedback_timer - delta)

	if not InputMap.has_action("move_left"):
		InputMap.load_from_project_settings()
	var keyboard_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down") if InputMap.has_action("move_left") else Vector2.ZERO
	if keyboard_dir.length_squared() > 0.001 and not external_tracking_active:
		use_target_position = false

	var keyboard_shield: bool = InputMap.has_action("shield") and Input.is_action_pressed("shield")
	_update_shield(shield_held or keyboard_shield, delta)
	_move_player(delta, keyboard_dir)
	_constrain_to_viewport()
	_update_visuals(delta)


func _move_player(delta: float, keyboard_dir: Vector2) -> void:
	var desired_velocity: Vector2 = Vector2.ZERO
	if use_target_position:
		var to_target: Vector2 = target_position - global_position
		var distance: float = to_target.length()
		if distance > TARGET_STOP_DISTANCE:
			var dir: Vector2 = to_target / distance
			var desired_speed: float = minf(target_follow_speed, distance / maxf(delta, 0.001))
			desired_velocity = dir * desired_speed
		else:
			global_position = target_position
			velocity = Vector2.ZERO
			return
		# Direct pointer/hand control must track exactly, without inertial overshoot.
		velocity = desired_velocity
	else:
		desired_velocity = keyboard_dir * move_speed
		velocity = velocity.move_toward(desired_velocity, MOVE_ACCELERATION * delta)

	if is_inside_tree() and not Engine.is_editor_hint():
		move_and_slide()
	else:
		global_position += velocity * delta


func _update_shield(held: bool, delta: float) -> void:
	if held and not shield_exhausted and shield_energy > 0.0:
		if not is_shielding:
			_on_shield_started()
		is_shielding = true
		shield_energy = maxf(0.0, shield_energy - SHIELD_DRAIN_PER_SEC * delta)
		shield_recharge_timer = SHIELD_RECHARGE_DELAY
		if shield_energy <= 0.0:
			_break_shield()
		return

	if is_shielding:
		is_shielding = false
		shield_changed.emit(false)
	if held:
		# An exhausted shield recharges only after the input is released.
		return
	shield_exhausted = false
	if shield_energy >= SHIELD_MAX_ENERGY:
		return
	if shield_recharge_timer > 0.0:
		shield_recharge_timer = maxf(0.0, shield_recharge_timer - delta)
		return
	shield_energy = minf(SHIELD_MAX_ENERGY, shield_energy + SHIELD_RECHARGE_PER_SEC * delta)


func _on_shield_started() -> void:
	shield_activation_flash = 1.0
	_play_shield_sfx(&"shield_on", AudioLibrary.shield_on())
	shield_changed.emit(true)


func _break_shield() -> void:
	is_shielding = false
	shield_exhausted = true
	shield_energy = 0.0
	hit_invincibility_timer = maxf(hit_invincibility_timer, SHIELD_BREAK_GRACE)
	_play_shield_sfx(&"shield_break", AudioLibrary.shield_break())
	shield_changed.emit(false)
	shield_broken.emit()


## Sets the shield hold state from an external source (MediaPipe closed fist).
func set_shield_held(held: bool) -> void:
	shield_held = held


## Returns the current shield energy as a normalized [0.0..1.0] ratio.
func get_shield_energy_ratio() -> float:
	return clampf(shield_energy / SHIELD_MAX_ENERGY, 0.0, 1.0)


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


## Releases external hand-tracking control so mouse and keyboard inputs immediately resume.
func release_external_tracking() -> void:
	external_tracking_active = false
	shield_held = false
	velocity = Vector2.ZERO
	if is_shielding:
		is_shielding = false
		shield_changed.emit(false)
	use_target_position = false
	target_position = global_position


## Returns true when the player cannot take damage (shield or post-hit i-frames).
func is_invincible() -> bool:
	return is_shielding or hit_invincibility_timer > 0.0


## Applies damage unless shielded or currently in post-hit invincibility frames.
func take_damage(amount: int = 1) -> void:
	if not is_active or amount <= 0 or current_hp <= 0:
		return

	if is_shielding:
		_register_shield_block()
		return

	if hit_invincibility_timer > 0.0:
		return

	var prev_hp: int = current_hp
	current_hp = maxi(0, current_hp - amount)
	hit_invincibility_timer = HIT_INVINCIBILITY_DURATION
	hit_flash_timer = 1.0
	if current_hp < prev_hp:
		_play_hit_sfx()
		damaged.emit(amount)
	hp_changed.emit(current_hp, MAX_HP)

	if current_hp <= 0:
		is_active = false
		is_shielding = false
		shield_held = false
		velocity = Vector2.ZERO
		died.emit()
	_update_visuals(0.0)


func _register_shield_block() -> void:
	shield_block_flash = 1.0
	if shield_block_feedback_timer > 0.0:
		return
	shield_block_feedback_timer = SHIELD_BLOCK_FEEDBACK_COOLDOWN
	_play_shield_sfx(&"shield_block", AudioLibrary.shield_block())
	shield_blocked.emit()


func _play_hit_sfx() -> void:
	if sfx_player == null:
		sfx_player = get_node_or_null("SfxPlayer") as AudioStreamPlayer
	var stream: AudioStreamWAV = AudioLibrary.hit()
	if sfx_player != null:
		sfx_player.stream = stream
		if is_inside_tree() and not Engine.is_editor_hint():
			sfx_player.play()
	hit_sfx_play_count += 1
	last_sfx_played = &"hit"


func _play_shield_sfx(sfx_name: StringName, stream: AudioStreamWAV) -> void:
	if shield_sfx_player == null:
		shield_sfx_player = get_node_or_null("ShieldSfxPlayer") as AudioStreamPlayer
	if shield_sfx_player != null:
		shield_sfx_player.stream = stream
		if is_inside_tree() and not Engine.is_editor_hint():
			shield_sfx_player.play()
	shield_sfx_play_count += 1
	last_sfx_played = sfx_name


## Resets player health, position, shield, and states for a fresh level run.
func reset_player(spawn_position: Vector2) -> void:
	global_position = spawn_position
	target_position = spawn_position
	use_target_position = false
	external_tracking_active = false
	velocity = Vector2.ZERO
	current_hp = MAX_HP
	is_active = true
	is_shielding = false
	shield_held = false
	shield_energy = SHIELD_MAX_ENERGY
	shield_exhausted = false
	shield_recharge_timer = 0.0
	shield_block_feedback_timer = 0.0
	shield_block_flash = 0.0
	shield_activation_flash = 0.0
	hit_invincibility_timer = 0.0
	hit_flash_timer = 0.0
	hp_changed.emit(current_hp, MAX_HP)
	shield_changed.emit(false)
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


func _update_visuals(delta: float) -> void:
	if outer_polygon == null or inner_polygon == null:
		return

	_light_pulse_time += maxf(delta, 0.0)
	var damage_pop: float = hit_flash_timer * 0.16
	outer_polygon.scale = Vector2.ONE * (1.0 + damage_pop)
	var blink_on: bool = false
	if hit_invincibility_timer > 0.0 and not is_shielding:
		blink_on = int(hit_invincibility_timer * 16.0) % 2 == 0
		outer_polygon.color = Color(0.35, 0.35, 0.35, 1.0) if blink_on else Color.WHITE
	else:
		outer_polygon.color = Color.WHITE

	var pulse_wave: float = 0.5 + 0.5 * sin(_light_pulse_time * 3.4)
	var speed_ratio: float = clampf(velocity.length() / maxf(move_speed, 1.0), 0.0, 1.0)
	var shield_boost: float = 0.28 if is_shielding else 0.0
	var flash_boost: float = 0.35 * shield_block_flash + 0.25 * shield_activation_flash + 0.22 * hit_flash_timer
	var dim_factor: float = 0.55 if blink_on else 1.0

	if player_glow != null:
		player_glow.visible = is_active
		var glow_alpha: float = clampf((0.36 + 0.06 * pulse_wave + 0.08 * speed_ratio + shield_boost * 0.5 + flash_boost) * dim_factor, 0.0, 0.92)
		player_glow.color = Color(1.0, 1.0, 1.0, glow_alpha)
		var glow_scale: float = 1.0 + 0.05 * pulse_wave + 0.08 * speed_ratio + (0.22 if is_shielding else 0.0) + 0.25 * shield_block_flash + 0.16 * shield_activation_flash + 0.12 * hit_flash_timer
		player_glow.scale = Vector2.ONE * glow_scale

	if player_light != null:
		player_light.enabled = is_active
		player_light.color = Color.WHITE
		player_light.energy = (0.75 + 0.12 * pulse_wave + 0.15 * speed_ratio + shield_boost + flash_boost * 1.4) * dim_factor
		player_light.texture_scale = 1.55 + 0.08 * pulse_wave + (0.30 if is_shielding else 0.0) + 0.35 * shield_block_flash + 0.20 * shield_activation_flash

	if shield_glow != null:
		shield_glow.visible = is_shielding or shield_block_flash > 0.0 or shield_activation_flash > 0.0
		if shield_glow.visible:
			var low_energy: float = 0.0 if shield_energy > 0.25 else (1.0 - shield_energy / 0.25)
			var flicker: float = 1.0 - 0.25 * low_energy * (0.5 + 0.5 * sin(shield_energy * 90.0))
			var glow_alpha: float = (0.10 + 0.10 * shield_block_flash + 0.08 * shield_activation_flash) * flicker
			shield_glow.color = Color(0.72, 0.72, 0.72, glow_alpha)
			shield_glow.scale = Vector2.ONE * (1.0 + 0.18 * shield_block_flash + 0.10 * shield_activation_flash)

	if shield_ring != null:
		shield_ring.visible = is_shielding or shield_block_flash > 0.0 or shield_activation_flash > 0.0
		if shield_ring.visible:
			shield_ring.rotation += delta * (2.4 if is_shielding else 0.8)
			var ring_scale: float = 1.0 + 0.08 * shield_activation_flash - 0.05 * (1.0 - get_shield_energy_ratio())
			ring_scale += 0.10 * shield_block_flash
			shield_ring.scale = Vector2.ONE * ring_scale
			var ring_gray: float = 0.72 + 0.28 * get_shield_energy_ratio()
			var ring_alpha: float = 0.55 + 0.35 * shield_block_flash if is_shielding else shield_block_flash
			shield_ring.default_color = Color(ring_gray, ring_gray, ring_gray, ring_alpha)

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


func _configure_player_lighting() -> void:
	if player_glow != null:
		var glow_mat: CanvasItemMaterial = CanvasItemMaterial.new()
		glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		player_glow.material = glow_mat
		var segments: int = 36
		var radii: Array[float] = [14.0, 22.0, 32.0, 44.0, 56.0, 68.0, 80.0, 92.0]
		var alphas: Array[float] = [0.62, 0.42, 0.25, 0.14, 0.07, 0.03, 0.008, 0.0]
		var verts: PackedVector2Array = PackedVector2Array()
		var colors: PackedColorArray = PackedColorArray()
		verts.append(Vector2.ZERO)
		colors.append(Color(1.0, 1.0, 1.0, 0.85))
		for r_idx: int in range(radii.size()):
			var radius: float = radii[r_idx]
			var alpha: float = alphas[r_idx]
			for s: int in range(segments):
				var angle: float = TAU * float(s) / float(segments)
				verts.append(Vector2.from_angle(angle) * radius)
				colors.append(Color(1.0, 1.0, 1.0, alpha))
		var polys: Array = []
		for s: int in range(segments):
			var next_s: int = (s + 1) % segments
			polys.append(PackedInt32Array([0, 1 + s, 1 + next_s]))
		for r_idx: int in range(radii.size() - 1):
			var inner_start: int = 1 + r_idx * segments
			var outer_start: int = 1 + (r_idx + 1) * segments
			for s: int in range(segments):
				var next_s: int = (s + 1) % segments
				polys.append(PackedInt32Array([
					inner_start + s,
					outer_start + s,
					outer_start + next_s,
					inner_start + next_s,
				]))
		player_glow.polygon = verts
		player_glow.polygons = polys
		player_glow.vertex_colors = colors
		player_glow.color = Color(1.0, 1.0, 1.0, 0.42)

	if player_light != null:
		var grad: Gradient = Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.35, 0.72, 1.0])
		grad.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 1.0),
			Color(0.65, 0.65, 0.65, 0.75),
			Color(0.22, 0.22, 0.22, 0.25),
			Color(0.0, 0.0, 0.0, 0.0),
		])
		var tex: GradientTexture2D = GradientTexture2D.new()
		tex.width = 128
		tex.height = 128
		tex.fill = GradientTexture2D.Fill.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.gradient = grad
		player_light.texture = tex
		player_light.blend_mode = Light2D.BLEND_MODE_ADD
		player_light.color = Color.WHITE
		player_light.energy = 0.85
		player_light.texture_scale = 1.6


func _build_polygon(radius: float, sides: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(sides):
		points.append(Vector2.from_angle(TAU * float(i) / float(sides)) * radius)
	return points


func _build_ring_points(radius: float, segments: int, rotation_offset: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(segments):
		var angle: float = rotation_offset + TAU * float(i) / float(segments)
		points.append(Vector2.from_angle(angle) * radius)
	return points
