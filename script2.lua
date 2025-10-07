---@diagnostic disable: undefined-global

local camera_helper = {}

local ui = {}
local state = {
    lock_active = false,
    last_follow_pos = nil,
}

local convars = {
    lock = ConVar.Find("dota_camera_lock"),
    lock_to_hero = ConVar.Find("dota_camera_lock_to_hero"),
}

local menu_group = Menu.Create("Utility", "Camera Helper", "Camera", "Main", "Настройки")
ui.follow_enabled = menu_group:Switch("Автоследование за героем", true)
ui.follow_enabled:ToolTip("Держит камеру в центре вокруг основного героя, пока опция активна.")
ui.follow_when_dead = menu_group:Switch("Следовать, когда герой мёртв", true)
ui.follow_when_dead:ToolTip("Если выключено, камера перестаёт двигаться, пока герой мёртв.")
ui.min_distance = menu_group:Slider("Мин. смещение для обновления", 0, 600, 32, "%d ед.")
ui.min_distance:ToolTip("Насколько далеко должен сместиться герой (в игровых единицах), прежде чем камера обновит позицию.")
ui.lock_bind = menu_group:Bind("Переключить фиксацию камеры", Enum.ButtonCode.KEY_SPACE)
ui.lock_bind:Properties(nil, nil, true)
ui.lock_bind:ToolTip("Назначьте клавишу для включения \u{2013} отключения dota_camera_lock и dota_camera_lock_to_hero.")
ui.lock_status = menu_group:Switch("Фиксация активна", false)
ui.lock_status:Disabled(true)
ui.lock_status:ToolTip("Отображает текущее состояние фиксации камеры (только для чтения).")

local updating_bind_state = false

local function clone_vector(vec)
    return Vector(vec.x, vec.y, vec.z)
end

local function set_camera_convar(handle, name, value)
    if handle then
        ConVar.SetInt(handle, value)
        return handle
    end

    local found = ConVar.Find(name)
    if found then
        ConVar.SetInt(found, value)
        return found
    end

    Engine.ExecuteCommand(string.format("%s %d", name, value))
    return nil
end

local function update_lock_ui(is_active)
    if ui.lock_status then
        ui.lock_status:Set(is_active)
    end

    if ui.lock_bind and ui.lock_bind:IsToggled() ~= is_active then
        updating_bind_state = true
        ui.lock_bind:SetToggled(is_active)
        updating_bind_state = false
    end
end

local function apply_camera_lock(is_active)
    is_active = not not is_active
    state.lock_active = is_active
    update_lock_ui(is_active)

    local convar_value = is_active and 1 or 0
    convars.lock = set_camera_convar(convars.lock, "dota_camera_lock", convar_value)
    convars.lock_to_hero = set_camera_convar(convars.lock_to_hero, "dota_camera_lock_to_hero", convar_value)

    if is_active then
        local hero = Heroes.GetLocal()
        if hero then
            local hero_pos = Entity.GetAbsOrigin(hero)
            if hero_pos then
                Engine.LookAt(hero_pos.x, hero_pos.y)
            end
        end
    else
        state.last_follow_pos = nil
    end
end

ui.lock_bind:SetCallback(function(bind)
    if updating_bind_state then
        return
    end

    apply_camera_lock(bind:IsToggled())
end, false)

apply_camera_lock(false)

local function should_follow(hero)
    if not ui.follow_enabled:Get() then
        return false
    end

    if not ui.follow_when_dead:Get() and not Entity.IsAlive(hero) then
        return false
    end

    return true
end

function camera_helper.OnUpdate()
    if not Engine.IsInGame() then
        state.last_follow_pos = nil
        return
    end

    if state.lock_active then
        state.last_follow_pos = nil
        return
    end

    local hero = Heroes.GetLocal()
    if not hero then
        state.last_follow_pos = nil
        return
    end

    if not should_follow(hero) then
        state.last_follow_pos = nil
        return
    end

    local hero_pos = Entity.GetAbsOrigin(hero)
    if not hero_pos then
        return
    end

    if state.last_follow_pos then
        local delta = hero_pos - state.last_follow_pos
        local min_distance = ui.min_distance:Get()
        if min_distance > 0 and delta:Length2DSqr() < (min_distance * min_distance) then
            return
        end
    end

    Engine.LookAt(hero_pos.x, hero_pos.y)
    state.last_follow_pos = clone_vector(hero_pos)
end

function camera_helper.OnGameEnd()
    apply_camera_lock(false)
    state.last_follow_pos = nil
end

return camera_helper
