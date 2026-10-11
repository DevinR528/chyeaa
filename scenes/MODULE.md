# scenes

Godot scene files. `main.tscn` is a `RoomRunner` that plays the demo room in
front of the `eroded_earth` backdrop, with the follow camera and the reach
overlay (V toggles it). It spawns the character; backtick (gamepad Back) cycles
Standard, Grappler, and Pogo.

- `player/` — `standard.tscn` is the base character. `grappler.tscn` and
  `pogo.tscn` inherit it and add a body size, surface flags, stat overrides,
  their ability node (assigned to the root's `ability` export), and the
  `CharacterSprite` AnimationLibrary (octo for Grappler, old man for Pogo).
  `PlaceholderBody` (box and eye) shows whenever no clip resolves.
- `backgrounds/` — backdrop scenes: a `Backdrop` root with one `BackdropLayer`
  per plate, back to front. Plate effects are a `backdrop_plate.gdshader` material.
- `props/` — `block.tscn` is the base `TileProp`. `moving_platform.tscn`,
  `breakable.tscn`, and `windmill.tscn` inherit it with a component already
  added. Turn on Editable Children on an instance to tune its components.
- `tiles/` — `block_terrain.tscn`, the `BlockTerrain` layer and its hand-made
  TileSet (earth art on 8 px cells). Rooms instance it.
- `rooms/` — room scenes. Each has `BlockTerrain` (an instance of
  `tiles/block_terrain.tscn`),
  `Terrain` (8 px solid, death, and exit tiles from `resources/tiles/kind_tiles.tres`
  for detail smaller than a block), `GrappleSurfaces` and `PogoSurfaces` (8 px,
  enabled per character), and a `Spawn` marker at the player's feet. Both terrain
  layers are for every character; don't paint them over the same spot.
  Props live under a `Props` node, walkers and throwables under `Actors`.
- `actors/` — `walker.tscn` and `throwable.tscn`. Size and tuning are exports on
  the root, so no Editable Children is needed. Both process after props and
  before the player (physics priority 5).

Planned folders: `pieces/`, `ui/`, and `dev/`. Scripts
referenced by these scenes live under `res://src/`.
