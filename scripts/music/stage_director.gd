extends Node
class_name StageDirector
## Builds and continuously alters procedural track content based on musical structure.
## Keeps pooling/recycling philosophy: preallocated rings/pillars are teleported,
## never queue_free'd. Deterministic from song seed + bar/phrase index.

signal pattern_changed(new_pattern: int, bar: int)
signal section_stage_changed(section: MusicSection)

@export var fighter_path: NodePath = NodePath("../Fighter")
@export var music_director_path: NodePath = NodePath("../MusicDirector")
@export var song_profile: SongProfile = null
@export var stage_theme: StageTheme = null

## Tuning — all exposed, no magic numbers buried.
@export_category("Musical Chunks")
@export_range(1, 32, 1) var bars_per_pattern: int = 4 ## how often we may switch pattern (phrase = 4 bars)
@export_range(0.5, 8.0, 0.5) var beats_per_ring_stream: float = 2.0
@export_range(0.5, 8.0, 0.5) var beats_per_ring_dense: float = 1.0
@export_range(0.5, 8.0, 0.5) var beats_per_ring_sparse: float = 4.0
@export_range(0.5, 8.0, 0.5) var beats_per_pillar: float = 2.5
@export_category("Fallback")
@export var fallback_seed: int = 1337
@export var fallback_tile_count: int = 6

var fighter: FighterJet = null
var music_director: MusicDirector = null
var _rng := RandomNumberGenerator.new()
var _current_pattern: int = StagePattern.Type.OPEN_FLIGHT
var _next_pattern_bar: int = 0
var _last_section_index: int = -999
var _bar_counter: int = 0
var _base_seed: int = 1337
var _pattern_history: Array[int] = []

## Accessors for debug HUD.
var current_pattern: int:
	get: return _current_pattern
var current_stage_theme: StageTheme:
	get: return stage_theme if stage_theme != null else _fallback_theme
var seed_used: int:
	get: return _base_seed

var _fallback_theme: StageTheme = null

func _ready() -> void:
	_resolve_refs()
	_fallback_theme = StageTheme.make_fallback()
	_rebuild_rng()
	# Connect to music director signals for chunk decisions.
	if music_director != null:
		if not music_director.bar.is_connected(_on_bar):
			music_director.bar.connect(_on_bar)
		if not music_director.section_started.is_connected(_on_section_started):
			music_director.section_started.connect(_on_section_started)
		if not music_director.section_ended.is_connected(_on_section_ended):
			music_director.section_ended.connect(_on_section_ended)
		if not music_director.phrase.is_connected(_on_phrase):
			music_director.phrase.connect(_on_phrase)
	set_process(false) # we are signal-driven + polled by Main during recycle

func _resolve_refs() -> void:
	if fighter_path != NodePath(""):
		fighter = get_node_or_null(fighter_path) as FighterJet
	if fighter == null:
		var p: Node = get_parent()
		if p != null:
			fighter = p.get_node_or_null("Fighter") as FighterJet
	if music_director_path != NodePath(""):
		music_director = get_node_or_null(music_director_path) as MusicDirector
	if music_director == null:
		var p2: Node = get_parent()
		if p2 != null:
			music_director = p2.get_node_or_null("MusicDirector") as MusicDirector
	# Song/profile may be set externally after ready; Main wires them.
	if song_profile == null and music_director != null:
		song_profile = music_director.song_profile
	if stage_theme == null and song_profile != null and song_profile.stage_theme != null:
		stage_theme = song_profile.stage_theme as StageTheme

func is_active() -> bool:
	return song_profile != null and music_director != null and not music_director.is_fallback()

func get_effective_theme() -> StageTheme:
	if stage_theme != null:
		return stage_theme
	if song_profile != null and song_profile.stage_theme != null:
		return song_profile.stage_theme as StageTheme
	return _fallback_theme

func get_effective_profile() -> SongProfile:
	if song_profile != null:
		return song_profile
	if music_director != null:
		return music_director.song_profile
	return null

