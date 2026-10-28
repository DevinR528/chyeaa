# todo

## Port: what's left

See [`PORTING.md`](PORTING.md) for agent-sized tasks, dependencies, source and
target files, acceptance tests, parallel-work guidance, deferred decisions, and
the final retirement checklist.

Next safe parallel wave:

- [x] AnimationPlayer plus Pogo stride (Task 1).
- [x] Switch/gate/power, fall block, and track audit (Task 3).
- [x] Piece import and runtime stitching (Task 4).
- [x] Screen shake and vignette (Task 5).
- [x] Pure run-build and stat stacking model (Task 6A).
- [x] Checkpoint, potion UI, HUD, and pause (Task 6B).
- [x] Runtime diagnostics (Task 7).
- [ ] Input remap. A pause Controls page edits Godot's InputMap: replace a
  key without wiping the joypad button, and the reverse, and leave stick
  axes alone. Save the result into `user://player.cfg` and apply it on boot.
  Do not port `../idea/src/input/bindings.ts`. The Nintendo HID profile stays out.

## Use groups for room-wide broadcasts

Groups (`call_group`, `set_group`) suit one-to-many commands. Keep `ContactBox`
signals for pairwise contacts and signals for one-off facts (`died`, `hurt`).

- [ ] Hitstop freeze: `Room.freeze_entities` loops props and actors to set
  `frozen`; a `set_group` per group does it in one line.
- [ ] `Room.use_surfaces`: broadcast the character's surfaces to the
  `tile_props` group and let each prop decide its own exclusion.

Before converting, handle these:

- Groups are tree-wide. Once rooms are stitched (`pieces/`), a bare `call_group`
  reaches every loaded room. Scope by room, for example a per-room group name.
- Method and property names are strings, so a typo or rename fails silently at
  runtime instead of at parse time.
- `call_group` runs immediately. From inside a contact handler, use
  `call_group_flags` with `SceneTree.GROUP_CALL_DEFERRED` (see `ContactBox`).

Switches and powered props are not room-wide broadcasts. A switch emits its
state change, while each `Power` component resolves the requested switch ids
through its owning room and connects directly. The component reads initial
state when binding and caches later signal updates for all/any evaluation.



## HUMANS write, AI can update if fixed or something

## Game Feel

 - "Deaths of Peck" has MUCH less air movement control, this might be nice???

## Art/Animation issues

 - grappler guys run is to slow at 8fps consider
   - `"times": PackedFloat32Array(0, 0.0833, 0.1666, 0.24999, 0.3333, 0.41666, 0.4999, 0.58333),` instead of 1/8th
 - Most state transition need a 3ish frame (specifically for idle to run) "transition" animation
   - we could play these at 2-3x speed (this is typically how it's done)
 - The tileset can be slightly isometric we just can't have top/bottom on the same 32pixel tile... fucking duh
 - skid/turn animation
 - All ability BLOCKS!!!
 - finish death blocks
 - windmill sprite
 - on/off switch sprite
 - bouncy "bullet bill" thing
 - bouncy "mushroom" (a trampoline)


## Bugs

 - tapping jump and pressing left/right pogo continues your jump (much to high)
   - it's like your getting the boost from connecting with the pogo bash
 - the square hitboxes are funky
   - we catch on transitions from green solid blocks to art tileset
   - same for jumping and "catching" the edge
   - floats a solid pixel or 2 above ground
 - vignette still isn't always centered on player...
 - location trail doesn't clear when it should
 - we don't want infinite rewind...
