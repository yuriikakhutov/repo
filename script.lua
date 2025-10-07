---@diagnostic disable: undefined-global

local script = {}

local SCRIPT_ID <const> = "auto_unit_controller"
local ZERO_VECTOR <const> = Vector()
local bit_module = bit32 or bit
local BIT_BAND <const> = bit_module and bit_module.band or function() return 0 end

local hero_state = {
    last_target = nil,
    last_target_time = -math.huge,
}

local root_tab = Menu.Create("General", "Unit Control", "Auto Units", "Auto Control")
local main_group = root_tab:Create("Настройки")
local unit_group = root_tab:Create("Юниты")

local ui = {}
ui.enabled = main_group:Switch("Включить автоконтроль", false)
ui.mirror_orders = main_group:Switch("Повторять приказы героя", true)
ui.fallback_mode = main_group:Combo("Поведение вне приказов", {
    "Следовать за героем",
    "Атаковать поблизости",
    "Остановить юнитов",
}, 0)
ui.follow_radius = main_group:Slider("Радиус слежения", 200, 2000, 700, "%d")
ui.reapply_threshold = main_group:Slider("Допустимое отклонение", 50, 800, 200, "%d")
ui.update_interval = main_group:Slider("Интервал обновления (сек)", 0.05, 0.5, 0.2, "%.2f")
ui.attack_offset = main_group:Slider("Смещение точки атаки", 150, 1200, 400, "%d")

ui.units = {
    hero_clones = unit_group:Switch("Герои-клоны (Meepo, Tempest Double)", true),
    illusions = unit_group:Switch("Иллюзии", true),
    summons = unit_group:Switch("Призывы и доминированные существа", true),
    lane_creeps = unit_group:Switch("Лайн-крипы", false),
    siege = unit_group:Switch("Осадные крипы", false),
    couriers = unit_group:Switch("Курьеры", false),
}

ui.attack_offset:Visible(ui.fallback_mode:Get() == 1)
ui.fallback_mode:SetCallback(function(widget)
    ui.attack_offset:Visible(widget:Get() == 1)
end, true)

local MIRRORABLE_ORDERS <const> = {
    [Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION] = true,
    [Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_TARGET] = true,
    [Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_DIRECTION] = true,
    [Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_RELATIVE] = true,
    [Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_MOVE] = true,
    [Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET] = true,
    [Enum.UnitOrder.DOTA_UNIT_ORDER_PATROL] = true,
    [Enum.UnitOrder.DOTA_UNIT_ORDER_STOP] = true,
    [Enum.UnitOrder.DOTA_UNIT_ORDER_HOLD_POSITION] = true,
}

local cached_units = {}
local unit_state = {}
local last_cache_time = 0
local last_maintain_time = 0
local cache_interval = 0.25
local is_internal_order = false

local function build_selected_lookup(player)
    local lookup = {}
    if not player or not Player or not Player.GetSelectedUnits then
        return lookup
    end

    local ok, selected = pcall(Player.GetSelectedUnits, player)
    if not ok or type(selected) ~= "table" then
        return lookup
    end

    for i = 1, #selected do
        local npc = selected[i]
        local index = npc and Entity.GetIndex(npc)
        if index then
            lookup[index] = true
        end
    end

    return lookup
end

local function clear_state()
    cached_units = {}
    unit_state = {}
    last_cache_time = 0
    last_maintain_time = 0
    hero_state.last_target = nil
    hero_state.last_target_time = -math.huge
end

ui.enabled:SetCallback(function(widget)
    if not widget:Get() then
        clear_state()
    end
end)

local function get_time()
    if GameRules and GameRules.GetGameTime then
        local ok, value = pcall(GameRules.GetGameTime)
        if ok and type(value) == "number" then
            return value
        end
    end
    return os.clock()
end

local function get_unit_state(npc)
    local index = Entity.GetIndex(npc)
    local state = unit_state[index]
    if not state then
        state = {
            last_mirror = -math.huge,
            last_follow = -math.huge,
            last_attack_time = -math.huge,
            last_attack_target = nil,
            last_attack_target_index = nil,
            ability_last_cast = {},
        }
        unit_state[index] = state
    end
    state.npc = npc
    return state, index
end

local function is_valid_enemy(entity, hero_team)
    return entity and Entity.IsAlive(entity) and not Entity.IsDormant(entity) and Entity.GetTeamNum(entity) ~= hero_team
end

