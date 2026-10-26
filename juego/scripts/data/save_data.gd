class_name SaveData
extends Resource
## Persistent player profile (Godot equivalent of a Unity ScriptableObject).
##
## Stored as a custom Resource in user://save_data.tres through ResourceSaver.
## Keeps the player name plus, for every difficulty ("level tier"), the longest
## time survived and whether that tier was ever completed.

@export var player_name: String = "PLAYER"
## difficulty (int) -> { "time": float, "completed": bool }
@export var records: Dictionary = {}
@export_range(0.0, 1.0) var music_volume: float = 0.8
@export_range(0.0, 1.0) var sfx_volume: float = 1.0


## Returns the highest difficulty with a recorded run, or -1 when nothing is stored.
func get_highest_difficulty() -> int:
	var highest: int = -1
	for key: Variant in records.keys():
		highest = maxi(highest, int(key))
	return highest


## Returns the record of a difficulty ({} when never played).
func get_record(difficulty: int) -> Dictionary:
	return records.get(difficulty, {}) as Dictionary


## Returns the record of the highest difficulty played ({} when none).
func get_highest_record() -> Dictionary:
	var highest: int = get_highest_difficulty()
	if highest < 0:
		return {}
	var record: Dictionary = get_record(highest).duplicate()
	record["difficulty"] = highest
	return record


## Stores a run if it beats the current record of that difficulty.
## A completed run always beats an incomplete one; otherwise longer time wins.
## Returns true when the stored record changed.
func submit_result(difficulty: int, time_survived: float, completed: bool) -> bool:
	var current: Dictionary = get_record(difficulty)
	var improved: bool = current.is_empty()
	if not improved:
		var was_completed: bool = bool(current.get("completed", false))
		if completed and not was_completed:
			improved = true
		elif not completed and not was_completed and time_survived > float(current.get("time", 0.0)):
			improved = true
	if improved:
		records[difficulty] = {"time": time_survived, "completed": completed}
	return improved
