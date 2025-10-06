---@diagnostic disable: undefined-global

local auto_dominator = {}

local DOMINATOR_ITEMS = {
    "item_helm_of_the_dominator",
    "item_helm_of_the_overlord",
}

local BIG_NEUTRAL_NAMES = {
    npc_dota_neutral_alpha_wolf = true,
    npc_dota_neutral_centaur_khan = true,
    npc_dota_neutral_dark_troll_warlord = true,
    npc_dota_neutral_enraged_wildkin = true,
    npc_dota_neutral_hellbear_smasher = true,
    npc_dota_neutral_mud_golem = true,
    npc_dota_neutral_ogre_bruiser = true,
    npc_dota_neutral_ogre_magi = true,
    npc_dota_neutral_polar_furbolg_ursa_warrior = true,
    npc_dota_neutral_satyr_hellcaller = true,
    npc_dota_neutral_warpine_raider = true,
}

local BIG_NEUTRAL_MIN_HEALTH = 700
local CAST_RANGE_BUFFER = 50
local ORDER_COOLDOWN = 0.25
local FOLLOW_ORDER_INTERVAL = 0.75
local FOLLOW_DISTANCE_LEASH = 250
local ABILITY_ORDER_COOLDOWN = 0.6
local NO_TARGET_FALLBACK_RANGE = 350

local SPECIAL_VALUE_KEYS = {
    "radius",
    "range",
    "max_distance",
    "distance",
    "cast_range",
    "cast_radius",
    "aoe",
    "area_of_effect",
}

local ABILITY_RULES = {
    centaur_khan_war_stomp = { cast = "no_target", range = 325 },
    hellbear_smasher_thunder_clap = { cast = "no_target", range = 350 },
    polar_furbolg_ursa_warrior_thunder_clap = { cast = "no_target", range = 350 },
    dark_troll_warlord_ensnare = { cast = "target", range = 550, allow_zero_damage = true },
    satyr_hellcaller_shockwave = { cast = "point", range = 950 },
    mudgolem_hurl_boulder = { cast = "target", range = 800 },
    rock_golem_hurl_boulder = { cast = "target", range = 800 },
    greater_mudgolem_hurl_boulder = { cast = "target", range = 800 },
    greater_rock_golem_hurl_boulder = { cast = "target", range = 800 },
    warpine_raider_seed_shot = { cast = "target", range = 600 },
    ogre_bruiser_ogre_smash = { cast = "point", range = 275 },
    black_dragon_fireball = { cast = "point", range = 1200 },
    ancient_black_dragon_fireball = { cast = "point", range = 1200 },
    granite_golem_hurl_boulder = { cast = "target", range = 900 },
    ancient_rock_golem_hurl_boulder = { cast = "target", range = 900 },
    ancient_thunderhide_slam = { cast = "no_target", range = 325 },
}

local NO_TARGET_WHITELIST = {
    centaur_khan_war_stomp = true,
    hellbear_smasher_thunder_clap = true,
    polar_furbolg_ursa_warrior_thunder_clap = true,
    ancient_thunderhide_slam = true,
}

local ABILITY_BLACKLIST = {
    dark_troll_warlord_raise_dead = true,
    enraged_wildkin_tornado = true,
    ogre_magi_frost_armor = true,
    ancient_thunderhide_frenzy = true,
}

local last_cast_time = 0
local creep_states = {}
local ability_last_cast_times = {}

local band = bit32 and bit32.band or (bit and bit.band)

local function has_flag(value, flag)
    if not value or not flag then
        return false
    end

    if band then
        return band(value, flag) ~= 0
    end

    while value > 0 and flag > 0 do
        if value % 2 == 1 and flag % 2 == 1 then
            return true
        end

        value = math.floor(value / 2)
        flag = math.floor(flag / 2)
    end

    return false
end

local function reset_state()
    last_cast_time = 0
    creep_states = {}
    ability_last_cast_times = {}
end

local function get_creep_state(index)
    local state = creep_states[index]
    if not state then
        state = { last_follow = 0 }
        creep_states[index] = state
    end

    return state
end

local function cleanup_creep_states(active_indices)
    for index in pairs(creep_states) do
        if not active_indices[index] then
            creep_states[index] = nil
        end
    end
end

local function record_ability_cast(ability, game_time)
    local idx = Ability.GetIndex(ability)
    if idx then
        ability_last_cast_times[idx] = game_time
    end
end

local function can_cast_now(ability, game_time)
    local idx = Ability.GetIndex(ability)
    if not idx then
        return true
    end

    local last = ability_last_cast_times[idx]
    if last and (game_time - last) < ABILITY_ORDER_COOLDOWN then
        return false
    end

    return true
end

local function get_special_value(ability, key)
    local ok, value = pcall(Ability.GetLevelSpecialValueFor, ability, key, -1)
    if ok and type(value) == "number" then
        return value
    end

    return nil
