extends Node
class_name SFXManager
## Central manager for radio chatter and jet alarms.
##
## - Radio: 12-file narrative (Easy13/Baker5/Razor) played sequentially with
##   configurable gaps, optional static bed + key-out tail (extras/).
## - Alarms: 14 jet alarms mapped to flight conditions (altitude, pull-up,
##   bounds, bingo, threat simulation, barrel-roll flare).
##
## Design: two dedicated alarm players (Critical vs Threat) + one radio
## player + static/tail players. All null-safe, all exports for tuning.
## Polls FighterJet public state (never privates) and listens to its
## signals + Main.stunt_performed.

# ------------------------------------------------------------------
# Exports
# ------------------------------------------------------------------
@export_category("References")
@export var fighter_path: NodePath = NodePath("../Fighter")
@export var hud_path: NodePath = NodePath("../HUD")

@export_category("Radio")
@export var radio_enabled: bool = true
@export_range(1.0, 30.0, 0.5) var radio_interval_min: float = 7.0
@export_range(1.0, 30.0, 0.5) var radio_interval_max: float = 13.0
@export_range(0.0, 10.0, 0.5) var radio_initial_delay: float = 4.0
@export_range(-18.0, 6.0, 0.5) var radio_volume_db: float = -1.0
@export var radio_random_order: bool = false
@export var radio_loop: bool = true
@export var radio_use_static: bool = true
@export_range(-30.0, -4.0, 0.5) var radio_static_volume_db: float = -20.0
@export var radio_use_tail: bool = true
@export_range(-18.0, 6.0, 0.5) var radio_tail_volume_db: float = -4.5
@export_range(0.0, 0.08, 0.01) var radio_pitch_variance: float = 0.0 ## 0 = preserve voice
@export var radio_show_subtitles: bool = true
@export_range(0.8, 4.0, 0.1) var radio_subtitle_time: float = 2.2

@export_category("Jet Alarms — Critical")
@export var alarms_enabled: bool = true
@export_range(-18.0, 6.0, 0.5) var alarm_volume_db: float = -0.5
@export_range(0.0, 2.0, 0.1) var alarm_global_cooldown: float = 0.75
@export_range(1.0, 10.0, 0.5) var altitude_warn_height: float = 6.0 ## world y below this = ALTITUDE
@export_range(1.0, 10.0, 0.5) var pull_up_height: float = 4.8 ## lower + diving = PULL UP
@export_range(-20.0, -1.0, 0.5) var pull_up_dive_rate: float = -6.0 ## velocity.y threshold
@export_range(1.0, 20.0, 0.5) var bingo_interval: float = 45.0
@export var alarm_show_hud: bool = true
@export_range(0.5, 4.0, 0.1) var alarm_hud_time: float = 1.6

@export_category("Jet Alarms — Threat Simulation")
@export var threat_enabled: bool = true
@export_range(8.0, 40.0, 1.0) var threat_interval_min: float = 12.0
@export_range(8.0, 40.0, 1.0) var threat_interval_max: float = 22.0
@export_range(20.0, 80.0, 1.0) var launch_interval_min: float = 28.0
@export_range(20.0, 80.0, 1.0) var launch_interval_max: float = 48.0
@export_range(-18.0, 6.0, 0.5) var threat_volume_db: float = -2.0
## Flare is a defensive response to a barrel roll — very audible.
@export var flare_on_barrel_roll: bool = true
@export_range(0.0, 1.0, 0.05) var flare_chance: float = 0.85

@export_category("Music Ducking")
@export var music_ducking_enabled: bool = true
@export_range(0.0, 8.0, 0.5) var music_duck_db: float = 3.5 ## how much to duck Music bus during critical alarms (0 = off)
@export_range(0.1, 2.0, 0.05) var music_duck_attack: float = 0.35
@export_range(0.1, 4.0, 0.05) var music_duck_release: float = 0.8

@export_category("Debug")
@export var debug_print: bool = false

# ------------------------------------------------------------------
# Internal — streams
# ------------------------------------------------------------------
var radio_streams: Array[AudioStream] = []
var radio_titles: Array[String] = [] ## subtitle text per stream, same index
var alarm_streams: Dictionary = {} ## key -> AudioStream
var static_stream: AudioStream = null
var tail_stream: AudioStream = null

# ------------------------------------------------------------------
# Internal — players (created in _ready)
# ------------------------------------------------------------------
var radio_player: AudioStreamPlayer
var static_player: AudioStreamPlayer
var tail_player: AudioStreamPlayer
var critical_player: AudioStreamPlayer
var threat_player: AudioStreamPlayer

# ------------------------------------------------------------------
# Internal — state
# ------------------------------------------------------------------
var fighter: FighterJet = null
var hud: CanvasLayer = null
var radio_label: Label = null
var alarm_label: Label = null

var _rng := RandomNumberGenerator.new()
var _radio_idx: int = 0
var _radio_timer: float = 0.0
var _radio_order: Array[int] = []
var _subtitle_t: float = 0.0
var _alarm_t: float = 0.0

