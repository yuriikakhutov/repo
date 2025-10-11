---@diagnostic disable: undefined-global, param-type-mismatch, cast-local-type

local script = {}

local bit = bit or bit32

local ABILITY_BEHAVIOR = {
    PASSIVE = 2,
    NO_TARGET = 4,
    UNIT_TARGET = 8,
    POINT = 16,
    AOE = 32,
    CHANNELLED = 128,
    TOGGLE = 512,
    DIRECTIONAL = 1024,
    IMMEDIATE = 2048,
    AUTOCAST = 4096,
    OPTIONAL_UNIT_TARGET = 8192,
    OPTIONAL_POINT = 16384,
    OPTIONAL_NO_TARGET = 32768,
    AURA = 65536,
    ATTACK = 131072,
    VECTOR_TARGETING = 1073741824,
}

local TARGET_TEAM = {
    NONE = 0,
    FRIENDLY = 1,
    ENEMY = 2,
    BOTH = 3,
}

local TARGET_FLAG = {
    MAGIC_IMMUNE_ENEMIES = 16,
}

local MODIFIER_STATE = {
    INVULNERABLE = 8,
    MAGIC_IMMUNE = 9,
    HEXED = 6,
    OUT_OF_WORLD = 23,
}

local TEAM_TYPE = {
    ENEMY = Enum.TeamType.TEAM_ENEMY,
    FRIEND = Enum.TeamType.TEAM_FRIEND,
    BOTH = Enum.TeamType.TEAM_BOTH,
}

local RUBICK_NAME = "npc_dota_hero_rubick"
local TELEKINESIS_NAME = "rubick_telekinesis"
local TELEKINESIS_LAND_NAME = "rubick_telekinesis_land"
local TELEKINESIS_MODIFIER = "modifier_rubick_telekinesis"

local menu_root = Menu.Create("Heroes", "Rubick", "Rubick", "Rubick Spellcraft")
local menu_general = menu_root:Create("General")
local menu_tele = menu_root:Create("Telekinesis")

local option_auto_cast = menu_general:Switch("Auto-cast stolen abilities", true)
local option_cast_only_visible = menu_general:Switch("Skip invisible or out-of-world targets", true)
local option_enemy_radius = menu_general:SliderInt("Enemy search radius for no-target spells", 500, 250, 1200)
local option_point_lead_time = menu_general:SliderFloat("Point cast lead time (sec)", 0.15, 0.0, 0.6)

local option_tele_enabled = menu_tele:Switch("Smart Telekinesis landing", true)
local option_tele_mode = menu_tele:Combo("Preferred landing", {
    "Nearest allied tower",
    "Nearest allied hero",
    "Towards Rubick",
}, 0)
local option_tele_offset = menu_tele:SliderInt("Minimum gap from target", 80, 0, 300)
local option_tele_max_distance = menu_tele:SliderInt("Max throw distance override", 0, 0, 600)

local last_cast_times = {}
local function clear_state()
    last_cast_times = {}
end

local function get_time()
    return GameRules.GetGameTime()
end

local function get_local_player()
    if not Engine.IsInGame() then
        return nil
    end

    return Players.GetLocal()
end

local function get_local_hero()
    local player = get_local_player()
    if not player then
        return nil
    end

    local hero = Player.GetAssignedHero(player)
    if not hero or not Entity.IsAlive(hero) then
        return nil
    end

    if Entity.GetUnitName(hero) ~= RUBICK_NAME then
        return nil
    end

    return hero
end

local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

local function vector_sub(a, b)
    return { x = a.x - b.x, y = a.y - b.y, z = (a.z or 0) - (b.z or 0) }
end

local function vector_add(a, b)
    return { x = a.x + b.x, y = a.y + b.y, z = (a.z or 0) + (b.z or 0) }
end

local function vector_scale(v, s)
    return { x = v.x * s, y = v.y * s, z = (v.z or 0) * s }
end

local function vector_length(v)
    return math.sqrt(v.x * v.x + v.y * v.y + (v.z or 0) * (v.z or 0))
end

local function vector_normalize(v)
    local len = vector_length(v)
    if len <= 0.001 then
        return { x = 0, y = 0, z = 0 }
    end
    return { x = v.x / len, y = v.y / len, z = (v.z or 0) / len }
end

local function vector_distance(a, b)
    return vector_length(vector_sub(a, b))
end

