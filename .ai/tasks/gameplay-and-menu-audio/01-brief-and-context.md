---
task_name: gameplay-and-menu-audio
description: Procedural sound effects for player hits, laser/circle bursts, exploding hazards, and menu button presses, plus a simple looping procedural soundtrack during active level gameplay.
---

## 1. Task Brief

### Problem Statement
<!-- prose · required -->
"SHAPES & BEAMS" runs completely silently across menus and level gameplay, lacking audio cues for hazard activations, player hits, menu interactions, and background music.

### Expected Outcome
<!-- prose · required -->
Minimal, polished procedural audio across gameplay and UI: distinct synthesized sound effects play on player hit, laser/circle hazard activation, and exploder detonation; audible click feedback plays on all menu button presses; and a simple looping procedural soundtrack plays during active level gameplay without external audio assets.

### Acceptance Criteria
<!-- ordered list · required -->
1. All sound effects and the level soundtrack are synthesized procedurally in code with zero external audio asset files.
2. Taking player damage (`take_damage` when HP decreases) plays a distinct hit sound effect.
3. Rectangular light beams (`HazardType.BEAM`) and filling circles (`HazardType.CIRCLE`) entering `Phase.ACTIVE` play a distinct laser/burst sound effect.
4. Exploding hazards (`HazardType.EXPLODER`) detonating into radial projectiles play a distinct explosion sound effect.
5. Pressing any button in Main Menu (`DifficultyButton`, `PlayButton`, `QuitButton`) or Level overlay menus (`RetryButton`, `GameOverMainMenuButton`, `ReplayButton`, `CompleteMainMenuButton`) plays a menu feedback sound effect.
6. Active level gameplay (`is_level_running == true`) plays a simple looping soundtrack that starts on level start, stops immediately on Game Over or Level Complete, and restarts from the beginning on Retry or Replay.
7. Main Menu plays no background soundtrack, remaining silent except for button press feedback.

### Out of Scope
<!-- bullet list · optional -->
- External audio files (`.wav`, `.ogg`, `.mp3`).
- Beat-synchronized obstacle spawning.
- Volume sliders, mute toggles, or audio settings UI.
- Spatial/3D positional audio.
- Sound effects for player dash, hazard telegraph phases, or edge-projectile spawns.
- Changes to gameplay mechanics, difficulty scaling, or monochrome visual primitives.

## 2. Context

### Codebase
<!-- bullet list · required -->
- `juego/scenes/main_menu.tscn` & `juego/scripts/main_menu.gd` — Main Menu UI and button press handlers (`_on_difficulty_pressed`, `_on_play_pressed`, `_on_quit_pressed`) where menu feedback SFX triggers before scene transition or quit.
- `juego/scenes/level.tscn` & `juego/scripts/level.gd` — Level lifecycle controller (`_ready`, `restart_level`, `_on_player_died`, `trigger_level_complete`) and HUD overlay button handlers (`_on_retry_pressed`, `_on_replay_pressed`, `_on_main_menu_pressed`) governing the level soundtrack and overlay menu feedback SFX.
- `juego/scenes/light_beam.tscn` & `juego/scripts/light_beam.gd` — Consolidated hazard script handling `HazardType.BEAM` and `HazardType.CIRCLE` activation (`_enter_beam_phase(Phase.ACTIVE)`, `_enter_circle_phase(Phase.ACTIVE)`) and `HazardType.EXPLODER` detonation (`_detonate_exploder()`).
- `juego/scenes/player.tscn` & `juego/scripts/player.gd` — Player controller exposing `take_damage(amount)` and `hp_changed` signal where player hit SFX triggers when HP decreases.
- `juego/tests/test_gameplay.gd` — Existing `McpTestSuite` acceptance test suite (line 398 in `_assert_subtree_monochrome_and_primitive` currently asserts `assert_false(node is AudioStreamPlayer, ...)` from prior tasks when audio was out of scope).
- `juego/project.godot` — Godot 4.7 project configuration and autoload definitions.

### Conventions & Prior Art
<!-- bullet list · optional -->
- Official Godot 4 GDScript Style Guide — Static typing, `snake_case` files and functions, `PascalCase` nodes and enums.
- Minimal entity/script/object footprint — Consolidate functionality into minimal code, nodes, scenes, and scripts rather than proliferating separate nodes or files per sound/feature.
- Deterministic `simulate_physics(delta: float)` pattern — Gameplay and hazard phase transitions (`_enter_phase`, `_detonate_exploder`, `take_damage`) can be stepped deterministically in `McpTestSuite` tests.
- Procedural generation over external assets — Synthesize audio waveforms (`AudioStreamWAV` / `AudioStreamGenerator`) procedurally in GDScript, matching the procedural `Polygon2D` / `ColorRect` approach used for visuals.

