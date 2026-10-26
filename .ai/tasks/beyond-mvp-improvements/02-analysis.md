---
task_name: beyond-mvp-improvements
---

## 1. Change Summary
<!-- prose · required -->
Replaces the player's directional dash burst (`0.18s` duration, `0.45s` cooldown, `1150.0` speed) in `juego/scripts/player.gd` with a timed defensive shield (`1.0s` duration, `1.5s` cooldown, `100%` normal movement speed, zero velocity burst) activated via rising-edge closed-fist detection (`consume_fist_dash_trigger()` in `juego/scripts/hand_tracking_client.gd`) or `dash` / `shield` input actions, granting full damage immunity and destroying contacting projectiles with visual/audio block feedback while preserving backward-compatible method, property, and signal aliases. Expands `juego/scripts/light_beam.gd` and `juego/scripts/level.gd` from 4 to 9 monochrome primitive hazard and enemy types (`BEAM`, `CIRCLE`, `PROJECTILE`, `EXPLODER`, `CLOSING_WALLS`, `SAW`, `CHASER`, `CHARGER`, `TURRET`) across `Easy`, `Normal`, and `Hard` difficulty wave progressions. Adds monochrome primitive visual polish (shield ring/cooldown indicator, hit/block ripples, screen shake, hazard/enemy telegraphs, and smooth `GameOverPanel` / `LevelCompletePanel` transitions) while leaving `juego/scenes/main_menu.tscn` structure intact. Precomputes and reuses static unit polygon geometries and point buffers to keep peak waves within `<= 16.67 ms` (`60 FPS`) with zero orphan nodes, and applies frame-rate-independent exponential smoothing (`1.0 - exp(-speed * delta)`) to 30-to-60 FPS player target following and 21-landmark hand shadow rendering with instant closed-fist shield trigger.

## 2. Impact Map
<!-- bullet list · required -->
- `juego/scenes/player.tscn` & `juego/scripts/player.gd` — Relationship: origin — Replaces directional dash burst with `1.0s` shield (`1.5s` cooldown, `100%` speed, projectile block feedback), adds shield/hit/trail monochrome primitives, and smooths 30-to-60 FPS target-position following while keeping backward-compatible `dash` aliases — Impacts: I1, I2, I4, I5, I6
- `juego/scenes/light_beam.tscn` & `juego/scripts/light_beam.gd` — Relationship: origin — Extends unified `Area2D` hazard entity with 5 new hazard/enemy types (`CLOSING_WALLS`, `SAW`, `CHASER`, `CHARGER`, `TURRET`), deterministic detached-tree player/shield overlap handling, projectile destruction on shield contact, and precomputed static unit polygons — Impacts: I2, I3, I5, I6
- `juego/scenes/level.tscn` & `juego/scripts/level.gd` — Relationship: origin — Schedules all 9 hazard/enemy types across difficulties, steps `BeamContainer` hazards in detached simulations, interpolates 21-landmark hand shadow positions across 60 FPS frames, and drives screen shake and overlay transitions — Impacts: I1, I3, I4, I5, I6
- `juego/project.godot` — Relationship: origin — Registers backward-compatible `dash` and `shield` input actions alongside existing movement and autoload settings — Impacts: I1
- `juego/scripts/hand_tracking_client.gd` — Relationship: upstream — Supplies 30 FPS UDP 21-landmark packets, mirrored palm-center targets, and rising-edge `consume_fist_dash_trigger()` events consumed for instant shield activation and smoothed rendering — Impacts: I1, I4
- `juego/scenes/main_menu.tscn` & `juego/scripts/main_menu.gd` — Relationship: downstream — Boot menu scene whose node hierarchy and button contracts must remain untouched while passing monochrome primitive checks — Impacts: I5
- `juego/tests/test_gameplay.gd` — Relationship: downstream — `McpTestSuite` runner instantiating scenes detached from `SceneTree` (`!is_inside_tree()`) and asserting player shield/dash aliases, hazard lifecycles, difficulty scaling, audio, hand tracking, monochrome primitives, and 60 FPS performance — Impacts: I1, I2, I3, I4, I5, I6

