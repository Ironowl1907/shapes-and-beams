---
task_name: hand-tracking-control
---

## 1. Change Summary
<!-- prose · required -->
Introduces a Godot autoload client (`HandTrackingClient`) registered in `juego/project.godot` that regulates the `tracker_server` Python subprocess across the game application's lifetime (spawning headless at game boot without duplicates and terminating cleanly on exit) and polls UDP `127.0.0.1:5005` for little-endian binary MediaPipe hand landmark packets (`<i63f` and `<i`). Connects incoming 21-landmark frames during active `Level` gameplay to drive horizontally mirrored palm-center movement (`#0, #5, #9, #13, #17`) and rising-edge closed-fist dash (`#8, #12, #16, #20`), while dynamically releasing and re-engaging `external_tracking_active` in `player.gd` so mouse/keyboard fallback and hand-tracking resumption switch automatically. Adds a monochrome HUD tracking status guide (`HAND: TRACKING`, `HAND: NO HAND`, `HAND: OFFLINE`) and a procedural grayscale articulated constellation hand shadow rendered behind gameplay entities in `level.tscn`, plus deterministic hardware-independent tests in `juego/tests/test_gameplay.gd`.

## 2. Impact Map
<!-- bullet list · required -->
- `juego/project.godot` — Relationship: origin — Registers the hand-tracking autoload singleton that manages Python subprocess lifecycle from game boot to exit and polls UDP `127.0.0.1:5005` — Impacts: I2, I3, I5
- `tracker_server/src/mediapipe_py/main.py` — Relationship: upstream — Captures webcam frames, writes `.tracker.status` heartbeats, and streams binary `<i63f` / `<i` UDP packets to `127.0.0.1:5005` — Impacts: I2, I5
- `juego/scenes/player.tscn` & `juego/scripts/player.gd` — Relationship: origin — Consumes normalized hand-tracking targets, triggers dash on closed-fist transitions, and switches `external_tracking_active` off and back on as hand landmarks stop and resume — Impacts: I1, I3, I5
- `juego/scenes/level.tscn` & `juego/scripts/level.gd` — Relationship: origin — Forwards live hand-tracking state to `Player`, renders the procedural grayscale hand shadow between `Background` and `BeamContainer`/`Player`, and updates the HUD tracking status pill — Impacts: I1, I3, I4, I5
- `juego/scenes/main_menu.tscn` & `juego/scripts/main_menu.gd` — Relationship: downstream — Boot scene (`run/main_scene`) where tracker warms up in headless mode and `QuitButton` triggers `get_tree().quit()` requiring clean tracker subprocess termination — Impacts: I2
- `juego/tests/test_gameplay.gd` — Relationship: downstream — Instantiates scenes detached from `SceneTree` (`!is_inside_tree()`), runs `@tool` scripts, and enforces `_assert_subtree_monochrome_and_primitive` across `level.tscn` — Impacts: I2, I3, I4

## 3. Impacts
<!-- entries · required · repeat per entry -->

### I1 — Permanent `external_tracking_active` Lockout Blocks Bidirectional Hand/Mouse-Keyboard Switching in `player.gd`
- **Lens**: Behavior and regressions
- **Severity**: High
- **Breaking**: Yes
- **Condition**: Unconditional
- **Evidence**: `juego/scripts/player.gd:42,68,95,104,139,151,242` sets `external_tracking_active = true` on the first `set_normalized_target_position()` call and never clears it when hand landmarks stop arriving (`0` landmarks or UDP timeout) or when `reset_player()` runs, causing `_unhandled_input` (`line 68`) and `simulate_physics` (`line 95`) to ignore mouse motion and `WASD`/Arrow input permanently.
- **Consequence**: Once a single hand landmark packet is received, lowering the hand out of camera view or losing tracker connection leaves the player unable to move with mouse or keyboard (violating AC5).
- **Disposition**: Mitigate via: O1 (Settled in: Q1)

### I2 — Orphaned or Duplicate Python `tracker_server` Processes and Editor/Test Webcam Contention
- **Lens**: Reliability and failure modes
- **Severity**: High
- **Breaking**: Yes
- **Condition**: Unconditional
- **Evidence**: `tracker_server/src/mediapipe_py/main.py:82-189` runs an infinite capture loop holding `/dev/video0` and sending UDP to `127.0.0.1:5005`; `juego/scripts/main_menu.gd:113` exits via `get_tree().quit()`, and game scripts use `@tool` (`Engine.is_editor_hint()`) and run inside `juego/tests/test_gameplay.gd`.
- **Consequence**: Spawning the Python server when `Engine.is_editor_hint()` is true, spawning a second instance when one is already alive, or failing to terminate the Python child process on `get_tree().quit()` / window close leaves orphan Python processes holding `/dev/video0` and causes subsequent game launches to fail with `error:camera` (violating AC1).
- **Disposition**: Mitigate via: O2 (Settled in: Q2)

