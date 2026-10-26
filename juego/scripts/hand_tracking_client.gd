extends Node
## Autoload client that regulates the headless Python MediaPipe hand-tracker
## subprocess across the game's lifetime and polls UDP 127.0.0.1:5005 for
## little-endian binary landmark packets (<i63f and <i).

signal tracking_state_changed(new_state: int, label_text: String)
signal fist_closed_triggered

enum TrackingState {
	OFFLINE = 0,
	NO_HAND = 1,
	TRACKING = 2,
}

const UDP_HOST: String = "127.0.0.1"
const UDP_PORT: int = 5005
const LANDMARK_COUNT: int = 21
const FLOATS_PER_LANDMARK: int = 3
const FULL_PACKET_BYTES: int = 4 + LANDMARK_COUNT * FLOATS_PER_LANDMARK * 4
const EMPTY_PACKET_BYTES: int = 4
const PACKET_TIMEOUT: float = 0.5
const HEARTBEAT_MAX_AGE_SEC: int = 5

const PALM_LANDMARK_INDICES: Array[int] = [0, 5, 9, 13, 17]
const FINGERTIP_LANDMARK_INDICES: Array[int] = [4, 8, 12, 16, 20]
const FIST_FINGER_TRIPLETS: Array[Array] = [
	[5, 6, 8],
	[9, 10, 12],
	[13, 14, 16],
	[17, 18, 20],
]

var auto_manage_process: bool = true
var udp_port: int = UDP_PORT
var udp_bound: bool = false
var tracker_pid: int = -1
var tracking_state: int = TrackingState.OFFLINE
var has_hand: bool = false
var is_fist: bool = false
var fist_just_closed: bool = false
var landmark_revision: int = 0
var landmarks: Array[Vector3] = []
var packets_received_count: int = 0
var process_spawn_count: int = 0
var process_stop_count: int = 0
var last_status_text: String = ""
var last_launch_executable: String = ""
var last_launch_args: PackedStringArray = PackedStringArray()

