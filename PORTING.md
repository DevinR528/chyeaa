# Remaining port work

This is the implementation handoff for agents finishing the TypeScript-to-Godot
port. `todo.md` is the short checklist; this file owns scope, dependencies,
source references, and acceptance criteria.

The behavior source is the prototype in `../idea/src` and `../idea/assets`. The target is
this Godot 4.7 project. Preserve behavior and tuning during the port; redesigns
belong in a later task.

## Before assigning work

- Give one numbered task below to one agent. Do not ask an agent to "finish the
  port."
- Use isolated branches/worktrees for parallel agents. The current working tree
  has ongoing authored scene and art changes; agents must not clean, revert, or
  regenerate unrelated files.
- Read the nearest `MODULE.md` before searching or editing a folder.
- Add or extend a headless test for behavior. Do not use browser tests.
- Do not run `import_demo_room.gd` or `import_demo_entities.gd` against the
  authored demo unless the task explicitly owns that output; those scripts
  replace editor-authored content.
- Do not restructure `scenes/tiles/block_terrain.tscn`. It is hand-authored.
- Keep typed GDScript, native pixel/world coordinates, and the existing hybrid
  composition: room entities own optional component nodes.
- Keep rectangle collision until task 10 is approved.

Godot console:

```powershell
$godot = "C:\Users\devin\Desktop\aprog\Godot4_7\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path . --script res://tests/<suite>.gd
```

Before handoff, run the changed suite, every suite reasonably affected by the
change, and this boot check:

```powershell
& $godot --headless --path . --quit-after 600
```

Current suites are `abilities_smoke`, `actors_smoke`, `art_smoke`,
`audio_smoke`, `block_terrain_smoke`, `debug_smoke`, `demo_room_smoke`,
`fx_smoke`, `locomotion_smoke`, `pieces_smoke`, `player_data_smoke`, `presentation_smoke`, `props_smoke`,
`reach_overlay_smoke`, `rewind_smoke`, `run_smoke`, `run_ui_smoke`, and `triggers_smoke`.

## Still to do

Tasks 1-7 below are done. Behavior questions go to `../idea/src`.

Rewind and generated runs are in. Rewind matches the TypeScript replay: one
start-of-history snapshot of the player's primitive fields, then an input log.
A backward scrub restores that start and re-simulates; a forward scrub
continues from the cursor. The per-second snapshot cache is not a task.
Pause can start a generated run, and the exit loads `seed + 1` at the same
difficulty. Do not reopen either.

The open port item is input remap. See `todo.md`: a pause Controls page edits
Godot's InputMap, saves into `user://player.cfg`, and applies it on boot. Do not
port `../idea/src/input/bindings.ts`. The Nintendo HID profile stays out.

### A run advances from pause

`scenes/main.tscn` still boots the authored demo. Pause can start a generated
run: difficulty 3, piece count `[1, 2]`, random seed (tests pass one). The
exit effect opens the reward menu titled with the level, then the next room
uses `seed + 1` at the same difficulty. An empty offer skips the menu. A failed
seed tries the next 5, then the current room restarts. There is no room
graph, overworld, or difficulty that climbs.

There is no collected bank and no build screen (`../idea/src/ui/build_screen.ts`).
The HUD bank count is always 0. Pause is Resume, Restart room, and Generated
run. During a generated run that last entry is Demo room and reloads the
authored demo; the build stays. Input remap is not on that menu; see `todo.md`.

### Potions and rewind

Checkpoint and rewind can both be drunk. Rewind opens a scrub screen and
replays the input log; the charge is spent on commit, not on open or cancel.
The log records only while a debug overlay is up (`keep_rewind_history`
counts) or a Rewind charge is equipped, and the trail is stored only while
that overlay is visible. A debug death or fall stays on the log. A win, a
pause restart, and a move to the demo or the next generated room start a new
one. With a debug overlay up, the picker always lists Rewind and the commit
is free. `RewindTrail` draws the log while a debug overlay is visible.

`ContactLog` is not that log. It is the prototype's debug contact print
(`../idea/src/physics/debug.ts` `log_contact`): who hit whom, the boxes, and whether
the decision was stomp, hurt, or bounce. It stays off unless a test turns it
on. The readout does not show it, and rewind would not read it. Rewind replays
recorded input.

