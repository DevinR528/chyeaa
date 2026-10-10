# todo

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
