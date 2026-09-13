extends MusicDirector
class_name AccurateMusicDirector
## Production clock fixes layered over MusicDirector.
##
## - Uses Godot's recommended heard-audio clock:
##   playback_position + time_since_last_mix - output_latency.
## - Caches output latency instead of requesting it every frame.
## - Keeps absolute song time separate from beat-grid offset.
## - Uses analyzer beat timestamps when available, falling back to BPM math.
## - Guards against tiny backwards clock jitter between audio mix updates.

var _cached_output_latency: float = 0.0
var _last_clock_position: float = 0.0

func _ready() -> void:
	refresh_output_latency()
	super._ready()
	_last_clock_position = song_position

func refresh_output_latency() -> void:
	_cached_output_latency = maxf(AudioServer.get_output_latency(), 0.0)

func _reset_clock() -> void:
	super._reset_clock()
	_last_clock_position = 0.0

func _apply_profile(profile: SongProfile) -> void:
	if profile != null:
		bpm = maxf(profile.bpm, 1.0)
		seconds_per_beat = 60.0 / bpm
		seconds_per_bar = seconds_per_beat * float(maxi(profile.beats_per_bar, 1))
		if _player != null:
			_player.stream = profile.resolve_stream()
			if _player.stream != null and _player.stream.has_method("get_length"):
				_song_length = float(_player.stream.get_length())
			else:
				_song_length = 0.0
		_prev_section_index = -999
	else:
		bpm = fallback_bpm
		seconds_per_beat = 60.0 / maxf(bpm, 1.0)
		seconds_per_bar = seconds_per_beat * float(maxi(fallback_beats_per_bar, 1))
		_song_length = 0.0
		if _player != null:
			_player.stream = null
	current_beat = 0
	current_bar = 0
	beat_phase = 0.0
	bar_phase = 0.0

func set_song(profile: SongProfile, play_immediately: bool = true) -> void:
	song_profile = profile
	_apply_profile(profile)
	_reset_clock()
	refresh_output_latency()
	if play_immediately and profile != null and _player != null and _player.stream != null:
		play_song()
	else:
		stop_song()

func is_fallback() -> bool:
	return song_profile == null or _player == null or _player.stream == null

func seek_to(pos: float) -> void:
	pos = maxf(0.0, pos)
	if _player != null and _player.stream != null and _player.playing:
		_player.play(pos)
	song_position = pos
	raw_playback_position = pos
	_last_clock_position = pos
	_prev_beat = -1
	_prev_bar = -1
	_prev_phrase = -1
	_prev_section_index = -999
	_prev_important = false

func _update_time(delta: float) -> void:
	if is_fallback():
		if is_playing:
			song_position += delta
			raw_playback_position = song_position
			_last_clock_position = song_position
		return

	if _player == null:
		return
	if _player.playing:
		is_playing = true
		_was_playing = true
		var raw: float = _player.get_playback_position()
		raw_playback_position = raw
		# Godot's recommended position corresponding to what the user is hearing.
		var candidate: float = raw + AudioServer.get_time_since_last_mix() - _cached_output_latency + latency_compensation
		candidate = maxf(candidate, 0.0)
		# Audio mix timing can occasionally report a tiny backwards step. Ignore it
		# during normal playback; explicit seeks reset _last_clock_position above.
		if candidate + 0.002 >= _last_clock_position:
			song_position = maxf(candidate, _last_clock_position)
			_last_clock_position = song_position
		_song_length = maxf(_song_length, song_position + 1.0)
	else:
		is_playing = false

func _update_beats() -> void:
	if seconds_per_beat <= 0.001:
		return
	# Beat offset belongs to the beat grid only. Section/moment queries continue
	# to use absolute `song_position` seconds.
	var grid_pos: float = song_position
	if song_profile != null:
		grid_pos -= song_profile.beat_offset
	if grid_pos < 0.0:
		current_beat = -1
		current_bar = -1
		beat_phase = 0.0
		bar_phase = 0.0
		phrase_index = -1
		phrase_phase = 0.0
		return

	var analysis_beats: Array = []
	if song_profile != null:
		analysis_beats = song_profile.get_analysis_beats()
	if analysis_beats.size() >= 2:
		_update_beats_from_timestamps(grid_pos, analysis_beats)
	else:
		_update_beats_from_bpm(grid_pos)

func _update_beats_from_bpm(grid_pos: float) -> void:
	var beats_precise: float = grid_pos / seconds_per_beat
	var beat_idx: int = int(floor(beats_precise))
	var phase: float = beats_precise - floor(beats_precise)
	_apply_beat_state(beat_idx, phase)

func _update_beats_from_timestamps(grid_pos: float, beats: Array) -> void:
	# Binary-search the last analyzed beat at or before the heard song time.
	var lo: int = 0
	var hi: int = beats.size()
	while lo < hi:
		var mid: int = int((lo + hi) / 2)
		if float(beats[mid]) <= grid_pos:
			lo = mid + 1
		else:
			hi = mid
	var beat_idx: int = lo - 1
	if beat_idx < 0:
		current_beat = -1
		current_bar = -1
		beat_phase = 0.0
		bar_phase = 0.0
		phrase_index = -1
		phrase_phase = 0.0
		return
	var beat_t: float = float(beats[beat_idx])
	var next_t: float = beat_t + seconds_per_beat
	if beat_idx + 1 < beats.size():
		next_t = float(beats[beat_idx + 1])
	var phase: float = clampf((grid_pos - beat_t) / maxf(next_t - beat_t, 0.001), 0.0, 0.999999)
	_apply_beat_state(beat_idx, phase)

func _apply_beat_state(beat_idx: int, phase: float) -> void:
	beat_phase = phase
	var beats_per_bar_local: int = fallback_beats_per_bar
	var phrase_len: int = 16
	if song_profile != null:
		beats_per_bar_local = maxi(song_profile.beats_per_bar, 1)
		phrase_len = maxi(song_profile.beats_per_phrase, 1)
	var bar_idx: int = int(floor(float(beat_idx) / float(beats_per_bar_local)))
	var phrase_idx_local: int = int(floor(float(beat_idx) / float(phrase_len)))
	current_beat = beat_idx
	current_bar = bar_idx
	bar_phase = (float(beat_idx % beats_per_bar_local) + phase) / float(beats_per_bar_local)
	phrase_index = phrase_idx_local
	phrase_phase = (float(beat_idx % phrase_len) + phase) / float(phrase_len)

	if beat_idx != _prev_beat:
		_prev_beat = beat_idx
		beat.emit(beat_idx, song_position)
		if beat_idx % beats_per_bar_local == 0:
			downbeat.emit(bar_idx, song_position)
			if bar_idx != _prev_bar:
				_prev_bar = bar_idx
				bar.emit(bar_idx, song_position)
		if beat_idx % phrase_len == 0 and phrase_idx_local != _prev_phrase:
			_prev_phrase = phrase_idx_local
			phrase.emit(phrase_idx_local, song_position)

func get_music_clock_state() -> Dictionary:
	var state: Dictionary = super.get_music_clock_state()
	state["output_latency"] = _cached_output_latency
	var using_analysis: bool = song_profile != null and song_profile.get_analysis_beats().size() >= 2
	state["beat_source"] = "ANALYSIS" if using_analysis else "BPM"
	return state
