extends Node
## Game controller (autoload "GameManager").
##
## Owns the high level game state, scene navigation and the persistent
## SaveData resource (player name + best run per difficulty).

signal state_changed(new_state: int)
signal record_updated(difficulty: int, time_survived: float, completed: bool)
signal player_name_changed(new_name: String)

enum State {
	MENU = 0,
	PLAYING = 1,
	GAME_OVER = 2,
	COMPLETE = 3,
	CREDITS = 4,
}

const SAVE_PATH: String = "user://save_data.tres"
const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
const LEVEL_SCENE: String = "res://scenes/level.tscn"
const CREDITS_SCENE: String = "res://scenes/credits.tscn"
const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard"]
const MAX_NAME_LENGTH: int = 12
const SaveDataScript: GDScript = preload("res://scripts/data/save_data.gd")

const DEV_SAVE_PATH: String = "res://data/save_data.tres"

var state: int = State.MENU
var save_data: Resource = null
var save_path: String = SAVE_PATH


func _ready() -> void:
	load_game()
	# Ensure the file exists on disk on first boot
	if not ResourceLoader.exists(save_path):
		save_game()


## Returns the absolute system path to the save file.
func get_absolute_save_path() -> String:
	return ProjectSettings.globalize_path(save_path)


## Opens the user save directory in the system file manager.
func open_save_folder() -> void:
	var dir_path: String = ProjectSettings.globalize_path("user://")
	OS.shell_open(dir_path)


## Loads the profile from disk, falling back to res:// template or creating a default one.
func load_game() -> void:
	save_data = null
	if ResourceLoader.exists(save_path):
		var loaded: Resource = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if loaded != null and loaded.get_script() == SaveDataScript:
			save_data = loaded
	if save_data == null and ResourceLoader.exists(DEV_SAVE_PATH):
		var dev_loaded: Resource = ResourceLoader.load(DEV_SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		if dev_loaded != null and dev_loaded.get_script() == SaveDataScript:
			save_data = dev_loaded.duplicate()
	if save_data == null:
		save_data = SaveDataScript.new()
	print("[GameManager] Loaded player data from: %s (Player: '%s', Best: %s)" % [
		get_absolute_save_path(),
		get_player_name(),
		get_best_summary()
	])


## Writes the profile to user://save_data.tres (and mirrors to res://data in debug).
func save_game() -> Error:
	if save_data == null:
		return ERR_UNCONFIGURED
	var err: Error = ResourceSaver.save(save_data, save_path)
	if err == OK:
		print("[GameManager] Saved player data to: %s" % get_absolute_save_path())
		if OS.is_debug_build() and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://data")):
			ResourceSaver.save(save_data, DEV_SAVE_PATH)
	else:
		push_warning("[GameManager] Failed to save game data, error code: %d" % err)
	return err


func set_state(new_state: int) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)


func get_player_name() -> String:
	return str(save_data.get("player_name")) if save_data != null else "PLAYER"


## Sanitises, stores and persists the player name.
func set_player_name(new_name: String) -> void:
	if save_data == null:
		return
	var cleaned: String = new_name.strip_edges().left(MAX_NAME_LENGTH)
	if cleaned.is_empty():
		cleaned = "PLAYER"
	save_data.set("player_name", cleaned)
	save_game()
	player_name_changed.emit(cleaned)


func get_difficulty_name(difficulty: int) -> String:
	return DIFFICULTY_NAMES[clampi(difficulty, 0, DIFFICULTY_NAMES.size() - 1)]


## Records a finished run. Returns true when it is a new personal record.
func report_result(difficulty: int, time_survived: float, completed: bool) -> bool:
	if save_data == null:
		return false
	var improved: bool = bool(save_data.call("submit_result", difficulty, time_survived, completed))
	if improved:
		save_game()
		record_updated.emit(difficulty, time_survived, completed)
	set_state(State.COMPLETE if completed else State.GAME_OVER)
	return improved


## One-line summary of the best run at the highest difficulty reached.
func get_best_summary() -> String:
	if save_data == null:
		return "No runs yet"
	var record: Dictionary = save_data.call("get_highest_record") as Dictionary
	if record.is_empty():
		return "No runs yet"
	var status: String = "COMPLETED" if bool(record.get("completed", false)) else "%.1fs" % float(record.get("time", 0.0))
	return "BEST  %s  -  %s" % [get_difficulty_name(int(record.get("difficulty", 0))).to_upper(), status]


func go_to_menu() -> void:
	set_state(State.MENU)
	_change_scene(MAIN_MENU_SCENE)


func start_level(difficulty: int) -> void:
	Engine.set_meta(&"selected_difficulty", difficulty)
	set_state(State.PLAYING)
	_change_scene(LEVEL_SCENE)


func go_to_credits() -> void:
	set_state(State.CREDITS)
	_change_scene(CREDITS_SCENE)


func _change_scene(path: String) -> void:
	if is_inside_tree() and get_tree() != null:
		get_tree().change_scene_to_file(path)
