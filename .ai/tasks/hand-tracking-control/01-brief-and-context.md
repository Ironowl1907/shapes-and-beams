---
task_name: hand-tracking-control
description: Automatic Python MediaPipe UDP hand-tracker lifecycle management, palm-center player movement and closed-fist dash control with keyboard/mouse fallback, HUD tracking status guide, and procedural monochrome articulated hand shadow in the playing scene.
---

## 1. Task Brief

### Problem Statement
<!-- prose · required -->
`player.gd` and `level.gd` expose hand-tracking target hooks and `tracker_server/` exists in the repository, but the game does not launch or manage the Python tracker process, consume its UDP landmark packets, drive player movement and dash from hand landmarks, or render on-screen hand-tracking status and hand shadow feedback in the playing scene.

### Expected Outcome
<!-- prose · required -->
Starting the game application immediately launches the Python hand-tracking server in headless mode (warming up at game start rather than level entry) and terminates it automatically when the game closes. During level gameplay, the player character follows the horizontally mirrored palm center, closing the hand into a fist triggers a dash, a HUD status pill displays live tracking state (`HAND: TRACKING`, `HAND: NO HAND`, `HAND: OFFLINE`), a procedural monochrome articulated constellation shadow renders the 21 hand landmarks in the arena behind gameplay entities, and controls fall back seamlessly to mouse and keyboard whenever no hand is tracked.

### Acceptance Criteria
<!-- ordered list · required -->
1. Game startup automatically launches the `tracker_server` Python process in headless mode (`--headless` / `TRACKER_HEADLESS=1`) at application boot (before entering `level.tscn`) without spawning duplicate instances if one is already running, and terminates the process when the game closes (`NOTIFICATION_WM_CLOSE_REQUEST`, `_exit_tree()`, or Main Menu `Quit`).
2. A Godot client listens on UDP `127.0.0.1:5005` and decodes the existing little-endian binary packet format from `tracker_server/src/mediapipe_py/main.py` (`<i63f` for 21 `(x, y, z)` landmarks when a hand is detected, `<i` with `0` when no hand is detected).
3. When 21 hand landmarks are received during active level gameplay, the horizontally mirrored palm center (average of landmarks `#0, #5, #9, #13, #17` with `1.0 - x`) updates the player's target position via `set_normalized_target_position()`.
4. Transitioning from an open hand to a closed fist (fingertips `#8, #12, #16, #20` curled toward the palm) triggers `player.trigger_dash()`, while preserving keyboard/mouse dash inputs.
5. When no hand is detected (`0` landmarks) or UDP packets time out/tracker is offline, `external_tracking_active` releases so keyboard (`WASD`/Arrows) and mouse motion control the player without manual switching.
6. `level.tscn` displays a monochrome HUD status guide pill/indicator with a geometric icon and state label reflecting live tracker state: `HAND: TRACKING` (hand detected), `HAND: NO HAND` (tracker ready, `0` landmarks), or `HAND: OFFLINE` (tracker starting, unreachable, or camera error).
7. `level.tscn` renders a procedural monochrome articulated hand shadow behind the player and hazards using only grayscale 2D primitives: a translucent dark-gray palm polygon (`#0, #1, #5, #9, #13, #17`), grayscale finger bone lines connecting the 21 landmarks, and brighter geometric joint/fingertip nodes (`#4, #8, #12, #16, #20`) that pulse/contract on fist dash and smoothly fade out when no hand is tracked.

### Out of Scope
<!-- bullet list · optional -->
- Rewriting `tracker_server` from UDP (`127.0.0.1:5005`) to TCP.
- Starting/stopping the Python tracker per level transition instead of once for the application lifetime.
- Hand-tracking cursor navigation in `main_menu.tscn` or level overlay menus.
- Camera selection, sensitivity, or calibration settings UI.
- Multi-hand tracking (single hand only).
- External image, sprite, or texture assets (`Sprite2D`, `TextureRect`).

## 2. Context

