# Main Menu Redesign — Portal 2-Inspired Left Rail

2026-06-11 · approved by user (layout option A picked in visual companion; user waived extended brainstorm)

## Goals
1. Move ship-color picking out of the main menu — pick it where you commit to playing.
2. Replace the boxed-button centered menu with a clean Portal 2-style left rail.
3. Add an Options menu (audio sliders + display settings).

## Main menu (`scripts/menu.gd`, rewrite)
- **Left rail:** dark gradient panel (~35-40% width, fading right). Title "SHOTGUN DRIFT"
  stacked top-left with subtitle; below it a vertical list of plain text items:
  Dungeon Dive, Arena Waves, Local Versus, Play Online, Options, Quit.
- **Item style:** no boxes. Dim-bright text; hover/focus turns accent orange with a `▸`
  marker. Keyboard/gamepad navigable via focus. Version string bottom-right of screen.
- **Submenus swap in-place on the rail** (main list hides, submenu shows):
  - **Play Online:** IP field, Host button, Join button, SHIP COLOR swatch strip
    (drives `Net.preferred_color`, unchanged claim flow), Back.
  - **Options:** Music + SFX sliders (existing `Net.set_*_volume`), Fullscreen toggle,
    VSync toggle, Back.
- **Background — live arena diorama:** full-screen ambient scene behind the rail:
  nebula, drifting asteroids, and 2-3 ships flying lazy paths that occasionally
  trade tracer fire (scripted sprites + simple fx, NOT the real game sim — no Net,
  no physics, cheap on CPU). Menu music unchanged.

## Couch lobby color pick (`scripts/local_lobby.gd`)
- After a player joins (A / click / Enter), their card shows a color swatch.
- Cycle colors: d-pad left/right on that pad; left/right arrows for the keyboard player.
- Colors are unique among joined players; default = slot color. Card border/P-number
  tint follows the pick.
- `Net.start_local(roster, colors)` carries picks; `main._add_local_players` spawns
  with the picked color instead of slot index. `colors` defaults to slot order so
  existing callers/tests keep working.

## Settings backend (`scripts/net.gd`)
- Persist `display/fullscreen` and `display/vsync` in `user://settings.cfg`;
  apply on startup and on toggle.

## Files touched
`scripts/menu.gd` (rewrite), `scripts/local_lobby.gd`, `scripts/net.gd`,
`scripts/main.gd` (couch spawn line), tests as needed.

## Testing
- Existing headless tests must stay green (esp. `local_mode_test`, `color_spectate_test`).
- New/updated headless test covering couch color pick plumbing (roster+colors → spawn).
- Visual check: MCP screenshot of the new menu.
