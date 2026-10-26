@tool
extends CharacterBody2D
## Player entity for the black-and-white dodge game.
## Supports keyboard movement (WASD/Arrows), frame-rate-independent smoothed 2D
## target-position following (mouse cursor and 30-to-60 FPS MediaPipe hand tracking),
## and a timed defensive shield (1.0s active duration, 1.5s cooldown) that grants
## full damage immunity, destroys contacting projectiles with visual/audio block
## feedback, and preserves 100% normal movement speed with backward-compatible
## dash aliases.

signal hp_changed(new_hp: int, max_hp: int)
signal died
signal dashed
signal shield_activated
signal shield_blocked

const MAX_HP: int = 3
const MOVE_SPEED: float = 420.0
const TARGET_FOLLOW_SPEED: float = 950.0
const TARGET_STOP_DISTANCE: float = 4.0
const TARGET_SMOOTHING_SPEED: float = 28.0
const SHIELD_DURATION: float = 1.0
const SHIELD_COOLDOWN: float = 1.5
const DASH_SPEED: float = MOVE_SPEED
const DASH_DURATION: float = SHIELD_DURATION
const DASH_COOLDOWN: float = SHIELD_COOLDOWN
const HIT_INVINCIBILITY_DURATION: float = 1.2
const PLAYER_HALF_SIZE: float = 14.0
const SHIELD_RING_RADIUS: float = 22.0
const SHIELD_RING_SEGMENTS: int = 16
const RIPPLE_DURATION: float = 0.28
const AUDIO_MIX_RATE: int = 22050

static var _hit_sfx_stream: AudioStreamWAV = null
static var _shield_block_sfx_stream: AudioStreamWAV = null
static var _unit_shield_ring_polygon: PackedVector2Array = PackedVector2Array()
static var _unit_ring_loop_points: PackedVector2Array = PackedVector2Array()

@export var move_speed: float = MOVE_SPEED
@export var target_follow_speed: float = TARGET_FOLLOW_SPEED

var current_hp: int = MAX_HP
var is_active: bool = true

var _shield_active_state: bool = false
var _shield_timer_state: float = 0.0
var _shield_cooldown_state: float = 0.0

var is_shield_active: bool = false:
	get:
		return _shield_active_state
	set(value):
		_shield_active_state = value

var is_dashing: bool = false:
	get:
		return _shield_active_state
	set(value):
		_shield_active_state = value

var shield_timer: float = 0.0:
	get:
		return _shield_timer_state
	set(value):
		_shield_timer_state = value

var dash_timer: float = 0.0:
	get:
		return _shield_timer_state
	set(value):
		_shield_timer_state = value

var shield_cooldown_timer: float = 0.0:
	get:
		return _shield_cooldown_state
	set(value):
		_shield_cooldown_state = value

var dash_cooldown_timer: float = 0.0:
	get:
		return _shield_cooldown_state
	set(value):
		_shield_cooldown_state = value

var dash_direction: Vector2 = Vector2.RIGHT
var last_move_direction: Vector2 = Vector2.RIGHT
var hit_invincibility_timer: float = 0.0
var hit_sfx_play_count: int = 0
var block_sfx_play_count: int = 0
var last_sfx_played: StringName = &""

## Target position used for mouse or external 2D hand-tracking input.
var target_position: Vector2 = Vector2.ZERO
var smoothed_target_position: Vector2 = Vector2.ZERO
var use_target_position: bool = false
var external_tracking_active: bool = false

var ripple_timer: float = 0.0
var shield_block_pulse: float = 0.0
var _visual_time: float = 0.0
var _cooldown_arc_buffer: PackedVector2Array = PackedVector2Array()

@onready var outer_polygon: Polygon2D = $OuterPolygon
@onready var inner_polygon: Polygon2D = $InnerPolygon
@onready var dash_ring: Polygon2D = $DashRing
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sfx_player: AudioStreamPlayer = $SfxPlayer
var cooldown_ring: Line2D = null
var ripple_ring: Line2D = null


func _ready() -> void:
	_resolve_nodes()
	add_to_group("player")
	target_position = global_position
	smoothed_target_position = global_position
	_update_visuals(0.0)


func _resolve_nodes() -> void:
	if not InputMap.has_action("move_left"):
		InputMap.load_from_project_settings()
	_ensure_static_polygons()
	if outer_polygon == null:
		outer_polygon = get_node_or_null("OuterPolygon") as Polygon2D
	if inner_polygon == null:
		inner_polygon = get_node_or_null("InnerPolygon") as Polygon2D
	if dash_ring == null:
		dash_ring = get_node_or_null("DashRing") as Polygon2D
	if collision_shape == null:
		collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if sfx_player == null:
		sfx_player = get_node_or_null("SfxPlayer") as AudioStreamPlayer
	_ensure_polish_nodes()
	if dash_ring != null and dash_ring.polygon.size() != SHIELD_RING_SEGMENTS:
		dash_ring.polygon = _unit_shield_ring_polygon
	if sfx_player != null and sfx_player.stream == null and (not is_inside_tree() or not Engine.is_editor_hint()):
		sfx_player.stream = _get_hit_sfx_stream()


