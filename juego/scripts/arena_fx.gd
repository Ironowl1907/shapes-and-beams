@tool
extends Node2D
## Lightweight pooled visual-effects layer.
##
## All sparks and shockwaves are drawn by this single node instead of spawning
## one node per particle, which keeps draw calls low while adding readable
## hit/shield feedback.

const DEFAULT_SHARD_COLOR: Color = Color(0.92, 0.92, 0.92, 1.0)

var _shards: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_process(false)


## Emits a radial burst of short line shards.
func spawn_burst(
	origin: Vector2,
	count: int = 10,
	speed: float = 260.0,
	shard_color: Color = DEFAULT_SHARD_COLOR,
	duration: float = 0.38,
	shard_length: float = 9.0,
	width: float = 2.0
) -> void:
	if count <= 0:
		return
	var safe_count: int = mini(count, 40)
	for i: int in range(safe_count):
		var angle: float = _rng.randf_range(0.0, TAU)
		var shard_speed: float = speed * _rng.randf_range(0.55, 1.25)
		_shards.append({
			"pos": origin,
			"vel": Vector2.from_angle(angle) * shard_speed,
			"life": duration * _rng.randf_range(0.75, 1.15),
			"max_life": duration,
			"length": shard_length * _rng.randf_range(0.65, 1.2),
			"color": shard_color,
			"width": width,
		})
	if not is_processing():
		set_process(true)


## Emits an expanding ring (shield block, explosion, level complete).
func spawn_ring(
	origin: Vector2,
	start_radius: float = 8.0,
	end_radius: float = 70.0,
	duration: float = 0.42,
	ring_color: Color = DEFAULT_SHARD_COLOR,
	width: float = 2.0
) -> void:
	_rings.append({
		"pos": origin,
		"start_radius": start_radius,
		"end_radius": end_radius,
		"life": duration,
		"max_life": duration,
		"color": ring_color,
		"width": width,
	})
	if not is_processing():
		set_process(true)


## Removes every active effect immediately (used when restarting a level).
func clear() -> void:
	_shards.clear()
	_rings.clear()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	var safe_delta: float = maxf(delta, 0.0)
	for shard: Dictionary in _shards:
		shard["life"] = float(shard["life"]) - safe_delta
		shard["pos"] = Vector2(shard["pos"]) + Vector2(shard["vel"]) * safe_delta
		shard["vel"] = Vector2(shard["vel"]) * (1.0 - minf(3.2 * safe_delta, 0.9))
	for i: int in range(_shards.size() - 1, -1, -1):
		if float(_shards[i]["life"]) <= 0.0:
			_shards.remove_at(i)

	for ring: Dictionary in _rings:
		ring["life"] = float(ring["life"]) - safe_delta
	for i: int in range(_rings.size() - 1, -1, -1):
		if float(_rings[i]["life"]) <= 0.0:
			_rings.remove_at(i)

	queue_redraw()
	if _shards.is_empty() and _rings.is_empty():
		set_process(false)


func _draw() -> void:
	for shard: Dictionary in _shards:
		var max_life: float = maxf(float(shard["max_life"]), 0.001)
		var alpha: float = clampf(float(shard["life"]) / max_life, 0.0, 1.0)
		var shard_color: Color = shard["color"]
		shard_color.a *= alpha
		var pos: Vector2 = shard["pos"]
		var vel: Vector2 = shard["vel"]
		var dir: Vector2 = vel.normalized() if vel.length_squared() > 0.001 else Vector2.RIGHT
		draw_line(pos, pos - dir * float(shard["length"]), shard_color, float(shard["width"]), true)

	for ring: Dictionary in _rings:
		var max_life: float = maxf(float(ring["max_life"]), 0.001)
		var progress: float = 1.0 - clampf(float(ring["life"]) / max_life, 0.0, 1.0)
		var radius: float = lerpf(float(ring["start_radius"]), float(ring["end_radius"]), ease(progress, 0.35))
		var ring_color: Color = ring["color"]
		ring_color.a *= pow(1.0 - progress, 1.2)
		var ring_pos: Vector2 = ring["pos"]
		draw_arc(ring_pos, radius, 0.0, TAU, 40, ring_color, float(ring["width"]), true)


## Emits a one-shot CPUParticles2D burst (GPU-free, works in every renderer).
## Auto-frees when finished. Grayscale only.
func emit_particles(
	origin: Vector2,
	amount: int = 24,
	particle_color: Color = Color(1.0, 1.0, 1.0, 0.9),
	speed: float = 220.0,
	lifetime: float = 0.7,
	size: float = 3.0
) -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var p: CPUParticles2D = CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = clampi(amount, 1, 80)
	p.lifetime = lifetime
	p.position = origin
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.6
	p.damping_max = speed * 1.1
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var fade: Gradient = Gradient.new()
	fade.colors = PackedColorArray([particle_color, Color(particle_color.r, particle_color.g, particle_color.b, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 1.0])
	p.color_ramp = fade
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
