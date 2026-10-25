---
task_name: jsab-core-gameplay
description: Black-and-white Just Shapes & Beats style 2D dodge game prototype with main menu and light-beam level, ready for future hand-tracking input.
---

## 1. Task Brief

### Problem Statement
<!-- prose · required -->
Science fair project needs interactive game that transcends standard screen interaction via future hand tracking. No playable base game exists yet to test dodging mechanics or connect external 2D hand coordinates.

### Expected Outcome
<!-- prose · required -->
Playable black-and-white 2D Godot game with Main Menu and one 45-second survival level. Player moves via keyboard or target-position following (mouse now, MediaPipe coordinates later), dashes with brief invincibility, and dodges telegraphed white light beams using minimal primitive 2D shapes.

### Acceptance Criteria
<!-- ordered list · required -->
1. Launching game opens Main Menu displaying game title, "Play" button, and "Quit" button.
2. Pressing "Play" starts level; pressing "Quit" exits application.
3. Player entity renders as primitive 2D shape in black-and-white palette, constrained within screen bounds.
4. Player moves via keyboard (WASD/Arrows) and target-position following (mouse cursor position), allowing future drop-in replacement by 2D hand-tracking coordinates.
5. Player has dash action granting brief movement burst and temporary invincibility, while game remains completable using position movement alone.
6. Level spawns only one obstacle type: edge-to-edge rectangular light beams at varied positions and angles.
7. Each light beam first appears as dim gray warning telegraph (~1s) with no collision, activates as solid white beam with active collision, then disappears.
8. Player starts level with 3 HP; touching active beam reduces HP by 1 and grants brief post-hit invincibility frames.
9. Reaching 0 HP stops level and displays Game Over screen with "Retry" and "Main Menu" buttons.
10. Surviving 45-second level timer stops beam spawns and displays Level Complete screen with "Replay" and "Main Menu" buttons.
11. All visuals use only black, white, and gray primitive 2D shapes with zero external art or audio asset dependencies.

### Out of Scope
<!-- bullet list · optional -->
- Python script and MediaPipe hand-tracking integration.
- Audio/music playback and beat-synchronized obstacle spawning.
- Color palettes beyond black, white, and grayscale.
- Multiple obstacle types beyond rectangular light beams.
- Multiple levels, bosses, scoring systems, or persistent save data.

## 2. Context

### Codebase
<!-- bullet list · required -->
- `juego/project.godot` — Godot 4.7 project configuration file where main scene, display settings (`canvas_items` stretch mode), and input actions are registered.
- `juego/addons/godot_ai/` — Enabled Godot AI MCP plugin used to create, inspect, and test scenes, nodes, and scripts during development.

### Conventions & Prior Art
<!-- bullet list · optional -->
- Official Godot 4 GDScript Style Guide — Static typing, `snake_case` file and function names, `PascalCase` node and class names.
- Scene-per-entity modularity — Separate scenes and scripts for `main_menu`, `level`, `player`, and `light_beam`.
- Godot AI MCP workflow — Use `godot-ai` MCP server tools for scene, node, script, and project operations.

### Related Work
<!-- bullet list · optional -->
- None

### External References
<!-- bullet list · optional -->
- Godot 4.7 2D Documentation (`CharacterBody2D`, `Area2D`, `Control`, `Polygon2D`, `ColorRect`) — Core engine APIs for 2D movement, overlap detection, UI, and primitive shape rendering.
- Just Shapes & Beats gameplay mechanics — Prior art for telegraphed rectangular beam hazards, brief dash invincibility, and multi-hit survival levels.

### Constraints
<!-- bullet list · optional -->
- Development must use `godot-ai` MCP tools against `juego/`.
- Visuals restricted strictly to black, white, and grayscale primitive 2D shapes with zero external art or audio assets.
- Target 60 FPS on standard desktop/laptop hardware in Godot 4.7.
- Player movement input must support direct 2D target-position coordinates so future Python/MediaPipe hand tracking can drive player position without refactoring level or obstacle logic.

## 3. Decision Log
<!-- bullet list · optional -->
- **Q1** — Task Name: Use `jsab-core-gameplay`.
- **Q2** — Problem & Purpose: Science fair prototype designed to transcend screen interaction via future hand tracking; build playable base dodge game first.
- **Q3** — Current Input & Future Hand-Tracking Readiness: Support keyboard (WASD/Arrows) and mouse/target-position following now; Python/MediaPipe integration out of scope for this task.
- **Q4** — Player Abilities & Health: 3 HP with post-hit invincibility frames and invincible dash, keeping level playable with position-only movement for future hand tracking.
- **Q5** — Light Beam Obstacle Behavior: Edge-to-edge rectangular beams that telegraph in dim gray (~1s), flash solid white with active damage collision, then fade out.
- **Q6** — Level Progression, Audio & Win/Loss Conditions: 45-second timer-driven survival level without audio sync; 0 HP triggers Game Over (Retry/Main Menu), surviving 45s triggers Level Complete (Replay/Main Menu).
- **Q7** — Main Menu Scope: Title, Play button, and Quit button.
- **Q8** — Dependencies & Blockers: Zero external asset dependencies; use minimal primitive 2D shapes and keep entity variety/quantity as simple as possible.
- **Q9** — Codebase Relevance: Use `juego/project.godot` as project root and `juego/addons/godot_ai/` MCP tools for development.
- **Q10** — Conventions & Prior Art: Follow official Godot 4 GDScript style guide with static typing and modular scene-per-entity structure.
- **Q11** — Related Work: None; hand-tracking script will be a separate future task.
- **Q12** — External References: Godot 4 2D documentation and Just Shapes & Beats telegraph/dodge mechanics.
- **Q13** — Constraints: 60 FPS in Godot 4.7, pure 2D primitives, MCP-driven development, and decoupled 2D target-position input for future MediaPipe hand tracking.