## 3. Impacts
<!-- entries · required · repeat per entry -->

### I1 — Shield Replacement Breaks Existing Dash Velocity Burst and `0.18s`/`0.45s` Timing Assertions in `test_gameplay.gd` and `level.gd`
- **Lens**: Contracts and interfaces
- **Severity**: High
- **Breaking**: Yes
- **Condition**: Unconditional
- **Evidence**: `juego/scripts/player.gd:16-18,103-110,167-192` implements directional dash burst (`DASH_SPEED = 1150.0`, `DASH_DURATION = 0.18`, `DASH_COOLDOWN = 0.45`); `juego/tests/test_gameplay.gd:84-105` asserts horizontal burst displacement (`assert_gt(player.global_position.x, start_x)`) and expiry after `0.20s`; `juego/tests/test_gameplay.gd:442-446` steps `0.25s` expecting invincibility to expire before testing hit SFX; `juego/tests/test_gameplay.gd:706-715` steps `0.75s` expecting duration plus cooldown to finish; `juego/scripts/level.gd:546,553` and `juego/project.godot:58` reference `trigger_dash`, `is_dashing`, and input action `dash`.
- **Consequence**: Removing the directional velocity burst and changing timing to `SHIELD_DURATION = 1.0s` and `SHIELD_COOLDOWN = 1.5s` causes `test_ac5_player_dash_and_invincibility`, `test_procedural_audio_sfx_and_soundtrack`, and `test_hand_tracking_closed_fist_rising_edge_dash` to fail unless `player.gd` keeps synchronized backward-compatible aliases (`is_dashing`/`is_shield_active`, `trigger_dash`/`trigger_shield`, `dash`/`shield`) and `test_gameplay.gd` is updated to assert `1.0s` shield duration, `1.5s` cooldown, and `100%` normal movement speed without velocity burst.
- **Disposition**: Mitigate via: O1 (Settled in: Q1)

### I2 — Detached-Tree Collision Blindness (`!is_inside_tree()`) and Missing Projectile-Only Shield Destruction & Block Feedback in `light_beam.gd` and `player.gd`
- **Lens**: Behavior and regressions
- **Severity**: High
- **Breaking**: Yes
- **Condition**: Unconditional
- **Evidence**: `juego/scripts/light_beam.gd:599-610` exits early when `not is_inside_tree()` and relies solely on `get_overlapping_bodies()` and `body_entered`, which do not fire in detached `McpTestSuite` `simulate_physics(delta)` loops (`juego/tests/test_gameplay.gd:140,185,323,365`); furthermore, `light_beam.gd:604` calls `body.call("take_damage", 1)` identically for all hazard types without distinguishing projectiles from non-projectile hazards, and `juego/scripts/player.gd:200-202` silently returns when invincible (`juego/tests/test_gameplay.gd:441` asserts `hit_sfx_play_count == 0` when damage is blocked).
- **Consequence**: Contacting projectiles (`PROJECTILE` from edges, exploders, or turrets) will neither despawn on shield impact nor trigger visual/audio block feedback (violating AC2), or non-projectile hazards (`BEAM`, `CIRCLE`, `CLOSING_WALLS`, `SAW`, `CHASER`, `CHARGER`, `TURRET` body) would erroneously despawn on shield contact, and synchronous `simulate_physics(delta)` tests in `test_gameplay.gd` cannot verify hazard-player or projectile-shield collisions when detached from `SceneTree`.
- **Disposition**: Mitigate via: O2 (Settled in: Q2)

