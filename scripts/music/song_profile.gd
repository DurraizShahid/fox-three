extends Resource
class_name SongProfile
## Reusable Resource describing a single song + its stage/environment mapping.
## See docs/music-system.md for authoring workflow.

@export var song_id: String = "untitled"
@export var song_name: String = "Untitled"
@export var stream: AudioStream = null

## Musical clock.
@export_range(40.0, 240.0, 0.1) var bpm: float = 128.0
@export_range(-5.0, 5.0, 0.01) var beat_offset: float = 0.0 ## seconds, shifts downbeats
@export_range(1, 7, 1) var beats_per_bar: int = 4 ## time signature numerator
@export_range(1, 4, 1) var beats_per_phrase: int = 16 ## e.g. 4 bars = 16 beats
@export var seed: int = 1337 ## deterministic stage seed for this song
@export_range(0.0, 1.0, 0.05) var difficulty: float = 0.5
@export_range(0.5, 2.0, 0.05) var global_speed_mult: float = 1.0
@export_range(0.5, 2.0, 0.05) var global_intensity_mult: float = 1.0

## Stage mapping.
@export var stage_theme: Resource = null ## StageTheme

## Section / moment definitions. Manual entries override analyzer guesses.
@export var sections: Array[MusicSection] = []
@export var important_moments: Array[ImportantMoment] = []

## Optional sidecar JSON produced by tools/music_analysis/analyze_song.py.
@export_file("*.json") var analysis_json_path: String = ""
## Parsed cache of that JSON (not serialized). Loaded on demand.
var _analysis_cache: Dictionary = {}
var _analysis_loaded: bool = false

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
## Section queries
## ------------------------------------------------------------------

## Returns the MusicSection containing song_pos, or null if none / before first.
func get_section_at(song_pos: float) -> MusicSection:
	for s in sections:
		if s != null and s.contains_time(song_pos):
			return s
	return null

## Sorted copy of sections by start_time (not mutating original order is nicer for authoring).
func get_sorted_sections() -> Array[MusicSection]:
	var arr: Array[MusicSection] = []
	for s in sections:
		if s != null:
			arr.append(s)
	arr.sort_custom(func(a: MusicSection, b: MusicSection) -> bool: return a.start_time < b.start_time)
	return arr

## Index of the section containing song_pos in sorted order, -1 if none.
func get_section_index_at(song_pos: float) -> int:
	var sorted: Array[MusicSection] = get_sorted_sections()
	for i in sorted.size():
		if sorted[i].contains_time(song_pos):
			return i
	return -1

## Progress 0..1 within current section.
func get_section_progress_at(song_pos: float) -> float:
	var sec: MusicSection = get_section_at(song_pos)
	if sec == null:
		return 0.0
	return sec.progress_at(song_pos)

## Whether song_pos is inside any important moment.
func is_in_important_moment(song_pos: float) -> bool:
	for m in important_moments:
		if m != null and m.contains(song_pos):
			return true
	return false

## The important moment containing song_pos, or null.
func get_important_moment_at(song_pos: float) -> ImportantMoment:
	for m in important_moments:
		if m != null and m.contains(song_pos):
			return m
	return null

## Current intensity/intensity helpers — section intensity blended with importance.
func intensity_at(song_pos: float) -> float:
	var sec: MusicSection = get_section_at(song_pos)
	var base: float = 0.45
	if sec != null:
		base = sec.intensity
	var imp: ImportantMoment = get_important_moment_at(song_pos)
	if imp != null:
		base = maxf(base, imp.intensity)
	return clampf(base * global_intensity_mult, 0.0, 1.0)

func importance_at(song_pos: float) -> float:
	var sec: MusicSection = get_section_at(song_pos)
	var imp_val: float = 0.0
	if sec != null:
		imp_val = sec.importance
	var mom: ImportantMoment = get_important_moment_at(song_pos)
	if mom != null:
		imp_val = maxf(imp_val, 1.0) # moments force importance 1
	return clampf(imp_val, 0.0, 1.0)

