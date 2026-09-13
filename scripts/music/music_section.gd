extends Resource
class_name MusicSection
## Data describing a single musical section of a song.
## Used inside SongProfile.sections. Manual markers override auto-detected ones.

enum Type {
	INTRO,
	VERSE,
	BUILD,
	CHORUS,
	DROP,
	SOLO,
	GUITAR_SOLO,
	BRIDGE,
	BREAKDOWN,
	CRESCENDO,
	CLIMAX,
	OUTRO,
	PEAK,
	CUSTOM,
}

@export var section_type: int = Type.VERSE
@export var custom_type_name: String = "" ## only when section_type == CUSTOM

## Timing in seconds from song start (inclusive start, exclusive end).
@export_range(0.0, 3600.0, 0.05) var start_time: float = 0.0
@export_range(0.0, 3600.0, 0.05) var end_time: float = 8.0

## Musical weight.
@export_range(0.0, 1.0, 0.01) var intensity: float = 0.5
@export_range(0.0, 1.0, 0.01) var importance: float = 0.0 ## 1 = drop/solo peak -> triggers hype spectacle
@export_range(0.1, 4.0, 0.05) var density_mult: float = 1.0 ## multiplies ring/pillar density
@export_range(0.5, 2.0, 0.01) var speed_mult: float = 1.0 ## multiplies music-driven cruise

## Optional overrides for this section only.
@export var pattern_override: int = -1 ## -1 = none, else StagePattern.Type
@export var stage_theme_override: Resource = null ## StageTheme or null

## Placeholder for future analysis-driven fields: if set, this section came from analyzer.
@export var auto_generated: bool = false


func get_type_name() -> String:
	if section_type == Type.CUSTOM and custom_type_name != "":
		return custom_type_name
	match section_type:
		Type.INTRO: return "INTRO"
		Type.VERSE: return "VERSE"
		Type.BUILD: return "BUILD"
		Type.CHORUS: return "CHORUS"
		Type.DROP: return "DROP"
		Type.SOLO: return "SOLO"
		Type.GUITAR_SOLO: return "GUITAR_SOLO"
		Type.BRIDGE: return "BRIDGE"
		Type.BREAKDOWN: return "BREAKDOWN"
		Type.CRESCENDO: return "CRESCENDO"
		Type.CLIMAX: return "CLIMAX"
		Type.OUTRO: return "OUTRO"
		Type.PEAK: return "PEAK"
		Type.CUSTOM: return "CUSTOM"
		_: return "UNKNOWN"

## Duration helper.
func duration() -> float:
	return maxf(0.0, end_time - start_time)

## Progress inside this section for a given song position (0..1).
func progress_at(song_pos: float) -> float:
	var d: float = duration()
	if d <= 0.001:
		return 0.0
	return clampf((song_pos - start_time) / d, 0.0, 1.0)

## Whether a given time is inside this section (end exclusive).
func contains_time(t: float) -> bool:
	return t >= start_time and t < end_time

## Validate data (called by SongProfile).
func is_valid() -> bool:
	return end_time > start_time + 0.01 and intensity >= 0.0 and intensity <= 1.0

static func type_from_string(s: String) -> int:
	match s.to_upper():
		"INTRO": return Type.INTRO
		"VERSE": return Type.VERSE
		"BUILD": return Type.BUILD
		"CHORUS": return Type.CHORUS
		"DROP": return Type.DROP
		"SOLO": return Type.SOLO
		"GUITAR_SOLO", "GUITAR-SOLO", "GUITAR SOLO": return Type.GUITAR_SOLO
		"BRIDGE": return Type.BRIDGE
		"BREAKDOWN": return Type.BREAKDOWN
		"CRESCENDO": return Type.CRESCENDO
		"CLIMAX": return Type.CLIMAX
		"OUTRO": return Type.OUTRO
		"PEAK": return Type.PEAK
		"CUSTOM": return Type.CUSTOM
		_: return Type.CUSTOM
