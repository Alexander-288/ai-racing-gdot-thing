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

    src/brain/    Brain runtime — node registry, graph load/validate/evaluate. No engine deps.
    src/sim/      Sim core — vehicle physics, track, weather, tyres, damage. Knows nothing about graphs.
    src/editor/   GraphEdit UI over the node registry. Never evaluates anything.
    src/race/     Race manager — grid, seed, replays, cameras, telemetry.
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

## Status

Environment set up. Next: Phase 1 vertical slice — node registry first, then graph
interpreter, then one car on one short track. Success condition is one hand-built brain
completing a clean lap.
