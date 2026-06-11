# Arsenal, Hazards & Maps Overhaul — Design

Date: 2026-06-10
Branch: overhaul-singleplayer
Status: Approved

## Goal

A batch of combat/arena upgrades for the versus modes: rebalance two weapons,
add two new pickups (grenades, legendary medkit), fix the two hazard
glitch-through bugs, buff vortex pull, add a teleporter hazard, and ship
three new arenas that use it.

## Prerequisite

The hazards (`scripts/hazards/laser_strip.gd`, `vortex.gd`, `bounce_pad.gd`)
and the 8-level rotation (`scripts/level_db.gd`, `levels/*.tscn`) live on
`main` (PR #3) and are not yet in `overhaul-singleplayer`. **Task 0 merges
`origin/main` into this branch** and resolves conflicts with the dungeon work.

## Tasks

### 1. Sniper → Legendary
`weapon_db.gd` SNIPER rarity `RARE` → `LEGENDARY`. No stat changes; it now
rolls at the 2% legendary weight and renders the gold rarity glow.

### 2. RPG instakill on direct impact
RPG direct-hit `damage` 40 → 999. Splash unchanged (90 dmg, 220 radius), so
only a direct rocket hit is a guaranteed kill.

### 3. Throwable grenades (dedicated key)
- Consumable, **versus/multiplayer only**. Carry cap 3, start with 0.
- New input action `grenade` (keyboard `G`, controller button), routed
  per-device for couch play like existing actions.
- Throw lobs a fuse projectile reusing `projectile.gd` bounce + fuse-explode:
  ~1.1 s fuse, 2 bounces, blast 55 dmg / 160 radius. Thrower-credited for
  kill attribution. Server-spawned via RPC like weapon throws.
- Grenade pickup: a 2-pack that spawns among the arena weapon pickups in the
  restock loop. HUD shows carried count.

### 4. Legendary healing item — "Nano-Medkit"
- Rare gold-glow pickup, versus arenas only (small chance in restock roll).
- Instant on pickup: heal to full, then **overheal to 150 HP**, decaying
  3 HP/s back down to 100.
- `player.gd`: overheal support (cap 150, decay in authority update); health
  bar shows the bonus.

### 5. Fix laser glitch-through
`laser_strip.gd` damages via a 0.25 s server tick with a zero-width segment
query — players moving ~900 px/s cross between ticks untouched.
Fix: per-physics-frame **swept check**: for each player, if the segment from
last frame's position to this frame's crosses the beam (with beam WIDTH)
while state is ON, apply PLAYER_DAMAGE. Per-player damage cooldown (~0.35 s)
so a hit isn't applied every frame. Rock damage keeps the coarse tick.
Same authority model as today (server applies damage).

### 6. Fix vortex glitch-through + stronger pull
- Core kill check is a 0.5 s tick over a ~54 px radius — players skip ~450 px
  between checks. Fix: per-frame swept-path test against the core circle.
- Pull buff: falloff quadratic `k²` → linear `k`, base `pull` 900 → 1100.
  Mid-range pull becomes meaningful; inner third takes real thrust to escape.

### 7. Teleporter hazard (new)
`scripts/hazards/teleporter.gd` — paired portals:
- Node2D pair linked by export/NodePath; entering one's radius teleports you
  to the twin.
- Speed preserved, velocity redirected along the exit portal's facing.
- ~0.8 s re-entry cooldown per body to prevent ping-ponging.
- Each peer teleports its locally controlled players (vortex pattern);
  identical geometry needs no sync. Distinct-color swirl visuals.
- Players only (rocks/pickups unaffected) to keep it simple and readable.

### 8. Three new arenas (LevelDB ids 8–10)
1. **Wormhole** — open box, two portal pairs linking opposite corners,
   light rocks. Teleporter showcase.
2. **Gauntlet** — wide corridor sliced by blinking laser strips, with a
   portal shortcut that skips the laser wall.
3. **Maelstrom** — large central vortex ringed by lasers; rim portals for
   slingshot plays.

Each follows the existing level pattern: scene in `levels/`, entry in
`LevelDB.LEVELS` (bounds, spawns, asteroid_density), auto-joins rotation
via `pick_next()`.

## Order & verification

Tasks land in the order above, one commit each. Hazard fixes (5, 6) land
before the maps that use them (8). Verify by launching the game (solo/couch
versus) after each task; hazard fixes verified by flying through a laser/
vortex core at top speed.