### Left behind on purpose, or not a runtime port

- The in-browser room, piece, and anim editor. They stay in `../idea`. Piece
  JSON still imports through `src/tools/import_pieces.gd`.
- The debug tuning panel and sim-speed slider. Use the inspector.
- Capsule collision. Rectangles stay until feel is signed off.
- A room graph, overworld, climbing difficulty, collected bank, and build screen.
- `tint` and `wave` shaders. Nothing uses them.

## Scheduling

Safe first-wave tasks on separate branches:

- Task 1: animation and Pogo stride
- Task 3: remaining props
- Task 6A: pure run-build model

Second wave:

- Task 2 after Task 1
- Task 4 after Task 3
- Task 5 after Task 2
- Task 6B after Task 6A
- Task 7 after presentation and contact APIs stop moving

Tasks 8-10 are cleanup, optimization, or approval-gated work. Tasks that touch
the same generated scene, `main.tscn`, `room_runner.gd`, `sync_art.gd`, or a
shared smoke test should be merged sequentially even if their implementation
was developed in parallel.

## 1. AnimationPlayer and Pogo stride

Status: complete. This task owns the animation representation and stride together
so stride is not implemented against SpriteFrames and immediately rewritten.

Prototype sources:

- `../idea/src/player/stride.ts` and `stride.test.ts`
- `../idea/src/player/player.ts`, especially `_run_footsteps`
- `../idea/src/player/animator.ts`
- `../idea/assets/art/*/*.anim.json`

Godot targets:

- `src/tools/sync_art.gd`
- `src/presentation/character_sprite.gd`
- `src/player/player_body.gd`
- character scenes and generated animation resources under `assets/art`
- `tests/art_smoke.gd` and `tests/locomotion_smoke.gd`

Requirements:

1. Replace `AnimatedSprite2D` clip playback with `Sprite2D` plus
   `AnimationPlayer`. Do not add `AnimationTree`; clip selection is the existing
   priority: ability clip, movement clip, fallback, placeholder.
2. Generated animations key texture, region, offset/pivot, and frame timing from
   the animation JSON. Different clips may use different sheets.
3. Re-sync must preserve hand-authored tracks. Mark generated tracks or keep
   generated and hand-authored libraries separate; add a mutation test proving a
   hand-added track survives.
4. Keep an event boundary for presentation listeners: a generated method key
   calls the character presentation node, which emits an animation event. Do not
   put audio playback directly in generated animation resources.
5. Pogo ground running keeps constant physical run speed. On the two animation
   frames before each footstep, generated presentation keys trail the sprite by
   one then two pixels; the footstep frame catches up to the hitbox.
6. The visual offset follows facing and resets for clips without footstep marks.
7. Placeholder visibility, facing flip, clip fallback, pivots, and hitstop
   behavior must remain unchanged.

Acceptance:

- `art_smoke` covers generated timing, pivot, clip selection, flip,
  placeholder, event and visual stride keys, and preservation of a hand-authored
  track.
- A locomotion test proves animation does not vary Pogo's physical run speed.
- `sync_art.gd` can run twice without changing output or deleting hand work.

Do not also add sound in this task.

## 2. Audio and gameplay event wiring

Status: complete. Own audio copying, playback, and event connections;
do not decide gameplay outcomes in the audio code.

Prototype sources:

- `../idea/src/audio/game_sfx.ts` and `sfx.ts`
- `../idea/assets/audio`

Godot targets:

- `src/tools/sync_art.gd`
- new presentation audio script/scene
- `src/rooms/room_runner.gd` only for event wiring
- `scenes/main.tscn`
- a new headless audio smoke test and relevant `MODULE.md` files

Requirements:

1. Copy only used audio into `assets/audio`. The prototype currently maps dash
   to `dash2.flac`, death to `raw/bird_poo.flac`, exit to `fanfare.ogg`, pogo
   side bash to `bash.ogg`, and footsteps to `footstep.wav` /
   `footstep_cane.wav`. Convert FLAC only if Godot 4.7 cannot import these files.
