---
task_name: difficulty-and-obstacles
---

## 1. Change Summary
<!-- prose · required -->
Introduces a single difficulty-mode toggle button on `MainMenu` (`Easy`, `Normal`, `Hard`) that persists the selected mode into `Level` and scales only wave spawn frequency (`spawn_timer`). Expands `Level` and `LightBeam` to spawn and simulate four monochrome 2D hazard types—edge-to-edge light beams, three-pattern filling circles (center-out, outside-in, angular sweep), un-telegraphed edge projectiles, and stationary exploding objects that detonate into radial projectile bursts—while preserving existing `MainMenu`, `Level`, `LightBeam`, and `Player` contracts with minimal scenes and scripts.

## 2. Impact Map
<!-- bullet list · required -->
- `juego/scenes/main_menu.tscn` & `juego/scripts/main_menu.gd` — Relationship: origin — Adds single mode toggle button cycling Easy/Normal/Hard while preserving `PlayButton` and `_on_play_pressed` — Impacts: I1, I3
- `juego/scenes/level.tscn` & `juego/scripts/level.gd` — Relationship: origin — Scales `spawn_timer` frequency by active difficulty mode, preserves difficulty across `restart_level()`, and spawns all four hazard types into `BeamContainer` — Impacts: I2, I3, I4, I5
- `juego/scenes/light_beam.tscn` & `juego/scripts/light_beam.gd` — Relationship: origin — Consolidates light-beam, filling-circle, projectile, and exploding-object behaviors while keeping default light-beam `configure()` and child node contracts intact — Impacts: I2, I4, I5
- `juego/tests/test_gameplay.gd` — Relationship: downstream — Existing `McpTestSuite` asserting `PlayButton`, `BeamContainer`, and `LightBeam` phase contracts — Impacts: I1, I2, I3
- `juego/scenes/player.tscn` & `juego/scripts/player.gd` — Relationship: downstream — Receives `take_damage(1)` from all active hazard types while relying on fair telegraph/edge-spawn rules for position-only playability — Impacts: I4

## 3. Impacts
<!-- entries · required · repeat per entry -->

### I1 — Main Menu PlayButton Contract vs. Difficulty Selection UI
- **Lens**: Contracts and interfaces
- **Severity**: High
- **Breaking**: Yes
- **Condition**: If adding difficulty selection replaces, renames, or removes `CenterContainer/MenuBox/PlayButton` or `_on_play_pressed` in `juego/scenes/main_menu.tscn` and `juego/scripts/main_menu.gd`.
- **Evidence**: `juego/tests/test_gameplay.gd:21-32` (`test_ac1_and_ac2_main_menu_structure_and_actions`) asserts that `CenterContainer/MenuBox/PlayButton` exists, has `.text == "Play"`, and connects `.pressed` to `menu._on_play_pressed`.
- **Consequence**: Replacing `PlayButton` with three separate difficulty buttons or changing its node path/handler breaks the existing Main Menu acceptance test in `juego/tests/test_gameplay.gd`.
- **Disposition**: Mitigate via: O1 (Settled in: Q1)

### I2 — Existing LightBeam & BeamContainer Contracts Under Minimal-Entity Consolidation
- **Lens**: Contracts and interfaces
- **Severity**: High
- **Breaking**: Yes
- **Condition**: When consolidating new obstacle types (filling circles, edge projectiles, exploding objects) into `juego/scenes/light_beam.tscn`, `juego/scripts/light_beam.gd`, and `BeamContainer` to minimize entity/script count (AC9).
- **Evidence**: `juego/tests/test_gameplay.gd:86-116` instantiates `res://scenes/light_beam.tscn`, calls `configure(Vector2(576.0, 324.0), 0.4, 44.0, 1.0, 0.35)`, and checks `current_phase`, `is_hazard_active`, `CollisionShape2D.disabled`, and `BeamVisual.color`; `juego/tests/test_gameplay.gd:171-187` checks that level obstacles spawn as children of `BeamContainer` and are cleared to 0 on level end via `_clear_beams()`.
- **Consequence**: Breaking default `light_beam.gd` light-beam behavior, altering `configure()` default parameters or child nodes (`BeamVisual`, `CenterLine`, `CollisionShape2D`), or parenting new obstacles (including explosion-spawned projectiles) outside `BeamContainer` breaks existing tests and leaves active hazards on screen after Game Over, Level Complete, or Retry.
- **Disposition**: Mitigate via: O2 (Settled in: Q2)

