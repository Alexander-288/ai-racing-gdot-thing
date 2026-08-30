extends Node3D
## Placeholder entry point. Phase 1 replaces this with the vertical slice:
## one car, one short track, one hand-built brain completing a clean lap.

func _ready() -> void:
	print("Formula AI: Grand Prix — Godot %s" % Engine.get_version_info().string)
	print("physics tick: %d Hz" % Engine.physics_ticks_per_second)
