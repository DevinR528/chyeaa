# tests

Headless tests for movement feel, abilities, contacts, moving platforms, and
piece stitching. Test-only scenes belong beside the scripts in this folder.

- `locomotion_smoke.gd` — input latching, run, jump, dash, coyote, buffer, jump
  cut, and Pogo's constant physical speed during its visual stride.
- `demo_room_smoke.gd` — spawn, landing, character switching and surfaces, and
  death, exit, and fall restarts in the demo room. Does not pin authored room content.
- `abilities_smoke.gd` — grapple latch, pull, jump-off, and solid block; pogo down
  bounce and side pop. Builds its small rooms in code.
- `triggers_smoke.gd` — the player's touch sensor reports exit, death, and kill
  plane contact, and ignores flush edges.
- `reach_overlay_smoke.gd` — the reach overlay's jump and dash numbers match real
  movement, and its wall probe measures the gap to a wall.
- `props_smoke.gd` — riding a moving platform, jumping into a descending one,
  breakables, grapple and pogo on props, death props, per-character exclusion,
  crushing (and that one solid is not a crush), spin layout, switch modes,
  room-scoped all/any power and its four effects, falling blocks, and
  moving-platform cargo.
- `actors_smoke.gd` — walker turns at walls and ledges, stomp and side hurt,
  pickup and throw, ball bounces off the floor, walkers it kills, and other
  balls, standing on an idle ball, and a thrower's immunity to their own ball.
- `art_smoke.gd` — synced AnimationLibraries match their anim documents (frame
  timing, textures, regions, pivots, event/visual-stride keys, and
  authored-track preservation),
  character sprites pick clips, flip, show the placeholder, and fire frame
  events, and backdrop layers land where the
  prototype's placement put them and follow the camera. Run `sync_art.gd` first.
- `audio_smoke.gd` — event-to-stream mapping, landing volume/pitch, pooled
  one-shots, replacing/stopping the footstep voice, and reconnecting after a
  character switch, with device playback disabled.
- `block_terrain_smoke.gd` — 32 px art tiles on 8 px cells (also flipped and
  transposed) answer the room's cell queries wherever physics says they collide,
  hold the player up, and death blocks are a hazard. Every tile in the demo's
  hand-made TileSet has collision matching its kind, and
  none overlaps Terrain.
- `test_room_builder.gd` — preloaded helper that builds rooms, props, actors, and
  players in code.

Run one with the console build so the exit code is real:
`Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/<name>.gd`
