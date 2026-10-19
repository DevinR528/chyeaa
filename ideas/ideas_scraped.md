# Ideas scraped from Discord DM

Source: browser XHR dumps → [`tmp_discord.json`](../tmp_discord.json), conversation from **8/29/26 10:25 AM** onward (Devin + Austin).

Cross-checked against [`ideas.md`](./ideas.md), [`power-ups.md`](./power-ups.md), [`design-doc.md`](./design-doc.md), and root [`todo.md`](../todo.md). Items marked **(new)** are not clearly written down elsewhere; **(overlap)** already live in those docs (kept short so the scrap is still searchable).

---

## Design goals / feel

- **(new)** Success bar: if you play the strategy, a non-platformer can clear; if you ignore strategy, late game should feel like late Celeste. (8/29 Devin; Austin: strategy helps but you still have to get decent at platforming.)
- **(new)** Ascensions-style overall progression (STS). (9/1 Austin)
- **(overlap)** Multi-path rooms: optimal path + harder alternates by build (grapple easy / floor jump hard / pogo hard; floor can have enemies). — already in ideas.md / GDD
- **(new)** All paths stay *valid* for every character; difficulty comes from build + skill, not soft-locking a char off a route. Alternate: char-specific obstacle pools for procgen. Still an open tension. (9/1)

## Story / presentation

- **(new)** Story stays light (less non-gameplay animation). Sci-fi framing is the easy explanation for wild abilities. (9/1 Austin)
- **(new)** Story delivery like Grime / Hollow Knight / STS: almost no cutscenes; lore through item/artifact text. ~2 slide-style moments (mid + late/end), like old STS art. (9/1)
- **(new)** No mouth lipsync — humanoids just “Mmm hmm” / Charlie Brown noise. (9/17 Austin, half-joke half-serious)
- **(new)** Character bible (à la that GDC talk): per-char lore, world ties, inspirations in a shared doc; Devin animates from that. (9/9)
- **(new)** Relics / items that pay homage or gently parody other games (STS relic shout-outs). (9/19)

## Characters / art direction

- **(overlap)** Grappler inherits from base “average jump/dash” guy. — GDD §4
- **(new)** Pogo pig keeps a **tool** (pogo stick) so there can be a swipe anim; octopus needs a tool too (e.g. Darkwing Duck–style plunger gun) — funnier, and lets tentacles shorten for a squarer sprite. (9/19)
- **(new)** Third traversal kit still TBD: free dash / another mechanic. (9/19 Devin)
- **(new)** Pogo look: high-tech goggles (forehead ok) + lounge / Fallout-ish spacesuit, more “spacey” colors. Later bit: old man with walker as pogo guy. (9/11, 9/23–9/24)
- **(new)** Potion overuse gag for old-man pogo: get younger until you crawl, or “addicted → baby” side effect. (9/24)
- **(overlap)** Pogo frame tech: jump within ~2–3 frames of pogo → extra midair jump / perfect-pogo bonus. — already in GDD §4.2

## Level entities / room ideas

- **(overlap)** Bounce enemies like Kaizo Mario — timing objects, not combat bags; everyone interacts, different tools (pogo bounce vs other). Escort: drag a bounce-enemy to the exit for one jump. — GDD §5 escort + todo actors
- **(overlap)** Hit block toggles other blocks on/off. — todo.md “on/off switches”
- **(new)** Character-specific **semi-secret exits** that can appear randomly. (9/11)
- **(new)** Elite “Infested Prism” rooms: every time you do X (e.g. jump), the room escalates (platforms faster, etc.). Movement ability *is* the puzzle. Kaizo on/off-on-jump as cousin. (9/23)
- **(new)** Optional level preview / lookout binoculars (Celeste does this) — especially early, to teach mechanics without being too hand-holdy. (9/23)
- **(new)** Celeste B-sides analogue: find cassette tapes → harder versions of rooms. (9/23)
- **(new)** Wall-bash (King Knight / *Heart of Mycelium* style). Level length reference: King Knight stages on the shorter side. (9/24)
- **(new)** Throw / Lob material as tasteful **non-pixel** shader prop (metal, glass that drips away); timed blocks dematerialize / rematerialize the same way. (9/19)
- **(overlap)** Rewind potion = Sands of Time; only buffer rewind state when potion is held (or debug). — power-ups.md

## Procgen / pacing

- **(new)** Worry: handcrafted platformers care about mechanic flow; pure room RNG may dump wall-jump once then not again for floors. Builder may need pacing rules, not just piece glue. (9/22 Austin)
- **(new)** Practical compromise: hand-author first floor (and/or first run per character) for intro pacing; later floors freer. Or build full layouts from reusable pieces and only generate which *path* is favored. (9/22)
- **(overlap)** Hand-author pieces first → library for generation. — ideas.md / plans

## Audio

- **(new)** Soundtrack matters early; every level should feel like a banger. External people (Chris? Austin’s contacts) for music/SFX once there’s something to show. (9/2, 9/23)

---

## References

Web links and Discord embeds from the same DM window (message text + embed title/description).

### Design / project

| When | Who | Link | Why it was shared |
|------|-----|------|-------------------|
| 8/29 | Austin | [Roguelite Platformer GDD](https://docs.google.com/document/d/1ubqsIKv5zJQ3KMelW0JHNI6dN_04vsH6VdKnFsGyFbE/edit?usp=sharing) | Canonical design doc kickoff |
| 9/1 | Devin | [github.com/DevinR528/lil_guy](https://github.com/DevinR528/lil_guy) | Early prototype repo |
| 9/20 | Devin | [huggingface/funes](https://github.com/huggingface/funes) | Long-term LLM memory skill (tooling, not game design) |

### Gameplay / tone inspirations

| When | Who | Link | Why it was shared |
|------|-----|------|-------------------|
| 9/9 | Devin | [Blasphemous II Dev Diary EP07](https://youtu.be/v2nMNzCX8o8?t=319) (t=319) | Character bible: per-char lore, world ties, inspirations in a shared doc |
| 9/13 | Devin | [His Holiness Escribar monologue](https://www.youtube.com/watch?v=AWTXBzszA5Y) | Final-boss / sparse dialog tone (“amazing final boss dialog”) |
| 9/24 | Devin | [Heart of Mycelium – Official Gameplay Trailer](https://www.youtube.com/watch?v=0s1-H1skO9I) | Wall-bash (King Knight / Shovel Knight); also play Specter + King Knight — shorter level length target |

### Art / animation craft

| When | Who | Link | Why it was shared |
|------|-----|------|-------------------|
| 9/11 | Devin | [2d animated strut walk](https://www.youtube.com/watch?v=ySS6_Le3PdI&t=8s) | Strut walk reference for pogo guy |
| 9/17 | Devin | [pixeljoint 121392](https://pixeljoint.com/pixelart/121392.htm) · [artist profile 4012](https://pixeljoint.com/p/4012.htm) | Detail level / scale target for pixel art |
| 9/19 | Devin | [Pixel Art Run Animation Tutorial](https://www.youtube.com/watch?v=PEyQP5_CYf0&t=479) (t=479) | Run cycle from two shapes — silhouette readability |

### Audio

| When | Who | Link | Why it was shared |
|------|-----|------|-------------------|
| 9/1 | Devin | [Last Bible III OST – Underworld Forest](https://www.youtube.com/watch?v=61ccGdcS2vw) | “Every levels song banger” vibe reference |

---

## Skipped on purpose

Chat noise (status, tooling, pixel-editor debugging, “play Well Dweller / Celeste”, file sizes, etc.) and pure art-process notes that aren’t design ideas.