### Codebase
<!-- bullet list · required -->
- `tracker_server/src/mediapipe_py/main.py` & `tracker_server/src/mediapipe_py/landmarker.py` — Python MediaPipe hand-tracking server capturing webcam frames, writing `.tracker.status` heartbeats (`ready` / `error:camera`), and streaming 21 `(x, y, z)` normalized landmarks over UDP `127.0.0.1:5005` (`struct.pack("<i63f", ...)` or `<i` with `0`).
- `tracker_server/pyproject.toml` & `tracker_server/README.md` — `uv`-managed Python 3.12 package definition (`mediapipe-py = "mediapipe_py.main:main"`) and documentation of the UDP and heartbeat contract.
- `juego/project.godot` — Godot 4.7 project configuration where the hand-tracking autoload singleton is registered to launch and terminate the Python tracker process across the game's lifetime and poll UDP packets.
- `juego/scenes/player.tscn` & `juego/scripts/player.gd` — Player entity exposing `set_target_position()`, `set_normalized_target_position()`, `trigger_dash()`, and `external_tracking_active` for hand-tracking movement, dash, and fallback to mouse/keyboard.
- `juego/scenes/level.tscn` & `juego/scripts/level.gd` — Playing scene and lifecycle controller (`simulate_physics`, `set_hand_tracking_target`, `set_normalized_hand_tracking_target`, `_sync_background_size`, `_apply_monochrome_ui_theme`) where the procedural hand shadow renders behind gameplay entities and the HUD tracking status indicator is displayed.
- `juego/scenes/main_menu.tscn` & `juego/scripts/main_menu.gd` — Boot scene (`run/main_scene`) and `_on_quit_pressed` application exit path.
- `juego/tests/test_gameplay.gd` — `McpTestSuite` test suite enforcing monochrome primitive visuals (`_assert_subtree_monochrome_and_primitive`) and deterministic gameplay verification.

### Conventions & Prior Art
<!-- bullet list · optional -->
- Official Godot 4 GDScript Style Guide — Static typing, `snake_case` file and function names, `PascalCase` node and enum names.
- Minimal entity/script/object footprint — Consolidate process lifecycle, UDP client, and procedural hand shadow/HUD guide into minimal scripts and nodes rather than proliferating separate scenes or files.
- Deterministic testability without hardware — Keep UDP packet decoding, palm/fist gesture detection, fallback state transitions, and hand shadow/HUD updates deterministically testable in `McpTestSuite` without requiring a physical webcam during automated test runs.
- Procedural monochrome primitives over external assets — Render the hand shadow and HUD status indicator using grayscale procedural primitives (`Polygon2D`, `Line2D`, `ColorRect`, or `Node2D._draw()`) that satisfy `_assert_subtree_monochrome_and_primitive`.

### Related Work
<!-- bullet list · optional -->
- `.ai/tasks/jsab-core-gameplay/01-brief-and-context.md` — Established the player target-position hooks (`set_target_position`, `set_normalized_target_position`, `set_hand_tracking_target`) and the strict monochrome primitive visual rule (`AC11`).
- `.ai/tasks/difficulty-and-obstacles/01-brief-and-context.md` & `.ai/tasks/gameplay-and-menu-audio/01-brief-and-context.md` — Established the current `level.tscn` HUD layout, scene lifecycle, and `test_gameplay.gd` regression suite.
- Git commits `283e7aa` & `031f34f` — Added `tracker_server/` with MediaPipe 21-landmark detection and UDP `127.0.0.1:5005` binary streaming.

### External References
<!-- bullet list · optional -->
- Godot 4.7 Networking & OS Process APIs (`PacketPeerUDP`, `StreamPeerBuffer`, `OS.create_process`, `OS.is_process_running`, `OS.kill`, `Node.NOTIFICATION_WM_CLOSE_REQUEST`) — Engine APIs for non-blocking UDP packet reception, little-endian binary unpacking (`<i63f`), and child process lifecycle regulation.
- MediaPipe Hands 21-Landmark Topology (`WRIST = 0`, thumb `1..4`, index `5..8`, middle `9..12`, ring `13..16`, pinky `17..20`) — Standard landmark indices used for palm center calculation (`#0, #5, #9, #13, #17`), articulated finger bone connections, and closed-fist curl detection (`#8, #12, #16, #20`).