local function distance_between(entity_a, entity_b)
    local origin_a = Entity.GetAbsOrigin(entity_a)
    local origin_b = Entity.GetAbsOrigin(entity_b)
    if not origin_a or not origin_b then
        return math.huge
    end
    return origin_a:Distance2D(origin_b)
end

local function find_nearest(entity, list)
    if not list then
        return nil
    end
    local best_target
    local best_distance = math.huge
    local origin = Entity.GetAbsOrigin(entity)
    if not origin then
        return nil
    end
    for i = 1, #list do
        local target = list[i]
        local target_origin = Entity.GetAbsOrigin(target)
        if target_origin then
            local distance = origin:Distance2D(target_origin)
            if distance < best_distance then
                best_distance = distance
                best_target = target
            end
        end
    end
    return best_target, best_distance
end

local function enemy_nearby(npc, radius)
    if radius <= 0 then
        radius = 600
    end
    local heroes = Entity.GetHeroesInRadius(npc, radius, Enum.TeamType.TEAM_ENEMY, false, true)
    if heroes and #heroes > 0 then
        return heroes[1]
    end
    local creeps = Entity.GetUnitsInRadius(npc, radius, Enum.TeamType.TEAM_ENEMY, false, true)
    if creeps and #creeps > 0 then
        return creeps[1]
    end
    return nil
end

local function get_cast_range(ability, npc)
    local range = Ability.GetCastRange(ability)
    if type(range) ~= "number" or range <= 0 then
        if npc and NPC.GetAttackRange then
            local attack_range = NPC.GetAttackRange(npc)
            if attack_range and attack_range > 0 then
                range = attack_range + 100
            else
                range = 600
            end
        else
            range = 600
        end
    end
    return range
end

local function ability_targets_enemies(ability)
    local team = Ability.GetTargetTeam(ability)
    if team == nil then
        return true
    end
    return team == Enum.TargetTeam.DOTA_UNIT_TARGET_TEAM_ENEMY
        or team == Enum.TargetTeam.DOTA_UNIT_TARGET_TEAM_BOTH
        or team == Enum.TargetTeam.DOTA_UNIT_TARGET_TEAM_CUSTOM
end

local function should_attempt_ability(state, ability, now)
    local attempts = state.ability_last_cast
    local last = attempts[ability]
    if last and (now - last) < 0.3 then
        return false
    end
    return true
end

local function record_ability_attempt(state, ability, now)
    state.ability_last_cast[ability] = now
end