local function can_cast_now(hero)
    if NPC.IsSilenced(hero) or NPC.IsStunned(hero) then
        return false
    end

    if NPC.IsChannellingAbility(hero) then
        return false
    end

    if NPC.HasState(hero, MODIFIER_STATE.HEXED) then
        return false
    end

    return true
end

local function ability_recently_cast(ability, now, delay)
    local index = Ability.GetIndex(ability)
    if not index then
        return false
    end

    delay = delay or 0.1
    local last = last_cast_times[index]
    if not last then
        return false
    end

    return now - last < delay
end

local function mark_ability_cast(ability, now)
    local index = Ability.GetIndex(ability)
    if index then
        last_cast_times[index] = now
    end
end

local function has_behavior(behavior, flag)
    if not bit then
        return false
    end
    return bit.band(behavior, flag) ~= 0
end

local function is_enemy(hero, unit)
    return not Entity.IsSameTeam(hero, unit)
end

local function is_ally(hero, unit)
    return Entity.IsSameTeam(hero, unit)
end

local function is_visible_target(unit)
    if option_cast_only_visible:Get() then
        if Entity.IsDormant(unit) then
            return false
        end

        if NPC.HasState(unit, MODIFIER_STATE.OUT_OF_WORLD) then
            return false
        end
    end

    return Entity.IsAlive(unit)
end

local function is_magic_immune(unit)
    return NPC.HasState(unit, MODIFIER_STATE.MAGIC_IMMUNE) or NPC.HasState(unit, MODIFIER_STATE.INVULNERABLE)
end

local function get_units_in_range(reference, radius, team_type, omit_illusions)
    team_type = team_type or TEAM_TYPE.ENEMY
    local omit = omit_illusions ~= false
    local units = Entity.GetHeroesInRadius(reference, radius, team_type, omit, true) or {}
    return units
end

local function pick_enemy_target(hero, ability, range)
    range = math.max(range, 150)
    local enemies = get_units_in_range(hero, range + 25, TEAM_TYPE.ENEMY)
    if #enemies == 0 then
        return nil
    end

    local flags = Ability.GetTargetFlags(ability)
    local allow_magic_immune = bit and bit.band(flags or 0, TARGET_FLAG.MAGIC_IMMUNE_ENEMIES) ~= 0

    local origin = Entity.GetAbsOrigin(hero)
    local best_target = nil
    local best_score = math.huge

    for _, enemy in ipairs(enemies) do
        if enemy and is_enemy(hero, enemy) and is_visible_target(enemy) and not NPC.IsIllusion(enemy) then
            if allow_magic_immune or not is_magic_immune(enemy) then
                local distance = vector_distance(origin, Entity.GetAbsOrigin(enemy))
                if distance <= range + 25 then
                    local health_ratio = NPC.GetHealth(enemy) / math.max(NPC.GetMaxHealth(enemy), 1)
                    local score = distance + health_ratio * 100
                    if score < best_score then
                        best_target = enemy
                        best_score = score
                    end
                end
            end
        end
    end

    return best_target
end

local function pick_friendly_target(hero, ability, range)
    range = math.max(range, 150)
    local allies = get_units_in_range(hero, range + 25, TEAM_TYPE.FRIEND)
    if #allies == 0 then
        return nil
    end

    local origin = Entity.GetAbsOrigin(hero)
    local best_target = nil
    local best_score = math.huge

    for _, ally in ipairs(allies) do
        if ally and ally ~= hero and is_ally(hero, ally) and is_visible_target(ally) and not NPC.IsIllusion(ally) then
            local distance = vector_distance(origin, Entity.GetAbsOrigin(ally))
            if distance <= range + 25 then
                local health_ratio = NPC.GetHealth(ally) / math.max(NPC.GetMaxHealth(ally), 1)
                local score = health_ratio * 100 + distance * 0.5
                if score < best_score then
                    best_target = ally
                    best_score = score
                end
            end
        end
    end

    return best_target
end

local function should_cast_no_target(hero, ability, range)
    local team = Ability.GetTargetTeam(ability)
    if team == TARGET_TEAM.FRIENDLY then
        return false
    end

    range = range > 0 and range or option_enemy_radius:Get()
    local enemies = get_units_in_range(hero, range, TEAM_TYPE.ENEMY)
    return #enemies > 0
end

local function predict_position(unit, delay)
    return Entity.GetAbsOrigin(unit)
end

