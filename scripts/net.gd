extends Node

enum Mode { SOLO, HOST, JOIN, LOCAL }

const SETTINGS_PATH := "user://settings.cfg"

signal host_info_changed
signal join_status(message: String)
signal join_failed(reason: String)

var mode: int = Mode.SOLO

# Couch mode: one PlayerInput device id per joined player (-1 = KB+M).
# Runs single-process on the default offline peer — every couch player
# keeps authority 1, so all the server-side RPC paths work unchanged.
var local_roster: Array = []
# Lobby-picked color index per roster entry; empty falls back to slots.
var local_colors: Array = []
var ui_open := false  # a blocking menu (pause) is up; gameplay input should ignore the mouse

# Set while hosting: the code friends type to join, plus a one-line
# status for the HUD while UPnP is negotiating.
var room_code := ""
var host_info := ""

# Swappable matchmaking transport (direct ENet now, Steam/Xbox later).
var backend: NetBackend = null

var music_volume := 0.8
var sfx_volume := 0.8
var fullscreen := false
var vsync := true

# Menu-picked ship color (index into player COLORS); -1 = slot default.
var preferred_color := -1


func _ready() -> void:
	# Dedicated buses so music and SFX volume are independent.
	for bus_name in ["Music", "SFX"]:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	_load_settings()
	set_music_volume(music_volume)
	set_sfx_volume(sfx_volume)
	_apply_display()

	backend = DirectBackend.new()
	backend.name = "Backend"
	add_child(backend)
	backend.room_opened.connect(_on_room_opened)
	backend.join_status.connect(func(msg: String): join_status.emit(msg))
	backend.join_validated.connect(_on_join_validated)
	backend.join_failed.connect(func(reason: String): join_failed.emit(reason))


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_bus("Music", music_volume)
	_save_settings()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_bus("SFX", sfx_volume)
	_save_settings()


func _apply_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))


func set_preferred_color(idx: int) -> void:
	preferred_color = idx
	_save_settings()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_display()
	_save_settings()


func set_vsync(on: bool) -> void:
	vsync = on
	_apply_display()
	_save_settings()


# Headless runs (tests, exports) have no window to flip.
func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN
			if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED
			if vsync else DisplayServer.VSYNC_DISABLED)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		music_volume = cfg.get_value("audio", "music", 0.8)
		sfx_volume = cfg.get_value("audio", "sfx", 0.8)
		preferred_color = cfg.get_value("player", "color", -1)
		fullscreen = cfg.get_value("display", "fullscreen", false)
		vsync = cfg.get_value("display", "vsync", true)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("player", "color", preferred_color)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.save(SETTINGS_PATH)


func start_solo() -> void:
	mode = Mode.SOLO
	_go()


func start_host() -> void:
	mode = Mode.HOST
	_go()


# Joining never leaves the menu until the backend confirms the room is
# reachable, so mode stays untouched until then (the menu's background
# demo runs in LOCAL mode and reads it every frame).
func start_join(code: String) -> void:
	backend.begin_join(code)


func cancel_join() -> void:
	backend.cancel_join()


func start_local(roster: Array, colors: Array = []) -> void:
	mode = Mode.LOCAL
	local_roster = roster.duplicate()
	local_colors = colors.duplicate()
	_go()


func _go() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_join_validated() -> void:
	mode = Mode.JOIN
	_go()


func _on_room_opened(code: String, status: String) -> void:
	room_code = code
	host_info = status
	host_info_changed.emit()


# Called by main._ready once the game scene exists, so spawners are
# already in place when peers start talking.
func setup_peer() -> void:
	if mode == Mode.HOST:
		backend.host()
	elif mode == Mode.JOIN:
		backend.complete_join()


func leave() -> void:
	backend.leave()
	mode = Mode.SOLO
	ui_open = false
	room_code = ""
	host_info = ""
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