local function cast_unit_ability(npc, ability, target, threat, hero_team, now, state)
    if not ability or Ability.IsHidden(ability) then
        return false
    end
    if Ability.GetLevel(ability) <= 0 then
        return false
    end
    if not Ability.IsActivated(ability) then
        return false
    end
    local mana = NPC.GetMana(npc)
    if not Ability.IsReady(ability) then
        return false
    end
    if not Ability.IsCastable(ability, mana) then
        return false
    end

    local behavior = Ability.GetBehavior(ability)
    if type(behavior) ~= "number" then
        return false
    end

    if BIT_BAND(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_PASSIVE) ~= 0 then
        return false
    end
    if BIT_BAND(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_TOGGLE) ~= 0 then
        return false
    end
    if BIT_BAND(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_ITEM) ~= 0 then
        return false
    end
    if BIT_BAND(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING) ~= 0 then
        return false
    end

    if (NPC.IsSilenced and NPC.IsSilenced(npc)) and BIT_BAND(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_CHANNELLED) == 0 then
        local team = Ability.GetTargetTeam(ability)
        if team == Enum.TargetTeam.DOTA_UNIT_TARGET_TEAM_ENEMY or team == Enum.TargetTeam.DOTA_UNIT_TARGET_TEAM_BOTH then
            return false
        end
    end

    if not should_attempt_ability(state, ability, now) then
        return false
    end

    local npc_origin = Entity.GetAbsOrigin(npc)
    if not npc_origin then
        return false
    end

    local casted = false
    local cast_range = get_cast_range(ability, npc)
    local engaged_target = nil
    if is_valid_enemy(target, hero_team) then
        engaged_target = target
    elseif is_valid_enemy(threat, hero_team) then
        engaged_target = threat
    end
    local attack_target = nil
    if NPC.GetAttackTarget then
        attack_target = NPC.GetAttackTarget(npc)
        if not is_valid_enemy(attack_target, hero_team) then
            attack_target = nil
        end
    end
    if not engaged_target then
        engaged_target = attack_target
    end

    if BIT_BAND(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_UNIT_TARGET) ~= 0 then
        if not ability_targets_enemies(ability) then
            return false
        end
        local use_target = engaged_target
        if not is_valid_enemy(use_target, hero_team) or distance_between(npc, use_target) > (cast_range + 100) then
            local heroes = Entity.GetHeroesInRadius(npc, cast_range + 100, Enum.TeamType.TEAM_ENEMY, false, true)
            use_target = find_nearest(npc, heroes)
            if not use_target then
                local creeps = Entity.GetUnitsInRadius(npc, cast_range + 100, Enum.TeamType.TEAM_ENEMY, false, true)
                use_target = find_nearest(npc, creeps)
            end
        end
        if is_valid_enemy(use_target, hero_team) then
            record_ability_attempt(state, ability, now)
            Ability.CastTarget(ability, use_target)
            casted = true
        end
    elseif BIT_BAND(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_POINT) ~= 0 then
        local target_entity = engaged_target
        if not is_valid_enemy(target_entity, hero_team) then
            target_entity = enemy_nearby(npc, cast_range + 200)
        end
        if is_valid_enemy(target_entity, hero_team) then
            local position = Entity.GetAbsOrigin(target_entity)
            if position and npc_origin:Distance2D(position) <= (cast_range + 200) then
                record_ability_attempt(state, ability, now)
                Ability.CastPosition(ability, position)
                casted = true
            end
        end
    elseif BIT_BAND(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_NO_TARGET) ~= 0 then
        local target_entity = engaged_target
        if is_valid_enemy(target_entity, hero_team) and distance_between(npc, target_entity) <= (cast_range + 150) then
            record_ability_attempt(state, ability, now)
            Ability.CastNoTarget(ability)
            casted = true
        else
            local nearby = enemy_nearby(npc, cast_range + 150)
            if nearby and is_valid_enemy(nearby, hero_team) then
                record_ability_attempt(state, ability, now)
                Ability.CastNoTarget(ability)
                casted = true
            elseif NPC.IsAttacking and NPC.IsAttacking(npc) and attack_target and distance_between(npc, attack_target) <= (cast_range + 150) then
                record_ability_attempt(state, ability, now)
                Ability.CastNoTarget(ability)
                casted = true
            end
        end
    end

    if casted then
        state.last_follow = now
    end

    return casted
end

local function process_unit_abilities(npc, target, threat, hero_team, now, state)
    if NPC.IsChannellingAbility and NPC.IsChannellingAbility(npc) then
        return
    end
    if NPC.IsStunned and NPC.IsStunned(npc) then
        return
    end

    for slot = 0, 23 do
        local ability = NPC.GetAbilityByIndex(npc, slot)
        if not ability then
            break
        end
        cast_unit_ability(npc, ability, target, threat, hero_team, now, state)
    end
end

local function select_unit_attack_target(npc, hero, hero_target, hero_team)
    if NPC.GetAttackTarget then
        local current = NPC.GetAttackTarget(npc)
        if is_valid_enemy(current, hero_team) then
            return current
        end
    end

    if is_valid_enemy(hero_target, hero_team) and distance_between(npc, hero_target) <= 2000 then
        return hero_target
    end

    local heroes = Entity.GetHeroesInRadius(npc, 1500, Enum.TeamType.TEAM_ENEMY, false, true)
    local target = find_nearest(npc, heroes)
    if is_valid_enemy(target, hero_team) then
        return target
    end

    local creeps = Entity.GetUnitsInRadius(npc, 1200, Enum.TeamType.TEAM_ENEMY, false, true)
    target = find_nearest(npc, creeps)
    if is_valid_enemy(target, hero_team) then
        return target
    end

    return nil
end

local function get_current_hero_target(hero, now)
    local hero_team = Entity.GetTeamNum(hero)
    local target = hero_state.last_target
    if is_valid_enemy(target, hero_team) and (now - hero_state.last_target_time) <= 5.0 then
        return target
    end
    hero_state.last_target = nil
    return nil
end

local function get_preferences()
    return {
        hero_clones = ui.units.hero_clones:Get(),
        illusions = ui.units.illusions:Get(),
        summons = ui.units.summons:Get(),
        lane_creeps = ui.units.lane_creeps:Get(),
        siege = ui.units.siege:Get(),
        couriers = ui.units.couriers:Get(),
    }
end

local function is_siege_creep(name)
    if not name then
        return false
    end
    return name:find("siege", 1, true) ~= nil or name:find("catapult", 1, true) ~= nil
end

