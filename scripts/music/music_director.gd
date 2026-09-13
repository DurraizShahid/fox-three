extends Node
class_name MusicDirector
## Central authoritative musical clock and playback controller.
## Single source of truth for song time, beats, sections, intensity and hype.
##
## Design notes:
## - Uses AudioStreamPlayer.get_playback_position() + AudioServer latency correction,
##   not a delta-accumulated timer, so the clock cannot drift from audio.
## - Everything derives timing from here so systems cannot drift independently.
## - Seeking/restarting resynchronizes via resync().

signal beat(beat_index: int, song_pos: float)
signal downbeat(bar_index: int, song_pos: float)
signal bar(bar_index: int, song_pos: float)
signal phrase(phrase_index: int, song_pos: float)
signal section_started(section: MusicSection, index: int)
signal section_ended(section: MusicSection, index: int)
signal important_moment_started(moment: ImportantMoment)
signal important_moment_ended(moment: ImportantMoment)
signal intensity_changed(new_intensity: float, new_importance: float)
signal hype_changed(new_hype: float)
signal song_finished
signal song_started(profile: SongProfile)

## ------------------------------------------------------------------
## Exports — wiring
## ------------------------------------------------------------------

@export var song_profile: SongProfile = null
## If set, MusicDirector auto-creates an AudioStreamPlayer child on this bus.
## If you already have a player in the scene, assign it via `music_player_path`.
@export var music_player_path: NodePath = NodePath("")
@export var music_bus: String = "Music"
@export var auto_play: bool = true
## When no SongProfile, MusicDirector stays in fallback (no beats, but still ticks).
@export var fallback_bpm: float = 128.0
@export var fallback_beats_per_bar: int = 4

## Smoothing / reactivity tuning (exposed for feel).
@export_category("Clock / Fell")
@export_range(0.0, 2.0, 0.01) var latency_compensation: float = 0.0 ## extra manual latency offset (s)
@export_category("Hype")
@export_range(0.5, 8.0, 0.1) var hype_response: float = 3.0 ## how fast hype chases target
@export_range(0.1, 4.0, 0.05) var hype_decay: float = 1.2 ## how fast hype falls when importance drops
@export_category("Spectrum")
@export_range(0.5, 20.0, 0.1) var spectrum_smoothing: float = 8.0

## ------------------------------------------------------------------
## Runtime state (read these; do not write)
## ------------------------------------------------------------------

var song_position: float = 0.0 ## compensated seconds from song start
var raw_playback_position: float = 0.0 ## without latency correction
var bpm: float = 128.0
var seconds_per_beat: float = 0.46875
var seconds_per_bar: float = 1.875
var current_beat: int = 0 ## floor((pos - offset)/spb)
var beat_phase: float = 0.0 ## 0..1 within beat
var current_bar: int = 0
var bar_phase: float = 0.0 ## 0..1 within bar
var phrase_index: int = 0
var phrase_phase: float = 0.0
var current_section: MusicSection = null
var current_section_index: int = -1
var section_progress: float = 0.0 ## 0..1 inside section
var current_intensity: float = 0.5
var current_importance: float = 0.0
var is_in_important_moment: bool = false
var hype: float = 0.0 ## 0..1 smoothed hype (the "impact_intensity" / "music_hype")
var is_playing: bool = false

## Live spectrum bands 0..1 (smoothed).
var low_energy: float = 0.0
var mid_energy: float = 0.0
var high_energy: float = 0.0
var overall_energy: float = 0.0

## ------------------------------------------------------------------
## Private
## ------------------------------------------------------------------

var _player: AudioStreamPlayer = null
var _spectrum: AudioEffectSpectrumAnalyzerInstance = null
var _prev_beat: int = -1
var _prev_bar: int = -1
var _prev_phrase: int = -1
var _prev_section_index: int = -999
var _prev_important: bool = false
var _prev_intensity: float = -1.0
var _hype_target: float = 0.0
var _was_playing: bool = false
var _song_length: float = 0.0
var _spectrum_bus_index: int = -1
var _spectrum_effect_index: int = -1
var _last_hype_emit: float = -1.0

# Band Hz ranges for spectrum analyzer (tune by ear; covers bass/mid/presence).
const LOW_HZ: Vector2 = Vector2(20.0, 250.0)
const MID_HZ: Vector2 = Vector2(250.0, 2000.0)
const HIGH_HZ: Vector2 = Vector2(2000.0, 11025.0)

## ------------------------------------------------------------------
## Lifecycle
## ------------------------------------------------------------------