## Rebuild deterministic RNG from profile seed + theme.
func _rebuild_rng() -> void:
	var prof: SongProfile = get_effective_profile()
	var theme: StageTheme = get_effective_theme()
	var seed_a: int = fallback_seed
	if prof != null:
		seed_a = prof.seed
	var seed_b: int = 0
	if theme != null:
		# Hash theme id into int.
		seed_b = hash(theme.theme_id) & 0x7fffffff
	_base_seed = seed_a ^ (seed_b * 16777619)
	_rng.seed = _base_seed
	_current_pattern = StagePattern.Type.OPEN_FLIGHT
	_next_pattern_bar = 0
	_last_section_index = -999
	_bar_counter = 0
	_pattern_history.clear()

## Public: change song at runtime (seek-safe, deterministic).
func set_song(profile: SongProfile, theme_override: StageTheme = null) -> void:
	song_profile = profile
	if theme_override != null:
		stage_theme = theme_override
	elif profile != null and profile.stage_theme != null:
		stage_theme = profile.stage_theme as StageTheme
	_rebuild_rng()
	# If we are mid-song, align pattern to current bar immediately.
	if music_director != null:
		_bar_counter = music_director.current_bar
		_decide_pattern_for_bar(_bar_counter, true)

## Called when Main recycles a ring that went behind the fighter.
## Returns a new global_position for that ring, deterministic for given
## fighter_z and musical state. Uses seeded per-bar RNG so same bar => same slot
## even if called out of order (seek).
func get_next_ring_position(fighter_z: float, ring_index: int, fallback_spacing: float = 55.0) -> Vector3:
	var prof: SongProfile = get_effective_profile()
	var theme: StageTheme = get_effective_theme()
	if not is_active() or prof == null or fighter == null:
		# Fallback: legacy random lane slot (still deterministic via _rng sequential).
		var lane_pick: float = float(_rng.randi_range(0, 2) - 1)
		var jitter_x: float = _rng.randf_range(-3.0, 3.0)
		var y: float = _rng.randf_range(6.0, 30.0)
		var z_jit: float = _rng.randf_range(-8.0, 8.0)
		var z: float = fighter_z - fallback_spacing * 14.0 + z_jit
		if fighter != null:
			return Vector3(lane_pick * fighter.lane_spacing + jitter_x, y, z)
		return Vector3(jitter_x, y, z)

	# Active: derive bar from fighter progress + music bar.
	# Use music bar directly for determinism; fighter_z maps to upcoming bars.
	var bar: int = music_director.current_bar if music_director != null else 0
	# Advance pattern if we have crossed a chunk boundary (handled via signals, but also check here for safety).
	if bar >= _next_pattern_bar:
		_decide_pattern_for_bar(bar, false)

	var sec: MusicSection = null
	if music_director != null:
		sec = music_director.current_section
	elif prof != null:
		sec = prof.get_section_at(music_director.song_position if music_director != null else 0.0)

	var intensity: float = 0.5
	var density_mult: float = 1.0
	if sec != null:
		intensity = sec.intensity
		density_mult = sec.density_mult
	# Hype lifts density a bit.
	var hype: float = music_director.hype if music_director != null else 0.0
	density_mult *= 1.0 + hype * 0.35

	var spacing: float = _ring_spacing_for_pattern(_current_pattern, prof, intensity, density_mult)
	var z_base: float = _ring_z_ahead(fighter_z, spacing, prof, ring_index)
	# Per-bar deterministic RNG: seed = base ^ bar ^ ring_index
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = _base_seed ^ (bar * 2654435761) ^ (ring_index * 97531) ^ (int(prof.seed) & 0xffff)

	var pos: Vector3 = _position_for_pattern(_current_pattern, local_rng, bar, fighter_z, theme, sec, intensity, z_base)
	return pos

