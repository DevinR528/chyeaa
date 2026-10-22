# tests

Headless tests for movement feel, abilities, contacts, moving platforms, and
piece stitching. Test-only scenes belong beside the scripts in this folder.

- `locomotion_smoke.gd` — input latching, run, jump, dash, coyote, buffer, jump
  cut, and Pogo's constant physical speed during its visual stride.
- `run_smoke.gd` — stack caps, every build formula, summary text, no compounding
  across a character switch, jump-height apex, and slow-time distance at an
  unchanged physics tick rate.
- `rewind_smoke.gd` — input replay of a platform, walker, and throwable; the rewind
  trail and camera follow the scrub; checkpoint undo on the way back; drinking
  rewind leaves the scrub open; commit spends a charge and cancel does not;
  debug lists a free rewind; the death floor; a restart with debug history
  starts a fresh log; a run with no rewind records nothing; and a printed
  replay time for a generated room.
- `run_ui_smoke.gd` — checkpoint plant, replace, undo without a refund, unequip,
  death and fall respawn, exit cleanup, the centered pause menu, a seeded
  generated run that advances after the reward, the same pause entry returning
  to the demo, and the potion picker.
- `debug_smoke.gd` — a fixed run matches with the readout hidden or shown, and
  one stomp is captured as a contact record.
- `demo_room_smoke.gd` — spawn, landing, character switching and surfaces, and
  death, exit, and fall restarts in the demo room. The exit opens the reward
  menu and restarts after a card is picked. Does not pin authored room content.
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
- `player_data_smoke.gd` — window rect round-trip, rejected sizes, a preserved
  extra section, fullscreen keeping the windowed rect, and pulling a saved
  window onto a screen that exists.
- `presentation_smoke.gd` — quadratic screen-shake decay/replacement/direction,
  vignette screen coordinates and radii, and Pogo shake beginning after hitstop.
- `fx_smoke.gd` — death and exit effects delay the respawn and the reward menu,
  a dash does not keep its speed through that respawn, and the dash trail fades.
- `pieces_smoke.gd` — imported scene structure, portal placement, flex corridors,
  overlap rejection, caps/budget/determinism, and a generated Room in RoomRunner.
- `block_terrain_smoke.gd` — 32 px art tiles on 8 px cells (also flipped and
  transposed) answer the room's cell queries wherever physics says they collide,
  hold the player up, and death blocks are a hazard. Every tile in the demo's
  hand-made TileSet has collision matching its kind. Terrain may remain beneath
  art tiles while rooms migrate from placeholder cells.
- `test_room_builder.gd` — preloaded helper that builds rooms, props, actors, and
  players in code.

Run one with the console build so the exit code is real:
`Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/<name>.gd`