func _ensure_polish_nodes() -> void:
	if cooldown_ring == null:
		cooldown_ring = get_node_or_null("CooldownRing") as Line2D
	if ripple_ring == null:
		ripple_ring = get_node_or_null("RippleRing") as Line2D
	if ripple_ring != null and ripple_ring.points.size() != SHIELD_RING_SEGMENTS + 1:
		ripple_ring.points = _unit_ring_loop_points


static func _ensure_static_polygons() -> void:
	if _unit_shield_ring_polygon.size() == SHIELD_RING_SEGMENTS and _unit_ring_loop_points.size() == SHIELD_RING_SEGMENTS + 1:
		return
	_unit_shield_ring_polygon.resize(SHIELD_RING_SEGMENTS)
	_unit_ring_loop_points.resize(SHIELD_RING_SEGMENTS + 1)
	for i: int in range(SHIELD_RING_SEGMENTS):
		var angle: float = (TAU * float(i)) / float(SHIELD_RING_SEGMENTS)
		var pt: Vector2 = Vector2.from_angle(angle) * SHIELD_RING_RADIUS
		_unit_shield_ring_polygon[i] = pt
		_unit_ring_loop_points[i] = pt
	_unit_ring_loop_points[SHIELD_RING_SEGMENTS] = _unit_shield_ring_polygon[0]


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not is_active:
		return

	if event is InputEventMouseMotion and not external_tracking_active:
		var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		set_target_position(motion_event.position)

	if event.is_action_pressed("dash") or (InputMap.has_action("shield") and event.is_action_pressed("shield")):
		trigger_shield()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances player movement, shield/invincibility timers, exponential target smoothing, and visuals by delta seconds.
func simulate_physics(delta: float) -> void:
	if not is_active:
		velocity = Vector2.ZERO
		return

	_visual_time += maxf(0.0, delta)

	if _shield_cooldown_state > 0.0:
		_shield_cooldown_state = maxf(0.0, _shield_cooldown_state - delta)

	if hit_invincibility_timer > 0.0:
		hit_invincibility_timer = maxf(0.0, hit_invincibility_timer - delta)

	if ripple_timer > 0.0:
		ripple_timer = maxf(0.0, ripple_timer - delta)

	if shield_block_pulse > 0.0:
		shield_block_pulse = maxf(0.0, shield_block_pulse - delta * 4.0)

	if _shield_active_state:
		_shield_timer_state = maxf(0.0, _shield_timer_state - delta)
		if _shield_timer_state <= 0.0:
			_shield_active_state = false

	if not InputMap.has_action("move_left"):
		InputMap.load_from_project_settings()
	var keyboard_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down") if InputMap.has_action("move_left") else Vector2.ZERO
	if keyboard_dir.length_squared() > 0.001 and not external_tracking_active:
		use_target_position = false
		last_move_direction = keyboard_dir.normalized()

	# Movement runs at 100% normal speed whether shield is active or inactive (zero directional burst).
	if use_target_position:
		var smooth_alpha: float = 1.0 - exp(-TARGET_SMOOTHING_SPEED * maxf(delta, 0.001))
		smoothed_target_position = smoothed_target_position.lerp(target_position, smooth_alpha)
		var to_smoothed: Vector2 = smoothed_target_position - global_position
		var raw_distance: float = (target_position - global_position).length()
		var smooth_distance: float = to_smoothed.length()
		if raw_distance > TARGET_STOP_DISTANCE:
			var dir: Vector2 = (to_smoothed / smooth_distance) if smooth_distance > 0.001 else (target_position - global_position).normalized()
			last_move_direction = dir
			var desired_speed: float = minf(target_follow_speed, smooth_distance / maxf(delta, 0.001))
			velocity = dir * desired_speed
		else:
			global_position = target_position
			smoothed_target_position = target_position
			velocity = Vector2.ZERO
	else:
		velocity = keyboard_dir * move_speed
		smoothed_target_position = global_position

	if is_inside_tree() and not Engine.is_editor_hint():
		move_and_slide()
	else:
		global_position += velocity * delta

	_constrain_to_viewport()
	_update_visuals(delta)


