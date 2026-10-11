# assets

Godot-facing art, audio, fonts, and shader source.

Level and gameplay configuration do not live here. The ongoing pixel-art export
may update art atlases and animation resources, but must not rewrite room scenes.

- `tiles/kind_tiles.png` — placeholder flat tiles, one 8x8 column per tile kind
  (atlas order is in `src/tools/import_demo_room.gd`). Repaint freely; keep the layout.
- `art/` — copied from the prototype's `../assets/art` by `src/tools/sync_art.gd`,
  only what Godot uses, at the same relative paths. Edit the source, not these
  copies; the next sync overwrites them. `<id>/<id>.animation_library.tres` is
  generated from `<id>.anim.json`: clips key texture, region, pivot offset, and
  frame timing, while authored events become presentation method keys. Re-sync
  replaces those generated tracks and preserves tracks added by hand.
  Until the JS prototype is removed, both games read this art from `../assets`.
  `earth_tileset/earth_tileset.png` is the 32 px block art for rooms' `BlockTerrain`
  TileSets, which are made in the editor; if pieces move in the sheet, update their
  atlases by hand.
- `shaders/` — `backdrop_plate.gdshader` (the prototype's desaturate then fog
  passes, combined) and `fog_texture.png` (synced from `../assets/shaders`).
