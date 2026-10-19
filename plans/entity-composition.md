# Entity composition — carriers, children, and a composable inspector

Status: **proposal**. Supersedes the `spin_arms` number added with the windmill.

Decided: children **nest** inside the parent def; actors **ride** rather than
attach; `moving_platform` **stays**, and every kind is assembled from one shared
component vocabulary (below) so that is provable rather than conventional.

## Problem

Motion is currently welded to the thing that moves. `spin_arms: 3` spawns three
hard-coded copies of the same platform, a "track" can only ever carry itself, and
the only authorable arm is a tile-surface rectangle. We want:

- arms / cargo that can be **any** entity — a solid block, spikes, a grapple point,
  a breakable, a falling block, or another mover;
- **motion nodes** (track, windmill) that are responsible for moving *whatever is
  attached to them*, so rigs nest: a windmill mounted on an oscillating track;
- an editor where composition is a first-class act — drag a kind from the Place
  dock into a slot on the parent — and which keeps working for components and
  kinds we have not invented yet.

## Core model: a scene tree of kinematic nodes

One idea does all the work: **`children` becomes a component like `motion` or
`breakable`, and a parent hands each child a frame (a translation) every tick.**

```
node position = parent_frame + own local x/y + path offset + oscillate offset
child frame   = node position + spin placement(child_index, child_count)
```

Translation only — no rotation of child boxes. Orbiting non-rotating platforms is
the windmill look we already have, and AABB collision stays intact.

Consequences worth naming:

- **Spin becomes a child-placement rule, not self-motion.** A spin node puts child
  *i* of *n* at `angle = spin_phase + i/n + spin_speed·t`. The node itself never
  orbits, so a single orbiting platform is a windmill with one child. (Today's
  self-spin group on `moving_platform` goes away; nothing authored uses it.)
- **Path / oscillate move the node**, and therefore everything under it. That is
  the whole "windmill on a track" feature, with no special case.
- **Riding is already solved.** Every child is its own runtime entity and derives
  `carry_delta` from its own previous → current world position, so a player
  standing on an arm of a windmill on a track gets the combined motion for free.
  No change to `resolve_entity_y`, `SolidEntry`, or the grappler.
- **Nesting is unbounded** because a child frame is the same kind of thing as a
  root frame.

### Why not per-rect carry on one entity?

The alternative — one windmill entity exposing three rects — breaks riding: carry
is per entity, so a rider on arm A would get arm B's motion. Keeping every arm a
real entity is what makes arbitrary composition work without touching collision.

## Data format

Children nest inside the parent def:

```jsonc
{
  "kind": 7, "x": 680, "y": 192,          // windmill hub, world coords
  "spin_radius": 4, "spin_speed": 0.2,
  "children": [
    { "kind": 8, "x": -16, "y": -8, "w": 32, "h": 16, "surface": 1 },  // block
    { "kind": 8, "x": -16, "y": -8, "w": 32, "h": 16, "surface": 4 },  // spikes
    { "kind": 6, "x": -16, "y": -16, "w": 32, "h": 32 }                // falling block
  ]
}
```

- **Child `x` / `y` are local to the parent frame.** Dragging the hub moves the whole
  rig; a child's own offset is usually `-w/2, -h/2` so it centres on its arm point.
  Roots keep absolute world coords, so every existing room is unaffected.
- **Path points live in the node's parent frame** (world for roots). The editor
  converts on draw / edit by the parent's base, so on-canvas path editing keeps
  working unchanged for top-level movers.
- Nesting rather than a flat list with `parent_id` means: no id bookkeeping, no
  orphans, and copy / delete / undo of a whole rig is already correct
  (`capture_room` deep-clones each def with `structuredClone`).

## Runtime changes