end

local function get_effective_range(ability, fallback)
    local range = Ability.GetCastRange(ability)
    if range and range > 0 then
        return range
    end

    for _, key in ipairs(SPECIAL_VALUE_KEYS) do
        local value = get_special_value(ability, key)
        if value and value > 0 then
            return value
        end
    end

    return fallback
end

local function is_big_neutral(npc)
    if not npc or not Entity.IsNPC(npc) then
        return false
    end

    if not Entity.IsAlive(npc) or Entity.IsDormant(npc) then
        return false
    end

    if not NPC.IsNeutral(npc) or NPC.IsAncient(npc) then
        return false
    end

    local name = NPC.GetUnitName(npc)
    if name and BIG_NEUTRAL_NAMES[name] then
        return true
    end

    local max_health = Entity.GetMaxHealth(npc)
    if max_health and max_health >= BIG_NEUTRAL_MIN_HEALTH then
        return true
    end

    return false
end

local function get_dominator_item(hero)
    for _, item_name in ipairs(DOMINATOR_ITEMS) do
        local item = NPC.GetItem(hero, item_name, true)
        if item and Ability.IsReady(item) then
            return item
        end
    end

    return nil
end

local function find_best_target(origin, range)
    local best_target = nil
    local best_health = -1

    for _, npc in pairs(NPCs.GetAll()) do
        if is_big_neutral(npc) then
            local npc_pos = Entity.GetAbsOrigin(npc)
            local distance = npc_pos:Distance2D(origin)
            if distance <= range then
                local health = Entity.GetHealth(npc) or 0
                if health > best_health then
                    best_health = health
                    best_target = npc
                end
            end
        end
    end

    return best_target
end

local function collect_enemy_heroes(hero)
    local enemies = {}

    for _, enemy in pairs(Heroes.GetAll()) do
        if enemy ~= hero and Entity.IsAlive(enemy) and not Entity.IsDormant(enemy) and not Entity.IsSameTeam(hero, enemy) then
            table.insert(enemies, enemy)
        end
    end

    return enemies
end

local function is_controlled_creep(hero, npc, player_id)
    if npc == hero then
        return false
    end

    if not npc or not Entity.IsNPC(npc) or Entity.IsDormant(npc) or not Entity.IsAlive(npc) then
        return false
    end

    if NPC.IsHero(npc) or NPC.IsIllusion(npc) then
        return false
    end

    local is_creep = NPC.IsCreep(npc)
    local is_ancient = NPC.IsAncient(npc)
    if not is_creep and not is_ancient then
        return false
    end

    if NPC.IsLaneCreep(npc) then
        return false
    end

    if not Entity.IsSameTeam(hero, npc) then
        return false
    end

    if player_id and player_id >= 0 and not NPC.IsControllableByPlayer(npc, player_id) then
        return false
    end

    return true
end

local function collect_controlled_creeps(hero)
    local player = Players.GetLocal()
    local player_id = nil

    if player then
        player_id = Player.GetPlayerID(player)
        if player_id and player_id < 0 then
            player_id = nil
        end
    end

    local creeps = {}
    local active_indices = {}

    for _, npc in pairs(NPCs.GetAll()) do
        if is_controlled_creep(hero, npc, player_id) then
            table.insert(creeps, npc)
            active_indices[Entity.GetIndex(npc)] = true
        end
    end

    cleanup_creep_states(active_indices)

    return creeps
end

local function find_enemy_in_range(enemies, source_pos, range)
    local best_target = nil
    local best_distance = math.huge

    for _, enemy in ipairs(enemies) do
        if not NPC.IsIllusion(enemy) then
            local enemy_pos = Entity.GetAbsOrigin(enemy)
            local distance = enemy_pos:Distance2D(source_pos)
            if distance <= range and distance < best_distance then
                best_target = enemy
                best_distance = distance
            end
        end
    end

    return best_target, best_distance
end

