@tool
extends Area2D
## Edge-to-edge rectangular light beam hazard.
## Telegraphs in dim gray (~1s) with no collision, activates as a solid white
## beam with active collision, then disappears.

enum Phase {
	TELEGRAPH,
	ACTIVE,
	FADE_OUT,
}

const DEFAULT_LENGTH: float = 3200.0
const DEFAULT_WIDTH: float = 44.0
const TELEGRAPH_COLOR: Color = Color(0.32, 0.32, 0.32, 0.55)
const TELEGRAPH_LINE_COLOR: Color = Color(0.62, 0.62, 0.62, 0.85)
const ACTIVE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const FADE_COLOR: Color = Color(0.75, 0.75, 0.75, 0.6)

@export var telegraph_duration: float = 1.0
@export var active_duration: float = 0.35
@export var fade_duration: float = 0.2
@export var beam_width: float = DEFAULT_WIDTH
@export var beam_length: float = DEFAULT_LENGTH

var current_phase: Phase = Phase.TELEGRAPH
var phase_timer: float = 0.0
var is_hazard_active: bool = false

@onready var beam_visual: Polygon2D = $BeamVisual
@onready var center_line: Polygon2D = $CenterLine
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	beam_visual = get_node_or_null("BeamVisual") as Polygon2D
	center_line = get_node_or_null("CenterLine") as Polygon2D
	collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	add_to_group("light_beams")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


func configure(
	spawn_pos: Vector2,
	angle_radians: float,
	width: float = DEFAULT_WIDTH,
	warning_time: float = 1.0,
	active_time: float = 0.35
) -> void:
	global_position = spawn_pos
	rotation = angle_radians
	beam_width = width
	telegraph_duration = warning_time
	active_duration = active_time
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances the light beam lifecycle phases (TELEGRAPH -> ACTIVE -> FADE_OUT).
func simulate_physics(delta: float) -> void:
	phase_timer += delta

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
				queue_free()


func _enter_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_timer = 0.0

	match current_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = TELEGRAPH_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = true
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


func _rebuild_geometry() -> void:
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


func _check_player_overlap() -> void:
	if not is_hazard_active or not is_inside_tree():
		return
	for body: Node2D in get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.call("take_damage", 1)


func _on_body_entered(body: Node2D) -> void:
	if is_hazard_active and body.is_in_group("player") and body.has_method("take_damage"):
		body.call("take_damage", 1)
