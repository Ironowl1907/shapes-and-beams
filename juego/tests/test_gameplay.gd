@tool
extends McpTestSuite

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const LEVEL_SCENE: PackedScene = preload("res://scenes/level.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const LIGHT_BEAM_SCENE: PackedScene = preload("res://scenes/light_beam.tscn")
const LIGHT_BEAM_SCRIPT: GDScript = preload("res://scripts/light_beam.gd")
const HAND_TRACKING_CLIENT_SCRIPT: GDScript = preload("res://scripts/hand_tracking_client.gd")


func suite_name() -> String:
	return "gameplay"


func assert_lt(a: float, b: float, message: String = "") -> void:
	assert_true(a < b, message)


func test_ac1_and_ac2_main_menu_structure_and_actions() -> void:
	var main_scene_setting: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	assert_eq(main_scene_setting, "res://scenes/main_menu.tscn", "Main scene should be main_menu.tscn")

	var menu: Control = track(MAIN_MENU_SCENE.instantiate()) as Control
	menu._ready()

	var title_label: Label = menu.get_node_or_null("CenterContainer/MenuBox/TitleLabel") as Label
	var difficulty_button: Button = menu.get_node_or_null("CenterContainer/MenuBox/DifficultyButton") as Button
	var play_button: Button = menu.get_node_or_null("CenterContainer/MenuBox/PlayButton") as Button
	var quit_button: Button = menu.get_node_or_null("CenterContainer/MenuBox/QuitButton") as Button

	assert_true(title_label != null, "TitleLabel must exist")
	assert_gt(title_label.text.length(), 0, "TitleLabel must display game title")
	assert_true(difficulty_button != null, "DifficultyButton must exist")
	assert_eq(difficulty_button.text, "Difficulty: Normal", "DifficultyButton should default to Normal")
	assert_true(play_button != null, "PlayButton must exist")
	assert_eq(play_button.text, "Play", "PlayButton text must be 'Play'")
	assert_true(quit_button != null, "QuitButton must exist")
	assert_eq(quit_button.text, "Quit", "QuitButton text must be 'Quit'")
	assert_true(difficulty_button.pressed.is_connected(menu._on_difficulty_pressed), "DifficultyButton must connect to _on_difficulty_pressed")
	assert_true(play_button.pressed.is_connected(menu._on_play_pressed), "PlayButton must connect to _on_play_pressed")
	assert_true(quit_button.pressed.is_connected(menu._on_quit_pressed), "QuitButton must connect to _on_quit_pressed")

	# Verify single toggle button cycles Normal -> Hard -> Easy -> Normal
	menu._on_difficulty_pressed()
	assert_eq(menu.selected_difficulty, 2, "First press should select Hard (2)")
	assert_eq(difficulty_button.text, "Difficulty: Hard", "DifficultyButton should display Hard")

	menu._on_difficulty_pressed()
	assert_eq(menu.selected_difficulty, 0, "Second press should select Easy (0)")
	assert_eq(difficulty_button.text, "Difficulty: Easy", "DifficultyButton should display Easy")

	menu._on_difficulty_pressed()
	assert_eq(menu.selected_difficulty, 1, "Third press should select Normal (1)")
	assert_eq(difficulty_button.text, "Difficulty: Normal", "DifficultyButton should display Normal")

	if Engine.has_meta(&"selected_difficulty"):
		Engine.remove_meta(&"selected_difficulty")


func test_ac3_and_ac4_player_movement_and_target_following() -> void:
	var player: CharacterBody2D = track(PLAYER_SCENE.instantiate()) as CharacterBody2D
	player.global_position = Vector2(576.0, 324.0)
	player._ready()

	for action: String in ["move_left", "move_right", "move_up", "move_down", "dash", "shield"]:
		assert_true(InputMap.has_action(action), "InputMap must have action: " + action)

	# Verify target-position following (mouse / MediaPipe hand-tracking coordinates)
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

	var start_pos: Vector2 = player.global_position
	var shield_started: bool = player.trigger_dash(Vector2.RIGHT)
	assert_true(shield_started, "Shield/dash trigger should start")
	assert_true(player.is_shield_active, "Player is_shield_active must be true")
	assert_true(player.is_dashing, "Backward-compatible alias is_dashing must be true")
	assert_eq(player.shield_timer, 1.0, "Shield duration must be 1.0s (SHIELD_DURATION)")
	assert_eq(player.dash_timer, 1.0, "Alias dash_timer must match 1.0s shield_timer")
	assert_eq(player.shield_cooldown_timer, 1.5, "Shield cooldown must be 1.5s (SHIELD_COOLDOWN)")
	assert_eq(player.dash_cooldown_timer, 1.5, "Alias dash_cooldown_timer must match 1.5s")
	assert_true(player.is_invincible(), "Player should be invincible while shield is active")

	# Taking damage during active shield must not reduce HP
	player.take_damage(1)
	assert_eq(player.current_hp, 3, "Shield invincibility must prevent HP loss")

	# Stationary player with no movement input must NOT have a directional velocity burst (AC1 / O1)
	player.simulate_physics(0.25)
	assert_eq(player.global_position, start_pos, "Shield activation must not apply a directional velocity burst when stationary")
	assert_true(player.is_shield_active, "Shield must remain active at 0.25s (< 1.0s)")

	# While shielded, moving toward a target preserves 100% normal movement speed
	player.set_target_position(Vector2(500.0, 300.0), false)
	player.simulate_physics(0.10)
	assert_gt(player.global_position.x, start_pos.x, "Player must move at normal speed while shield is active")

	# Advance past 1.0s shield duration (0.25 + 0.10 + 0.70 = 1.05s)
	player.simulate_physics(0.70)
	assert_false(player.is_shield_active, "Shield must end after 1.0s SHIELD_DURATION")
	assert_false(player.is_dashing, "is_dashing alias must also be false after 1.0s")
	assert_gt(player.shield_cooldown_timer, 0.0, "1.5s cooldown must still be active right after 1.0s shield expires")
	assert_false(player.trigger_shield(), "Shield must not re-activate while on cooldown")

	# Advance past remaining cooldown (0.50s -> total 1.55s > 1.5s)
	player.simulate_physics(0.50)
	assert_eq(player.shield_cooldown_timer, 0.0, "Shield cooldown must reach 0.0 after 1.5s")
	assert_true(player.trigger_shield(), "trigger_shield() must succeed once 1.5s cooldown expires")


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
		root._ready()
		_assert_subtree_monochrome_and_primitive(root)


func test_difficulty_modes_scaling_and_persistence() -> void:
	# Verify standalone Level defaults to Normal (1)
	if Engine.has_meta(&"selected_difficulty"):
		Engine.remove_meta(&"selected_difficulty")

	var standalone_level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	standalone_level._ready()
	assert_eq(standalone_level.difficulty_mode, 1, "Standalone level must default to Normal (1)")

	# Verify cross-scene difficulty transfer via MainMenu -> Level (O3)
	var menu: Control = track(MAIN_MENU_SCENE.instantiate()) as Control
	menu._ready()
	menu.set_difficulty(2) # Hard
	menu._on_play_pressed()

	var hard_level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	hard_level._ready()
	hard_level.restart_level()
	assert_eq(hard_level.difficulty_mode, 2, "Level should initialize with Hard difficulty selected on MainMenu")

	# Verify Retry and Replay preserve selected difficulty (AC4 / O3)
	hard_level._on_retry_pressed()
	assert_eq(hard_level.difficulty_mode, 2, "Retry must preserve Hard difficulty")
	hard_level._on_replay_pressed()
	assert_eq(hard_level.difficulty_mode, 2, "Replay must preserve Hard difficulty")

	# Verify difficulty scales attack spawn frequency while spawning all 9 hazard/enemy types across Easy, Normal, Hard (AC6 / O3)
	var counts_by_mode: Dictionary = {}
	for mode: int in [0, 1, 2]:
		var lvl: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
		lvl._ready()
		lvl.set_difficulty(mode)
		lvl.restart_level()

		var p: CharacterBody2D = lvl.get_node("Player") as CharacterBody2D
		p._ready()
		assert_eq(p.current_hp, 3, "Player HP must be 3 in difficulty mode %d" % mode)
		assert_eq(lvl.level_duration, 45.0, "Level duration must be 45s in difficulty mode %d" % mode)

		var seen_types: Dictionary = {}
		var beam_container: Node2D = lvl.get_node("BeamContainer") as Node2D
		for _step: int in range(60):
			lvl.simulate_physics(0.2)
			for child: Node in beam_container.get_children():
				var htype: int = int(child.get("hazard_type"))
				seen_types[htype] = true

		counts_by_mode[mode] = lvl.wave_index
		for expected_type: int in range(9):
			assert_true(seen_types.has(expected_type), "Difficulty %d must spawn hazard/enemy type %d" % [mode, expected_type])

	assert_gt(int(counts_by_mode[1]), int(counts_by_mode[0]), "Normal must spawn more waves than Easy")
	assert_gt(int(counts_by_mode[2]), int(counts_by_mode[1]), "Hard must spawn more waves than Normal")


func test_filling_circle_patterns_and_phases() -> void:
	for fill_mode: int in [0, 1, 2]:
		var circle: Area2D = track(LIGHT_BEAM_SCENE.instantiate()) as Area2D
		circle._ready()
		circle.configure_circle(Vector2(400.0, 300.0), 80.0, fill_mode, 1.0, 0.35)

		var col: CollisionShape2D = circle.get_node("CollisionShape2D") as CollisionShape2D
		var shadow_vis: Polygon2D = circle.get_node("BeamVisual") as Polygon2D
		var fill_vis: Polygon2D = circle.get_node("CenterLine") as Polygon2D

		assert_eq(int(circle.hazard_type), 1, "Hazard type must be CIRCLE (1)")
		assert_eq(int(circle.circle_fill_mode), fill_mode, "Circle fill mode must match configured pattern")
		assert_eq(circle.current_phase, 0, "Circle must start in TELEGRAPH phase")
		assert_false(circle.is_hazard_active, "Circle must not deal damage while filling")
		assert_true(col.disabled, "Circle collision must be disabled while filling")
		assert_true(col.shape is CircleShape2D, "Circle collision shape must be CircleShape2D")
		assert_eq((col.shape as CircleShape2D).radius, 80.0, "Circle collision radius must match full radius")
		assert_gt(shadow_vis.polygon.size(), 8, "Shadow visual must be a circular polygon")

		# Step halfway through fill (~0.5s)
		circle.simulate_physics(0.5)
		assert_eq(circle.current_phase, 0, "Circle must still be filling at 0.5s")
		assert_false(circle.is_hazard_active, "Circle collision must remain inactive at 50% fill")
		assert_true(col.disabled, "CollisionShape2D must remain disabled at 50% fill")
		assert_true(fill_vis.visible, "Fill progress visual must be visible while filling")
		assert_gt(fill_vis.polygon.size(), 2, "Fill polygon must have vertices for mode %d" % fill_mode)

		# Complete fill (>1.0s) -> ACTIVE solid-white burst (~0.35s)
		circle.simulate_physics(0.55)
		assert_eq(circle.current_phase, 1, "Circle must enter ACTIVE phase at 100% fill")
		assert_true(circle.is_hazard_active, "Circle must activate hazard at 100% fill")
		assert_false(col.disabled, "Circle collision must be enabled at 100% fill")
		assert_eq(shadow_vis.color, Color.WHITE, "Active circle burst must be solid white")

		# Step past 0.35s active burst -> FADE_OUT
		circle.simulate_physics(0.4)
		assert_eq(circle.current_phase, 2, "Circle must enter FADE_OUT after ~0.35s active burst")
		assert_false(circle.is_hazard_active, "Circle hazard must deactivate during FADE_OUT")
		assert_true(col.disabled, "Circle collision must disable during FADE_OUT")


func test_edge_projectiles_and_offscreen_despawn() -> void:
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()
	var beam_container: Node2D = level.get_node("BeamContainer") as Node2D
	var arena: Vector2 = Vector2(1152.0, 648.0)

	# Verify spawning from all 4 screen edges (Top=0, Right=1, Bottom=2, Left=3)
	for edge: int in range(4):
		var proj: Area2D = level.spawn_edge_projectile(edge, 400.0, 10.0)
		var col: CollisionShape2D = proj.get_node("CollisionShape2D") as CollisionShape2D
		var vis: Polygon2D = proj.get_node("BeamVisual") as Polygon2D

		assert_eq(int(proj.hazard_type), 2, "Edge projectile must have hazard_type PROJECTILE (2)")
		assert_eq(proj.current_phase, 1, "Un-telegraphed projectile must start immediately in ACTIVE phase")
		assert_true(proj.is_hazard_active, "Un-telegraphed projectile must have immediate active hazard")
		assert_false(col.disabled, "Un-telegraphed projectile must have immediate active collision")
		assert_eq(vis.color, Color.WHITE, "Un-telegraphed projectile must be solid white")

		match edge:
			0:
				assert_eq(proj.global_position.y, 0.0, "Edge 0 projectile must spawn on top edge")
			1:
				assert_eq(proj.global_position.x, arena.x, "Edge 1 projectile must spawn on right edge")
			2:
				assert_eq(proj.global_position.y, arena.y, "Edge 2 projectile must spawn on bottom edge")
			3:
				assert_eq(proj.global_position.x, 0.0, "Edge 3 projectile must spawn on left edge")

	# Verify straight-line travel and automatic despawn once outside viewport bounds (AC7 / O5)
	level._clear_beams()
	var fast_proj: Area2D = level.spawn_projectile(Vector2(1140.0, 324.0), Vector2.RIGHT, 500.0, 10.0)
	var start_pos: Vector2 = fast_proj.global_position
	fast_proj.simulate_physics(0.05)
	assert_gt(fast_proj.global_position.x, start_pos.x, "Projectile must move in straight line along direction")
	assert_eq(beam_container.get_child_count(), 1, "Projectile inside bounds should remain in BeamContainer")

	# Step past viewport bound + margin (64px)
	fast_proj.simulate_physics(0.5)
	assert_eq(beam_container.get_child_count(), 0, "Projectile must despawn after exiting viewport bounds")


func test_exploding_object_telegraph_and_radial_burst() -> void:
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()
	level._clear_beams()

	var beam_container: Node2D = level.get_node("BeamContainer") as Node2D
	var spawn_pos: Vector2 = Vector2(576.0, 324.0)
	var exploder: Area2D = level.spawn_exploder(spawn_pos, 1.0, 8, 380.0)
	var col: CollisionShape2D = exploder.get_node("CollisionShape2D") as CollisionShape2D

	assert_eq(int(exploder.hazard_type), 3, "Hazard type must be EXPLODER (3)")
	assert_eq(exploder.current_phase, 0, "Exploder must start in TELEGRAPH phase")
	assert_false(exploder.is_hazard_active, "Exploder must be non-damaging during telegraph")
	assert_true(col.disabled, "Exploder collision must be disabled during telegraph")

	# Stationary during ~1.0s telegraph
	exploder.simulate_physics(0.5)
	assert_eq(exploder.global_position, spawn_pos, "Exploder must remain stationary during telegraph")
	assert_false(exploder.is_hazard_active, "Exploder must still be non-damaging at 0.5s")
	assert_eq(beam_container.get_child_count(), 1, "Exploder must not detonate before 1.0s")

	# Detonate at 1.0s into 8 radial projectiles parented to BeamContainer (AC8 / O2)
	exploder.simulate_physics(0.55)
	assert_eq(beam_container.get_child_count(), 8, "Exploder must detonate into 8 radial projectiles and disappear")

	for child: Node in beam_container.get_children():
		var proj: Area2D = child as Area2D
		assert_true(proj != null, "Burst child must be Area2D")
		assert_eq(int(proj.get("hazard_type")), 2, "Burst child must be configured as PROJECTILE (2)")
		assert_true(bool(proj.get("is_hazard_active")), "Burst projectile must be immediately active")


func test_shield_blocks_and_destroys_projectiles_only() -> void:
	# AC2 & O2: Active shield grants 0 damage from all hazards, destroys contacting projectiles with shield_block SFX, and keeps non-projectiles intact
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()
	level._clear_beams()

	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	var beam_container: Node2D = level.get_node("BeamContainer") as Node2D
	player.global_position = Vector2(576.0, 324.0)

	# Activate player shield
	assert_true(player.trigger_shield(), "Player shield must activate")
	assert_true(player.is_shield_active, "Player shield must be active")

	# Spawn projectile approaching shielded player, then step into impact
	var proj: Area2D = level.spawn_projectile(Vector2(530.0, 324.0), Vector2.RIGHT, 400.0, 10.0)
	assert_eq(beam_container.get_child_count(), 1, "Projectile must be in BeamContainer before impact")
	proj.simulate_physics(0.10)

	assert_eq(beam_container.get_child_count(), 0, "Contacting projectile must despawn on shield impact (AC2/O2)")
	assert_eq(player.current_hp, 3, "Shielded player must take 0 damage from projectile (AC2)")
	assert_eq(player.block_sfx_play_count, 1, "Blocking projectile must increment block_sfx_play_count (O2)")
	assert_eq(player.last_sfx_played, &"shield_block", "Blocking projectile must record shield_block SFX (O2)")
	assert_eq(player.hit_sfx_play_count, 0, "Blocking projectile must not increment hit_sfx_play_count (O2)")

	# Spawn non-projectile hazards (BEAM, SAW, CHASER) onto shielded player -> 0 damage and hazard does NOT despawn
	var beam: Area2D = level.spawn_beam(player.global_position, 0.0, 44.0, 0.2, 0.5)
	var saw: Area2D = level.spawn_saw(player.global_position, Vector2.ZERO, 0.0, 36.0, 0.2, 1.0, 0)
	var chaser: Area2D = level.spawn_chaser(player.global_position, 200.0, 0.2, 2.0)
	assert_eq(beam_container.get_child_count(), 3, "3 non-projectile hazards must be in BeamContainer")

	beam.simulate_physics(0.25)
	saw.simulate_physics(0.25)
	chaser.simulate_physics(0.25)

	assert_eq(player.current_hp, 3, "Shielded player must take 0 damage from non-projectile hazards and enemies (AC2)")
	assert_eq(beam_container.get_child_count(), 3, "Non-projectile hazards must remain intact on shield contact (O2)")


func test_closing_walls_telegraph_slam_safe_corridor_and_retract() -> void:
	# AC3 & O3: Closing Walls telegraph along arena borders, slam inward leaving a collision-free safe corridor, hold, and retract
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()
	level._clear_beams()

	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	var beam_container: Node2D = level.get_node("BeamContainer") as Node2D

	# Spawn horizontal closing walls (axis=0) with safe corridor at Y = 324.0 (gap_size = 136.0 -> Y in [256, 392])
	var walls: Area2D = level.spawn_closing_walls(0, 324.0, 136.0, 1.0, 0.45)
	var col_a: CollisionShape2D = walls.get_node("CollisionShape2D") as CollisionShape2D
	var col_b: CollisionShape2D = walls.get_node("SecondaryCollision") as CollisionShape2D
	var vis_a: Polygon2D = walls.get_node("BeamVisual") as Polygon2D
	var vis_b: Polygon2D = walls.get_node("SecondaryVisual") as Polygon2D

	assert_eq(int(walls.hazard_type), 4, "Hazard type must be CLOSING_WALLS (4)")
	assert_eq(walls.current_phase, 0, "Closing walls must start in TELEGRAPH phase")
	assert_false(walls.is_hazard_active, "Closing walls must be non-damaging during telegraph")
	assert_true(col_a.disabled and col_b.disabled, "Both wall collision shapes must be disabled during telegraph")
	assert_true(vis_a.visible and vis_b.visible, "Both opposing wall visuals must be visible")

	# Player inside safe corridor (Y = 324.0) takes 0 damage when walls slam into ACTIVE phase
	player.global_position = Vector2(576.0, 324.0)
	assert_true(bool(walls.call("is_point_in_safe_corridor", player.global_position)), "Center point must lie inside safe corridor")
	walls.simulate_physics(1.05)
	assert_eq(walls.current_phase, 1, "Closing walls must transition to ACTIVE slam phase after 1.0s")
	assert_true(walls.is_hazard_active, "Closing walls must be active during slam")
	assert_false(col_a.disabled or col_b.disabled, "Both wall collision shapes must be enabled during ACTIVE phase")
	assert_eq(player.current_hp, 3, "Player inside safe corridor gap must take 0 damage during active slam (AC3/O3)")

	# Move player into top crushing wall slab (Y = 80.0) during ACTIVE phase -> takes damage
	player.global_position = Vector2(576.0, 80.0)
	assert_false(bool(walls.call("is_point_in_safe_corridor", player.global_position)), "Point inside wall slab must not be in safe corridor")
	walls.simulate_physics(0.05)
	assert_eq(player.current_hp, 2, "Player inside crushing wall segment must take damage (AC3/O3)")

	# Advance past active_duration (0.45s) into FADE_OUT retraction and despawn
	walls.simulate_physics(0.45)
	assert_eq(walls.current_phase, 2, "Closing walls must enter FADE_OUT retraction phase")
	assert_false(walls.is_hazard_active, "Closing walls must deactivate hazard during retraction")
	walls.simulate_physics(0.25)
	assert_eq(beam_container.get_child_count(), 0, "Closing walls must despawn after FADE_OUT")


func test_rotating_hazard_saws_telegraph_traverse_bounce_and_despawn() -> void:
	# AC4 & O3: Toothed monochrome Polygon2D saw telegraphs, spins, traverses/bounces across arena, and despawns
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()
	level._clear_beams()

	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	var beam_container: Node2D = level.get_node("BeamContainer") as Node2D
	player.global_position = Vector2(576.0, 500.0)

	var saw: Area2D = level.spawn_saw(Vector2(1120.0, 200.0), Vector2.RIGHT, 400.0, 36.0, 0.85, 1.5, 1)
	var vis: Polygon2D = saw.get_node("BeamVisual") as Polygon2D
	var col: CollisionShape2D = saw.get_node("CollisionShape2D") as CollisionShape2D

	assert_eq(int(saw.hazard_type), 5, "Hazard type must be SAW (5)")
	assert_eq(saw.current_phase, 0, "Saw must start in TELEGRAPH phase")
	assert_false(saw.is_hazard_active, "Saw must not damage player during telegraph")
	assert_true(col.disabled, "Saw collision must be disabled during telegraph")
	assert_eq(vis.polygon.size(), 24, "Saw must be rendered as a 24-vertex toothed Polygon2D (AC4)")

	# Step past 0.85s telegraph into ACTIVE phase
	var rot_before: float = saw.rotation
	saw.simulate_physics(0.90)
	assert_eq(saw.current_phase, 1, "Saw must enter ACTIVE phase after telegraph")
	assert_true(saw.is_hazard_active, "Saw must be active after telegraph")
	assert_gt(saw.rotation, rot_before, "Saw must continuously rotate")

	# Step so saw hits right arena border (1152 - 36 = 1116) and bounces left (saw_velocity.x < 0)
	saw.simulate_physics(0.10)
	assert_lt(saw.saw_velocity.x, 0.0, "Saw must bounce off right arena border and reverse X velocity (AC4)")
	assert_eq(saw.saw_bounces_remaining, 0, "Saw bounce count must decrement on border bounce")

	# Step past active_duration (1.5s) and FADE_OUT (0.2s) -> despawn
	saw.simulate_physics(1.50)
	assert_eq(saw.current_phase, 2, "Saw must enter FADE_OUT after active_duration")
	saw.simulate_physics(0.25)
	assert_eq(beam_container.get_child_count(), 0, "Saw must despawn after FADE_OUT")


func test_enemy_archetypes_chaser_charger_and_turret() -> void:
	# AC5(a,b,c) & O3: Chaser homing drone, Charger straight-line dasher, and Turret aiming sniper
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()
	level._clear_beams()

	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	var beam_container: Node2D = level.get_node("BeamContainer") as Node2D

	# (a) Chaser / Homing Drone: telegraphs (~0.85s) and steers toward player for fixed lifetime (~3.2s)
	player.global_position = Vector2(500.0, 300.0)
	var chaser: Area2D = level.spawn_chaser(Vector2(200.0, 300.0), 260.0, 0.85, 3.2, 18.0)
	assert_eq(int(chaser.hazard_type), 6, "Hazard type must be CHASER (6)")
	assert_eq(chaser.current_phase, 0, "Chaser must start in TELEGRAPH phase")

	chaser.simulate_physics(0.90)
	assert_eq(chaser.current_phase, 1, "Chaser must enter ACTIVE phase after telegraph")
	var dist_before: float = chaser.global_position.distance_to(player.global_position)
	chaser.simulate_physics(0.30)
	var dist_after: float = chaser.global_position.distance_to(player.global_position)
	assert_lt(dist_after, dist_before, "Chaser must steer and move closer to player during ACTIVE phase (AC5a)")

	# Move player vertically to (500, 120) and verify Chaser steers upward (chaser_velocity.y < 0)
	player.global_position = Vector2(500.0, 120.0)
	chaser.simulate_physics(0.25)
	assert_lt(chaser.chaser_velocity.y, 0.0, "Chaser must dynamically steer toward new player Y position (AC5a)")

	# Expire Chaser fixed lifetime (~3.2s) -> FADE_OUT -> despawn
	chaser.simulate_physics(2.80)
	assert_eq(chaser.current_phase, 2, "Chaser must enter FADE_OUT after fixed lifetime")
	chaser.simulate_physics(0.25)
	assert_eq(beam_container.get_child_count(), 0, "Chaser must despawn after FADE_OUT")

	# (b) Charger / Dasher: rotates/locks onto player during telegraph (~1.0s) and lunges rapidly in a straight line
	player.global_position = Vector2(600.0, 200.0)
	var charger: Area2D = level.spawn_charger(Vector2(200.0, 200.0), 780.0, 1.0, 0.85, 20.0)
	var charger_line: Polygon2D = charger.get_node("CenterLine") as Polygon2D
	assert_eq(int(charger.hazard_type), 7, "Hazard type must be CHARGER (7)")
	assert_eq(charger.current_phase, 0, "Charger must start in TELEGRAPH phase")
	assert_true(charger_line.visible, "Charger must show aim/lunge line during telegraph")

	# Move player to (200, 500) during telegraph -> Charger rotates to lock onto new downward direction
	player.global_position = Vector2(200.0, 500.0)
	charger.simulate_physics(0.50)
	assert_gt(charger.charger_direction.y, 0.9, "Charger must rotate to track player during telegraph (AC5b)")

	# Enter ACTIVE phase -> locks direction and lunges rapidly downward even if player moves away
	charger.simulate_physics(0.55)
	assert_eq(charger.current_phase, 1, "Charger must enter ACTIVE lunge phase after 1.0s telegraph")
	var locked_dir: Vector2 = charger.charger_direction
	player.global_position = Vector2(900.0, 100.0)
	var y_before_lunge: float = charger.global_position.y
	charger.simulate_physics(0.20)
	assert_eq(charger.charger_direction, locked_dir, "Charger direction must remain locked during straight-line lunge (AC5b)")
	assert_gt(charger.global_position.y, y_before_lunge + 100.0, "Charger must lunge rapidly along locked direction (AC5b)")
	level._clear_beams()

	# (c) Turret / Sniper: stationary, tracks player with aim telegraph line, and fires aimed projectile burst into BeamContainer
	var turret_pos: Vector2 = Vector2(180.0, 324.0)
	player.global_position = Vector2(780.0, 324.0)
	var turret: Area2D = level.spawn_turret(turret_pos, 1.0, 3, 480.0, 0.35, 22.0)
	var aim_line: Polygon2D = turret.get_node("CenterLine") as Polygon2D
	assert_eq(int(turret.hazard_type), 8, "Hazard type must be TURRET (8)")
	assert_eq(turret.current_phase, 0, "Turret must start in TELEGRAPH phase")
	assert_true(aim_line.visible, "Turret must display sniper aim telegraph line during TELEGRAPH (AC5c)")

	turret.simulate_physics(0.50)
	assert_eq(turret.global_position, turret_pos, "Turret must remain stationary (AC5c)")
	assert_gt(turret.turret_aim_direction.x, 0.95, "Turret must aim toward player during telegraph")

	# Step past 1.0s telegraph -> fires 3 aimed projectiles into BeamContainer (1 turret + 3 projectiles = 4 children)
	turret.simulate_physics(0.55)
	assert_eq(turret.current_phase, 1, "Turret must enter ACTIVE phase and fire at 1.0s")
	assert_eq(beam_container.get_child_count(), 4, "Turret must spawn 3 aimed projectiles into BeamContainer (AC5c/O3)")

	var proj_count: int = 0
	for child: Node in beam_container.get_children():
		if int(child.get("hazard_type")) == 2:
			proj_count += 1
			var vel: Vector2 = child.get("projectile_velocity") as Vector2
			assert_gt(vel.x, 300.0, "Turret-fired projectile must travel toward aimed player direction")
	assert_eq(proj_count, 3, "Exactly 3 PROJECTILE nodes must be spawned by turret burst")

	level._clear_beams()
	assert_eq(beam_container.get_child_count(), 0, "_clear_beams() must clean up turret and all turret projectiles (O3)")


func test_visual_polish_screen_shake_and_overlay_transitions() -> void:
	# AC7 & O5: Shield/cooldown/ripple primitives, screen shake without player displacement, and smooth overlay transitions
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()
	level._clear_beams()

	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	var beam_container: Node2D = level.get_node("BeamContainer") as Node2D
	var game_over_panel: ColorRect = level.get_node("HUD/HUDRoot/GameOverPanel") as ColorRect
	var complete_panel: ColorRect = level.get_node("HUD/HUDRoot/LevelCompletePanel") as ColorRect
	var player_start_pos: Vector2 = player.global_position

	# 1. Player shield ring, ripple ring, and cooldown ring monochrome primitives
	player.trigger_shield()
	var dash_ring: Polygon2D = player.get_node("DashRing") as Polygon2D
	var cooldown_ring: Line2D = player.get_node("CooldownRing") as Line2D
	var ripple_ring: Line2D = player.get_node("RippleRing") as Line2D
	assert_true(dash_ring.visible, "DashRing (shield barrier) must be visible while shield is active (AC7)")
	assert_true(ripple_ring.visible, "RippleRing must be visible on shield activation (AC7)")
	assert_false(cooldown_ring.visible, "CooldownRing must be hidden while shield is active")

	# Step past 1.0s shield duration into cooldown window (1.05s)
	player.simulate_physics(1.05)
	assert_false(dash_ring.visible, "DashRing must hide after shield expires")
	assert_true(cooldown_ring.visible, "CooldownRing must display while shield cooldown is recharging (AC7)")
	_assert_subtree_monochrome_and_primitive(player)

	# Expire cooldown and take damage -> triggers screen shake without moving player.global_position (O5)
	player.simulate_physics(0.55)
	player.take_damage(1)
	assert_gt(level.screen_shake_timer, 0.0, "Taking damage must trigger arena screen shake (AC7)")
	assert_true(beam_container.position != Vector2.ZERO, "Screen shake must offset BeamContainer")
	assert_eq(player.global_position, player_start_pos, "Screen shake must not displace player.global_position (O5)")

	# Decay screen shake to 0
	level.simulate_physics(0.30)
	assert_eq(level.screen_shake_offset, Vector2.ZERO, "Screen shake offset must decay back to Vector2.ZERO")
	assert_eq(beam_container.position, Vector2.ZERO, "BeamContainer position must return to Vector2.ZERO")

	# 2. GameOverPanel immediate visibility + smooth alpha/scale transition + instant reset on restart_level (O5)
	level._on_player_died()
	assert_true(game_over_panel.visible, "GameOverPanel.visible must be true immediately on Game Over (O5)")
	var initial_go_alpha: float = game_over_panel.modulate.a
	var initial_go_scale: float = game_over_panel.scale.x
	assert_lt(initial_go_alpha, 1.0, "GameOverPanel transition must start below alpha 1.0 (AC7)")
	assert_lt(initial_go_scale, 1.0, "GameOverPanel transition must start below scale 1.0 (AC7)")

	level.simulate_physics(0.10)
	assert_gt(game_over_panel.modulate.a, initial_go_alpha, "GameOverPanel alpha must smoothly increase during transition")
	level.simulate_physics(0.25)
	assert_eq(game_over_panel.modulate.a, 1.0, "GameOverPanel alpha must reach 1.0 after transition")
	assert_eq(game_over_panel.scale, Vector2.ONE, "GameOverPanel scale must reach Vector2.ONE after transition")

	level.restart_level()
	assert_false(game_over_panel.visible, "restart_level() must immediately set GameOverPanel.visible = false (O5)")
	assert_eq(game_over_panel.scale, Vector2.ONE, "restart_level() must reset GameOverPanel scale")

	# 3. LevelCompletePanel immediate visibility + smooth alpha/scale transition
	level.trigger_level_complete()
	assert_true(complete_panel.visible, "LevelCompletePanel.visible must be true immediately on Level Complete (O5)")
	var initial_lc_alpha: float = complete_panel.modulate.a
	level.simulate_physics(0.30)
	assert_gt(complete_panel.modulate.a, initial_lc_alpha, "LevelCompletePanel alpha must animate to 1.0 (AC7)")
	assert_eq(complete_panel.scale, Vector2.ONE, "LevelCompletePanel scale must animate to Vector2.ONE (AC7)")
	_assert_subtree_monochrome_and_primitive(level)


func test_procedural_audio_sfx_and_soundtrack() -> void:
	# AC7 & AC5: Main Menu has no background soundtrack and plays menu SFX on all buttons
	var menu: Control = track(MAIN_MENU_SCENE.instantiate()) as Control
	menu._ready()
	assert_true(menu.get_node_or_null("MusicPlayer") == null, "MainMenu must not have a background MusicPlayer (AC7)")
	assert_true(menu.sfx_player != null, "MainMenu must have SfxPlayer")
	assert_eq(menu.sfx_play_count, 0, "MainMenu must remain silent before button presses (AC7)")

	var menu_stream_1: AudioStreamWAV = menu.sfx_player.stream as AudioStreamWAV
	assert_true(menu_stream_1 != null, "MainMenu SfxPlayer stream must be AudioStreamWAV (AC1)")
	assert_eq(menu_stream_1.resource_path, "", "MainMenu SFX stream must be procedural in-memory (AC1/O1)")
	assert_gt(menu_stream_1.data.size(), 0, "MainMenu SFX stream must contain synthesized PCM bytes")
	assert_eq(menu_stream_1.loop_mode, AudioStreamWAV.LOOP_DISABLED, "MainMenu SFX must not loop")

	menu._on_difficulty_pressed()
	assert_eq(menu.sfx_play_count, 1, "DifficultyButton press must play menu SFX (AC5)")
	assert_eq(menu.last_sfx_played, &"menu", "DifficultyButton press must record menu SFX")

	menu._on_play_pressed()
	assert_eq(menu.sfx_play_count, 2, "PlayButton press must play menu SFX (AC5/O2)")
	assert_eq(menu.last_sfx_played, &"menu", "PlayButton press must record menu SFX")

	menu._on_quit_pressed()
	assert_eq(menu.sfx_play_count, 3, "QuitButton press must play menu SFX (AC5)")
	assert_eq(menu.sfx_player.stream, menu_stream_1, "MainMenu must reuse cached menu AudioStreamWAV (O4)")

	if Engine.has_meta(&"selected_difficulty"):
		Engine.remove_meta(&"selected_difficulty")

	# AC2: Player hit SFX on damage (when HP decreases), silent on shield activation or invincible hits
	var player: CharacterBody2D = track(PLAYER_SCENE.instantiate()) as CharacterBody2D
	player.global_position = Vector2(576.0, 324.0)
	player._ready()
	assert_true(player.sfx_player != null, "Player must have SfxPlayer")
	var hit_stream: AudioStreamWAV = player.sfx_player.stream as AudioStreamWAV
	assert_true(hit_stream != null, "Player hit stream must be AudioStreamWAV (AC1)")
	assert_eq(hit_stream.resource_path, "", "Player hit stream must be procedural in-memory (AC1/O1)")
	assert_gt(hit_stream.data.size(), 0, "Player hit stream must contain PCM data")
	assert_eq(player.hit_sfx_play_count, 0, "Player must not play hit SFX before taking damage")

	# Activating shield must not play hit SFX and must block damage SFX during 1.0s duration
	player.trigger_dash(Vector2.RIGHT)
	assert_eq(player.hit_sfx_play_count, 0, "Shield activation must not trigger hit SFX")
	player.take_damage(1)
	assert_eq(player.hit_sfx_play_count, 0, "Blocked damage during shield must not play hit SFX")
	player.simulate_physics(1.05)

	# Real damage (3 -> 2) plays hit SFX
	player.take_damage(1)
	assert_eq(player.current_hp, 2, "Player HP should drop to 2")
	assert_eq(player.hit_sfx_play_count, 1, "Taking damage must play hit SFX (AC2)")
	assert_eq(player.last_sfx_played, &"hit", "Player must record hit SFX")
	assert_eq(player.sfx_player.stream, hit_stream, "Player must reuse cached hit AudioStreamWAV (O4)")

	# Blocked damage during post-hit i-frames must not play hit SFX
	player.take_damage(1)
	assert_eq(player.hit_sfx_play_count, 1, "Ignored damage during i-frames must not play hit SFX")

	# AC3: BEAM and CIRCLE play laser SFX on entering Phase.ACTIVE, silent during TELEGRAPH
	var beam: Area2D = track(LIGHT_BEAM_SCENE.instantiate()) as Area2D
	beam._ready()
	beam.configure(Vector2(576.0, 324.0), 0.0, 44.0, 1.0, 0.35)
	assert_eq(beam.sfx_play_count, 0, "Beam telegraph phase must be silent (AC3)")
	beam.simulate_physics(0.5)
	assert_eq(beam.sfx_play_count, 0, "Beam must remain silent halfway through telegraph")
	beam.simulate_physics(0.55)
	assert_eq(beam.current_phase, 1, "Beam must enter Phase.ACTIVE")
	assert_eq(beam.sfx_play_count, 1, "Beam entering Phase.ACTIVE must play laser SFX (AC3)")
	assert_eq(beam.last_sfx_played, &"laser", "Beam active phase must trigger laser SFX")
	var laser_stream: AudioStreamWAV = beam.sfx_player.stream as AudioStreamWAV
	assert_true(laser_stream != null, "Laser stream must be AudioStreamWAV")
	assert_eq(laser_stream.resource_path, "", "Laser stream must be procedural in-memory")
	assert_gt(laser_stream.data.size(), 0, "Laser stream must have non-empty PCM data")
	beam.simulate_physics(0.4)
	assert_eq(beam.sfx_play_count, 1, "Beam FADE_OUT must not play additional SFX")

	var circle: Area2D = track(LIGHT_BEAM_SCENE.instantiate()) as Area2D
	circle._ready()
	circle.configure_circle(Vector2(400.0, 300.0), 78.0, 0, 1.0, 0.35)
	assert_eq(circle.sfx_play_count, 0, "Circle telegraph phase must be silent")
	circle.simulate_physics(1.05)
	assert_eq(circle.current_phase, 1, "Circle must enter Phase.ACTIVE")
	assert_eq(circle.sfx_play_count, 1, "Circle entering Phase.ACTIVE must play laser/burst SFX (AC3)")
	assert_eq(circle.last_sfx_played, &"laser", "Circle active burst must trigger laser SFX")
	assert_eq(circle.sfx_player.stream, laser_stream, "Beam and Circle must reuse cached laser AudioStreamWAV (O4)")

	# AC6, AC4, AC5, O2: Level soundtrack lifecycle, Exploder detonation SFX, and Level overlay buttons
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()
	level._clear_beams()

	assert_true(level.music_player != null, "Level must have MusicPlayer")
	assert_true(level.sfx_player != null, "Level must have SfxPlayer")
	var music_stream: AudioStreamWAV = level.music_player.stream as AudioStreamWAV
	assert_true(music_stream != null, "Level soundtrack must be AudioStreamWAV (AC1/AC6)")
	assert_eq(music_stream.resource_path, "", "Level soundtrack must be procedural in-memory (AC1/O1)")
	assert_gt(music_stream.data.size(), 0, "Level soundtrack must contain PCM data")
	assert_eq(music_stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "Level soundtrack must loop forward (AC6)")
	assert_gt(music_stream.loop_end, 0, "Level soundtrack must define a positive loop_end")
	assert_true(level.is_music_playing, "Soundtrack must play when level starts (AC6)")
	var initial_music_restarts: int = level.music_restart_count

	# Edge projectile spawns must be silent (Out of Scope)
	var edge_proj: Area2D = level.spawn_edge_projectile(0, 390.0, 10.0)
	assert_eq(edge_proj.sfx_play_count, 0, "Edge projectile spawn must be silent")
	level._clear_beams()

	# Exploder detonation triggers explosion SFX and delegates to Level SfxPlayer before despawn (AC4/O2)
	var exploder: Area2D = level.spawn_exploder(Vector2(576.0, 324.0), 1.0, 8, 380.0)
	assert_eq(exploder.sfx_play_count, 0, "Exploder telegraph must be silent")
	exploder.simulate_physics(1.05)
	assert_eq(exploder.sfx_play_count, 1, "Exploder detonation must trigger explosion SFX (AC4)")
	assert_eq(exploder.last_sfx_played, &"explosion", "Exploder must record explosion SFX")
	var explosion_stream: AudioStreamWAV = exploder.sfx_player.stream as AudioStreamWAV
	assert_true(explosion_stream != null, "Explosion stream must be AudioStreamWAV")
	assert_eq(explosion_stream.resource_path, "", "Explosion stream must be procedural in-memory")
	assert_gt(explosion_stream.data.size(), 0, "Explosion stream must contain PCM data")
	assert_eq(level.last_sfx_played, &"explosion", "Level SfxPlayer must receive explosion SFX so it outlives exploder despawn (O2)")
	assert_eq(level.sfx_player.stream, explosion_stream, "Level SfxPlayer must hold explosion stream on detonation (O2)")

	var beam_container: Node2D = level.get_node("BeamContainer") as Node2D
	for child: Node in beam_container.get_children():
		assert_eq(int(child.get("sfx_play_count")), 0, "Burst projectiles spawned by exploder must be silent")

	# Verify all synthesized SFX waveforms are distinct (AC1–AC5)
	var shield_block_stream: AudioStreamWAV = player._get_shield_block_sfx_stream()
	assert_true(shield_block_stream != null and shield_block_stream.resource_path == "", "Shield block SFX must be procedural in-memory AudioStreamWAV")
	assert_true(hit_stream.data != laser_stream.data, "Hit SFX and Laser SFX must have distinct waveforms")
	assert_true(hit_stream.data != shield_block_stream.data, "Hit SFX and Shield Block SFX must have distinct waveforms")
	assert_true(laser_stream.data != explosion_stream.data, "Laser SFX and Explosion SFX must have distinct waveforms")
	assert_true(explosion_stream.data != menu_stream_1.data, "Explosion SFX and Menu SFX must have distinct waveforms")
	assert_true(hit_stream.data != explosion_stream.data, "Hit SFX and Explosion SFX must have distinct waveforms")

	# Game Over stops soundtrack immediately; Retry plays menu SFX and restarts soundtrack (AC5/AC6/O2)
	level._on_player_died()
	assert_false(level.is_level_running, "Level must stop on Game Over")
	assert_false(level.is_music_playing, "Level soundtrack must stop immediately on Game Over (AC6/O2)")

	var sfx_before_retry: int = level.sfx_play_count
	level._on_retry_pressed()
	assert_eq(level.sfx_play_count, sfx_before_retry + 1, "RetryButton must play menu feedback SFX (AC5)")
	assert_eq(level.last_sfx_played, &"menu", "RetryButton must record menu SFX")
	assert_true(level.is_level_running, "Retry must restart level")
	assert_true(level.is_music_playing, "Retry must restart level soundtrack (AC6)")
	assert_eq(level.music_restart_count, initial_music_restarts + 1, "Retry must restart soundtrack from beginning (AC6)")
	assert_eq(level.music_player.stream, music_stream, "Retry must reuse cached soundtrack stream (O4)")

	# Level Complete stops soundtrack immediately; Replay plays menu SFX and restarts soundtrack (AC5/AC6/O2)
	level.trigger_level_complete()
	assert_false(level.is_level_running, "Level must stop on Level Complete")
	assert_false(level.is_music_playing, "Level soundtrack must stop immediately on Level Complete (AC6/O2)")

	var sfx_before_replay: int = level.sfx_play_count
	level._on_replay_pressed()
	assert_eq(level.sfx_play_count, sfx_before_replay + 1, "ReplayButton must play menu feedback SFX (AC5)")
	assert_eq(level.last_sfx_played, &"menu", "ReplayButton must record menu SFX")
	assert_true(level.is_level_running, "Replay must restart level")
	assert_true(level.is_music_playing, "Replay must restart level soundtrack (AC6)")
	assert_eq(level.music_restart_count, initial_music_restarts + 2, "Replay must restart soundtrack from beginning (AC6)")

	# GameOverMainMenuButton and CompleteMainMenuButton handler stops music and plays menu SFX (AC5/AC6/O2)
	var sfx_before_menu: int = level.sfx_play_count
	level._on_main_menu_pressed()
	assert_false(level.is_music_playing, "MainMenu button must stop level soundtrack immediately (O2)")
	assert_eq(level.sfx_play_count, sfx_before_menu + 1, "MainMenu overlay button must play menu feedback SFX (AC5/O2)")
	assert_eq(level.last_sfx_played, &"menu", "MainMenu overlay button must record menu SFX")


func test_hand_tracker_process_lifecycle_and_single_instance() -> void:
	# AC1 & O2: Autoload registration, headless command resolution, single-instance guard, clean exit
	var autoload_setting: String = str(ProjectSettings.get_setting("autoload/HandTrackingClient", ""))
	assert_eq(
		autoload_setting,
		"*res://scripts/hand_tracking_client.gd",
		"HandTrackingClient must be registered as an autoload singleton in project.godot (AC1)"
	)

	var client: Node = track(HAND_TRACKING_CLIENT_SCRIPT.new())
	client.set("auto_manage_process", false)
	client.call("set_mock_process_mode", true)

	# Verify editor-hint protection skips background tracker process launch by default (O2)
	var started_in_editor_default: bool = bool(client.call("start_tracker_process", false))
	assert_false(started_in_editor_default, "Editor mode must not spawn background tracker process without explicit test override (O2)")
	assert_eq(int(client.get("process_spawn_count")), 0, "No process must spawn in default editor hint check")

	var cmd: Dictionary = client.call("resolve_tracker_launch_command") as Dictionary
	var args: PackedStringArray = cmd.get("args", PackedStringArray()) as PackedStringArray
	assert_gt(str(cmd.get("executable", "")).length(), 0, "Tracker launch executable must resolve")
	assert_true(args.has("--headless"), "Tracker launch args must include --headless (AC1)")

	# Spawn first headless tracker instance
	var first_spawn: bool = bool(client.call("start_tracker_process", true))
	assert_true(first_spawn, "First start_tracker_process should succeed (AC1)")
	assert_eq(OS.get_environment("TRACKER_HEADLESS"), "1", "TRACKER_HEADLESS=1 environment variable must be set (AC1)")
	assert_eq(int(client.get("process_spawn_count")), 1, "Exactly one tracker process must be spawned")
	assert_true(bool(client.call("is_tracker_process_alive")), "Tracker process must report alive after launch")

	# Calling start_tracker_process again while alive must not spawn a duplicate (AC1 / O2)
	var duplicate_spawn: bool = bool(client.call("start_tracker_process", true))
	assert_false(duplicate_spawn, "Duplicate tracker process spawn must be prevented while an instance is alive (AC1/O2)")
	assert_eq(int(client.get("process_spawn_count")), 1, "Spawn count must remain 1")

	# Clean termination via window close notification / stop_tracker_process (AC1 / O2)
	client.call("_notification", Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_false(bool(client.call("is_tracker_process_alive")), "Window close notification must terminate tracker process (AC1/O2)")
	assert_eq(int(client.get("tracker_pid")), -1, "tracker_pid must reset to -1 after stop")
	assert_eq(int(client.get("process_stop_count")), 1, "Stop count must increment to 1")

	# Verify .tracker.status heartbeat contract ("ready" vs "error:camera") (AC1 / AC6)
	var temp_status_path: String = ProjectSettings.globalize_path("user://test_tracker.status")
	var f_ready: FileAccess = FileAccess.open(temp_status_path, FileAccess.WRITE)
	if f_ready != null:
		f_ready.store_string("ready")
		f_ready.close()
	client.call("set_status_file_override", temp_status_path)
	client.call("poll_and_update", 0.016)
	assert_eq(str(client.call("get_status_label_text")), "HAND: NO HAND", "Fresh 'ready' heartbeat with 0 landmarks must report HAND: NO HAND (AC6)")
	assert_false(bool(client.call("start_tracker_process", true)), "Fresh 'ready' heartbeat must prevent duplicate process launch (AC1/O2)")

	var f_err: FileAccess = FileAccess.open(temp_status_path, FileAccess.WRITE)
	if f_err != null:
		f_err.store_string("error:camera")
		f_err.close()
	client.call("set_status_file_override", temp_status_path)
	client.call("poll_and_update", 0.016)
	assert_eq(str(client.call("get_status_label_text")), "HAND: OFFLINE", "'error:camera' status must report HAND: OFFLINE (AC6)")
	if FileAccess.file_exists(temp_status_path):
		DirAccess.remove_absolute(temp_status_path)


func test_hand_tracking_udp_decoding_socket_draining_and_mirrored_palm_target() -> void:
	# AC2, AC3, O3, O5: Binary packet decoding (<i63f and <i), UDP buffer draining to latest packet, and mirrored palm target
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()

	var tracker: Node = level.get("hand_tracker") as Node
	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	assert_true(tracker != null, "Level must have a valid hand_tracker instance when detached from SceneTree (O3)")

	# Verify malformed packet rejection
	var bad_pkt: PackedByteArray = PackedByteArray([1, 2])
	assert_false(bool(tracker.call("ingest_packet", bad_pkt)), "Malformed packet (<4 bytes) must be rejected")

	# Verify real loopback UDP binding and multi-packet buffer draining (AC2 / O5)
	var test_port: int = 15005
	var bind_err: Error = int(tracker.call("bind_udp", test_port)) as Error
	assert_eq(bind_err, OK, "HandTrackingClient must bind UDP socket on localhost")

	var sender: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(sender.set_dest_address("127.0.0.1", test_port), OK, "UDP sender must target 127.0.0.1")

	# Queue two packets before polling: first at raw x=0.80, y=0.70, second (newest) at raw x=0.25, y=0.30
	var old_hand: Array[Vector3] = _build_hand_landmarks(Vector2(0.80, 0.70), false)
	var new_hand: Array[Vector3] = _build_hand_landmarks(Vector2(0.25, 0.30), false)
	var pkt_old: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(old_hand)
	var pkt_new: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(new_hand)
	assert_eq(pkt_old.size(), 256, "Encoded <i63f packet must be exactly 256 bytes (AC2)")

	sender.put_packet(pkt_old)
	sender.put_packet(pkt_new)
	tracker.call("queue_synthetic_packet", pkt_old)
	tracker.call("queue_synthetic_packet", pkt_new)

	# Single tick must drain queued packets and apply the newest packet (O5)
	level.simulate_physics(0.016)
	sender.close()
	tracker.call("close_udp")

	assert_true(bool(tracker.get("has_hand")), "Tracker must report has_hand=true after 21-landmark packet (AC2)")
	var mirrored_palm: Vector2 = tracker.call("get_mirrored_palm_center") as Vector2
	# Raw palm x=0.25 -> horizontally mirrored x = 1.0 - 0.25 = 0.75; y = 0.30 (AC3)
	assert_true(absf(mirrored_palm.x - 0.75) < 0.01, "Mirrored palm X must be 1.0 - 0.25 = 0.75 (AC3)")
	assert_true(absf(mirrored_palm.y - 0.30) < 0.01, "Mirrored palm Y must be 0.30 (AC3)")

	var expected_screen_target: Vector2 = Vector2(0.75 * 1152.0, 0.30 * 648.0)
	assert_true(player.external_tracking_active, "Player external_tracking_active must be true when hand is tracked (AC3)")
	assert_true(player.target_position.distance_to(expected_screen_target) < 2.0, "Player target_position must match mirrored palm center from newest packet (AC3/O5)")

	# Step simulation to confirm player moves to the mirrored palm target
	for _i: int in range(25):
		level.ingest_hand_packet(pkt_new)
		level.simulate_physics(0.016)
	assert_true(player.global_position.distance_to(expected_screen_target) < 8.0, "Player must follow mirrored palm center to target position (AC3)")


func test_hand_tracking_closed_fist_rising_edge_dash() -> void:
	# AC1, AC9 & O1: Open-to-closed fist transition triggers 1.0s shield (with 1.5s cooldown) once; held fist does not re-trigger
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()
	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D

	var open_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(
		_build_hand_landmarks(Vector2(0.35, 0.50), false)
	)
	var fist_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(
		_build_hand_landmarks(Vector2(0.35, 0.50), true)
	)

	# 1. Open hand must not trigger shield/dash
	level.ingest_hand_packet(open_pkt)
	assert_false(player.is_shield_active, "Open hand must not trigger player shield (AC1)")
	assert_false(player.is_dashing, "Open hand must not set is_dashing alias")

	# 2. Transition from open hand to closed fist triggers shield and shadow pulse immediately on packet receipt (AC1/AC9)
	level.ingest_hand_packet(fist_pkt)
	assert_true(player.is_shield_active, "Open-to-closed fist transition must activate player shield immediately (AC1/AC9)")
	assert_true(player.is_dashing, "Open-to-closed fist transition must synchronize is_dashing alias (O1)")
	assert_gt(float(level.get("hand_shadow_dash_pulse")), 0.5, "Closed-fist shield activation must pulse hand shadow")

	# 3. Advance past 1.0s shield duration and 1.5s cooldown while holding closed fist (35 * 0.05s = 1.75s)
	for _i: int in range(35):
		level.ingest_hand_packet(fist_pkt)
		level.simulate_physics(0.05)

	assert_false(player.is_shield_active, "Shield must finish after 1.0s SHIELD_DURATION")
	assert_false(player.is_dashing, "is_dashing alias must finish after SHIELD_DURATION")
	assert_eq(player.shield_cooldown_timer, 0.0, "Shield 1.5s cooldown must have expired")
	assert_eq(player.dash_cooldown_timer, 0.0, "dash_cooldown_timer alias must have expired")

	# Sending another held-fist frame after cooldown expiry must NOT re-trigger shield
	level.ingest_hand_packet(fist_pkt)
	assert_false(player.is_shield_active, "Held closed fist must not re-trigger shield after cooldown expires")

	# 4. Opening hand and closing into a fist again must trigger a second shield
	level.ingest_hand_packet(open_pkt)
	assert_false(player.is_shield_active, "Re-opening hand must not activate shield")
	level.ingest_hand_packet(fist_pkt)
	assert_true(player.is_shield_active, "Subsequent open-to-closed fist transition must trigger shield again")


func test_hand_tracking_30_to_60_fps_smoothing_and_instant_fist_shield() -> void:
	# AC9 & O4: 30 FPS UDP packets interpolated smoothly across 60 FPS render frames without stepping
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()
	level._clear_beams()

	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	var tip_8: Polygon2D = level.get_node("HandShadow/Fingertip8") as Polygon2D

	# Packet 1 (initial hand acquisition at raw x=0.50, y=0.50 -> mirrored x=0.50, y=0.50) snaps immediately
	var pkt_1: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(
		_build_hand_landmarks(Vector2(0.50, 0.50), false)
	)
	level.ingest_hand_packet(pkt_1)
	var tip8_start_x: float = tip_8.position.x

	# Packet 2 (30 FPS update jumps to raw x=0.20, y=0.50 -> mirrored x=0.80, y=0.50 = 921.6px)
	var pkt_2: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(
		_build_hand_landmarks(Vector2(0.20, 0.50), false)
	)
	level.ingest_hand_packet(pkt_2)

	# Raw target_position updates immediately on tick 1 (< 2.0px), while smoothed position and shadow interpolate across 60 FPS frames
	var expected_target: Vector2 = Vector2(0.80 * 1152.0, 0.50 * 648.0)
	assert_lt(player.target_position.distance_to(expected_target), 2.0, "player.target_position must update immediately on packet arrival (O4)")
	var tip8_frame1_x: float = tip_8.position.x
	var player_frame1_x: float = player.global_position.x
	assert_gt(tip8_frame1_x, tip8_start_x, "HandShadow landmark must advance smoothly on 60 FPS frame 1 (AC9/O4)")

	# Intermediate 60 FPS frame (no new UDP packet arrives between 30Hz packets) must continue advancing smoothly
	level.simulate_physics(0.016)
	var tip8_frame2_x: float = tip_8.position.x
	var player_frame2_x: float = player.global_position.x
	assert_gt(tip8_frame2_x, tip8_frame1_x, "HandShadow landmark must continue interpolating on intermediate 60 FPS frame without new packet (AC9/O4)")
	assert_gt(player_frame2_x, player_frame1_x, "Player position must continue interpolating smoothly on intermediate 60 FPS frame (AC9/O4)")


func test_hand_tracking_bidirectional_fallback_and_resumption() -> void:
	# AC5 & O1: Seamless bidirectional switching between hand tracking and mouse/keyboard fallback
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()
	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D

	var hand_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(
		_build_hand_landmarks(Vector2(0.30, 0.40), false)
	)
	var empty_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_empty_packet()
	assert_eq(empty_pkt.size(), 4, "Empty <i packet must be 4 bytes (AC2)")

	# Engage hand tracking
	level.ingest_hand_packet(hand_pkt)
	assert_true(player.external_tracking_active, "21-landmark packet must engage external_tracking_active (AC3/O1)")

	# Receive 0-landmark packet -> immediately releases external_tracking_active for mouse/keyboard fallback (AC5 / O1)
	level.ingest_hand_packet(empty_pkt)
	assert_false(player.external_tracking_active, "0-landmark packet must immediately clear external_tracking_active (AC5/O1)")
	assert_false(player.use_target_position, "Releasing hand tracking must clear stale target following (O1)")

	# Verify mouse fallback works while hand is untracked
	var mouse_target: Vector2 = Vector2(220.0, 180.0)
	player.set_target_position(mouse_target, false)
	assert_false(player.external_tracking_active, "Mouse target must keep external_tracking_active false")
	for _i: int in range(30):
		player.simulate_physics(0.016)
	assert_true(player.global_position.distance_to(mouse_target) < 6.0, "Mouse fallback must move player when no hand is tracked (AC5/O1)")

	# Send 21-landmark packet again -> automatically re-engages hand tracking (O1)
	level.ingest_hand_packet(hand_pkt)
	assert_true(player.external_tracking_active, "Subsequent 21-landmark packet must automatically re-engage external_tracking_active (O1)")

	# Simulate UDP packet timeout (>0.5s without packets) -> releases external_tracking_active (AC5 / O1)
	level.simulate_physics(0.6)
	assert_false(player.external_tracking_active, "UDP packet timeout must release external_tracking_active (AC5/O1)")


func test_hand_tracking_hud_status_pill_and_constellation_shadow() -> void:
	# AC6, AC7, O4: HUD status states, HandShadow layering behind hazards/player, articulated primitives, pulse & fade
	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.restart_level()

	var bg: ColorRect = level.get_node("Background") as ColorRect
	var hand_shadow: Node2D = level.get_node("HandShadow") as Node2D
	var beam_container: Node2D = level.get_node("BeamContainer") as Node2D
	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	var palm_poly: Polygon2D = level.get_node("HandShadow/PalmPolygon") as Polygon2D
	var index_bone: Line2D = level.get_node("HandShadow/IndexBone") as Line2D
	var tip_8: Polygon2D = level.get_node("HandShadow/Fingertip8") as Polygon2D
	var status_pill: ColorRect = level.get_node("HUD/HUDRoot/HandStatusPill") as ColorRect
	var status_icon: Polygon2D = level.get_node("HUD/HUDRoot/HandStatusPill/HandStatusIcon") as Polygon2D
	var status_label: Label = level.get_node("HUD/HUDRoot/HandStatusPill/HandStatusLabel") as Label

	assert_true(hand_shadow != null, "HandShadow node must exist in level.tscn (AC7)")
	assert_true(status_pill != null and status_icon != null and status_label != null, "HUD HandStatusPill, icon, and label must exist (AC6)")

	# Verify strict scene tree draw order: Background < HandShadow < BeamContainer < Player (O4)
	assert_gt(hand_shadow.get_index(), bg.get_index(), "Background must be drawn behind HandShadow (O4)")
	assert_gt(beam_container.get_index(), hand_shadow.get_index(), "HandShadow must be drawn behind BeamContainer hazards (AC7/O4)")
	assert_gt(player.get_index(), beam_container.get_index(), "BeamContainer must be ordered before Player (O4)")

	# 1. Initial / offline state: HAND: OFFLINE and shadow hidden (AC6, AC7)
	assert_eq(status_label.text, "HAND: OFFLINE", "HUD status must start as HAND: OFFLINE (AC6)")
	assert_false(hand_shadow.visible, "HandShadow must be hidden when no hand has been tracked (AC7)")

	# 2. Active 21-landmark hand tracking: HAND: TRACKING and articulated shadow visible (AC6, AC7)
	var open_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(
		_build_hand_landmarks(Vector2(0.40, 0.50), false)
	)
	level.ingest_hand_packet(open_pkt)
	assert_eq(status_label.text, "HAND: TRACKING", "HUD status must display HAND: TRACKING when 21 landmarks are received (AC6)")
	assert_true(hand_shadow.visible, "HandShadow must become visible when hand is tracked (AC7)")
	assert_eq(palm_poly.polygon.size(), 6, "PalmPolygon must have 6 vertices (#0, #1, #5, #9, #13, #17) (AC7)")
	assert_eq(index_bone.points.size(), 5, "IndexBone Line2D must connect 5 landmarks (#0, #5, #6, #7, #8) (AC7)")
	var open_tip8_pos: Vector2 = tip_8.position
	var open_tip8_scale: Vector2 = tip_8.scale

	# 3. Closed-fist shield contracts fingertips toward palm and pulses scale/brightness (AC7)
	var fist_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(
		_build_hand_landmarks(Vector2(0.40, 0.50), true)
	)
	level.ingest_hand_packet(fist_pkt)
	assert_gt(tip_8.scale.x, open_tip8_scale.x, "Fingertip node must pulse larger on fist shield (AC7)")
	assert_true(tip_8.position != open_tip8_pos, "Fingertip node must contract toward palm on closed fist (AC7)")
	_assert_subtree_monochrome_and_primitive(level)

	# 4. 0-landmark packet -> HAND: NO HAND and smooth shadow fade-out (AC6, AC7)
	var empty_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_empty_packet()
	level.ingest_hand_packet(empty_pkt)
	assert_eq(status_label.text, "HAND: NO HAND", "HUD status must display HAND: NO HAND when 0 landmarks are received (AC6)")

	var alpha_before_fade: float = float(level.get("hand_shadow_alpha"))
	level.simulate_physics(0.1)
	var alpha_mid_fade: float = float(level.get("hand_shadow_alpha"))
	assert_gt(alpha_before_fade, alpha_mid_fade, "HandShadow alpha must smoothly decrease when no hand is tracked (AC7)")

	for _i: int in range(10):
		level.simulate_physics(0.1)
	assert_eq(float(level.get("hand_shadow_alpha")), 0.0, "HandShadow alpha must reach 0.0 after fade-out (AC7)")
	assert_false(hand_shadow.visible, "HandShadow must hide once faded out (AC7)")
	assert_eq(status_label.text, "HAND: OFFLINE", "HUD status must return to HAND: OFFLINE after packet timeout (AC6)")


func test_performance_profiling_static_polygons_and_60fps_budget() -> void:
	# AC8 & O6: Precomputed static unit polygons, peak 9-hazard wave step time <= 16.67 ms (60 FPS), and zero orphan nodes
	for htype: int in [1, 2, 3, 5, 6, 7, 8]:
		var unit_poly: PackedVector2Array = LIGHT_BEAM_SCRIPT.get_static_unit_polygon(htype)
		assert_gt(unit_poly.size(), 3, "Static unit polygon must be precomputed for hazard type %d (O6)" % htype)

	var level: Node2D = track(LEVEL_SCENE.instantiate()) as Node2D
	level._ready()
	level.set_difficulty(2) # Hard peak wave density
	level.restart_level()
	level._clear_beams()

	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	# Spawn a simultaneous peak wave containing all 9 hazard/enemy types + active hand tracking
	level.spawn_beam(Vector2(576.0, 120.0), 0.15)
	level.spawn_circle(Vector2(260.0, 200.0), 78.0, 0)
	level.spawn_projectile(Vector2(100.0, 100.0), Vector2.RIGHT, 390.0, 10.0)
	level.spawn_exploder(Vector2(880.0, 180.0))
	level.spawn_closing_walls(0, 324.0, 136.0)
	level.spawn_saw(Vector2(200.0, 480.0), Vector2.RIGHT, 340.0, 36.0)
	level.spawn_chaser(Vector2(900.0, 480.0), 240.0)
	level.spawn_charger(Vector2(180.0, 520.0), 780.0)
	level.spawn_turret(Vector2(960.0, 140.0))

	var hand_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(
		_build_hand_landmarks(Vector2(0.45, 0.52), false)
	)
	level.ingest_hand_packet(hand_pkt)

	var total_usec: int = 0
	var peak_usec: int = 0
	var frames: int = 120
	for i: int in range(frames):
		if i % 2 == 0:
			level.ingest_hand_packet(hand_pkt)
		var t0: int = Time.get_ticks_usec()
		level.simulate_physics(0.016)
		var elapsed_usec: int = Time.get_ticks_usec() - t0
		total_usec += elapsed_usec
		if elapsed_usec > peak_usec:
			peak_usec = elapsed_usec

	var avg_ms: float = (float(total_usec) / float(frames)) / 1000.0
	var peak_ms: float = float(peak_usec) / 1000.0
	assert_lt(avg_ms, 16.67, "Average peak-wave physics step time must be <= 16.67 ms (60 FPS) (avg=%.3f ms)" % avg_ms)
	assert_lt(peak_ms, 16.67, "Peak 9-hazard physics step time must be <= 16.67 ms (60 FPS) (peak=%.3f ms)" % peak_ms)

	var beam_container: Node2D = level.get_node("BeamContainer") as Node2D
	level._clear_beams()
	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	assert_eq(beam_container.get_child_count(), 0, "All peak-wave hazards and child projectiles must be cleaned up with 0 leftover children (AC8/O6)")
	assert_eq(orphans_after - orphans_before, 0, "Orphan node delta after peak wave and _clear_beams() must be 0 (AC8/O6)")


func _build_hand_landmarks(palm_target: Vector2, closed_fist: bool) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	pts.resize(21)
	var px: float = palm_target.x
	var py: float = palm_target.y

	pts[0] = Vector3(px, py + 0.08, 0.0)
	pts[1] = Vector3(px - 0.05, py + 0.05, 0.0)
	pts[2] = Vector3(px - 0.08, py + 0.02, 0.0)
	pts[3] = Vector3(px - 0.10, py - 0.01, 0.0)
	pts[4] = Vector3(px - 0.04, py + 0.01, 0.0) if closed_fist else Vector3(px - 0.12, py - 0.04, 0.0)

	var finger_x_offsets: Array[float] = [-0.06, -0.02, 0.02, 0.06]
	var base_indices: Array[int] = [5, 9, 13, 17]
	for f: int in range(4):
		var b_idx: int = base_indices[f]
		var fx: float = px + finger_x_offsets[f]
		pts[b_idx] = Vector3(fx, py - 0.02, 0.0)
		pts[b_idx + 1] = Vector3(fx, py - 0.07, 0.0)
		if closed_fist:
			pts[b_idx + 2] = Vector3(fx, py - 0.03, 0.0)
			pts[b_idx + 3] = Vector3(fx, py + 0.01, 0.0)
		else:
			pts[b_idx + 2] = Vector3(fx, py - 0.12, 0.0)
			pts[b_idx + 3] = Vector3(fx, py - 0.17, 0.0)

	return pts


func _assert_subtree_monochrome_and_primitive(node: Node) -> void:
	assert_false(node is Sprite2D, "External texture Sprite2D is not allowed: " + node.name)
	assert_false(node is TextureRect, "External TextureRect is not allowed: " + node.name)
	if node is AudioStreamPlayer:
		var audio_player: AudioStreamPlayer = node as AudioStreamPlayer
		if audio_player.stream != null:
			assert_eq(
				audio_player.stream.resource_path,
				"",
				"AudioStreamPlayer stream must be procedural in-memory without external resource_path: " + node.name
			)

	if node is Polygon2D:
		var c: Color = (node as Polygon2D).color
		assert_true(absf(c.r - c.g) < 0.01 and absf(c.g - c.b) < 0.01, "Polygon2D must be grayscale: " + node.name)
	elif node is ColorRect:
		var c: Color = (node as ColorRect).color
		assert_true(absf(c.r - c.g) < 0.01 and absf(c.g - c.b) < 0.01, "ColorRect must be grayscale: " + node.name)
	elif node is Line2D:
		var c: Color = (node as Line2D).default_color
		assert_true(absf(c.r - c.g) < 0.01 and absf(c.g - c.b) < 0.01, "Line2D must be grayscale: " + node.name)

	for child: Node in node.get_children():
		_assert_subtree_monochrome_and_primitive(child)