### Constraints
<!-- bullet list · optional -->
- Strictly minimal code, nodes, objects, scenes, and scripts.
- Zero external art/texture asset files; all hand shadow and HUD status visuals must use grayscale procedural 2D primitives that pass `_assert_subtree_monochrome_and_primitive`.
- Non-blocking 60 FPS execution: UDP polling and background process management must never stall the main thread, and the game must remain playable via mouse/keyboard even if a camera or Python environment is unavailable.
- Clean process regulation: launch the headless Python tracker once at game boot, avoid duplicate instances, and terminate the child process cleanly when the game exits so no orphan Python process remains.
- Execute scene, script, and test operations via `godot-ai` MCP tools against `juego/`.

## 3. Decision Log
<!-- bullet list · optional -->
- **Q1** — Task Name: Use `hand-tracking-control`.
- **Q2** — Problem Statement & Expected Outcome: Manage the Python tracker process automatically, drive player movement and dash via hand landmarks with mouse/keyboard fallback, and render both a HUD tracking status guide and a procedural monochrome hand shadow in `level.tscn`.
- **Q3** — Transport Protocol: Keep the existing UDP `127.0.0.1:5005` binary protocol (`<i63f` / `<i`) implemented in `tracker_server/src/mediapipe_py/main.py`.
- **Q4** — Player Control Mapping & Gestures: Map horizontally mirrored palm center (`#0, #5, #9, #13, #17`) to player 2D target position, trigger `trigger_dash()` on closed-fist gesture transition (alongside keyboard/mouse dash), and fall back automatically to mouse/keyboard when no hand is tracked.
- **Q5** — Visual Guide & Hand Shadow Design: Use Option A — articulated monochrome geometric constellation shadow (translucent palm polygon, bone lines, joint/fingertip nodes that react on dash and fade out when untracked) behind gameplay entities, plus a HUD status pill (`HAND: TRACKING` / `HAND: NO HAND` / `HAND: OFFLINE`).
- **Q6** — Tracker Process Lifecycle & Scope Boundaries: Launch the headless Python tracker automatically when the game application boots (not on level entry, avoiding startup delay) and terminate it when the game closes; keep menus, camera settings UI, multi-hand, and external textures out of scope.
- **Q7** — Codebase Relevance: Include `tracker_server/src/mediapipe_py/main.py`, `landmarker.py`, `pyproject.toml`, `README.md`, `juego/project.godot`, `player.tscn`/`player.gd`, `level.tscn`/`level.gd`, `main_menu.tscn`/`main_menu.gd`, and `test_gameplay.gd`.
- **Q8** — Conventions & Prior Art: Follow the Godot 4 GDScript style guide, minimal entity/script/object footprint, deterministic hardware-independent testability in `McpTestSuite`, and procedural monochrome 2D primitives.
- **Q9** — Related Work: Reference prior dossiers (`jsab-core-gameplay`, `difficulty-and-obstacles`, `gameplay-and-menu-audio`) and commits `283e7aa` and `031f34f`.
- **Q10** — External References: Reference Godot 4.7 Networking & OS Process APIs (`PacketPeerUDP`, `StreamPeerBuffer`, `OS.create_process`, `OS.is_process_running`, `OS.kill`, `NOTIFICATION_WM_CLOSE_REQUEST`) and MediaPipe Hands 21-Landmark Topology.
- **Q11** — Constraints: Enforce minimal code/nodes/scripts, zero external texture assets, non-blocking 60 FPS execution with graceful fallback, clean game-lifetime child process management without orphans or duplicates, and `godot-ai` MCP workflow.
