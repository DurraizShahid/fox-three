extends CanvasLayer
class_name MusicDebugOverlay
## Toggleable music debug overlay (F3 to show). Shows song clock, hype, patterns etc.
## Also handles debug seek keys for section jumps when enabled.

@export var music_director_path: NodePath = NodePath("../MusicDirector")
@export var stage_director_path: NodePath = NodePath("../StageDirector")
@export var fighter_path: NodePath = NodePath("../Fighter")
@export var enabled: bool = false ## start visible?
@export var enable_seek_keys: bool = true ## ] [ jump sections

var music_director: MusicDirector = null
var stage_director: StageDirector = null
var fighter: FighterJet = null
var _label: Label = null
var _bg: ColorRect = null

func _ready() -> void:
	layer = 10
	_resolve()
	_build_ui()
	visible = enabled

func _resolve() -> void:
	if music_director_path != NodePath(""):
		music_director = get_node_or_null(music_director_path) as MusicDirector
	if music_director == null:
		music_director = get_parent().get_node_or_null("MusicDirector") as MusicDirector
	if stage_director_path != NodePath(""):
		stage_director = get_node_or_null(stage_director_path) as StageDirector
	if stage_director == null:
		stage_director = get_parent().get_node_or_null("StageDirector") as StageDirector
	if fighter_path != NodePath(""):
		fighter = get_node_or_null(fighter_path) as FighterJet
	if fighter == null:
		fighter = get_parent().get_node_or_null("Fighter") as FighterJet

func _build_ui() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0.62)
	_bg.anchor_left = 1.0
	_bg.anchor_right = 1.0
	_bg.anchor_top = 0.0
	_bg.anchor_bottom = 0.0
	_bg.offset_left = -420.0
	_bg.offset_right = -8.0
	_bg.offset_top = 8.0
	_bg.offset_bottom = 340.0
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_label = Label.new()
	_label.anchor_left = 0.0
	_label.anchor_top = 0.0
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	# Use built-in font; label settings for readability.
	var ls := LabelSettings.new()
	ls.font_size = 13
	ls.font_color = Color(0.9, 0.95, 1.0, 0.95)
	ls.outline_size = 3
	ls.outline_color = Color(0, 0, 0, 0.85)
	_label.label_settings = ls
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.text = "Music debug initializing..."
	_bg.add_child(_label)

func _process(_delta: float) -> void:
	if not visible or _label == null:
		return
	_update_text()