## Ring spacing musical: meters_per_beat * beats_per_ring / density-ish
func _ring_spacing_for_pattern(pattern: int, prof: SongProfile, intensity: float, density_mult: float) -> float:
	var spb: float = 60.0 / maxf(prof.bpm, 1.0) if prof != null else 0.46875
	var exp_speed: float = 45.0
	if fighter != null:
		exp_speed = fighter.cruise_speed
	if prof != null:
		exp_speed *= prof.global_speed_mult
		if prof.get_section_at(music_director.song_position if music_director != null else 0.0) != null:
			var cur: MusicSection = prof.get_section_at(music_director.song_position)
			exp_speed *= cur.speed_mult
	var mpb: float = exp_speed * spb
	var beats: float
	match pattern:
		StagePattern.Type.OPEN_FLIGHT, StagePattern.Type.BREAKDOWN_OPEN, StagePattern.Type.WIDE_CORRIDOR:
			beats = beats_per_ring_sparse
		StagePattern.Type.CHAOS, StagePattern.Type.DROP_RUSH, StagePattern.Type.RING_STREAM:
			beats = beats_per_ring_dense
		_:
			beats = beats_per_ring_stream
	var theme: StageTheme = get_effective_theme()
	var raw: float = mpb * beats
	# Clamp to theme spacing bounds, modulated by intensity density.
	var min_s: float = theme.ring_spacing_min if theme != null else 36.0
	var max_s: float = theme.ring_spacing_max if theme != null else 72.0
	raw = clampf(raw / maxf(density_mult, 0.1), min_s, max_s)
	# Intensity tightens spacing up to 0.8x at max hype.
	raw *= lerpf(1.0, 0.75, clampf(intensity * density_mult * 0.6, 0.0, 1.0))
	return maxf(raw, 18.0)

func _ring_z_ahead(fighter_z: float, spacing: float, prof: SongProfile, ring_index: int) -> float:
	# Place ahead by spacing * ring_count-ish spread; add tiny jitter.
	var ring_count: int = 14
	# Use ring_index to stagger so not all rings share same Z.
	return fighter_z - spacing * float(ring_count) - float(ring_index % 3) * spacing * 0.15

func _position_for_pattern(pattern: int, rng: RandomNumberGenerator, bar: int, fighter_z: float, theme: StageTheme, sec: MusicSection, intensity: float, z_base: float) -> Vector3:
	var lane_spacing: float = 40.0
	if fighter != null:
		lane_spacing = fighter.lane_spacing
	var lane_pick: int = rng.randi_range(-1, 1)
	var z_jitter: float = rng.randf_range(-spacing_jitter(spacing), spacing_jitter(spacing))
	var z: float = z_base + z_jitter
	var y_base: float = 10.0
	var x: float = float(lane_pick) * lane_spacing + rng.randf_range(-2.5, 2.5)

	match pattern:
		StagePattern.Type.OPEN_FLIGHT:
			# Sparse, long sightlines — few rings, low Y, centered.
			lane_pick = 0 if rng.randf() < 0.7 else rng.randi_range(-1, 1)
			x = float(lane_pick) * lane_spacing + rng.randf_range(-4.0, 4.0)
			y_base = rng.randf_range(8.0, 16.0)
		StagePattern.Type.RING_STREAM:
			# Straight line, moderate Y
			# Keep same lane for 3-4 rings to make a stream.
			lane_pick = (bar / 2) % 3 - 1
			x = float(lane_pick) * lane_spacing + rng.randf_range(-2.0, 2.0)
			y_base = rng.randf_range(9.0, 18.0) + sin(float(bar) * 0.7) * 3.0
		StagePattern.Type.RING_WAVE:
			x = float(lane_pick) * lane_spacing
			var wave: float = sin(float(bar) * 1.2 + float(rng.randi() % 10)) * 6.0 + rng.randf_range(-2.0, 2.0)
			y_base = clampf(12.0 + wave, 6.0, 28.0)
		StagePattern.Type.RING_SLALOM:
			# Alternating lanes each bar — encourages barrel-like slalom.
			lane_pick = 1 if (bar % 2 == 0) else -1
			if rng.randf() < 0.15:
				lane_pick = 0
			x = float(lane_pick) * lane_spacing + rng.randf_range(-1.5, 1.5)
			y_base = rng.randf_range(10.0, 20.0)
		StagePattern.Type.VERTICAL_WAVE:
			x = float(lane_pick) * lane_spacing + rng.randf_range(-2.0, 2.0)
			y_base = 10.0 + sin(float(bar) * 2.1) * 9.0 + rng.randf_range(-2.0, 2.0)
			y_base = clampf(y_base, 5.0, 28.0)
		StagePattern.Type.PILLAR_SLALOM, StagePattern.Type.TIGHT_CORRIDOR:
			# Rings stay centered, pillars do the slalom — position still lane-based.
			x = float(lane_pick) * lane_spacing + rng.randf_range(-2.0, 2.0)
			y_base = rng.randf_range(9.0, 16.0)
		StagePattern.Type.LOW_ALTITUDE_RUN:
			x = float(lane_pick) * lane_spacing
			y_base = rng.randf_range(5.0, 10.0)
		StagePattern.Type.HIGH_ALTITUDE_RUN:
			x = float(lane_pick) * lane_spacing
			y_base = rng.randf_range(20.0, 30.0)
		StagePattern.Type.LANE_WEAVE:
			# Frequency-modulated X offset
			x = sin(float(bar) * 0.9) * lane_spacing * 0.35 + float(lane_pick) * lane_spacing * 0.15
			x += rng.randf_range(-2.0, 2.0)
			y_base = rng.randf_range(9.0, 22.0)
		StagePattern.Type.DROP_RUSH:
			# Fast straight rush — center lane, moderate height, tight spacing already.
			x = rng.randf_range(-4.0, 4.0)
			y_base = rng.randf_range(10.0, 16.0)
		StagePattern.Type.SOLO_FLOW:
			# Flowing lines encouraging banking — sine slalom with rising Y
			var t: float = float(bar) * 0.8
			x = sin(t) * 18.0 + sin(t * 1.9) * 8.0
			x = clampf(x, -lane_spacing * 1.1, lane_spacing * 1.1)
			y_base = 12.0 + sin(t * 1.3) * 5.0 + rng.randf_range(-1.5, 1.5)
		StagePattern.Type.CRESCENDO_CLIMB:
			y_base = lerpf(8.0, 24.0, clampf(float(bar % 8) / 8.0, 0.0, 1.0)) + rng.randf_range(-1.5, 1.5)
			x = float(lane_pick) * lane_spacing * 0.7 + rng.randf_range(-3.0, 3.0)
		StagePattern.Type.BREAKDOWN_OPEN:
			# Very sparse, high, wide
			if rng.randf() < 0.5:
				return Vector3(x, y_base, z) # caller may hide this ring? For now place but far.
			y_base = rng.randf_range(14.0, 26.0)
			x = float(lane_pick) * lane_spacing * 0.5
		StagePattern.Type.CHAOS:
			x = rng.randf_range(-lane_spacing, lane_spacing)
			y_base = rng.randf_range(6.0, 28.0)
		StagePattern.Type.CUSTOM, _:
			y_base = rng.randf_range(8.0, 24.0)

	y_base = clampf(y_base, 4.5, 30.0)
	return Vector3(x, y_base, z)

