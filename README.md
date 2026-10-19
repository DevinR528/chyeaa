# lil-guy

Godot 4.7 project for the roguelite platformer.

Open this folder to work on the game. The TypeScript editor and pixel documents stay in the sibling repo [`../idea`](../idea).

## Art and levels

Runtime art under `assets/` is a copy of what this game uses. Paint and export in `../idea/assets` (the pixel editor already writes there), then re-run the sync from this repo:

```powershell
$godot = "C:\Users\devin\Desktop\aprog\Godot4_7\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path . --script res://src/tools/sync_art.gd
```

Piece JSON is authored in the TypeScript editor under `../idea/assets/pieces` and imported with `src/tools/import_pieces.gd`. The demo-room importers replace authored scenes; do not re-run them unless that output is the task.

Work in progress stays in `../idea/assets` until an importer references it.

Design notes are [`ideas/`](ideas/) and [`plans/`](plans/), copied from the authoring repo so they start the same. Edit them here when the note is about the game. Port checklist: [`todo.md`](todo.md) and [`PORTING.md`](PORTING.md). The open port item is input remap.

## Tests

```powershell
$godot = "C:\Users\devin\Desktop\aprog\Godot4_7\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path . --script res://tests/<suite>.gd
& $godot --headless --path . --quit-after 600
```
