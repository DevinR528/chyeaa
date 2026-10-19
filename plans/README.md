# Plans

Git-tracked design / implementation briefs for this repo.

| Doc | Status | What |
|-----|--------|------|
| [`../plan.md`](../plan.md) | active | Staged build plan (Stages 0–5) — stays at repo root |
| [`../plan-actors-editor.md`](../plan-actors-editor.md) | reference | Actors + editor detail (Stage 2a++) |
| [`../plan-game-events.md`](../plan-game-events.md) | active | Domain events → SFX / anim markers |
| [`piece-room-gen.md`](./piece-room-gen.md) | **deferred** | Piece stitcher, flex corridors, `generate_room` |
| [`pixel-editor-features.md`](./pixel-editor-features.md) | **deferred** | Pixel editor: transforms, block-out, shade, PP, harmonies, onion |
| [`level-draw.md`](./level-draw.md) | not started | Viewport cull and a retained level picture. Stamp bitset already shipped |

**Convention:** new long-lived plans go in this folder. Root `plan*.md` files can migrate here over time; keep `plan.md` at root as the overview until then.

Cursor’s `.cursor/plans/` is for agent session plans — prefer promoting lasting work into `plans/` so it is reviewed and versioned with the code.