### I3 — Consolidated `LightBeam` Single-Node Collisions, Detached-Tree Enemy Target Lookup, and `BeamContainer` Lifecycle Across 9 Hazard/Enemy Types
- **Lens**: Responsibilities and boundaries
- **Severity**: High
- **Breaking**: Yes
- **Condition**: Unconditional
- **Evidence**: `juego/scenes/light_beam.tscn:11-21` provides a single `BeamVisual`, `CenterLine`, and `CollisionShape2D`; `juego/scripts/level.gd:239-257` does not step `BeamContainer` children during detached `level.simulate_physics(delta)` runs and `level.gd:692` hardcodes `current_wave % 4`; `juego/tests/test_gameplay.gd:208,265-278` asserts `BeamContainer` child cleanup on level end and checks that all hazard types spawn across Easy, Normal, and Hard difficulties.
- **Consequence**: Representing Closing Walls with a single full-arena `CollisionShape2D` would damage the player inside the safe corridor gap; homing/aiming enemies (`CHASER`, `CHARGER`, `TURRET`) querying `SceneTree` groups directly fail when detached from `SceneTree`; turret-fired projectiles or wall segments parented outside `BeamContainer` survive `_clear_beams()`; and `level.simulate_physics(delta)` not stepping `BeamContainer` children when detached leaves hazards frozen in `test_gameplay.gd`.
- **Disposition**: Mitigate via: O3 (Settled in: Q3)

### I4 — 30-to-60 FPS Exponential Smoothing vs. Synchronous Target-Convergence Assertions and Instant Fist-Close Shield Trigger
- **Lens**: Behavior and regressions
- **Severity**: High
- **Breaking**: Yes
- **Condition**: If exponential smoothing overwrites raw `player.target_position`, interpolates initial hand-shadow appearance from `(0, 0)`, or uses a damping rate too slow for existing fixed-tick convergence tests.
- **Evidence**: `juego/tests/test_gameplay.gd:66-74` asserts `player.global_position.distance_to(target) < 5.0` after 20 ticks (`0.32s`); `juego/tests/test_gameplay.gd:673-679` asserts `player.target_position.distance_to(expected_screen_target) < 2.0` after 1 tick and `player.global_position.distance_to(expected_screen_target) < 8.0` after 25 ticks (`0.40s`); `juego/tests/test_gameplay.gd:808-810` asserts immediate fingertip contraction and scale pulse on `ingest_hand_packet(fist_pkt)`.
- **Consequence**: Overwriting `player.target_position` with a lagged value or under-damping player/shadow interpolation breaks existing target-following and hand-shadow tests in `test_gameplay.gd` or introduces gesture latency on closed-fist shield activation (violating AC9).
- **Disposition**: Mitigate via: O4 (Settled in: Q4)

### I5 — Overlay Transition Animations (`GameOverPanel`, `LevelCompletePanel`) and Screen Shake vs. Synchronous Visibility and Monochrome Assertions
- **Lens**: User experience
- **Severity**: Medium
- **Breaking**: Yes
- **Condition**: If smooth panel transitions delay `.visible = true` on trigger or delay `.visible = false` on `restart_level()`, or if screen shake offsets `Player` global coordinates outside viewport bounds.
- **Evidence**: `juego/tests/test_gameplay.gd:175,181,209,215` asserts `game_over_panel.visible == true` immediately on 0 HP, `complete_panel.visible == true` immediately at `45.0s`, and `.visible == false` immediately after `_on_retry_pressed()` / `_on_replay_pressed()`; `juego/tests/test_gameplay.gd:862-885` enforces `_assert_subtree_monochrome_and_primitive` across all scenes.
- **Consequence**: Deferring `.visible` state changes to tween completion breaks Game Over, Level Complete, Retry, and Replay assertions in `test_gameplay.gd`, and non-grayscale colors or un-reset screen shake offsets break monochrome compliance or arena alignment on restart.
- **Disposition**: Mitigate via: O5 (Settled in: Q5)