### I3 — Cross-Scene Difficulty State Transfer & Standalone Level Defaulting
- **Lens**: Data and state
- **Severity**: High
- **Breaking**: No
- **Condition**: Unconditional
- **Evidence**: `juego/scripts/main_menu.gd:58-60` calls `get_tree().change_scene_to_file("res://scenes/level.tscn")` which frees `MainMenu` before `Level` initializes, and `juego/tests/test_gameplay.gd:119,164` instantiates `level.tscn` directly without `MainMenu` and invokes `_on_retry_pressed()` / `_on_replay_pressed()`.
- **Consequence**: Storing difficulty only on the `MainMenu` instance loses the selected mode when `level.tscn` loads, and lacking a default difficulty on `Level` or resetting it during `restart_level()` breaks AC1, AC2, AC4, and standalone `level.tscn` execution.
- **Disposition**: Mitigate via: O3 (Settled in: Q3)

### I4 — Unavoidable Damage Risk from Un-telegraphed Projectiles & Telegraphed In-Arena Hazards
- **Lens**: Behavior and regressions
- **Severity**: Medium
- **Breaking**: No
- **Condition**: Unconditional
- **Evidence**: `juego/scripts/level.gd:205-243` spawns wave hazards at or near `player_pos` relying on `TELEGRAPH_TIME = 1.0`, whereas standalone projectiles have no preview and immediate active collision (AC7) and must remain dodgeable using position movement alone (`01-brief-and-context.md` Constraints).
- **Consequence**: Spawning un-telegraphed projectiles inside the arena near the player or activating filling circles / exploding objects without their ~1.0s non-damaging telegraph causes unavoidable instant hits and violates position-only playability.
- **Disposition**: Mitigate via: O4 (Settled in: Q4)

### I5 — Off-Screen Projectile Accumulation in BeamContainer
- **Lens**: Performance and capacity
- **Severity**: Medium
- **Breaking**: No
- **Condition**: Unconditional
- **Evidence**: `juego/scripts/light_beam.gd:69-94` frees hazards only after a fixed `fade_duration`, whereas edge projectiles and exploding-object burst projectiles travel across the arena (AC7, AC8) at higher spawn frequencies in Hard mode (AC2).
- **Consequence**: Moving projectiles that are not freed upon exiting viewport bounds accumulate in `BeamContainer` throughout the 45-second level, increasing active `Area2D` overlap checks and risking frame drops below 60 FPS.
- **Disposition**: Mitigate via: O5 (Settled in: Q5)

## 4. Obligations
<!-- entries · optional · repeat per entry -->

### O1 — Single Difficulty Toggle Button Preserving MainMenu Play Contract
- **Requirements**: `juego/scenes/main_menu.tscn` exposes a single difficulty mode toggle button that cycles through Easy, Normal, and Hard while preserving `CenterContainer/MenuBox/PlayButton` (with `.text == "Play"` connected to `_on_play_pressed`) to launch the level with the active difficulty mode.
- **Applies**: Always
- **Verification**: Instantiating `main_menu.tscn` confirms `CenterContainer/MenuBox/PlayButton` exists with text `"Play"` connected to `_on_play_pressed`, and pressing the difficulty toggle button cycles the selected mode across Easy, Normal, and Hard.
- **Source**: I1

