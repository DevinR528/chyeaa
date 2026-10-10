# scenes

Godot scene files. `main.tscn` is a `RoomRunner` that plays the demo room with
the follow camera and the reach overlay (V toggles it). It spawns the character;
backtick (gamepad Back) cycles Standard, Grappler, and Pogo.

- `player/` — `standard.tscn` is the base character. `grappler.tscn` and
  `pogo.tscn` inherit it and add a body size, surface flags, stat overrides,
  and their ability node, assigned to the root's `ability` export.
  `PlaceholderBody` (box and eye) is temporary until character sprites land.
- `props/` — `block.tscn` is the base `TileProp`. `moving_platform.tscn`,
  `breakable.tscn`, and `windmill.tscn` inherit it with a component already
  added. Turn on Editable Children on an instance to tune its components.
- `rooms/` — room scenes. Each has `Terrain` (solid, death, exit for every
  character), `GrappleSurfaces`, `PogoSurfaces` (enabled per character), and a
  `Spawn` marker at the player's feet. Tiles come from `resources/tiles/kind_tiles.tres`.
  Props live under a `Props` node, walkers and throwables under `Actors`.
- `actors/` — `walker.tscn` and `throwable.tscn`. Size and tuning are exports on
  the root, so no Editable Children is needed. Both process after props and
  before the player (physics priority 5).

Planned folders: `pieces/`, `ui/`, and `dev/`. Scripts
referenced by these scenes live under `res://src/`.