func _ready() -> void:
	_resolve_player()
	_setup_spectrum()
	_apply_profile(song_profile)
	set_process(true)

func _resolve_player() -> void:
	if music_player_path != NodePath("") :
		_player = get_node_or_null(music_player_path) as AudioStreamPlayer
	if _player == null:
		# Look for a child AudioStreamPlayer named MusicPlayer.
		_player = get_node_or_null("MusicPlayer") as AudioStreamPlayer
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.name = "MusicPlayer"
		_player.bus = music_bus
		add_child(_player)
	else:
		# Ensure bus is correct (don't force if user wired custom).
		if music_bus != "" and _player.bus != music_bus:
			_player.bus = music_bus
	if _player != null and not _player.finished.is_connected(_on_song_finished):
		_player.finished.connect(_on_song_finished)

func _setup_spectrum() -> void:
	if music_bus == "":
		return
	_spectrum_bus_index = AudioServer.get_bus_index(music_bus)
	if _spectrum_bus_index == -1:
		# Bus may not exist in fallback/editor — not an error.
		return
	# Find first spectrum analyzer effect on this bus.
	for i in AudioServer.get_bus_effect_count(_spectrum_bus_index):
		var eff: AudioEffect = AudioServer.get_bus_effect(_spectrum_bus_index, i)
		if eff is AudioEffectSpectrumAnalyzer:
			_spectrum_effect_index = i
			_spectrum = AudioServer.get_bus_effect_instance(_spectrum_bus_index, i) as AudioEffectSpectrumAnalyzerInstance
			break

## Set or change the active song. Pass null for fallback (no music).
func set_song(profile: SongProfile, play_immediately: bool = true) -> void:
	song_profile = profile
	_apply_profile(profile)
	_reset_clock()
	if play_immediately and profile != null and profile.stream != null:
		play_song()
	elif profile == null:
		stop_song()

func _apply_profile(profile: SongProfile) -> void:
	if profile != null:
		bpm = maxf(profile.bpm, 1.0)
		seconds_per_beat = 60.0 / bpm
		seconds_per_bar = seconds_per_beat * float(maxi(profile.beats_per_bar, 1))
		if _player != null:
			_player.stream = profile.stream
			if _player.stream != null:
				# Estimate length if possible (OGG/MP3 expose via get_length? not uniform).
				if _player.stream.has_method("get_length"):
					_song_length = _player.stream.get_length()
				else:
					_song_length = 0.0
		# Reset section tracking so next tick fires section_started.
		_prev_section_index = -999
	else:
		bpm = fallback_bpm
		seconds_per_beat = 60.0 / maxf(bpm, 1.0)
		seconds_per_bar = seconds_per_beat * float(maxi(fallback_beats_per_bar, 1))
		_song_length = 0.0
	current_beat = 0
	current_bar = 0
	beat_phase = 0.0
	bar_phase = 0.0

func _reset_clock() -> void:
	song_position = 0.0
	raw_playback_position = 0.0
	current_beat = 0
	_prev_beat = -1
	_prev_bar = -1
	_prev_phrase = -1
	_prev_section_index = -999
	_prev_important = false
	_prev_intensity = -1.0
	hype = 0.0
	_hype_target = 0.0
	current_section = null
	current_section_index = -1

## ------------------------------------------------------------------
## Transport
## ------------------------------------------------------------------

func play_song(from_position: float = 0.0) -> void:
	if _player == null:
		_resolve_player()
		_setup_spectrum()
	if song_profile == null or _player == null or _player.stream == null:
		# Fallback: fabricate clock without audio.
		is_playing = true
		_was_playing = true
		_reset_clock()
		song_position = from_position
		if song_profile != null:
			song_started.emit(song_profile)
		return
	_player.play(from_position)
	is_playing = true
	_was_playing = true
	_reset_clock()
	song_position = from_position
	song_started.emit(song_profile)

func stop_song() -> void:
	if _player != null and _player.playing:
		_player.stop()
	is_playing = false
	_was_playing = false

func pause_song() -> void:
	if _player != null:
		_player.stream_paused = true
	is_playing = false

func resume_song() -> void:
	if _player != null:
		_player.stream_paused = false
	is_playing = _player != null and _player.playing

func seek_to(pos: float) -> void:
	pos = maxf(0.0, pos)
	if _player != null and _player.stream != null and _player.playing:
		var estimate: float = pos
		# AudioStreamPlayer.seek is via play(from_position).
		_player.play(estimate)
	song_position = pos
	_prev_beat = -1
	_prev_bar = -1
	_prev_phrase = -1
	# Force section re-evaluation next tick.

