# src

Typed GDScript only. Scenes and imported assets do not live here.

## Planned domains

- `player/` — `PlayerBody` (locomotion, one script for every character),
  `MovementStats`, and abilities. An ability is a `PlayerAbility` child node that
  the body calls through hooks: `Grapple` and `PogoStrike` (with `HalfDisk`).
  Ability tuning lives in the ability's exports; character stat changes are
  `PlayerBody.stat_overrides` on top of the shared base stats. Every character
  has a `Carrier` child that picks up and throws throwables (hold and release
  interact). The player emits `hurt` and `stomped` from actor contacts.
- `input/` — action sampling, press latching, and aim.
- `rooms/` — `Room` (tile layers, cell kind and solidity queries, kill plane,
  out-of-bounds walls) and `RoomRunner` (character spawn and switching, hitstop,
  restarts on fall, exit, and death).
- `props/` — `TileProp`: a box with a surface kind (solid, grapple, exit, death,
  pogo, or none). Optional component child nodes in `props/components/` move it
  (`OscillatingMotion`, `PathMotion`), spread the props it carries (`SpinMotion`),
  or break it (`Breakable`). Carried props are child nodes. The room excludes
  grapple and pogo props per character, resets props on restart, and freezes them
  during hitstop. Switches, gates, fall blocks, and tracks are not ported yet.
- `actors/` — `RoomActor`, a `CharacterBody2D` that moves on its own, and its two
  kinds. `Walker` patrols, turns at walls and ledges, hurts on side contact, and
  dies to a stomp or a hazardous ball (`died`). `Throwable` is the ball: carried,
  thrown, solid when idle, a hazard when fast, and it bounces off floors, walls,
  ceilings, walkers it kills, and other balls (tuning in its `Bounce` exports).
  The room resets actors on restart and freezes them during hitstop.
- `contacts/` — `ContactBox`, the area every player, walker, and ball carries on
  the contact layer, and the stomp rule. Bodies talk only through its `touched`
  signal: each decides its own reaction in the handler and applies it at the
  start of its own tick, so the order Godot delivers the pair's signals never
  matters. Read the class comment before adding a contact reaction.
- `pieces/` — portal matching and room stitching.
- `presentation/` — camera, audio routing, hitstop, and screen shake.
- `debug/` — game-specific runtime overlays and readouts. `ReachOverlay` draws
  jump, dash, grapple, pogo, and wall-probe guides for the current character.
- `physics_layers.gd` — named collision layer bits: world, hazard, exit, fall,
  player, contact. The player body is on its own layer, never world.

Code that real art or animation will replace is grouped in
`#region Placeholder visuals` blocks with a note on what replaces it.
- `run/` — build stats, potions, and run-persistent state.
- `tools/` — one-time migration and ongoing pixel-art import scripts.
  `import_demo_room.gd` already ran; re-running overwrites Godot edits to the demo room.
  `import_demo_entities.gd` already ran; re-running replaces the demo room's `Props` node.
  `import_demo_actors.gd` already ran; re-running replaces the demo room's `Actors` node.
- `dev/` — temporary probes used while bootstrapping the project.