func spacing_jitter(spacing: float) -> float:
	return clampf(spacing * 0.12, 2.0, 7.0)

## Pillar counterpart: called by Main when recycling a pillar.
func get_next_pillar_position(fighter_z: float, pillar_index: int, is_near: bool) -> Vector3:
	var prof: SongProfile = get_effective_profile()
	var theme: StageTheme = get_effective_theme()
	if not is_active() or prof == null:
		var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
		var dist: float = _rng.randf_range(48.0, 70.0) if _rng.randf() < 0.35 else _rng.randf_range(70.0, 140.0)
		var z: float = fighter_z - 1000.0 * (0.1 + _rng.randf() * 0.9)
		return Vector3(side * dist, 0.0, z)

	var bar: int = music_director.current_bar if music_director != null else 0
	var sec: MusicSection = music_director.current_section if music_director != null else null
	var pattern: int = _current_pattern

	# Per-bar RNG for pillars.
	var rng := RandomNumberGenerator.new()
	rng.seed = _base_seed ^ (bar * 9721) ^ (pillar_index * 131071) ^ 0x9E3779B9

	var side2: float = -1.0 if rng.randf() < 0.5 else 1.0
	var dist2: float
	match pattern:
		StagePattern.Type.PILLAR_SLALOM:
			side2 = 1.0 if (bar % 2 == 0) else -1.0
			dist2 = 52.0 + rng.randf_range(-4.0, 8.0)
		StagePattern.Type.TIGHT_CORRIDOR:
			dist2 = rng.randf_range(44.0, 58.0)
		StagePattern.Type.WIDE_CORRIDOR, StagePattern.Type.BREAKDOWN_OPEN, StagePattern.Type.OPEN_FLIGHT:
			dist2 = rng.randf_range(80.0, 140.0)
		StagePattern.Type.DROP_RUSH:
			dist2 = rng.randf_range(48.0, 62.0)
		StagePattern.Type.SOLO_FLOW:
			# Pillars hug lanes for near-miss flow.
			dist2 = rng.randf_range(46.0, 66.0)
		StagePattern.Type.CHAOS:
			dist2 = rng.randf_range(42.0, 120.0)
		_:
			dist2 = rng.randf_range(48.0, 70.0) if rng.randf() < 0.35 else rng.randf_range(70.0, 140.0)

	var spb: float = 60.0 / maxf(prof.bpm, 1.0)
	var mpb: float = (fighter.cruise_speed if fighter != null else 45.0) * spb
	var spacing: float = mpb * beats_per_pillar
	spacing = clampf(spacing, 22.0, 90.0)
	var z2: float = fighter_z - spacing * 8.0 - rng.randf_range(0.0, spacing * 2.0)
	return Vector3(side2 * dist2, 0.0, z2)

