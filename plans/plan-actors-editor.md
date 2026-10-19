# Plan — Actors (Walker / Lob) + component inspector

Detailed Cursor working plan for Stage 2a++. High-level summary lives in [plan.md](./plan.md); this file is the implementation brief (pseudo-code, schema UI, binding notes).

---

## Goals

1. **Actor entity family** — gravity, contact, player verbs — separate from `TileProp`.
2. **Walker** first (patrol + stomp + hazard).
3. **Lob** second (carry / throw / slide; shell×snowball, our jump boost).
4. **Component-aware inspector** — grouped, presence-aware fields so prefabs stay editable as they grow.

Non-goal: full ECS, Unity-style component marketplace, runtime reflection magic.

---

## Input — Lob vs Jump

Lob pickup/throw must be pressable **while holding Jump** (Mario: jump + hold shell).

| Bind | Default pad (today) | Role |
|------|---------------------|------|
| Jump | FaceDown | Jump |
| Action | R1 | Grapple / Pogo |
| Item | FaceRight | Checkpoint |
| — | **FaceLeft** | **Target for Lob** (Mario B-feel on many layouts) |

**Lean:** Lob on **FaceLeft** so it chords with Jump (FaceDown). Checkpoint stays FaceRight / Item.

**Binding work when Lob ships:** FaceLeft is unused in defaults today (Action is R1). Either:

- map Lob/interact to FaceLeft (+ a keyboard key), or  
- move Action’s default pad to FaceLeft and put Lob on Action (abilities vs carry need clear priority — worse)

Prefer a clear **Interact** (or Lob-specific) on FaceLeft rather than overloading Action.

```
on face_left / interact pressed:
  if holding Lob -> throw / drop
  else if overlapping idle Lob -> pickup
```

---

## Shared actor pipeline

```
each frame (play):
  entities.update(dt)           // motors + ActorBody integrate
  player.update(dt, ...)
  resolve_actor_contacts(...)   // stomp / hazard / (later) pickup prompt
  check_triggers(...)           // tiles exit/death — unchanged
```

### Pseudo — ActorBody

```ts
type ActorBody = {
  x, y, w, h: number;
  vx, vy: number;
  on_ground: boolean;
  gravity: number;       // from prefab / TILE scale
};

function body_integrate(body, dt, level, solids: Rect[]) {
  body.vy += body.gravity * dt;
  // move X vs level + solids, then Y; set on_ground on downward hit
  // (same spirit as player collision, slimmer — no coyote/jump buffers)
}
```

### Pseudo — contact resolve

```ts
function resolve_actor_contacts(player, actors, controller) {
  for (const a of actors) {
    if (!a.alive) continue;
    if (stomp_hit(player, a)) {          // falling, feet near top
      a.on_stomped(player);              // Walker: kill; Lob: stop slide
      player.apply_bounce(a.stomp_vy);
      continue;
    }
    if (a.hazard_active && overlap(player, a)) {
      controller.restart_room(Death);
      return;
    }
  }
}
```

`hazard_active`: Walker always (while alive); Lob only if `speed > threshold` or state ∈ {Thrown, Sliding}.

---

## Walker (slice 1)

**Components:** `ActorBody` + `PatrolWalk` + `ContactHazard` + `Stompable` + `Killable`.

```ts
function patrol_update(patrol, body, level) {
  body.vx = patrol.facing * patrol.speed;
  if (wall_ahead(body, level) || (patrol.turn_on_ledge && ledge_ahead(body, level))) {
    patrol.facing *= -1;
  }
}
```

- Prefab field `stomp_vy` (not derived from player jump).
- Ledge turn **on** for v1.
- Dead → vanish; `reset()` restores pose on room restart.

**Follow-ups:** pogo slash as stomp; grapple kill/yank.

---

## Lob (slice 2)

**Components:** `ActorBody` + `Carryable` + `Throwable` + conditional `ContactHazard` + `Stompable` (stop slide).

**States:** `Idle | Carried | Thrown | Sliding`

```ts
on item_pressed:
  if lob.state == Carried:
    lob.throw(player.face, throw_speed)
  else if lob.state == Idle && near(player, lob):
    player.held = lob; lob.state = Carried

// player jump:
  if (player.held is Lob) or (standing_on idle/sliding Lob):
    apply extra lob_jump_boost   // v1: underfoot / carried only
```

While `Carried`, Lob follows a carry anchor on the player; body gravity off.

**Ours vs Mario/Celeste:** carry-first; **Lob jump** as the signature tech; hazard only when fast.

---

## Editor UI — component groups

### Problem

`kinds/*.json` exposes a flat `fields[]`. Inspector renders every field. Motion/breakable/respawn already clutter the panel when `fragile: 0`. Actors + art will make this worse.

### Approach: schema-driven UI (not TS reflection)

TypeScript **does not** give useful runtime field reflection. What you already have — **JSON kind schemas** — *is* the automation layer:

| Layer | Role |
|-------|------|
| `kinds/*.json` | Source of truth for defaults + field metadata |
| `registry.ts` | Load / validate / `spawn_entity_def` |
| `inspector.ts` | **Generic** renderer: walk schema → DOM controls |

Do **not** try to reflect `class Walker` fields into the UI. Keep defs as plain data (`EntityDef`); runtime classes read defs in constructors (as `TileProp` does today).

Optional later automation (only if schema authoring hurts):

- **Zod** (or similar) schemas that emit both types + inspector field lists  
- **One codegen script** from a single TS const (groups + fields) → JSON + types  
- Avoid decorator/`reflect-metadata` unless you already want that dependency  

**Presence** is data, not magic:

