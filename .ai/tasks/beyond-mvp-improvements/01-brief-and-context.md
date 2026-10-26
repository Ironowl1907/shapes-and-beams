---
task_name: beyond-mvp-improvements
description: Replace fist-close dash with a timed defensive shield, expand arena hazards with closing walls, rotating saws, and three enemy archetypes (chaser, charger, turret), upgrade monochrome primitive visual polish and feedback, and optimize frame pacing and hand-tracking fluidity.
---

## 1. Task Brief

### Problem Statement
<!-- prose · required -->
Game prototype (`player.gd`, `level.gd`, `light_beam.gd`) feels like an MVP. Closed-fist gesture triggers directional dash (`0.18s` duration, `0.45s` cooldown) instead of defensive shield. Arena hazard roster only cycles four basic patterns (`BEAM`, `CIRCLE`, `PROJECTILE`, `EXPLODER`) without closing walls, saws, or enemy archetypes. Combat visual feedback and overlay transitions are minimal. 30 FPS webcam UDP tracking updates against 60 FPS rendering and per-wave polygon/node allocations need profiling and smoothing.

### Expected Outcome
<!-- prose · required -->
Closing fist (via existing `hand_tracking_client.gd` detection) or pressing action key activates a timed shield (`1.0s` duration, `1.5s` cooldown) granting full damage immunity, destroying contacting projectiles, and keeping `100%` movement speed without directional dash burst. Arena wave spawner integrates five new hazard and enemy types alongside existing four: Closing Walls, Hazard Saws, Chaser Drone, Charger / Dasher, and Turret / Sniper (9 total types). Player shield/hit feedback, hazard animations, and level overlay transitions gain monochrome primitive visual polish while keeping `main_menu.tscn` layout untouched. Profiled CPU/memory/object bottlenecks and 30-to-60 FPS hand-tracking micro-stutters are resolved with documented before/after metrics.

### Acceptance Criteria
<!-- ordered list · required -->
1. Rising-edge closed-fist detection (`consume_fist_dash_trigger()` in `hand_tracking_client.gd`) and `dash` / `shield` input action activate player shield for `1.0s` (`SHIELD_DURATION`) with `1.5s` cooldown (`SHIELD_COOLDOWN`), removing directional dash velocity burst while keeping `100%` normal movement speed and backward-compatible method/action aliases (`trigger_dash` / `trigger_shield`).
2. While shield is active, player takes `0` damage from all hazards and enemies, and contacting projectiles despawn on impact with visual/audio block feedback.
3. Arena hazard system (`light_beam.gd` and `level.gd`) implements Closing Walls / Crushing Hazards that telegraph along arena borders (`~1.0s`), slam inward leaving a safe corridor gap, hold briefly, and retract/fade out.
4. Arena hazard system implements Rotating Hazard Saws rendered as toothed monochrome `Polygon2D` shapes that telegraph (`~0.8s–1.0s`) and traverse or bounce across the arena before despawning.
5. Arena hazard system implements three distinct enemy archetypes: (a) Chaser / Homing Drone that telegraphs and steers toward the player for a fixed lifetime (`~3.0s–4.0s`), (b) Charger / Dasher that rotates/locks onto the player during telegraph (`~1.0s`) and lunges rapidly in a straight line, and (c) Turret / Sniper that spawns stationary, tracks player with an aim telegraph line, and fires an aimed projectile burst or beam.
6. Wave spawning in `level.gd` incorporates all 9 hazard/enemy types across Easy, Normal, and Hard difficulties without breaking existing `spawn_beam`, `spawn_circle`, `spawn_projectile`, or `spawn_exploder` API contracts.
7. Monochrome primitive visual polish is added for player shield barrier ring/cooldown state, movement/hit/block ripple and screen shake, hazard/enemy telegraphs and bursts, and smooth fade/scale transitions on `GameOverPanel` and `LevelCompletePanel`, while keeping `main_menu.tscn` structure untouched and passing `_assert_subtree_monochrome_and_primitive` (`r == g == b`, no `Sprite2D` or `TextureRect`).
8. CPU frame time, physics time, node count, and polygon allocations are profiled before and after optimization; static hazard unit polygons are precomputed/reused so peak waves maintain `60 FPS` (`<= 16.67 ms` frame time) with zero orphan nodes.
9. Player hand-tracking target following (`player.gd`) and 21-landmark hand shadow rendering (`level.gd`) apply frame-rate-independent smoothing/interpolation between 30 FPS UDP packets and 60 FPS render frames to eliminate visual stepping while keeping fist-close shield activation instant on packet arrival.