local function cast_creep_ability(creep, ability, enemies, game_time)
    if not ability then
        return false
    end

    local ability_name = Ability.GetName(ability)
    if not ability_name or ABILITY_BLACKLIST[ability_name] then
        return false
    end

    if Ability.GetLevel(ability) <= 0 or Ability.IsHidden(ability) or not Ability.IsActivated(ability) then
        return false
    end

    if not Ability.IsReady(ability) or not Ability.IsOwnersManaEnough(ability) or not can_cast_now(ability, game_time) then
        return false
    end

    local behavior = Ability.GetBehavior(ability)
    if has_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_PASSIVE) then
        return false
    end

    if has_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_CHANNELLED) then
        return false
    end

    local config = ABILITY_RULES[ability_name]
    local cast_type = config and config.cast

    if not cast_type then
        if has_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_UNIT_TARGET) then
            cast_type = "target"
        elseif has_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_POINT) then
            cast_type = "point"
        elseif has_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_NO_TARGET) then
            cast_type = "no_target"
        else
            return false
        end
    end

    local target_team = Ability.GetTargetTeam(ability)
    if (cast_type == "target" or cast_type == "point")
        and target_team ~= Enum.TargetTeam.DOTA_UNIT_TARGET_TEAM_ENEMY
        and target_team ~= Enum.TargetTeam.DOTA_UNIT_TARGET_TEAM_BOTH then
        return false
    end

    if cast_type == "target" and (not config or not config.allow_zero_damage) then
        local damage = Ability.GetDamage(ability)
        if not damage or damage <= 0 then
            return false
        end
    end

    if cast_type == "no_target" and not (config or NO_TARGET_WHITELIST[ability_name]) then
        local damage = Ability.GetDamage(ability)
        if not damage or damage <= 0 then
            return false
        end
    end

    local fallback = cast_type == "no_target" and NO_TARGET_FALLBACK_RANGE or 700
    local range = config and config.range or get_effective_range(ability, fallback)
    if not range or range <= 0 then
        range = fallback
    end

    local creep_pos = Entity.GetAbsOrigin(creep)

    if cast_type == "target" then
        if range < 0 then
            range = 0
        end
        local target = find_enemy_in_range(enemies, creep_pos, range)
        if target then
            Ability.CastTarget(ability, target)
            record_ability_cast(ability, game_time)
            return true
        end
    elseif cast_type == "point" then
        local target = find_enemy_in_range(enemies, creep_pos, range)
        if target then
            local pos = Entity.GetAbsOrigin(target)
            Ability.CastPosition(ability, pos)
            record_ability_cast(ability, game_time)
            return true
        end
    elseif cast_type == "no_target" then
        local radius = range > 0 and range or NO_TARGET_FALLBACK_RANGE
        for _, enemy in ipairs(enemies) do
            local enemy_pos = Entity.GetAbsOrigin(enemy)
            if enemy_pos:Distance2D(creep_pos) <= radius then
                Ability.CastNoTarget(ability)
                record_ability_cast(ability, game_time)
                return true
            end
        end
    end

    return false
end

local function handle_auto_dominator(hero, game_time)
    if NPC.IsStunned(hero) or NPC.IsChannellingAbility(hero) then
        return
    end

    local dominator = get_dominator_item(hero)
    if not dominator then
        return
    end

    local mana = NPC.GetMana(hero)
    if not Ability.IsCastable(dominator, mana) then
        return
    end

    if last_cast_time > 0 and (game_time - last_cast_time) < ORDER_COOLDOWN then
        return
    end

    local hero_origin = Entity.GetAbsOrigin(hero)
    local cast_range = Ability.GetCastRange(dominator) or 0
    if cast_range < 0 then
        cast_range = 0
    end
    cast_range = cast_range + CAST_RANGE_BUFFER

    local target = find_best_target(hero_origin, cast_range)
    if not target then
        return
    end

    Ability.CastTarget(dominator, target)
    last_cast_time = game_time
end

local function handle_controlled_creeps(hero, game_time)
    local creeps = collect_controlled_creeps(hero)
    if #creeps == 0 then
        return
    end

    local enemies = collect_enemy_heroes(hero)
    local hero_pos = Entity.GetAbsOrigin(hero)

    for _, creep in ipairs(creeps) do
        local index = Entity.GetIndex(creep)
        local state = get_creep_state(index)

        if state then
            local creep_pos = Entity.GetAbsOrigin(creep)
            if creep_pos:Distance2D(hero_pos) > FOLLOW_DISTANCE_LEASH then
                if game_time - (state.last_follow or 0) >= FOLLOW_ORDER_INTERVAL then
                    NPC.MoveTo(creep, hero_pos)
                    state.last_follow = game_time
                end
            end
        end

        local can_use_abilities = #enemies > 0
            and not NPC.IsStunned(creep)
            and not NPC.IsSilenced(creep)
            and not NPC.IsChannellingAbility(creep)

        if can_use_abilities then
            for slot = 0, 5 do
                local ability = NPC.GetAbilityByIndex(creep, slot)
                if cast_creep_ability(creep, ability, enemies, game_time) then
                    break
                end
            end
        end
    end
end

function auto_dominator.OnUpdate()
    if not Engine.IsInGame() then
        reset_state()
        return
    end

    local hero = Heroes.GetLocal()
    if not hero or not Entity.IsAlive(hero) or Entity.IsDormant(hero) or NPC.IsIllusion(hero) then
        reset_state()
        return
    end

    local game_time = GameRules.GetGameTime()

    handle_auto_dominator(hero, game_time)
    handle_controlled_creeps(hero, game_time)
end

return auto_dominator
