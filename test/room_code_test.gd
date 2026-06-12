# Headless test for the room code codec. Run with:
#   godot --headless --path . -s res://test/room_code_test.gd
extends SceneTree

var _fails := 0


func _initialize() -> void:
	_round_trips()
	_normalization()
	_rejections()
	_typo_detection()
	if _fails == 0:
		print("ROOM CODE TEST OK")
		quit(0)
	else:
		push_error("%d room code checks failed" % _fails)
		quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL: ", what)
		_fails += 1


func _round_trips() -> void:
	var samples := [
		["83.45.120.7", 7777],
		["192.168.1.42", 7792],   # last port slot
		["10.0.0.1", 7780],
		["0.0.0.0", 7777],
		["255.255.255.255", 7792],
	]
	for s in samples:
		var code: String = RoomCode.encode(s[0], s[1])
		_check(code.length() == 9 and code[4] == "-",
				"format of %s -> %s" % [s, code])
		var back: Dictionary = RoomCode.decode(code)
		_check(back.get("ip", "") == s[0] and back.get("port", 0) == s[1],
				"round trip %s -> %s -> %s" % [s, code, back])


func _normalization() -> void:
	_check(RoomCode.normalize("o1l-i O") == "01110", "lookalike mapping")
	var code: String = RoomCode.encode("83.45.120.7", 7778)
	var want: Dictionary = RoomCode.decode(code)
	for variant in [code.to_lower(), code.replace("-", ""),
			" %s " % code, code.replace("-", " ")]:
		_check(RoomCode.decode(variant) == want, "variant '%s'" % variant)


func _rejections() -> void:
	_check(RoomCode.decode("") == {}, "empty input")
	_check(RoomCode.decode("KQ7M") == {}, "too short")
	_check(RoomCode.decode("KQ7M-2PXD-44") == {}, "too long")
	_check(RoomCode.decode("KQ7M-2PXU") == {}, "invalid char U")
	_check(RoomCode.encode("1.2.3", 7777) == "", "malformed ip")
	_check(RoomCode.encode("1.2.3.4", 7776) == "", "port below range")
	_check(RoomCode.encode("1.2.3.4", 7793) == "", "port above range")


# A 4-bit checksum can't catch everything, but it must catch the vast
# majority of single-character typos so menu feedback is instant.
func _typo_detection() -> void:
	var code: String = RoomCode.normalize(RoomCode.encode("83.45.120.7", 7781))
	var caught := 0
	var total := 0
	for pos in range(8):
		for ch in RoomCode.ALPHABET:
			if ch == code[pos]:
				continue
			total += 1
			var typo := code.substr(0, pos) + ch + code.substr(pos + 1)
			if RoomCode.decode(typo) == {}:
				caught += 1
	_check(caught >= total * 9 / 10,
			"typo catch rate %d/%d below 90%%" % [caught, total])
