extends Node

enum Mode { SOLO, HOST, JOIN, LOCAL }

const PORT := 7777
const SETTINGS_PATH := "user://settings.cfg"

signal host_info_changed

var mode: int = Mode.SOLO
var join_ip := "127.0.0.1"

# Couch mode: one PlayerInput device id per joined player (-1 = KB+M).
# Runs single-process on the default offline peer — every couch player
# keeps authority 1, so all the server-side RPC paths work unchanged.
var local_roster: Array = []
var ui_open := false  # a blocking menu (pause) is up; gameplay input should ignore the mouse

# Set while hosting: the address friends type in to join from outside the
# LAN, plus a one-line status for the HUD while UPnP is negotiating.
var external_ip := ""
var host_info := ""

var _upnp_thread: Thread = null

var music_volume := 0.8
var sfx_volume := 0.8


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


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		music_volume = cfg.get_value("audio", "music", 0.8)
		sfx_volume = cfg.get_value("audio", "sfx", 0.8)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(SETTINGS_PATH)


func start_solo() -> void:
	mode = Mode.SOLO
	_go()


func start_host() -> void:
	mode = Mode.HOST
	_go()


func start_join(ip: String) -> void:
	mode = Mode.JOIN
	join_ip = ip.strip_edges() if ip.strip_edges() != "" else "127.0.0.1"
	_go()


func start_local(roster: Array) -> void:
	mode = Mode.LOCAL
	local_roster = roster.duplicate()
	_go()


func _go() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# Called by main._ready once the game scene exists, so spawners are
# already in place when peers start talking.
func setup_peer() -> void:
	if mode == Mode.HOST:
		var peer := ENetMultiplayerPeer.new()
		peer.create_server(PORT, 8)
		multiplayer.multiplayer_peer = peer
		_start_upnp()
	elif mode == Mode.JOIN:
		var peer := ENetMultiplayerPeer.new()
		peer.create_client(join_ip, PORT)
		multiplayer.multiplayer_peer = peer


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_stop_upnp()
	mode = Mode.SOLO
	ui_open = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _exit_tree() -> void:
	_stop_upnp()


# --- UPnP: open the host's router port so internet peers can join -----
#
# Discovery talks to the router and can take seconds, so it runs on a
# thread and reports back through call_deferred.

func _start_upnp() -> void:
	host_info = "Opening internet port via UPnP…"
	host_info_changed.emit()
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_setup)


# Runs on _upnp_thread. Returns the UPNP instance when a mapping was
# created (so _stop_upnp can remove it), or null when nothing to undo.
func _upnp_setup() -> UPNP:
	var upnp := UPNP.new()
	var err := upnp.discover()
	if err != UPNP.UPNP_RESULT_SUCCESS or upnp.get_gateway() == null or not upnp.get_gateway().is_valid_gateway():
		_apply_host_info.call_deferred("",
			"No UPnP router found — LAN play works; for internet, forward UDP port %d." % PORT)
		return null
	if upnp.add_port_mapping(PORT, PORT, "Shotgun Drift", "UDP", 0) != UPNP.UPNP_RESULT_SUCCESS:
		_apply_host_info.call_deferred("",
			"Router refused UPnP — LAN play works; for internet, forward UDP port %d." % PORT)
		return null
	var ip := upnp.query_external_address()
	if ip == "":
		_apply_host_info.call_deferred("",
			"Port %d is open, but couldn't read your public IP — look it up and share it." % PORT)
	else:
		_apply_host_info.call_deferred(ip, "Friends join with IP: %s" % ip)
	return upnp


func _apply_host_info(ip: String, info: String) -> void:
	if mode != Mode.HOST:
		return  # left the game before discovery finished
	external_ip = ip
	host_info = info
	host_info_changed.emit()


func _stop_upnp() -> void:
	if _upnp_thread == null:
		return
	var upnp: UPNP = _upnp_thread.wait_to_finish()
	_upnp_thread = null
	if upnp != null:
		upnp.delete_port_mapping(PORT, "UDP")
	external_ip = ""
	host_info = ""