var _udp: PacketPeerUDP = PacketPeerUDP.new()
var _queued_packets: Array[PackedByteArray] = []
var _time_since_last_packet: float = 999.0
var _has_received_packet: bool = false
var _was_fist: bool = false
var _has_seen_open_hand: bool = false
var _status_file_override: String = ""
var _status_check_timer: float = 0.0
var _cached_heartbeat_ready: bool = false
var _cached_heartbeat_error: bool = false
var _mock_process_mode: bool = false
var _mock_running_pids: Dictionary = {}
var _next_mock_pid: int = 41000


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not is_inside_tree() or not auto_manage_process:
		return
	bind_udp(udp_port)
	start_tracker_process()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not is_inside_tree() or not auto_manage_process:
		return
	poll_and_update(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		stop_tracker_process()
		close_udp()


func _exit_tree() -> void:
	stop_tracker_process()
	close_udp()


## Enables or disables mock subprocess lifecycle mode for hardware-independent tests.
func set_mock_process_mode(enabled: bool) -> void:
	_mock_process_mode = enabled
	if not enabled:
		_mock_running_pids.clear()


## Overrides the .tracker.status file path for deterministic status tests.
func set_status_file_override(path: String) -> void:
	_status_file_override = path
	_refresh_heartbeat_cache()


## Binds the non-blocking UDP socket to 127.0.0.1:port.
func bind_udp(port: int = UDP_PORT) -> Error:
	if udp_bound and udp_port == port:
		return OK
	close_udp()
	udp_port = port
	var err: Error = _udp.bind(udp_port, UDP_HOST)
	udp_bound = (err == OK)
	return err


## Closes the UDP socket if bound.
func close_udp() -> void:
	if udp_bound:
		_udp.close()
		udp_bound = false


## Resolves the tracker_server directory path relative to the Godot project.
func get_tracker_server_dir() -> String:
	return ProjectSettings.globalize_path("res://../tracker_server").simplify_path()


## Resolves the Python tracker executable and arguments for headless launch.
func resolve_tracker_launch_command() -> Dictionary:
	var tracker_dir: String = get_tracker_server_dir()
	var is_windows: bool = OS.get_name() == "Windows"
	var venv_entry: String = tracker_dir.path_join(
		".venv/Scripts/mediapipe-py.exe" if is_windows else ".venv/bin/mediapipe-py"
	)
	if FileAccess.file_exists(venv_entry):
		return {
			"executable": venv_entry,
			"args": PackedStringArray(["--headless"]),
		}

	var venv_python: String = tracker_dir.path_join(
		".venv/Scripts/python.exe" if is_windows else ".venv/bin/python"
	)
	if FileAccess.file_exists(venv_python):
		return {
			"executable": venv_python,
			"args": PackedStringArray(["-m", "mediapipe_py.main", "--headless"]),
		}

	return {
		"executable": "uv",
		"args": PackedStringArray(["run", "--directory", tracker_dir, "mediapipe-py", "--headless"]),
	}


## Starts the Python tracker server in headless mode if not already running.
func start_tracker_process(allow_in_test: bool = false) -> bool:
	# Headless test runs have no display/camera context; only explicit tests may
	# launch the tracker there. Normal games still auto-manage the subprocess.
	if (Engine.is_editor_hint() or DisplayServer.get_name() == "headless") and not allow_in_test:
		return false
	if is_tracker_process_alive():
		return false
	_refresh_heartbeat_cache()
	if _cached_heartbeat_ready or (_has_received_packet and _time_since_last_packet <= PACKET_TIMEOUT):
		return false

	_clear_stale_status_files()
	OS.set_environment("TRACKER_HEADLESS", "1")
	var cmd: Dictionary = resolve_tracker_launch_command()
	var executable: String = str(cmd.get("executable", ""))
	var args: PackedStringArray = cmd.get("args", PackedStringArray()) as PackedStringArray
	if executable.is_empty():
		return false

	last_launch_executable = executable
	last_launch_args = args

	if _mock_process_mode:
		var pid: int = _next_mock_pid
		_next_mock_pid += 1
		_mock_running_pids[pid] = true
		tracker_pid = pid
		process_spawn_count += 1
		return true

	var spawned_pid: int = OS.create_process(executable, args, false)
	if spawned_pid <= 0:
		tracker_pid = -1
		return false

	tracker_pid = spawned_pid
	process_spawn_count += 1
	return true


## Terminates the spawned Python tracker process if one is active.
func stop_tracker_process() -> void:
	if tracker_pid <= 0:
		return
	var pid_to_stop: int = tracker_pid
	tracker_pid = -1
	if _mock_process_mode:
		if _mock_running_pids.has(pid_to_stop):
			_mock_running_pids.erase(pid_to_stop)
			process_stop_count += 1
		return

	if OS.is_process_running(pid_to_stop):
		OS.kill(pid_to_stop)
		process_stop_count += 1


## Returns true if the spawned tracker subprocess is currently running.
func is_tracker_process_alive() -> bool:
	if tracker_pid <= 0:
		return false
	if _mock_process_mode:
		return _mock_running_pids.get(tracker_pid, false) == true
	return OS.is_process_running(tracker_pid)


## Queues a raw UDP binary packet for deterministic processing on the next poll_and_update call.
func queue_synthetic_packet(packet: PackedByteArray) -> void:
	_queued_packets.append(packet)


## Drains a batch of UDP binary packets and applies only the newest valid packet (O5).
func ingest_packet_batch(packets: Array[PackedByteArray]) -> bool:
	var latest_valid: Dictionary = {}
	for pkt: PackedByteArray in packets:
		var decoded: Dictionary = decode_packet(pkt)
		if bool(decoded.get("valid", false)):
			latest_valid = decoded
			packets_received_count += 1
	if latest_valid.is_empty():
		return false
	_apply_decoded_packet(latest_valid)
	return true


## Decodes and immediately applies a single raw binary UDP packet (<i63f or <i).
func ingest_packet(packet: PackedByteArray) -> bool:
	var decoded: Dictionary = decode_packet(packet)
	if not bool(decoded.get("valid", false)):
		return false
	packets_received_count += 1
	_apply_decoded_packet(decoded)
	return true


## Decodes a little-endian binary UDP packet from tracker_server (<i63f or <i).
func decode_packet(packet: PackedByteArray) -> Dictionary:
	if packet.size() < EMPTY_PACKET_BYTES:
		return {"valid": false, "count": 0, "landmarks": []}

	var count: int = packet.decode_s32(0)
	if count == 0:
		return {"valid": true, "count": 0, "landmarks": []}

	if count != LANDMARK_COUNT or packet.size() < FULL_PACKET_BYTES:
		return {"valid": false, "count": count, "landmarks": []}

	var parsed: Array[Vector3] = []
	parsed.resize(LANDMARK_COUNT)
	var offset: int = 4
	for i: int in range(LANDMARK_COUNT):
		var lx: float = packet.decode_float(offset)
		var ly: float = packet.decode_float(offset + 4)
		var lz: float = packet.decode_float(offset + 8)
		parsed[i] = Vector3(lx, ly, lz)
		offset += 12

	return {"valid": true, "count": LANDMARK_COUNT, "landmarks": parsed}


## Encodes 21 (x, y, z) landmarks into the tracker's little-endian <i63f binary format.
static func encode_landmarks_packet(points: Array[Vector3]) -> PackedByteArray:
	if points.size() != LANDMARK_COUNT:
		return encode_empty_packet()
	var buf: PackedByteArray = PackedByteArray()
	buf.resize(FULL_PACKET_BYTES)
	buf.encode_s32(0, LANDMARK_COUNT)
	var offset: int = 4
	for i: int in range(LANDMARK_COUNT):
		var pt: Vector3 = points[i]
		buf.encode_float(offset, pt.x)
		buf.encode_float(offset + 4, pt.y)
		buf.encode_float(offset + 8, pt.z)
		offset += 12
	return buf


## Encodes a 0-landmark packet in the tracker's little-endian <i binary format.
static func encode_empty_packet() -> PackedByteArray:
	var buf: PackedByteArray = PackedByteArray()
	buf.resize(EMPTY_PACKET_BYTES)
	buf.encode_s32(0, 0)
	return buf


## Polls queued UDP packets, drains the socket buffer to the freshest packet, and updates state.
func poll_and_update(delta: float) -> void:
	var drained: Array[PackedByteArray] = []
	if not _queued_packets.is_empty():
		drained.append_array(_queued_packets)
		_queued_packets.clear()

	if udp_bound:
		while _udp.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _udp.get_packet()
			if _udp.get_packet_error() == OK and pkt.size() >= EMPTY_PACKET_BYTES:
				drained.append(pkt)

	if not drained.is_empty():
		ingest_packet_batch(drained)
	else:
		_time_since_last_packet += maxf(0.0, delta)

	_status_check_timer -= delta
	if _status_check_timer <= 0.0:
		_status_check_timer = 0.5
		_refresh_heartbeat_cache()

	_refresh_tracking_state()


## Returns the horizontally mirrored palm center (average of #0, #5, #9, #13, #17 with 1.0 - x).
func get_mirrored_palm_center() -> Vector2:
	if landmarks.size() < LANDMARK_COUNT:
		return Vector2(0.5, 0.5)
	var sum_x: float = 0.0
	var sum_y: float = 0.0
	for idx: int in PALM_LANDMARK_INDICES:
		var lm: Vector3 = landmarks[idx]
		sum_x += lm.x
		sum_y += lm.y
	var count_f: float = float(PALM_LANDMARK_INDICES.size())
	var avg_x: float = sum_x / count_f
	var avg_y: float = sum_y / count_f
	return Vector2(clampf(1.0 - avg_x, 0.0, 1.0), clampf(avg_y, 0.0, 1.0))


## Returns all 21 landmarks as horizontally mirrored normalized 2D coordinates (1.0 - x, y).
func get_mirrored_landmarks_2d() -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if landmarks.size() < LANDMARK_COUNT:
		return result
	result.resize(LANDMARK_COUNT)
	for i: int in range(LANDMARK_COUNT):
		var lm: Vector3 = landmarks[i]
		result[i] = Vector2(clampf(1.0 - lm.x, 0.0, 1.0), clampf(lm.y, 0.0, 1.0))
	return result


## Consumes and returns true if a rising-edge open-to-closed fist trigger is pending.
func consume_fist_closed_trigger() -> bool:
	if not fist_just_closed:
		return false
	fist_just_closed = false
	return true


## Returns the HUD status pill text for the current tracking state (AC6).
func get_status_label_text() -> String:
	match tracking_state:
		TrackingState.TRACKING:
			return "HAND: TRACKING"
		TrackingState.NO_HAND:
			return "HAND: NO HAND"
		_:
			return "HAND: OFFLINE"


## Evaluates whether the given 21 landmarks form a closed fist (#8, #12, #16, #20 curled to palm).
static func evaluate_closed_fist(points: Array[Vector3]) -> bool:
	if points.size() < LANDMARK_COUNT:
		return false

	var wrist: Vector2 = Vector2(points[0].x, points[0].y)
	var palm_sum: Vector2 = Vector2.ZERO
	for idx: int in PALM_LANDMARK_INDICES:
		palm_sum += Vector2(points[idx].x, points[idx].y)
	var palm_center: Vector2 = palm_sum / float(PALM_LANDMARK_INDICES.size())

	var mcp_dist_sum: float = 0.0
	for mcp_idx: int in [5, 9, 13, 17]:
		mcp_dist_sum += Vector2(points[mcp_idx].x, points[mcp_idx].y).distance_to(palm_center)
	var palm_radius: float = maxf(0.015, mcp_dist_sum / 4.0)

	var curled_fingers: int = 0
	for triplet: Array in FIST_FINGER_TRIPLETS:
		var mcp_pt: Vector2 = Vector2(points[int(triplet[0])].x, points[int(triplet[0])].y)
		var pip_pt: Vector2 = Vector2(points[int(triplet[1])].x, points[int(triplet[1])].y)
		var tip_pt: Vector2 = Vector2(points[int(triplet[2])].x, points[int(triplet[2])].y)

		var tip_to_palm: float = tip_pt.distance_to(palm_center)
		var mcp_to_palm: float = mcp_pt.distance_to(palm_center)
		var tip_to_wrist: float = tip_pt.distance_to(wrist)
		var pip_to_wrist: float = pip_pt.distance_to(wrist)

		if tip_to_palm <= maxf(mcp_to_palm * 1.35, palm_radius * 1.35) or tip_to_wrist <= pip_to_wrist * 1.05:
			curled_fingers += 1

	return curled_fingers >= 3


func _apply_decoded_packet(decoded: Dictionary) -> void:
	_has_received_packet = true
	_time_since_last_packet = 0.0
	var count: int = int(decoded.get("count", 0))
	if count == LANDMARK_COUNT:
		var pts: Array[Vector3] = []
		var raw_list: Array = decoded.get("landmarks", [])
		pts.resize(LANDMARK_COUNT)
		for i: int in range(LANDMARK_COUNT):
			pts[i] = raw_list[i] as Vector3
		landmarks = pts
		has_hand = true
		landmark_revision += 1

		var now_fist: bool = evaluate_closed_fist(landmarks)
		if not now_fist:
			_has_seen_open_hand = true
			fist_just_closed = false
		elif _has_seen_open_hand and not _was_fist:
			fist_just_closed = true
			fist_closed_triggered.emit()
		_was_fist = now_fist
		is_fist = now_fist
	else:
		_clear_hand_tracking_state()

	_refresh_tracking_state()


func _clear_hand_tracking_state() -> void:
	has_hand = false
	is_fist = false
	fist_just_closed = false
	_was_fist = false
	_has_seen_open_hand = false
	landmarks.clear()


func _refresh_tracking_state() -> void:
	var packet_fresh: bool = _has_received_packet and _time_since_last_packet <= PACKET_TIMEOUT
	if has_hand and not packet_fresh:
		_clear_hand_tracking_state()

	var next_state: int = TrackingState.OFFLINE
	if _cached_heartbeat_error and not packet_fresh:
		next_state = TrackingState.OFFLINE
	elif has_hand and packet_fresh:
		next_state = TrackingState.TRACKING
	elif packet_fresh or (_cached_heartbeat_ready and not _cached_heartbeat_error):
		next_state = TrackingState.NO_HAND
	else:
		next_state = TrackingState.OFFLINE

	var prev_state: int = tracking_state
	tracking_state = next_state
	if prev_state != tracking_state:
		tracking_state_changed.emit(tracking_state, get_status_label_text())


func _get_candidate_status_files() -> Array[String]:
	if not _status_file_override.is_empty():
		return [_status_file_override]
	if not auto_manage_process:
		return []
	return [
		ProjectSettings.globalize_path("res://.tracker.status").simplify_path(),
		get_tracker_server_dir().path_join(".tracker.status"),
		ProjectSettings.globalize_path("res://../.tracker.status").simplify_path(),
	]


func _refresh_heartbeat_cache() -> void:
	_cached_heartbeat_ready = false
	_cached_heartbeat_error = false
	var candidates: Array[String] = _get_candidate_status_files()
	if candidates.is_empty():
		return

	var now_unix: int = int(Time.get_unix_time_from_system())
	var newest_mtime: int = -1
	var newest_text: String = ""

	for path: String in candidates:
		if not FileAccess.file_exists(path):
			continue
		var mtime: int = int(FileAccess.get_modified_time(path))
		if mtime >= newest_mtime:
			newest_mtime = mtime
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file != null:
				newest_text = file.get_as_text().strip_edges()

	if newest_mtime < 0:
		return

	last_status_text = newest_text
	var age: int = maxi(0, now_unix - newest_mtime)
	if newest_text.begins_with("error"):
		if age <= HEARTBEAT_MAX_AGE_SEC * 2:
			_cached_heartbeat_error = true
	elif newest_text == "ready" and age <= HEARTBEAT_MAX_AGE_SEC:
		_cached_heartbeat_ready = true


func _clear_stale_status_files() -> void:
	var now_unix: int = int(Time.get_unix_time_from_system())
	for path: String in _get_candidate_status_files():
		if not FileAccess.file_exists(path):
			continue
		var mtime: int = int(FileAccess.get_modified_time(path))
		if now_unix - mtime > HEARTBEAT_MAX_AGE_SEC:
			DirAccess.remove_absolute(path)
