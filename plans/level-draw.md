# Level draw: cull, then keep the picture

Status: **not started**. The stamp-footprint bitset in `Level` is already in place (`src/level/level.ts`).

Measured 2026-10-08, same machine, two Firefox profiles:

| Capture | Frames | Main-thread work | What dominated |
|---------|--------|------------------|----------------|
| 15:18 (before the bitset) | ~9 fps | ~50 ms/frame | Per-cell scan of every stamp |
| 21:31 (bitset in, stamps may overlap) | ~146 fps | ~1.2 ms/frame | Walking the whole grid, then batched `fillRect`. Stamp `drawImage` is under 1% |

The 21:31 frame gaps cluster at 5–7 ms (about 150–180 fps), with a minority at 10–13 ms. That file is not a 75 fps trace. Static tiles are still replayed every frame; they are not one `fillRect` per cell.

Play frame is 840×504 world pixels (105×63 tiles). The demo room is 384×104 tiles, 3072×832 pixels. `draw` still walks the whole grid.

## Viewport cull

`Level.draw` has no camera. Pass the world rect and only visit rows and columns that intersect it.

- Pad by one tile. Shake is a screen-pixel translate applied before the camera scale, so a tile of slack covers it.
- Flat fills cull to the tile rect.
- Stamps cull to the blit rect, not `span_w` / `span_h`. A bottom-anchored cell can hang above its footprint (`_draw_stamps`).
- This is a large cut at play zoom (about a sixth of the demo cells) and a small one in the editor when zoomed out.

## Retained picture

The grid and stamps do not change during play (`set_tile` and stamp edits are editor-only). Draw the room once into an offscreen canvas and blit it.

- Demo-sized buffer is 3072×832.
- Invalidate when cells, stamps, the terrain skin, or debug mode change. Do not rebuild every frame.
- Play and edit are different pictures: play leaves stamp cells empty so transparent pixels show the backdrop; edit keeps the kind color under the art.
- Dirty rectangles only if editor painting still hitches after the bitset. A full rebuild per stroke is the first version.
