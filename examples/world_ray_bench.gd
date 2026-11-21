extends Node

## Micro-benchmark: microseconds per world ray over N boxes, four ways: the script loop, the native
## flat scan, the native hierarchy one ray at a time, and the hierarchy with all rays in one call.
## Native rows need GameSpice Sim's library. Run:
##   godot --headless --path . res://examples/world_ray_bench.tscn -- --n=300 --rays=2000 --reps=5

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var n := 300
	var rays := 2000
	var reps := 5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			n = int(arg.substr(4))
		elif arg.begins_with("--rays="):
			rays = int(arg.substr(7))
		elif arg.begins_with("--reps="):
			reps = int(arg.substr(7))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var trace := DotTraceFlat.with_floor(0.0)
	for b in n:
		var at := Vector3(rng.randf_range(-45.0, 45.0), rng.randf_range(0.0, 4.0), rng.randf_range(-45.0, 45.0))
		trace.add_box(AABB(at, Vector3(rng.randf_range(0.5, 6.0), rng.randf_range(0.5, 5.0), rng.randf_range(0.5, 6.0))))
	var froms := PackedVector3Array()
	var dirs := PackedVector3Array()
	var reach := PackedFloat64Array()
	for r in rays:
		froms.append(Vector3(rng.randf_range(-45.0, 45.0), rng.randf_range(0.5, 2.5), rng.randf_range(-45.0, 45.0)))
		var a := rng.randf() * TAU
		dirs.append(Vector3(cos(a), rng.randf_range(-0.2, 0.2), sin(a)).normalized())
		reach.append(100.0)
	var native := trace.is_native()
	trace.prepare()
	var script_us := 0.0
	var scan_us := 0.0
	var bvh_us := 0.0
	var batch_us := 0.0
	var raw_us := 0.0
	for rep in reps:
		trace.native = false
		var t0 := Time.get_ticks_usec()
		for r in rays:
			trace._world_ray(froms[r], dirs[r], reach[r])
		script_us += float(Time.get_ticks_usec() - t0) / rays
		trace.native = true
		if native:
			var bvh: Object = trace._bvh
			trace._bvh = null
			t0 = Time.get_ticks_usec()
			for r in rays:
				trace._world_ray(froms[r], dirs[r], reach[r])
			scan_us += float(Time.get_ticks_usec() - t0) / rays
			trace._bvh = bvh
			t0 = Time.get_ticks_usec()
			for r in rays:
				trace._world_ray(froms[r], dirs[r], reach[r])
			bvh_us += float(Time.get_ticks_usec() - t0) / rays
			t0 = Time.get_ticks_usec()
			trace.world_rays(froms, dirs, reach)
			batch_us += float(Time.get_ticks_usec() - t0) / rays
			t0 = Time.get_ticks_usec()
			trace.world_rays_raw(froms, dirs, reach)
			raw_us += float(Time.get_ticks_usec() - t0) / rays
	print("BENCH n=%d rays=%d native=%s us/ray: script %.2f  native-scan %.2f  bvh %.2f  bvh-batch %.2f  bvh-batch-raw %.2f" % [n, rays, native, script_us / reps, scan_us / reps, bvh_us / reps, batch_us / reps, raw_us / reps])
	get_tree().quit(0)
