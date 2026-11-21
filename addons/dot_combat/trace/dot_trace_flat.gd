class_name DotTraceFlat
extends DotTrace

## Traces world geometry against a list of analytic boxes and planes.
##
## The backend for a headless server, a self-test and a deterministic replay — none of
## which has a populated physics space, and the last of which must not depend on one:
## a physics query is a floating-point result from a solver whose internal state
## depends on what ran before it, and a replay that re-derives a different answer than
## the original is a reconciliation loop that never converges.
##
## The same reason GameSpice Player Controller ships [code]DotFpsFlatBody[/code]. This is not a
## toy: a deathmatch level made of boxes is a deathmatch level, and every self-test in
## this project runs against one.

## Ground plane height. Set to -INF for no ground.
var floor_y: float = -INF

## Axis-aligned solid boxes, in world space. Edit through [method add_box] and [method clear];
## after changing it directly, call [method repack] (a different count alone falls back to script).
var boxes: Array[AABB] = []

## Material id per box, parallel to [member boxes] (missing = none).
var box_materials: Array[StringName] = []

## Walk the boxes natively when GameSpice Sim's [code]DotSimFlatTrace[/code] is loaded (same hits to
## the bit; the script loop is the web build's path and the fallback). Off forces the script.
var native := true

## [member boxes] as low then high corner each, what the native walk reads.
var _corners := PackedVector3Array()

## The stateless native walker, shared by every trace and thread; null without the library.
static var _walker: Object = ClassDB.instantiate(&"DotSimFlatTrace") if ClassDB.class_exists(&"DotSimFlatTrace") else null


static func with_floor(y: float = 0.0) -> DotTraceFlat:
	# Not this class's own name. A script that names itself in an expression, loaded after
	# its base, cuts Godot 4.7.2's exit teardown short and leaks every script loaded before
	# it. See docs/gdscript-hazards.md, "A script that names itself".
	var trace := new()
	trace.floor_y = y
	return trace


## Adds a solid box. Returns self, so a level is one chained expression.
func add_box(box: AABB, material: StringName = &"") -> DotTraceFlat:
	var b := box.abs()
	boxes.append(b)
	box_materials.append(material)
	_corners.append(b.position)
	_corners.append(b.position + b.size)
	return self


## Adds a wall as a box of [param thickness] between two points on the XZ plane.
##
## What a test level is actually made of, and building one out of [AABB]s by hand is
## error-prone in a way that produces walls one axis thick in the wrong axis.
func add_wall(
	from: Vector3,
	to: Vector3,
	height: float,
	thickness: float = 0.25
) -> DotTraceFlat:
	var half := thickness * 0.5
	var min_point := Vector3(
		minf(from.x, to.x) - half,
		minf(from.y, to.y),
		minf(from.z, to.z) - half,
	)
	var size := Vector3(
		absf(to.x - from.x) + thickness,
		height,
		absf(to.z - from.z) + thickness,
	)
	return add_box(AABB(min_point, size))


func clear() -> void:
	boxes.clear()
	box_materials.clear()
	_corners.clear()


## Rebuilds the native walk's copy of [member boxes] after a direct edit.
func repack() -> void:
	_corners.clear()
	for b in boxes:
		_corners.append(b.position)
		_corners.append(b.position + b.size)


## Whether rays walk the boxes natively now.
func is_native() -> bool:
	return native and _walker != null and _corners.size() == boxes.size() * 2


func _world_ray(
	from: Vector3,
	direction: Vector3,
	max_distance: float
) -> DotHitbox.Hit:
	var best := DotHitbox.Hit.new()
	var nearest := max_distance

	if floor_y > -INF and direction.y < -0.000001:
		var t := (floor_y - from.y) / direction.y
		if t >= 0.0 and t <= nearest:
			nearest = t
			best = _make_hit(from + direction * t, Vector3.UP, t)

	if native and _walker != null and _corners.size() == boxes.size() * 2:
		var i: int = _walker.nearest(_corners, from, direction, nearest)
		if i < 0:
			return best
		var box := boxes[i]
		var t := _ray_aabb(from, direction, box, nearest)
		best = _make_hit(from + direction * t, _box_normal(box, from + direction * t), t)
		if i < box_materials.size():
			best.material = box_materials[i]
		return best

	for i in boxes.size():
		var box := boxes[i]
		var t := _ray_aabb(from, direction, box, nearest)
		if t < 0.0:
			continue
		nearest = t
		best = _make_hit(from + direction * t, _box_normal(box, from + direction * t), t)
		if i < box_materials.size():
			best.material = box_materials[i]

	return best


static func _make_hit(
	point: Vector3,
	normal: Vector3,
	distance: float
) -> DotHitbox.Hit:
	var hit := DotHitbox.Hit.new()
	hit.point = point
	hit.normal = normal
	hit.distance = distance
	hit.blocked = true
	hit.group = DotHitGroup.GENERIC
	return hit


## Slab test. Returns the entry distance, or -1 for a miss or a farther hit.
##
## A ray starting inside a box returns 0 rather than the exit distance: a muzzle
## inside a wall is a shot that goes nowhere, and reporting the exit would let it out
## the far side.
static func _ray_aabb(
	from: Vector3,
	direction: Vector3,
	box: AABB,
	limit: float
) -> float:
	var t_min := 0.0
	var t_max := limit
	var box_end := box.position + box.size

	for axis in range(3):
		var d := direction[axis]
		var o := from[axis]

		if absf(d) < 0.000001:
			if o < box.position[axis] or o > box_end[axis]:
				return -1.0
			continue

		var inverse := 1.0 / d
		var t1 := (box.position[axis] - o) * inverse
		var t2 := (box_end[axis] - o) * inverse

		if t1 > t2:
			var swap := t1
			t1 = t2
			t2 = swap

		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)

		if t_min > t_max:
			return -1.0

	return t_min


static func _box_normal(box: AABB, point: Vector3) -> Vector3:
	var centre := box.position + box.size * 0.5
	var offset := point - centre
	var half := box.size * 0.5

	var scaled := Vector3(
		offset.x / maxf(0.0001, half.x),
		offset.y / maxf(0.0001, half.y),
		offset.z / maxf(0.0001, half.z),
	)

	var axis := 0
	for i in range(1, 3):
		if absf(scaled[i]) > absf(scaled[axis]):
			axis = i

	var normal := Vector3.ZERO
	normal[axis] = signf(scaled[axis])
	return normal


func describe() -> Dictionary:
	var out := super.describe()
	out["boxes"] = boxes.size()
	out["floor"] = "none" if floor_y == -INF else str(floor_y)
	return out
