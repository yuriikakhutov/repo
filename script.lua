---@diagnostic disable: undefined-global

local script = {}

local TROLL_UNIT_NAME <const> = "npc_dota_neutral_dark_troll_warlord"
local RAISE_DEAD_SLOT <const> = 0
local ENGAGE_RADIUS <const> = 600
local LEASH_RADIUS <const> = 600
local FOLLOW_REISSUE_DELAY <const> = 0.4
local ATTACK_REISSUE_DELAY <const> = 0.25

local last_move_time = {}
local last_attack_time = {}

local function get_entity_index(entity)
    if Entity and Entity.GetIndex then
        return Entity.GetIndex(entity)
    end

    return nil
end

local function now()
    if GameRules and GameRules.GetGameTime then
        return GameRules.GetGameTime()
    end

    return 0
end

local function is_unit_valid(entity)
    return entity
        and Entity
        and Entity.IsAlive
        and Entity.IsAlive(entity)
        and (not Entity.IsDormant or not Entity.IsDormant(entity))
end

local function resolve_local_player()
    if not Players or not Players.GetLocal or not Player or not Player.GetPlayerID then
        return nil, nil
    end

    local player = Players.GetLocal()
    if not player then
        return nil, nil
    end

    local player_id = Player.GetPlayerID(player)
    if not player_id or player_id < 0 then
        return nil, nil
    end

    return player, player_id
end

local function get_local_hero()
    if not Heroes or not Heroes.GetLocal then
        return nil
    end

    local hero = Heroes.GetLocal()
    if is_unit_valid(hero) then
        return hero
    end

    return nil
end

local function can_cast_raise_dead(troll)
    if not NPC or not Ability or not Ability.CastNoTarget or not NPC.GetAbilityByIndex then
        return nil
    end

    local ability = NPC.GetAbilityByIndex(troll, RAISE_DEAD_SLOT)
    if not ability then
        return nil
    end

    if Ability.IsHidden and Ability.IsHidden(ability) then
        return nil
    end

    if Ability.GetLevel and Ability.GetLevel(ability) <= 0 then
        return nil
    end

    if Ability.IsActivated and not Ability.IsActivated(ability) then
        return nil
    end

    if Ability.IsReady and not Ability.IsReady(ability) then
        return nil
    end

    local mana = NPC.GetMana and NPC.GetMana(troll) or 0
    if Ability.IsCastable and not Ability.IsCastable(ability, mana) then
        return nil
    end

    return ability
end

local function distance_squared(a, b)
    local delta = a - b
    if delta and delta.Length2DSqr then
        return delta:Length2DSqr()
    end

    if delta and delta.Length2D then
        local value = delta:Length2D()
        return value and value * value or nil
    end

    return nil
end

local function find_enemy_near_position(hero, position, radius)
    if not hero or not position or not NPCs or not NPCs.GetAll or not Entity or not Entity.IsSameTeam then
        return nil
    end

    local radius_sqr = radius * radius
    local closest
    local closest_dist

    for _, candidate in pairs(NPCs.GetAll()) do
        if candidate ~= hero and is_unit_valid(candidate) and not Entity.IsSameTeam(hero, candidate) then
            local candidate_pos = Entity.GetAbsOrigin and Entity.GetAbsOrigin(candidate)
            if candidate_pos then
                local dist = distance_squared(candidate_pos, position)
                if dist and dist <= radius_sqr and (not closest_dist or dist < closest_dist) then
                    closest = candidate
                    closest_dist = dist
                end
            end
        end
    end

    return closest
end

local function cast_raise_dead_if_needed(troll, hero)
    if not Entity or not Entity.GetAbsOrigin then
        return
    end

    local troll_pos = Entity.GetAbsOrigin(troll)
    if not troll_pos then
        return
    end

    local enemy = find_enemy_near_position(hero, troll_pos, ENGAGE_RADIUS)
    if not enemy then
        return
    end

    local ability = can_cast_raise_dead(troll)
    if not ability then
        return
    end

    Ability.CastNoTarget(ability)
end

local function issue_group_attack(player, units, target)
    if not Player or not Player.AttackTarget then
        return
    end

    local target_index = get_entity_index(target)
    if not target_index then
        return
    end

    local current_time = now()

    if Player.PrepareUnitOrders and Enum and Enum.UnitOrder and Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET then
        local order_units = {}

        for _, unit in ipairs(units) do
            local unit_index = get_entity_index(unit)
            if unit_index then
                local last_time = last_attack_time[unit_index]
                if not last_time or current_time - last_time >= ATTACK_REISSUE_DELAY then
                    table.insert(order_units, unit)
                end
            end
        end

        if #order_units > 0 then
            Player.PrepareUnitOrders(player, {
                OrderType = Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET,
                Units = order_units,
                TargetIndex = target_index,
                Queue = false,
                ShowEffects = false,
            })

            for _, unit in ipairs(order_units) do
                local unit_index = get_entity_index(unit)
                if unit_index then
                    last_attack_time[unit_index] = current_time
                end
            end

            return
        end
    end

    for _, unit in ipairs(units) do
        local unit_index = get_entity_index(unit)
        if unit_index then
            local last_time = last_attack_time[unit_index]
            if not last_time or current_time - last_time >= ATTACK_REISSUE_DELAY then
                Player.AttackTarget(player, unit, target, false, false, true)
                last_attack_time[unit_index] = current_time
            end
        end
    end
end

local function issue_follow_orders(units, destination)
    if not NPC or not NPC.MoveTo then
        return
    end

    local current_time = now()

    for _, unit in ipairs(units) do
        local unit_index = get_entity_index(unit)
        if unit_index then
            local last_time = last_move_time[unit_index]
            if not last_time or current_time - last_time >= FOLLOW_REISSUE_DELAY then
                NPC.MoveTo(unit, destination, false, false, false, true)
                last_move_time[unit_index] = current_time
            end
        end
    end
end

local function collect_dark_trolls(player_id)
    if not NPCs or not NPCs.GetAll or not NPC or not NPC.GetUnitName or not NPC.IsControllableByPlayer then
        return {}
    end

    local trolls = {}

    for _, npc in pairs(NPCs.GetAll()) do
        if is_unit_valid(npc)
            and NPC.IsControllableByPlayer(npc, player_id)
            and NPC.GetUnitName(npc) == TROLL_UNIT_NAME
        then
            table.insert(trolls, npc)
        end
    end

    return trolls
end

function script.OnUpdate()
    local player, player_id = resolve_local_player()
    if not player then
        return
    end

    local hero = get_local_hero()
    if not hero then
        return
    end

    if not Entity or not Entity.GetAbsOrigin then
        return
    end

    local hero_pos = Entity.GetAbsOrigin(hero)
    if not hero_pos then
        return
    end

    local trolls = collect_dark_trolls(player_id)
    if #trolls == 0 then
        return
    end

    local target = find_enemy_near_position(hero, hero_pos, ENGAGE_RADIUS)

    for _, troll in ipairs(trolls) do
        cast_raise_dead_if_needed(troll, hero)
    end

    if target then
        issue_group_attack(player, trolls, target)
    else
        local follow_units = {}
        for _, troll in ipairs(trolls) do
            local troll_pos = Entity.GetAbsOrigin(troll)
            if troll_pos then
                local dist = distance_squared(troll_pos, hero_pos)
                if not dist or dist > LEASH_RADIUS * LEASH_RADIUS then
                    table.insert(follow_units, troll)
                end
            end
        end

        if #follow_units > 0 then
            issue_follow_orders(follow_units, hero_pos)
        end
    end
end

return script
