class_name NetBackend
extends Node

# One implementation per matchmaking transport: DirectBackend (ENet +
# room codes) today, Steam or Xbox lobbies later. A backend owns the
# MultiplayerPeer lifecycle; join strings are opaque to everything
# above this class, so a Steam lobby id rides the same pipe as a code.
#
# Lifecycle:
#   host()           in the game scene; opens the room, emits room_opened
#                    as the code/status evolve (e.g. while UPnP negotiates)
#   begin_join(s)    from the menu; validates the room is reachable
#                    without touching the scene, then emits join_validated
#                    or join_failed
#   complete_join()  in the game scene; creates the real client peer to
#                    the address begin_join validated
#   cancel_join()    abandons a begin_join in flight
#   leave()          tears everything down, back to the offline peer

signal room_opened(code: String, status: String)
signal join_status(message: String)
signal join_validated
signal join_failed(reason: String)


func host() -> void:
	push_error("NetBackend.host not implemented")


func begin_join(_join_string: String) -> void:
	push_error("NetBackend.begin_join not implemented")


func complete_join() -> void:
	push_error("NetBackend.complete_join not implemented")


func cancel_join() -> void:
	pass


func leave() -> void:
	pass


# The code players share to bring friends in; "" until the room is open.
func current_code() -> String:
	return ""
