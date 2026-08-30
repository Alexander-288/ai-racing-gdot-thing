extends TestCase
## Smoke test: proves the runner discovers and executes tests, and that the
## determinism-critical project settings are actually in effect.

func test_assertions_run() -> void:
	assert_true(true, "runner executes test methods")
	assert_almost_eq(0.1 + 0.2, 0.3, 1e-9, "float compare works")

func test_fixed_physics_tick() -> void:
	assert_eq(Engine.physics_ticks_per_second, 60, "physics tick is pinned for determinism")
	assert_almost_eq(ProjectSettings.get_setting("physics/common/physics_jitter_fix"), 0.0, 1e-9,
		"jitter fix must be off — it makes physics delta frame-rate dependent")
