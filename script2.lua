---@diagnostic disable: undefined-global, param-type-mismatch, inject-field

local keyboard_move = {}

local menu_root = Menu.Create("Miscellaneous", "In Game", "Keyboard Move")
local menu_group = menu_root:Create("Main"):Create("Keyboard Move")

local ui = {
    enabled = menu_group:Switch("Включить WASD-передвижение", true, "\u{f11c}"),
    hold = menu_group:Switch("Повторять приказ при удержании", true),
    distance = menu_group:Slider("Базовая дистанция направления", 150, 900, 380, "%d"),
    lead = menu_group:Slider("Дополнительный запас вперёд", 0, 600, 140, "%d"),
    interval = menu_group:Slider("Интервал повторных приказов (мс)", 40, 400, 120, "%d"),
    respect_state = menu_group:Switch("Не перебивать во время стана/канала", true),
}

local KEY_BINDINGS = {
    forward = Enum.ButtonCode.KEY_W,
    back = Enum.ButtonCode.KEY_S,
    left = Enum.ButtonCode.KEY_A,
    right = Enum.ButtonCode.KEY_D,
}

local KEY_LIST = {
    Enum.ButtonCode.KEY_W,
    Enum.ButtonCode.KEY_S,
    Enum.ButtonCode.KEY_A,
    Enum.ButtonCode.KEY_D,
}

local ORDER_IDENTIFIER = "keyboard_wasd_move"

local state = {
    next_order_time = 0,
    last_input_direction = nil,
    last_order_direction = nil,
    wait_release = false,
}

local function any_key_pressed_once()
    for i = 1, #KEY_LIST do
        if Input.IsKeyDownOnce(KEY_LIST[i]) then
            return true
        end
    end

    return false
end

local function collect_selected_units(player)
    local selected = Player.GetSelectedUnits(player)
    if not selected or #selected == 0 then
        return nil, nil
    end

    local alive = {}
    local player_id = Player.GetPlayerID(player)
    for i = 1, #selected do
        local unit = selected[i]
        if
            Entity.IsNPC(unit)
            and Entity.IsAlive(unit)
            and (not player_id or Entity.IsControllableByPlayer(unit, player_id))
        then
            alive[#alive + 1] = unit
        end
    end

    if #alive == 0 then
        return nil, nil
    end

    local hero = Heroes.GetLocal()
    if hero then
        local hero_index = Entity.GetIndex(hero)
        for i = 1, #alive do
            if Entity.GetIndex(alive[i]) == hero_index then
                return alive, alive[i]
            end
        end
    end

    return alive, alive[1]
end

local function build_direction()
    local direction = Vector()
    local any_down = false

    if Input.IsKeyDown(KEY_BINDINGS.forward) then
        direction = direction + Vector(0, 1, 0)
        any_down = true
    end
    if Input.IsKeyDown(KEY_BINDINGS.back) then
        direction = direction + Vector(0, -1, 0)
        any_down = true
    end
    if Input.IsKeyDown(KEY_BINDINGS.right) then
        direction = direction + Vector(1, 0, 0)
        any_down = true
    end
    if Input.IsKeyDown(KEY_BINDINGS.left) then
        direction = direction + Vector(-1, 0, 0)
        any_down = true
    end

    if not any_down then
        return nil, false
    end

    direction.z = 0
    if direction:Length2D() == 0 then
        return nil, true
    end

    direction = direction:Normalized()
    return direction, true
end

local function can_issue(reference)
    if not reference or not Entity.IsAlive(reference) then
        return false
    end

    if ui.respect_state:Get() and (NPC.IsStunned(reference) or NPC.IsChannellingAbility(reference)) then
        return false
    end

    return true
end

local function adjust_target(reference_pos, direction, distance)
    local target = reference_pos + direction:Scaled(distance)
    if GridNav.IsTraversableFromTo(reference_pos, target, false, nil) then
        return target
    end

    local step = distance
    for _ = 1, 4 do
        step = step * 0.5
        if step < 25 then
            break
        end

        target = reference_pos + direction:Scaled(step)
        if GridNav.IsTraversableFromTo(reference_pos, target, false, nil) then
            return target
        end
    end

    return nil
end

function keyboard_move.OnUpdate()
    if not ui.enabled:Get() then
        return
    end

    if Input.IsInputCaptured() then
        return
    end

    local player = Players.GetLocal()
    if not player then
        return
    end

    local issuers, reference = collect_selected_units(player)
    if not issuers or not reference then
        state.last_input_direction = nil
        state.last_order_direction = nil
        state.next_order_time = 0
        state.wait_release = false
        return
    end

    if not can_issue(reference) then
        state.next_order_time = 0
        return
    end

    local direction, has_active_key = build_direction()
    if not direction then
        if ui.hold:Get() and state.last_order_direction and not has_active_key then
            Player.PrepareUnitOrders(
                player,
                Enum.UnitOrder.DOTA_UNIT_ORDER_STOP,
                nil,
                nil,
                nil,
                Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_SELECTED_UNITS,
                issuers,
                false,
                false,
                false,
                false,
                ORDER_IDENTIFIER
            )
        end

        state.last_input_direction = nil
        state.last_order_direction = nil
        state.next_order_time = 0
        state.wait_release = false
        return
    end

    local now = GlobalVars.GetCurTime()
    local should_issue = false

    if ui.hold:Get() then
        if not state.last_input_direction or now >= state.next_order_time then
            should_issue = true
        elseif state.last_input_direction and direction:Dot2D(state.last_input_direction) < 0.995 then
            should_issue = true
        end
    else
        if state.wait_release then
            if not has_active_key then
                state.wait_release = false
            end
        elseif any_key_pressed_once() then
            should_issue = true
            state.wait_release = true
        end
    end

    if not should_issue then
        return
    end

    local reference_pos = Entity.GetAbsOrigin(reference)
    local distance = ui.distance:Get() + ui.lead:Get()
    local target = adjust_target(reference_pos, direction, distance)
    if not target then
        state.next_order_time = now + ui.interval:Get() / 1000.0
        return
    end

    state.last_input_direction = direction
    Player.PrepareUnitOrders(
        player,
        Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION,
        nil,
        target,
        nil,
        Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_SELECTED_UNITS,
        issuers,
        false,
        false,
        false,
        false,
        ORDER_IDENTIFIER
    )

    state.last_order_direction = (target - reference_pos):Normalized()
    if ui.hold:Get() then
        state.next_order_time = now + ui.interval:Get() / 1000.0
    else
        state.next_order_time = 0
    end
end

function keyboard_move.OnGameEnd()
    state.last_input_direction = nil
    state.last_order_direction = nil
    state.next_order_time = 0
    state.wait_release = false
end

return keyboard_move
