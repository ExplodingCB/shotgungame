# Weapon Assortment + Rarity System — Design

Date: 2026-06-10

## Goal

Add 12 new weapons from the existing art packs (ARs, SMGs, heavy pistols,
shotguns, grenade launcher, RPG) behind a rarity system that controls how
often each weapon spawns as a pickup. Each rarity has a signature color
shown on the pickup (glow ring) and in the HUD (weapon name).

## Rarity tiers

| Rarity    | Color                | Spawn weight |
|-----------|----------------------|--------------|
| Common    | gray  (0.75,0.78,0.80) | 42 |
| Uncommon  | green (0.35,0.90,0.40) | 30 |
| Rare      | blue  (0.30,0.60,1.00) | 18 |
| Epic      | purple(0.75,0.40,1.00) | 8  |
| Legendary | gold  (1.00,0.65,0.15) | 2  |

A weapon pickup rolls rarity by weight, then picks uniformly among that
tier's weapons. When a weapon pickup is collected, its respawn re-rolls a
fresh weapon (shell packs always respawn as shell packs), so rare finds
stay rare and the arena stays varied.

## Roster

Existing: Shotgun (Common), Pistol (sidearm, never spawns), SMG/MP5
(Common), Sniper (Rare).

New: UZI (Common); AK-47, M4 Carbine, Sawed-Off, Revolver (Uncommon);
Desert Eagle, FN SCAR, P90 (Rare); KRISS Vector, SPAS-12, Grenade
Launcher (Epic); RPG (Legendary).

Flavor notes: Sawed-Off has huge recoil — it doubles as a movement tool.
Grenade Launcher lobs slow grenades that bounce off asteroids and walls up
to 3 times and explode on enemies/players or when the fuse runs out. RPG
fires a rocket that explodes on anything it touches (220px radius, hurts
the shooter too) with monstrous recoil — half weapon, half engine.

## Architecture

- **`scripts/weapon_db.gd`** (`class_name WeaponDB`) — single source of
  truth: `Weapon` enum, per-weapon stat dictionaries (now with `name`,
  `rarity`, `fire_mode`, explosion params), rarity colors/weights, and
  static `roll_weapon()` / `rarity_color()`. `player.gd`, `pickup.gd`,
  `hud.gd`, and `main.gd` all read from it; the duplicated texture table
  in `pickup.gd` and the name list in `hud.gd` go away.
- **`projectile.gd`** — gains optional explosion (`explode_radius`,
  `explode_damage`: circle query, damage + knockback from center, scaled
  break-effect fx, pitched-down 20-gauge boom) and bouncing (`bounces`:
  reflect off world, explode on players/enemies or when fuse/bounces run
  out). Remote visual-only copies show fx but deal no damage, matching
  the existing `deals_damage` convention.
- **`player.gd`** — `_fire_fx` becomes data-driven on `fire_mode`
  (`pellets` / `beam` / `rocket`) with per-weapon smoke amounts; shotgun
  spin-kick becomes a data flag (`spin_kick`) shared by Sawed-Off/SPAS.
- **`pickup.gd`** — texture from WeaponDB; weapon pickups draw a soft
  rarity-colored glow disc + ring behind the gun sprite.
- **`hud.gd`** — weapon names render in their rarity color.
- **`main.gd`** — `PICKUP_SET` keeps 8 shell packs; 10 weapon pickups are
  rolled through `WeaponDB.roll_weapon()` at world spawn.

Multiplayer: pickups already replicate by integer `kind`; weapon ids and
ammo sync unchanged. Explosions run only on the shooting peer's lethal
projectile (same as bullets), so damage lands exactly once.

## Testing

`test/smoke_test.gd` extended to give and fire every weapon in the DB
(including explosive paths) headlessly; existing wave + UPnP tests keep
passing.