func seek_to_section(index: int) -> void:
	if song_profile == null:
		return
	var sorted: Array[MusicSection] = song_profile.get_sorted_sections()
	if index < 0 or index >= sorted.size():
		return
	seek_to(sorted[index].start_time + 0.02)

func restart_song() -> void:
	seek_to(0.0)
	if not is_playing:
		play_song(0.0)

## Resynchronize everything (call after Engine.time_scale hitstop, etc.).
func resync() -> void:
	# No-op for audio clock (it never drifts), but re-evaluate sections/beats.
	_prev_beat = -1
	_prev_bar = -1
	_prev_phrase = -1
	_prev_section_index = -999

func is_fallback() -> bool:
	return song_profile == null or song_profile.stream == null

## ------------------------------------------------------------------
## Per-frame clock
## ------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_time(delta)
	_update_beats()
	_update_section(delta)
	_update_hype(delta)
	_update_spectrum(delta)
	_check_song_end()

func _update_time(delta: float) -> void:
	if is_fallback():
		# Fallback: synthesize time without audio so stage still moves.
		if is_playing:
			song_position += delta
			raw_playback_position = song_position
		else:
			# Even when not playing in fallback, keep a slow synthetic clock so debug still moves?
			# Only when auto fallback play is desired. For now keep still unless playing.
			pass
		return

	if _player == null:
		return
	if _player.playing:
		is_playing = true
		_was_playing = true
		var raw: float = _player.get_playback_position()
		# Latency correction — compensate audio output delay so visuals align with heard beats.
		var latency: float = 0.0
		# AudioServer APIs exist on all platforms; guard for headless.
		latency += AudioServer.get_time_since_last_mix()
		latency += AudioServer.get_output_latency()
		raw_playback_position = raw
		song_position = raw + latency + latency_compensation
		# Apply beat offset (shifts grid so manual offset aligns with authored sections).
		if song_profile != null:
			song_position = maxf(0.0, song_position + song_profile.beat_offset)
		_song_length = maxf(_song_length, song_position + 1.0)
	else:
		if _was_playing:
			# Just stopped — emit finished handled elsewhere.
			pass
		is_playing = false

func _update_beats() -> void:
	var spb: float = seconds_per_beat
	if spb <= 0.001:
		return
	var beats_precise: float = song_position / spb
	var beat_idx: int = int(floor(beats_precise))
	var phase: float = beats_precise - floor(beats_precise)
	beat_phase = phase
	var beats_per_bar_local: int = fallback_beats_per_bar
	if song_profile != null:
		beats_per_bar_local = maxi(song_profile.beats_per_bar, 1)
	var bar_idx: int = int(floor(float(beat_idx) / float(beats_per_bar_local)))
	var bar_ph: float = (float(beat_idx % beats_per_bar_local) + phase) / float(beats_per_bar_local)
	var phrase_len: int = 16
	if song_profile != null:
		phrase_len = maxi(song_profile.beats_per_phrase, 1)
	var phrase_idx: int = int(floor(float(beat_idx) / float(phrase_len)))
	var phrase_ph: float = (float(beat_idx % phrase_len) + phase) / float(phrase_len)

	current_beat = beat_idx
	current_bar = bar_idx
	bar_phase = bar_ph
	phrase_index = phrase_idx
	phrase_phase = phrase_ph

	# Emit beat.
	if beat_idx != _prev_beat:
		_prev_beat = beat_idx
		beat.emit(beat_idx, song_position)
		# Downbeat when beat mod beats_per_bar == 0.
		if beat_idx % beats_per_bar_local == 0:
			downbeat.emit(bar_idx, song_position)
		# Bar signal also on downbeat (bar granularity).
		if beat_idx % beats_per_bar_local == 0:
			if bar_idx != _prev_bar:
				_prev_bar = bar_idx
				bar.emit(bar_idx, song_position)
		# Phrase every phrase_len beats.
		if beat_idx % phrase_len == 0:
			if phrase_idx != _prev_phrase:
				_prev_phrase = phrase_idx
				phrase.emit(phrase_idx, song_position)