### I3 — Detached SceneTree Instantiation (`!is_inside_tree()`) in `test_gameplay.gd` and Hardware-Independent Testability
- **Lens**: Downstream consumers
- **Severity**: High
- **Breaking**: Yes
- **Condition**: Unconditional
- **Evidence**: `juego/tests/test_gameplay.gd:18,59,139,364,483` instantiates `LEVEL_SCENE` and `PLAYER_SCENE` detached from the `SceneTree` (`is_inside_tree() == false`, `get_tree() == null`) and steps `simulate_physics(delta)` directly in `McpTestSuite`.
- **Consequence**: If `level.gd` or `player.gd` unconditionally dereferences `/root/` autoloads or requires a live webcam/Python subprocess to update tracking state, existing `test_gameplay.gd` tests break and AC2–AC7 cannot be deterministically verified in automated tests.
- **Disposition**: Mitigate via: O3 (Settled in: Q3)

### I4 — Grayscale Primitive Subtree Assertion (`_assert_subtree_monochrome_and_primitive`) and Arena Draw-Order Occlusion in `level.tscn`
- **Lens**: Contracts and interfaces
- **Severity**: Medium
- **Breaking**: Yes
- **Condition**: Unconditional
- **Evidence**: `juego/tests/test_gameplay.gd:562-582` asserts that every `Polygon2D` and `ColorRect` in `level.tscn` has `absf(r - g) < 0.01 and absf(g - b) < 0.01` and forbids `Sprite2D`/`TextureRect`; `juego/scenes/level.tscn:153-163` orders `Background` (opaque black `ColorRect`), `BeamContainer`, and `Player`.
- **Consequence**: Any non-grayscale color or texture node in the hand shadow or HUD status guide breaks `test_ac11_monochrome_primitives_only`, and placing the hand shadow behind `Background` makes it invisible while placing it above `BeamContainer`/`Player` obscures hazards and the player (violating AC6 and AC7).
- **Disposition**: Mitigate via: O4 (Settled in: Q4)

### I5 — UDP Buffer Lag and Repeated Dash Re-Triggering on Held Closed Fist
- **Lens**: Performance and capacity
- **Severity**: Medium
- **Breaking**: No
- **Condition**: If the UDP client reads only one packet per frame instead of draining queued packets to the latest frame, or if closed-fist dash triggers continuously while a fist is held rather than on the open-to-closed transition.
- **Evidence**: `tracker_server/src/mediapipe_py/main.py:162-174` sends UDP datagrams continuously per camera frame, and `juego/scripts/player.gd:155-177` allows `trigger_dash()` whenever `dash_cooldown_timer <= 0.0` (`0.45s`).
- **Consequence**: Reading only one queued UDP packet per tick causes cumulative input lag when packet arrival outpaces a frame, and level-triggered fist detection causes the player to dash repeatedly every `0.45s` while holding a closed fist (degrading AC2, AC3, and AC4).
- **Disposition**: Mitigate via: O5 (Settled in: Q5)

## 4. Obligations
<!-- entries · optional · repeat per entry -->

### O1 — Bidirectional Automatic Switching Between Hand Tracking and Mouse/Keyboard Fallback
- **Requirements**: When the tracker reports `0` landmarks, times out, or goes offline (or when `reset_player()` runs), `external_tracking_active` immediately clears to `false` so mouse motion and `WASD`/Arrow keyboard inputs control the player; when valid 21-landmark hand packets are received again, `external_tracking_active` automatically re-engages to `true` and resumes hand-tracking control without manual intervention.
- **Applies**: Always
- **Verification**: Stepping `Level` / `Player` with valid 21-landmark input sets `external_tracking_active == true` and moves the player to the mirrored palm target; stepping with a `0`-landmark packet or packet timeout clears `external_tracking_active == false` and restores keyboard/mouse movement; sending a subsequent 21-landmark packet sets `external_tracking_active == true` again and resumes hand-tracking movement.
- **Source**: I1

