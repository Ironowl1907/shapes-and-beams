@tool
extends McpTestSuite

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const LEVEL_SCENE: PackedScene = preload("res://scenes/level.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const LIGHT_BEAM_SCENE: PackedScene = preload("res://scenes/light_beam.tscn")


func suite_name() -> String:
	return "gameplay"


func test_ac1_and_ac2_main_menu_structure_and_actions() -> void:
	var main_scene_setting: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	assert_eq(main_scene_setting, "res://scenes/main_menu.tscn", "Main scene should be main_menu.tscn")

	var menu: Control = track(MAIN_MENU_SCENE.instantiate()) as Control
	menu._ready()

	var title_label: Label = menu.get_node_or_null("CenterContainer/MenuBox/TitleLabel") as Label
	var play_button: Button = menu.get_node_or_null("CenterContainer/MenuBox/PlayButton") as Button
	var quit_button: Button = menu.get_node_or_null("CenterContainer/MenuBox/QuitButton") as Button

	assert_true(title_label != null, "TitleLabel must exist")
	assert_gt(title_label.text.length(), 0, "TitleLabel must display game title")
	assert_true(play_button != null, "PlayButton must exist")
	assert_eq(play_button.text, "Play", "PlayButton text must be 'Play'")
	assert_true(quit_button != null, "QuitButton must exist")
	assert_eq(quit_button.text, "Quit", "QuitButton text must be 'Quit'")
	assert_true(play_button.pressed.is_connected(menu._on_play_pressed), "PlayButton must connect to _on_play_pressed")
	assert_true(quit_button.pressed.is_connected(menu._on_quit_pressed), "QuitButton must connect to _on_quit_pressed")


func test_ac3_and_ac4_player_movement_and_target_following() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down", "dash"]:
		assert_true(InputMap.has_action(action), "InputMap must have action: " + action)

	var player: CharacterBody2D = track(PLAYER_SCENE.instantiate()) as CharacterBody2D
	player.global_position = Vector2(576.0, 324.0)
	player._ready()

	# Verify target-position following (mouse / future MediaPipe hand-tracking coordinates)
	var target: Vector2 = Vector2(700.0, 250.0)
	player.set_target_position(target, true)
	assert_true(player.use_target_position, "use_target_position should be enabled")
	assert_true(player.external_tracking_active, "external_tracking_active should be enabled")

	for _i: int in range(20):
		player.simulate_physics(0.016)

	var dist: float = player.global_position.distance_to(target)
	assert_true(dist < 5.0, "Player should reach target position (dist=%f)" % dist)

	# Verify screen bounds clamping
	player.set_target_position(Vector2(-500.0, 9999.0), true)
	for _i: int in range(30):
		player.simulate_physics(0.05)
	assert_true(player.global_position.x >= 14.0, "Player X must be clamped within left screen bound")
	assert_true(player.global_position.y <= 648.0 - 14.0, "Player Y must be clamped within bottom screen bound")


func test_ac5_player_dash_and_invincibility() -> void:
	var player: CharacterBody2D = track(PLAYER_SCENE.instantiate()) as CharacterBody2D
	player.global_position = Vector2(300.0, 300.0)
	player._ready()

	var start_x: float = player.global_position.x
	var dash_started: bool = player.trigger_dash(Vector2.RIGHT)
	assert_true(dash_started, "Dash should start")
	assert_true(player.is_dashing, "Player should be in dashing state")
	assert_true(player.is_invincible(), "Player should be invincible while dashing")

	# Taking damage during dash must not reduce HP
	player.take_damage(1)
	assert_eq(player.current_hp, 3, "Dash invincibility must prevent HP loss")

	player.simulate_physics(0.05)
	assert_gt(player.global_position.x, start_x, "Dash should burst move player to the right")

	# Advance past dash duration (0.18s)
	player.simulate_physics(0.15)
	assert_false(player.is_dashing, "Dash should end after DASH_DURATION")


func test_ac6_and_ac7_light_beam_phases_and_collision() -> void:
	var beam: Area2D = track(LIGHT_BEAM_SCENE.instantiate()) as Area2D
	beam._ready()
	beam.configure(Vector2(576.0, 324.0), 0.4, 44.0, 1.0, 0.35)

	var col: CollisionShape2D = beam.get_node("CollisionShape2D") as CollisionShape2D
	var vis: Polygon2D = beam.get_node("BeamVisual") as Polygon2D

	# Phase 0: TELEGRAPH (~1.0s)
	assert_eq(beam.current_phase, 0, "Beam should start in TELEGRAPH phase")
	assert_false(beam.is_hazard_active, "Telegraph phase must have no active hazard")
	assert_true(col.disabled, "CollisionShape2D must be disabled during telegraph")
	assert_true(vis.color.r < 0.8, "Telegraph visual must be dim gray")

	beam.simulate_physics(0.5)
	assert_eq(beam.current_phase, 0, "Beam should still be in TELEGRAPH at 0.5s")
	assert_false(beam.is_hazard_active, "Still no hazard at 0.5s")

	# Advance past 1.0s into ACTIVE phase
	beam.simulate_physics(0.55)
	assert_eq(beam.current_phase, 1, "Beam should transition to ACTIVE phase after 1.0s")
	assert_true(beam.is_hazard_active, "ACTIVE phase must enable hazard")
	assert_false(col.disabled, "CollisionShape2D must be enabled during ACTIVE phase")
	assert_eq(vis.color, Color.WHITE, "ACTIVE beam visual must be solid white")

	# Advance past active_duration (0.35s) into FADE_OUT phase
	beam.simulate_physics(0.4)
	assert_eq(beam.current_phase, 2, "Beam should transition to FADE_OUT phase")
	assert_false(beam.is_hazard_active, "FADE_OUT phase must disable hazard")
	assert_true(col.disabled, "CollisionShape2D must be disabled during FADE_OUT")


func test_ac8_and_ac9_hp_damage_iframes_and_game_over() -> void:
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()

	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	player._ready()
	var game_over_panel: Control = level.get_node("HUD/HUDRoot/GameOverPanel") as Control
	var retry_btn: Button = level.get_node("HUD/HUDRoot/GameOverPanel/VBoxContainer/RetryButton") as Button
	var menu_btn: Button = level.get_node("HUD/HUDRoot/GameOverPanel/VBoxContainer/GameOverMainMenuButton") as Button

	assert_eq(player.current_hp, 3, "Player must start with 3 HP")
	assert_false(game_over_panel.visible, "GameOverPanel must be hidden initially")
	assert_eq(retry_btn.text, "Retry", "Retry button text must be 'Retry'")
	assert_eq(menu_btn.text, "Main Menu", "Main Menu button text must be 'Main Menu'")

	# Hit 1
	player.take_damage(1)
	assert_eq(player.current_hp, 2, "HP should drop to 2")
	assert_true(player.is_invincible(), "Player must gain post-hit invincibility frames")

	# Immediate hit during i-frames must be ignored
	player.take_damage(1)
	assert_eq(player.current_hp, 2, "Post-hit i-frames must block immediate damage")

	# Expire i-frames and take Hit 2
	player.simulate_physics(1.3)
	assert_false(player.is_invincible(), "Post-hit i-frames should expire after 1.2s")
	player.take_damage(1)
	assert_eq(player.current_hp, 1, "HP should drop to 1")

	# Expire i-frames and take Hit 3 -> Game Over
	player.simulate_physics(1.3)
	player.take_damage(1)
	assert_eq(player.current_hp, 0, "HP should reach 0")
	assert_false(level.is_level_running, "Level must stop at 0 HP")
	assert_true(game_over_panel.visible, "GameOverPanel must be displayed at 0 HP")

	# Pressing Retry restarts level
	level._on_retry_pressed()
	assert_true(level.is_level_running, "Retry must restart level")
	assert_eq(player.current_hp, 3, "Retry must restore 3 HP")
	assert_false(game_over_panel.visible, "Retry must hide GameOverPanel")


func test_ac10_level_survival_45_seconds_and_replay() -> void:
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()

	var complete_panel: Control = level.get_node("HUD/HUDRoot/LevelCompletePanel") as Control
	var replay_btn: Button = level.get_node("HUD/HUDRoot/LevelCompletePanel/VBoxContainer/ReplayButton") as Button
	var menu_btn: Button = level.get_node("HUD/HUDRoot/LevelCompletePanel/VBoxContainer/CompleteMainMenuButton") as Button
	var beam_container: Node2D = level.get_node("BeamContainer") as Node2D

	assert_eq(level.level_duration, 45.0, "Level duration must be 45 seconds")
	assert_false(complete_panel.visible, "LevelCompletePanel must be hidden initially")
	assert_eq(replay_btn.text, "Replay", "Replay button text must be 'Replay'")
	assert_eq(menu_btn.text, "Main Menu", "Main Menu button text must be 'Main Menu'")

	# Step into level to verify beams spawn
	level.simulate_physics(0.6)
	assert_gt(beam_container.get_child_count(), 0, "Level must spawn light beam obstacles")

	# Advance to 45.0s completion
	for _i: int in range(90):
		level.simulate_physics(0.5)

	assert_false(level.is_level_running, "Level must stop after surviving 45 seconds")
	assert_eq(beam_container.get_child_count(), 0, "Active beams must be cleared upon level completion")
	assert_true(complete_panel.visible, "LevelCompletePanel must be displayed after 45 seconds")

	# Pressing Replay restarts level
	level._on_replay_pressed()
	assert_true(level.is_level_running, "Replay must restart level")
	assert_eq(level.elapsed_time, 0.0, "Replay must reset elapsed_time to 0")
	assert_false(complete_panel.visible, "Replay must hide LevelCompletePanel")


func test_ac11_monochrome_primitives_only() -> void:
	var scenes: Array[PackedScene] = [MAIN_MENU_SCENE, LEVEL_SCENE, PLAYER_SCENE, LIGHT_BEAM_SCENE]
	for packed: PackedScene in scenes:
		var root: Node = track(packed.instantiate())
		_assert_subtree_monochrome_and_primitive(root)


func _assert_subtree_monochrome_and_primitive(node: Node) -> void:
	assert_false(node is Sprite2D, "External texture Sprite2D is not allowed: " + node.name)
	assert_false(node is TextureRect, "External TextureRect is not allowed: " + node.name)
	assert_false(node is AudioStreamPlayer, "AudioStreamPlayer is out of scope: " + node.name)

	if node is Polygon2D:
		var c: Color = (node as Polygon2D).color
		assert_true(absf(c.r - c.g) < 0.01 and absf(c.g - c.b) < 0.01, "Polygon2D must be grayscale: " + node.name)
	elif node is ColorRect:
		var c: Color = (node as ColorRect).color
		assert_true(absf(c.r - c.g) < 0.01 and absf(c.g - c.b) < 0.01, "ColorRect must be grayscale: " + node.name)

	for child: Node in node.get_children():
		_assert_subtree_monochrome_and_primitive(child)
