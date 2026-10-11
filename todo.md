# todo

## Port: what's left

See [`PORTING.md`](PORTING.md) for agent-sized tasks, dependencies, source and
target files, acceptance tests, parallel-work guidance, deferred decisions, and
the final retirement checklist.

Next safe parallel wave:

- [x] AnimationPlayer plus Pogo stride (Task 1).
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

## Room cell queries

`kind_at_cell` and `is_solid_cell` ask the physics space, so big-tile shapes,
flips, and transposes stay in the engine. Grapple and pogo tiles are sensor
layers. Props with those surfaces are still found by their box.

## Move character sprites to Sprite2D + AnimationPlayer

`CharacterSprite` now uses `Sprite2D` plus `AnimationPlayer`. Generated method
keys are re-emitted through `frame_event`; audio remains Task 2.

An `AnimationPlayer` can key other properties on the same timeline: audio and
method-call tracks for footsteps, plus effects, squash and stretch, or offsets.
Each clip keys `texture`, `region_rect`, and `offset`, so clips with different
sheets need no shared canvas (the AtlasTexture margins in `sync_art.gd` go away).

- [x] `sync_art.gd` writes an `AnimationLibrary` per anim document instead of SpriteFrames.
- [x] Re-syncing replaces only generated texture, region, pivot, visual-stride,
  and animation-event tracks and keeps tracks added in Godot.
- [x] Anim-document `events` become method-call keys that retain the presentation
  event boundary.
- [x] `CharacterSprite` keeps choosing clips the same way (the ability's clip,
  then the body's movement clip, then `fallback`, else the placeholder) and plays them on the player.
- [x] Update `art_smoke.gd`: the clip, pivot, flip, and placeholder checks carry
  over; the frame-event checks move to the new tracks.

Not needed for this: `AnimationTree`. Clip choice is simple and driven by code,
and crossfades do little for pixel flipbooks. Revisit if land or run-start
transition clips arrive.
