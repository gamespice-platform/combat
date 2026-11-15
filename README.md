Health, damage and hit registration for a Godot 4.7+ shooter. It gives you hitboxes, scatter that is the same everywhere, lag compensation, and a resolver that turns a shot into damage under one set of rules. A client can predict its own fire while the server stays the authority. Part of the [dot-*](https://github.com/gamespice-platform) family.

It needs [dot-core](https://github.com/gamespice-platform/core). It works with dot-net, [dot-weapon](https://github.com/gamespice-platform/weapon) and dot-player-controller without importing any of them. It does not know what a weapon is: a `DotShot` describes itself (damage, range, splash), so a rifle, a bow, a thrown charge, a trap or a hazard all produce one the same way.

## Install

1. Copy `addons/dot_combat/` and `addons/dot_core/` into your project.
2. Enable both in *Project > Project Settings > Plugins*.

## Quick start

```gdscript
# Once, on the server.
var combat := DotCombatManager.new()
combat.trace = DotTracePhysics.for_world(get_world_3d())
combat.rules = DotDamageRules.strict()
add_child(combat)

# Per shootable entity.
hitbox_set.register_with(combat, player_id)
combat.register_health(player_id, health)

# Per shot. Anything can build one; dot-weapon usually does.
var shot := DotShot.make(&"rifle", player_id, tick, index)
shot.origin = eye_position
shot.direction = aim
shot.damage = 25.0
shot.max_range = 200.0
shot.scatter()

if is_server:
    combat.resolve_shot(shot, client_view_tick)
```

Something else decides that a shot happened. dot-combat decides what it hit. `resolve_shot()` runs only where the game is authoritative, because a client that resolved its own shots would decide who dies.

## What is in it

| Class | What it does |
| --- | --- |
| `DotHealth` | Health, armour, regeneration and spawn protection, counted in ticks so it replays. |
| `DotDamage` | One damage event, carrying its own scaling trace so a surprising number can be explained. |
| `DotDamageType` | Falloff, armour share, self and friendly scales. A game adds its own. |
| `DotHitGroup` | Named regions and their multipliers. A table, not an enum. |
| `DotHitbox`, `DotHitboxSet` | Capsules, boxes and spheres tested analytically against a ray. |
| `DotTrace` | Where a shot goes. `DotTracePhysics` for a real world, `DotTraceFlat` for a headless one. |
| `DotShot` | One thing that was fired. |
| `DotSpread` | Deterministic scatter, the reason prediction works. |
| `DotDamageRules`, `DotDamageResolver` | Friendly fire, self damage, hit groups, criticals, falloff and clamping, in one order. |
| `DotCombatManager` | Tracing, lag compensation, damage, kill reporting. |
| `DotCombatNetSync` | What to replicate, without naming a dot-net type. |

## Three failures it is built around

| Failure | How it is avoided |
| --- | --- |
| A shot that disagrees with itself. | Spread from a random stream differs on the predicting client, the server and every replay. `DotSpread` is a pure function of shooter, tick, shot and pellet, so all agree. |
| A shot through a wall. | World geometry and hitboxes are traced together, and a tie between a hitbox and a wall goes to the wall. |
| A rewind that leaks. | Lag compensation moves hitboxes into the past. Every path out of `resolve_shot()`, including refusals, restores them. |

## Lag compensation

dot-combat does not name dot-net. Two callables turn compensation on:

```gdscript
combat.rewind_fn = func(view_tick: float) -> void:
    net.history.rewind(view_tick, net.registry.all())
combat.restore_fn = net.history.restore
```

Unset, shots resolve against the present. That is right for a listen server and wrong for anyone with latency.

More: [docs/design.md](docs/design.md).

## Test

```bash
godot --headless --path . --import
godot --headless --path . res://examples/combat_selftest.tscn
```

The self-test is offline and exits non-zero on any failure.

## Status

Built and maintained with Claude Code. The test suites pass, but little of this has been in front of real players yet. Please report rough edges by opening an issue.

## Licence

MIT. See [LICENSE](LICENSE). Only the TMC back-end web infrastructure is not open source.