## Sets the 2D target position in viewport coordinates for the player to follow.
## Preserves target_position immediately while smoothing intermediate 30-to-60 FPS motion.
func set_target_position(new_target: Vector2, is_external: bool = false) -> void:
	var viewport_size: Vector2 = _get_arena_size()
	var clamped: Vector2 = Vector2(
		clampf(new_target.x, PLAYER_HALF_SIZE, viewport_size.x - PLAYER_HALF_SIZE),
		clampf(new_target.y, PLAYER_HALF_SIZE, viewport_size.y - PLAYER_HALF_SIZE)
	)
	if not use_target_position:
		smoothed_target_position = global_position
	target_position = clamped
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
	if external_tracking_active:
		external_tracking_active = false
		use_target_position = false
		target_position = global_position
		smoothed_target_position = global_position


## Activates the timed defensive shield (1.0s active duration, 1.5s cooldown) with zero velocity burst.
func trigger_shield(override_direction: Vector2 = Vector2.ZERO) -> bool:
	if not is_active or _shield_active_state or _shield_cooldown_state > 0.0:
		return false

	if override_direction.length_squared() > 0.001:
		dash_direction = override_direction.normalized()
		last_move_direction = dash_direction
	elif last_move_direction.length_squared() > 0.001:
		dash_direction = last_move_direction.normalized()
	else:
		dash_direction = Vector2.RIGHT

	_shield_active_state = true
	_shield_timer_state = SHIELD_DURATION
	_shield_cooldown_state = SHIELD_COOLDOWN
	ripple_timer = RIPPLE_DURATION * 0.75
	_update_visuals(0.0)
	dashed.emit()
	shield_activated.emit()
	return true


## Backward-compatible alias for trigger_shield().
func trigger_dash(override_direction: Vector2 = Vector2.ZERO) -> bool:
	return trigger_shield(override_direction)


## Returns true when the player cannot take damage (during active shield or post-hit i-frames).
func is_invincible() -> bool:
	return _shield_active_state or hit_invincibility_timer > 0.0


## Handles blocking and destroying a contacting projectile while the shield is active (AC2 / O2).
func on_shield_block(_impact_pos: Vector2 = Vector2.ZERO) -> bool:
	if not is_active or not _shield_active_state:
		return false
	_play_shield_block_sfx()
	shield_block_pulse = 1.0
	ripple_timer = RIPPLE_DURATION
	_update_visuals(0.0)
	shield_blocked.emit()
	return true


## Applies damage if the player is not currently shielded or in post-hit invincibility frames.
func take_damage(amount: int = 1) -> void:
	if not is_active or is_invincible() or current_hp <= 0 or amount <= 0:
		return

	var prev_hp: int = current_hp
	current_hp = maxi(0, current_hp - amount)
	if current_hp < prev_hp:
		_play_hit_sfx()
		ripple_timer = RIPPLE_DURATION
	hit_invincibility_timer = HIT_INVINCIBILITY_DURATION
	_update_visuals(0.0)
	hp_changed.emit(current_hp, MAX_HP)

	if current_hp <= 0:
		is_active = false
		velocity = Vector2.ZERO
		died.emit()


func _play_hit_sfx() -> void:
	if sfx_player == null:
		sfx_player = get_node_or_null("SfxPlayer") as AudioStreamPlayer
	var stream: AudioStreamWAV = _get_hit_sfx_stream()
	if sfx_player != null:
		sfx_player.stream = stream
		if is_inside_tree() and not Engine.is_editor_hint():
			sfx_player.play()
	hit_sfx_play_count += 1
	last_sfx_played = &"hit"


func _play_shield_block_sfx() -> void:
	if sfx_player == null:
		sfx_player = get_node_or_null("SfxPlayer") as AudioStreamPlayer
	var stream: AudioStreamWAV = _get_shield_block_sfx_stream()
	if sfx_player != null:
		sfx_player.stream = stream
		if is_inside_tree() and not Engine.is_editor_hint():
			sfx_player.play()
	block_sfx_play_count += 1
	last_sfx_played = &"shield_block"


static func _get_hit_sfx_stream() -> AudioStreamWAV:
	if _hit_sfx_stream != null:
		return _hit_sfx_stream
	var sample_count: int = int(AUDIO_MIX_RATE * 0.18)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(320.0, 75.0, progress)
		phase += TAU * freq / float(AUDIO_MIX_RATE)
		var tone: float = 0.65 * signf(sin(phase)) + 0.35 * sin(phase * 0.5)
		var noise: float = sin(float(i * 127 + 31) * 0.43) * cos(float(i * 73) * 0.19)
		var env: float = pow(1.0 - progress, 1.6)
		var sample: float = clampf((tone * 0.7 + noise * 0.3 * (1.0 - progress)) * env * 0.6, -1.0, 1.0)
		data.encode_s16(i * 2, clampi(int(round(sample * 32767.0)), -32768, 32767))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = AUDIO_MIX_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = data
	_hit_sfx_stream = wav
	return _hit_sfx_stream


