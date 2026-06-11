# Level Variety — Design Spec

**Date:** 2026-06-10
**Status:** Approved (design walked through section-by-section with user; user waived final spec review)

## Goal

Versus rounds (couch LOCAL + online HOST/JOIN) rotate through hand-authored arenas with
different shapes, permanent obstacles, and hazards — SpiderHeck-style level variety.
Solo wave mode keeps the classic arena unchanged.

## Decisions

| Question | Decision |
|---|---|
| Scope | Versus rounds only; solo always plays Classic |
| Selection | Random per round, never the same level twice in a row |
| Ingredients | Arena shapes/sizes, static obstacles, vortexes, bounce pads, kill-laser strips |
| Vortex behavior | Constant pull ramping toward center + deadly core; tugs rocks and pickups too |
| Asteroids | Per-level density multiplier (0.0 = none, 1.0 = current spread) |
| Architecture | Approach A: scene-based levels + registry (see below) |

## Architecture

### New components

- **`scripts/level_db.gd`** — registry like `WeaponDB`. `LEVELS: Dictionary` mapping
  `int id -> {scene_path: String, name: String, bounds: Rect2, spawns: Array[Vector2],
  asteroid_density: float}`. Id 0 = Classic (current 3200×1800 box, density 1.0).
- **`levels/*.tscn`** — one scene per level containing `Walls` (StaticBody2D),
  `Obstacles` (StaticBody2D blocks/pillars), and hazard component instances.
  Pure local geometry — no MultiplayerSpawner; every peer instances the same scene
  deterministically.
- **`scripts/level_host.gd`** — node in `main.tscn` replacing the hardcoded `Walls`.
  `load_level(id)`: frees current level + leftover rocks/pickups, instances the new
  scene, exposes `bounds`/`spawns`/`asteroid_density` to dependents.

### Hazard components (`scenes/hazards/`)

Reusable self-contained scenes (visual + behavior + collision), tuned via exported vars
per level instance. Initial numbers below are first-pass tuning values.

- **`vortex.tscn` / `vortex.gd`** — pull field (radius ~450px) with force ramping
  toward center (inverse-square-ish, capped at the rim); deadly core (~40px,
  60 damage per 0.5s tick — same tick cadence as the shrink zone). Pull applied by whoever simulates each body:
  players integrate it in their own movement, host applies to rocks/pickups.
  Damage is server-authoritative. Does NOT pull projectiles (aim stays readable).
  Visual: swirling particle spiral, darkened core, slow rotation.
- **`bounce_pad.tscn` / `bounce_pad.gd`** — Area2D strip; entering bodies get
  velocity set (not added) to ~1100px/s along pad direction; ~0.3s per-body cooldown.
  Applied by the simulating peer; deterministic, no extra sync.
- **`laser_strip.tscn` / `laser_strip.gd`** — line hazard between two points.
  Exported cycle: always-on or blinking (default 0.6s warning glow → 1.4s lethal →
  1.5s off). Blink clock starts at FIGHT phase on every peer; damage (~30 per 0.25s
  tick) is server-side only. Damages players and enemy ships; slowly destroys rocks.

Static obstacles are plain StaticBody2D collision in the level scene; projectiles
already collide with walls, so ricochet weapons work for free.

### What becomes per-level (was global)

- `ARENA` const (`main.gd:31`, duplicated in `shrink_zone.gd`) → active level `bounds`
- `PLAYER_SPAWNS` (`main.gd:38`) → active level `spawns` (≥4 per level, placed clear
  of obstacles)
- Shrink zone starts at level bounds, contracts to its center (damage-based rect,
  works over non-rectangular arenas)
- Shared camera (couch) + per-player camera limits derive from level bounds
- Asteroid spawn counts scale by `asteroid_density`

### Round flow

1. ROUND_END → host picks next level id (random, ≠ current); id rides the existing
   `_net_phase` RPC payload for COUNTDOWN.
2. All peers run `level_host.load_level(id)`; host respawns asteroids at
   `density × standard counts` via the existing asteroid spawner path (syncs as today).
3. Players revive at the new level's spawns → countdown → fight.
4. Solo/wave mode: `load_level(0)` once, never rotates. Zero behavior change.
5. Late joiners: `_on_peer_joined` catch-up RPC includes current level id; joiner
   builds the arena before receiving phase state.

### Spawn safety

Asteroid, pickup, and chaos-event spawn positions are validated with a physics query
against obstacle geometry (retry up to 12 times, then skip that spawn). Player spawn
points are hand-placed per level and trusted.

## Level Roster (8 levels, all approved)

| # | Name | Bounds | Contents |
|---|---|---|---|
| 0 | Classic | 3200×1800 | Standard rocks (density 1.0). Solo arena; always in rotation. |
| 1 | The Cross | plus-shape in ~3200×1800 | Four dead-end wings; pillar blocks at the intersection corners; light rocks. |
| 2 | The Donut | 3200×1800 | One huge indestructible rounded block centered; fights orbit it; medium rocks around the ring. |
| 3 | Vortex Alley | 3600×1000 corridor | Twin vortexes at ⅓ and ⅔ across the middle lanes; no rocks; spawns at opposite ends. |
| 4 | The Grinder | 3200×1800 | Blinking laser strips slice the box into 6 cells on offset rhythms; light rocks. |
| 5 | Pinball | ~2300×1400 | Bounce pads on all four walls flinging across the arena; two diamond bumper obstacles; no rocks. |
| 6 | Binary Stars | 3200×1800 | Twin vortexes left and right; dense asteroid spine down the middle (gets eaten by the vortexes over the round). |
| 7 | Shoebox | 1700×1100 | One blinking laser bisecting it horizontally; no rocks; seconds-long rounds. |

(The cross shape is enforced by wall geometry; the shrink-zone rect simply contracts
over it.)

## Deliberate non-features

- Vortexes do not pull projectiles.
- Chaos round events unchanged — rock-rain can still hit "no-rock" levels.
- No enemy-AI obstacle avoidance needed: solo is always Classic; versus has no AI ships.
- No level-select UI/voting (random rotation only).

## Error handling

- Level scene fails to load → log error, fall back to Classic (id 0).
- Unknown level id from host (version mismatch) → Classic + warning, match continues.

## Testing (headless, existing `-s res://test/...` pattern)

- **`level_db_test`** — every registered scene loads; metadata complete; ≥4 spawns
  inside bounds and not overlapping obstacles (physics query).
- **`hazard_test`** — vortex applies pull + core damage; bounce pad flings with
  cooldown; laser damages only during lethal phase.
- **`level_rotation_test`** — no immediate repeats; level id in phase RPC payload;
  solo always loads Classic.
- Update existing smoke/round tests for the `ARENA`-const → level-bounds change.