| File | Change |
|------|--------|
| `entities/types.ts` | `children?: EntityDef[]` on the base def; `def_children(def)`; drop `spin_arms` |
| `entities/frame.ts` *(new)* | `Frame = { x, y }` and the placement helpers; keeps transform math out of `TileProp` |
| `entities/props/tile_prop.ts` | Accept a parent frame in `update`; expose `child_frame(i, n)`; own position = frame + local + path + oscillate |
| `entities/entity.ts` | `create_entities` recurses: build the node, then its children, returning the node plus descendants in pre-order |
| `entities/manager.ts` | Keep `roots` (recursive `update` / `reset`) **and** the flat pre-order `entities` array every query already uses |
| `entities/iface.ts` | Optional `set_frame(frame)` / `child_frame(...)`, guarded by `is_carryable(e)` so non-kinematic kinds are untouched |
| `entities/registry.ts` | `carryable?: boolean` on the kind schema; `sanitize_entities` recurses and drops `children` on non-carrier kinds with a console error |
| `entities/surface.ts` | `TileKind.Empty` becomes a legal surface = **None**: no draw, no collision, no triggers — that is the invisible transform node |
| `player/character_filter.ts` | Recurse into `children` when filtering excluded surfaces (Pogo run should drop grapple arms but keep the hub) |

`update` order falls out of the recursion: a parent always resolves its frame
before its children, in one pass, at any depth.

## A kind is a list of components

There is one runtime node type. A "kind" is a **prefab**: a named set of
components plus defaults. Today each `kinds/*.json` re-declares the transform,
surface and motion groups by hand, which is why the shared blocks are invisible —
four files describe the same motion group four times.

Extract the vocabulary into `entities/groups/*.json` (one file per component:
`transform`, `surface`, `motion`, `path`, `spin`, `breakable`, `fall`, `children`)
and let a kind reference them:

```jsonc
{
  "id": "moving_platform",
  "label": "Moving platform",
  "use": ["transform", "surface", "motion", "children?", "breakable?"],
  "defaults": { "w": 64, "h": 32, "travel": 96, "speed": 2, "surface": 1 }
}
```

An entry is a group id, or an object when the kind wants to rename or constrain
it — `{ "group": "children", "label": "Arms", "max": 12 }`, or a `presence`
override so `fall_block` shows Fall always while `moving_platform` shows it behind
the `falls` flag. Field defaults live with the group; a kind's own `defaults` win
over them, which is what lets the windmill leave Track switched off yet still fill
in travel 64 / speed 1.5 the moment you enable it.

The payoff is that composition is legible in one line per kind, adding a component
to the vocabulary offers it to every kind at once, and nobody can drift.

| Kind | Components | Carryable | Children |
|------|-----------|-----------|----------|
| `block` *(new)* | `surface` — "any tile kind" as an entity: solid, grapple, exit, death, pogo | yes | optional |
| `track` *(new)* | `motion` or `path` + `children` (surface None) | yes | yes (`max: 1` default) |
| `windmill` | `spin` + `children`, optional `motion` / `path` track | yes | yes (list) |
| `moving_platform` | `surface` + `motion` — the one-node shorthand | yes | optional |
| `breakable` | `surface` + `breakable` | yes | optional |
| `fall_block` | `surface` + `fall` | yes | optional |
| `gate` | `surface` + `power` (Vanishes when signalled) | yes | optional |
| `walker`, `lob` | actor components | **no** — they *ride* arms by collision | no |
| `switch` | sensor: player overlap → `signal()` under its `id` | no | no |

So `moving_platform` and `track` differ only in *where the surface sits*: on the
moving node itself, or on a child it carries. Both are the same components on the
same node type.

## Generalizing beyond motion

Motion is the first component family to get this treatment, but the same shape
should carry behaviours, feedback, and spawning. The way to keep that honest is to
say what *slot* a component fills, because components in the same slot compete and
components in different slots compose freely.

