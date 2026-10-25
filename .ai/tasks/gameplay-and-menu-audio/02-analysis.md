---
task_name: gameplay-and-menu-audio
---

## 1. Change Summary
<!-- prose · required -->
Introduces procedural in-memory audio synthesis (`AudioStreamWAV`) and playback (`AudioStreamPlayer`) across `MainMenu`, `Level`, `Player`, and `LightBeam` with zero external audio files and minimal code/object count. Adds distinct synthesized sound effects for menu button presses, player damage (`take_damage`), beam and filling-circle active bursts (`Phase.ACTIVE`), and exploder detonations (`_detonate_exploder`), plus a simple looping procedural soundtrack during active level gameplay (`is_level_running == true`) that stops on Game Over, Level Complete, or Main Menu transition and restarts on Retry/Replay. Updates `test_gameplay.gd` to permit procedural in-memory `AudioStreamPlayer` nodes while preserving existing gameplay, difficulty, and monochrome primitive guarantees.

## 2. Impact Map
<!-- bullet list · required -->
- `juego/tests/test_gameplay.gd` — Relationship: downstream — Existing `_assert_subtree_monochrome_and_primitive` test forbids `AudioStreamPlayer` nodes and instantiates scenes detached from `SceneTree` — Impacts: I1, I3, I4
- `juego/scenes/light_beam.tscn` & `juego/scripts/light_beam.gd` — Relationship: origin — Triggers laser/burst SFX on `BEAM`/`CIRCLE` entering `Phase.ACTIVE` and explosion SFX on `EXPLODER` detonation immediately before `_despawn()` — Impacts: I1, I2, I3, I4
- `juego/scenes/main_menu.tscn` & `juego/scripts/main_menu.gd` — Relationship: origin — Triggers menu feedback SFX on `DifficultyButton`, `PlayButton` (immediately before scene change), and `QuitButton` while keeping background music silent — Impacts: I1, I2, I3, I4
- `juego/scenes/level.tscn` & `juego/scripts/level.gd` — Relationship: origin — Controls looping level soundtrack lifecycle (`restart_level`, `_on_player_died`, `trigger_level_complete`, `_on_main_menu_pressed`) and triggers HUD overlay button SFX — Impacts: I1, I2, I3, I4
- `juego/scenes/player.tscn` & `juego/scripts/player.gd` — Relationship: origin — Triggers hit SFX when `take_damage` reduces `current_hp` — Impacts: I1, I3, I4

## 3. Impacts
<!-- entries · required · repeat per entry -->

### I1 — Existing `test_ac11_monochrome_primitives_only` Forbids `AudioStreamPlayer` in Scene Subtrees
- **Lens**: Contracts and interfaces
- **Severity**: High
- **Breaking**: Yes
- **Condition**: Unconditional
- **Evidence**: `juego/tests/test_gameplay.gd:217-222,395-408` instantiates `MAIN_MENU_SCENE`, `LEVEL_SCENE`, `PLAYER_SCENE`, and `LIGHT_BEAM_SCENE` and calls `_assert_subtree_monochrome_and_primitive(root)`, where line 398 asserts `assert_false(node is AudioStreamPlayer, "AudioStreamPlayer is out of scope: " + node.name)`.
- **Consequence**: Adding `AudioStreamPlayer` nodes to the scenes causes `test_ac11_monochrome_primitives_only` to fail unless the assertion is updated to allow procedural in-memory `AudioStreamPlayer` nodes while still rejecting external asset files.
- **Disposition**: Mitigate via: O1 (Settled in: Q1)

### I2 — SFX Cut Off on Immediate Hazard Despawn (`_detonate_exploder`) or Scene Transition (`PlayButton`, `MainMenuButton`)
- **Lens**: Behavior and regressions
- **Severity**: High
- **Breaking**: No
- **Condition**: If explosion SFX is played by a child node of the despawning `LightBeam` instance or if menu button SFX on `PlayButton` / `MainMenuButton` is played by a node freed when `change_scene_to_file()` unloads the active scene.
- **Evidence**: `juego/scripts/light_beam.gd:270-292` calls `_despawn()` (`queue_free()` / `remove_child(self)`) immediately inside `_detonate_exploder()`, and `juego/scripts/main_menu.gd:95` and `juego/scripts/level.gd:462` call `get_tree().change_scene_to_file(...)` immediately inside `_on_play_pressed()` and `_on_main_menu_pressed()`.
- **Consequence**: Explosion SFX (AC4) and `Play` / `Main Menu` button click SFX (AC5) are truncated after a single frame if their playback node is destroyed with the hazard or scene, whereas failing to stop the level soundtrack on scene exit causes music to bleed into `MainMenu` (violating AC6 and AC7).
- **Disposition**: Mitigate via: O2 (Settled in: Q2)

### I3 — Detached (`!is_inside_tree()`) Test Execution and `@tool` Editor Mode Safety
- **Lens**: Reliability and failure modes
- **Severity**: High
- **Breaking**: Yes
- **Condition**: Unconditional
- **Evidence**: `juego/tests/test_gameplay.gd:18,59,107,139,184,229` instantiates scenes via `track(SCENE.instantiate())` without adding them to the `SceneTree` (`is_inside_tree() == false`) and calls `_ready()`, `simulate_physics(delta)`, `take_damage(1)`, and button handlers directly; additionally, `main_menu.gd`, `level.gd`, `light_beam.gd`, and `player.gd` all run with `@tool`.
- **Consequence**: Audio code that requires `is_inside_tree() == true` or `get_tree() != null` to update state or that plays audio when `Engine.is_editor_hint()` is true breaks detached test execution or causes unwanted sound in the Godot editor.
- **Disposition**: Mitigate via: O3 (Settled in: Q3)