static func _get_shield_block_sfx_stream() -> AudioStreamWAV:
	if _shield_block_sfx_stream != null:
		return _shield_block_sfx_stream
	var sample_count: int = int(AUDIO_MIX_RATE * 0.12)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(540.0, 980.0, pow(progress, 0.5))
		phase += TAU * freq / float(AUDIO_MIX_RATE)
		var chime: float = 0.7 * sin(phase) + 0.3 * sin(phase * 2.5)
		var env: float = minf(progress * 24.0, 1.0) * pow(1.0 - progress, 1.4)
		var sample: float = clampf(chime * env * 0.52, -1.0, 1.0)
		data.encode_s16(i * 2, clampi(int(round(sample * 32767.0)), -32768, 32767))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = AUDIO_MIX_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = data
	_shield_block_sfx_stream = wav
	return _shield_block_sfx_stream


## Resets player health, position, and states for a fresh level run.
func reset_player(spawn_position: Vector2) -> void:
	global_position = spawn_position
	target_position = spawn_position
	smoothed_target_position = spawn_position
	use_target_position = false
	external_tracking_active = false
	velocity = Vector2.ZERO
	current_hp = MAX_HP
	is_active = true
	_shield_active_state = false
	_shield_timer_state = 0.0
	_shield_cooldown_state = 0.0
	hit_invincibility_timer = 0.0
	ripple_timer = 0.0
	shield_block_pulse = 0.0
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


func _update_visuals(delta: float) -> void:
	_resolve_nodes()
	if outer_polygon == null or inner_polygon == null or dash_ring == null:
		return

	_ensure_static_polygons()
	if dash_ring.polygon.size() != SHIELD_RING_SEGMENTS:
		dash_ring.polygon = _unit_shield_ring_polygon

	dash_ring.visible = _shield_active_state
	if _shield_active_state:
		outer_polygon.color = Color.WHITE
		var pulse: float = 0.5 + 0.5 * sin(_visual_time * 18.0)
		var ring_gray: float = clampf(lerpf(0.78, 1.0, maxf(pulse, shield_block_pulse)), 0.0, 1.0)
		var ring_alpha: float = clampf(lerpf(0.62, 0.95, maxf(pulse, shield_block_pulse)), 0.0, 1.0)
		dash_ring.color = Color(ring_gray, ring_gray, ring_gray, ring_alpha)
		dash_ring.rotation += delta * 3.2
		var ring_scale: float = 1.05 + 0.12 * pulse + 0.22 * shield_block_pulse
		dash_ring.scale = Vector2(ring_scale, ring_scale)
		scale = Vector2(1.08 + 0.08 * shield_block_pulse, 1.08 + 0.08 * shield_block_pulse)
	else:
		dash_ring.scale = Vector2.ONE
		scale = Vector2.ONE
		if hit_invincibility_timer > 0.0:
			var blink_on: bool = int(hit_invincibility_timer * 16.0) % 2 == 0
			outer_polygon.color = Color(0.35, 0.35, 0.35, 1.0) if blink_on else Color.WHITE
		else:
			outer_polygon.color = Color.WHITE

	# Cooldown indicator ring when shield is recharging after active phase
	if cooldown_ring != null:
		if not _shield_active_state and _shield_cooldown_state > 0.0:
			cooldown_ring.visible = true
			var cd_ratio: float = clampf(1.0 - (_shield_cooldown_state / maxf(SHIELD_COOLDOWN, 0.001)), 0.0, 1.0)
			var seg_count: int = maxi(2, int(ceil(float(SHIELD_RING_SEGMENTS) * cd_ratio)) + 1)
			_cooldown_arc_buffer.resize(seg_count)
			for i: int in range(seg_count):
				_cooldown_arc_buffer[i] = _unit_ring_loop_points[mini(i, SHIELD_RING_SEGMENTS)]
			cooldown_ring.points = _cooldown_arc_buffer
			cooldown_ring.default_color = Color(0.46, 0.46, 0.46, 0.55)
		else:
			cooldown_ring.visible = false

	# Expanding ripple ring for shield block / shield activate / hit feedback
	if ripple_ring != null:
		if ripple_timer > 0.0:
			ripple_ring.visible = true
			var r_progress: float = clampf(1.0 - (ripple_timer / maxf(RIPPLE_DURATION, 0.001)), 0.0, 1.0)
			var r_scale: float = lerpf(0.95, 2.15, r_progress)
			ripple_ring.scale = Vector2(r_scale, r_scale)
			var r_gray: float = 0.92 if shield_block_pulse > 0.0 else 0.72
			var r_alpha: float = (1.0 - r_progress) * 0.78
			ripple_ring.default_color = Color(r_gray, r_gray, r_gray, r_alpha)
		else:
			ripple_ring.visible = false

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
