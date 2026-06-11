# SHOTGUN DRIFT

Top-down 2D space arena where **recoil is your engine** — your shotgun blast is also your thruster. Drift through an asteroid field, grab floating weapons, dive a procedurally generated dungeon solo, or duel a friend over LAN.

## Requirements

- [Godot 4.6](https://godotengine.org/download) (standard build, no Mono needed)

## Getting started

1. Clone the repo:
   ```
   git clone https://github.com/ExplodingCB/shotgungame.git
   ```
2. Open Godot, click **Import**, and select the `project.godot` file in the cloned folder.
3. Press **F5** (or the Play button) to run. The first open takes a minute while Godot imports the assets.

## Controls

| Input | Action |
| --- | --- |
| Mouse | Aim |
| Left click | Fire (recoil pushes you the opposite way — this is how you move) |
| Scroll wheel / `1` / `2` | Switch between primary weapon and pistol |
| `A` / `D` | Spin your body |
| `Esc` | Pause menu (volume sliders, back to menu) |

## Weapons

- **Shotgun** — big blast, big recoil, limited shells. Grab red shell packs to refill.
- **Pistol** — infinite ammo, tiny scoot, short-range bullet. Your backup thruster.
- **SMG** — pickup. Very fast fire, sustained gentle thrust.
- **Sniper** — pickup. Instant beam across the whole map, massive recoil, few shots.

Picked-up weapons replace your shotgun; when they run dry they break and the shotgun comes back. Everything (weapons, ammo, asteroids) drifts and collides in zero-G.

## Singleplayer

- **Dungeon Dive** — a roguelite run through procedurally generated chambers. Rooms roll an identity (swarm dens, ambushes, minefields, vaults, sniper nests) and a layout carved by interior hull blocks. Clear each room, then fly into one of the exit gates: **Armory** (high-tier guns), **Repair Bay** (hull), or **Tech Cache** (pick a stacking perk); ordinary clears sometimes offer a small field upgrade, and the rare AUX RACK lets you carry two big guns. Eleven enemy types unlock as you go deeper, crates and wrecks crack open for loot, proximity mines guard the worst rooms, and every 5th chamber holds the Warden. Death ends the run; depth is your score.
- **Arena Waves** — the classic survival mode: endless waves of enemy ships in the open arena.

## Multiplayer (2+ players)

One player hosts, the others join — same PC, LAN, or anything that can reach port `7777`:

1. **Host**: main menu → **Host (port 7777)**.
2. **Join**: main menu → enter the host's IP (`127.0.0.1` if both instances are on the same PC) → **Join**.

Solo mode has enemy ship waves; multiplayer is PvP.

## Asset credits

Gun sprites, asteroid art, space backgrounds, spaceship sprites, gun sound effects, and music are third-party asset packs included under `assets/` and `audio/`.