func _update_section(_delta: float) -> void:
	if song_profile == null:
		if current_section != null:
			var prev: MusicSection = current_section
			current_section = null
			current_section_index = -1
			section_progress = 0.0
			current_intensity = 0.5
			current_importance = 0.0
			section_ended.emit(prev, _prev_section_index)
		return

	var sorted: Array[MusicSection] = song_profile.get_sorted_sections()
	var idx: int = -1
	var sec: MusicSection = null
	for i in sorted.size():
		if sorted[i].contains_time(song_position):
			idx = i
			sec = sorted[i]
			break
	# Also handle after-last-section: keep last section held until song end.
	if sec == null and not sorted.is_empty():
		if song_position >= sorted[sorted.size() - 1].end_time:
			# Past end — stay on last but at progress 1.
			sec = sorted[sorted.size() - 1]
			idx = sorted.size() - 1

	var changed: bool = (idx != _prev_section_index) or (sec != current_section)
	if changed:
		if current_section != null and _prev_section_index != -999:
			section_ended.emit(current_section, _prev_section_index)
		_prev_section_index = idx
		current_section = sec
		current_section_index = idx
		if sec != null:
			section_started.emit(sec, idx)
		section_progress = 0.0

	if sec != null:
		section_progress = sec.progress_at(song_position)
		current_intensity = song_profile.intensity_at(song_position)
		current_importance = song_profile.importance_at(song_position)
	else:
		current_intensity = song_profile.intensity_at(song_position) if song_profile != null else 0.45
		current_importance = 0.0
		section_progress = 0.0

	# Important moment tracking.
	var imp: bool = song_profile.is_in_important_moment(song_position) if song_profile != null else false
	var prev_imp: bool = _prev_important
	if imp != prev_imp:
		_prev_important = imp
		is_in_important_moment = imp
		if imp:
			var mom: ImportantMoment = song_profile.get_important_moment_at(song_position)
			important_moment_started.emit(mom)
		else:
			# We don't know which moment ended without storing prev — emit null and let listeners query.
			important_moment_ended.emit(null)

	if absf(current_intensity - _prev_intensity) > 0.015:
		_prev_intensity = current_intensity
		intensity_changed.emit(current_intensity, current_importance)

func _update_hype(delta: float) -> void:
	# Target is max(importance, remapped intensity) but importance dominates.
	var target: float = clampf(maxf(current_importance * 1.0, current_intensity * 0.65 + current_importance * 0.35), 0.0, 1.0)
	# Boost hype during important moments strongly toward 1.
	if is_in_important_moment:
		target = maxf(target, 0.92)
	# Sections with DROP/CLIMAX etc and high importance push harder.
	if current_section != null and current_importance > 0.75:
		match current_section.section_type:
			MusicSection.Type.DROP, MusicSection.Type.CLIMAX, MusicSection.Type.PEAK:
				target = maxf(target, 0.95)
			MusicSection.Type.GUITAR_SOLO, MusicSection.Type.SOLO, MusicSection.Type.CRESCENDO:
				target = maxf(target, 0.88)
	_hype_target = target
	var lambda: float
	if target > hype:
		lambda = hype_response
	else:
		lambda = hype_decay
	hype = lerpf(hype, target, 1.0 - exp(-lambda * delta))
	hype = clampf(hype, 0.0, 1.0)
	if absf(hype - _hype_target) < 0.001:
		hype = _hype_target