var _global_cd: float = 0.0
var _alarm_cd: Dictionary = {} ## key -> remaining
var _bingo_timer: float = 0.0
var _threat_timer: float = 0.0
var _launch_timer: float = 0.0
var _bounds_cd: float = 0.0
var _pending_rwr: float = 0.0
var _tail_delay: float = 0.0
var _tail_pending: bool = false

# Alarm priority (higher wins) and per-alarm cooldowns.
const ALARM_PRIORITY: Dictionary = {
	"pull_up": 10,
	"altitude": 9,
	"warning": 8,
	"master_caution": 7,
	"tws_launch_1": 7,
	"tws_launch_2": 7,
	"rwr_lock": 6,
	"caution": 6,
	"tws_lock": 5,
	"lock": 5,
	"flare": 5,
	"jammer_warning": 4,
	"tws_search": 3,
	"bingo": 2,
}
const ALARM_COOLDOWN: Dictionary = {
	"pull_up": 4.5,
	"altitude": 3.8,
	"warning": 5.5,
	"master_caution": 6.0,
	"caution": 5.0,
	"bingo": 30.0,
	"tws_search": 6.0,
	"tws_lock": 5.0,
	"lock": 4.5,
	"rwr_lock": 5.0,
	"jammer_warning": 7.0,
	"tws_launch_1": 7.0,
	"tws_launch_2": 7.0,
	"flare": 3.0,
}

# Human-readable subtitles for the 12 radio files (inferred from filenames;
# exact phrasing may differ from the recorded lines — update if you have the script).
const RADIO_SUBTITLES: Array[String] = [
	"Easy 1-3 → Baker 5: Do you copy, Baker 5?",
	"Baker 5: Baker 5 copies, go ahead Easy 1-3.",
	"Easy 1-3: Enemy troops heading your way — platoon strength.",
	"Baker 5: Request heavy weapons, over.",
	"Easy 1-3: Moving to Hill 526 to intercept.",
	"Baker 5: Advise Razor units of contact.",
	"Easy 1-3: Easy 1-3, out.",
	"Easy 1-3 → Razor 6-6: Razor 6-6, do you copy?",
	"Razor 2-6: Razor 2-6, go ahead.",
	"Easy 1-3: Relay — enemy platoon converging on Hill 526, Baker 5 needs support.",
	"Razor 2-6: Copies, will relay.",
	"Razor 2-6 → All Razor: Be advised — hostile infantry moving on Hill 526.",
]

# ------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------
func _ready() -> void:
	_rng.seed = 1337 ^ 0x9E3779B9
	_fighter_lookup()
	_hud_lookup()
	_create_players()
	_load_streams()
	_wire_signals()
	_reset_timers()
	_update_static_loop()
	if debug_print:
		print("[SFXManager] ready — radio:%d alarms:%d static:%s tail:%s fighter:%s" % [
			radio_streams.size(), alarm_streams.size(),
			"yes" if static_stream != null else "no",
			"yes" if tail_stream != null else "no",
			"yes" if fighter != null else "NO (check fighter_path)",
		])


func _process(delta: float) -> void:
	# Always tick HUD timers even if audio disabled.
	_subtitle_t = maxf(0.0, _subtitle_t - delta)
	_alarm_t = maxf(0.0, _alarm_t - delta)
	_update_subtitle_visibility()
	_update_alarm_hud(delta)
	_update_music_ducking(delta)

	# Deferred tail after radio finishes (avoids await in _process).
	if _tail_pending:
		_tail_delay -= delta
		if _tail_delay <= 0.0:
			_tail_pending = false
			_play_tail_now()

	# Deferred RWR chain after a launch.
	if _pending_rwr > 0.0:
		_pending_rwr -= delta
		if _pending_rwr <= 0.0:
			_pending_rwr = 0.0
			_try_alarm("rwr_lock", threat_player, threat_volume_db)

	if fighter == null:
		_fighter_lookup()
		_wire_signals()
	if hud == null:
		_hud_lookup()
	if radio_enabled:
		_update_radio(delta)
	if alarms_enabled and fighter != null:
		_update_alarms(delta)


func _fighter_lookup() -> void:
	if fighter_path != NodePath("") :
		fighter = get_node_or_null(fighter_path) as FighterJet
	if fighter == null:
		# Fallback: parent holds Fighter as sibling.
		var p: Node = get_parent()
		if p != null:
			fighter = p.get_node_or_null("Fighter") as FighterJet
			if fighter == null:
				# Deeper search one level.
				for c in p.get_children():
					if c is FighterJet:
						fighter = c as FighterJet
						break


func _hud_lookup() -> void:
	hud = get_node_or_null(hud_path) as CanvasLayer
	if hud == null and get_parent() != null:
		hud = get_parent().get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		# Last resort: find any CanvasLayer named HUD in tree.
		var root: Node = get_tree().current_scene
		if root != null:
			hud = root.get_node_or_null("HUD") as CanvasLayer
	_ensure_hud_labels()


