# lil-guy

Godot 4.7 project for the platformer.

## Layout

- `src/` — typed GDScript, grouped by gameplay domain.
- `scenes/` — `.tscn` files; mirrors the domains in `src/` where useful.
- `resources/` — editable `.tres` tuning and content resources.
- `assets/` — art, audio, fonts, and shaders imported by Godot.
- `tests/` — headless GDScript tests and test scenes.
- `project.godot` — project-wide display, physics, input, and rendering settings.
- `todo.md` — follow-ups for the Godot project.
- `PORTING.md` — agent-sized remaining port tasks, dependencies, and acceptance
  criteria.

Use lowercase snake_case paths. Godot resource paths are case-sensitive on
case-sensitive export targets even when authored on Windows.