func _update_spectrum(delta: float) -> void:
	var t_low: float = 0.0
	var t_mid: float = 0.0
	var t_high: float = 0.0
	var t_all: float = 0.0
	if _spectrum != null:
		# Spectrum returns magnitude (linear 0..~something). Convert to 0..1 via log-ish mapping.
		var mag_low: float = _spectrum.get_magnitude_for_frequency_range(LOW_HZ.x, LOW_HZ.y).length()
		var mag_mid: float = _spectrum.get_magnitude_for_frequency_range(MID_HZ.x, MID_HZ.y).length()
		var mag_high: float = _spectrum.get_magnitude_for_frequency_range(HIGH_HZ.x, HIGH_HZ.y).length()
		# Common calibration: mag ~ 0..0.1 typical music. Scale and clamp.
		t_low = clampf((log(maxf(mag_low, 0.0001)) + 8.0) / 6.0, 0.0, 1.0) # log(0.0003) ~ -8, log(0.05) ~ -3
		t_mid = clampf((log(maxf(mag_mid, 0.0001)) + 8.0) / 6.0, 0.0, 1.0)
		t_high = clampf((log(maxf(mag_high, 0.0001)) + 8.0) / 6.0, 0.0, 1.0)
		# Rough fallback when analyzer returns 0 (silence/bus not yet primed): use intensity.
		if mag_low < 0.00005 and mag_mid < 0.00005 and mag_high < 0.00005:
			var fb: float = current_intensity * 0.5 + hype * 0.5
			t_low = fb * 0.9
			t_mid = fb * 0.85
			t_high = fb * 0.7
		t_all = (t_low + t_mid + t_high) / 3.0
	else:
		# No analyzer (bus missing or headless): synthesize from intensity/hype + beat pulse.
		var base: float = current_intensity * 0.55 + hype * 0.45
		var pulse: float = 0.0
		# Subtle beat pulse without needing analyzer.
		pulse = (1.0 - beat_phase) * 0.18 * (0.5 + hype * 0.5)
		if current_beat % 4 == 0:
			pulse *= 1.4
		t_low = clampf(base * 0.95 + pulse, 0.0, 1.0)
		t_mid = clampf(base * 0.85 + pulse * 0.7, 0.0, 1.0)
		t_high = clampf(base * 0.7 + pulse * 0.5, 0.0, 1.0)
		t_all = clampf(base + pulse * 0.3, 0.0, 1.0)

	var l: float = 1.0 - exp(-spectrum_smoothing * delta)
	low_energy = lerpf(low_energy, t_low, l)
	mid_energy = lerpf(mid_energy, t_mid, l)
	high_energy = lerpf(high_energy, t_high, l)
	overall_energy = lerpf(overall_energy, t_all, l)

	# Also synthesize hype_changed emission boundary check (do here once per frame).
	if absf(hype - _last_hype_emit) > 0.04:
		_last_hype_emit = hype
		hype_changed.emit(hype)

func _check_song_end() -> void:
	if is_fallback():
		return
	if _player == null or _player.stream == null:
		return
	if not _player.playing and _was_playing and song_position > 1.0:
		# Playback naturally ended.
		_was_playing = false
		is_playing = false
		song_finished.emit()

func _on_song_finished() -> void:
	# AudioStreamPlayer finished — note we still correct via _check_song_end for latency cases.
	if is_fallback():
		return
	is_playing = false
	_was_playing = false
	song_finished.emit()

## ------------------------------------------------------------------
## Public query API (for directors / HUD)
## ------------------------------------------------------------------

func get_song_position() -> float:
	return song_position

func get_bpm() -> float:
	return bpm

func get_seconds_per_beat() -> float:
	return seconds_per_beat

func get_beat() -> int:
	return current_beat

func get_beat_phase() -> float:
	return beat_phase

func get_bar() -> int:
	return current_bar

func get_bar_phase() -> float:
	return bar_phase

func get_phrase() -> int:
	return phrase_index

func get_phrase_phase() -> float:
	return phrase_phase

func get_section() -> MusicSection:
	return current_section

func get_section_progress() -> float:
	return section_progress

func get_intensity() -> float:
	return current_intensity

func get_importance() -> float:
	return current_importance

func get_hype() -> float:
	return hype

func is_in_important() -> bool:
	return is_in_important_moment

func get_spectrum() -> Dictionary:
	return {"low": low_energy, "mid": mid_energy, "high": high_energy, "overall": overall_energy}

## Distance helper: meters per beat using an expected forward speed.
func meters_per_beat(expected_speed: float) -> float:
	return maxf(expected_speed, 1.0) * seconds_per_beat

## Next downbeat time (seconds until next bar start).
func time_until_next_downbeat() -> float:
	var phase: float = bar_phase
	if phase < 0.001:
		return 0.0
	return (1.0 - phase) * seconds_per_bar

## Whether we are within threshold seconds of a beat.
func is_on_beat(threshold: float = 0.08) -> bool:
	return beat_phase < threshold / seconds_per_beat or beat_phase > 1.0 - threshold / seconds_per_beat

## State dict for debug HUD / music-reactive consumers.
func get_music_clock_state() -> Dictionary:
	return {
		"song_position": song_position,
		"bpm": bpm,
		"seconds_per_beat": seconds_per_beat,
		"beat": current_beat,
		"beat_phase": beat_phase,
		"bar": current_bar,
		"bar_phase": bar_phase,
		"phrase": phrase_index,
		"phrase_phase": phrase_phase,
		"section": current_section.get_type_name() if current_section != null else "NONE",
		"section_progress": section_progress,
		"intensity": current_intensity,
		"importance": current_importance,
		"hype": hype,
		"in_important": is_in_important_moment,
		"low": low_energy,
		"mid": mid_energy,
		"high": high_energy,
		"overall": overall_energy,
		"is_playing": is_playing,
		"is_fallback": is_fallback(),
	}