### O2 — Backward-Compatible LightBeam Contract and Unified BeamContainer Parenting
- **Requirements**: `juego/scenes/light_beam.tscn` and `juego/scripts/light_beam.gd` preserve default rectangular light-beam behavior, child nodes (`BeamVisual`, `CenterLine`, `CollisionShape2D`), and `configure(spawn_pos, angle_radians, width, warning_time, active_time)` behavior, and all active hazards (light beams, filling circles, edge projectiles, exploding objects, and burst projectiles) are parented under `BeamContainer` and removed when the level stops or restarts.
- **Applies**: When consolidating new obstacle types into existing hazard scene/script and level container
- **Verification**: Existing `test_ac6_and_ac7_light_beam_phases_and_collision` and `test_ac10_level_survival_45_seconds_and_replay` pass unchanged, and `BeamContainer.get_child_count()` drops to `0` on Game Over, Level Complete, and `restart_level()`.
- **Source**: I2

### O3 — Cross-Scene Difficulty Persistence and Standalone Level Default
- **Requirements**: The difficulty mode selected on `MainMenu` persists into `Level` across scene transition, remains unchanged across `restart_level()` ("Retry" and "Replay"), and defaults to Normal when `level.tscn` is instantiated directly without `MainMenu`.
- **Applies**: Always
- **Verification**: Selecting Easy, Normal, or Hard on `MainMenu` sets the corresponding attack spawn frequency in `Level`; calling `_on_retry_pressed()` or `_on_replay_pressed()` retains that difficulty mode; instantiating `level.tscn` directly defaults to Normal mode.
- **Source**: I3

### O4 — Edge-Only Un-telegraphed Projectile Spawns and Non-Damaging In-Arena Telegraphs
- **Requirements**: Standalone un-telegraphed projectiles spawn exclusively along viewport edges (never inside the arena on the player), and all in-arena hazards (light beams, filling circles, exploding objects) keep collision disabled throughout their ~1.0s telegraph/fill phase before activating collision or detonating into projectiles.
- **Applies**: Always
- **Verification**: Stepping `simulate_physics` verifies standalone projectiles spawn at viewport boundaries with active collision, while filling circles and exploding objects have `is_hazard_active == false` and disabled collision during their ~1.0s telegraph/fill phase.
- **Source**: I4

### O5 — Automatic Despawn of Off-Screen Projectiles
- **Requirements**: Every projectile hazard automatically despawns (`queue_free`) once its position exits the viewport bounds (beyond a small margin), in addition to being cleared when the level stops or restarts.
- **Applies**: Always
- **Verification**: Stepping `simulate_physics` on a projectile until its position exceeds the viewport bounds plus margin removes or queues the projectile for deletion.
- **Source**: I5

## 5. Decision Log
<!-- bullet list · optional -->
- **Q1** — I1: Main Menu PlayButton Contract vs. Difficulty Selection UI: Mitigate via O1 using a single mode toggle button on `MainMenu` (do not use 3 separate difficulty buttons) while preserving `PlayButton` and `_on_play_pressed`.
- **Q2** — I2: Existing LightBeam & BeamContainer Contracts Under Minimal-Entity Consolidation: Mitigate via O2 by keeping `light_beam.tscn` default light-beam behavior/nodes backward-compatible and parenting all obstacle types (including burst projectiles) under `BeamContainer`.
- **Q3** — I3: Cross-Scene Difficulty State Transfer & Standalone Level Defaulting: Mitigate via O3 by persisting selected difficulty from `MainMenu` into `Level`, preserving it across `restart_level()` (Retry/Replay), and defaulting standalone `level.tscn` to Normal.
- **Q4** — I4: Unavoidable Damage Risk from Un-telegraphed Projectiles & In-Arena Hazards: Mitigate via O4 by spawning standalone un-telegraphed projectiles only at viewport edges and keeping collision disabled during the ~1.0s telegraph/fill phase of in-arena hazards.
- **Q5** — I5: Off-Screen Projectile Accumulation in BeamContainer: Mitigate via O5 by automatically despawning projectiles once they exit viewport bounds.
