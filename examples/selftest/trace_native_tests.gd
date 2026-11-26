extends "res://examples/selftest/hitbox_native_tests.gd"

## GSTrace.ray walking every hitbox set in one native call (GSSimHitboxRay.nearest_in_sets)
## against the script walk: seeded random players in random poses behind random walls, some
## disabled, excluded by entity or by set, one null slot; every hit equal to the bit. Without
## the library both sides are the script, and the check says so.


func _test_trace_native() -> void:
	_section("trace: native set walk against script")
	var loaded := ClassDB.class_exists(&"GSSimHitboxRay")
	_check(GSTrace.sets_are_native() == loaded, "the native set walk is on exactly when the library is loaded")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261126
	var holder := Node3D.new()
	add_child(holder)
	var cases := 0
	var hits := 0
	var bodies := 0
	var same := 0
	var first_miss := ""
	var script_us := 0
	var native_us := 0
	var world_us := 0
	for level in 6:
		var trace := GSTraceFlat.with_floor(-1.0)
		for w in rng.randi_range(2, 6):
			var a := Vector3(rng.randf_range(-10.0, 10.0), -1.0, rng.randf_range(-10.0, 10.0))
			var b := a + Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-6.0, 6.0))
			trace.add_wall(a, b, rng.randf_range(0.5, 3.0), rng.randf_range(0.1, 0.6))
		trace.prepare()
		var sets: Array[GSHitboxSet] = []
		var entities: Array[Node3D] = []
		for n in 32:
			var entity := Node3D.new()
			entity.position = Vector3(rng.randf_range(-10.0, 10.0), 0.0, rng.randf_range(-10.0, 10.0))
			entity.rotation.y = rng.randf_range(-PI, PI)
			holder.add_child(entity)
			var set_node := _random_set(rng, n + level)
			set_node.bounds_radius = rng.randf_range(1.0, 3.5)
			set_node.bounds_offset = Vector3(0.0, rng.randf_range(0.0, 1.2), 0.0)
			set_node.enabled = rng.randf() > 0.08
			entity.add_child(set_node)
			set_node.refresh()
			sets.append(set_node)
			entities.append(entity)
		sets[rng.randi_range(0, sets.size() - 1)] = null
		for r in 400:
			var aim := sets[rng.randi_range(0, sets.size() - 1)]
			var target := Vector3(rng.randf_range(-10.0, 10.0), rng.randf_range(-1.0, 2.0), rng.randf_range(-10.0, 10.0))
			if aim != null and not aim.hitboxes().is_empty():
				var boxes := aim.hitboxes()
				target = boxes[rng.randi_range(0, boxes.size() - 1)].global_position
				target += Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
			var from := Vector3(rng.randf_range(-14.0, 14.0), rng.randf_range(-0.5, 2.5), rng.randf_range(-14.0, 14.0))
			if r % 23 == 0 and aim != null:
				from = aim.global_position
			var dir := target - from
			dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
			var reach := rng.randf_range(2.0, 40.0)
			trace.exclude = []
			var pick := rng.randi_range(0, 31)
			match r % 4:
				1:
					trace.exclude = [entities[pick]]
				2:
					trace.exclude = [null, sets[pick]]
			var t0 := Time.get_ticks_usec()
			trace.ray(from, dir, reach)
			var t1 := Time.get_ticks_usec()
			GSTrace.native_sets = false
			var a := trace.ray(from, dir, reach, sets)
			var t2 := Time.get_ticks_usec()
			GSTrace.native_sets = true
			var b := trace.ray(from, dir, reach, sets)
			var t3 := Time.get_ticks_usec()
			world_us += t1 - t0
			script_us += t2 - t1
			native_us += t3 - t2
			cases += 1
			if a.ok():
				hits += 1
			if a.hitbox != null:
				bodies += 1
			if a.distance == b.distance and a.point == b.point and a.normal == b.normal and a.hitbox == b.hitbox and a.group == b.group and a.blocked == b.blocked and a.entity == b.entity and a.inside_start == b.inside_start and a.material == b.material:
				same += 1
			elif first_miss == "":
				first_miss = "level %d ray %d: script %s %s %s, native %s %s %s" % [level, r, a.distance, a.point, a.hitbox, b.distance, b.point, b.hitbox]
		for entity in entities:
			entity.queue_free()
			holder.remove_child(entity)
	GSTrace.native_sets = true
	holder.queue_free()
	remove_child(holder)
	_check(same == cases and bodies > cases / 5 and hits > bodies, "%d random rays over 32 posed players behind walls (%d hits, %d on a body): the %s walk matches the script to the bit" % [cases, hits, bodies, "native" if loaded else "script (no library)"], first_miss)
	print("        ray, 32 sets: world only %.2f us, script walk %.2f us, %s walk %.2f us" % [float(world_us) / cases, float(script_us) / cases, "native" if loaded else "script", float(native_us) / cases])
	var manager := _make_manager(GSTraceFlat.with_floor(0.0), GSDamageRules.new())
	_check(manager.set_cvar(GSCombatManager.CVAR_TRACE_NATIVE, "0") and not GSTrace.native_sets, "sv_trace_native 0 forces the script walk")
	_check(manager.set_cvar(GSCombatManager.CVAR_TRACE_NATIVE, "1") and GSTrace.native_sets, "and 1 turns the native walk back on")
	_done()
