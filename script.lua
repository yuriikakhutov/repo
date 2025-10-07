---@diagnostic disable: undefined-global

local script = {}

local DARK_TROLL_WARLORD_NAME <const> = "npc_dota_neutral_dark_troll_warlord"
local RAISE_DEAD_SLOT <const> = 0
local FOLLOW_RADIUS <const> = 600
local FOLLOW_REPOSITION_DISTANCE <const> = 300
local MOVE_REISSUE_DELAY <const> = 0.3
local ATTACK_REISSUE_DELAY <const> = 0.2
local RAISE_DEAD_TRIGGER_RADIUS <const> = 600

local attack_memory = {}
local move_memory = {}

local function get_entity_index(entity)
    if Entity and Entity.GetIndex then
        return Entity.GetIndex(entity)
    end

    return nil
end

local function get_game_time()
    if GameRules and GameRules.GetGameTime then
        return GameRules.GetGameTime()
    end

    return 0
end

local function is_alive_and_visible(entity)
    return entity
        and Entity
        and Entity.IsAlive
        and Entity.IsAlive(entity)
        and (not Entity.IsDormant or not Entity.IsDormant(entity))
end

local function resolve_local_player()
    if not Players or not Players.GetLocal then
        return nil, nil
    end

    local player = Players.GetLocal()
    if not player or not Player or not Player.GetPlayerID then
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
    if is_alive_and_visible(hero) then
        return hero
    end

    return nil
end

local function can_cast_raise_dead(ability, mana)
    if not ability or Ability.IsHidden and Ability.IsHidden(ability) then
        return false
    end

    if Ability.GetLevel and Ability.GetLevel(ability) <= 0 then
        return false
    end

    if Ability.IsActivated and not Ability.IsActivated(ability) then
        return false
    end

    if Ability.IsReady and not Ability.IsReady(ability) then
        return false
    end

    if Ability.IsCastable and not Ability.IsCastable(ability, mana or 0) then
        return false
    end

    return true
end

local function cast_raise_dead_if_enemy_nearby(npc, hero)
    if not NPC or not NPC.GetAbilityByIndex or not Ability or not Ability.CastNoTarget then
        return
    end

    if not hero or not Entity or not Entity.GetAbsOrigin then
        return
    end

    local npc_pos = Entity.GetAbsOrigin(npc)
    if not npc_pos then
        return
    end

    local nearby_enemy = find_enemy_near_position(hero, npc_pos, RAISE_DEAD_TRIGGER_RADIUS)
    if not nearby_enemy then
        return
    end

    local ability = NPC.GetAbilityByIndex(npc, RAISE_DEAD_SLOT)
    if not ability then
        return
    end

    local mana = NPC.GetMana and NPC.GetMana(npc) or 0
    if not can_cast_raise_dead(ability, mana) then
        return
    end

    Ability.CastNoTarget(ability)
end

local function find_enemy_near_position(hero, center_pos, radius)
    if not NPCs or not NPCs.GetAll or not Entity or not Entity.IsSameTeam then
        return nil
    end

    local radius_sqr = radius * radius
    local best_target
    local best_distance

    for _, candidate in pairs(NPCs.GetAll()) do
        if is_alive_and_visible(candidate)
            and candidate ~= hero
            and not Entity.IsSameTeam(hero, candidate)
        then
            if not NPC or not NPC.IsKillable or NPC.IsKillable(candidate) then
                local candidate_pos = Entity.GetAbsOrigin(candidate)
                if candidate_pos then
                    local distance = (candidate_pos - center_pos):Length2DSqr()
                    if distance <= radius_sqr then
                        if not best_distance or distance < best_distance then
                            best_target = candidate
                            best_distance = distance
                        end
                    end
                end
            end
        end
    end

    return best_target
end

local function resolve_attack_order_type()
    if Enum and Enum.UnitOrder and Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET then
        return Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET
    end

    return nil
end

local function resolve_move_order_type()
    if Enum and Enum.UnitOrder and Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION then
        return Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION
    end

    return nil
end

local function issue_attack(player, npc, target)
    if not Player or not Player.AttackTarget then
        return false
    end

    local npc_index = get_entity_index(npc)
    if not npc_index then
        return false
    end

    local target_index = get_entity_index(target)
    if not target_index then
        return false
    end

    local now = get_game_time()
    local memory = attack_memory[npc_index]

    if memory and memory.target == target_index and now - memory.time < ATTACK_REISSUE_DELAY then
        return false
    end

    Player.AttackTarget(player, npc, target, false, false, true)
    attack_memory[npc_index] = { target = target_index, time = now }
    move_memory[npc_index] = nil

    return true
end

local function issue_follow(npc, destination)
    if not NPC or not NPC.MoveTo then
        return false
    end

    local npc_index = get_entity_index(npc)
    if not npc_index then
        return false
    end

    local now = get_game_time()
    local last_order_time = move_memory[npc_index]
    if last_order_time and now - last_order_time < MOVE_REISSUE_DELAY then
        return false
    end

    NPC.MoveTo(npc, destination, false, false, false, true)
    move_memory[npc_index] = now
    attack_memory[npc_index] = nil

    return true
end

