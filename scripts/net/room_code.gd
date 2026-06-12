class_name RoomCode
extends RefCounted

# Self-contained room codes: the host's IPv4 and game port travel inside
# the code, so no matchmaking server exists and codes work forever.
#
# Layout, 40 bits total, rendered as 8 Crockford base32 chars (XXXX-XXXX):
#   IPv4 address (32) | port index (4, port = BASE_PORT + index) | checksum (4)

const BASE_PORT := 7777
const PORT_SLOTS := 16

# Crockford base32: no I, L, O, U, so codes survive handwriting and shouting.
const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


static func encode(ip: String, port: int) -> String:
	var idx := port - BASE_PORT
	if idx < 0 or idx >= PORT_SLOTS:
		return ""
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var payload := 0
	for p in parts:
		if not p.is_valid_int() or int(p) < 0 or int(p) > 255:
			return ""
		payload = (payload << 8) | int(p)
	payload = (payload << 4) | idx
	var bits := (payload << 4) | _checksum(payload)
	var raw := ""
	for i in range(8):
		raw = ALPHABET[bits & 31] + raw
		bits >>= 5
	return raw.substr(0, 4) + "-" + raw.substr(4, 4)


# Returns {"ip": String, "port": int}, or {} when the code is invalid.
static func decode(code: String) -> Dictionary:
	var clean := normalize(code)
	if clean.length() != 8:
		return {}
	var bits := 0
	for ch in clean:
		var v := ALPHABET.find(ch)
		if v < 0:
			return {}
		bits = (bits << 5) | v
	var payload := bits >> 4
	if (bits & 15) != _checksum(payload):
		return {}
	var ip_bits := payload >> 4
	return {
		"ip": "%d.%d.%d.%d" % [(ip_bits >> 24) & 255, (ip_bits >> 16) & 255,
				(ip_bits >> 8) & 255, ip_bits & 255],
		"port": BASE_PORT + (payload & 15),
	}


# Forgiving input: any case, dashes and spaces optional, and the
# lookalikes people type by accident map to what they meant.
static func normalize(code: String) -> String:
	var out := ""
	for ch in code.strip_edges().to_upper():
		if ch == "-" or ch == " ":
			continue
		elif ch == "O":
			out += "0"
		elif ch == "I" or ch == "L":
			out += "1"
		else:
			out += ch
	return out


# 4-bit mix of the 36-bit payload. Catches ~15/16 of typos instantly in
# the menu; the rare survivor decodes to a wrong address and fails the
# connect timeout instead, so nothing worse than a slow error happens.
static func _checksum(payload: int) -> int:
	# splitmix64 finalizer; 64-bit wraparound is fine for hashing
	var h := payload
	h = (h ^ (h >> 30)) * -0x40A7B892E31B1A47
	h = (h ^ (h >> 27)) * -0x6B2FB644ECCEEE15
	h ^= h >> 31
	return h & 15
