# GameSpice Combat

Health, damage and hit registration: analytic hitboxes, deterministic spread, lag compensation, and a resolver that turns a `GSShot` into damage under one set of rules. Weapons are GameSpice Weapon's; this addon does not know what a weapon is.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to combat.

**The distributable is `addons/gs_combat/`.** It requires [GameSpice Core](../gs-core) and nothing else (`ln -s ../../gs-core/addons/gs_core addons/gs_core`, gitignored). It works with gs-net, gs-weapon and gs-player-controller without naming any of their classes.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | anything: the two jobs, the self-describing shot, spread, hitboxes, ties, rewinds, origin correction, team zero, criticals, wire form, coupling, what is not here |
| [docs/history.md](docs/history.md) | touching `GSSpread` or the shot: the half-moon spread, the hand-copied constants, the shot that held a weapon, stacked team-mates |

## Layout

| Path | What |
| --- | --- |
| `core/gs_shot.gd` | `GSShot`: a shot that describes itself (damage, type, range, pellets, splash, `deferred`) |
| `core/gs_sentry.gd` | `GSSentry`: a deployed turret as data; `step(delta, now, candidates, can_see)` says when and where it fires, `find_spot` is the placement check (floor, slope, headroom, room); the game applies damage and draws it |
| `core/gs_fall_damage.gd`, `gs_fall_damage_rules.gd` | `GSFallDamage` (per player: a controller's `landed(impact)` becomes `apply_damage`, authority only) and `GSFallDamageRules` (`sv_falldamage`, `_threshold`, `_scale`; off by default; water and soft surfaces ignored) |
| `core/gs_defib.gd` | `GSDefib`: a defibrillator as data (charges, cooldown, reach, charge time, revive share, body-age limit); `check(now, body_age, distance)` says why a try refuses, the game owns the hold, the body and the revive |
| `core/gs_spread.gd` | `GSSpread`: deterministic scatter over GameSpice Core's `GSRandomStream` |
| `core/gs_hitzone.gd` | `GSHitzone`: fine zones (neck, hand, foot beside head, chest, stomach, arm, leg), `coarse()` fold-back, left/middle/right `side_of`; `mp_hitzones` (default 0) decides whether the fine ones carry their own multiplier; multipliers from `hit_groups:` in `cfg/addons/gs-combat/*.yml` |
| `core/gs_hitbox.gd`, `gs_hitbox_set.gd`, `gs_hit_group.gd` | analytic capsule, box and sphere hitboxes; tie-break by precedence; `GSHitGroup.bind_cvars(add, prefix, flags)` makes the server cvars `<prefix>_head_mult`, `_neck_`, `_stomach_`, `_leg_` |
| `core/gs_stomp.gd`, `gs_stomp_rules.gd` | `GSStomp` (pure head-landing detector: fall speed, head gap, reach, cooldown, team) and `GSStompRules` (`sv_stomp*` cvars; off by default; the game applies the damage and bounce, with `context.ignores_teams` for same-team) |
| `core/gs_health.gd`, `gs_damage.gd`, `gs_damage_type.gd` | health and armour, the damage event, falloff |
| `core/gs_penetration.gd`, `GSPelletTracer` | a shot's `GSPenetration` (power, per-material resistance, body cost per hit group): a pellet crosses walls (exit found by a reverse world ray, `shot.penetrations` records both faces) and bodies, damage falls per pass, `damage.context` gets `penetrated`/`wallbang`; `sv_penetration`, `_scale`, `_players`. `speed` + `reference_speed` (default 0, off) make costs scale with the round's speed, which falls with spent power. A one-sided sheet gets an exit at the material's `sheet_thickness` (unknown material stops the round). `sv_ricochet` (default off): a shallow hit on a profile-listed material reflects (`shot.ricochets`, `context["ricochet"]`) |
| `trace/` | `GSTrace` (world ray plus hitboxes; `material_fn(collider)` names a body's material, `material_shape_fn(collider, shape)` a box of a many-box body, asked first), `GSTracePhysics` (world via the physics server), `GSTraceFlat` (analytic boxes and a ground plane; with the gs-sim library the world ray runs native through a BVH, `prepare()` builds it, `world_rays(froms, directions, max_distances)` casts many rays in one call; `native = false` or no library is the script walk, same hits to the bit). `hold_bounds(sets)`/`release_bounds()` read every set's bounds centre once a shot instead of once a ray (the manager does it around the pellets under `sv_combat_bounds_cache`, default 1; same hits, checked in the prefilter section). `phase_timers` turns on `phase_us` per `PHASES` here and in the manager, for a profiler |
| `resolve/` | `GSDamageResolver`, `GSDamageRules`: teams, friendly fire, falloff, criticals; `GSDamageImmunity` (per-entity damage kinds ignored, set from a class profile, none by default) |
| `net/gs_combat_net_sync.gd` | `GSCombatNetSync`: health, armour and alive as data specs |
| `gs_combat_base.gd`, `gs_combat_manager.gd`, `gs_pellet_tracer.gd`, `gs_combat_cvars.gd` | `GSCombatManager` (extends `GSCombatBase`: exports, signals, registration, damage types): trace, rewind, resolve, apply; `GSPelletTracer` (pellet walk through walls, panes, ricochets, bodies) and `GSCombatCvars` (cvar table and writes) are its helpers, held by composition; a game swaps the pellet walker with `set_tracer(t)` (a `GSPelletTracer` subclass, e.g. a native twin; null restores the stock one), never by writing `_tracer` |
| `gs_combat_config.gd` | `GSCombatConfig`: rate limits, `max_origin_error`, lag compensation |
| `examples/combat_selftest.tscn` | the suite, all offline |

Paths except `examples/` are in `addons/gs_combat/`.

## Running and testing

The family's two steps ([family CLAUDE.md](../../CLAUDE.md#validating-anything)), then `godot --headless --path . res://examples/combat_selftest.tscn` (exits non-zero on any failure). Run it after any change to the trace, the resolver or the manager: several checks exist because the obvious implementation is wrong (the wall tie, the leaked rewind, the zero-team truce, the point-blank ray, the team-mate at the muzzle, the pass-through cvar read back on bind, a client following the server's level).

## Rules that bite

- The manager resolves and applies damage only where `is_authority`; a client traces for effects and never touches a `GSHealth`. [design](docs/design.md#two-jobs-two-places)
- A `GSShot` carries its own numbers; never make the manager read them off a weapon resource. [design](docs/design.md#a-gsshot-describes-itself)
- Spread is a pure integer function of `(shooter, tick, shot, pellet)`; never `randf()` or a stream, or client and server disagree silently. [design](docs/design.md#spread-cannot-come-from-a-random-number-generator)
- Keep the quadrant check in `_test_spread_determinism`; a max-angle check passes for a half-moon pattern. [history](docs/history.md#the-half-moon-spread)
- Hitboxes are arithmetic, not `Area3D`; world geometry goes through the physics server once. [design](docs/design.md#hitboxes-are-not-area3ds)
- Ties go to the wall (a hitbox must be strictly nearer); within a set, ties go to `precedence`, then `damage_scale`. [design](docs/design.md#ties)
- Refuse a shot before `_begin_rewind`; nothing between it and `_end_rewind` may return early. [design](docs/design.md#every-rewind-is-restored)
- `_correct_origin` relocates, never refuses, and does nothing without `set_authoritative_origin()` per entity. [design](docs/design.md#never-trust-the-clients-muzzle)
- A shot passes through a team-mate whose hitboxes hold the muzzle (`pass_through_sets`), never an enemy: point-blank on an enemy stays a 0 m hit. [design](docs/design.md#a-team-mate-holding-the-muzzle-is-not-a-target)
- `mp_friendlyfire` (0/1) rides the same `bind_cvars`; its default is the game's own `rules.friendly_fire`, so binding changes nothing until an operator sets it. A game builds its `GSDamageRules` as before and binds; it hard-codes nothing the operator should choose.
- `mp_teammate_passthrough` (0 never, 1 at the muzzle, 2 every team-mate in the line) is the manager's cvar; a game binds it with `combat.bind_cvars(add_cvar, FLAG_NOTIFY | FLAG_REPLICATED)` on its authoritative manager, never with its own copy, and each client's manager calls `follow_cvars(link)`. [design](docs/design.md#the-operator-decides-mp_teammate_passthrough)
- register_hitboxes/register_health ignore entity id 0 or a null node with a warning and count it (describe()["registrations_refused"]); register after the entity has its network id.
- Team 0 is "no team" in `_same_team`, or a free-for-all with friendly fire off has nobody able to hurt anybody. [design](docs/design.md#zero-is-not-a-team)
- Critical defaults change no number; the roll is a hash of the hit, not a stream. [design](docs/design.md#a-critical-is-a-flag-before-it-is-a-number)
- A hitbox's `limb` tag (not `group`, which is about damage) resolves a hit to limb, world point and impulse: `GSCombatManager.limb_hit`, or `limb_target_fn(entity) -> Object` whose `hit(point, amount, impulse)` is called (GameSpice NPC's `GSNpcLimbs`, duck-typed; never import it). `limb_min_damage` (`cfg/addons/gs-combat/*.yml`, per limb or `default`) is the least resolved damage that counts. [design](docs/design.md#limbs)
- Health replicates as integers; ammunition is GameSpice Weapon's `GSWeaponNetSync`, not here. [design](docs/design.md#wire-form)
- Name no class outside GameSpice Core; net types are strings resolved by the game's bridge. [design](docs/design.md#coupling-nothing-is-imported)

Deliberately not here: projectiles as entities, anything about what a player holds, ballistics, presentation, ammunition pickups, damage over time. [design](docs/design.md#deliberately-not-here)
