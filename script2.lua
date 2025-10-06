---@diagnostic disable: undefined-global, param-type-mismatch, inject-field

local keyboard_move = {}

local STEP_DISTANCE = 420
local LEAD_DISTANCE = 160
local REPEAT_INTERVAL = 0.12 -- seconds
local STOP_ON_RELEASE = true

local KEY_ORDER = {
    Enum.ButtonCode.KEY_W,
    Enum.ButtonCode.KEY_A,
    Enum.ButtonCode.KEY_S,
    Enum.ButtonCode.KEY_D,
}

local KEY_DIRECTIONS = {
    [Enum.ButtonCode.KEY_W] = Vector(0, 1, 0),  -- вверх по карте (север)
    [Enum.ButtonCode.KEY_S] = Vector(0, -1, 0), -- вниз (юг)
    [Enum.ButtonCode.KEY_A] = Vector(-1, 0, 0), -- влево (запад)
    [Enum.ButtonCode.KEY_D] = Vector(1, 0, 0),  -- вправо (восток)
}

local ORDER_IDENTIFIER = "keyboard_move_wasd"

local state = {
    last_direction = nil,
    next_order_time = 0,
    moving = false,
}

local function gather_selected(player)
    local selected = Player.GetSelectedUnits(player)
    if not selected or #selected == 0 then
        return nil, nil
    end

    local valid = {}
    for i = 1, #selected do
        local unit = selected[i]
        if Entity.IsNPC(unit) and Entity.IsAlive(unit) then
            valid[#valid + 1] = unit
        end
    end

    if #valid == 0 then
        return nil, nil
    end

    local hero = Heroes.GetLocal()
    if hero then
        local hero_index = Entity.GetIndex(hero)
        for i = 1, #valid do
            if Entity.GetIndex(valid[i]) == hero_index then
                return valid, valid[i]
            end
        end
    end

    return valid, valid[1]
end

local function current_direction()
    local dir = Vector(0, 0, 0)
    local pressed = false

    for i = 1, #KEY_ORDER do
        local key = KEY_ORDER[i]
        if Input.IsKeyDown(key) then
            dir = dir + KEY_DIRECTIONS[key]
            pressed = true
        end
    end

    if not pressed then
        return nil
    end

    dir.z = 0
    if dir:Length2D() == 0 then
        return nil
    end

    return dir:Normalized()
end

local function adjust_target(origin, direction, distance)
    local desired = origin + direction:Scaled(distance)
    if GridNav.IsTraversableFromTo(origin, desired, false, nil) then
        return desired
    end

    local step = distance
    for _ = 1, 5 do
        step = step * 0.5
        if step < 25 then
            break
        end

        local candidate = origin + direction:Scaled(step)
        if GridNav.IsTraversableFromTo(origin, candidate, false, nil) then
            return candidate
        end
    end

    return nil
end

local function issue_move(player, units, target)
    Player.PrepareUnitOrders(
        player,
        Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION,
        nil,
        target,
        nil,
        Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_SELECTED_UNITS,
        units,
        false,
        false,
        false,
        false,
        ORDER_IDENTIFIER
    )
end

local function issue_stop(player, units)
    Player.PrepareUnitOrders(
        player,
        Enum.UnitOrder.DOTA_UNIT_ORDER_STOP,
        nil,
        nil,
        nil,
        Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_SELECTED_UNITS,
        units,
        false,
        false,
        false,
        false,
        ORDER_IDENTIFIER
    )
end

function keyboard_move.OnUpdate()
    local player = Players.GetLocal()
    if not player then
        return
    end

    local units, reference = gather_selected(player)
    if not units or not reference then
        state.last_direction = nil
        state.next_order_time = 0
        state.moving = false
        return
    end

    if NPC.IsChannellingAbility(reference) or NPC.IsStunned(reference) then
        state.next_order_time = 0
        return
    end

    local direction = current_direction()
    local now = GlobalVars.GetCurTime()

    if not direction then
        if state.moving and STOP_ON_RELEASE then
            issue_stop(player, units)
        end
        state.moving = false
        state.last_direction = nil
        state.next_order_time = 0
        return
    end

    local need_issue = false
    if not state.last_direction then
        need_issue = true
    else
        local dot = direction:Dot2D(state.last_direction)
        if dot < 0.995 then
            need_issue = true
        elseif now >= state.next_order_time then
            need_issue = true
        end
    end

    if not need_issue then
        return
    end

    local origin = Entity.GetAbsOrigin(reference)
    local distance = STEP_DISTANCE + LEAD_DISTANCE
    local target = adjust_target(origin, direction, distance)
    if not target then
        state.next_order_time = now + REPEAT_INTERVAL
        return
    end

    issue_move(player, units, target)

    state.last_direction = direction
    state.moving = true
    state.next_order_time = now + REPEAT_INTERVAL
end

function keyboard_move.OnGameEnd()
    state.last_direction = nil
    state.next_order_time = 0
    state.moving = false
end

return keyboard_move
