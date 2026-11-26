class_name GSTrace
extends RefCounted

## Where a shot goes. The single place a weapon asks "what did I hit".
##
## [b]Why this is an abstraction and not just a physics query.[/b] The same reason
## GameSpice Player Controller has [code]GSFpsBody[/code]: a headless server, a self-test and
## a deterministic replay all need to trace against a world, and only one of those
## three has a populated physics space. Subclass it and a game can trace against
## anything — a heightmap, a voxel grid, a set of analytic boxes — without weapons
## knowing.
##
## Subclasses implement [method _world_ray] only. The hitbox walk, the world-geometry
## precedence and the exclusion rules are here, because getting them wrong is how a
## shot damages a player through a wall and every backend would otherwise have to get
## them right independently.

## Layers world geometry lives on, for backends that have layers.
## A hit nearer than this is not rechecked against the world, nor is the stretch of the reverse ray that close to the hit.
const WALL_RECHECK_MIN := 0.02

## Microseconds per part of [method ray], summed while [member phase_timers] is on (a profiler's switch; off, each
## part costs one branch): the world ray, the hitbox-set walk, the reverse wall ray, the observer.
const PHASES: Array[StringName] = [&"world", &"sets", &"reverse", &"observer"]
static var phase_us := PackedInt64Array([0, 0, 0, 0])
## Read by a profiler, never by the game: timings on, [member phase_us] grows.
static var phase_timers := false

var collision_mask: int = 1

## Nodes whose hitboxes are never tested. The shooter, usually.
var exclude: Array = []

## Bodies the world query ignores, for backends that have RIDs.
var exclude_rids: Array[RID] = []

## Told of every ray: [code]call(from, direction, distance)[/code], [param distance] being the nearest hit or the full range.
## What lets dropped weapons be shot without the trace knowing about them.
var ray_observer: Callable = Callable()

## `func(collider) -> StringName`: the surface material of a world hit, for backends that have a collider.
var material_fn: Callable = Callable()

## `func(collider, shape_index) -> StringName`, asked before [member material_fn]: one static body built of many boxes names each box's material on its shape.
var material_shape_fn: Callable = Callable()

## Told of every splash query: [code]call(centre, radius)[/code].
var sphere_observer: Callable = Callable()

# The bounds of [member _held_sets] read once by [method hold_bounds]: centre and squared radius by index.
var _held_sets: Array[GSHitboxSet] = []
var _held_centres := PackedVector3Array()
var _held_radii := PackedFloat64Array()


## The world-geometry hit, or a miss. Override this and nothing else.
##
## Must return the [i]nearest[/i] solid surface along the ray, with
## [member GSHitbox.Hit.blocked] set. Returning a farther one lets shots through
## walls; returning nothing at all makes every wall in the game transparent to
## gunfire, which is the failure this base class cannot detect for you.
func _world_ray(
	_from: Vector3,
	_direction: Vector3,
	_max_distance: float
) -> GSHitbox.Hit:
	return GSHitbox.Hit.new()


## Traces a ray against world geometry and a set of entities.
##
## Returns the nearest hit of either kind. A world hit that is nearer than every
## hitbox comes back with [member GSHitbox.Hit.blocked] set and no entity, which is
## how a caller tells "hit a wall" from "hit nobody" — the first should still spawn a
## decal and the second should not.
##
## [param direction] must be unit length; it is not normalised here because every
## caller already has a normalised aim vector and normalising twice per pellet of a
## twelve-pellet shotgun is measurable.
## Reads every set's bounds centre once, for a shot whose rays all test [param sets] while nothing moves them: [method ray] given this same list (the same array, not a copy) uses the reads. [method release_bounds] after the last ray.
func hold_bounds(sets: Array[GSHitboxSet]) -> void:
	_held_sets = sets
	_held_centres.resize(sets.size())
	_held_radii.resize(sets.size())
	for i in sets.size():
		var set_node := sets[i]
		if set_node == null or not is_instance_valid(set_node):
			continue
		_held_centres[i] = set_node.global_transform * set_node.bounds_offset
		_held_radii[i] = set_node.bounds_radius * set_node.bounds_radius


## Forgets [method hold_bounds]: rays read every set's transform again.
func release_bounds() -> void:
	_held_centres.resize(0)