local function issue_attack_group(player, units, target)
    if not units or #units == 0 then
        return
    end

    if Player and Player.PrepareUnitOrders then
        local attack_order = resolve_attack_order_type()
        local target_index = get_entity_index(target)

        if attack_order and target_index then
            local valid_units = {}
            local now = get_game_time()

            for _, unit in ipairs(units) do
                local unit_index = get_entity_index(unit)
                if unit_index then
                    table.insert(valid_units, unit)
                end
            end

            if #valid_units > 0 then
                Player.PrepareUnitOrders(player, {
                    OrderType = attack_order,
                    Units = valid_units,
                    TargetIndex = target_index,
                    Queue = false,
                    ShowEffects = false,
                })

                for _, unit in ipairs(valid_units) do
                    local unit_index = get_entity_index(unit)
                    if unit_index then
                        attack_memory[unit_index] = { target = target_index, time = now }
                        move_memory[unit_index] = nil
                    end
                end

                return
            end
        end
    end

    for _, unit in ipairs(units) do
        issue_attack(player, unit, target)
    end
end

local function issue_follow_group(player, units, destination)
    if not units or #units == 0 then
        return
    end

    if Player and Player.PrepareUnitOrders then
        local move_order = resolve_move_order_type()
        if move_order then
            local valid_units = {}
            local now = get_game_time()

            for _, unit in ipairs(units) do
                local unit_index = get_entity_index(unit)
                if unit_index then
                    table.insert(valid_units, unit)
                end
            end

            if #valid_units > 0 then
                Player.PrepareUnitOrders(player, {
                    OrderType = move_order,
                    Units = valid_units,
                    Position = destination,
                    Queue = false,
                    ShowEffects = false,
                })

                for _, unit in ipairs(valid_units) do
                    local unit_index = get_entity_index(unit)
                    if unit_index then
                        move_memory[unit_index] = now
                        attack_memory[unit_index] = nil
                    end
                end

                return
            end
        end
    end

    for _, unit in ipairs(units) do
        issue_follow(unit, destination)
    end
end

local function should_handle_dark_troll(npc, player_id)
    if not npc or not NPC or not NPC.IsControllableByPlayer or not Entity or not Entity.IsAlive then
        return false
    end

    if not Entity.IsAlive(npc) then
        return false
    end

    if Entity.IsDormant and Entity.IsDormant(npc) then
        return false
    end

    if not NPC.IsControllableByPlayer(npc, player_id) then
        return false
    end

    if not NPC.GetUnitName then
        return false
    end

    if NPC.GetUnitName(npc) ~= DARK_TROLL_WARLORD_NAME then
        return false
    end

    return true
end

local function is_dark_troll_warlord(npc)
    if not NPC or not NPC.GetUnitName then
        return false
    end

    return NPC.GetUnitName(npc) == DARK_TROLL_WARLORD_NAME
end

local function record_processed_index(processed_indices, npc)
    local npc_index = get_entity_index(npc)
    if npc_index then
        processed_indices[npc_index] = true
    end
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

    if not NPCs or not NPCs.GetAll or not Entity or not Entity.GetAbsOrigin then
        return
    end

    local hero_pos = Entity.GetAbsOrigin(hero)
    if not hero_pos then
        return
    end

    local processed_indices = {}
    local enemy_target = find_enemy_near_position(hero, hero_pos, FOLLOW_RADIUS)
    local enemy_target_index = enemy_target and get_entity_index(enemy_target) or nil
    local attack_units = {}
    local follow_units = {}
    local now = get_game_time()

    for _, npc in pairs(NPCs.GetAll()) do
        if should_handle_dark_troll(npc, player_id) then
            record_processed_index(processed_indices, npc)

            if is_dark_troll_warlord(npc) then
                cast_raise_dead_if_enemy_nearby(npc, hero)
            end

            local npc_index = get_entity_index(npc)

            if enemy_target and enemy_target_index then
                if not is_alive_and_visible(enemy_target) then
                    enemy_target = nil
                    enemy_target_index = nil
                elseif NPC and NPC.IsKillable and not NPC.IsKillable(enemy_target) then
                    enemy_target = nil
                    enemy_target_index = nil
                end
            end

            if not enemy_target then
                enemy_target = find_enemy_near_position(hero, hero_pos, FOLLOW_RADIUS)
                enemy_target_index = enemy_target and get_entity_index(enemy_target) or nil
            end

            if enemy_target and enemy_target_index and npc_index then
                local memory = attack_memory[npc_index]
                if not (memory and memory.target == enemy_target_index and now - memory.time < ATTACK_REISSUE_DELAY) then
                    table.insert(attack_units, npc)
                end
            else
                local npc_pos = Entity.GetAbsOrigin(npc)
                if npc_pos and npc_index then
                    local distance_to_hero = (hero_pos - npc_pos):Length2D()
                    if distance_to_hero > FOLLOW_REPOSITION_DISTANCE then
                        local last_order_time = move_memory[npc_index]
                        if not last_order_time or now - last_order_time >= MOVE_REISSUE_DELAY then
                            table.insert(follow_units, npc)
                        end
                    else
                        attack_memory[npc_index] = nil
                    end
                end
            end
        end
    end

    if enemy_target and enemy_target_index and #attack_units > 0 then
        issue_attack_group(player, attack_units, enemy_target)
    end

    if (not enemy_target) and #follow_units > 0 then
        issue_follow_group(player, follow_units, hero_pos)
    end

    for index in pairs(attack_memory) do
        if not processed_indices[index] then
            attack_memory[index] = nil
        end
    end

    for index in pairs(move_memory) do
        if not processed_indices[index] then
            move_memory[index] = nil
        end
    end
end

return script