## ------------------------------------------------------------------
## Pattern selection (deterministic weighted)
## ------------------------------------------------------------------

func _decide_pattern_for_bar(bar: int, force: bool) -> void:
	if bar < _next_pattern_bar and not force:
		return
	var prof: SongProfile = get_effective_profile()
	var theme: StageTheme = get_effective_theme()
	if prof == null or theme == null:
		return
	var sec: MusicSection = null
	if music_director != null:
		sec = music_director.current_section
	var next: int = _pick_pattern_weighted(bar, sec, theme, prof)
	if next != _current_pattern or force:
		_current_pattern = next
		pattern_changed.emit(next, bar)
		_pattern_history.append(next)
		if _pattern_history.size() > 16:
			_pattern_history.pop_front()
	_next_pattern_bar = bar + bars_per_pattern

func _pick_pattern_weighted(bar: int, sec: MusicSection, theme: StageTheme, prof: SongProfile) -> int:
	# Build weighted list from theme allow-list + section biases.
	var candidates: Array[int] = []
	var weights: Array[float] = []
	var allowed: Array[int] = theme.allowed_patterns if not theme.allowed_patterns.is_empty() else StagePattern.all_types()

	# Section-biased base weights.
	var section_bias: Dictionary = _bias_for_section(sec)
	for p in allowed:
		var w: float = theme.weight_for_pattern(p)
		if section_bias.has(p):
			w *= float(section_bias[p])
		# Avoid repeating same pattern twice in a row when alternative exists (soft).
		if _pattern_history.size() > 0 and _pattern_history[_pattern_history.size() - 1] == p:
			w *= 0.35
		# Important sections push DROP_RUSH/CHAOS/SOLO_FLOW more.
		if sec != null and sec.importance > 0.75:
			if p == StagePattern.Type.DROP_RUSH and (sec.section_type == MusicSection.Type.DROP or sec.section_type == MusicSection.Type.CLIMAX):
				w *= 3.0
			if p == StagePattern.Type.SOLO_FLOW and (sec.section_type == MusicSection.Type.SOLO or sec.section_type == MusicSection.Type.GUITAR_SOLO):
				w *= 3.0
			if p == StagePattern.Type.CHAOS and sec.section_type == MusicSection.Type.PEAK:
				w *= 2.5
		if w > 0.01:
			candidates.append(p)
			weights.append(w)

	if candidates.is_empty():
		return StagePattern.Type.OPEN_FLIGHT

	# Deterministic weighted pick via per-bar RNG.
	var rng := RandomNumberGenerator.new()
	var sec_hash: int = 0
	if sec != null:
		sec_hash = int(sec.section_type) * 1009 + int(sec.start_time)
	rng.seed = _base_seed ^ (bar * 15485863) ^ sec_hash ^ 0x517cc1b727220a95
	var total: float = 0.0
	for w in weights:
		total += w
	var r: float = rng.randf() * total
	var acc: float = 0.0
	for i in candidates.size():
		acc += weights[i]
		if r <= acc:
			return candidates[i]
	return candidates[0]