### I4 — Frame Drops from Repeated Procedural Waveform Synthesis on Physics and Test Hot Paths
- **Lens**: Performance and capacity
- **Severity**: Medium
- **Breaking**: No
- **Condition**: If procedural PCM byte buffers (`AudioStreamWAV.data`) are synthesized on every hazard activation, explosion, hit, or button press rather than synthesized once and reused.
- **Evidence**: `juego/scripts/level.gd:132-133` spawns waves every `0.50s–0.78s` in Hard mode, and `juego/tests/test_gameplay.gd:203-204,265-266` runs up to 90 `simulate_physics` steps in tight synchronous loops.
- **Consequence**: Re-allocating and computing PCM waveform arrays on every event adds avoidable CPU overhead on physics hot paths and slows down synchronous test execution.
- **Disposition**: Mitigate via: O4 (Settled in: Q4)

## 4. Obligations
<!-- entries · optional · repeat per entry -->

### O1 — Procedural-Only `AudioStreamPlayer` Allowance in Scene Subtree Verification
- **Requirements**: `juego/tests/test_gameplay.gd` permits `AudioStreamPlayer` nodes in scene subtrees provided any assigned `AudioStream` is generated in memory (`resource_path == ""`), while continuing to reject `Sprite2D`, `TextureRect`, and external audio file resources.
- **Applies**: Always
- **Verification**: Running `test_ac11_monochrome_primitives_only` in `juego/tests/test_gameplay.gd` passes with procedural `AudioStreamPlayer` nodes present and fails if an external resource path is attached.
- **Source**: I1

### O2 — Decoupled SFX Completion on Hazard Despawn/Scene Change and Strict Level Soundtrack Stop
- **Requirements**: Explosion SFX triggered in `_detonate_exploder()` and menu feedback SFX triggered on `PlayButton`, `GameOverMainMenuButton`, and `CompleteMainMenuButton` remain audible without being destroyed by hazard despawn or scene transition, while the level soundtrack stops immediately on Game Over, Level Complete, or transition to `MainMenu`.
- **Applies**: When an exploding hazard despawns or when a menu button triggers a scene transition
- **Verification**: Detonating an `EXPLODER` hazard records and plays the explosion SFX even after the exploder node despawns; pressing `Play` or `Main Menu` triggers the menu SFX; and `_on_player_died()`, `trigger_level_complete()`, and `_on_main_menu_pressed()` immediately stop the level soundtrack.
- **Source**: I2

### O3 — Detached SceneTree and `@tool` Editor Safety for Audio Triggers and State
- **Requirements**: All gameplay SFX triggers (`hit`, `laser`, `explosion`), menu button SFX triggers, and level soundtrack state transitions execute without error and update verifiable state even when scene instances are detached from the `SceneTree` (`!is_inside_tree()`), and suppress audio output when `Engine.is_editor_hint()` is true.
- **Applies**: Always
- **Verification**: Instantiating `main_menu.tscn`, `level.tscn`, `player.tscn`, and `light_beam.tscn` via `track(SCENE.instantiate())` outside the `SceneTree` and invoking button handlers, `take_damage(1)`, `simulate_physics(delta)`, `restart_level()`, `_on_player_died()`, and `trigger_level_complete()` updates observable SFX/soundtrack state and passes all `McpTestSuite` assertions with zero errors.
- **Source**: I3

### O4 — Cached Procedural Stream Reuse with Minimal Audio Objects
- **Requirements**: Each procedural sound effect (`hit`, `laser`, `explosion`, `menu`) and the level soundtrack stream is synthesized into an in-memory `AudioStreamWAV` once and reused across subsequent triggers without regenerating PCM buffers per event, using a minimal number of `AudioStreamPlayer` nodes.
- **Applies**: Always
- **Verification**: Multiple consecutive triggers of the same SFX or level soundtrack reuse the same pre-built `AudioStreamWAV` instance (`stream != null` and identical stream reference or pre-populated non-empty PCM data) and complete `test_gameplay.gd` without frame/timeout regressions.
- **Source**: I4

## 5. Decision Log
<!-- bullet list · required -->
- **Q1** — I1: Existing `test_ac11_monochrome_primitives_only` Forbids `AudioStreamPlayer` in Scene Subtrees: Mitigate via O1 by updating `_assert_subtree_monochrome_and_primitive` in `juego/tests/test_gameplay.gd` to allow `AudioStreamPlayer` nodes with procedural in-memory streams (`resource_path == ""`).
- **Q2** — I2: SFX Cut Off on Immediate Hazard Despawn or Scene Transition: Mitigate via O2 by ensuring explosion and menu button SFX playback outlives hazard despawn and scene transitions while strictly stopping the level soundtrack on Game Over, Level Complete, or exit to Main Menu.
- **Q3** — I3: Detached (`!is_inside_tree()`) Test Execution and `@tool` Editor Mode Safety: Mitigate via O3 by guarding playback against `Engine.is_editor_hint()` and ensuring all audio triggers and soundtrack states work deterministically when instantiated outside the `SceneTree`.
- **Q4** — I4: Frame Drops from Repeated Procedural Waveform Synthesis on Hot Paths: Mitigate via O4 by synthesizing procedural `AudioStreamWAV` streams once and reusing the cached streams across minimal `AudioStreamPlayer` objects.
