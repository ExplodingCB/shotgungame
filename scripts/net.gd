extends Node

enum Mode { SOLO, HOST, JOIN }

const PORT := 7777
const SETTINGS_PATH := "user://settings.cfg"

var mode: int = Mode.SOLO
var join_ip := "127.0.0.1"
var ui_open := false  # a blocking menu (pause) is up; gameplay input should ignore the mouse

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


func _go() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# Called by main._ready once the game scene exists, so spawners are
# already in place when peers start talking.
func setup_peer() -> void:
	if mode == Mode.HOST:
		var peer := ENetMultiplayerPeer.new()
		peer.create_server(PORT, 8)
		multiplayer.multiplayer_peer = peer
	elif mode == Mode.JOIN:
		var peer := ENetMultiplayerPeer.new()
		peer.create_client(join_ip, PORT)
		multiplayer.multiplayer_peer = peer


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.SOLO
	ui_open = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