### Related Work
<!-- bullet list · optional -->
- `.ai/tasks/jsab-core-gameplay/01-brief-and-context.md` — Foundational task dossier that established the Main Menu, 45-second survival level, player damage, and initial `test_ac11_monochrome_primitives_only` test suite.
- `.ai/tasks/difficulty-and-obstacles/01-brief-and-context.md` & `.ai/tasks/difficulty-and-obstacles/02-analysis.md` — Prior task dossiers that added `DifficultyButton` and consolidated `BEAM`, `CIRCLE`, `PROJECTILE`, and `EXPLODER` hazards into `light_beam.gd`.

### External References
<!-- bullet list · optional -->
- Godot 4.7 Audio Documentation (`AudioStreamPlayer`, `AudioStreamWAV`, `AudioStreamGenerator`, `AudioStreamGeneratorPlayback`, `AudioServer`) — Engine APIs for procedural PCM/waveform synthesis and non-positional playback.

### Constraints
<!-- bullet list · optional -->
- Strictly minimal code, nodes, objects, scenes, and scripts.
- Zero external audio or art asset files; synthesize all SFX and music procedurally in GDScript.
- Maintain 60 FPS performance during simultaneous hazard spawns/explosions without audio clipping or frame drops.
- Preserve existing gameplay mechanics, difficulty scaling, monochrome visual rules, and player 2D target-position hooks (`set_target_position`, `set_normalized_target_position`, `set_hand_tracking_target`).
- Execute scene, script, and test operations via `godot-ai` MCP tools against `juego/`.

## 3. Decision Log
<!-- bullet list · optional -->
- **Q1** — Task Name: Use `gameplay-and-menu-audio`.
- **Q2** — Problem & Expected Outcome: Add minimal, polished audio with distinct SFX for player hit, laser/circle activation, and explosions, menu button feedback, and a looping level soundtrack.
- **Q3** — Audio Asset Source: Generate all SFX and the level soundtrack procedurally in GDScript with zero external audio files.
- **Q4** — Gameplay Sound Effect Triggers: Trigger SFX on player damage (`Hit`), `HazardType.BEAM` and `HazardType.CIRCLE` entering `Phase.ACTIVE` (`Laser`), and `HazardType.EXPLODER` detonation (`Explosion`); keep dash, telegraph, and projectile spawns silent.
- **Q5** — Menu Feedback Scope & Triggers: Play menu feedback SFX on `pressed` for all buttons in Main Menu (`DifficultyButton`, `PlayButton`, `QuitButton`) and Level HUD overlays (`RetryButton`, `GameOverMainMenuButton`, `ReplayButton`, `CompleteMainMenuButton`).
- **Q6** — Level Soundtrack Behavior & Lifecycle: Play a simple looping procedural soundtrack only during active level gameplay (`is_level_running == true`), stopping on Game Over or Level Complete and restarting on Retry/Replay; keep Main Menu without background music.
- **Q7** — Out of Scope Boundaries: Exclude external audio files, beat-synced spawning, volume/mute UI, positional audio, and changes to gameplay mechanics or monochrome visual rules.
- **Q8** — Codebase Relevance: Include `main_menu`, `level`, `light_beam`, `player`, `test_gameplay.gd`, and `project.godot` in Codebase section.
- **Q9** — Conventions & Prior Art: Follow Godot 4 GDScript style guide, minimal entity/script/object footprint, deterministic `simulate_physics(delta)` testability, and procedural audio synthesis in GDScript.
- **Q10** — Related Work: Reference both `jsab-core-gameplay` (`01-brief-and-context.md`) and `difficulty-and-obstacles` (`01-brief-and-context.md`, `02-analysis.md`).
- **Q11** — External References: Reference Godot 4.7 Audio documentation (`AudioStreamPlayer`, `AudioStreamWAV`, `AudioStreamGenerator`, `AudioStreamGeneratorPlayback`, `AudioServer`).
- **Q12** — Constraints: Enforce strictly minimal code and objects, zero external assets, 60 FPS performance, untouched gameplay/visual/hand-tracking contracts, and `godot-ai` MCP workflow.