| Slot | Answers | Today | Later |
|------|---------|-------|-------|
| **Transform** | Where is it? | `motion`, `path`, `spin`, `fall` | conveyor drift, follow-the-player, tween on signal |
| **Presence** | Does it exist right now? | `breakable`, `power` (Appears / Vanishes) | timed phase (on/off blocks) |
| **Reaction** | What happens when something touches it? | hard-coded in the tile kind | `bounce`, `hazard`, `sticky`, `conveyor`, `checkpoint` |
| **Presentation** | How does it look / sound? | one hard-coded draw per surface | `clip` (anim), `sfx`, particles, shake |
| **Spawn** | What does it produce? | — | enemy spawner, projectile emitter, item drop |
| **Signal** | What does it listen to / emit? | `signal()` by `id` (switch); `power` group `watches` on any tile prop — Runs / Stops pause motion, Appears / Vanishes toggle presence | more senders (broken, landed, timer), power on actors |

Four moves get us there, each small on its own.

### 1. Contact events instead of magic surfaces

Right now "what happens when you touch this" is encoded in the **tile kind**:
death hurts, pogo bounces, exit ends the room, grapple is attachable. That is the
tile vocabulary leaking into entities, and it is why a Hollow-Knight-style bouncy
mushroom has nowhere to live except a new `TileKind`.

Split it: **surface = how it draws and whether it is solid; reactions are
components.** Replace the two ad-hoc hooks (`on_stood_on`, `on_surface_used`) with
one event:

```ts
type ContactEvent =
    | { type: "land";   body: ContactBody; point: Vec }   // came to rest on top
    | { type: "touch";  body: ContactBody; normal: Vec }  // any overlap this frame
    | { type: "leave";  body: ContactBody }
    | { type: "stomp";  body: ContactBody }
    | { type: "ability"; use: SurfaceUse; point: Vec };   // grapple / pogo hit
```

`breakable` and `fall` already want exactly `land` and `ability`, so they convert
directly. Then a **mushroom is a `block` with a `bounce` component**
(`strength`, `axis`, `retrigger_delay`, whether it needs a stomp) — no new kind, no
new tile, and it can be an arm of a windmill because it is just a carryable node.
Existing tile kinds stay as presets: a Death surface is shorthand for
`surface: solid + hazard`, so no room changes.

### 2. States and presentation hooks

Components already move through named states (`Active → Arming → Gone`,
`Idle → Falling → Landed`). Publish that: the node exposes a current state string,
and a **`presentation` component maps state → animation clip / sound / tint** in
the kind JSON rather than in code:

```jsonc
{ "group": "presentation", "states": {
    "arming": { "clip": "shake", "sfx": "crack" },
    "gone":   { "clip": "burst", "sfx": "break" } } }
```

That keeps art and audio out of every behaviour class, reuses the anim documents
the editor already loads, and means a new behaviour gets sound for free by naming
its states.

### 3. Spawners are children with a template

A spawner is the tree again, one level later: instead of `children` built at load,
it holds a **template** and a `spawn` component (interval, max alive, on-signal)
that instantiates copies parented to its own frame. Everything downstream already
works — spawned things are ordinary nodes, so they can be blocks, hazards, or a
whole windmill, and a spawner mounted on a track sprays enemies while it moves.
The storage is the same `children` array with a `role: "template"` marker, so the
inspector's slot box edits it with no new UI.

### 4. Rules that keep combinations sane

- **One authority per slot.** Transform components apply in a fixed pipeline
  (frame → path → oscillate → spin → fall) and a component may declare itself
  *authoritative*, which stops the ones after it — that is exactly how a falling
  block stops taking orders from its track mid-drop. The same rule generalises
  instead of being a special case inside `TileProp`.
- **Declared requirements.** Each group states what it needs (`spin` requires
  `children`, `bounce` requires a solid surface, `children` requires a carryable
  kind). The registry validates on load and the inspector greys out a group it
  cannot satisfy — so an unforeseen combination fails loudly at author time
  instead of silently at runtime.
