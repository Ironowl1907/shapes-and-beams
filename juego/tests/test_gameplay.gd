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

	# Verify difficulty scales only attack spawn frequency, keeping HP (3) and duration (45s) constant (AC2, AC3)
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
		for expected_type: int in [0, 1, 2, 3]:
			assert_true(seen_types.has(expected_type), "Difficulty %d must spawn hazard type %d" % [mode, expected_type])

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

	# AC2: Player hit SFX on damage (when HP decreases), silent on dash or invincible hits
	var player: CharacterBody2D = track(PLAYER_SCENE.instantiate()) as CharacterBody2D
	player.global_position = Vector2(576.0, 324.0)
	player._ready()
	assert_true(player.sfx_player != null, "Player must have SfxPlayer")
	var hit_stream: AudioStreamWAV = player.sfx_player.stream as AudioStreamWAV
	assert_true(hit_stream != null, "Player hit stream must be AudioStreamWAV (AC1)")
	assert_eq(hit_stream.resource_path, "", "Player hit stream must be procedural in-memory (AC1/O1)")
	assert_gt(hit_stream.data.size(), 0, "Player hit stream must contain PCM data")
	assert_eq(player.hit_sfx_play_count, 0, "Player must not play hit SFX before taking damage")

	# Dashing must remain silent (Out of Scope) and block damage SFX
	player.trigger_dash(Vector2.RIGHT)
	assert_eq(player.hit_sfx_play_count, 0, "Dash must not trigger SFX")
	player.take_damage(1)
	assert_eq(player.hit_sfx_play_count, 0, "Blocked damage during dash must not play hit SFX")
	player.simulate_physics(0.25)

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
	assert_true(hit_stream.data != laser_stream.data, "Hit SFX and Laser SFX must have distinct waveforms")
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

	for child: Node in node.get_children():
		_assert_subtree_monochrome_and_primitive(child)