### I6 — Per-Frame `PackedVector2Array` / `Shape2D` Allocations and Visual Effect Node Churn Under 9-Hazard Peak Waves
- **Lens**: Performance and capacity
- **Severity**: Medium
- **Breaking**: No
- **Condition**: Unconditional
- **Evidence**: `juego/scripts/light_beam.gd:475-569` allocates new `PackedVector2Array` and `Shape2D` instances on every spawn and rebuilds 32-to-66-vertex circle polygons every physics frame during telegraph; `juego/scripts/level.gd:622-677` allocates 8 new `PackedVector2Array` buffers every frame in `_update_hand_shadow()`.
- **Consequence**: Adding 5 more complex hazard/enemy geometries (toothed saws, closing walls, drones, chargers, aiming turrets) and visual ripples on top of per-frame array allocations increases allocation pressure and risks frame times exceeding `16.67 ms` (`60 FPS`) or leaving orphan nodes (violating AC8).
- **Disposition**: Mitigate via: O6 (Settled in: Q6)

## 4. Obligations
<!-- entries · optional · repeat per entry -->

### O1 — Backward-Compatible Shield/Dash Aliases and Updated Shield Timing & Movement Contracts
- **Requirements**: `juego/project.godot` and `juego/scripts/player.gd` expose both `dash` and `shield` input actions, methods (`trigger_dash` and `trigger_shield`), signals (`dashed` and `shield_activated`), and synchronized state properties (`is_dashing` / `is_shield_active`, `dash_timer` / `shield_timer`, `dash_cooldown_timer` / `shield_cooldown_timer`) that activate a `1.0s` shield (`SHIELD_DURATION`) with a `1.5s` cooldown (`SHIELD_COOLDOWN`) while keeping `100%` normal movement speed and zero directional velocity burst; `juego/tests/test_gameplay.gd` verifies the `1.0s` duration, `1.5s` cooldown, and non-burst movement contract across keyboard, mouse, and closed-fist triggers.
- **Applies**: Always
- **Verification**: Calling `trigger_shield()` or `trigger_dash()` sets both `is_shield_active` and `is_dashing` to `true` for `1.0s`, applies a `1.5s` cooldown, leaves a stationary player's position unchanged when no movement input is active, preserves `100%` normal movement speed when moving, and passes all shield and audio tests in `juego/tests/test_gameplay.gd`.
- **Source**: I1

### O2 — Deterministic Detached-Tree Overlap Detection and Projectile-Only Shield Destruction with Block Feedback
- **Requirements**: Active hazards and enemies in `juego/scripts/light_beam.gd` detect player overlap during `simulate_physics(delta)` whether attached to or detached from the `SceneTree` (`!is_inside_tree()`); when the player's shield is active, contacting `PROJECTILE` hazards immediately despawn and trigger distinct player shield-block visual and audio feedback (`last_sfx_played == &"shield_block"`, without incrementing `hit_sfx_play_count`), whereas non-projectile hazards and enemy bodies deal `0` damage without despawning on shield contact.
- **Applies**: Always
- **Verification**: Stepping `simulate_physics(delta)` on a detached `Level` or `LightBeam` instance where an active `PROJECTILE` overlaps a shielded `Player` despawns the projectile, keeps `player.current_hp` unchanged, increments shield-block feedback (`block_sfx_play_count > 0`, `hit_sfx_play_count == 0`), and leaves non-projectile hazards (`BEAM`, `CIRCLE`, `CLOSING_WALLS`, `SAW`, `CHASER`, `CHARGER`, `TURRET`) intact while dealing `0` damage.
- **Source**: I2

