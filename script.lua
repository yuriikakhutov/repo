---@diagnostic disable: undefined-global

local script = {}

local SCRIPT_ID <const> = "auto_unit_controller"
local ZERO_VECTOR <const> = Vector()

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

local function clear_state()
    cached_units = {}
    unit_state = {}
    last_cache_time = 0
    last_maintain_time = 0
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
        }
        unit_state[index] = state
    end
    state.npc = npc
    return state, index
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
        return prefs.couriers
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
    local alive_indices = {}
    local list = {}

    for _, npc in pairs(NPCs.GetAll()) do
        if npc ~= hero and Entity.IsAlive(npc) and not Entity.IsDormant(npc) then
            if NPC.IsControllableByPlayer(npc, player_id) and not NPC.IsWaitingToSpawn(npc) and not NPC.IsStructure(npc) then
                if should_control(npc, hero, prefs) then
                    list[#list + 1] = npc
                    local state, index = get_unit_state(npc)
                    state.last_seen = now
                    alive_indices[index] = true
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
    local units = ensure_units_cache(hero, now)
    if #units == 0 then
        return
    end

    local to_command = {}
    for _, npc in ipairs(units) do
        if Entity.IsAlive(npc) then
            local state = get_unit_state(npc)
            state.last_mirror = now
            state.last_follow = now
            to_command[#to_command + 1] = npc
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

    local move_units = {}
    local attack_units = {}
    local hold_units = {}

    for _, npc in ipairs(units) do
        if Entity.IsAlive(npc) and not Entity.IsDormant(npc) then
            local state = get_unit_state(npc)
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
