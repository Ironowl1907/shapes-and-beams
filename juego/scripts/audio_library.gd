extends RefCounted
## Procedural monochrome audio library.
##
## All streams are synthesized in memory so the project keeps zero external
## audio assets. Streams are cached statically and can be prewarmed before a
## scene transition to keep level entry hitch-free.

const MIX_RATE: int = 22050

static var _cache: Dictionary = {}


## Builds every stream once. Call from a deferred menu callback so the one-time
## synthesis cost is paid while the player is still in the menu.
static func prewarm() -> void:
	menu()
	hit()
	laser()
	explosion()
	shield_on()
	shield_block()
	shield_break()
	music()


static func menu() -> AudioStreamWAV:
	return _cached(&"menu", _make_menu)


static func hit() -> AudioStreamWAV:
	return _cached(&"hit", _make_hit)


static func laser() -> AudioStreamWAV:
	return _cached(&"laser", _make_laser)


static func explosion() -> AudioStreamWAV:
	return _cached(&"explosion", _make_explosion)


static func shield_on() -> AudioStreamWAV:
	return _cached(&"shield_on", _make_shield_on)


static func shield_block() -> AudioStreamWAV:
	return _cached(&"shield_block", _make_shield_block)


static func shield_break() -> AudioStreamWAV:
	return _cached(&"shield_break", _make_shield_break)


static func music() -> AudioStreamWAV:
	return _cached(&"music", _make_music)


static func _cached(id: StringName, maker: Callable) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id] as AudioStreamWAV
	var stream: AudioStreamWAV = maker.call() as AudioStreamWAV
	_cache[id] = stream
	return stream


static func _new_wav(sample_count: int, loop: bool) -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	wav.loop_begin = 0
	wav.loop_end = sample_count if loop else 0
	wav.data = PackedByteArray()
	return wav


static func _write_sample(data: PackedByteArray, index: int, sample: float) -> void:
	data.encode_s16(index * 2, clampi(int(round(clampf(sample, -1.0, 1.0) * 32767.0)), -32768, 32767))


static func _make_menu() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.07)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = 660.0 if progress < 0.45 else 880.0
		phase += TAU * freq / float(MIX_RATE)
		var wave: float = 0.75 * sin(phase) + 0.25 * signf(sin(phase))
		var env: float = minf(progress * 20.0, 1.0) * pow(1.0 - progress, 1.5)
		_write_sample(data, i, wave * env * 0.45)
	wav.data = data
	return wav


static func _make_hit() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.18)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(320.0, 75.0, progress)
		phase += TAU * freq / float(MIX_RATE)
		var tone: float = 0.65 * signf(sin(phase)) + 0.35 * sin(phase * 0.5)
		var noise: float = sin(float(i * 127 + 31) * 0.43) * cos(float(i * 73) * 0.19)
		var env: float = pow(1.0 - progress, 1.6)
		_write_sample(data, i, (tone * 0.7 + noise * 0.3 * (1.0 - progress)) * env * 0.6)
	wav.data = data
	return wav


static func _make_laser() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.16)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(1080.0, 240.0, pow(progress, 0.65))
		phase += TAU * freq / float(MIX_RATE)
		var wave: float = 0.65 * sin(phase) + 0.35 * sin(phase * 2.0)
		var env: float = minf(progress * 18.0, 1.0) * pow(1.0 - progress, 1.35)
		_write_sample(data, i, wave * env * 0.42)
	wav.data = data
	return wav


static func _make_explosion() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.28)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(165.0, 38.0, pow(progress, 0.55))
		phase += TAU * freq / float(MIX_RATE)
		var sub_bass: float = sin(phase) + 0.4 * signf(sin(phase * 0.5))
		var rumble: float = sin(float(i * 97 + 19) * 0.37) * cos(float(i * 53 + 7) * 0.23)
		var env: float = pow(1.0 - progress, 1.45)
		_write_sample(data, i, (sub_bass * 0.6 + rumble * 0.4) * env * 0.55)
	wav.data = data
	return wav


static func _make_shield_on() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.14)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(260.0, 620.0, progress)
		phase += TAU * freq / float(MIX_RATE)
		var env: float = minf(progress * 12.0, 1.0) * pow(1.0 - progress, 0.9)
		_write_sample(data, i, (sin(phase) * 0.6 + sin(phase * 1.5) * 0.4) * env * 0.28)
	wav.data = data
	return wav


static func _make_shield_block() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.12)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(880.0, 180.0, progress)
		phase += TAU * freq / float(MIX_RATE)
		var metal: float = 0.55 * sin(phase) + 0.45 * signf(sin(phase * 2.7))
		var noise: float = sin(float(i * 211 + 7) * 0.61) * 0.25
		var env: float = minf(progress * 40.0, 1.0) * pow(1.0 - progress, 2.0)
		_write_sample(data, i, (metal + noise) * env * 0.34)
	wav.data = data
	return wav


static func _make_shield_break() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.26)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(540.0, 58.0, pow(progress, 0.7))
		phase += TAU * freq / float(MIX_RATE)
		var glass: float = sin(phase) + 0.35 * sin(phase * 3.1)
		var noise: float = sin(float(i * 157 + 43) * 0.47)
		var env: float = pow(1.0 - progress, 1.3)
		_write_sample(data, i, (glass * 0.65 + noise * 0.35) * env * 0.32)
	wav.data = data
	return wav


static func _make_music() -> AudioStreamWAV:
	var notes: Array[float] = [220.0, 261.63, 329.63, 392.0, 293.66, 349.23, 329.63, 246.94]
	var step_duration: float = 0.20
	var step_samples: int = int(MIX_RATE * step_duration)
	var total_samples: int = step_samples * notes.size()
	var wav: AudioStreamWAV = _new_wav(total_samples, true)
	var data: PackedByteArray = PackedByteArray()
	data.resize(total_samples * 2)
	var lead_phase: float = 0.0
	var bass_phase: float = 0.0
	for i: int in range(total_samples):
		var step_idx: int = mini(i / step_samples, notes.size() - 1)
		var step_pos: float = float(i % step_samples) / float(step_samples)
		var lead_freq: float = notes[step_idx]
		var bass_freq: float = lead_freq * 0.5
		lead_phase += TAU * lead_freq / float(MIX_RATE)
		bass_phase += TAU * bass_freq / float(MIX_RATE)
		var env: float = minf(step_pos * 16.0, 1.0) * pow(1.0 - step_pos, 0.75)
		var lead: float = (0.7 * sin(lead_phase) + 0.3 * signf(sin(lead_phase))) * env
		var bass: float = sin(bass_phase) * (1.0 - step_pos * 0.5)
		_write_sample(data, i, (lead * 0.55 + bass * 0.45) * 0.30)
	wav.data = data
	return wav