### Out of Scope
<!-- bullet list · optional -->
- Redesigning, restructuring, or adding submenus to `main_menu.tscn`.
- Modifying `tracker_server` UDP binary protocol (`<i63f` / `<i`) or replacing `evaluate_closed_fist()` curl detection math.
- Non-monochrome colors (`r != g` or `g != b`) or external image, sprite, or texture assets (`Sprite2D`, `TextureRect`).
- Player offensive weapons or attacks (gameplay remains dodge + defensive shield).
- Multi-level campaign progression or persistent save files.

## 2. Context

### Codebase
<!-- bullet list · required -->
- `juego/scenes/player.tscn` & `juego/scripts/player.gd` — Player `CharacterBody2D` where directional dash is replaced with timed shield (`1.0s` duration, `1.5s` cooldown, `100%` movement speed, projectile block/destroy), shield/hit/trail visual feedback, and 30-to-60 FPS target-position smoothing.
- `juego/scenes/light_beam.tscn` & `juego/scripts/light_beam.gd` — Unified `Area2D` hazard entity (`BEAM`, `CIRCLE`, `PROJECTILE`, `EXPLODER`) extended with Closing Walls, Hazard Saws, Chaser Drone, Charger / Dasher, Turret / Sniper, shield projectile collision handling, precomputed static unit polygons, and visual effects.
- `juego/scenes/level.tscn` & `juego/scripts/level.gd` — Arena survival controller driving 9-pattern wave spawning across difficulties, 30-to-60 FPS hand-shadow landmark interpolation, camera shake/feedback, overlay transitions (`GameOverPanel`, `LevelCompletePanel`), and node cleanup.
- `juego/scripts/hand_tracking_client.gd` — Autoload UDP hand-tracking client whose existing `evaluate_closed_fist()` and `consume_fist_dash_trigger()` detection is preserved and wired to shield activation.
- `juego/scenes/main_menu.tscn` & `juego/scripts/main_menu.gd` — Main menu scene and controller whose structure and clean simplicity must be preserved without regression.
- `juego/project.godot` — Godot 4.7 project configuration defining input actions and autoload singletons.
- `juego/tests/test_gameplay.gd` — `McpTestSuite` verification suite testing player shield/movement, all 9 hazard/enemy types, difficulty scaling, audio, hand tracking, performance/fluidity, and `_assert_subtree_monochrome_and_primitive`.

### Conventions & Prior Art
<!-- bullet list · optional -->
- Official Godot 4 GDScript Style Guide — Use static typing everywhere, `snake_case` functions/variables, and `PascalCase` nodes/enums.
- Consolidated Minimal Entity/Script Footprint — Extend unified `light_beam.tscn` / `light_beam.gd` and existing controllers (`player.gd`, `level.gd`) rather than proliferating separate scenes and scripts per obstacle/enemy.
- Procedural Monochrome Primitives & Cached Procedural Audio — Render all visuals with grayscale 2D primitives (`Polygon2D`, `Line2D`, `ColorRect` where `r == g == b`) and synthesize SFX into cached static `AudioStreamWAV` streams (`22050 Hz` 16-bit mono PCM).
- Deterministic `simulate_physics(delta)` Stepping — Drive movement, shield timers, smoothing, and hazard lifecycles through `simulate_physics(delta)` for deterministic `McpTestSuite` testing without wall-clock waits.

### Related Work
<!-- bullet list · optional -->
- `.ai/tasks/jsab-core-gameplay/01-brief-and-context.md` (commit `c2b0f08`) — Established core player movement, dash, `LIGHT_BEAM` hazard phases, and the monochrome primitive visual rule.
- `.ai/tasks/difficulty-and-obstacles/01-brief-and-context.md` (commit `3726a66`) — Added difficulty scaling (`Easy`, `Normal`, `Hard`) and `CIRCLE`, `PROJECTILE`, and `EXPLODER` hazards.
- `.ai/tasks/gameplay-and-menu-audio/01-brief-and-context.md` (commit `6e80ac3`) — Added procedural `AudioStreamWAV` music and SFX for player hit, hazards, and menu buttons.
- `.ai/tasks/hand-tracking-control/01-brief-and-context.md` (commit `fa70aa9`) — Added `HandTrackingClient` UDP polling, palm-center target following, closed-fist gesture trigger, HUD status pill, and procedural hand shadow.

### External References
<!-- bullet list · optional -->
- Godot 4.7 2D Physics, Rendering & Profiling APIs (`CharacterBody2D`, `Area2D`, `Polygon2D`, `Line2D`, `Performance.get_monitor()`, `Time.get_ticks_usec()`) — Engine APIs for collision detection, primitive geometry rendering, and CPU/memory/object profiling.
- Frame-Rate-Independent Exponential Smoothing (`lerp` with `1.0 - exp(-speed * delta)`) — Real-time interpolation formula for smoothing 30 Hz webcam landmark updates across 60 Hz render frames without frame-rate sensitivity.

