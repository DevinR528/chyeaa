# Build plan — roguelite platformer

Working plan for getting from "movement prototype" to "playable run." Design source is [design-doc.md](./design-doc.md).

**Guiding bet:** the GDD claims *difficulty comes from your build, not from the room.* Concretely that means rooms offer several routes to the exit, each favouring a different build, and your upgrades decide which route is cheap for you (see [Rooms are multi-path](#rooms-are-multi-path-not-build-agnostic)). That's unproven and everything else depends on it, so the early work exists to test it as cheaply as possible. Procgen, shops, meta progression and art all wait until we know the bet pays off.

---

## Stage 0 — Stats + characters ✅ done

Movement tuning moved out of module constants into a per-run `Stats` object, and the player split into a base class plus an ability subclass.

| File | Role |
|------|------|
| `stats.ts` | `Stats` type, `BASE_STATS`, `make_stats(overrides)` |
| `player.ts` | Base `Player` — The Standard Guy. Run, jump, collide. No ability. |
| `grappler.ts` | `Grappler extends Player` — hook state machine + grapple tuning |
| `characters.ts` | `CHARACTERS` registry, `make_character(id, x, y)` |

**Rules this locks in:**

- Power-ups only ever mutate `Stats`, so they apply to every character equally. No power-up buffs a unique ability (grapple reach stays a fixed constant in `grappler.ts`).
- Subclasses fill in ability hooks rather than reimplementing movement: `_tick_ability`, `_update_ability`, `_try_start_ability`, plus `_can_jump` / `_jump_velocity` / `_consume_jump` for extending jump windows.
- `stats.air_jumps` already exists and defaults to `0`, so the "extra double jump" power-up is a one-line stat change when we get there.

---

## Stage 1 — Power-ups + pause build picker ✅ done

The actual experiment. No run loop needed yet; demo level + change your build between attempts.

**Power-up shape** (`src/build/`):

```ts
export type BuildEffects = { stats: Stats; time_scale: number };
export type PowerUp = {
  id: string;
  name: string;
  desc: string;
  max_stacks: number;
  apply: (effects: BuildEffects, stacks: number) => void;
};
```

**Starter catalog:** Slow Time (Celeste-style sim `time_scale`, full render FPS, max −20%), Top Speed (`max_run`), Jump Height (`jump_v`), Slow Fall (softer fall stats).

**UI:** Pause (`Esc` / `Tab` / Start) → Build card picker (stack / clear). HUD shows active build. Global control remaps (Jump / Action / Dash) live under Controls in the same pause menu (`localStorage` `plt.binds.v1`); per-character overrides hooked but not exposed yet.

**What we're looking for:** run the same room with a few builds. Does difficulty vary in an interesting way?

---

## Stage 2a — Tiles, level revamp, entities ✅ done

Level package, JSON rooms, new tile kinds, restart controller, and a third **Entity** layer (moving platforms).

| Area | Files |
|------|-------|
| Level | `src/level/` — `TileKind` enum, `RoomDocument` JSON, `assets/levels/demo.json` |
| Game | `src/game/` — `PlayScene`, `Editor`, `GameController`, trigger checks |
| Entities | `src/entities/` — prefab kinds + composed `TileProp` (`motion` / `breakable` components), collision + riding |
| Dev save | `tools/vite-level-save.ts` — Vite plugin on `npm run dev:plt` (`POST /api/levels/:id`) |

**Tile kinds:** solid, grapple, exit (restart for now), death, pogo (lethal until Pogo character exists).

**Room format:** versioned JSON with `layers[].runs` (`[row, x0, x1, kind]`) and `entities[]`. Stubs for future tileset/tilemap PNG rendering in `tileset.ts` / `tilemap.ts`.

**Editor:** brushes `1`–`5`, platform `6`/`P`, breakable `B`, resize `[` `]` / `;` `'`, copy `C`, save `Ctrl+S`. Prefabs share optional motion + fragile fields so you can make moving death/breakables without new classes.

---

## Stage 2a+ — Entity composition ✅ done (tile props)

Tile-like entities are a bag of optional components on one runtime type (`TileProp`), not one class per combo:

| Piece | Role |
|-------|------|
| Surface | Solid / grapple / exit / death / pogo (+ solid override) |
| Motion | Sine patrol (`travel` / `speed` / `axis` / `phase`) → `carry_delta` |
| Breakable | Fallaway / one-shot (`fragile` on movers, always on breakable prefab) |
| Path | Waypoint walk (`path` tile coords / `path_speed` / `path_mode`) |
| Spin | Orbit the hub (`spin_radius` / `spin_speed` / `spin_phase`); `spin_arms` spawns one platform per arm |
| Fall | Armed by a footstep, then drops and stays (`falls` on movers, always on the fall_block prefab) |

Editor **kinds** remain prefabs (placement defaults). Flat inspector lists every JSON field today — fine for 2 components, painful once actors + art land.

---

## Stage 2a++ — First actors + component inspector

Goal: prove an **actor** entity family (gravity, contact, player interaction) with two complementary prefabs, without a full ECS — and make the editor honest about optional components so bigger prefabs stay usable.

**Two “first” actors** (same body / contact pipeline; different motors + player verbs):

| Prefab | Fantasy | Player verbs |
|--------|---------|--------------|
| **Walker** | Ground patrol hazard | Stomp to kill; sides kill you |
| **Lob** (name TBD) | Kickable / throwable prop (shell × snowball) | Pick up, carry, throw; ride/boost jumps; moving = soft hazard |

Ship **walker first** (contact + stomp path), then **Lob** (carry/throw path). Shared pieces should already exist from the walker slice.

### A. Actor runtime (not TileProp)

Actors still implement `Entity`, composed from small behaviors. Do **not** jam gravity/AI into `TileProp`.

| Component | Responsibility | Used by |
|-----------|----------------|---------|
| **`ActorBody`** | AABB, `vx/vy`, gravity, collide vs level + solids, `on_ground` | Walker, Lob, future NPCs |
| **`PatrolWalk`** | Constant speed; flip on wall and/or ledge | Walker |
| **`ContactHazard`** | Side / underside overlap → death (or only while “armed”) | Walker; Lob while sliding/thrown |
| **`Stompable`** | Falling onto top → bounce player + effect (kill / stop spin) | Walker kill; Lob → idle |
| **`Killable`** | Alive/dead; disable hitboxes; `reset()` on room restart | Walker (Lob may stay alive) |
| **`Carryable`** | Held by player: follow carry anchor, suppress own motor | Lob |
| **`Throwable`** | On release: inherit aim / face vel; bounce off walls | Lob |
| **Draw** | Rect / facing for now | Both |

**Contact resolution** (thin, outside prefab classes): after player + entity update, `resolve_actor_contacts(...)`:

1. Stomp → `Stompable`  
2. Else hazard → death  
3. (Lob later) interact / pickup edge when idle + Action  

**Design lock (walker):** all characters can stomp. Pogo slash and Grappler hook are extra kill paths.

#### A1. Walker — first vertical slice

**Prefab:** `EntityKind.Walker` + `kinds/walker.json`. Placement e.g. `E`.

1. `ActorBody` + level collision  
2. `PatrolWalk` (walls, then ledges)  
3. Contact kill + stomp + room `reset()`  
4. Editor prefab + one demo spawn  

**Follow-ups:**

- [ ] Pogo down-slash counts as stomp  
- [ ] Grapple latch kills / yanks walker  
- [ ] Flying motor (no gravity)  

#### A2. Lob — throwable prop (after walker)

Mario shell / Celeste snowball inspiration, but lean into **our** verbs instead of a clean clone:

| Borrow | Make it ours |
|--------|----------------|
| Kick / slide, wall bounce | **Carry is first-class** (Action pickup while idle; not only kick-from-side) |
| Stand-on bounce | **Lob jump:** while carried or freshly underfoot, jump gets a scripted boost (shell-jump energy without a second enemy) |
| Hazard when moving | Hazard only above a speed threshold — idle is a platform/prop |
| — | Character flavor later: Grappler hook-reels a Lob; Pogo slash taps it into slide |

**States:** `Idle` → `Carried` → `Thrown` / `Sliding` → (stomp or friction) → `Idle`.

**Why it belongs in 2a++:** forces `Carryable` / player “held entity” hooks that Checkpoint items don’t cover, and reuses `ActorBody` + conditional `ContactHazard` + `Stompable` (stop slide). Multi-path tool: throw across a gap on the speed route, carry on the careful route.

**Name:** **Lob** in code until art/fantasy settles (shell / snowball / scrap / seed all fit the same components).

### B. Editor: component-aware inspector

**Problem today:** `EntityKindSchema.fields` is a flat list. Moving platform already shows motion + fragile + respawn/delay even when `fragile: 0`. Actors will add patrol, hazard, carry, later animation/asset fields — the panel becomes unusable.

**Direction:** schema describes **groups (components)** with presence, not only bare fields. Inspector renders collapsible sections; inactive groups stay collapsed (or hidden behind “Add component”).

```ts
// Sketch — evolve registry.ts / kinds/*.json
type FieldGroup = {
  id: string;                 // "transform" | "motion" | "breakable" | "patrol" | "carry" | …
  label: string;
  /** How presence is stored on the def */
  presence?: {
    mode: "flag" | "keys" | "always";
    /** flag: key "fragile" on/off; keys: present iff travel+speed set; always: transform */
    flag_key?: string;
    required_keys?: string[];
  };
  default_open?: boolean;     // transform + surface open; optional comps closed unless present
  fields: EntityFieldSchema[];
};
```

**UI behavior:**

| State | UI |
|-------|----|
| Group `always` (transform, size) | Always visible, expanded |
| Group present (flag=1 or keys set) | `<details open>` with fields + “Remove” where safe |
| Group absent | Collapsed row or “+ Motion / + Breakable / …” affordance that writes defaults |
| Removing a group | Clears that group’s keys from the def (runtime already treats absence as off) |

**Apply first to existing tile props** (motion + breakable) before walker ships — proves the schema without new gameplay. Then walker groups, then Lob (`carry` / `throw` tunables).

**Later (same pattern, don’t build yet):**

- Animation / sprite group (sheet id, frame size, facing)  
- Audio hooks  
- Per-component advanced fields behind a nested “Advanced” disclosure  

**Non-goals for 2a++:** full Unity-style add-component palette, visual scripting, live prefab variants browser.

### C. How this plugs into the bigger plan

- Stage 2a++ validates **actors + carry/throw + editor scale**.  
- Stage 2 (room metadata / multi-path) stays independent; walker = hazard route tax, Lob = tool for biased / fallback routes.  
- Stage 3 seeded RNG can later vary Lob throw speed; v1 uses fixed JSON defaults.

### Open calls

- Stomp bounce: dedicated `stomp_vy` on prefab (tunable per room).  
- Ledge turn on walker: yes for v1.  
- Dead walker: vanish immediately for v1.  
- Lob pickup bind: prefer **FaceLeft** (Mario-style: hold shell while Jump on FaceDown). May mean moving default Action onto FaceLeft, or a dedicated interact — Item/Checkpoint stays FaceRight. Conflict rules TBD when Lob ships.  
- Lob jump: start with boost when jumping off a carried / underfoot Lob only (not mid-air throw-down yet).  

**Detail / pseudo-code / inspector automation:** [plan-actors-editor.md](./plan-actors-editor.md).

## Stage 2 — Rooms as units

**Exit tile.** ✅ Added as `TileKind.Exit` in Stage 2a. Overlap restarts the room for now; Stage 3 wires room clear.

**Room data.** Extend `RoomDocument` with metadata the run loop needs:

```ts
type RoomBias = "jump" | "speed" | "air_jump" | "grapple" | "none";

type RoomPath = {
  bias: RoomBias;       // the build this route rewards
  difficulty: number;   // 1–5, how hard this route is *for its intended build*
  fallback?: boolean;   // clearable with no investment; every room needs one
};

type RoomData = LevelData & {
  id: string;
  tier: "normal" | "elite" | "boss";
  paths: RoomPath[];
  par_seconds: number;
};
```

The editor's `C` export already emits compact level data — extend `export_js()` to include the new fields so authoring stays in-editor.

### Rooms are multi-path, not build-agnostic

A room is **not** one neutral challenge. It's two or three routes to the same exit, each favouring a different build, and the room's identity is which route it makes cheapest. A room that "biases toward jump height" has a high direct route for players who invested in jumping, and a longer, more technical route for everyone else. The Grappler doesn't need a grapple-only room; he needs a route where the hook saves him time and risk.

This replaces the "no room may require an ability" framing. Requirements are fine per-route. What matters is:

**Invariant:** every room has at least one `fallback` path, clearable with zero investment. Biased paths may require anything. Nothing in a room can dead-end a run.

**What balancing means here:** the biased path should be *faster and riskier*, the fallback *slower and safer*. If the biased path is strictly better on every axis, the build stops being a choice and becomes a tax. The room timer (Stage 4) is what gives the fallback a real cost — taking the safe route should genuinely threaten the clock, otherwise everyone takes it every time and the bias does nothing.

**Verification** per room, using Stage 1's build panel: clear the fallback at zero build, then clear each biased path with its intended build, and record the times. The gap between those times *is* the balance number.

---

## Stage 3 — Run loop

```
character select → room → cleared? → reward pick (3 power-ups) → next room → ...
                     ↑                                              |
                     └──── death: spend a life, restart room ───────┘
```

**Run state** in a new `run.ts`, kept separate from `World` so the loop is testable without a canvas:

```ts
type RunState = {
  character: CharacterId;
  stats: Stats;
  power_ups: PowerUp[];
  lives: number;
  room_index: number;
  seed: number;
  history: { room_id: string; deaths: number; seconds: number }[];
};
```

**Screens.** `World` grows a mode: `playing` / `reward` / `dead`. Simplest version is a DOM overlay on top of the canvas rather than canvas-drawn UI — faster to iterate and we can steal the draggable card work in `src_rgl/` for the reward pick.

**Room switching.** `World.load_level` already exists and respawns the player; the run loop calls it with the next room and leaves `player.stats` untouched so the build persists across rooms.

**Seeded RNG** from the start (small xorshift in `rng.ts`). Reward offers and room picks both draw from it, so a seed plus a build is reproducible — required for comparing builds fairly.

---

## Stage 4 — Resources

- **Lives** (GDD §3.3): death restarts the room and decrements; zero ends the run.
- **Room timer** (GDD §3.4): per-room limit from `par_seconds`, expiry costs a life.
- **Potions** (GDD §3.2): one-time consumables. Mechanically these are temporary stat edits with a duration, so they reuse the Stage 1 power-up machinery plus a timer that reverts them.

---

## Stage 5 — Content and generation

Only worth doing once the loop is fun.

- **Hand-author 10–15 rooms** in the existing editor first, tagged by tier. These double as the module library.
- **Synergy power-ups** — the ones needing per-frame hooks in the player.
- **Chunk stitching** before full procgen — see [plans/piece-room-gen.md](./plans/piece-room-gen.md) (piece library exists; stitcher deferred). Reuses the editor and fails less mysteriously than a from-scratch generator.
- **Meta progression** (GDD §7) last.

---

## Open questions

**Elite scaling doesn't survive a tilemap.** GDD §2.3 says elite rooms scale obstacles ×1.5, but you can't scale a 16px grid by 1.5 at runtime without wrecking ceilings and platform runs. Elite difficulty has to come from authoring/generation parameters instead — gap width, ceiling clearance, hazard speed.

Multi-path rooms suggest a cleaner answer: **an elite is a room with fewer paths.** Take away the generous fallback and leave two tight biased routes, so an elite punishes an unfocused build rather than punishing reflexes. That reuses the path model instead of inventing a scaling system, and it keeps the "difficulty comes from your build" line intact. Worth trying before anything geometric.

**Does the fallback path stay zero-build clearable all run?** Keeping it zero-build forever guarantees no dead runs but may make late floors feel soft. The alternative is letting the fallback assume a floor-appropriate amount of investment, which means a badly-built run can hard-stop. Affects how we verify rooms, so it needs deciding before authoring the Stage 5 room pool.

**Grappler stat nerfs.** GDD §4.2 wants lower jump and run speed to pay for the hook. `GRAPPLER_STATS` in `grappler.ts` is deliberately empty for now because the demo level was authored around base numbers. Tune once Stage 2 rooms exist.

**Where does the Standard Guy's interest come from?** With no ability and only stat buffs, he risks being strictly boring rather than balanced. Possibly he gets more reward picks, or starts with a potion. Unresolved.