2. Add a presentation listener that connects to completed gameplay facts:
   `PlayerBody.dashed`, `PlayerBody.landed(fall_duration)`,
   `RoomRunner.restarted(reason)`, Pogo side-connect, and the animation-event
   signal from Task 1.
3. Match `game_sfx.ts` volumes/rates. Port `land_opts`: airtime maps over
   `0..0.9 s`, volume is that clamped fraction, and pitch is `1.28 - 0.5*u`.
4. Footsteps use one named voice: entering a new footstep cuts the previous
   footstep, and leaving the run clip stops it.
5. Use a small AudioStreamPlayer pool for unrelated overlapping one-shots.
6. Reconnect when `RoomRunner.character_changed` replaces the player. No stale
   connections to freed characters.

Acceptance:

- A headless test verifies event-to-stream mapping, land options, footstep voice
  replacement, and reconnection after character switching without requiring a
  real audio device.
- Existing gameplay tests remain silent about audio and continue to pass.

## 3. Remaining prop components

Status: complete. Implemented as one task because the importer and
`props_smoke.gd` are shared.

Prototype sources:

- `../idea/src/entities/props/switch.ts`
- `../idea/src/entities/components/power.ts`
- `../idea/src/entities/components/faller.ts` and `faller.test.ts`
- `../idea/src/entities/props/tile_prop.ts`
- `../idea/data/entities/kinds/{switch,gate,fall_block,track}.json`
- `../idea/assets/pieces/on_off_gate.json`

Godot targets:

- new prop/component scripts under `src/props`
- scenes under `scenes/props`
- `src/props/tile_prop.gd`
- `src/tools/import_demo_entities.gd` as shared import helpers, without
  re-importing the demo
- `tests/props_smoke.gd`

Requirements:

1. Switch modes match the prototype: toggle changes on overlap entry,
   momentary follows overlap, once latches on. Reset restores `starts_on`. A
   switch emits `state_changed(id, is_on)` only when its state changes.
2. A power component resolves switch ids through its owning room, connects to
   their signals, and evaluates all/any from cached switch state. Initial
   binding reads current state so it does not depend on a transition occurring
   after the prop enters the tree.
3. Power effects are `runs`, `stops`, `appears`, and `vanishes`. A hidden prop
   has no drawing, collision, or surface use. Paused motion holds phase. Do not
   poll switches or emit a signal every frame.
4. Scope switch discovery and signal connections to the owning room. Disconnect
   cleanly when either endpoint leaves it; do not use an unscoped tree-wide
   group that could affect another loaded room.
5. Gate is a TileProp with the vanish effect and `starts_open` behavior.
6. Fall block arms only when stood on as a solid surface, waits `fall_delay`,
   shakes by the prototype amount, accelerates with configured gravity to its
   cap, substeps by at most `TILE/2`, lands without tunneling, and resets home.
7. Prototype Track imports as the existing moving-platform prefab carrying a
   child. Do not add a Track component or prefab; `OscillatingMotion` and
   `PathMotion` already provide all of its movement behavior.
8. Keep optional behavior as component children, not new TileProp subclasses.

Acceptance:

- Extend `props_smoke` for all three switch modes, all/any, every power effect,
  room isolation, fall delay/landing/reset, and moving-platform cargo.
- Port the important cases from `faller.test.ts`.
- Do not alter the authored demo: it currently contains none of these kinds.

## 4. Piece import and stitching

Status: complete. Task 3 supplies the Switch and Gate prefabs used by
`on_off_gate.json`.

Prototype sources:

- `../idea/assets/pieces/*.json` and `index.json`
- `../idea/src/level/piece_document.ts`
- all files under `../idea/src/gen`, especially `generate_room.test.ts`

Godot targets:

- `src/pieces`, including `generate_room.gd` and focused stitching helpers
- `scenes/pieces` and small piece metadata resources
- a repeatable, standalone `src/tools/import_pieces.gd`
- `tests/pieces_smoke.gd`

Import requirements:

1. Treat the JavaScript piece index and JSON files as the continuing authoring
   source. Import all entries into individual Godot scenes and metadata
   resources whenever those sources change.
