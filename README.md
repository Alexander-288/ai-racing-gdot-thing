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
| Open the brain editor (the main scene) | `$GODOT` |
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

A brain is a text file of nodes and wires. Two reference brains ship as a ladder
(spec 2.10): [brains/follower.brain](brains/follower.brain) is the naive lap completer,
[brains/braker.brain](brains/braker.brain) lifts and brakes for corners and beats it on
both time and damage.
Nodes are the source of truth (spec 2.3); the format is verbose and hand-editable on
purpose, and it is the import path for weights trained outside the engine.

## Status

**Phase 1 vertical slice: done.** `brains/follower.brain` completes clean laps of the
test oval, driving only on egocentric senses — no absolute position anywhere.

**The editor runs.** It is the main scene, so `$GODOT` opens it: a palette built from
the registry, boxes coloured by node role, live validation, and save/load of `.brain`
files. It never evaluates anything (spec 3). Hand-written brain files carry no
positions, so anything at the origin is laid out left to right by how far downstream
it sits.

**The circuit is a real test.** `Track.grand_prix()` has corners from 16 m to nearly
straight, and only 11 checkpoints, placed at corner entry / apex / exit and down the
middle of straights — sparse and irregular on purpose, so they give route and never a
racing line (spec 2.5). The track is walled: running out of road is a collision that
costs speed and does lasting damage, not a quiet slide onto grass.

Cornering is grip-limited, so turn radius grows with the *square* of speed. That is
what makes braking a decision: flat out laps quickly and wrecks the car, cruising is
clean but slow, and lifting only for corners beats both.

**Test Drive works.** The editor's Test Drive button runs the open brain on the test
oval in a top-down wireframe: track edges, checkpoints, the car, and its 14 rays drawn
from the same angle list the sensors use — so the picture cannot disagree with what the
brain was told. Pause, Step, Reset, and 1x/5x/20x. Speeding up runs more ticks per
frame, never bigger ticks, so it stays deterministic.

The wireframe is an instrument, not the graphical suite. Cel shading, cameras and the
broadcast overlay are Phase 6; this gets deleted then.

Working: node registry, graph, brain file format, validator, evaluator, sensors and
control outputs, track, car physics, race session, editor, debug view.

Next: Phase 2 — vector ports, Pack / Unpack, and Dense Layer with weight import.
