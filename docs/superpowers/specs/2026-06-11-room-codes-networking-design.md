# Networking Overhaul: Room Codes

2026-06-11, approved direction: self-contained codes (zero infrastructure), picked by user.

## Goals
1. Replace IP entry with room codes: host gets a code, friends type the code.
2. Support multiple hosts on the same network (and same machine).
3. Prefer LAN when host and joiner share a network (also fixes NAT hairpin failures,
   where joining a same-network host through its public IP silently fails).
4. Keep internet play free via UPnP, no servers, no accounts.
5. Structure the code so Steam/Xbox "join friend" backends slot in later without rework.

## Room code format (`scripts/net/room_code.gd`, class_name RoomCode)
- 40 bits packed: IPv4 address (32) + port index (4, port = 7777 + index) + checksum (4).
- Rendered as 8 Crockford base32 chars, displayed `XXXX-XXXX` (no I, L, O, U; decode
  maps o->0, i/l->1; input is case-insensitive and ignores dashes/spaces).
- Checksum is a 4-bit fold of the 36 payload bits: catches typos instantly in the menu.
- The encoded address is the host's public IP when UPnP succeeds, else its LAN IP
  (first private non-loopback IPv4 from `IP.get_local_addresses()`), so a LAN-only
  host still has a working code.
- Pure static functions, fully covered by a headless test.
- Codes are opaque strings everywhere outside the direct backend; UI and Net never
  parse them. A future Steam backend can hand out its own join strings through the
  same pipe.

## Backend abstraction (`scripts/net/net_backend.gd` + `scripts/net/direct_backend.gd`)
- `NetBackend` (abstract, Node): `host()`, `join(code)`, `leave()`, plus signals
  `room_opened(code, status)`, `status_changed(msg)`, `join_failed(reason)`. It owns
  creating and tearing down the `MultiplayerPeer`.
- `DirectBackend` is the only implementation now: ENet + UPnP + room codes + LAN
  discovery. All UPnP logic moves here out of `net.gd`.
- `Net` keeps its public surface (`start_host()`, `start_join(code)`, `leave()`,
  `host_info` for the HUD) and delegates to the active backend. Adding Steam later
  means one new backend class and a selection rule, nothing else moves.
- Dev escape hatch: if the join input parses as an IP (contains a dot), connect to it
  directly on port 7777. Keeps localhost testing one keystroke away.

## Multiple hosts per network
- Game port: try 7777..7792, bind the first free one; the index goes in the code.
  UPnP maps whichever port was bound.
- Discovery responder: each host binds the first free UDP port in 7800..7815.

## LAN discovery (`scripts/net/lan_discovery.gd`)
- Host side: UDP responder answers `{"q":"sgdrift","c":"<code>"}` with
  `{"a":"sgdrift","p":<game port>}` only when the code matches its own.
- Join side: broadcast the query to 255.255.255.255 and per-interface subnet
  broadcasts, all 16 discovery ports, wait up to 0.8s. A reply wins: connect to the
  responder's source IP and returned port over LAN. No reply: decode the code and
  connect over the internet.

## Join flow and failure handling (new, currently absent)
The whole join is validated from the menu; the screen does not change until the
connection is confirmed.
1. Normalize code, verify checksum: bad code is rejected in the menu instantly.
2. LAN probe (0.8s), then internet connect from the decoded address, all while the
   online page shows progress ("Looking on your network...", "Connecting...").
3. Only `multiplayer.connected_to_server` moves to the game scene. A connection
   failure or 6s timeout stays in the menu and shows "Room not reachable. Check the
   code, or the host's router may not support UPnP." Today a failed join sits in an
   empty arena forever.
4. Ready handshake: because the client now connects before its game scene exists,
   the host no longer spawns ships on `peer_connected`. The client's `main._ready`
   sends a `client_ready` RPC and the host spawns the ship then (`round_manager`'s
   join hook moves to the same signal). This also closes today's latent race where
   spawn replication could beat the client's scene load.

## UI (`scripts/menu.gd`, `scripts/hud.gd`)
- Online page: code entry field (auto-uppercased, accepts dashed or plain) replaces
  the IP field; a status line shows join progress and failures.
- Host HUD: top-left shows `ROOM KQ7M-2PXD` instead of the raw IP, with the UPnP
  status line beneath while negotiating ("Opening room...", then "Internet ready" or
  "LAN only: router refused UPnP"). Code is also copyable from the pause menu.

## Known limits (accepted)
- CGNAT or UPnP-disabled routers: internet joins fail, LAN still works. The fix is a
  relay or registry; the backend abstraction is where one would plug in. Not now.
- IPv4 only. A format change would change the code length, which self-disambiguates.

## Files touched
New: `scripts/net/room_code.gd`, `scripts/net/lan_discovery.gd`,
`scripts/net/net_backend.gd`, `scripts/net/direct_backend.gd`,
`test/room_code_test.gd`, `test/lan_discovery_test.gd`.
Modified: `scripts/net.gd` (slims down, delegates), `scripts/menu.gd` (online page),
`scripts/hud.gd` (room code display), `scripts/pause_menu.gd` (show code).

## Testing
- `room_code_test`: encode/decode round-trips, checksum rejection, normalization
  (case, dashes, o/i/l mapping), LAN-IP fallback packing.
- `lan_discovery_test`: responder + prober over loopback in one headless process,
  wrong-code query gets no reply.
- Existing smoke/lobby/spectate tests stay green.
- Manual: two instances on one machine (host + LAN join via code), plus an internet
  join from a second network.