func _update_text() -> void:
	if music_director == null:
		_label.text = "[MusicDebug] No MusicDirector"
		return
	var s: String = ""
	var prof: SongProfile = music_director.song_profile
	var md: MusicDirector = music_director
	var sd: StageDirector = stage_director

	s += "MUSIC DEBUG (F3 toggle)  [ ] prev/next section  R reset sync\n"
	s += "--------------------------------------------------\n"
	if prof != null:
		s += "Song: %s (%s)  BPM %.1f  %d/4  seed %d\n" % [prof.song_name, prof.song_id, prof.bpm, prof.beats_per_bar, prof.seed]
		if prof.stream != null:
			s += " Stream: %s\n" % prof.stream.resource_path if prof.stream.resource_path != "" else " Stream: <loaded>\n"
		else:
			s += " Stream: <none - fallback>\n"
	else:
		s += "Song: <none> (fallback)  BPM %.1f\n" % md.bpm

	s += "Time: %.2f s  Beat %d (phase %.2f)  Bar %d (phase %.2f)  Phrase %d\n" % [
		md.song_position, md.current_beat, md.beat_phase, md.current_bar, md.bar_phase, md.phrase_index
	]
	s += "SPB %.3f  SPBar %.3f\n" % [md.seconds_per_beat, md.seconds_per_bar]
	var sec_name: String = md.current_section.get_type_name() if md.current_section != null else "NONE"
	var imp: String = " (!!)" if md.is_in_important_moment else ""
	s += "Section: %s  idx %d  progress %.2f%s\n" % [sec_name, md.current_section_index, md.section_progress, imp]
	s += "Intensity %.2f  Importance %.2f  Hype %.2f\n" % [md.current_intensity, md.current_importance, md.hype]
	s += "Spectrum low %.2f  mid %.2f  high %.2f  overall %.2f\n" % [md.low_energy, md.mid_energy, md.high_energy, md.overall_energy]

	if fighter != null:
		s += "--- Fighter music ---\n"
		s += " music_speed target %.2f  cur %.2f  surge %.1f  beat %.2f\n" % [
			fighter.music_speed_mult, fighter._music_speed_current, fighter._music_surge, fighter._music_beat_kick
		]
		s += " fwd %.1f m/s  ratio %.2f  hype %.2f  spectrum L/M/H %.2f/%.2f/%.2f\n" % [
			fighter.forward_speed, fighter.speed_ratio, fighter.music_hype, fighter.music_low, fighter.music_mid, fighter.music_high
		]
	if sd != null:
		s += "--- Stage ---\n"
		s += " Pattern %s  bar %d  mpb %.1f m  seed %d\n" % [sd.get_current_pattern_name(), sd.get_bar(), sd.get_meters_per_beat(), sd.seed_used]
		var theme: StageTheme = sd.get_effective_theme()
		if theme != null:
			s += " Theme %s (%s)\n" % [theme.display_name, theme.theme_id]
		s += " Density %.2f  Next bar %d\n" % [
			theme.density_for_intensity(md.current_intensity) if theme != null else 1.0,
			sd._next_pattern_bar
		]
	# Analyzer hint
	if prof != null and prof.analysis_json_path != "":
		s += " Analysis: %s %s\n" % [prof.analysis_json_path, "✓" if prof.has_analysis() else "✗ missing"]
	s += "\nF3 hud  +/- fine seek  ,/. bar seek\n"
	_label.text = s

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F3:
				enabled = not enabled
				visible = enabled
				get_viewport().set_input_as_handled()
			KEY_BRACKETLEFT:
				if enable_seek_keys and enabled and music_director != null:
					_seek_prev_section()
					get_viewport().set_input_as_handled()
			KEY_BRACKETRIGHT:
				if enable_seek_keys and enabled and music_director != null:
					_seek_next_section()
					get_viewport().set_input_as_handled()
			KEY_COMMA:
				if enable_seek_keys and enabled and music_director != null:
					music_director.seek_to(maxf(0.0, music_director.song_position - music_director.seconds_per_bar))
					get_viewport().set_input_as_handled()
			KEY_PERIOD:
				if enable_seek_keys and enabled and music_director != null:
					music_director.seek_to(music_director.song_position + music_director.seconds_per_bar)
					get_viewport().set_input_as_handled()
			KEY_EQUAL, KEY_PLUS:
				if enabled and music_director != null:
					music_director.seek_to(music_director.song_position + 1.0)
					get_viewport().set_input_as_handled()
			KEY_MINUS, KEY_UNDERSCORE:
				if enabled and music_director != null:
					music_director.seek_to(maxf(0.0, music_director.song_position - 1.0))
					get_viewport().set_input_as_handled()

func _seek_next_section() -> void:
	if music_director == null or music_director.song_profile == null:
		return
	var sorted: Array[MusicSection] = music_director.song_profile.get_sorted_sections()
	if sorted.is_empty():
		return
	var cur: int = music_director.current_section_index
	var nxt: int = clampi(cur + 1, 0, sorted.size() - 1)
	music_director.seek_to_section(nxt)

func _seek_prev_section() -> void:
	if music_director == null or music_director.song_profile == null:
		return
	var sorted: Array[MusicSection] = music_director.song_profile.get_sorted_sections()
	if sorted.is_empty():
		return
	var cur: int = music_director.current_section_index
	var prv: int = clampi(cur - 1, 0, sorted.size() - 1)
	music_director.seek_to_section(prv)

func toggle() -> void:
	enabled = not enabled
	visible = enabled
