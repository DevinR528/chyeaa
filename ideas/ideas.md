# Ideas

## Roguelite platformer (main vision)

Full design doc: **[design-doc.md](./design-doc.md)** (local mirror) · [Google Doc](https://docs.google.com/document/d/1ubqsIKv5zJQ3KMelW0JHNI6dN_04vsH6VdKnFsGyFbE/edit?tab=t.0) (canonical) · build plan: **[plan.md](./plan.md)**

**One-liner:** Slay the Spire run structure, but each node is a short procedural platforming room. Difficulty comes from your build (power-ups, potions, lives, time), not from rooms testing one fixed skill.

**Prototype home:** `src/` — movement, grapple, tile editor.

**Open design threads** (from GDD §9 and notes in-doc):

- Speed gauntlets — called out as “kinda dumb” in the doc; maybe salvage pieces (moving platforms + momentum checks)
- Room procgen from obstacle modules (§6) — deliberately deferred; hand-author rooms in the editor first, they become the module library
- Run loop (rewards, branching, elites, potions, lives, timer) — design only so far; see [plan.md](./plan.md)
- Rooms are multi-path: two or three routes to the exit, each favouring a different build. A room "biases toward high jump" by making the jump route direct and the others longer/harder. Balance = tuning the cost gap between routes, not making rooms neutral
- Standard Guy has no ability by design (he's the yardstick for each room's fallback path) — but that may make him boring to play
- **Entity composition** — props are surface + optional motion/breakable (`TileProp`); next pieces: path follow, bounce-pad bullets / spawners, Mario-like enemies as actor components (not one class per combo). See [plan.md](./plan.md) Stage 2a+
- Movable death / movable breakable — already authorable via surface + `fragile` / travel on existing prefabs; tune in editor before adding more prefabs
- **Builds** — Stage 1 starter cards in pause menu; expand catalog once the demo room proves build-sensitive difficulty
- Per-character control remaps (Action for pogo vs grapple) — data hook exists; UI still global-only

## Art

 - transition screens, can we get away with pixel size being different (smaller, more detail)
 - what do items/relics look like, what does the pick screen UI/art look like
 - what does the overworld/map look like

## Things todo:

 - We need more level entities/obstacles (Celeste moving blocks/clouds)
   - Austin has spike windmill things
     - pogo windmill
     - grapple lineups where you are blocked by the other 2 windmill blades 2/3 of the time so you have to lineup and time your grapple shot
     - grapple could also acts as "pull to you" and there is a key on one and grapple blocks on the other, if you hit the grapple you fall to your death (like you don't want to grapple since it's over death pit
   - moving death block (I think we basically have this)
   - player gets += platform momentum (grime/celeste/etc.)
   - trampoline bounce pad things, these would give you at least 2x jump height
   - water???
   - multiple (partial) switches/keys/key pieces, you must collect (or switch on) all
   - flip level over (castelvania SOTN does this, 200% because 1/2 way through castle flips)
   - sinking platforms, others rise
   - the ball (or Lob as AI calls it) could be turned into a key, and you have to escort the key
   - blocks that grapple and pogo push forwards (or down in pogo's case) they can "land" and be used, they also move slower than the player so you could "ride" them
