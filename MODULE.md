# lil-guy

Godot 4.7 project for the platformer. The authoring lab and pixel source live
in the sibling repo `../idea`. `ideas/` and `plans/` here started as copies of
that repo's notes.

## Layout

- `src/` — typed GDScript, grouped by gameplay domain.
- `scenes/` — `.tscn` files; mirrors the domains in `src/` where useful.
- `resources/` — editable `.tres` tuning and content resources.
- `assets/` — Godot copies of art, audio, fonts, and shaders. Edit sheets in
  `../idea/assets` and re-run `src/tools/sync_art.gd`.
- `tests/` — headless GDScript tests and test scenes.
- `project.godot` — project-wide display, physics, input, and rendering settings.
- `ideas/` — game design notes. Edit this copy for game ideas.
- `plans/` — design and implementation briefs. Edit this copy for game work.
  `pixel-editor-features.md`, `level-draw.md`, and the TypeScript editor
  sections are reference from the authoring lab, not tasks for this repo.
- `todo.md` — follow-ups for the Godot project.
- `PORTING.md` — agent-sized remaining port tasks, dependencies, and acceptance
  criteria.

Use lowercase snake_case paths. Godot resource paths are case-sensitive on
case-sensitive export targets even when authored on Windows.
