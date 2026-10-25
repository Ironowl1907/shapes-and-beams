---
task_name: difficulty-and-obstacles
description: Selectable difficulty modes (Easy, Normal, Hard) scaling attack frequency and three new monochrome 2D hazard types (filling circles, edge-spawned un-telegraphed projectiles, and exploding projectile bursts) with minimal entity/script count.
---

## 1. Task Brief

### Problem Statement
<!-- prose · required -->
Existing dodge prototype only offers a single fixed-pace 45-second level with rectangular light beams, lacking difficulty scaling for varied player skill levels and lacking hazard variety for the science fair showcase.

### Expected Outcome
<!-- prose · required -->
Main Menu lets player select Easy, Normal, or Hard difficulty to adjust attack spawn frequency. Level spawns four monochrome primitive 2D hazard types—edge-to-edge light beams, multi-pattern filling circles, un-telegraphed projectiles from all screen edges, and stationary exploding objects that burst into radial projectiles—implemented with minimal scenes and scripts while keeping future hand-tracking compatibility intact.

### Acceptance Criteria
<!-- ordered list · required -->
1. Main Menu allows selecting one of three difficulty modes (Easy, Normal, Hard) before starting level.
2. Difficulty mode scales only attack spawn frequency across Easy, Normal, and Hard, keeping player HP (3), level duration (45s), and individual obstacle behaviors constant.
3. All four obstacle types (light beams, filling circles, edge projectiles, exploding objects) spawn in every difficulty mode.
4. Pressing "Retry" on Game Over or "Replay" on Level Complete restarts level using currently selected difficulty mode until returning to Main Menu.
5. Filling circle hazard spawns with non-damaging dim gray circular shadow showing full radius and fills using one of three patterns: center-out (growing inner circle), outside-in (shrinking outer ring), or angular sweep (0° to 360° sector).
6. Filling circle collision remains disabled while filling, activates as solid white circle for brief burst (~0.35s) once 100% filled to deal 1 HP damage on player overlap, then fades out and despawns.
7. Un-telegraphed projectile hazard spawns without preview from random positions along all four screen edges, travels in straight line across arena with active collision dealing 1 HP damage on contact, and despawns after exiting viewport bounds.
8. Exploding object hazard spawns stationary inside arena as non-damaging pulsing telegraph (~1.0s), then detonates into radial ring of active un-telegraphed projectiles and disappears.
9. Codebase uses minimal entities, scenes, and scripts, rendering all visuals with black, white, and grayscale primitive 2D shapes and zero external assets.

### Out of Scope
<!-- bullet list · optional -->
- Python script and MediaPipe hand-tracking implementation.
- Audio/music playback and beat-synchronized spawning.
- Color palettes beyond black, white, and grayscale.
- Difficulty scaling of player HP, level duration, or per-obstacle speed/telegraph duration (only attack frequency changes).
- Multiple levels, bosses, scoring systems, or persistent save data.

## 2. Context

### Codebase
<!-- bullet list · required -->
- `juego/scenes/main_menu.tscn` & `juego/scripts/main_menu.gd` — Main Menu UI and controller where Easy, Normal, and Hard difficulty selection is exposed before launching level.
- `juego/scenes/level.tscn` & `juego/scripts/level.gd` — 45-second level controller managing `spawn_timer` attack frequency, `_spawn_next_wave()` hazard spawning, `_clear_beams()` cleanup, and Retry/Replay state reset.
- `juego/scenes/light_beam.tscn` & `juego/scripts/light_beam.gd` — Existing `Area2D` hazard with `TELEGRAPH`/`ACTIVE`/`FADE_OUT` phases, procedural `Polygon2D` + `CollisionShape2D` geometry, and `"player"` group overlap damage.
- `juego/scenes/player.tscn` & `juego/scripts/player.gd` — Player `CharacterBody2D` in group `"player"` exposing `take_damage(1)` and 2D target-position hooks (`set_target_position`, `set_normalized_target_position`).
- `juego/tests/test_gameplay.gd` — Existing `McpTestSuite` acceptance test suite verifying menu actions, level progression, hazard phases, and monochrome primitive rules.
- `juego/project.godot` — Godot 4.7 project configuration and `godot_ai` MCP plugin registration.

