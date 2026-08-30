# Formula AI: Grand Prix

3D AI racing competition. Developers build car "brains" as node graphs; the Grand Prix
runs on tracks the brains have never seen. Design spec:
[docs/superpowers/specs/2026-08-30-formula-ai-grand-prix-design.md](docs/superpowers/specs/2026-08-30-formula-ai-grand-prix-design.md).

## Environment

Godot 4.7.2 (standard, not .NET) lives in `tools/godot/` and is **not** in version control.
To recreate it, unzip the official `Godot_v4.7.2-stable_win64.zip` into that directory.

    GODOT=./tools/godot/Godot_v4.7.2-stable_win64_console.exe

| Task | Command |
| --- | --- |
| Open the editor | `$GODOT -e` |
| Import assets (first checkout / CI) | `$GODOT --headless --import` |
| Run the game | `$GODOT` |
| Run the test suite | `$GODOT --headless --script res://tests/run_tests.gd` |

The test runner exits non-zero on failure, so it drops straight into CI.

## Layout

    src/brain/    Brain runtime — node registry, graph, format, validator, evaluator.
    src/sim/      Sim core — track, car physics, sensor snapshot. Knows nothing about graphs.
    src/editor/   GraphEdit UI over the node registry. Never evaluates anything. (empty)
    src/race/     Race session and entry point. Later: grid, seed, replays, cameras.
    scenes/       Godot scenes.
    brains/       Brain files (verbose, hand-editable text format).
    tracks/       Track definitions.
    tests/        Headless tests; any `*_test.gd` extending `TestCase` is auto-discovered.

The four `src/` pieces are deliberately isolated — three of them are testable with no game running.

## Determinism

Non-negotiable from day one (spec §2.4). Fixed 60 Hz physics tick, all AI evaluated in
`_physics_process`, seeded RNG, **no `delta`-dependent logic anywhere in the sim**.
`physics_jitter_fix` and physics interpolation are off in `project.godot` because both
reintroduce frame-rate dependence; `tests/harness_test.gd` asserts they stay off.

## Brains

A brain is a text file of nodes and wires — see [brains/follower.brain](brains/follower.brain).
Nodes are the source of truth (spec 2.3); the format is verbose and hand-editable on
purpose, and it is the import path for weights trained outside the engine.

## Status

**Phase 1 vertical slice: done.** `brains/follower.brain` completes clean laps of the
test oval, driving only on egocentric senses — no absolute position anywhere.

Working: node registry, graph, brain file format, validator, evaluator, sensors and
control outputs, track, car physics, race session.

Next: the editor (GraphEdit over the registry), then Phase 2 — vector ports, Pack /
Unpack, and Dense Layer with weight import.
