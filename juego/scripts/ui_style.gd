extends RefCounted
## Shared monochrome button styling and micro-animations for every screen.

const FOCUS_WHITE: Color = Color(1.0, 1.0, 1.0, 1.0)


static func style_button(btn: Button, font_size: int = 20, margin: int = 12) -> void:
	if btn == null:
		return
	var normal_style: StyleBoxFlat = _box(Color(0.06, 0.06, 0.06, 1.0), Color(0.85, 0.85, 0.85, 1.0), margin)
	var hover_style: StyleBoxFlat = _box(Color.WHITE, Color.WHITE, margin)
	hover_style.shadow_color = Color(1.0, 1.0, 1.0, 0.35)
	hover_style.shadow_size = 14
	var pressed_style: StyleBoxFlat = _box(Color(0.7, 0.7, 0.7, 1.0), Color.WHITE, margin)
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("focus", hover_style)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.BLACK)
	btn.add_theme_color_override("font_hover_color", Color.BLACK)
	btn.add_theme_color_override("font_pressed_color", Color.BLACK)


## Smooth scale-up on hover/focus (pivot kept centred as the layout resizes).
static func add_hover_pop(btn: Button, scale_to: float = 1.06) -> void:
	if btn == null or btn.has_meta(&"hover_pop"):
		return
	btn.set_meta(&"hover_pop", true)
	var center_pivot: Callable = func() -> void:
		btn.pivot_offset = btn.size * 0.5
	btn.resized.connect(center_pivot)
	center_pivot.call()
	var pop: Callable = func(target: float) -> void:
		if not btn.is_inside_tree():
			return
		var tw: Tween = btn.create_tween()
		tw.tween_property(btn, "scale", Vector2.ONE * target, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	btn.mouse_entered.connect(pop.bind(scale_to))
	btn.mouse_exited.connect(pop.bind(1.0))
	btn.focus_entered.connect(pop.bind(scale_to))
	btn.focus_exited.connect(pop.bind(1.0))


static func _box(bg: Color, border: Color, margin: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(2)
	box.set_content_margin_all(margin)
	box.set_corner_radius_all(2)
	return box