2. The importer stands on its own: it does not require another import script to
   have run and does not read from or mutate `demo.tscn`. Validate inputs before
   replacing outputs and report the source file for invalid portals, entities,
   or tile data.
3. Each generated scene has the same room layer structure as `demo.tscn`,
   entry/exit portal markers, entities (including nested children), spawn marker
   when present, and metadata for difficulty, tags, and cap status.
4. Preserve gameplay semantics first. Paint 8 px collision and trigger cells
   with the placeholder kind TileSet. Actual art terrain is not required for
   imported pieces, and the importer must not synthesize or rewrite the
   hand-authored earth atlas.
5. Import into `scenes/pieces` only. Generated piece scenes are replaceable
   outputs, so keep hand-authored additions elsewhere.
6. Import is deterministic and safe to run repeatedly: unchanged JavaScript
   input produces byte-equivalent Godot output.

Stitch requirements:

1. Port opposite-facing checks, aperture/bounds logic, overlap rejection,
   placement, flex corridors, difficulty budget, seeded selection, and merge.
2. Runtime stitching consumes imported scenes/resources, never JSON.
3. Translate tiles, markers, and root entities once. Child entity transforms
   remain relative to their parent.

Acceptance:

- Port `generate_room.test.ts` cases: facing portals join, mismatched apertures
  use a flex corridor, overlap is rejected, caps/budget are respected, and a
  fixed seed is deterministic.
- Run the importer twice with no output change, then change a source fixture and
  verify the corresponding imported piece changes without touching the demo.
- Load one stitched room in a test RoomRunner and verify spawn, room extent,
  collisions, and entity ownership.
- Verify runtime generation succeeds with the prototype JSON unavailable.
- Update `tests/MODULE.md`; the current mention of piece tests is aspirational.

## 5. Screen shake and vignette

Status: complete. Kept in
presentation; gameplay only requests the effect.

Prototype sources:

- `../idea/src/frame/screen_shake.ts`
- `../idea/src/render/vignette.ts` and `vignette.test.ts`
- `../idea/src/player/pogo.ts` side-pop event ordering
- `../idea/src/world.ts` vignette constants

Godot targets:

- `src/presentation`, `src/player/pogo_strike.gd`,
  `src/rooms/room_runner.gd`, and `scenes/main.tscn`
- presentation smoke tests

Requirements:

1. Shake is screen-pixel camera offset, quadratic decay, default frequency
   `30 Hz`; weaker requests do not replace a stronger active shake.
2. Pogo side-pop requests `0.18 s`, amplitude `4`, frequency `24`, directed
   along the struck side.
3. Preserve prototype ordering: side hit requests `0.1 s` hitstop, then shake
   starts when that freeze ends. Shake itself runs on presentation time.
4. Camera follow, smoothing, drag margins, room limits, respawn snapping, and
   backdrop placement must remain unchanged.
5. Vignette is a CanvasLayer effect centered on the player: inner `11` tiles,
   outer `26` tiles, darkness `0.45`. It follows the final camera position and
   shake but does not participate in world z-order.

Acceptance:

- Pure tests cover decay, request replacement, direction, and vignette
  coordinate/radius conversion.
- An integration test proves shake starts after side-hit hitstop, continues
  independently, and is cleared on restart/character switch.

## 6A. Pure run-build model

Status: complete. No UI or checkpoint in this subtask.

Prototype sources:

- `../idea/src/powerup/powerups.ts` and `powerups.test.ts`
- `../idea/src/player/stats.ts`

Godot targets:

- new scripts/resources under `src/run`
- new `tests/run_smoke.gd`

Requirements:

1. Represent stack counts independently from the live player.
2. Recompute a fresh `MovementStats` copy from character base stats:
   Slow Time `-5%` per stack, floor `0.8`, max 4; Top Speed `+12%`, max 5;
   Jump Height increases `abs(jump_velocity)` by `8%`, max 5; Slow Fall divides
   fall gravity and both fall caps by `1 + 0.12*stacks`, max 5.
3. Slow Time scales gameplay delta, not `Engine.time_scale`; UI, audio, and
   presentation continue in real time.