local function try_cast_unit_target(hero, ability, range)
    local target_team = Ability.GetTargetTeam(ability)
    if target_team == TARGET_TEAM.NONE then
        return false
    end

    local target
    if target_team == TARGET_TEAM.ENEMY then
        target = pick_enemy_target(hero, ability, range)
    elseif target_team == TARGET_TEAM.FRIENDLY then
        target = pick_friendly_target(hero, ability, range)
    elseif target_team == TARGET_TEAM.BOTH then
        target = pick_enemy_target(hero, ability, range) or pick_friendly_target(hero, ability, range)
    else
        target = pick_enemy_target(hero, ability, range)
    end

    if not target then
        return false
    end

    Ability.CastTarget(ability, target)
    return true
end

local function try_cast_point(hero, ability, range)
    local target_team = Ability.GetTargetTeam(ability)
    local delay = option_point_lead_time:Get()
    local target

    if target_team == TARGET_TEAM.FRIENDLY then
        target = pick_friendly_target(hero, ability, range)
    else
        target = pick_enemy_target(hero, ability, range)
    end

    if not target then
        return false
    end

    local pos = predict_position(target, delay)
    Ability.CastPosition(ability, pos)
    return true
end

local function try_cast_no_target(hero, ability, range)
    if not should_cast_no_target(hero, ability, range) then
        return false
    end

    Ability.CastNoTarget(ability)
    return true
end

local function should_skip_ability(ability)
    local behavior = Ability.GetBehavior(ability) or 0

    if has_behavior(behavior, ABILITY_BEHAVIOR.PASSIVE) then
        return true
    end

    if has_behavior(behavior, ABILITY_BEHAVIOR.AURA) then
        return true
    end

    if has_behavior(behavior, ABILITY_BEHAVIOR.TOGGLE) then
        return true
    end

    if has_behavior(behavior, ABILITY_BEHAVIOR.ATTACK) then
        return true
    end

    if has_behavior(behavior, ABILITY_BEHAVIOR.VECTOR_TARGETING) then
        return true
    end

    if Ability.IsHidden(ability) then
        return true
    end

    if not Ability.IsActivated(ability) then
        return true
    end

    if Ability.IsChannelling(ability) then
        return true
    end

    return false
end

local function try_use_stolen_ability(hero, ability, now)
    if should_skip_ability(ability) then
        return false
    end

    if ability_recently_cast(ability, now, 0.25) then
        return false
    end

    local mana = NPC.GetMana(hero)
    if not Ability.IsCastable(ability, mana) then
        return false
    end

    local behavior = Ability.GetBehavior(ability) or 0
    local range = Ability.GetCastRange(ability) or 0
    if range <= 0 then
        range = 600
    end

    if has_behavior(behavior, ABILITY_BEHAVIOR.UNIT_TARGET) or has_behavior(behavior, ABILITY_BEHAVIOR.OPTIONAL_UNIT_TARGET) then
        if try_cast_unit_target(hero, ability, range) then
            mark_ability_cast(ability, now)
            return true
        end
    end

    if has_behavior(behavior, ABILITY_BEHAVIOR.POINT) or has_behavior(behavior, ABILITY_BEHAVIOR.OPTIONAL_POINT) then
        if try_cast_point(hero, ability, range) then
            mark_ability_cast(ability, now)
            return true
        end
    end

    if has_behavior(behavior, ABILITY_BEHAVIOR.NO_TARGET) or has_behavior(behavior, ABILITY_BEHAVIOR.OPTIONAL_NO_TARGET) or has_behavior(behavior, ABILITY_BEHAVIOR.IMMEDIATE) then
        if try_cast_no_target(hero, ability, range) then
            mark_ability_cast(ability, now)
            return true
        end
    end

    return false
end

local function auto_cast_stolen_abilities(hero, now)
    if not option_auto_cast:Get() then
        return
    end

    if not can_cast_now(hero) then
        return
    end

    for slot = 0, 23 do
        local ability = NPC.GetAbilityByIndex(hero, slot)
        if ability and Ability.IsStolen(ability) then
            if try_use_stolen_ability(hero, ability, now) then
                break
            end
        end
    end
end

local function find_telekinesis_target(hero)
    local search_radius = 1200
    local enemies = get_units_in_range(hero, search_radius, TEAM_TYPE.ENEMY)
    for _, enemy in ipairs(enemies) do
        if enemy and NPC.HasModifier(enemy, TELEKINESIS_MODIFIER) and is_enemy(hero, enemy) then
            return enemy
        end
    end
    return nil
end

