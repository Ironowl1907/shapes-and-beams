extends Node
## Sound controller (autoload "SoundManager").
##
## Creates the Music and SFX buses at runtime, owns a small SFX player pool and
## a dedicated music player, and persists the volume settings via GameManager.

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const SFX_POOL_SIZE: int = 8
const AudioLibrary: GDScript = preload("res://scripts/audio_library.gd")

var music_player: AudioStreamPlayer = null
var _sfx_pool: Array[AudioStreamPlayer] = []
var _pool_cursor: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(BUS_MUSIC)
	_ensure_bus(BUS_SFX)

	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.bus = BUS_MUSIC
	add_child(music_player)

	for i: int in range(SFX_POOL_SIZE):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		p.bus = BUS_SFX
		add_child(p)
		_sfx_pool.append(p)

	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager != null and game_manager.get("save_data") != null:
		var data: Resource = game_manager.get("save_data") as Resource
		set_music_volume(float(data.get("music_volume")))
		set_sfx_volume(float(data.get("sfx_volume")))


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, BUS_MASTER)


## Linear volume [0..1] for the music bus.
func set_music_volume(linear: float) -> void:
	_set_bus_linear(BUS_MUSIC, linear)
	_persist(&"music_volume", linear)


## Linear volume [0..1] for the SFX bus.
func set_sfx_volume(linear: float) -> void:
	_set_bus_linear(BUS_SFX, linear)
	_persist(&"sfx_volume", linear)


func get_music_volume() -> float:
	return _get_bus_linear(BUS_MUSIC)


func get_sfx_volume() -> float:
	return _get_bus_linear(BUS_SFX)


## Plays a sound effect on the next free pooled player.
func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null or _sfx_pool.is_empty():
		return
	var chosen: AudioStreamPlayer = null
	for p: AudioStreamPlayer in _sfx_pool:
		if not p.playing:
			chosen = p
			break
	if chosen == null:
		chosen = _sfx_pool[_pool_cursor]
		_pool_cursor = (_pool_cursor + 1) % _sfx_pool.size()
	chosen.stream = stream
	chosen.volume_db = volume_db
	chosen.play()


func play_music(stream: AudioStream) -> void:
	if stream == null or music_player == null:
		return
	if music_player.stream == stream and music_player.playing:
		return
	music_player.stream = stream
	music_player.play()


func stop_music() -> void:
	if music_player != null:
		music_player.stop()


## UI feedback sounds shared by every screen.
func play_ui_click() -> void:
	play_sfx(AudioLibrary.menu())


func play_ui_hover() -> void:
	play_sfx(AudioLibrary.menu(), -14.0)


func _set_bus_linear(bus_name: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var clamped: float = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clamped) if clamped > 0.0 else -80.0)


func _get_bus_linear(bus_name: StringName) -> float:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


func _persist(key: StringName, value: float) -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager == null or game_manager.get("save_data") == null:
		return
	(game_manager.get("save_data") as Resource).set(key, clampf(value, 0.0, 1.0))