func _ensure_hud_labels() -> void:
	if hud == null:
		return
	# Radio subtitles — bottom center, just above the help line.
	radio_label = hud.get_node_or_null("RadioLabel") as Label
	if radio_label == null:
		# Also check TopLeft etc.
		radio_label = _find_label_recursive(hud, "RadioLabel")
	if radio_label == null:
		radio_label = Label.new()
		radio_label.name = "RadioLabel"
		# Place above Bottom help (Bottom is anchored bottom, offset -34).
		radio_label.anchor_left = 0.18
		radio_label.anchor_right = 0.82
		radio_label.anchor_top = 1.0
		radio_label.anchor_bottom = 1.0
		radio_label.offset_left = 0.0
		radio_label.offset_right = 0.0
		radio_label.offset_top = -58.0
		radio_label.offset_bottom = -34.0
		radio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		radio_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		radio_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var ls := LabelSettings.new()
		ls.font_size = 15
		ls.font_color = Color(0.95, 0.96, 1.0, 0.95)
		ls.outline_size = 5
		ls.outline_color = Color(0, 0, 0, 0.85)
		radio_label.label_settings = ls
		radio_label.text = ""
		radio_label.visible = false
		hud.add_child(radio_label)
	else:
		# Ensure per-instance LabelSettings so changing color/size doesn't bleed to LS_small.
		if radio_label.label_settings != null and not radio_label.label_settings.resource_local_to_scene:
			var dup: LabelSettings = radio_label.label_settings.duplicate(true) as LabelSettings
			dup.resource_local_to_scene = true
			radio_label.label_settings = dup
	# Alarm HUD — top center, urgent.
	alarm_label = hud.get_node_or_null("AlarmLabel") as Label
	if alarm_label == null:
		alarm_label = _find_label_recursive(hud, "AlarmLabel")
	if alarm_label == null:
		alarm_label = Label.new()
		alarm_label.name = "AlarmLabel"
		alarm_label.anchor_left = 0.25
		alarm_label.anchor_right = 0.75
		alarm_label.anchor_top = 0.0
		alarm_label.anchor_bottom = 0.0
		alarm_label.offset_left = 0.0
		alarm_label.offset_right = 0.0
		alarm_label.offset_top = 46.0
		alarm_label.offset_bottom = 78.0
		alarm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		alarm_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var als := LabelSettings.new()
		als.font_size = 26
		als.font_color = Color(1, 0.25, 0.2, 1)
		als.outline_size = 7
		als.outline_color = Color(0, 0, 0, 0.9)
		alarm_label.label_settings = als
		alarm_label.text = ""
		alarm_label.visible = false
		hud.add_child(alarm_label)
	else:
		if alarm_label.label_settings != null and not alarm_label.label_settings.resource_local_to_scene:
			var dup2: LabelSettings = alarm_label.label_settings.duplicate(true) as LabelSettings
			dup2.resource_local_to_scene = true
			alarm_label.label_settings = dup2


func _find_label_recursive(n: Node, name: String) -> Label:
	if n.name == name and n is Label:
		return n as Label
	for c in n.get_children():
		var r := _find_label_recursive(c, name)
		if r != null:
			return r
	return null


# ------------------------------------------------------------------
# Players
# ------------------------------------------------------------------
func _create_players() -> void:
	# Reuse existing nodes if SFXManager was instanced from a scene that already has them.
	radio_player = get_node_or_null("RadioPlayer") as AudioStreamPlayer
	if radio_player == null:
		radio_player = AudioStreamPlayer.new()
		radio_player.name = "RadioPlayer"
		add_child(radio_player)
	radio_player.bus = "Master"
	radio_player.autoplay = false
	radio_player.volume_db = radio_volume_db
	if not radio_player.finished.is_connected(_on_radio_finished):
		radio_player.finished.connect(_on_radio_finished)

	static_player = get_node_or_null("StaticPlayer") as AudioStreamPlayer
	if static_player == null:
		static_player = AudioStreamPlayer.new()
		static_player.name = "StaticPlayer"
		add_child(static_player)
	static_player.bus = "Master"
	static_player.autoplay = false
	static_player.volume_db = radio_static_volume_db

	tail_player = get_node_or_null("TailPlayer") as AudioStreamPlayer
	if tail_player == null:
		tail_player = AudioStreamPlayer.new()
		tail_player.name = "TailPlayer"
		add_child(tail_player)
	tail_player.bus = "Master"
	tail_player.autoplay = false
	tail_player.volume_db = radio_tail_volume_db

	critical_player = get_node_or_null("CriticalAlarmPlayer") as AudioStreamPlayer
	if critical_player == null:
		critical_player = AudioStreamPlayer.new()
		critical_player.name = "CriticalAlarmPlayer"
		add_child(critical_player)
	critical_player.bus = "Master"
	critical_player.autoplay = false
	critical_player.volume_db = alarm_volume_db

	threat_player = get_node_or_null("ThreatAlarmPlayer") as AudioStreamPlayer
	if threat_player == null:
		threat_player = AudioStreamPlayer.new()
		threat_player.name = "ThreatAlarmPlayer"
		add_child(threat_player)
	threat_player.bus = "Master"
	threat_player.autoplay = false
	threat_player.volume_db = threat_volume_db


