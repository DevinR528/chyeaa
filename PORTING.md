# Remaining port work

This is the implementation handoff for agents finishing the TypeScript-to-Godot
port. `todo.md` is the short checklist; this file owns scope, dependencies,
source references, and acceptance criteria.

The behavior source is the prototype in `../src` and `../assets`. The target is
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
`block_terrain_smoke`, `demo_room_smoke`, `locomotion_smoke`, `props_smoke`,
`reach_overlay_smoke`, and `triggers_smoke`.

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

- `../src/player/stride.ts` and `stride.test.ts`
- `../src/player/player.ts`, especially `_run_footsteps`
- `../src/player/animator.ts`
- `../assets/art/*/*.anim.json`

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

- `../src/audio/game_sfx.ts` and `sfx.ts`
- `../assets/audio`

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

- `../src/entities/props/switch.ts`
- `../src/entities/components/power.ts`
- `../src/entities/components/faller.ts` and `faller.test.ts`
- `../src/entities/props/tile_prop.ts`
- `../data/entities/kinds/{switch,gate,fall_block,track}.json`
- `../assets/pieces/on_off_gate.json`

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

- `../assets/pieces/*.json` and `index.json`
- `../src/level/piece_document.ts`
- all files under `../src/gen`, especially `generate_room.test.ts`

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

- `../src/frame/screen_shake.ts`
- `../src/render/vignette.ts` and `vignette.test.ts`
- `../src/player/pogo.ts` side-pop event ordering
- `../src/world.ts` vignette constants

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

- `../src/powerup/powerups.ts` and `powerups.test.ts`
- `../src/player/stats.ts`

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

Status: blocked by Task 6A.

Prototype sources:

- `../src/powerup/{potion,potion_belt,checkpoint,room_access}.ts`
- `../src/ui/{potion_picker,build_hud,pause_menu}.ts`

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

Status: ready after APIs above settle.

Prototype sources:

- `../src/debug/MODULE.md`
- `../src/physics/debug.ts`
- `../src/frame/perf.ts`

Godot targets:

- `src/debug`, `scenes/main.tscn`, and contact decision points
- debug smoke tests

Requirements:

1. CanvasLayer readout toggled with the existing debug action: FPS, player
   velocity, grounded, `move_state`, ability state, coyote, jump buffer, dash
   cooldown, and kind under the feet.
2. Structured contact logging behind a separate flag: participants, relevant
   boxes/normal or swept feet, velocities, and the selected stomp/hurt/bounce
   decision. Logging is off by default.
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

- Capsules for players/actors: wait for rectangle feel sign-off because they
  change tile-lip and contact behavior. Update ContactBox/sensors and all
  locomotion/contact tests together when approved.
- Rewind potion/log/screen/trail: decide after feel sign-off. If accepted, port
  `../src/level_manager/rewind.ts`, `../src/powerup/rewind.ts`,
  `../src/ui/rewind_screen.ts`, and `../src/debug/rewind_trail_overlay.ts` as one
  project.
- Input remapping and Nintendo HID profile: wait for a physical gamepad. Default
  keyboard, d-pad, stick, and standard joypad actions already exist.
- Reward screen, room graph, multi-path fallback, and seeded run progression
  are new Stage 2-3 work, not required to retire the prototype.
- `tint` and `wave` shaders have no current content users and are not port work.

## Final retirement checklist

1. Run every headless suite and the boot check.
2. Play Standard, Grappler, and Pogo side by side with `npm run dev:plt` in the
   same demo sections. Compare jump apex/range, dash, grapple latch/release,
   pogo down/side response, moving-platform carry, and actor contacts.
3. Confirm all runtime assets needed by Godot are under `lil-guy/assets`, or
   deliberately keep `sync_art.gd` reading `../assets`.
4. Confirm no Godot runtime or authored scene reads prototype JSON.
5. Only then remove the TypeScript runtime. Keep archived source data needed by
   the art sync or piece provenance.
