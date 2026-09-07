# Formula AI: Grand Prix

[![tests](https://github.com/Alexander-288/ai-racing-gdot-thing/actions/workflows/tests.yml/badge.svg)](https://github.com/Alexander-288/ai-racing-gdot-thing/actions/workflows/tests.yml)

A 3D AI racing competition, built in Godot 4. You do not drive; you build a car's
**brain** as a node graph, and the Grand Prix runs it on tracks the brain has never
seen.

Every car is mechanically identical. Every sensor budget is fixed. No brain can know
where it is in the world — it drives on egocentric senses alone: what its rays hit,
what its radar sees, where the next checkpoints lie relative to its own nose. The brain
is the only variable, so a race is a straight comparison of the ideas in it.

Brains are files, not code. They are plain text, hand-editable, and the same format is
the import path for weights trained outside the engine — the game only ever runs a
network forwards.

## Quickstart

Godot 4.7.2 (standard, not .NET) lives in `tools/godot/` and is **not** in version
control. To recreate it, unzip the official `Godot_v4.7.2-stable_win64.zip` into that
directory.

    GODOT=./tools/godot/Godot_v4.7.2-stable_win64_console.exe
    $GODOT --headless --import      # first checkout: import assets
    $GODOT                          # opens the brain editor

| Task | Command |
| --- | --- |
| Open the editor | `$GODOT -e` |
| Import assets (first checkout / CI) | `$GODOT --headless --import` |
| Open the brain editor (the main scene) | `$GODOT` |
| Run the test suite | `$GODOT --headless --script res://tests/run_tests.gd` |

The test runner exits non-zero on failure, so it drops straight into CI. Linux and
macOS work the same way — point `GODOT` at the matching official build.

From the editor: open a brain from `brains/`, hit **Test Drive** to watch it lap the
test oval, or **Grid...** to put fourteen cars on a circuit and race them.

## Layout

    src/brain/    Brain runtime — node registry, graph, format, validator, evaluator.
    src/sim/      Sim core — track, car physics, sensor snapshot. Knows nothing about graphs.
    src/editor/   GraphEdit UI over the node registry. Never evaluates anything.
    src/race/     Race session and entry point. Later: grid, seed, replays, cameras.
    scenes/       Godot scenes.
    brains/       Brain files (verbose, hand-editable text format).
    tracks/       Track definitions.
    tests/        Headless tests; any `*_test.gd` extending `TestCase` is auto-discovered.

The four `src/` pieces are deliberately isolated — three of them are testable with no
game running.

## Determinism

Non-negotiable from day one. Fixed 60 Hz physics tick, all AI evaluated in
`_physics_process`, seeded RNG, **no `delta`-dependent logic anywhere in the sim**.
`physics_jitter_fix` and physics interpolation are off in `project.godot` because both
reintroduce frame-rate dependence; `tests/harness_test.gd` asserts they stay off.

## Brains

A brain is a text file of nodes and wires. Four reference brains ship as a ladder:

| brain | drives on | unseen tracks |
| --- | --- | --- |
| [follower](brains/follower.brain) | the route alone, one fixed throttle | finishes, slowly |
| [braker](brains/braker.brain) | the route, lifting for corners | quickest on its own circuit, takes damage elsewhere |
| [racer](brains/racer.brain) | the route **and** its rays | as quick, and never touches a wall |
| [ace](brains/ace.brain) | everything but a network | about a sixth quicker again, still clean |

The braker beats the racer on the circuit it was tuned for and loses to it everywhere
else. That gap is the whole reason held-out tracks are the scoring mechanism.
`Track.generated(seed)` draws from a published distribution, so a track pool can be
public in shape and secret in seed.

Nodes are the source of truth; the format is verbose and hand-editable on purpose, and
it is the import path for weights trained outside the engine.

## Status

**Phase 1 vertical slice: done.** `brains/follower.brain` completes clean laps of the
test oval, driving only on egocentric senses — no absolute position anywhere.

**The editor runs.** It is the main scene, so `$GODOT` opens it: a palette built from
the registry, boxes coloured by node role, live validation, and save/load of `.brain`
files. It never evaluates anything. Hand-written brain files carry no positions, so
anything at the origin is laid out left to right by how far downstream it sits.

**The circuit is a real test.** `Track.grand_prix()` has corners from 16 m to nearly
straight, and only 11 checkpoints, placed at corner entry / apex / exit and down the
middle of straights — sparse and irregular on purpose, so they give route and never a
racing line. The track is walled: running out of road is a collision that costs speed
and does lasting damage, not a quiet slide onto grass.

Cornering is grip-limited, so turn radius grows with the *square* of speed. That is
what makes braking a decision: flat out laps quickly and wrecks the car, cruising is
clean but slow, and lifting only for corners beats both.

**Test Drive works.** The editor's Test Drive button runs the open brain on the test
oval in a top-down wireframe: track edges, checkpoints, the car, and its 14 rays drawn
from the same angle list the sensors use — so the picture cannot disagree with what the
brain was told. Pause, Step, Reset, 1x/5x/20x, and Watch next to follow a different car.

**Grid...** opens the field: a row per car, each picking its own brain from the
ones that ship with the game, the ones you have saved, or the brain open in the
editor. Add and remove cars, fill the grid, choose a track. A brain that will not
load or will not validate is named before the race starts rather than during it.

Racing copies of one brain is self-play; racing different ones is the only way to
find out whether a brain can overtake, defend, or survive contact with a driver
that behaves differently. Speeding up runs more ticks per
frame, never bigger ticks, so it stays deterministic.

The wireframe is an instrument, not the graphical suite. Cel shading, cameras and the
broadcast overlay are Phase 6; this gets deleted then.

Working: node registry, graph, brain file format, validator, evaluator, sensors and
control outputs, track, car physics, race session, editor, debug view.

**Phase 2 done.** Ports carry bundles as well as numbers: `Pack` / `Unpack` move
between the two, `Ray Ring` gives the whole eight-ray ring on one wire, and
`Dense Layer` is a whole network layer in one node — an N x M matrix, M biases and
a choice of tanh / relu / sigmoid, evaluated once per tick like everything else.

The engine only runs networks forwards. Weights are trained outside by whatever
means and imported through the brain file, which is why that format stays readable
and exact. A mis-shaped matrix is rejected on load, not discovered on track.

Fairness budgets are enforced: 64 neurons and 8 accumulators per brain. Both are
tuning knobs; what matters is that the check runs before a race.

**Phase 3, in part.** There is a grid: fourteen cars, staggered two abreast, each
with its own brain. Cars collide with each other, rays see them, and four radar
slots report a rival picked by rule rather than by name. DRS opens the wing for a
much higher top speed and much less grip.

Deferred to later: slipstream, weather, tyre wear. DRS has no activation zones or
one-second rule yet for the same reason — both need slipstream.

Rays are named by set and index rather than a flat number: a **ring** of eight
looking all the way round, and a **cone** of six looking forward. Six is even, so
the cone is symmetric with no ray on the nose — dead ahead is the ring's first
ray, and duplicating it would waste one of the six.

One Ray node carries up to eight readings. The + and - on the node add and remove
them, each with its own set and index.

Fourteen cars cost 13.4 ms a tick against a 16.6 ms budget, down from 27.1 ms.

Next: Phase 4 — headless batch racing, self-play and telemetry.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — how to get the engine, run the tests, and what
a change is expected to look like here.

## License

[GNU Affero General Public License v3.0 or later](LICENSE).

In short: you may use, study, change and share this, including commercially, as long as
anything you distribute — or run as a network service people interact with — is offered
under the same license, with source.

The Godot engine itself is separately licensed (MIT) and is not part of this repository.