```ts
type Presence =
  | { mode: "always" }
  | { mode: "flag"; flag_key: "fragile" }           // 0/1 on def
  | { mode: "keys"; required_keys: ["travel", "speed"] };

type FieldGroup = {
  id: string;
  label: string;
  presence: Presence;
  default_open?: boolean;
  fields: EntityFieldSchema[];
};

type EntityKindSchema = {
  kind: number;
  id: string;
  label: string;
  placement_key?: string;
  defaults: Record<string, number>;
  groups: FieldGroup[];   // replaces flat fields[]
};
```

### Pseudo — inspector render

```ts
function group_present(def, g: FieldGroup): boolean {
  if (g.presence.mode === "always") return true;
  if (g.presence.mode === "flag") return def[g.presence.flag_key] === 1;
  return g.presence.required_keys.every(k => def[k] != null);
}

function render_inspector(def, schema) {
  for (const g of schema.groups) {
    const on = group_present(def, g);
    if (!on) {
      render_add_button(g, () => apply_group_defaults(def, g));
      continue;
    }
    const open = g.default_open ?? true;
    render_details(g.label, open, () => {
      for (const f of g.fields) render_field(def, f);
      if (g.presence.mode !== "always")
        render_remove(() => clear_group_keys(def, g));
    });
  }
}
```

**Ship order for UI:**

1. Migrate moving_platform / breakable JSON to `groups` (motion, breakable presence).  
2. Generic inspector understands `groups` (keep flat `fields` as fallback during migrate).  
3. Walker / Lob schemas only use groups.  
4. Later: `animation` / `sprite` group — same renderer, new fields (`type: "string"` / asset picker when you need it).

### What “automation” means here

- **One renderer** for all kinds → adding a component = JSON group + runtime reader, **zero** new inspector code.  
- **Presence rules** hide unused tunables without custom per-prefab React.  
- Reflection is a dead end in browser TS; **schema as data** is the practical equivalent.

---

## File sketch (when implementing)

Target layout (additive; migrate as you touch files):

```
src/entities/
  iface.ts              # Entity interface (shared)
  geom.ts / collision.ts / surface.ts
  types.ts              # shared enums + Rect; keep thin
  defs/                 # optional later: split TilePropDef vs ActorDef
  components/
    # tile-prop (existing)
    motion.ts
    breakable.ts
    # actors (new)
    actor_body.ts
    patrol_walk.ts
    contact_hazard.ts
    stompable.ts
    killable.ts
    carryable.ts
    throwable.ts
  props/                # rename/move from root when convenient
    tile_prop.ts        # was entities/tile_prop.ts
  actors/
    walker.ts
    lob.ts
  kinds/
    moving_platform.json
    breakable.json
    walker.json
    lob.json
  entity.ts             # create_entity: switch kind → TileProp | Walker | Lob
  manager.ts
  registry.ts           # groups support
  index.ts

src/game/
  actor_contacts.ts
  triggers.ts           # tiles only; actors stay in actor_contacts

src/editor/gui/
  inspector.ts          # group-aware render
```

### Cleanup / ordering of what already exists

Do this **as part of 2a++**, not a separate mega-refactor — fold into the first PR that needs the path.

| Current | Cleanup |
|---------|---------|
| `entity.ts` only ever `new TileProp(def)` | Grow into a real factory: `switch (def.kind)` / kind family → prop vs actor. Keep `create_entity` as the only spawn entry. |
| `tile_prop.ts` at package root | Move under `props/tile_prop.ts` when actors/ appears (symmetric with `actors/`). Re-export from `index.ts` so call sites stay stable. |
| `components/motion.ts`, `breakable.ts` | Stay; they’re prop components. Don’t mix actor components into the same files — new files beside them (or later `components/props/` vs `components/actors/` if the folder gets noisy). |
| Flat `fields[]` in kind JSON | Migrate platform + breakable to `groups` **before** walker JSON so the inspector change isn’t blocked on gameplay. |
| `types.ts` dumps all def shapes | When Walker/Lob land, either `TilePropDef \| WalkerDef \| LobDef` union or split `types_prop.ts` / `types_actor.ts` and re-export. Avoid one giant bag of optional keys forever. |
| `draw.ts` = platform surfaces only | Keep for props; actors draw in their class (or `actors/draw.ts`) until shared sprite helpers exist. |
| `game/triggers.ts` | Stay tile/exit/death. Do **not** stuff stomp/hazard into it — `actor_contacts.ts` owns actor↔player. |
| `editor/tools/selection.ts` vs `selection_tiles.ts` | Already split entity hit-test vs tile marquee; leave unless names confuse — optional rename `selection_entities.ts`. |
| `powerup/` | Canonical power-up package; ignore any stale `build/` mentions in old docs. |
| Deprecated aliases (`MovingPlatformDef`, `TileSurfaceEntity`, `BINDS`, `FragileFlag`) | ✅ pruned |

**Ordering rule:** schema/inspector cleanup → factory + folders → Walker → Lob. Don’t move every file on day one; move `tile_prop` when the first actor file lands so the tree tells the story.

---

## Implementation order

1. Schema `groups` + inspector (tile props only); optional `props/` move. ✅  
2. `ActorBody` + Walker + `create_entity` dispatch + demo spawn. ✅  
3. Lob carry/throw + FaceLeft Interact bind. ✅  
4. Follow-ups: pogo/grapple on actors; animation group. (deprecated types ✅ pruned)  

---

## Open calls (copy from plan.md)

- Lob bind: **FaceLeft** (chord with Jump); Checkpoint stays Item/FaceRight.  
- Lob jump: carried / underfoot only for v1.  
- Walker: `stomp_vy` prefab field; ledge turn on; vanish on death.  