### O3 — Unified `BeamContainer` Parenting, Collision-Free Closing-Wall Corridor, Detached-Safe Enemy Targeting, and 9-Type Wave Progression
- **Requirements**: All 9 hazard and enemy types (`BEAM`, `CIRCLE`, `PROJECTILE`, `EXPLODER`, `CLOSING_WALLS`, `SAW`, `CHASER`, `CHARGER`, `TURRET`), including opposing closing-wall segments and turret/exploder projectiles, are parented under `BeamContainer`, stepped during detached `Level.simulate_physics(delta)` runs, and cleared to `0` children on `_clear_beams()`; `CLOSING_WALLS` leaves a genuinely collision-free safe corridor gap between opposing walls; `CHASER`, `CHARGER`, and `TURRET` resolve player positions without requiring `SceneTree` attachment; and `Level` wave spawning schedules all 9 types across `Easy`, `Normal`, and `Hard` difficulties while preserving existing `spawn_*` and `configure*` method contracts.
- **Applies**: Always
- **Verification**: Running `juego/tests/test_gameplay.gd` confirms all 9 hazard/enemy types spawn and advance phases in detached `Level` instances across `Easy`, `Normal`, and `Hard`, a player positioned inside the `CLOSING_WALLS` safe corridor takes `0` damage during active slam while a player inside a wall segment takes damage, `CHASER`/`CHARGER`/`TURRET` track and attack the player without `SceneTree` errors, and `BeamContainer.get_child_count()` drops to `0` on Game Over, Level Complete, and `restart_level()`.
- **Source**: I3

### O4 — Frame-Rate-Independent 30-to-60 FPS Exponential Smoothing with Target Convergence and Instant Fist Trigger
- **Requirements**: `juego/scripts/player.gd` preserves `target_position` as the latest clamped target coordinate while smoothing 30-to-60 FPS tracking motion via frame-rate-independent exponential smoothing (`1.0 - exp(-speed * delta)`) tuned to converge within `< 5.0 px` in `0.32s` (`20` ticks at `0.016s`) and `< 8.0 px` in `0.40s` (`25` ticks at `0.016s`); `juego/scripts/level.gd` snaps hand-shadow landmarks on initial hand acquisition and smoothly interpolates subsequent 21-landmark updates across 60 FPS frames while triggering closed-fist shield activation and fingertip contraction/pulse immediately on packet receipt.
- **Applies**: When external hand-tracking or target-following updates are active
- **Verification**: Stepping `Player` and `Level` in `juego/tests/test_gameplay.gd` confirms `player.target_position` matches the newest packet target within `< 2.0 px` on tick 1, `player.global_position` converges within `< 5.0 px` in 20 ticks and `< 8.0 px` in 25 ticks, intermediate 60 FPS frames between 30 FPS packets move smoothly without stepping, and `ingest_hand_packet(fist_pkt)` activates the shield and pulses `HandShadow` on the same tick.
- **Source**: I4

### O5 — Synchronous Overlay Visibility Invariants, Resettable Screen Shake, and Strict Monochrome Primitive Compliance
- **Requirements**: `GameOverPanel` and `LevelCompletePanel` set `.visible = true` immediately upon Game Over and Level Complete while animating their grayscale `modulate` alpha and scale during `simulate_physics(delta)`, and immediately reset `.visible = false` along with panel transforms and screen-shake offsets on `restart_level()`; `juego/scenes/main_menu.tscn` structure remains untouched, and all scenes and dynamic visual polish nodes pass `_assert_subtree_monochrome_and_primitive` (`r == g == b`, no `Sprite2D` or `TextureRect`).
- **Applies**: When overlay transitions, screen shake, or visual polish primitives are rendered
- **Verification**: `test_ac8_and_ac9_hp_damage_iframes_and_game_over`, `test_ac10_level_survival_45_seconds_and_replay`, `test_ac1_and_ac2_main_menu_structure_and_actions`, and `test_ac11_monochrome_primitives_only` pass in `juego/tests/test_gameplay.gd`, and overlay `modulate.a` / `scale` and screen-shake offsets animate and reset cleanly.
- **Source**: I5

