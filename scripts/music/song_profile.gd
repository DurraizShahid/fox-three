extends Resource
class_name SongProfile
## Reusable Resource describing a single song + its stage/environment mapping.
## See docs/music-system.md for authoring workflow.

@export var song_id: String = "untitled"
@export var song_name: String = "Untitled"
@export var stream: AudioStream = null
## Optional local/resource path fallback. Useful for local copyrighted test tracks
## that must not be committed as an ext_resource. Release profiles should normally
## assign `stream` directly so Godot includes the asset in exports.
@export_file var stream_path: String = ""

## Musical clock.
@export_range(40.0, 240.0, 0.1) var bpm: float = 128.0
## Positive values mean the beat grid begins later in the file. This shifts ONLY
## beat/bar/phrase timing; section and ImportantMoment times always remain absolute
## song-file seconds.
@export_range(-5.0, 5.0, 0.01) var beat_offset: float = 0.0
@export_range(1, 7, 1) var beats_per_bar: int = 4
@export_range(1, 64, 1) var beats_per_phrase: int = 16
@export var seed: int = 1337
@export_range(0.0, 1.0, 0.05) var difficulty: float = 0.5
@export_range(0.5, 2.0, 0.05) var global_speed_mult: float = 1.0
@export_range(0.5, 2.0, 0.05) var global_intensity_mult: float = 1.0

## Stage mapping.
@export var stage_theme: Resource = null ## StageTheme

## Manual definitions. Manual sections/moments override analyzer guesses that
## overlap the same time range.
@export var sections: Array[MusicSection] = []
@export var important_moments: Array[ImportantMoment] = []

## Optional sidecar JSON produced by tools/music_analysis/.
@export_file("*.json") var analysis_json_path: String = ""
var _analysis_cache: Dictionary = {}
var _analysis_loaded: bool = false
var _analysis_sections_cache: Array[MusicSection] = []
var _analysis_sections_built: bool = false
var _analysis_moments_cache: Array[ImportantMoment] = []
var _analysis_moments_built: bool = false

## ------------------------------------------------------------------
## Audio resolution
## ------------------------------------------------------------------

func resolve_stream() -> AudioStream:
	if stream != null:
		return stream
	if stream_path == "":
		return null
	if ResourceLoader.exists(stream_path):
		var loaded: Resource = load(stream_path)
		if loaded is AudioStream:
			return loaded as AudioStream
	return null

func has_resolved_stream() -> bool:
	return resolve_stream() != null

## ------------------------------------------------------------------
## Helpers — musical time
## ------------------------------------------------------------------

func seconds_per_beat() -> float:
	return 60.0 / maxf(bpm, 1.0)

func seconds_per_bar() -> float:
	return seconds_per_beat() * float(maxi(beats_per_bar, 1))

func seconds_per_phrase() -> float:
	return seconds_per_beat() * float(maxi(beats_per_phrase, 1))

## ------------------------------------------------------------------
## Analysis JSON
## ------------------------------------------------------------------

func reload_analysis() -> void:
	_analysis_loaded = false
	_analysis_cache = {}
	_analysis_sections_cache.clear()
	_analysis_sections_built = false
	_analysis_moments_cache.clear()
	_analysis_moments_built = false

func load_analysis() -> Dictionary:
	if _analysis_loaded:
		return _analysis_cache
	_analysis_loaded = true
	_analysis_cache = {}
	if analysis_json_path == "":
		return _analysis_cache
	if not FileAccess.file_exists(analysis_json_path):
		push_warning("[SongProfile] analysis JSON not found: %s" % analysis_json_path)
		return _analysis_cache
	var f: FileAccess = FileAccess.open(analysis_json_path, FileAccess.READ)
	if f == null:
		return _analysis_cache
	var text: String = f.get_as_text()
	if text == "":
		return _analysis_cache
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_analysis_cache = parsed as Dictionary
	else:
		push_warning("[SongProfile] failed to parse analysis JSON: %s" % analysis_json_path)
	return _analysis_cache

func has_analysis() -> bool:
	return not load_analysis().is_empty()

func get_analysis_beats() -> Array:
	var d: Dictionary = load_analysis()
	var value: Variant = d.get("beats", [])
	if value is Array:
		return value as Array
	return []