### Constraints
<!-- bullet list · optional -->
- Localize changes and preserve working systems (`evaluate_closed_fist()` detection logic, `main_menu.tscn` structure, difficulty progression, and public spawn/tracking hooks).
- Zero external art/texture/audio asset files; all nodes in `main_menu.tscn`, `level.tscn`, `player.tscn`, and `light_beam.tscn` must pass `_assert_subtree_monochrome_and_primitive` (`r == g == b`, no `Sprite2D` or `TextureRect`).
- Profile CPU/physics/node/allocation metrics before and after changes; precompute/reuse static polygon arrays so peak waves stay within `<= 16.67 ms` (60 FPS) with zero orphan nodes.
- Eliminate 30-to-60 FPS hand-tracking micro-stutters via interpolation while keeping fist-close shield activation immediate on packet receipt.
- Execute scene, script, and test operations via `godot-ai` MCP tools against `juego/`.

## 3. Decision Log
<!-- bullet list · optional -->
- **Q1** — Task Name: Use `beyond-mvp-improvements`.
- **Q2** — Problem Statement & Expected Outcome: Replace fist-close dash with defensive shield, expand hazard/enemy variety, upgrade monochrome primitive visual polish while keeping `main_menu.tscn` intact, and profile/fix technical performance and 30-to-60 FPS visual fluidity.
- **Q3** — Shield Mechanic Specifications: Full damage immunity during active shield, destroy contacting projectiles, keep `100%` normal movement speed while shielded, and preserve backward-compatible `dash` / `trigger_dash()` aliases alongside shield APIs.
- **Q4** — New Enemies & Obstacles Specifications: Add Closing Walls (opposite-edge telegraph and inward slam with safe corridor), Rotating Hazard Saws (toothed `Polygon2D` telegraph and traversal/bounce), and new enemy types into the survival loop.
- **Q5** — Visual Polish Scope & Art Direction: Add monochrome primitive shield ring/cooldown visuals, hit/block ripple and screen shake, hazard/enemy animations, and smooth `GameOverPanel`/`LevelCompletePanel` transitions while keeping `main_menu.tscn` untouched and passing `_assert_subtree_monochrome_and_primitive`.
- **Q6** — Performance & Visual Fluidity Acceptance Criteria: Profile baseline vs. optimized CPU/physics/node/allocation metrics to hold `<= 16.67 ms` (60 FPS) with zero orphans, and interpolate 30 FPS hand-tracking positions/landmarks across 60 FPS frames with zero added gesture latency.
- **Q7** — Out of Scope & Dependencies: Keep `main_menu.tscn` redesign, `tracker_server` UDP/fist-detection rewrites, non-monochrome/texture assets, and player weapons out of scope; no external blockers.
- **Q8** — Shield Activation Mode: Use Option A — timed `1.0s` active shield with `1.5s` cooldown triggered on rising-edge fist close (`consume_fist_dash_trigger()`) or `dash` / `shield` action press.
- **Q9** — Enemy Archetype Count: Include all three enemy archetypes (Chaser / Homing Drone, Charger / Dasher, and Turret / Sniper) alongside Closing Walls and Hazard Saws (9 total hazard/enemy types).
- **Q10** — Codebase Relevance: Include `player.tscn`/`player.gd`, `light_beam.tscn`/`light_beam.gd`, `level.tscn`/`level.gd`, `hand_tracking_client.gd`, `main_menu.tscn`/`main_menu.gd`, `project.godot`, and `test_gameplay.gd`.
- **Q11** — Conventions & Prior Art: Follow Godot 4 GDScript style guide, consolidated minimal scene/script footprint, procedural monochrome 2D primitives with cached procedural `AudioStreamWAV`, and deterministic `simulate_physics(delta)` stepping.
- **Q12** — Related Work: Reference prior dossiers (`jsab-core-gameplay`, `difficulty-and-obstacles`, `gameplay-and-menu-audio`, `hand-tracking-control`) and commits `c2b0f08`, `3726a66`, `6e80ac3`, and `fa70aa9`.
- **Q13** — External References: Reference Godot 4.7 2D Physics/Rendering/Profiling APIs and frame-rate-independent exponential smoothing (`lerp` with `1.0 - exp(-speed * delta)`).
- **Q14** — Constraints: Enforce localized changes preserving working systems, strict monochrome primitive compliance, profiled 60 FPS (`<= 16.67 ms`) with zero orphans, interpolated hand-tracking motion with instant gesture trigger, and `godot-ai` MCP workflow.