### Conventions & Prior Art
<!-- bullet list · optional -->
- Official Godot 4 GDScript Style Guide — Static typing, `snake_case` files and functions, `PascalCase` nodes and enums.
- Deterministic `simulate_physics(delta: float)` pattern — Gameplay and hazard scripts expose `simulate_physics(delta)` so `McpTestSuite` tests can step physics deterministically without waiting frames.
- `Area2D` + `Polygon2D` + `CollisionShape2D` hazard architecture — Hazards generate primitive polygon visuals and collision shapes in code and call `take_damage(1)` on overlapping `"player"` group bodies.
- Minimal entity/script footprint — Consolidate hazard types into the fewest possible scenes and scripts rather than creating separate scenes/scripts per obstacle variant.

### Related Work
<!-- bullet list · optional -->
- `.ai/tasks/jsab-core-gameplay/01-brief-and-context.md` — Foundational task dossier that defined and delivered the initial single-mode light-beam dodge prototype.

### External References
<!-- bullet list · optional -->
- Godot 4.7 2D Documentation (`Area2D`, `Polygon2D`, `CollisionShape2D`, `CircleShape2D`, `RectangleShape2D`, `Control`) — Engine APIs for 2D collision shapes, procedural polygons, and UI controls.
- Just Shapes & Beats hazard mechanics — Prior art for telegraphed circular fills, radial projectile bursts, and un-telegraphed bullet hazards.

### Constraints
<!-- bullet list · optional -->
- Keep entity, scene, and script count to the minimum necessary.
- Visuals restricted strictly to black, white, and grayscale primitive 2D shapes (`Polygon2D`, `ColorRect`) with zero external art or audio assets.
- Preserve existing player 2D target-position API (`set_target_position`, `set_normalized_target_position`, `set_hand_tracking_target`) untouched while keeping hand-tracking implementation out of scope.
- Maintain 60 FPS in Godot 4.7 and execute scene/script/test operations via `godot-ai` MCP tools against `juego/`.

## 3. Decision Log
<!-- bullet list · optional -->
- **Q1** — Task Name: Use `difficulty-and-obstacles`.
- **Q2** — Problem & Expected Outcome: Expand single-pace light-beam prototype with selectable difficulty modes and three new monochrome 2D hazard behaviors (filling circles, edge-spawned un-telegraphed projectiles, exploding objects) with minimal entity/script footprint.
- **Q3** — Difficulty Modes (Options, Selection UI & Scaling): Provide Easy, Normal, and Hard modes selectable on Main Menu; keep player HP (3) and level timer (45s) constant.
- **Q4** — Filling Circle Obstacle Behavior & Fill Modes: Show non-damaging dim gray circular shadow for full radius, fill progressively in white, enable collision only when 100% filled for brief solid-white burst, then fade out.
- **Q5** — Un-telegraphed Projectiles Behavior: Spawn small solid-white projectiles with immediate active collision and no preview from all four screen edges (and exploding objects), moving in straight lines and despawning outside viewport bounds.
- **Q6** — Exploding Objects Behavior: Spawn inside arena, telegraph briefly, then detonate into radial burst of active un-telegraphed projectiles.
- **Q7** — Scope Boundaries & Minimal Entity Constraint: Keep hand tracking, audio, non-monochrome colors, scoring/saves, and multi-level progression out of scope; consolidate obstacles into minimal scenes and scripts.
- **Q8** — Filling Circle Fill Variations & Damage Timing: Support center-out, outside-in, and angular sweep (0° to 360°) fill patterns; collision active only for ~0.35s solid-white burst at 100% fill.
- **Q9** — Exploding Object Pre-Detonation Movement & Collision: Spawn stationary in arena as non-damaging pulsing telegraph (~1.0s), then detonate into radial ring of projectiles and disappear.
- **Q10** — Difficulty Mode Obstacle Availability & Retry Behavior: Spawn all 4 obstacle types on every difficulty, changing only attack spawn frequency between modes; Retry/Replay preserves selected difficulty.
- **Q11** — Codebase Relevance: Include `main_menu`, `level`, `light_beam`, `player`, `test_gameplay.gd`, and `project.godot` in Codebase section.
- **Q12** — Conventions & Prior Art: Follow Godot 4 GDScript style guide, `simulate_physics(delta)` testability pattern, `Area2D` + procedural `Polygon2D` + `CollisionShape2D` hazard structure, and minimal entity/script consolidation.
- **Q13** — Related Work: Reference `.ai/tasks/jsab-core-gameplay/01-brief-and-context.md` as foundational prior task.
- **Q14** — External References: Reference Godot 4.7 2D documentation and Just Shapes & Beats hazard mechanics.
- **Q15** — Constraints: Enforce minimal entity/script count, strict monochrome primitive 2D visuals, untouched 2D target-position player hooks, and 60 FPS Godot 4.7 MCP workflow.