local function find_nearest_allied_tower(hero, position)
    local best = nil
    local best_distance = math.huge
    for i = 0, Towers.Count() - 1 do
        local tower = Towers.Get(i)
        if tower and Entity.IsAlive(tower) and is_ally(hero, tower) then
            local dist = vector_distance(position, Entity.GetAbsOrigin(tower))
            if dist < best_distance then
                best = tower
                best_distance = dist
            end
        end
    end
    return best
end

local function find_nearest_ally_hero(hero, position)
    local best = nil
    local best_distance = math.huge
    for i = 0, Heroes.Count() - 1 do
        local ally = Heroes.Get(i)
        if ally and ally ~= hero and is_ally(hero, ally) and Entity.IsAlive(ally) and not NPC.IsIllusion(ally) then
            local dist = vector_distance(position, Entity.GetAbsOrigin(ally))
            if dist < best_distance then
                best = ally
                best_distance = dist
            end
        end
    end
    return best
end

local function get_telekinesis_max_distance(hero)
    local base = option_tele_max_distance:Get()
    if base > 0 then
        return base
    end

    local telekinesis = NPC.GetAbility(hero, TELEKINESIS_NAME)
    if telekinesis then
        local distance = Ability.GetLevelSpecialValueFor(telekinesis, "max_land_distance")
        if distance and distance > 0 then
            return distance
        end
    end
    return 375
end

local function get_drop_position(hero, victim)
    local victim_pos = Entity.GetAbsOrigin(victim)
    local preferred_mode = option_tele_mode:Get()
    local drop_target_pos = nil

    if preferred_mode == 0 then
        local tower = find_nearest_allied_tower(hero, victim_pos)
        if tower then
            drop_target_pos = Entity.GetAbsOrigin(tower)
        end
        if not drop_target_pos then
            local ally = find_nearest_ally_hero(hero, victim_pos)
            if ally then
                drop_target_pos = Entity.GetAbsOrigin(ally)
            end
        end
        if not drop_target_pos then
            drop_target_pos = Entity.GetAbsOrigin(hero)
        end
    elseif preferred_mode == 1 then
        local ally = find_nearest_ally_hero(hero, victim_pos)
        if ally then
            drop_target_pos = Entity.GetAbsOrigin(ally)
        else
            local tower = find_nearest_allied_tower(hero, victim_pos)
            if tower then
                drop_target_pos = Entity.GetAbsOrigin(tower)
            end
        end
        if not drop_target_pos then
            drop_target_pos = Entity.GetAbsOrigin(hero)
        end
    else
        drop_target_pos = Entity.GetAbsOrigin(hero)
    end

    if not drop_target_pos then
        return nil
    end

    local max_distance = get_telekinesis_max_distance(hero)
    local direction = vector_sub(drop_target_pos, victim_pos)
    local distance = vector_length(direction)

    if distance <= option_tele_offset:Get() then
        direction = vector_normalize(direction)
        if vector_length(direction) < 0.01 then
            direction = vector_normalize(vector_sub(Entity.GetAbsOrigin(hero), victim_pos))
        end
        distance = option_tele_offset:Get()
    end

    local clamped = clamp(distance, option_tele_offset:Get(), max_distance)
    local normalized = vector_normalize(direction)
    if vector_length(normalized) < 0.01 then
        normalized = { x = 1, y = 0, z = 0 }
    end

    local offset = vector_scale(normalized, clamped)
    local drop_position = vector_add(victim_pos, offset)
    drop_position.z = victim_pos.z
    return drop_position
end

local function handle_telekinesis(hero, now)
    if not option_tele_enabled:Get() then
        return
    end

    local land_ability = NPC.GetAbility(hero, TELEKINESIS_LAND_NAME)
    if not land_ability then
        return
    end

    if ability_recently_cast(land_ability, now, 0.2) then
        return
    end

    if not Ability.IsCastable(land_ability, NPC.GetMana(hero)) then
        return
    end

    local victim = find_telekinesis_target(hero)
    if not victim then
        return
    end

    local drop_position = get_drop_position(hero, victim)
    if not drop_position then
        return
    end

    Ability.CastPosition(land_ability, drop_position)
    mark_ability_cast(land_ability, now)
end

function script.OnGameEnd()
    clear_state()
end

function script.OnGameStart()
    clear_state()
end

function script.OnUpdate()
    if not Engine.IsInGame() then
        clear_state()
        return
    end

    local hero = get_local_hero()
    if not hero then
        return
    end

    local now = get_time()

    handle_telekinesis(hero, now)
    auto_cast_stolen_abilities(hero, now)
end

return script
