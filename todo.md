# todo

## Port: what's left

See [`PORTING.md`](PORTING.md) for agent-sized tasks, dependencies, source and
target files, acceptance tests, parallel-work guidance, deferred decisions, and
the final retirement checklist.

Next safe parallel wave:

- [ ] AnimationPlayer plus Pogo stride (Task 1).
- [ ] Switch/gate/power, fall block, and track audit (Task 3).
- [ ] Pure run-build and stat stacking model (Task 6A).

## Use groups for room-wide broadcasts

Groups (`call_group`, `set_group`) suit one-to-many commands. Keep `ContactBox`
signals for pairwise contacts and signals for one-off facts (`died`, `hurt`).

- [ ] Hitstop freeze: `Room.freeze_entities` loops props and actors to set
  `frozen`; a `set_group` per group does it in one line.
- [ ] `Room.use_surfaces`: broadcast the character's surfaces to the
  `tile_props` group and let each prop decide its own exclusion.
- [ ] Switches and gates: a switch calls its channel's group
  (`&"gate_" + channel`) instead of holding references to its gates.

Before converting, handle these:

- Groups are tree-wide. Once rooms are stitched (`pieces/`), a bare `call_group`
  reaches every loaded room. Scope by room, for example a per-room group name.
- Method and property names are strings, so a typo or rename fails silently at
  runtime instead of at parse time.
- `call_group` runs immediately. From inside a contact handler, use
  `call_group_flags` with `SceneTree.GROUP_CALL_DEFERRED` (see `ContactBox`).

## Room cell queries: build a lookup table if they get slow

`kind_at_cell` and `is_solid_cell` scan neighbouring cells for big tiles' collision
(5x5 on BlockTerrain). About 9 us per query; a grapple throw makes about 54 per
tick (about 0.5 ms). Fine today; do this if profiling says otherwise.

- [ ] In `Room._ready`, build each layer's 8 px cell -> kind and solid table once,
  and cache `cell_bounds()`. Queries still skip disabled layers, so a character
  switch needs no rebuild; each room builds its own.
- [ ] Anything that paints tiles at runtime (breakable terrain) must update the
  table for the cells it changes.

## Move character sprites to Sprite2D + AnimationPlayer

Do this with footstep sounds, the first thing that needs more than a flipbook.
`CharacterSprite` is an `AnimatedSprite2D` today, and frame events ride along as
SpriteFrames metadata (`frame_events`) re-emitted as its `frame_event` signal.

An `AnimationPlayer` can key other properties on the same timeline: audio and
method-call tracks for footsteps, plus effects, squash and stretch, or offsets.
Each clip keys `texture`, `region_rect`, and `offset`, so clips with different
sheets need no shared canvas (the AtlasTexture margins in `sync_art.gd` go away).

- [ ] `sync_art.gd` writes an `AnimationLibrary` per anim document instead of SpriteFrames.
- [ ] Re-syncing must replace only the tracks the tool generated (sprite
  `texture`, `region_rect`, `offset`, `frame`) and keep tracks added in Godot.
  This merge is the risky part; test that a hand-added track survives a re-sync.
- [ ] Turn anim-document `events` into method-call or audio keys, and drop the
  `frame_events` metadata and the `frame_event` signal.
- [ ] `CharacterSprite` keeps choosing clips the same way (the ability's clip,
  then the body's movement clip, then `fallback`, else the placeholder) and plays them on the player.
- [ ] Update `art_smoke.gd`: the clip, pivot, flip, and placeholder checks carry
  over; the frame-event checks move to the new tracks.

Not needed for this: `AnimationTree`. Clip choice is simple and driven by code,
and crossfades do little for pixel flipbooks. Revisit if land or run-start
transition clips arrive.
