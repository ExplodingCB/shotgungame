class_name LanDiscovery
extends RefCounted

# LAN room discovery over UDP. Hosts answer "who has room X?" broadcasts,
# so a joiner on the same network connects directly instead of bouncing
# off the router's public IP (which most home routers refuse anyway).
#
# Each host binds its own responder port from a small range, so several
# hosts can share one network or even one machine. Joiners spray the
# query across the whole range.

const PORT_BASE := 7800
const PORT_SLOTS := 16
const MAGIC_QUERY := "sgdrift_q"
const MAGIC_REPLY := "sgdrift_a"

# RefCounted on purpose: no scene-tree dependency, the owner pumps
# poll() each frame, and tests drive both ends in one process.


class Responder:
	extends RefCounted

	var code := ""      # set once the room code is known; silent until then
	var game_port := 0
	var _socket := PacketPeerUDP.new()

	func start() -> bool:
		for i in range(LanDiscovery.PORT_SLOTS):
			if _socket.bind(LanDiscovery.PORT_BASE + i) == OK:
				return true
		return false

	func poll() -> void:
		while _socket.get_available_packet_count() > 0:
			var msg: Variant = JSON.parse_string(
					_socket.get_packet().get_string_from_utf8())
			if typeof(msg) != TYPE_DICTIONARY:
				continue
			if msg.get("q", "") != LanDiscovery.MAGIC_QUERY:
				continue
			if code == "" or RoomCode.normalize(str(msg.get("c", ""))) != RoomCode.normalize(code):
				continue
			_socket.set_dest_address(_socket.get_packet_ip(), _socket.get_packet_port())
			_socket.put_packet(JSON.stringify(
					{"a": LanDiscovery.MAGIC_REPLY, "p": game_port}).to_utf8_buffer())

	func stop() -> void:
		_socket.close()


class Prober:
	extends RefCounted

	var _socket := PacketPeerUDP.new()

	func start(room_code: String) -> bool:
		if _socket.bind(0) != OK:  # ephemeral port, just to hear replies
			return false
		_socket.set_broadcast_enabled(true)
		var payload := JSON.stringify(
				{"q": LanDiscovery.MAGIC_QUERY, "c": room_code}).to_utf8_buffer()
		# Global broadcast only leaves one interface on Windows, so also
		# hit each interface's assumed /24 broadcast, plus loopback for
		# two instances on one machine.
		var targets := {"255.255.255.255": true, "127.0.0.1": true}
		for addr in IP.get_local_addresses():
			if addr.count(".") == 3 and not addr.begins_with("127."):
				var p := addr.split(".")
				targets["%s.%s.%s.255" % [p[0], p[1], p[2]]] = true
		for t in targets:
			for i in range(LanDiscovery.PORT_SLOTS):
				_socket.set_dest_address(t, LanDiscovery.PORT_BASE + i)
				_socket.put_packet(payload)
		return true

	# Returns {"ip": String, "port": int} once a host answers, else {}.
	func poll() -> Dictionary:
		while _socket.get_available_packet_count() > 0:
			var msg: Variant = JSON.parse_string(
					_socket.get_packet().get_string_from_utf8())
			if typeof(msg) == TYPE_DICTIONARY and msg.get("a", "") == LanDiscovery.MAGIC_REPLY:
				var port := int(msg.get("p", 0))
				if port > 0:
					return {"ip": _socket.get_packet_ip(), "port": port}
		return {}

	func stop() -> void:
		_socket.close()


# Best LAN address to put in a room code when UPnP is unavailable.
static func local_ipv4() -> String:
	var v4: Array[String] = []
	for addr in IP.get_local_addresses():
		if addr.count(".") == 3 and not addr.begins_with("127.") \
				and not addr.begins_with("169.254."):
			v4.append(addr)
	for prefix in ["192.168.", "10.", "172."]:
		for addr in v4:
			if addr.begins_with(prefix):
				return addr
	return v4[0] if not v4.is_empty() else "127.0.0.1"