func _update_static_loop() -> void:
	if static_player == null or static_stream == null:
		return
	if radio_use_static and radio_enabled:
		if static_player.stream != static_stream:
			static_player.stream = static_stream
		static_player.volume_db = radio_static_volume_db
		if not static_player.playing:
			static_player.play()
	else:
		if static_player.playing:
			static_player.stop()


# ------------------------------------------------------------------
# Streams — safe loader handles wav/mp3 and wav loop config
# ------------------------------------------------------------------
func _safe_load(path: String) -> AudioStream:
	# Try exact path, then mp3 fallback, then wav fallback.
	var candidates: Array[String] = [path]
	if path.ends_with(".wav"):
		candidates.append(path.replace(".wav", ".mp3"))
	elif path.ends_with(".mp3"):
		candidates.append(path.replace(".mp3", ".wav"))
	for p in candidates:
		if ResourceLoader.exists(p):
			var res: Resource = load(p)
			if res is AudioStream:
				return res as AudioStream
		# Also try FileAccess check (covers not-yet-imported).
		if FileAccess.file_exists(p):
			var res2: Resource = load(p)
			if res2 is AudioStream:
				return res2 as AudioStream
	return null


func _make_looping_dup(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	var dup: AudioStream = stream.duplicate(true) as AudioStream
	if dup is AudioStreamWAV:
		var w: AudioStreamWAV = dup as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		# loop points default to full sample — fine for 8s static.
	elif dup is AudioStreamMP3:
		(dup as AudioStreamMP3).loop = true
	elif dup is AudioStreamOggVorbis:
		(dup as AudioStreamOggVorbis).loop = true
	return dup


func _make_oneshot_dup(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	var dup: AudioStream = stream.duplicate(true) as AudioStream
	if dup is AudioStreamWAV:
		(dup as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif dup is AudioStreamMP3:
		(dup as AudioStreamMP3).loop = false
	elif dup is AudioStreamOggVorbis:
		(dup as AudioStreamOggVorbis).loop = false
	return dup


func _load_streams() -> void:
	# --- Radio (ordered narrative) ---
	var radio_base: String = "res://sounds/fx/radio"
	var radio_files: Array[String] = [
		"01_easy13_calls_baker5.wav",
		"02_baker5_acknowledges.wav",
		"03_enemy_troops_heading_your_way.wav",
		"04_baker5_requests_heavy_weapons.wav",
		"05_moving_to_hill_526.wav",
		"06_advise_razor_units.wav",
		"07_easy13_signs_off.wav",
		"08_easy13_calls_razor6.wav",
		"09_razor26_go_ahead.wav",
		"10_relay_enemy_platoon_hill_526.wav",
		"11_razor26_will_relay.wav",
		"12_razor26_broadcasts_warning.wav",
	]
	radio_streams.clear()
	radio_titles.clear()
	for i in radio_files.size():
		var p: String = radio_base + "/" + radio_files[i]
		var s: AudioStream = _safe_load(p)
		if s != null:
			s = _make_oneshot_dup(s)
			radio_streams.append(s)
			var title: String = RADIO_SUBTITLES[i] if i < RADIO_SUBTITLES.size() else radio_files[i].get_basename()
			radio_titles.append(title)
		else:
			push_warning("[SFXManager] missing radio file: " + p)
	# Extras — static loop + tail.
	var static_candidates: Array[String] = [
		"res://sounds/fx/extras/radio_static_loop_8s.wav",
		"res://sounds/fx/extras/radio_static_loop_8s.mp3",
	]
	var tail_candidates: Array[String] = [
		"res://sounds/fx/extras/radio_static_and_keyout_tail.wav",
		"res://sounds/fx/extras/radio_static_and_keyout_tail.mp3",
	]
	for p in static_candidates:
		var s: AudioStream = _safe_load(p)
		if s != null:
			static_stream = _make_looping_dup(s)
			break
	for p in tail_candidates:
		var s: AudioStream = _safe_load(p)
		if s != null:
			tail_stream = _make_oneshot_dup(s)
			break
	# --- Jet alarms (14) ---
	var alarm_base: String = "res://sounds/fx/jet alarms"
	var alarm_map: Dictionary = {
		"master_caution": "01_master_caution.wav",
		"altitude": "02_altitude.wav",
		"pull_up": "03_pull_up.wav",
		"caution": "04_caution.wav",
		"warning": "05_warning.wav",
		"bingo": "06_bingo.wav",
		"lock": "07_lock.wav",
		"flare": "08_flare.wav",
		"jammer_warning": "09_jammer_warning.wav",
		"tws_search": "10_tws_search.wav",
		"tws_lock": "11_tws_lock.wav",
		"tws_launch_1": "12_tws_launch_1.wav",
		"rwr_lock": "13_rwr_lock.wav",
		"tws_launch_2": "14_tws_launch_2.wav",
	}
	alarm_streams.clear()
	for key in alarm_map.keys():
		var p: String = alarm_base + "/" + (alarm_map[key] as String)
		var s: AudioStream = _safe_load(p)
		if s != null:
			alarm_streams[key] = _make_oneshot_dup(s)
		else:
			push_warning("[SFXManager] missing alarm file: " + p + " (" + key + ")")
	# Init cooldown table.
	for k in ALARM_COOLDOWN.keys():
		_alarm_cd[k] = 0.0


# ------------------------------------------------------------------
# Wiring
# ------------------------------------------------------------------
func _wire_signals() -> void:
	if fighter == null:
		return
	# Fighter signals → alarms/reactions.
	if fighter.has_signal("barrel_started"):
		if not fighter.barrel_started.is_connected(_on_barrel_started):
			fighter.barrel_started.connect(_on_barrel_started)
	if fighter.has_signal("boost_started"):
		if not fighter.boost_started.is_connected(_on_boost_started):
			fighter.boost_started.connect(_on_boost_started)
	if fighter.has_signal("brake_started"):
		if not fighter.brake_started.is_connected(_on_brake_started):
			fighter.brake_started.connect(_on_brake_started)
	# Main stunt signal (parent is Main).
	var main: Node = get_parent()
	if main != null and main.has_signal("stunt_performed"):
		if not main.stunt_performed.is_connected(_on_stunt_performed):
			main.stunt_performed.connect(_on_stunt_performed)


func _reset_timers() -> void:
	_radio_timer = radio_initial_delay
	_radio_idx = 0
	_radio_order.clear()
	if radio_random_order and radio_streams.size() > 0:
		_radio_order = range(radio_streams.size())
		_radio_order.shuffle()
	_bingo_timer = bingo_interval * 0.7 # first bingo sooner
	_threat_timer = _rng.randf_range(threat_interval_min, threat_interval_max) * 0.6
	_launch_timer = _rng.randf_range(launch_interval_min, launch_interval_max) * 0.8
	_pending_rwr = 0.0
	_tail_pending = false
	_tail_delay = 0.0
	_global_cd = 0.0
	_bounds_cd = 0.0
	for k in _alarm_cd.keys():
		_alarm_cd[k] = 0.0


# ------------------------------------------------------------------
# Radio
# ------------------------------------------------------------------
func _update_radio(delta: float) -> void:
	if radio_streams.is_empty():
		return
	# Count down only when not transmitting (so gap is *between* calls, not overlapping).
	if radio_player != null and radio_player.playing:
		return
	if tail_player != null and tail_player.playing:
		return
	_radio_timer -= delta
	if _radio_timer <= 0.0:
		_play_next_radio()
		_radio_timer = _rng.randf_range(radio_interval_min, radio_interval_max)


func _play_next_radio() -> void:
	if radio_streams.is_empty() or radio_player == null:
		return
	var idx: int = -1
	if radio_random_order:
		if _radio_order.is_empty():
			_radio_order = range(radio_streams.size())
			_radio_order.shuffle()
		idx = _radio_order.pop_back()
	else:
		idx = _radio_idx % radio_streams.size()
		_radio_idx += 1
		if _radio_idx >= radio_streams.size():
			if radio_loop:
				_radio_idx = 0
			else:
				radio_enabled = false
				if debug_print:
					print("[SFXManager] radio sequence complete — disabling (radio_loop=false)")
				return
	var s: AudioStream = radio_streams[idx]
	radio_player.stream = s
	radio_player.volume_db = radio_volume_db
	var pv: float = radio_pitch_variance
	if pv > 0.001:
		radio_player.pitch_scale = _rng.randf_range(1.0 - pv, 1.0 + pv)
	else:
		radio_player.pitch_scale = 1.0
	# Duck static bed slightly while speaking so voice cuts.
	if static_player != null and static_player.playing:
		static_player.volume_db = radio_static_volume_db - 1.5
	radio_player.play()
	_show_subtitle(radio_titles[idx] if idx < radio_titles.size() else "")
	if debug_print:
		print("[SFXManager] radio → %s (idx %d)" % [radio_titles[idx] if idx < radio_titles.size() else str(idx), idx])


func _on_radio_finished() -> void:
	# Restore static bed.
	if static_player != null:
		static_player.volume_db = radio_static_volume_db
	# Tail burst (key-out static) right after the voice — deferred to _process.
	if radio_use_tail and tail_stream != null and tail_player != null:
		_tail_pending = true
		_tail_delay = 0.08


func _play_tail_now() -> void:
	if radio_player != null and radio_player.playing:
		return
	if tail_stream == null or tail_player == null:
		return
	tail_player.stream = tail_stream
	tail_player.volume_db = radio_tail_volume_db
	tail_player.pitch_scale = 1.0
	tail_player.play()


func _show_subtitle(text: String) -> void:
	if not radio_show_subtitles or radio_label == null or text == "":
		return
	radio_label.text = text
	radio_label.visible = true
	radio_label.modulate.a = 1.0
	_subtitle_t = radio_subtitle_time


func _update_subtitle_visibility() -> void:
	if radio_label == null:
		return
	if _subtitle_t <= 0.0:
		# Fade out quickly rather than pop.
		radio_label.modulate.a = move_toward(radio_label.modulate.a, 0.0, 0.06)
		if radio_label.modulate.a <= 0.01:
			radio_label.visible = false
	else:
		radio_label.visible = true
		radio_label.modulate.a = 1.0


# ------------------------------------------------------------------
# Alarms
# ------------------------------------------------------------------
func _update_alarms(delta: float) -> void:
	_global_cd = maxf(0.0, _global_cd - delta)
	_bounds_cd = maxf(0.0, _bounds_cd - delta)
	for k in _alarm_cd.keys():
		_alarm_cd[k] = maxf(0.0, (_alarm_cd[k] as float) - delta)
	if _bingo_timer > 0.0:
		_bingo_timer -= delta
	if _threat_timer > 0.0:
		_threat_timer -= delta
	if _launch_timer > 0.0:
		_launch_timer -= delta

	# ---- Critical altitude / pull-up (highest priority, checked every frame) ----
	var y: float = fighter.global_position.y
	var vy: float = fighter.velocity.y
	var near_ground: bool = y < pull_up_height
	var diving: bool = vy < pull_up_dive_rate
	if near_ground and diving:
		# Imminent ground collision — pull up now.
		if _try_alarm("pull_up", critical_player):
			fighter.add_trauma(0.04)
	elif y < altitude_warn_height:
		_try_alarm("altitude", critical_player)

	# ---- Soft-corridor grind (bounds) → caution / warning ----
	# Use lightweight distance check mirroring fighter._apply_soft_bounds but
	# without touching physics — just for audio.
	var bound_push: float = _estimate_bound_push()
	if bound_push > 0.55 and _bounds_cd <= 0.0:
		# Grinding hard — escalate.
		if bound_push > 0.85:
			if _try_alarm("warning", critical_player):
				_bounds_cd = 3.0
		elif bound_push > 0.65:
			if _try_alarm("caution", critical_player):
				_bounds_cd = 2.2
		else:
			if _try_alarm("master_caution", critical_player):
				_bounds_cd = 2.5
	elif bound_push > 0.25 and fighter.lateral_g > 0.72 and _bounds_cd <= 0.0:
		# High-G near wall — master caution even if not deep in push zone.
		if _try_alarm("master_caution", critical_player):
			_bounds_cd = 2.8

	# ---- Bingo fuel (periodic, low priority) ----
	if _bingo_timer <= 0.0:
		if _try_alarm("bingo", critical_player):
			_bingo_timer = bingo_interval
			if debug_print:
				print("[SFXManager] bingo fuel")

	# ---- Threat simulation (search → lock → launch) ----
	if threat_enabled:
		if _launch_timer <= 0.0:
			var launch_key: String = "tws_launch_1" if _rng.randf() < 0.5 else "tws_launch_2"
			if _try_alarm(launch_key, threat_player, threat_volume_db):
				_launch_timer = _rng.randf_range(launch_interval_min, launch_interval_max)
				# Chain a follow-up RWR lock shortly after launch for flavor.
				_pending_rwr = 0.45
			else:
				_launch_timer = 4.0 # retry soon if blocked
		elif _threat_timer <= 0.0:
			_trigger_threat(_rng)


func _estimate_bound_push() -> float:
	# Mirrors fighter soft bounds without side effects.
	var p: Vector3 = fighter.global_position
	var push: float = 0.0
	var edge_x: float = fighter.bound_half_width - fighter.bound_soft_margin
	if p.x > edge_x:
		push = maxf(push, (p.x - edge_x) / maxf(fighter.bound_soft_margin, 0.01))
	elif p.x < -edge_x:
		push = maxf(push, (-p.x - edge_x) / maxf(fighter.bound_soft_margin, 0.01))
	var edge_top: float = fighter.bound_max_height - fighter.bound_soft_margin
	var edge_bot: float = fighter.bound_min_height + fighter.bound_soft_margin
	if p.y > edge_top:
		push = maxf(push, (p.y - edge_top) / maxf(fighter.bound_soft_margin, 0.01))
	elif p.y < edge_bot:
		push = maxf(push, (edge_bot - p.y) / maxf(fighter.bound_soft_margin, 0.01))
	return clampf(push, 0.0, 1.5)


func _trigger_threat(rng: RandomNumberGenerator) -> void:
	var pool: Array[String] = ["tws_search", "tws_lock", "lock", "rwr_lock", "jammer_warning"]
	# Weight: search 30%, lock variants 45%, jammer 25%.
	var roll: float = rng.randf()
	var key: String
	if roll < 0.30:
		key = "tws_search"
	elif roll < 0.55:
		key = "tws_lock" if rng.randf() < 0.5 else "lock"
	elif roll < 0.75:
		key = "rwr_lock"
	else:
		key = "jammer_warning"
	if _try_alarm(key, threat_player, threat_volume_db):
		_threat_timer = _rng.randf_range(threat_interval_min, threat_interval_max)
		if debug_print:
			print("[SFXManager] threat → ", key)
	else:
		_threat_timer = 1.5 # blocked — retry quickly


func _can_play_alarm(key: String, player: AudioStreamPlayer) -> bool:
	if not alarms_enabled:
		return false
	if not alarm_streams.has(key):
		return false
	var cd: float = _alarm_cd.get(key, 0.0) as float
	if cd > 0.01:
		return false
	if _global_cd > 0.01:
		# Allow pull_up to interrupt anything.
		if key != "pull_up":
			return false
	# Priority check: don't let low-priority spam over a playing high-priority alarm.
	if player != null and player.playing:
		var cur_key: String = player.get_meta("alarm_key") if player.has_meta("alarm_key") else ""
		if cur_key != "" and ALARM_PRIORITY.has(cur_key) and ALARM_PRIORITY.has(key):
			var cur_prio: int = ALARM_PRIORITY[cur_key] as int
			var new_prio: int = ALARM_PRIORITY[key] as int
			if new_prio <= cur_prio:
				return false
	return true


func _try_alarm(key: String, player: AudioStreamPlayer, volume_override: float = NAN) -> bool:
	if not _can_play_alarm(key, player):
		return false
	return _play_alarm(key, player, volume_override)


func _play_alarm(key: String, player: AudioStreamPlayer, volume_override: float = NAN) -> bool:
	var stream: AudioStream = alarm_streams.get(key, null) as AudioStream
	if stream == null or player == null:
		return false
	player.stream = stream
	var vol: float = threat_volume_db if (player == threat_player and not is_nan(volume_override)) else (volume_override if not is_nan(volume_override) else alarm_volume_db)
	# Critical player uses alarm_volume_db, threat uses threat_volume_db by default.
	if player == critical_player and is_nan(volume_override):
		vol = alarm_volume_db
	elif player == threat_player and is_nan(volume_override):
		vol = threat_volume_db
	player.volume_db = vol
	player.pitch_scale = 1.0
	player.set_meta("alarm_key", key)
	player.play()
	_alarm_cd[key] = ALARM_COOLDOWN.get(key, 4.0) as float
	_global_cd = alarm_global_cooldown
	_show_alarm_hud(key)
	if debug_print:
		print("[SFXManager] alarm → ", key, " (", player.name, ")")
	return true


func _show_alarm_hud(key: String) -> void:
	if not alarm_show_hud or alarm_label == null:
		return
	var text: String = _alarm_hud_text(key)
	if text == "":
		return
	alarm_label.text = text
	alarm_label.visible = true
	alarm_label.modulate.a = 1.0
	# Color code.
	var ls: LabelSettings = alarm_label.label_settings
	if ls != null:
		match key:
			"pull_up":
				ls.font_color = Color(1, 0.15, 0.15, 1)
				ls.font_size = 34
			"altitude":
				ls.font_color = Color(1, 0.45, 0.1, 1)
				ls.font_size = 30
			"warning":
				ls.font_color = Color(1, 0.2, 0.2, 1)
				ls.font_size = 28
			"master_caution":
				ls.font_color = Color(1, 0.85, 0.2, 1)
				ls.font_size = 26
			"caution":
				ls.font_color = Color(1, 0.8, 0.25, 1)
				ls.font_size = 24
			"bingo":
				ls.font_color = Color(1, 0.6, 0.1, 1)
				ls.font_size = 24
			"flare":
				ls.font_color = Color(1, 0.5, 0.1, 1)
				ls.font_size = 22
			_:
				ls.font_color = Color(1, 0.35, 0.25, 1)
				ls.font_size = 22
	_alarm_t = alarm_hud_time
	# Brief hitstop on most urgent.
	if key == "pull_up":
		alarm_label.scale = Vector2(1.12, 1.12)
	else:
		alarm_label.scale = Vector2.ONE


func _alarm_hud_text(key: String) -> String:
	match key:
		"pull_up": return "⚠ PULL UP ⚠"
		"altitude": return "ALTITUDE"
		"master_caution": return "MASTER CAUTION"
		"caution": return "CAUTION"
		"warning": return "⚠ WARNING ⚠"
		"bingo": return "BINGO FUEL"
		"lock": return "LOCK"
		"flare": return "FLARE"
		"jammer_warning": return "JAMMER"
		"tws_search": return "TWS SEARCH"
		"tws_lock": return "TWS LOCK"
		"tws_launch_1": return "MISSILE LAUNCH"
		"tws_launch_2": return "MISSILE LAUNCH"
		"rwr_lock": return "RWR LOCK"
		_: return key.to_upper()


func _update_alarm_hud(_delta: float) -> void:
	if alarm_label == null:
		return
	if _alarm_t <= 0.0:
		alarm_label.modulate.a = move_toward(alarm_label.modulate.a, 0.0, 0.05)
		alarm_label.scale = alarm_label.scale.lerp(Vector2.ONE, 0.12)
		if alarm_label.modulate.a <= 0.02:
			alarm_label.visible = false
	else:
		# Flash for critical.
		var t: float = Time.get_ticks_msec() / 1000.0
		var flash: bool = fmod(t, 0.18) < 0.09
		if alarm_label.text.contains("PULL UP") or alarm_label.text.contains("WARNING"):
			alarm_label.visible = flash or _alarm_t > alarm_hud_time * 0.5
		else:
			alarm_label.visible = true
			alarm_label.modulate.a = 1.0


var _music_duck_current: float = 0.0 ## 0..1 duck amount smoothed

func _update_music_ducking(delta: float) -> void:
	if not music_ducking_enabled:
		if _music_duck_current > 0.01:
			_music_duck_current = lerpf(_music_duck_current, 0.0, 1.0 - exp(-3.0 * delta))
			_apply_music_duck(_music_duck_current)
		return
	var should_duck: bool = false
	if critical_player != null and critical_player.playing:
		var k: String = critical_player.get_meta("alarm_key") if critical_player.has_meta("alarm_key") else ""
		if k in ["pull_up", "altitude", "warning"]:
			should_duck = true
	var target: float = 1.0 if should_duck else 0.0
	var rate: float = music_duck_attack if should_duck else music_duck_release
	_music_duck_current = lerpf(_music_duck_current, target, 1.0 - exp(-rate * delta))
	_apply_music_duck(_music_duck_current)

func _apply_music_duck(amount: float) -> void:
	var bus: int = AudioServer.get_bus_index("Music")
	if bus == -1:
		return
	var db: float = -music_duck_db * amount
	# Don't spam same value every frame if unchanged much.
	AudioServer.set_bus_volume_db(bus, db)


# ------------------------------------------------------------------
# Signal handlers (fighter / main)
# ------------------------------------------------------------------
func _on_barrel_started(_dir: float) -> void:
	if not alarms_enabled or not flare_on_barrel_roll:
		return
	if _rng.randf() > flare_chance:
		return
	# Flare is a threat-layer sound — don't block critical warnings.
	_try_alarm("flare", threat_player, threat_volume_db)


func _on_boost_started() -> void:
	# Boost is loud — small chance to trigger a jammer warning as flavor
	# (afterburner lights up RWR). Very low priority so it never blocks pull_up.
	if threat_enabled and _rng.randf() < 0.08:
		_try_alarm("jammer_warning", threat_player, threat_volume_db)


func _on_brake_started() -> void:
	pass


func _on_stunt_performed(kind: String, _intensity: float, combo: int) -> void:
	# High-skill stunts occasionally earn a radio commendation — accelerate
	# the next transmission (feels like AWACS is watching).
	if kind == "PERFECT THREAD" and radio_enabled and radio_player != null and not radio_player.playing:
		_radio_timer = minf(_radio_timer, 1.2)
	elif kind == "THREADED" and combo >= 4 and radio_enabled:
		_radio_timer = minf(_radio_timer, 2.5)
	# Barrel chains are noisy — tiny threat bump.
	if kind == "BARREL CHAIN" and threat_enabled and _rng.randf() < 0.25:
		_try_alarm("tws_search", threat_player, threat_volume_db)


func _unhandled_input(event: InputEvent) -> void:
	# Debug toggles (no input map required): N = radio on/off, B = test pull-up, V = next radio.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_N:
				set_radio_enabled(not radio_enabled)
				if debug_print:
					print("[SFXManager] radio_enabled=", radio_enabled)
				get_viewport().set_input_as_handled()
			KEY_B:
				play_alarm("pull_up")
				get_viewport().set_input_as_handled()
			KEY_V:
				play_next_radio_now()
				get_viewport().set_input_as_handled()
			KEY_J:
				play_alarm("tws_launch_1" if _rng.randf() < 0.5 else "tws_launch_2")
				get_viewport().set_input_as_handled()


# ------------------------------------------------------------------
# Public API — call from console / tests / HUD buttons
# ------------------------------------------------------------------
func play_alarm(key: String) -> bool:
	## Manual trigger (e.g. debug console). key is one of the 14 alarm ids.
	var player: AudioStreamPlayer = _player_for_key(key)
	return _play_alarm(key, player)


func play_next_radio_now() -> void:
	## Force the next radio line immediately.
	_radio_timer = 0.0
	_update_radio(0.0)


func skip_radio() -> void:
	## Cut current radio and schedule next.
	if radio_player != null and radio_player.playing:
		radio_player.stop()
	if tail_player != null and tail_player.playing:
		tail_player.stop()
	_radio_timer = 0.35


func set_radio_enabled(v: bool) -> void:
	radio_enabled = v
	_update_static_loop()
	if not v:
		if radio_player != null and radio_player.playing:
			radio_player.stop()
		if static_player != null and static_player.playing:
			static_player.stop()


func set_alarms_enabled(v: bool) -> void:
	alarms_enabled = v
	if not v:
		if critical_player != null and critical_player.playing:
			critical_player.stop()
		if threat_player != null and threat_player.playing:
			threat_player.stop()


func _player_for_key(key: String) -> AudioStreamPlayer:
	match key:
		"pull_up", "altitude", "master_caution", "caution", "warning", "bingo":
			return critical_player
		_:
			return threat_player


func _on_critical_finished() -> void:
	if critical_player != null:
		critical_player.remove_meta("alarm_key")
