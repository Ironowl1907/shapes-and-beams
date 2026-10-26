@tool
extends Node2D
## Subtle arena grid and border drawn entirely with primitive lines.
## A short pulse brightens the border when the player blocks or takes a hit,
## giving feedback without external textures.

const GRID_SPACING: float = 96.0
const BASE_GRID: Color = Color(0.055, 0.055, 0.055, 1.0)
const BASE_BORDER: Color = Color(0.18, 0.18, 0.18, 1.0)
const PULSE_COLOR: Color = Color(0.92, 0.92, 0.92, 1.0)

var arena_size: Vector2 = Vector2(1152.0, 648.0)
var pulse_strength: float = 0.0


func _ready() -> void:
	set_process(false)
	queue_redraw()


## Updates the drawn arena extent (called by the level on resize).
func set_arena_size(new_size: Vector2) -> void:
	if new_size.x <= 0.0 or new_size.y <= 0.0:
		return
	arena_size = new_size
	queue_redraw()


## Briefly brightens the arena border for impact feedback.
func pulse(strength: float = 0.5) -> void:
	pulse_strength = clampf(maxf(pulse_strength, strength), 0.0, 1.0)
	if not is_processing():
		set_process(true)


func _process(delta: float) -> void:
	pulse_strength = maxf(0.0, pulse_strength - maxf(delta, 0.0) * 2.6)
	queue_redraw()
	if pulse_strength <= 0.0:
		set_process(false)


func _draw() -> void:
	var width: float = arena_size.x
	var height: float = arena_size.y
	if width <= 1.0 or height <= 1.0:
		return

	var grid_color: Color = BASE_GRID
	grid_color.a = 0.55 + 0.25 * pulse_strength
	var x: float = GRID_SPACING
	while x < width - 1.0:
		draw_line(Vector2(x, 0.0), Vector2(x, height), grid_color, 1.0)
		x += GRID_SPACING
	var y: float = GRID_SPACING
	while y < height - 1.0:
		draw_line(Vector2(0.0, y), Vector2(width, y), grid_color, 1.0)
		y += GRID_SPACING

	var center: Vector2 = Vector2(width * 0.5, height * 0.5)
	var center_color: Color = Color(0.10, 0.10, 0.10, 0.85)
	draw_line(Vector2(center.x, center.y - 18.0), Vector2(center.x, center.y + 18.0), center_color, 1.0)
	draw_line(Vector2(center.x - 18.0, center.y), Vector2(center.x + 18.0, center.y), center_color, 1.0)
	draw_arc(center, minf(width, height) * 0.16, 0.0, TAU, 48, center_color, 1.0, true)

	var border: Color = BASE_BORDER.lerp(PULSE_COLOR, pulse_strength * 0.65)
	draw_rect(Rect2(Vector2.ONE, arena_size - Vector2.ONE * 2.0), border, false, 2.0)
	var tick: float = 16.0
	var tick_color: Color = border
	tick_color.a = 0.9
	for corner: Vector2 in [Vector2(0.0, 0.0), Vector2(width, 0.0), Vector2(0.0, height), Vector2(width, height)]:
		var x_dir: float = 1.0 if corner.x < width * 0.5 else -1.0
		var y_dir: float = 1.0 if corner.y < height * 0.5 else -1.0
		draw_line(corner, corner + Vector2(tick * x_dir, 0.0), tick_color, 3.0)
		draw_line(corner, corner + Vector2(0.0, tick * y_dir), tick_color, 3.0)