func ray(
	from: Vector3,
	direction: Vector3,
	max_distance: float,
	sets: Array[GSHitboxSet] = []
) -> GSHitbox.Hit:
	var lap := Time.get_ticks_usec() if phase_timers else 0
	var world := _world_ray(from, direction, max_distance)
	lap = _lap(0, lap)

	if world.ok():
		world.blocked = true

	# The world hit shortens the search: a hitbox behind a wall cannot be hit, and
	# testing to the full range and comparing afterwards would walk every hitbox in
	# the level for a shot that stopped two metres away.
	var limit := world.distance if world.ok() else max_distance
	var best := world

	# Held bounds (hold_bounds) only for the very list they were read from, and only while it has not grown.
	var held := not _held_centres.is_empty() and is_same(sets, _held_sets) and sets.size() == _held_centres.size()
	for i in sets.size():
		var set_node := sets[i]
		if set_node == null or not is_instance_valid(set_node):
			continue

		# The bounds first: a few hundred bodies a shot, nearly all of them nowhere near the line.
		# The sphere test of GSHitboxSet._ray_hits_bounds inline, same arithmetic: a call per set is most of the cost of a miss.
		var offset: Vector3
		var gap: float
		if held:
			offset = from - _held_centres[i]
			gap = offset.length_squared() - _held_radii[i]
		else:
			offset = from - set_node.global_transform * set_node.bounds_offset
			gap = offset.length_squared() - set_node.bounds_radius * set_node.bounds_radius
		var along := offset.dot(direction)
		if gap > 0.0:
			if along > 0.0:
				continue
			var depth := along * along - gap
			if depth < 0.0 or -along - sqrt(depth) > limit:
				continue

		# may_be_hit is the bounds test just done plus enabled and empty; intersect_ray asks those two again
		# itself, so with held bounds only enabled is asked here (it keeps a disabled set out of _is_excluded).
		if held:
			if not set_node.enabled:
				continue
		elif not set_node.may_be_hit(from, direction, limit):
			continue

		if _is_excluded(set_node):
			continue

		var hit := set_node.intersect_ray(from, direction, limit)

		if not hit.ok():
			continue

		if hit.distance > limit:
			continue

		# Strictly nearer, so a hitbox exactly level with a wall surface loses to the
		# wall. A player standing flush against cover is the common case and giving
		# the tie to the hitbox is how they get shot through it.
		if best.ok() and hit.distance >= best.distance:
			continue

		best = hit
		limit = hit.distance

	lap = _lap(1, lap)

	# The reverse ray: a physics ray that starts inside a wall finds nothing there, so a shooter
	# pressed into geometry would reach the far side. From the hit back to the muzzle it enters
	# the wall from outside and cannot miss it.
	if best.ok() and not best.blocked and best.distance > WALL_RECHECK_MIN:
		var back := _world_ray(best.point, -direction, best.distance - WALL_RECHECK_MIN)
		if back.ok():
			back.blocked = true
			back.inside_start = true
			back.distance = best.distance - back.distance
			best = back
	lap = _lap(2, lap)

	if ray_observer.is_valid():
		ray_observer.call(from, direction, best.distance if best.ok() else max_distance)
	_lap(3, lap)
	return best


## Adds the time since [param since] to [member phase_us][[param phase]] and returns now; 0 while [member phase_timers] is off.
static func _lap(phase: int, since: int) -> int:
	if not phase_timers:
		return 0
	var now := Time.get_ticks_usec()
	phase_us[phase] += now - since
	return now


## Whether nothing solid stands between two points.
##
## For interest management, for bot vision and for splash damage, which should not
## travel through a wall. Entity hitboxes deliberately do not block: a team-mate
## standing in a doorway does not stop an explosion.
func line_of_sight(from: Vector3, to: Vector3) -> bool:
	var offset := to - from
	var distance := offset.length()

	if distance <= 0.0001:
		return true

	var hit := _world_ray(from, offset / distance, distance)
	return not hit.ok()


## Every entity with a hitbox inside a sphere, nearest first.
##
## What splash damage is built on. [param require_line_of_sight] runs one
## [method line_of_sight] per candidate against its closest point, so a grenade on the
## other side of a wall does not damage through it.
func sphere_overlap(
	centre: Vector3,
	radius: float,
	sets: Array[GSHitboxSet] = [],
	require_line_of_sight: bool = true
) -> Array[GSHitboxSet]:
	if sphere_observer.is_valid():
		sphere_observer.call(centre, radius)
	var found: Array[GSHitboxSet] = []
	var distances: Array[float] = []

	for set_node in sets:
		if set_node == null or not is_instance_valid(set_node):
			continue

		if _is_excluded(set_node):
			continue

		if not set_node.overlaps_sphere(centre, radius):
			continue

		var closest := set_node.closest_point(centre)

		if require_line_of_sight and not line_of_sight(centre, closest):
			continue

		# Insertion sort: splash reaches a handful of entities and this avoids
		# building a parallel structure to sort.
		var distance := centre.distance_to(closest)
		var index := distances.size()
		while index > 0 and distances[index - 1] > distance:
			index -= 1
		found.insert(index, set_node)
		distances.insert(index, distance)

	return found


func _is_excluded(set_node: GSHitboxSet) -> bool:
	if exclude.is_empty():
		return false

	var entity := set_node.entity_owner()

	for node in exclude:
		if node == null:
			continue
		if node == entity or node == set_node:
			return true

	return false


func describe() -> Dictionary:
	return {
		"backend": get_script().resource_path.get_file(),
		"mask": collision_mask,
		"excluded": exclude.size(),
	}