## Validate profile for editor warnings.
func validate() -> Array[String]:
	var errs: Array[String] = []
	if bpm < 40.0 or bpm > 240.0:
		errs.append("BPM out of range (40..240).")
	if beats_per_bar < 1:
		errs.append("beats_per_bar must be >= 1.")
	if sections.is_empty() and analysis_json_path == "":
		# Not an error — fallback mode is allowed, but warn.
		errs.append("No sections and no analysis JSON — song will use fallback flat stage.")
	var seen: Array[MusicSection] = get_sorted_sections()
	for i in seen.size():
		if not seen[i].is_valid():
			errs.append("Section %d (%s) invalid." % [i, seen[i].get_type_name()])
		if i > 0 and seen[i].start_time < seen[i - 1].end_time - 0.01:
			errs.append("Sections overlap: %d and %d." % [i - 1, i])
	return errs

## ------------------------------------------------------------------
## Analysis JSON
## ------------------------------------------------------------------

func load_analysis() -> Dictionary:
	if _analysis_loaded:
		return _analysis_cache
	_analysis_loaded = true
	_analysis_cache = {}
	if analysis_json_path == "" or analysis_json_path == null:
		return _analysis_cache
	if not ResourceLoader.exists(analysis_json_path) and not FileAccess.file_exists(analysis_json_path):
		# Try res:// resolution for FileAccess fallback.
		push_warning("[SongProfile] analysis JSON not found: %s" % analysis_json_path)
		return _analysis_cache
	var text: String = ""
	if FileAccess.file_exists(analysis_json_path):
		var f: FileAccess = FileAccess.open(analysis_json_path, FileAccess.READ)
		if f != null:
			text = f.get_as_text()
	elif ResourceLoader.exists(analysis_json_path):
		# For .json inside res:// that isn't imported as text, FileAccess still works via res:// path.
		var f2: FileAccess = FileAccess.open(analysis_json_path, FileAccess.READ)
		if f2 != null:
			text = f2.get_as_text()
	if text == "":
		return _analysis_cache
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_analysis_cache = parsed as Dictionary
	else:
		push_warning("[SongProfile] failed to parse analysis JSON: %s" % analysis_json_path)
	return _analysis_cache

func has_analysis() -> bool:
	var d: Dictionary = load_analysis()
	return not d.is_empty()

## Beat timestamps from analysis (if present) — otherwise empty so MusicDirector synthesizes from BPM.
func get_analysis_beats() -> Array:
	var d: Dictionary = load_analysis()
	if d.has("beats"):
		return d["beats"] as Array
	return []

## Energy curve helpers: returns loudness at song_pos via analysis lerp (or 0.5 fallback).
func get_analysis_energy_at(song_pos: float) -> float:
	var d: Dictionary = load_analysis()
	if not d.has("energy_curve"):
		return 0.5
	var curve: Array = d["energy_curve"] as Array # [{t, v}, ...] or [[t,v], ...]
	if curve.is_empty():
		return 0.5
	# Curve is expected as array of {time, energy} or [time, energy]. Normalize to 0..1.
	# We handle both formats.
	var prev_t: float = 0.0
	var prev_v: float = 0.5
	var first: Variant = curve[0]
	var as_dict: bool = first is Dictionary
	for i in curve.size():
		var t: float
		var v: float
		if as_dict:
			var entry: Dictionary = curve[i] as Dictionary
			t = float(entry.get("time", entry.get("t", 0.0)))
			v = float(entry.get("energy", entry.get("v", 0.5)))
		else:
			var entry2: Array = curve[i] as Array
			if entry2.size() < 2:
				continue
			t = float(entry2[0])
			v = float(entry2[1])
		if song_pos < t:
			if i == 0:
				return clampf(v, 0.0, 1.0)
			var frac: float = (song_pos - prev_t) / maxf(t - prev_t, 0.001)
			return clampf(lerpf(prev_v, v, frac), 0.0, 1.0)
		prev_t = t
		prev_v = v
	return clampf(prev_v, 0.0, 1.0)
