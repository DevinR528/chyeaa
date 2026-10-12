# src

Typed GDScript only. Scenes and imported assets do not live here.

## Planned domains

- `player/` — `PlayerBody` (locomotion, one script for every character),
  `MovementStats`, and abilities. An ability is a `PlayerAbility` child node that
  the body calls through hooks: `Grapple` and `PogoStrike` (with `HalfDisk`).
  Ability tuning lives in the ability's exports; character stat changes are
  `PlayerBody.stat_overrides` on top of the shared base stats. A run build
  (`run/`) recomputes a fresh copy from that baseline and never compounds. Every character
  has a `Carrier` child that picks up and throws throwables (hold and release
  interact). The player emits `hurt` and `stomped` from actor contacts.
- `input/` — action sampling, press latching, and aim.
- `rooms/` — `Room` (tile layers, cell kind and solidity queries, kill plane,
  out-of-bounds walls) and `RoomRunner` (character spawn and switching, hitstop,
  restarts on fall, exit, and death). Kind and solidity ask the physics space,
  so a shape counts wherever it reaches. Grapple and pogo tiles are sensor
  layers; props with those surfaces are queried by their box, not those layers.
- `props/` — `TileProp`: a box with a surface kind (solid, grapple, exit, death,
  pogo, or none). Optional component child nodes in `props/components/` move it
  (`OscillatingMotion`, `PathMotion`), spread the props it carries (`SpinMotion`),
  break it (`Breakable`), drop it (`FallingBehavior`), or apply switch power
  (`Power`). Carried props are child nodes. Switches emit state changes to
  room-scoped Power subscribers. The room excludes grapple and pogo props per
  character, resets props and switches on restart, and freezes props during
  hitstop. Gate and fall-block prefabs compose these behaviors. Prototype Track
  entities import as ordinary moving platforms carrying a child.
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
- `pieces/` — `PieceData`/`PieceLibrary` metadata plus seeded portal matching,
  flex corridors, overlap rejection, and runtime Room assembly in
  `generate_room.gd`. Runtime code reads imported Godot resources, never JSON.
- `presentation/` — camera, backdrop, character sprites, and the `FullscreenToggle`
  autoload. F11 grows the window through quarter-scale 840x504 steps and then
  enters fullscreen; Shift+F11 shrinks it. Manual resizing uses fractional
  nearest-neighbor scaling and keeps the 5:3 view with black bars. `Backdrop` holds
  `BackdropLayer`s (`Parallax2D`), and the runner frames them to the room so the
  prototype's top and bottom anchors hold. It sits at the lowest z_index, so room
  content with a negative z (the prototype's "behind the tiles" props) still draws
  in front of it. `CharacterSprite` plays an AnimationLibrary on its Sprite2D:
  the ability's `animation_clip()` (the body's `movement_clip()`
  while the ability is inactive), else a `fallback` clip, else the placeholder
  body shows. The body's `move_state` is its one movement state. Generated method
  keys emit `frame_event`; generated visual-stride keys trail the sprite just
  before a foot plant without changing physical run speed. `GameAudio` maps
  completed player, runner, Pogo, and animation facts to a one-shot pool and one
  replacing footstep voice. `ScreenShake` applies wall-time camera offset after
  Pogo hitstop; `Vignette` is a screen-space veil centered through the final
  camera transform.
- `debug/` — game-specific runtime overlays and readouts. `ReachOverlay` draws
  jump, dash, grapple, pogo, and wall-probe guides for the current character.
  `PlayReadout` is the same debug toggle: FPS, velocity, grounded, move and
  ability state, coyote, jump buffer, dash cooldown, and the kind under the
  feet. The mouse drags its title and collapses the body. `ContactLog` records
  stomp, hurt, and bounce decisions only when enabled. It is not the rewind log.
- `physics_layers.gd` — named collision layer bits: world, hazard, exit, fall,
  player, contact, grapple, pogo. Grapple and pogo are sensor layers (mask 0).
  The player body is on its own layer, never world.

Code that real art or animation will replace is grouped in
`#region Placeholder visuals` blocks with a note on what replaces it.
- `run/` — `RunBuild` stack counts and the exit offer (`roll_offer`), `SimStep` gameplay delta, and the potion
  belt. Stacks live on the run, not the player. Slow Time scales that delta;
  `Engine.time_scale` stays 1. Checkpoint potions plant a respawn the room reset
  does not clear; the exit does.
- `tools/` — migration and ongoing import scripts.
  `import_demo_room.gd` already ran; re-running overwrites Godot edits to the demo room.
  `import_demo_entities.gd` already ran; re-running replaces the demo room's `Props` node.
  `import_demo_actors.gd` already ran; re-running replaces the demo room's `Actors` node.
  `import_pieces.gd` is a repeatable standalone importer because pieces continue
  to be authored in the JavaScript editor; unchanged source fingerprints leave
  generated scenes/resources byte-identical.
  `sync_art.gd` is ongoing: it copies the art Godot uses from the prototype's
  `../assets` (animation, backdrop, and tile sheets) and rebuilds each animation's
  AnimationLibrary. Re-run after exporting art; generated tracks are replaced
  while other tracks survive.
- `dev/` — temporary probes used while bootstrapping the project.