### O6 — Precomputed Static Unit Polygons, Reusable Vertex Buffers, and Profiled 60 FPS Peak-Wave Budget
- **Requirements**: Static unit `PackedVector2Array` polygons (circle, octagon, projectile, toothed saw, chaser drone, charger, turret, fingertip, shield ring) and reusable landmark/bone point buffers are precomputed and reused across `juego/scripts/light_beam.gd`, `juego/scripts/player.gd`, and `juego/scripts/level.gd` without redundant per-frame vertex array reallocations, keeping profiled peak-wave CPU/physics frame time `<= 16.67 ms` (`60 FPS`) with zero orphan nodes.
- **Applies**: Always
- **Verification**: Automated performance and profiling tests in `juego/tests/test_gameplay.gd` record baseline vs. optimized CPU/physics step times, node counts, and static polygon reuse across peak 9-hazard waves, confirming average and peak step times stay `<= 16.67 ms` and orphan node delta equals `0` after `_clear_beams()`.
- **Source**: I6

## 5. Decision Log
<!-- bullet list · required -->
- **Q1** — I1: Shield Replacement vs. Existing Dash Velocity Burst and Timing Assertions: Confirmed and mitigated via O1 by preserving backward-compatible `dash` and `shield` input actions, methods, signals, and synchronized state properties on `player.gd` while updating `test_gameplay.gd` for the `1.0s` shield duration, `1.5s` cooldown, and `100%` normal movement speed with zero directional burst.
- **Q2** — I2: Detached-Tree Collision Blindness (`!is_inside_tree()`) and Projectile-Only Shield Destruction & Block Feedback: Confirmed and mitigated via O2 by supporting deterministic overlap detection in `simulate_physics(delta)` when detached from `SceneTree`, destroying contacting `PROJECTILE` hazards on active shield impact with dedicated visual/audio block feedback (`last_sfx_played == &"shield_block"`, `hit_sfx_play_count` unchanged), and keeping non-projectile hazards/enemies intact while dealing `0` damage.
- **Q3** — I3: Consolidated `LightBeam` Collision Shapes, Detached-Tree Enemy Target Lookup, and `BeamContainer` Lifecycle Across 9 Hazard/Enemy Types: Confirmed and mitigated via O3 by parenting all 9 hazard/enemy types (including paired closing-wall segments with a collision-free corridor gap and turret/exploder projectiles) under `BeamContainer`, resolving player positions safely when detached from `SceneTree`, stepping `BeamContainer` children during detached `Level.simulate_physics(delta)`, and scheduling all 9 types across `Easy`, `Normal`, and `Hard` difficulties.
- **Q4** — I4: 30-to-60 FPS Exponential Smoothing vs. Synchronous Target-Convergence Assertions and Instant Fist-Close Shield Trigger: Confirmed and mitigated via O4 by keeping `player.target_position` at the latest clamped target while smoothing 30-to-60 FPS player movement and 21-landmark hand shadow rendering via exponential smoothing (`1.0 - exp(-speed * delta)`) that snaps on initial hand acquisition, converges within existing test tolerances, and triggers closed-fist shield activation immediately on packet receipt.
- **Q5** — I5: Overlay Transition Animations (`GameOverPanel`, `LevelCompletePanel`) and Screen Shake vs. Synchronous Visibility and Monochrome Assertions: Confirmed and mitigated via O5 by setting overlay `.visible = true` immediately on trigger while animating grayscale alpha/scale, resetting overlay visibility/transforms and screen-shake offsets immediately on `restart_level()`, keeping `main_menu.tscn` structure untouched, and passing `_assert_subtree_monochrome_and_primitive`.
- **Q6** — I6: Per-Frame `PackedVector2Array` / `Shape2D` Allocations and Visual Effect Node Churn Under 9-Hazard Peak Waves: Confirmed and mitigated via O6 by precomputing and reusing static unit `PackedVector2Array` polygons and reusable point buffers across `light_beam.gd`, `player.gd`, and `level.gd`, driving uniform size/rotation updates via transforms, and verifying peak waves hold `<= 16.67 ms` (`60 FPS`) with zero orphan nodes.
