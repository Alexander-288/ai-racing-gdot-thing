# Contributing

Thanks for looking. This is a young project with strong opinions in a few places; this
page is mostly about which places those are.

## Getting set up

1. Get Godot **4.7.2, standard build (not .NET)** from
   [godotengine.org](https://godotengine.org/download/archive/) and unzip it into
   `tools/godot/`. That directory is gitignored — the engine is never committed.
2. Import the assets once: `./tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --import`
3. Run the tests. They must pass before you start, or the problem is your setup, not
   your change.

```
./tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --script res://tests/run_tests.gd
```

On Linux/macOS use the matching official build; nothing else changes.

## Tests

Any `*_test.gd` under `tests/` that extends `TestCase` is discovered automatically — no
registration list to update. Put it next to its subject: `tests/brain/`, `tests/sim/`,
`tests/editor/`, `tests/race/`.

`src/brain/`, `src/sim/` and most of `src/editor/` are testable with no game running,
and that is on purpose. If a change to one of those can only be tested by driving a
car around, that is usually a sign the change belongs somewhere else.

The runner exits non-zero on failure, so CI runs exactly the command above.

## The rules that are not negotiable

**Determinism.** Same brains and same seed must produce the same race, tick for tick,
on any machine and at any speed multiplier.

- All AI and sim logic runs in `_physics_process` at a fixed 60 Hz.
- No `delta`-dependent logic anywhere in the sim. Ever.
- RNG is seeded and threaded through; never call a global unseeded random.
- `physics_jitter_fix` and physics interpolation stay off in `project.godot`.
  `tests/harness_test.gd` asserts this, so a change that switches them on fails CI.
- Speeding a race up runs *more ticks per frame*, never bigger ticks.

**Brains cannot know where they are.** Every sensor is egocentric: rays, radar, self
state, and checkpoints relative to the car's own nose. Nothing may hand a brain a world
position, a lap-relative distance, or a track identity. That constraint is what makes an
unseen track a real test.

**Nodes are the source of truth.** The brain file format is verbose and hand-editable
on purpose. If you add a node type, add it to the registry, give it a test, and keep
the format readable — it is the import path for weights trained outside the engine, so
it has to stay exact as well as legible.

**The editor never evaluates.** `src/editor/` builds and validates graphs; it does not
run them. Evaluation lives in `src/brain/`, driving lives in `src/sim/`.

## Style

- GDScript with types. `project.godot` promotes untyped declarations and unsafe access
  to warnings; a change should not add new ones.
- Comments explain *why*, not *what*. Short, and only where the reason is not obvious
  from the code.
- Keep `src/brain/`, `src/sim/`, `src/editor/` and `src/race/` isolated from each other.
  The sim knows nothing about graphs; the brain runtime knows nothing about Godot nodes.

## Commits and pull requests

- One idea per commit. Commit messages here are a short sentence saying what changed
  and, where it matters, why — not a `type(scope):` prefix.
- Say in the PR what you tested and paste the test-run result.
- New behaviour comes with a test. Bug fixes come with the test that failed first.

## Contributing brains

Brain files are welcome, especially ones that beat the reference ladder. Put a comment
block at the top of the file saying what it does differently and how you tuned it —
`brains/ace.brain` is the model. A brain tuned on one circuit and never checked on
another is a fine thing to share, as long as the file says so.

## License

This project is licensed under the **GNU AGPL v3.0 or later**. By opening a pull
request you agree that your contribution is licensed under the same terms.
