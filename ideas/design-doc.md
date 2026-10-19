# Roguelite Platformer – Game Design Document

**Canonical (editable):** [Google Doc](https://docs.google.com/document/d/1ubqsIKv5zJQ3KMelW0JHNI6dN_04vsH6VdKnFsGyFbE/edit?tab=t.0)

Local mirror of the GDD for offline reference and repo search. Update the Google Doc first; refresh this file when the design changes meaningfully.

---

## 1. Core Concept

A fast-paced roguelite platformer inspired by Slay the Spire, where each room is a short, procedurally generated platforming challenge. Rooms do not test specific skills; instead, they test the player's build — the combination of power-ups, potions, character abilities, and strategic resource management.

The difficulty of any given room depends on how the player has chosen to build their character. Some rooms will naturally favor certain builds, but the game's philosophy is:

> Rooms are neutral challenges whose difficulty emerges from the player's chosen upgrades and consumables.

This creates dynamic gameplay where each run feels unique, and each room becomes a puzzle of how to apply your current abilities.

## Philosophical Ideas

Belief/hope in a future/greater good/progress from past, even if unfounded, is what powers reality. Belief alters reality. Nostalgia/despair has equally potent effect on reality (future). This can become a physical manifestation in later levels?
(inspired by "The OTHER Most Philosophical Video Game Ever Made", by @maxderrat, youtube video)


---

## 2. Game Structure

### 2.1 Room Flow

- Each floor consists of a single platforming room.
- Rooms are short but meaningful — longer than a Celeste screen, shorter than a Mario level.
- After completing a room, the player chooses a reward and proceeds to the next.
- The run structure mirrors Slay the Spire: branching paths, elites, shops, events, bosses.

### 2.2 Procedural Generation

Rooms are built from modular obstacle components:

- Spike pits under inverted staircases
- Ceiling dips requiring controlled double jumps
- Horizontal gaps with variable height constraints
- Moving platforms and timing hazards
- Grapple-friendly anchor points
- Vertical climb segments
- Escape sequences (lava, boulder, rising water)

### 2.3 Difficulty Scaling

Borrowing STS terminology:

- **Normal rooms** → base obstacle size
- **Elite rooms** → obstacles scaled ×1.5 (longer gaps, tighter ceilings, faster hazards)
- **Boss rooms** → unique handcrafted or semi-procedural challenges

---

## 3. Player Progression

### 3.1 Power-Ups (Permanent for the Run)

Completing a room grants a power-up. Examples:

- **Stat boosts:**
  - East/west velocity
  - Jump height
  - Extra double jump
  - Faster acceleration
- **Synergy upgrades:**
  - Gain +X horizontal speed per jump performed before landing
  - After grappling, next jump height is increased
  - Double jumps recharge faster when airborne
  - Speed increases while ascending

Power-ups stack and interact, creating emergent builds.

Some power-ups could have down-side. an idea for this is that bufs pools are tiered an so are debuf pools.
you get a random buf an that buf rolls the related tier debuf pool. higher buf pools corespond to debuf 
pools with more punishing debufs. they could also have mild or no debuf in the pool. 

### 3.2 Potions (Consumables)

One-time use items that are powerful and require timing:

- Temporary speed burst
- Temporary invulnerability
- Auto-grapple
- Slow-motion window
- Triple jump for one room
- Instant vertical boost

Potions encourage strategic decision-making: use them early for safety or save them for elite rooms.

make rooms harder if they horde potions too much (if we have potion chance similar to slay the spire, 
then if potion chance is hight and the player has full potions increase difficulty in levels until they use a potion)

### 3.3 Lives as a Resource

Players have multiple lives, but a limited number per run.

- Losing a life restarts the room.
- Lives become a strategic resource:
  - Spend a life to brute-force a hard room?
  - Save lives for elite or boss rooms?
  - Risk speed for safety?

### 3.4 Time Pressure

Most rooms have a time limit.

- Encourages fast decision-making.
- Allows speed-based builds to shine.
- Prevents overly cautious play.

---

## 4. Characters

Start - you have no abilities you are tossed into a pit that you can't get out of without out

### 4.1 The Standard Guy

A balanced character with no special mechanics.

- Decent speed
- Decent jump height
- Baseline mobility
- Ideal for learning the game

### 4.2 The Grappler

A mobility-focused character with a grappling hook.

- Quick-fire, quick-retract grapple
- Short range (e.g., 5 units)
- Lower base jump height
- Lower run speed
- High skill ceiling

Rooms can include grapple-friendly shortcuts or alternate paths.

### 4.2 The Pogo guy

A pogo guy, with a pogo stick!!

- can pogo
- has secret tripple jump, if jump out of pogo timed right
- "perfect pogo" powerup/bonus
- ...
- ...

Rooms can do stuff.

---

## 5. Room Types

- **Standard platforming** – neutral challenges
- **Elite platforming** – scaled obstacles, tighter layouts
- **Timed escape** – lava, boulder, rising water
- **Precision jump rooms** – tight ceilings, controlled double jumps
- **Speed gauntlets** – long horizontal segments (maybe; sequences of moving platforms, timed jumps, occasional enemy hazards)
- **Vertical climb rooms** – upward progression under pressure
- **Puzzle-platform rooms** – optional logic or timing puzzles
- **escort mission** – bring an enemy to end of the level for one jump

---

## 6. Obstacle Modules

Examples of modular components used in procedural generation:

- Inverted staircases with spikes below
- Ceiling dips requiring controlled double jumps
- Moving platforms with variable timing
- Grapple-only shortcuts
- Collapsing platforms
- Wind zones that push horizontally
- Sticky floors that reduce speed
- Bounce pads that alter jump arcs
- Moving death / trigger volumes (entity surfaces on a patrol)
- Path-following platforms and simple enemy patrols (prototype direction: composed entity pieces, not one class per combo — see `plan.md` / `src/entities/`)

---

## 7. Roguelite Meta Progression

While the core gameplay resets each run, players can unlock:

- New characters
- New obstacle modules
- New power-ups
  - 
- New potions
  - jetpack
- Cosmetic upgrades
- Additional room types

This keeps long-term progression engaging.

---

## 8. Example Run Flow

1. Choose a character.
2. Enter first room.
3. Complete room → choose a power-up.
4. Choose next path (normal, elite, shop, event).
5. Use potions strategically.
6. Manage lives carefully.
7. Reach boss → defeat → ascend to next act.
8. Continue until death or victory.

---

## 9. Future Expansion Ideas

- Characters with unique traversal mechanics (teleport dash, hover jump, wall-run)
- Rooms with environmental modifiers (low gravity, darkness, fog)
- Synergy-based relics that alter core rules
- Challenge modes (endless, time attack, hardcore)
- Co-op or race mode

---

## 10. ART

All background art must be at least 840×504 to allow for slight paralax on our 640×384 game screen (this is the ratio we stick with). we grow pixel size but never deviate from the ratio of 640×384.

Characters are varied but grappler is 80x64 and pogo is 72x88. multiples of 8 are important, it's our smallest tile unit.

## 10. Summary

This game blends the strategic buildcrafting of Slay the Spire with the kinetic challenge of platforming. Rooms are neutral tests of how well the player has constructed their build, and each run becomes a unique combination of mobility, timing, resource management, and improvisation.

The design supports deep replayability, expressive builds, and high-skill movement while remaining accessible to new players.
