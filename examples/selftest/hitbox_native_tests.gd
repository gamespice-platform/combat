extends "res://examples/selftest/prefilter_tests.gd"

## GSHitboxSet.intersect_ray with GameSpice Sim's native picker (GSSimHitboxRay) against the
## script loop: random sets of rotated, scaled, tied hitboxes and rays, every hit equal to the bit.
## Without the library both sides are the script, and the check says so.


func _test_hitbox_native() -> void:
	_section("hitbox set: native pick against script")
	var loaded := ClassDB.class_exists(&"GSSimHitboxRay")
	_check(GSHitboxSet.is_native() == loaded, "the native pick is on exactly when the library is loaded")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261125
	var holder := Node3D.new()
	add_child(holder)
	var cases := 0
	var hits := 0
	var same := 0
	var ties := 0
	var first_miss := ""
	var script_us := 0
	var native_us := 0
	for n in 60:
		var set_node := _random_set(rng, n)
		holder.add_child(set_node)
		set_node.refresh()
		var boxes := set_node.hitboxes()
		for r in 120:
			var target := boxes[rng.randi_range(0, boxes.size() - 1)].global_position if not boxes.is_empty() else Vector3.ZERO
			target += Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
			var from := Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-3.0, 4.0), rng.randf_range(-6.0, 6.0))
			if r % 17 == 0 and not boxes.is_empty():
				from = boxes[0].global_position
			var dir := target - from
			dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
			var reach := rng.randf_range(0.5, 15.0)
			GSHitboxSet.native = false
			var t0 := Time.get_ticks_usec()
			var a := set_node.intersect_ray(from, dir, reach)
			var t1 := Time.get_ticks_usec()
			GSHitboxSet.native = true
			var b := set_node.intersect_ray(from, dir, reach)
			native_us += Time.get_ticks_usec() - t1
			script_us += t1 - t0
			cases += 1
			if a.ok():
				hits += 1
			if a.ok() and a.hitbox != null and a.hitbox.has_meta(&"twin"):
				ties += 1
			if a.distance == b.distance and a.point == b.point and a.normal == b.normal and a.hitbox == b.hitbox and a.group == b.group:
				same += 1
			elif first_miss == "":
				first_miss = "set %d ray %d: script %s %s %s, native %s %s %s" % [n, r, a.distance, a.point, a.hitbox, b.distance, b.point, b.hitbox]
		set_node.queue_free()
		holder.remove_child(set_node)
	GSHitboxSet.native = true
	holder.queue_free()
	remove_child(holder)
	_check(same == cases and hits > cases / 5, "%d random rays (%d hits, %d on tied twins): the %s pick matches the script to the bit" % [cases, hits, ties, "native" if loaded else "script (no library)"], first_miss)
	print("        intersect_ray: script %.2f us/call, %s %.2f us/call" % [float(script_us) / cases, "native" if loaded else "script", float(native_us) / cases])
	var manager := _make_manager(GSTraceFlat.with_floor(0.0), GSDamageRules.new())
	_check(manager.set_cvar(GSCombatManager.CVAR_HITBOX_NATIVE, "0") and not GSHitboxSet.native, "sv_hitbox_native 0 forces the script loop")
	_check(manager.set_cvar(GSCombatManager.CVAR_HITBOX_NATIVE, "1") and GSHitboxSet.native, "and 1 turns the native pick back on")
	_done()


## A set of 1 to 12 hitboxes of every shape, rotated, sometimes scaled unevenly, some disabled,
## and some exact twins that differ only in precedence or damage scale (the set's tie rules).
func _random_set(rng: RandomNumberGenerator, n: int) -> GSHitboxSet:
	var set_node := GSHitboxSet.new()
	set_node.bounds_radius = 50.0
	set_node.position = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.5, 0.5), rng.randf_range(-1.0, 1.0))
	for i in rng.randi_range(1, 12):
		var box := GSHitbox.new()
		box.shape = rng.randi_range(0, 2) as GSHitbox.Shape
		box.radius = rng.randf_range(0.05, 0.6)
		box.height = rng.randf_range(0.1, 2.0)
		box.half_extents = Vector3(rng.randf_range(0.0, 0.6), rng.randf_range(0.05, 0.9), rng.randf_range(0.05, 0.6))
		box.precedence = rng.randi_range(0, 2)
		box.damage_scale = [1.0, 1.0, 2.0, 4.0][rng.randi_range(0, 3)]
		box.enabled = rng.randf() > 0.1
		box.group = StringName("g%d" % i)
		var basis := Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI)))
		if n % 3 == 1:
			basis = basis.scaled(Vector3(rng.randf_range(0.5, 2.0), rng.randf_range(0.5, 2.0), rng.randf_range(0.5, 2.0)))
		box.transform = Transform3D(basis, Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.0, 2.0), rng.randf_range(-1.5, 1.5)))
		set_node.add_child(box)
		if rng.randf() < 0.3:
			var twin: GSHitbox = box.duplicate()
			twin.precedence = box.precedence + rng.randi_range(-1, 1)
			twin.damage_scale = box.damage_scale * [0.5, 1.0, 2.0][rng.randi_range(0, 2)]
			twin.group = StringName("t%d" % i)
			twin.set_meta(&"twin", true)
			set_node.add_child(twin)
	return set_node