func _curve_at(key: String, song_pos: float, fallback: float) -> float:
	var d: Dictionary = load_analysis()
	var raw_curve: Variant = d.get(key, [])
	if not raw_curve is Array:
		return fallback
	var curve: Array = raw_curve as Array
	if curve.is_empty():
		return fallback
	var prev_t: float = 0.0
	var prev_v: float = fallback
	for i in curve.size():
		var item: Variant = curve[i]
		var t: float = 0.0
		var v: float = fallback
		if item is Dictionary:
			var row: Dictionary = item as Dictionary
			t = float(row.get("time", row.get("t", 0.0)))
			v = float(row.get("energy", row.get("importance", row.get("v", fallback))))
		elif item is Array:
			var pair: Array = item as Array
			if pair.size() < 2:
				continue
			t = float(pair[0])
			v = float(pair[1])
		else:
			continue
		if song_pos < t:
			if i == 0:
				return clampf(v, 0.0, 1.0)
			var frac: float = clampf((song_pos - prev_t) / maxf(t - prev_t, 0.001), 0.0, 1.0)
			return clampf(lerpf(prev_v, v, frac), 0.0, 1.0)
		prev_t = t
		prev_v = v
	return clampf(prev_v, 0.0, 1.0)

func get_analysis_energy_at(song_pos: float) -> float:
	return _curve_at("energy_curve", song_pos, 0.5)

func get_analysis_importance_at(song_pos: float) -> float:
	return _curve_at("importance_curve", song_pos, 0.0)

func _get_analysis_sections() -> Array[MusicSection]:
	if _analysis_sections_built:
		return _analysis_sections_cache
	_analysis_sections_built = true
	_analysis_sections_cache.clear()
	var d: Dictionary = load_analysis()
	var raw: Variant = d.get("sections", [])
	if not raw is Array:
		return _analysis_sections_cache
	var raw_sections: Array = raw as Array
	for item in raw_sections:
		if not item is Dictionary:
			continue
		var row: Dictionary = item as Dictionary
		var type_name: String = str(row.get("type", "VERSE")).to_upper()
		var s := MusicSection.new()
		s.section_type = MusicSection.type_from_string(type_name)
		if s.section_type == MusicSection.Type.CUSTOM:
			s.custom_type_name = type_name
		s.start_time = maxf(0.0, float(row.get("start", row.get("start_time", 0.0))))
		s.end_time = maxf(s.start_time + 0.05, float(row.get("end", row.get("end_time", s.start_time + 8.0))))
		s.intensity = clampf(float(row.get("intensity", 0.5)), 0.0, 1.0)
		s.importance = clampf(float(row.get("importance", 0.1)), 0.0, 1.0)
		s.density_mult = clampf(float(row.get("density_mult", 1.0)), 0.1, 4.0)
		s.speed_mult = clampf(float(row.get("speed_mult", 1.0)), 0.5, 2.0)
		s.auto_generated = true
		_analysis_sections_cache.append(s)
	_analysis_sections_cache.sort_custom(func(a: MusicSection, b: MusicSection) -> bool: return a.start_time < b.start_time)
	return _analysis_sections_cache

func _sections_overlap(a: MusicSection, b: MusicSection) -> bool:
	return a.start_time < b.end_time and b.start_time < a.end_time

## Automatic analyzer sections fill the song. A manual section removes any
## automatic section it overlaps, then takes its place. This keeps author intent
## authoritative while still making a raw analysis JSON useful by itself.
func get_effective_sections() -> Array[MusicSection]:
	var out: Array[MusicSection] = []
	for auto_section in _get_analysis_sections():
		var overridden: bool = false
		for manual_section in sections:
			if manual_section != null and _sections_overlap(auto_section, manual_section):
				overridden = true
				break
		if not overridden:
			out.append(auto_section)
	for manual_section in sections:
		if manual_section != null:
			out.append(manual_section)
	out.sort_custom(func(a: MusicSection, b: MusicSection) -> bool: return a.start_time < b.start_time)
	return out