### O2 — Single-Instance Headless Process Regulation and Clean Exit Termination
- **Requirements**: The game launches the headless Python tracker process once at runtime application boot (skipping process creation when `Engine.is_editor_hint()` is true or when a live tracker instance is already active) and cleanly terminates the spawned process when the game closes via window close (`NOTIFICATION_WM_CLOSE_REQUEST`), Main Menu `Quit` (`get_tree().quit()`), or autoload `_exit_tree()`.
- **Applies**: Always
- **Verification**: Starting the game runtime spawns at most one headless tracker process, editor/test mode never leaves a background tracker running, and invoking shutdown cleanup terminates the spawned process so `OS.is_process_running()` returns `false`.
- **Source**: I2

### O3 — Detached SceneTree Safety and Hardware-Independent Deterministic Testability
- **Requirements**: `level.gd`, `player.gd`, and the hand-tracking client operate without errors when instantiated outside the `SceneTree` (`!is_inside_tree()`) and accept synthetic binary UDP packets (`<i63f` and `<i`) or landmark frames in `McpTestSuite` without requiring physical camera hardware or a live Python subprocess.
- **Applies**: Always
- **Verification**: Running `juego/tests/test_gameplay.gd` in `McpTestSuite` deterministically verifies binary UDP packet decoding (`<i63f` and `<i`), mirrored palm target movement, closed-fist dash, fallback/resumption transitions, HUD status states, and hand shadow rendering on detached scene instances with zero errors.
- **Source**: I3

### O4 — Monochrome Grayscale Primitive Compliance and Background-to-Foreground Layering in `level.tscn`
- **Requirements**: All nodes and drawn primitives for the HUD tracking status pill and the articulated hand shadow in `level.tscn` use strictly grayscale colors (`absf(r - g) < 0.01 and absf(g - b) < 0.01`) with zero `Sprite2D` or `TextureRect` nodes, and the hand shadow node is ordered after `Background` and before `BeamContainer` and `Player` in `level.tscn`.
- **Applies**: Always
- **Verification**: `test_ac11_monochrome_primitives_only` passes on `level.tscn`, and tree index inspection confirms `Background.get_index() < HandShadow.get_index() < BeamContainer.get_index() < Player.get_index()`.
- **Source**: I4

### O5 — Latest-Packet UDP Buffer Draining and Rising-Edge Closed-Fist Dash Trigger
- **Requirements**: When multiple UDP packets are queued on `127.0.0.1:5005`, each update tick drains the UDP socket buffer and applies the newest valid packet, and `player.trigger_dash()` fires from hand tracking only on a rising-edge transition from open hand to closed fist rather than continuously while a fist remains held.
- **Applies**: When multiple UDP packets arrive between ticks or when a closed fist is held across multiple frames
- **Verification**: Feeding multiple queued UDP packets in a single tick applies the final packet's landmarks, and feeding consecutive closed-fist frames across cooldown expiry triggers `player.trigger_dash()` once on the initial open-to-closed transition and does not re-trigger until the hand opens and closes again.
- **Source**: I5

## 5. Decision Log
<!-- bullet list · required -->
- **Q1** — I1: Permanent `external_tracking_active` Lockout Blocks Mouse and Keyboard Fallback in `player.gd`: Mitigate via O1 by clearing `external_tracking_active` on `0` landmarks, packet timeout, offline state, or `reset_player()`, and automatically re-enabling `external_tracking_active` whenever valid 21-landmark packets arrive again.
- **Q2** — I2: Orphaned or Duplicate Python `tracker_server` Processes and Editor/Test Webcam Contention: Mitigate via O2 by launching the headless Python tracker once at runtime application boot only (never in editor hint or when already active) and terminating the spawned process cleanly on window close, `get_tree().quit()`, and `_exit_tree()`.
- **Q3** — I3: Detached SceneTree Instantiation (`!is_inside_tree()`) in `test_gameplay.gd` and Hardware-Independent Testability: Mitigate via O3 by keeping `level.gd`, `player.gd`, and the hand-tracking client safe when detached from `SceneTree` and supporting synthetic UDP packet/landmark injection in `McpTestSuite`.
- **Q4** — I4: Grayscale Primitive Subtree Assertion and Arena Draw-Order Occlusion in `level.tscn`: Mitigate via O4 by rendering the HUD status pill and articulated hand shadow exclusively with grayscale procedural 2D primitives and ordering the hand shadow between `Background` and `BeamContainer`/`Player`.
- **Q5** — I5: UDP Buffer Lag and Repeated Dash Re-Triggering on Held Closed Fist: Mitigate via O5 by draining queued UDP packets each tick to apply the freshest packet and triggering `trigger_dash()` only on an open-to-closed fist rising edge.