local function should_control(npc, hero, prefs)
    if NPC.IsCourier(npc) then
        return false
    end

    if NPC.IsIllusion(npc) then
        return prefs.illusions
    end

    if hero and npc == hero then
        return false
    end

    if NPC.IsHero(npc) or NPC.IsConsideredHero(npc) then
        return prefs.hero_clones
    end

    if NPC.IsLaneCreep(npc) then
        local name = NPC.GetUnitName(npc)
        if is_siege_creep(name) then
            return prefs.siege
        end
        return prefs.lane_creeps
    end

    if NPC.IsCreep(npc) then
        local name = NPC.GetUnitName(npc)
        if is_siege_creep(name) then
            return prefs.siege
        end
        return prefs.summons
    end

    return false
end

local function refresh_controlled_units(hero, now)
    now = now or get_time()
    local player = Players.GetLocal()
    if not player then
        clear_state()
        last_cache_time = now
        return cached_units
    end

    local player_id = Player.GetPlayerID(player)
    if not player_id or player_id < 0 then
        clear_state()
        last_cache_time = now
        return cached_units
    end

    local prefs = get_preferences()
    local selected_lookup = build_selected_lookup(player)
    local alive_indices = {}
    local list = {}

    for _, npc in pairs(NPCs.GetAll()) do
        if npc ~= hero and Entity.IsAlive(npc) and not Entity.IsDormant(npc) then
            if NPC.IsControllableByPlayer(npc, player_id) and not NPC.IsWaitingToSpawn(npc) and not NPC.IsStructure(npc) then
                if should_control(npc, hero, prefs) then
                    local index = Entity.GetIndex(npc)
                    if not index or not selected_lookup[index] then
                        list[#list + 1] = npc
                        local state
                        state, index = get_unit_state(npc)
                        state.last_seen = now
                        if index then
                            alive_indices[index] = true
                        end
                    end
                end
            end
        end
    end

    for index, _ in pairs(unit_state) do
        if not alive_indices[index] then
            unit_state[index] = nil
        end
    end

    cached_units = list
    last_cache_time = now
    return cached_units
end

local function ensure_units_cache(hero, now)
    now = now or get_time()
    if (now - last_cache_time) >= cache_interval then
        return refresh_controlled_units(hero, now)
    end
    return cached_units
end

local function issue_group_order(units, order, target, position, queue, show_effects)
    if not units or #units == 0 then
        return
    end

    local player = Players.GetLocal()
    if not player then
        return
    end

    position = position or ZERO_VECTOR
    is_internal_order = true
    local ok, err = pcall(
        Player.PrepareUnitOrders,
        player,
        order,
        target,
        position,
        nil,
        Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY,
        units,
        queue or false,
        show_effects or false,
        false,
        true,
        SCRIPT_ID,
        false
    )
    is_internal_order = false

    if not ok then
        print("[AutoControl] prepare order failed:", err)
    end
end

local function forward_hero_order(order)
    if not ui.enabled:Get() or not ui.mirror_orders:Get() then
        return
    end

    local hero = Heroes.GetLocal()
    if not hero or order.npc ~= hero then
        return
    end

    local local_player = Players.GetLocal()
    if not local_player or order.player ~= local_player then
        return
    end

    if not MIRRORABLE_ORDERS[order.order] then
        return
    end

    local now = get_time()
    if order.order == Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET then
        if order.target then
            hero_state.last_target = order.target
            hero_state.last_target_time = now
        end
    elseif order.order == Enum.UnitOrder.DOTA_UNIT_ORDER_STOP or order.order == Enum.UnitOrder.DOTA_UNIT_ORDER_HOLD_POSITION then
        hero_state.last_target = nil
        hero_state.last_target_time = -math.huge
    elseif order.order == Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_MOVE then
        hero_state.last_target = nil
        hero_state.last_target_time = now
    end

    local units = ensure_units_cache(hero, now)
    if #units == 0 then
        return
    end

    local to_command = {}
    local selected_lookup = build_selected_lookup(local_player)

    for _, npc in ipairs(units) do
        if Entity.IsAlive(npc) then
            local state = get_unit_state(npc)
            local index = Entity.GetIndex(npc)
            if not index or not selected_lookup[index] then
                state.last_mirror = now
                state.last_follow = now
                to_command[#to_command + 1] = npc
            end
        end
    end

    if #to_command == 0 then
        return
    end

    issue_group_order(to_command, order.order, order.target, order.position, order.queue, order.showEffects)
end

local function maintain_units(hero, units, now)
    local interval = ui.update_interval:Get()
    if (now - last_maintain_time) < interval then
        return
    end
    last_maintain_time = now

    local fallback_mode = ui.fallback_mode:Get()
    local follow_radius = ui.follow_radius:Get()
    local threshold = ui.reapply_threshold:Get()
    local attack_offset = ui.attack_offset:Get()

    local hero_position = Entity.GetAbsOrigin(hero)
    local attack_position = hero_position
    if fallback_mode == 1 then
        local forward = Entity.GetForwardPosition(hero, attack_offset)
        if forward and (forward.x ~= 0 or forward.y ~= 0 or forward.z ~= 0) then
            attack_position = forward
        end
    end

    local hero_team = Entity.GetTeamNum(hero)
    local hero_target = get_current_hero_target(hero, now)
    if not is_valid_enemy(hero_target, hero_team) then
        hero_target = nil
    end

    local move_units = {}
    local attack_units = {}
    local hold_units = {}
    local direct_attacks = {}

    local player = Players.GetLocal()
    local selected_lookup = build_selected_lookup(player)

    for _, npc in ipairs(units) do
        if Entity.IsAlive(npc) and not Entity.IsDormant(npc) then
            local state = get_unit_state(npc)
            local index = Entity.GetIndex(npc)
            if not index or not selected_lookup[index] then
                if state.last_attack_target and not is_valid_enemy(state.last_attack_target, hero_team) then
                    state.last_attack_target = nil
                    state.last_attack_target_index = nil
                end

                local attack_target = select_unit_attack_target(npc, hero, hero_target, hero_team)
                local ability_target = nil
                if NPC.GetAttackTarget then
                    ability_target = NPC.GetAttackTarget(npc)
                    if not is_valid_enemy(ability_target, hero_team) then
                        ability_target = nil
                    end
                end
                if not ability_target then
                    ability_target = attack_target or hero_target
                end
                local threat_target = ability_target
                if not is_valid_enemy(threat_target, hero_team) then
                    threat_target = enemy_nearby(npc, 900)
                end
                process_unit_abilities(npc, ability_target, threat_target, hero_team, now, state)

                if attack_target and (now - state.last_mirror) >= 0.05 then
                    local target_index = Entity.GetIndex(attack_target)
                    if target_index then
                        local needs_order = true
                        if state.last_attack_target_index == target_index then
                            if (now - state.last_attack_time) < 0.4 then
                                needs_order = false
                            end
                        end
                        if needs_order then
                            local group = direct_attacks[target_index]
                            if not group then
                                group = { target = attack_target, units = {} }
                                direct_attacks[target_index] = group
                            end
                            group.units[#group.units + 1] = npc
                            state.last_attack_target = attack_target
                            state.last_attack_target_index = target_index
                            state.last_attack_time = now
                            state.last_follow = now
                        end
                    end
                end

                if (now - state.last_mirror) >= interval then
                    local position = Entity.GetAbsOrigin(npc)
                    local distance = hero_position:Distance2D(position)
                    if distance >= (follow_radius + threshold) and (now - state.last_follow) >= interval then
                        if fallback_mode == 0 then
                            move_units[#move_units + 1] = npc
                        elseif fallback_mode == 1 then
                            attack_units[#attack_units + 1] = npc
                        else
                            hold_units[#hold_units + 1] = npc
                        end
                        state.last_follow = now
                    end
                end
            end
        end
    end

    for _, group in pairs(direct_attacks) do
        if group.target and group.units and #group.units > 0 then
            issue_group_order(group.units, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, group.target, ZERO_VECTOR, false, false)
        end
    end

    if #move_units > 0 then
        issue_group_order(move_units, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, hero_position, false, false)
    end

    if #attack_units > 0 then
        issue_group_order(attack_units, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_MOVE, nil, attack_position, false, false)
    end

    if #hold_units > 0 then
        issue_group_order(hold_units, Enum.UnitOrder.DOTA_UNIT_ORDER_HOLD_POSITION, nil, ZERO_VECTOR, false, false)
    end
end

function script.OnUpdate()
    if not ui.enabled:Get() then
        return
    end

    local hero = Heroes.GetLocal()
    if not hero or not Entity.IsAlive(hero) then
        clear_state()
        return
    end

    local now = get_time()
    local units = ensure_units_cache(hero, now)
    if #units == 0 then
        return
    end

    maintain_units(hero, units, now)
end

function script.OnPrepareUnitOrders(order)
    if is_internal_order then
        return true
    end

    forward_hero_order(order)
    return true
end

return script
