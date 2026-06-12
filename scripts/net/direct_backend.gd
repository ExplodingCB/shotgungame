class_name DirectBackend
extends NetBackend

# Direct ENet play, no services: the room code carries the host's
# address (see RoomCode), LAN joins are found by broadcast (see
# LanDiscovery), and internet reachability comes from UPnP.
#
# Joins are validated with a throwaway raw ENet connection while the
# menu is still up. The real client peer is only created once the game
# scene exists, because the MultiplayerSpawners flush existing state to
# a peer the moment it connects.

const MAX_PLAYERS := 8
const LAN_PROBE_TIME := 0.8
const PROBE_TIMEOUT := 4.0
const NOT_REACHABLE := "Room not reachable. Check the code, or the host's router may not support UPnP."

enum JoinState { IDLE, LAN_PROBE, NET_PROBE }

# --- hosting state ---
var _hosting := false
var _room_code := ""
var _game_port := 0
var _responder: LanDiscovery.Responder = null
var _upnp_thread: Thread = null

# --- joining state ---
var _state := JoinState.IDLE
var _prober: LanDiscovery.Prober = null
var _probe_conn: ENetConnection = null
var _probe_peer: ENetPacketPeer = null
var _timer := 0.0
var _decoded := {}  # address from the code (or typed IP)
var _target := {}   # address that actually answered the probe


func current_code() -> String:
	return _room_code


func _process(delta: float) -> void:
	if _responder != null:
		_responder.poll()
	match _state:
		JoinState.LAN_PROBE:
			var hit := _prober.poll()
			if not hit.is_empty():
				_prober.stop()
				_prober = null
				_state = JoinState.IDLE
				_target = hit
				join_validated.emit()
			else:
				_timer -= delta
				if _timer <= 0.0:
					_prober.stop()
					_prober = null
					_begin_net_probe()
		JoinState.NET_PROBE:
			var ev: Array = _probe_conn.service(0)
			if ev[0] == ENetConnection.EVENT_CONNECT:
				_finish_net_probe(true)
			elif ev[0] == ENetConnection.EVENT_DISCONNECT or ev[0] == ENetConnection.EVENT_ERROR:
				_finish_net_probe(false)
			else:
				_timer -= delta
				if _timer <= 0.0:
					_finish_net_probe(false)


# --- hosting -----------------------------------------------------------

func host() -> void:
	_hosting = true
	var peer: ENetMultiplayerPeer = null
	for i in range(RoomCode.PORT_SLOTS):
		peer = ENetMultiplayerPeer.new()
		if peer.create_server(RoomCode.BASE_PORT + i, MAX_PLAYERS) == OK:
			_game_port = RoomCode.BASE_PORT + i
			break
		peer = null
	if peer == null:
		room_opened.emit("", "Couldn't open a game port; close other running hosts.")
		return
	multiplayer.multiplayer_peer = peer
	_responder = LanDiscovery.Responder.new()
	if _responder.start():
		_responder.game_port = _game_port
	else:
		_responder = null
	room_opened.emit("", "Opening room...")
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_setup)


# Runs on _upnp_thread. Returns the UPNP instance when a port mapping
# exists (so _stop_upnp can remove it), or null when nothing to undo.
func _upnp_setup() -> UPNP:
	var lan_code: String = RoomCode.encode(LanDiscovery.local_ipv4(), _game_port)
	var upnp := UPNP.new()
	var err := upnp.discover()
	if err != UPNP.UPNP_RESULT_SUCCESS or upnp.get_gateway() == null \
			or not upnp.get_gateway().is_valid_gateway():
		_apply_host_result.call_deferred(lan_code, "LAN only: no UPnP router found.")
		return null
	if upnp.add_port_mapping(_game_port, _game_port, "Shotgun Drift", "UDP", 0) != UPNP.UPNP_RESULT_SUCCESS:
		_apply_host_result.call_deferred(lan_code, "LAN only: router refused UPnP.")
		return null
	var ip := upnp.query_external_address()
	if ip == "":
		_apply_host_result.call_deferred(lan_code, "LAN only: couldn't read the public IP.")
	else:
		_apply_host_result.call_deferred(RoomCode.encode(ip, _game_port), "Internet ready.")
	return upnp


func _apply_host_result(code: String, status: String) -> void:
	if not _hosting:
		return  # left the game before discovery finished
	_room_code = code
	if _responder != null:
		_responder.code = code
	room_opened.emit(code, status)


func _stop_upnp() -> void:
	if _upnp_thread == null:
		return
	var upnp: UPNP = _upnp_thread.wait_to_finish()
	_upnp_thread = null
	if upnp != null:
		upnp.delete_port_mapping(_game_port, "UDP")


# --- joining -----------------------------------------------------------

func begin_join(join_string: String) -> void:
	if _state != JoinState.IDLE:
		return
	var input := join_string.strip_edges()
	if input.contains("."):
		# Dev escape hatch: a literal IP joins directly on the base port.
		_decoded = {"ip": input, "port": RoomCode.BASE_PORT}
		_begin_net_probe()
		return
	_decoded = RoomCode.decode(input)
	if _decoded.is_empty():
		join_failed.emit("That doesn't look like a room code. Check it and try again.")
		return
	_prober = LanDiscovery.Prober.new()
	if _prober.start(RoomCode.normalize(input)):
		_state = JoinState.LAN_PROBE
		_timer = LAN_PROBE_TIME
		join_status.emit("Looking for the room...")
	else:
		_prober = null
		_begin_net_probe()


func _begin_net_probe() -> void:
	join_status.emit("Connecting...")
	_probe_conn = ENetConnection.new()
	if _probe_conn.create_host(1) != OK:
		_probe_conn = null
		join_failed.emit(NOT_REACHABLE)
		return
	_probe_peer = _probe_conn.connect_to_host(_decoded["ip"], _decoded["port"])
	if _probe_peer == null:
		_probe_conn.destroy()
		_probe_conn = null
		join_failed.emit(NOT_REACHABLE)
		return
	_state = JoinState.NET_PROBE
	_timer = PROBE_TIMEOUT


func _finish_net_probe(reached: bool) -> void:
	_state = JoinState.IDLE
	if reached and _probe_peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
		_probe_peer.peer_disconnect_now(0)
	_probe_conn.destroy()
	_probe_conn = null
	_probe_peer = null
	if reached:
		_target = _decoded
		join_validated.emit()
	else:
		join_failed.emit(NOT_REACHABLE)


func complete_join() -> void:
	if _target.is_empty():
		push_error("complete_join without a validated target")
		return
	var peer := ENetMultiplayerPeer.new()
	peer.create_client(_target["ip"], _target["port"])
	multiplayer.multiplayer_peer = peer


func cancel_join() -> void:
	if _prober != null:
		_prober.stop()
		_prober = null
	if _probe_conn != null:
		if _probe_peer != null and _probe_peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
			_probe_peer.peer_disconnect_now(0)
		_probe_conn.destroy()
		_probe_conn = null
		_probe_peer = null
	_state = JoinState.IDLE


# --- teardown ----------------------------------------------------------

func leave() -> void:
	cancel_join()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _responder != null:
		_responder.stop()
		_responder = null
	_stop_upnp()
	_hosting = false
	_room_code = ""
	_target = {}
	_decoded = {}


func _exit_tree() -> void:
	_stop_upnp()
