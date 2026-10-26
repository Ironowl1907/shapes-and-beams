---
task_name: menu-persistence-credits
description: Game/Sound controllers (autoloads), CPU particle effects, 2D lighting, persistent SaveData Resource (player name + best run at highest difficulty), responsive animated main menu, credits screen.
---

> Written by hand following the `.ai/tasks/` convention. The `prep` and `analysis` skills are
> symlinks to `/home/ironowl/dev/scf-skills/...` which does not exist on this machine, so they were NOT executed.

## 1. Task Brief

### Problem Statement
The game has no central game controller, no central sound controller, no persistent player data, no credits screen and a static menu. Course requirements (originally written for Unity) ask for: game controller, sound controller, particle effects, lighting, persistent data via ScriptableObject, responsive/aesthetic UI, an animated Play button and a credits screen.

### Expected Outcome
Godot equivalents of each requirement, keeping the strict black/white look (+ light and glow only).

### Acceptance Criteria
1. `GameManager` autoload: game state, scene navigation (menu/level/credits), difficulty handoff, owns the `SaveData` resource.
2. `SoundManager` autoload: `Music` and `SFX` buses created at runtime, pooled SFX players, music player, persisted volumes.
3. Particle effects: `CPUParticles2D` bursts on damage / shield block / shield break / death / level complete, player trail, ambient menu particles.
4. Lighting: `CanvasModulate` dim ambient + `PointLight2D` following the player, flash on hit. Procedural gradient texture (no external assets).
5. Persistence: `SaveData` custom `Resource` (Unity ScriptableObject equivalent) saved to `user://save_data.tres` holding player name, and per difficulty the longest time and completion flag. "Highest level" = highest difficulty played (Hard > Normal > Easy).
6. Main menu: name field (persisted), best-run label, animated (pulsing) Play button, Credits button, responsive layout.
7. Credits scene: title, developers Facundo Guiñazú and Bautista Prieto, tools used (Godot, MediaPipe), animated scroll, Back button / ESC.
8. Existing `test_gameplay.gd` keeps passing (grayscale only, no `Sprite2D`/`TextureRect`, procedural audio).

### Out of Scope
- Real multi-level campaign (the game keeps one 45 s level with 3 difficulties).
- Colour palette (user chose strictly black and white).

## 2. Decision Log
- Highest level = highest difficulty played; name asked in main menu; strictly B/W with light+glow; credits list both authors + tools (user answers, 2026-10-26).