func _bias_for_section(sec: MusicSection) -> Dictionary:
	if sec == null:
		return {}
	match sec.section_type:
		MusicSection.Type.INTRO:
			return {StagePattern.Type.OPEN_FLIGHT: 2.5, StagePattern.Type.WIDE_CORRIDOR: 1.8, StagePattern.Type.RING_STREAM: 0.6}
		MusicSection.Type.VERSE:
			return {StagePattern.Type.RING_STREAM: 1.8, StagePattern.Type.RING_SLALOM: 1.6, StagePattern.Type.PILLAR_SLALOM: 1.2}
		MusicSection.Type.BUILD:
			return {StagePattern.Type.RING_WAVE: 1.8, StagePattern.Type.CRESCENDO_CLIMB: 2.0, StagePattern.Type.VERTICAL_WAVE: 1.5, StagePattern.Type.LANE_WEAVE: 1.2}
		MusicSection.Type.CHORUS:
			return {StagePattern.Type.RING_WAVE: 1.6, StagePattern.Type.PILLAR_SLALOM: 1.4, StagePattern.Type.TIGHT_CORRIDOR: 1.3, StagePattern.Type.LANE_WEAVE: 1.2}
		MusicSection.Type.DROP:
			return {StagePattern.Type.DROP_RUSH: 3.5, StagePattern.Type.CHAOS: 2.0, StagePattern.Type.TIGHT_CORRIDOR: 1.4}
		MusicSection.Type.SOLO, MusicSection.Type.GUITAR_SOLO:
			return {StagePattern.Type.SOLO_FLOW: 3.0, StagePattern.Type.LANE_WEAVE: 2.0, StagePattern.Type.RING_WAVE: 1.4}
		MusicSection.Type.BRIDGE:
			return {StagePattern.Type.LANE_WEAVE: 2.2, StagePattern.Type.HIGH_ALTITUDE_RUN: 1.6, StagePattern.Type.VERTICAL_WAVE: 1.5}
		MusicSection.Type.BREAKDOWN:
			return {StagePattern.Type.BREAKDOWN_OPEN: 2.8, StagePattern.Type.WIDE_CORRIDOR: 2.0, StagePattern.Type.OPEN_FLIGHT: 1.8}
		MusicSection.Type.CRESCENDO:
			return {StagePattern.Type.CRESCENDO_CLIMB: 2.6, StagePattern.Type.RING_WAVE: 1.5, StagePattern.Type.VERTICAL_WAVE: 1.4}
		MusicSection.Type.CLIMAX, MusicSection.Type.PEAK:
			return {StagePattern.Type.CHAOS: 2.4, StagePattern.Type.DROP_RUSH: 2.6, StagePattern.Type.TIGHT_CORRIDOR: 1.5}
		MusicSection.Type.OUTRO:
			return {StagePattern.Type.OPEN_FLIGHT: 1.9, StagePattern.Type.WIDE_CORRIDOR: 1.6}
		_:
			return {}

## ------------------------------------------------------------------
## Signal handlers — keep pattern bar-aligned to musical structure
## ------------------------------------------------------------------

func _on_bar(bar_idx: int, _pos: float) -> void:
	_bar_counter = bar_idx
	_decide_pattern_for_bar(bar_idx, false)

func _on_phrase(phrase_idx: int, _pos: float) -> void:
	# Allow phrase-level transitions (bigger shifts).
	if phrase_idx % 2 == 0:
		_decide_pattern_for_bar(_bar_counter, false)

func _on_section_started(sec: MusicSection, idx: int) -> void:
	if sec == null:
		return
	_last_section_index = idx
	section_stage_changed.emit(sec)
	# Force pattern re-pick on section entry (choreography shift).
	var bar: int = music_director.current_bar if music_director != null else 0
	if sec.pattern_override >= 0:
		_current_pattern = sec.pattern_override
		pattern_changed.emit(_current_pattern, bar)
		_next_pattern_bar = bar + bars_per_pattern
	else:
		_decide_pattern_for_bar(bar, true)

func _on_section_ended(_sec: MusicSection, _idx: int) -> void:
	pass

## Public helpers for HUD / debugging.

func get_current_pattern_name() -> String:
	return StagePattern.display_name(_current_pattern)

func get_bar() -> int:
	return _bar_counter

func get_meters_per_beat() -> float:
	var prof: SongProfile = get_effective_profile()
	if prof == null:
		return 20.0
	var spb: float = 60.0 / maxf(prof.bpm, 1.0)
	var spd: float = fighter.cruise_speed if fighter != null else 45.0
	return spd * spb