- **Components never reach for the level or the player.** They receive what they
  need (`dt`, frame, contact event, solids) and return data. That is what lets the
  same `bounce` work on a static block, a windmill arm, and a spawned enemy.

None of this is required for the work below — but the frame stack, the component
vocabulary, and the slot box are built so each item is additive.

## Editor

### Selection becomes a path

`editor.selected_entity: number | null` → `selected_path: number[]` (`[2, 0]` = first
child of entity 2), with `def_at_path(room, path)` and `parent_of(room, path)`.
Contained: six call sites in `editor.ts`, plus `delete_selected_entity`,
`gesture_at`, and `render_inspector`'s index threading (`write_field` and friends
take a path instead of an index).

Canvas picking stays top-level: you select the rig, then pick a child inside the
inspector. Alt+clicking a child's *live* rect to select it is a follow-up
(children have no authored world rect, so it needs runtime hit-testing).

### The slot box

New field schema type, so this is declarative for every future kind:

```jsonc
{ "type": "children", "key": "children", "label": "Arms", "max": 12 }
```

Rendered as one dashed drop box. `max: 1` renders as a single slot, anything else
as a list — that covers "the track moves one thing" and "the windmill has N arms"
with one implementation.

- **Drag from the dock.** Place rows become `draggable`, carrying the kind id in
  `dataTransfer`. Dropping on the box spawns that kind's defaults, centres it on
  the arm point, appends it, and selects it. This is the interaction you asked for.
- **`+ Add`** picks from a list of carryable kinds — same result without dragging
  (touch, and faster once you know what you want).
- Each child row: kind label + surface, then select / duplicate / delete / reorder.
  Order is meaningful (arm order = angle order), hence ↑↓.
- Selecting a child renders **its** full group UI, recursively, with a breadcrumb
  (`← All entities › Windmill #3 › Block 1`). A child windmill shows its own Arms
  box, which is what makes deep rigs authorable.
- Drop is rejected with a reason when the kind is not carryable (walker, lob).

### Canvas overlay

Hub cross + orbit circle for a selected spin node, the existing yellow path
polyline (offset into the parent frame), and a highlight on the selected child's
live rect. Children already render in edit mode because the runtime tree is built
there too.

## Compatibility

Additive: no room, piece, or generated level changes shape, and every field that
exists today keeps its meaning. The only removals are `spin_arms` and the
`moving_platform` spin group, both added in the windmill change and not yet used
by any saved content.

## Staging

1. **Runtime tree** — `children`, frames, recursion, `block` + `track` kinds,
   surface None, carryable flags, filter/sanitize recursion. Rigs authorable by
   hand-editing JSON; windmill arms become children instead of a count.
2. **Inspector paths** — `selected_path`, recursive group rendering, breadcrumb,
   children box with `+ Add`, reorder, delete.
3. **Drag + overlay** — draggable dock rows, drop targets, orbit/path/child gizmos.

Each stage typechecks and is playable on its own.

## Staging, revised

0. **Component group library** — extract `entities/groups/*.json`, convert the
   eight existing kinds to `use: [...]`. Pure refactor, no behaviour change, and it
   makes every step after it a one-line edit per kind.
1. **Runtime tree** — `children`, frames, recursion, `block` + `track` kinds,
   surface None, carryable flags, filter/sanitize recursion.
2. **Inspector paths** — `selected_path`, recursive group rendering, breadcrumb,
   children box with `+ Add`, reorder, delete.
3. **Drag + overlay** — draggable dock rows, drop targets, orbit/path/child gizmos.

## Open questions

1. **Per-child angle override.** Even spacing by index covers windmills; a
   `spin_offset` field per child (for uneven arms) is a one-field follow-up.
2. **Carried actors.** If a walker patrolling a moving arm is ever wanted, apply
   the parent delta as a platform-style carry before its own collision pass.
