extends RefCounted

## GameSpice Combat's API level. The rule for bumping it is on [GSAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed.
# 2: GSDamageRules.pass_through_team_mate_at_muzzle, GSCombatManager.pass_through_fn and
#    pass_through_sets(), GSDamageResolver.are_team_mates(), GSHitboxSet.contains_point().
# 3: GSDamageRules.pass_through_team_mates, PASS_THROUGH_* and pass_through_level() /
#    set_pass_through_level(); GSCombatManager.CVAR_TEAMMATE_PASSTHROUGH, cvar_specs(),
#    bind_cvars() and set_cvar() (the mp_teammate_passthrough server cvar).
# 4: GSCombatManager.follow_cvars() (a client keeps the server's replicated cvars).
# 5: GSSentry (a deployable auto-turret: target choice, ammo, lifetime, placement check).
# 6: GSHitGroup.bind_cvars (the head, neck, stomach and leg multipliers as server cvars).
const LEVEL := 6
const OLDEST := 1