func _get_analysis_moments() -> Array[ImportantMoment]:
	if _analysis_moments_built:
		return _analysis_moments_cache
	_analysis_moments_built = true
	_analysis_moments_cache.clear()
	var d: Dictionary = load_analysis()
	var raw: Variant = d.get("impact_drops", [])
	if not raw is Array:
		return _analysis_moments_cache
	var raw_moments: Array = raw as Array
	for item in raw_moments:
		var t: float = -1.0
		var strength: float = 1.0
		if item is Dictionary:
			var row: Dictionary = item as Dictionary
			t = float(row.get("time", -1.0))
			strength = clampf(float(row.get("score", row.get("energy", 1.0))), 0.7, 1.0)
		elif typeof(item) == TYPE_FLOAT or typeof(item) == TYPE_INT:
			t = float(item)
		if t < 0.0:
			continue
		var m := ImportantMoment.new()
		m.time = t
		m.duration = 1.5
		m.intensity = strength
		m.label = "AUTO DROP"
		m.triggers_drop_surge = true
		_analysis_moments_cache.append(m)
	return _analysis_moments_cache

func get_effective_important_moments() -> Array[ImportantMoment]:
	var out: Array[ImportantMoment] = []
	for auto_moment in _get_analysis_moments():
		var overridden: bool = false
		for manual_moment in important_moments:
			if manual_moment != null and auto_moment.start_time() < manual_moment.end_time() and manual_moment.start_time() < auto_moment.end_time():
				overridden = true
				break
		if not overridden:
			out.append(auto_moment)
	for manual_moment in important_moments:
		if manual_moment != null:
			out.append(manual_moment)
	out.sort_custom(func(a: ImportantMoment, b: ImportantMoment) -> bool: return a.time < b.time)
	return out

## ------------------------------------------------------------------
## Section / moment queries
## ------------------------------------------------------------------

func get_section_at(song_pos: float) -> MusicSection:
	for s in get_effective_sections():
		if s.contains_time(song_pos):
			return s
	return null

func get_sorted_sections() -> Array[MusicSection]:
	return get_effective_sections()

func get_section_index_at(song_pos: float) -> int:
	var sorted: Array[MusicSection] = get_sorted_sections()
	for i in sorted.size():
		if sorted[i].contains_time(song_pos):
			return i
	return -1

func get_section_progress_at(song_pos: float) -> float:
	var sec: MusicSection = get_section_at(song_pos)
	if sec != null:
		return sec.progress_at(song_pos)
	return 0.0

func is_in_important_moment(song_pos: float) -> bool:
	for m in get_effective_important_moments():
		if m.contains(song_pos):
			return true
	return false

func get_important_moment_at(song_pos: float) -> ImportantMoment:
	for m in get_effective_important_moments():
		if m.contains(song_pos):
			return m
	return null

func intensity_at(song_pos: float) -> float:
	var sec: MusicSection = get_section_at(song_pos)
	var base: float = 0.45
	if sec != null:
		base = sec.intensity
	if has_analysis():
		# Analysis energy nudges the authored section without replacing its intent.
		base = maxf(base, get_analysis_energy_at(song_pos) * 0.78)
	var imp: ImportantMoment = get_important_moment_at(song_pos)
	if imp != null:
		base = maxf(base, imp.intensity)
	return clampf(base * global_intensity_mult, 0.0, 1.0)

func importance_at(song_pos: float) -> float:
	var sec: MusicSection = get_section_at(song_pos)
	var value: float = 0.0
	if sec != null:
		value = sec.importance
	if has_analysis():
		value = maxf(value, get_analysis_importance_at(song_pos) * 0.95)
	if get_important_moment_at(song_pos) != null:
		value = 1.0
	return clampf(value, 0.0, 1.0)

## Validate profile for editor warnings.
func validate() -> Array[String]:
	var errs: Array[String] = []
	if bpm < 40.0 or bpm > 240.0:
		errs.append("BPM out of range (40..240).")
	if beats_per_bar < 1:
		errs.append("beats_per_bar must be >= 1.")
	if sections.is_empty() and analysis_json_path == "":
		errs.append("No sections and no analysis JSON — song will use neutral stage mapping.")
	var seen: Array[MusicSection] = get_sorted_sections()
	for i in seen.size():
		if not seen[i].is_valid():
			errs.append("Section %d (%s) invalid." % [i, seen[i].get_type_name()])
	return errs