4. Switching character reapplies the build to that character's baseline and
   does not compound prior modifiers.
5. Port stack clamping, recomputation, and summary cases from
   `powerups.test.ts`. Reward offers remain out of scope.

Acceptance:

- Pure tests cover every formula, maxima, no compounding, and character switch.
- A locomotion integration test shows Jump Height changes apex and Slow Time
  changes simulated distance per real second without changing physics tick rate.

## 6B. Checkpoint, potion UI, HUD, and pause

Status: complete for checkpoint, the picker, the HUD, and pause. An exit now
offers three stacks and then restarts the same room. The next generated room,
the bank, and the build screen are still open. See "Still to do".

Prototype sources:

- `../idea/src/powerup/{potion,potion_belt,checkpoint,room_access}.ts`
- `../idea/src/ui/{potion_picker,build_hud,pause_menu}.ts`

Godot targets:

- `src/run`, `src/ui`, `scenes/ui`, `room_runner.gd`, and `main.tscn`
- run/UI smoke tests

Requirements:

1. Potion belt syncs from the build. Checkpoint uses have charges, place the
   respawn marker at the player's feet, and persist until unequipped.
2. Death/fall respawns at the checkpoint; room exit behavior remains explicit
   and tested. Resetting room entities must not erase the planted checkpoint.
3. Potion picker pauses gameplay, lists equipped potions and blocked reasons,
   and supports keyboard/gamepad cancel/confirm using existing input actions.
4. HUD shows the compact build/potion summary. Keep UI in a CanvasLayer with a
   process mode that runs while gameplay is paused.
5. Pause menu needs Resume and access to the build summary. Reward flow and
   room switching are out of scope.
6. Preserve the future rewind rule: checkpoint use must return enough
   information to undo/redo its room effect, but charges are never refunded.
   Do not implement the rewind log here.

Acceptance:

- Tests cover plant, replace, death respawn, charge spending, unequip cleanup,
  pause process behavior, and character switching with a build.

## 7. Runtime diagnostics

Status: complete. No tuning panel and no profiler.

Prototype sources:

- `../idea/src/debug/MODULE.md`
- `../idea/src/physics/debug.ts`
- `../idea/src/frame/perf.ts`

Godot targets:

- `src/debug`, `scenes/main.tscn`, and contact decision points
- debug smoke tests

Requirements:

1. CanvasLayer readout toggled with the existing debug action: FPS, player
   velocity, grounded, `move_state`, ability state, coyote, jump buffer, dash
   cooldown, and kind under the feet.
2. Structured contact logging behind a separate flag: participants, relevant
   boxes/normal or swept feet, velocities, and the selected stomp/hurt/bounce
   decision. Logging is off by default. This is the debug contact print, not
   the rewind history.
3. Diagnostics are read-only and must not change simulation results.
4. Use Godot's inspector/profiler/collision display for generic diagnostics;
   do not rebuild the browser's tuning panel or profiler.

Acceptance:

- A test compares a fixed gameplay trace with debug off/on and gets identical
  state.
- A contact test captures one structured decision without relying on console
  wording for gameplay.

## 8. Optional room-query lookup

Status: retired. Kind and solidity query the physics space, so the polygon scan
and the cell lookup table are both gone.

`block_terrain_smoke` remains the oracle for flipped and transposed large tiles.

## 10. Approval-gated or deferred

Moved into "Still to do". Capsules and the unused shaders stay deferred.
Input remap is the open port item. Rewind and the generated-run advance are
in. The reward card on an exit is in.

## Final retirement checklist

1. Run every headless suite and the boot check.
2. Play Standard, Grappler, and Pogo side by side with `npm run dev:plt` in
   `../idea`, in the same demo sections. Compare jump apex/range, dash, grapple
   latch/release, pogo down/side response, moving-platform carry, and actor contacts.
3. Runtime copies live under `assets/`. `sync_art.gd` reads `../idea/assets`.
4. Confirm no Godot runtime or authored scene reads prototype JSON.
5. The TypeScript runtime stays in `../idea`, which also keeps the source data
   for the art sync and piece provenance.
