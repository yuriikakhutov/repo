---@diagnostic disable: undefined-global, param-type-mismatch, cast-local-type

local script = {}

local RUBICK_NAME = "npc_dota_hero_rubick"
local TELEKINESIS_NAME = "rubick_telekinesis"
local TELEKINESIS_LAND_NAME = "rubick_telekinesis_land"
local TELEKINESIS_MODIFIER = "modifier_rubick_telekinesis"
local MAX_ABILITY_SLOTS = 32

local BLINK_ITEMS = {
    "item_blink",
    "item_overwhelming_blink",
    "item_swift_blink",
    "item_arcane_blink",
}

local JSON = dofile("assets/JSON.lua")

local ABILITY_DATA = nil
local SPELLS = {}
local SPELL_LIST = {}

local HERO_CATALOG = {}
local HERO_SETTINGS = {}
local HERO_DISPLAY_LIST = {}
local HERO_DISPLAY_TO_INTERNAL = {}
local HERO_PRIORITY = {}
local HERO_PRIORITY_INDEX = {}
local ABILITY_TO_HERO = {}

local RADIUS_KEYS = {
    "radius",
    "aoe",
    "aoe_radius",
    "area_of_effect",
    "effect_radius",
    "impact_radius",
    "pull_radius",
    "coil_radius",
    "ring_radius",
    "AbilityRadius",
}

local BASE_RUBICK_ABILITIES = {
    [TELEKINESIS_NAME] = true,
    ["rubick_fade_bolt"] = true,
    ["rubick_null_field"] = true,
    ["rubick_spell_steal"] = true,
    ["rubick_empty1"] = true,
    ["rubick_empty2"] = true,
    ["rubick_empty3"] = true,
    ["rubick_empty4"] = true,
    ["rubick_hidden1"] = true,
    ["rubick_hidden2"] = true,
    ["rubick_hidden3"] = true,
    ["rubick_hidden4"] = true,
    ["rubick_hidden5"] = true,
}

local function load_ability_data()
    if ABILITY_DATA then
        return ABILITY_DATA
    end

    local file = io.open("assets/data/npc_abilities.json", "r")
    if not file then
        ABILITY_DATA = {}
        return ABILITY_DATA
    end

    local raw = file:read("*a")
    file:close()

    local decoded = JSON:decode(raw)
    ABILITY_DATA = decoded and decoded.DOTAAbilities or {}
    return ABILITY_DATA
end

local function has_behavior(info, flag)
    local behavior = info and info.AbilityBehavior
    if type(behavior) ~= "string" then
        return false
    end
    return behavior:find(flag, 1, true) ~= nil
end

local function ability_display_name(name)
    local parts = {}
    for chunk in name:gmatch("[^_]+") do
        if #chunk > 0 then
            table.insert(parts, chunk:sub(1, 1):upper() .. chunk:sub(2))
        end
    end
    return table.concat(parts, " ")
end

local function should_include_ability(name, info)
    if type(info) ~= "table" then
        return false
    end
    if name:match("^item_") then
        return false
    end
    if name:match("^special_bonus") then
        return false
    end
    if name:match("^attribute_bonus") then
        return false
    end
    if name:match("^ability_") then
        return false
    end
    if has_behavior(info, "DOTA_ABILITY_BEHAVIOR_PASSIVE") and not has_behavior(info, "DOTA_ABILITY_BEHAVIOR_POINT") and not has_behavior(info, "DOTA_ABILITY_BEHAVIOR_UNIT_TARGET") and not has_behavior(info, "DOTA_ABILITY_BEHAVIOR_NO_TARGET") then
        return false
    end
    return true
end

local function determine_cast_type(info)
    if has_behavior(info, "DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING") then
        return nil
    end
    if has_behavior(info, "DOTA_ABILITY_BEHAVIOR_TOGGLE") then
        return nil
    end
    if has_behavior(info, "DOTA_ABILITY_BEHAVIOR_POINT") and not has_behavior(info, "DOTA_ABILITY_BEHAVIOR_NO_TARGET") then
        return "point"
    end
    if has_behavior(info, "DOTA_ABILITY_BEHAVIOR_UNIT_TARGET") then
        return "unit"
    end
    if has_behavior(info, "DOTA_ABILITY_BEHAVIOR_NO_TARGET") then
        return "no_target"
    end
    return nil
end

local function is_channelled(info)
    if has_behavior(info, "DOTA_ABILITY_BEHAVIOR_CHANNELLED") then
        return true
    end
    local channel_time = info and info.AbilityChannelTime
    if type(channel_time) == "string" then
        return channel_time ~= "0"
    end
    if type(channel_time) == "number" then
        return channel_time > 0
    end
    return false
end

local function build_spell_catalog()
    if #SPELL_LIST > 0 then
        return SPELL_LIST
    end

    local data = load_ability_data()
    local entries = {}
    for name, info in pairs(data) do
        if should_include_ability(name, info) then
            local cast_type = determine_cast_type(info)
            if cast_type then
                local friendly = ability_display_name(name)
                local icon = "panorama/images/spellicons/" .. name .. "_png.vtex_c"
                local entry = {
                    friendly = friendly,
                    icon = icon,
                    type = cast_type,
                    data = info,
                    channel = is_channelled(info),
                }
                SPELLS[name] = entry
                table.insert(entries, { friendly = friendly, tech = name, icon = icon })
            end
        end
    end

    table.sort(entries, function(a, b)
        return a.friendly < b.friendly
    end)

    SPELL_LIST = entries
    return SPELL_LIST
end

local function clone_array(list)
    local copy = {}
    if type(list) ~= "table" then
        return copy
    end
    for index, value in ipairs(list) do
        copy[index] = value
    end
    return copy
end

local function load_json_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local raw = file:read("*a")
    file:close()
    local ok, decoded = pcall(function()
        return JSON:decode(raw)
    end)
    if not ok then
        return nil
    end
    return decoded
end

local function ability_friendly(name)
    local info = SPELLS[name]
    if info and info.friendly then
        return info.friendly
    end
    return ability_display_name(name)
end

local function ability_icon(name)
    local info = SPELLS[name]
    if info and info.icon then
        return info.icon
    end
    return "panorama/images/spellicons/" .. name .. "_png.vtex_c"
end

local function build_hero_catalog()
    HERO_CATALOG = {}
    HERO_SETTINGS = {}
    HERO_DISPLAY_LIST = {}
    HERO_DISPLAY_TO_INTERNAL = {}
    HERO_PRIORITY = {}
    HERO_PRIORITY_INDEX = {}
    ABILITY_TO_HERO = {}

    local decoded = load_json_file("db/hero_spells.json")
    local heroes = {}
    if type(decoded) == "table" then
        if type(decoded.heroes) == "table" then
            heroes = decoded.heroes
        else
            heroes = decoded
        end
    end

    for hero_name, entry in pairs(heroes) do
        if type(hero_name) == "string" and type(entry) == "table" then
            local display = entry.display or ability_display_name(hero_name)
            local ability_list = {}
            if type(entry.abilities) == "table" then
                for _, ability in ipairs(entry.abilities) do
                    if type(ability) == "string" and SPELLS[ability] then
                        table.insert(ability_list, ability)
                        ABILITY_TO_HERO[ability] = hero_name
                    end
                end
            end
            if #ability_list > 0 then
                HERO_CATALOG[hero_name] = {
                    display = display,
                    abilities = clone_array(ability_list),
                }
                HERO_DISPLAY_TO_INTERNAL[display] = hero_name
                table.insert(HERO_DISPLAY_LIST, display)

                local order = clone_array(ability_list)
                local enabled = {}
                local order_map = {}
                for idx, ability in ipairs(order) do
                    enabled[ability] = true
                    order_map[ability] = idx
                end
                HERO_SETTINGS[hero_name] = {
                    order = order,
                    enabled = enabled,
                    order_map = order_map,
                }
            end
        end
    end

    table.sort(HERO_DISPLAY_LIST)
    for _, display in ipairs(HERO_DISPLAY_LIST) do
        local hero_name = HERO_DISPLAY_TO_INTERNAL[display]
        if hero_name then
            table.insert(HERO_PRIORITY, hero_name)
        end
    end
    for index, hero_name in ipairs(HERO_PRIORITY) do
        HERO_PRIORITY_INDEX[hero_name] = index
    end
end

local function rebuild_order_map(hero_name)
    local settings = HERO_SETTINGS[hero_name]
    if not settings then
        return
    end
    settings.order_map = {}
    for index, ability in ipairs(settings.order) do
        settings.order_map[ability] = index
    end
end

local function parse_number_field(field)
    if type(field) == "number" then
        return field
    end
    if type(field) == "string" then
        local num = field:match("%-?[%d%.]+")
        return tonumber(num)
    end
    if type(field) == "table" then
        if field.value ~= nil then
            local v = parse_number_field(field.value)
            if v then
                return v
            end
        end
        for _, inner in pairs(field) do
            local v = parse_number_field(inner)
            if v then
                return v
            end
        end
    end
    return nil
end

local function ability_targets_enemies(info)
    local data = info and info.data
    local team = data and data.AbilityUnitTargetTeam
    if type(team) == "string" then
        if team:find("ENEMY", 1, true) or team:find("BOTH", 1, true) then
            return true
        end
        return false
    end
    return true
end

local function get_cast_range(ability, info)
    local range = Ability.GetCastRange(ability)
    if range and range > 0 then
        return range
    end
    local data = info and info.data
    local value = parse_number_field(data and data.AbilityCastRange)
    if value and value > 0 then
        return value
    end
    local values = data and data.AbilityValues
    if type(values) == "table" then
        for _, key in ipairs({ "AbilityCastRange", "cast_range", "range", "distance" }) do
            local v = parse_number_field(values[key])
            if v and v > 0 then
                return v
            end
        end
    end
    return 600
end

local function get_effect_radius(ability, info)
    for _, key in ipairs(RADIUS_KEYS) do
        local val = Ability.GetLevelSpecialValueFor(ability, key)
        if val and val > 0 then
            return val
        end
    end

    local data = info and info.data
    local values = data and data.AbilityValues
    if type(values) == "table" then
        for _, key in ipairs(RADIUS_KEYS) do
            local v = parse_number_field(values[key])
            if v and v > 0 then
                return v
            end
        end
        for key, value in pairs(values) do
            if type(key) == "string" and (key:find("radius") or key:find("aoe")) then
                local v = parse_number_field(value)
                if v and v > 0 then
                    return v
                end
            end
        end
    end

    local range = Ability.GetCastRange(ability)
    if range and range > 0 then
        return math.min(range, 600)
    end
    return 300
end

local function vec3(x, y, z)
    return { x = x, y = y, z = z or 0 }
end

local function vec_add(a, b)
    return vec3(a.x + b.x, a.y + b.y, (a.z or 0) + (b.z or 0))
end

local function vec_sub(a, b)
    return vec3(a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0))
end

local function vec_scale(v, s)
    return vec3(v.x * s, v.y * s, (v.z or 0) * s)
end

local function vec_length2d(v)
    return math.sqrt(v.x * v.x + v.y * v.y)
end

local function vec_normalize(v)
    local len = vec_length2d(v)
    if len <= 0.0001 then
        return vec3(0, 0, 0)
    end
    return vec3(v.x / len, v.y / len, (v.z or 0) / len)
end

local function distance(a, b)
    return vec_length2d(vec_sub(a, b))
end

local function clamp(val, min_val, max_val)
    if val < min_val then
        return min_val
    end
    if val > max_val then
        return max_val
    end
    return val
end

local function get_time()
    return GameRules.GetGameTime()
end

local menu_root = Menu.Create("Heroes", "Rubick", "Spellcraft", "General")
local group_main = menu_root
local group_combos = menu_root:Create("Combos")
local group_targets = menu_root:Create("Targets")
local group_tele = menu_root:Create("Telekinesis")
local group_visual = menu_root:Create("Visuals")
local ui = {}

ui.enable = group_main:Switch("Enable Script", false, "\u{f0e7}")
ui.mode = group_main:Combo("Use Mode", { "Manual Toggle", "Always Auto" }, 0)
ui.toggle_key = group_main:Bind("Toggle Key", Enum.ButtonCode.KEY_T)
ui.combo_key = group_main:Bind("Cast All Key", Enum.ButtonCode.KEY_G)
ui.min_targets = group_main:Slider("Min Targets", 1, 5, 2, function(v) return tostring(v) end)
ui.blink_offset = group_main:Slider("Blink Offset", -200, 200, 0, function(v) return tostring(v) .. " units" end)
ui.use_refresher = group_main:Switch("Use Refresher Orb", false, "\u{f021}")
ui.adjust_for_dead = group_main:Switch("Adjust Min Targets for Dead Enemies", false, "\u{f571}")

build_spell_catalog()
build_hero_catalog()

local hero_display_items = clone_array(HERO_DISPLAY_LIST)
if #hero_display_items == 0 then
    hero_display_items = { "No heroes available" }
end

ui.combo_enable = group_combos:Switch("Enable hero combos", true, "\u{f0e3}")
ui.combo_allow_unmapped = group_combos:Switch("Include unmapped abilities", true, "\u{f12a}")
ui.combo_edit_hero = group_combos:Combo("Edit hero", hero_display_items, 0)
ui.combo_multiselect = group_combos:MultiSelect("Combo abilities", {}, true)
ui.combo_multiselect:DragAllowed(true)
ui.combo_edit_hero:Disabled(#HERO_DISPLAY_LIST == 0)
ui.combo_multiselect:Disabled(#HERO_DISPLAY_LIST == 0)

ui.tele_enable = group_tele:Switch("Smart Telekinesis landing", true)
ui.tele_preference = group_tele:Combo("Preferred landing", {
    "Nearest allied tower",
    "Nearest allied hero",
    "Towards Rubick",
}, 0)
ui.tele_gap = group_tele:Slider("Minimum gap from target", 0, 300, 80, function(v) return tostring(v) .. " units" end)
ui.tele_max_distance = group_tele:Slider("Max throw distance override", 0, 600, 0, function(v)
    if v == 0 then
        return "Default"
    end
    return tostring(v) .. " units"
end)

ui.visual_debug = group_visual:Switch("Visual Debug", false, "\u{f06e}")
ui.radius_color = group_visual:ColorPicker("In Range Color", Color(0, 255, 0))
ui.out_of_range_color = group_visual:ColorPicker("Out of Range Color", Color(255, 0, 0))

ui.enemy_selector = group_targets:MultiSelect("Target Enemies", {}, false)
ui.enemy_selector:DragAllowed(true)

local auto_mode_active = false
local last_key_state = false

local state = {
    stage = "idle",
    pending_plan = nil,
    blink_time = 0,
    next_allowed_time = 0,
    refresher_used = false,
    particle = nil,
    last_radius = 0,
    combo_mode = false,
    combo_queue = {},
    combo_index = 1,
    combo_key_down = false,
    combo_min_targets = 1,
    editor_display = HERO_DISPLAY_LIST[1],
    editor_hero = HERO_DISPLAY_LIST[1] and HERO_DISPLAY_TO_INTERNAL[HERO_DISPLAY_LIST[1]] or nil,
    editor_lookup = {},
}

local function combos_enabled()
    return ui.combo_enable:Get()
end

local function sorted_abilities(set)
    local entries = {}
    if type(set) ~= "table" then
        return entries
    end
    for ability in pairs(set) do
        table.insert(entries, ability)
    end
    table.sort(entries, function(a, b)
        return ability_friendly(a) < ability_friendly(b)
    end)
    return entries
end

local function ability_allowed(name)
    if not combos_enabled() then
        return true
    end
    local owner = ABILITY_TO_HERO[name]
    local settings = owner and HERO_SETTINGS[owner]
    if settings then
        if settings.enabled[name] == false then
            return false
        end
        return true
    end
    return ui.combo_allow_unmapped:Get()
end

local function collect_ready_stolen(hero)
    local hero_buckets = {}
    local leftover = {}
    for slot = 0, MAX_ABILITY_SLOTS - 1 do
        local ability = NPC.GetAbilityByIndex(hero, slot)
        if ability and Ability.IsStolen(ability) then
            local name = Ability.GetName(ability)
            if name and ability_is_ready(hero, ability) and ability_allowed(name) then
                local owner = ABILITY_TO_HERO[name]
                if owner then
                    local bucket = hero_buckets[owner]
                    if not bucket then
                        bucket = {}
                        hero_buckets[owner] = bucket
                    end
                    bucket[name] = true
                else
                    leftover[name] = true
                end
            end
        end
    end
    return hero_buckets, leftover
end

local function build_priority_list(hero_buckets, leftover)
    local ordered = {}
    for _, hero_name in ipairs(HERO_PRIORITY) do
        local bucket = hero_buckets[hero_name]
        if bucket then
            local settings = HERO_SETTINGS[hero_name]
            if settings then
                for _, ability in ipairs(settings.order) do
                    if bucket[ability] then
                        table.insert(ordered, ability)
                        bucket[ability] = nil
                    end
                end
            end
            for _, ability in ipairs(sorted_abilities(bucket)) do
                table.insert(ordered, ability)
            end
        end
    end
    for _, ability in ipairs(sorted_abilities(leftover)) do
        table.insert(ordered, ability)
    end
    return ordered
end

local function update_combo_editor()
    local display = state.editor_display
    local hero_name = display and HERO_DISPLAY_TO_INTERNAL[display]
    state.editor_hero = hero_name
    if not hero_name or not HERO_SETTINGS[hero_name] then
        state.editor_lookup = {}
        ui.combo_multiselect:Update({}, false, false)
        ui.combo_multiselect:Disabled(true)
        return
    end

    ui.combo_multiselect:Disabled(false)
    local settings = HERO_SETTINGS[hero_name]
    local used_labels = {}
    local lookup = {}
    local items = {}
    for _, ability in ipairs(settings.order) do
        local info = SPELLS[ability]
        if info then
            local label = info.friendly
            if used_labels[label] then
                local suffix = 2
                local candidate = string.format("%s (%d)", label, suffix)
                while used_labels[candidate] do
                    suffix = suffix + 1
                    candidate = string.format("%s (%d)", label, suffix)
                end
                label = candidate
            end
            used_labels[label] = true
            lookup[label] = ability
            table.insert(items, { label, ability_icon(ability), settings.enabled[ability] ~= false })
        end
    end

    state.editor_lookup = lookup
    ui.combo_multiselect:Update(items, true, false)
    ui.combo_multiselect:DragAllowed(true)
end

local function capture_combo_editor()
    local hero_name = state.editor_hero
    local settings = hero_name and HERO_SETTINGS[hero_name]
    if not settings then
        return
    end

    local lookup = state.editor_lookup or {}
    local order_labels = ui.combo_multiselect:List()
    if order_labels and #order_labels > 0 then
        local new_order = {}
        for _, label in ipairs(order_labels) do
            local ability = lookup[label]
            if ability then
                table.insert(new_order, ability)
            end
        end
        if #new_order > 0 then
            settings.order = new_order
            rebuild_order_map(hero_name)
        end
    end

    for label, ability in pairs(lookup) do
        local enabled = ui.combo_multiselect:Get(label)
        if enabled ~= nil then
            settings.enabled[ability] = enabled
        end
    end
end

ui.combo_multiselect:SetCallback(function()
    capture_combo_editor()
end)

ui.combo_edit_hero:SetCallback(function(widget)
    if #HERO_DISPLAY_LIST == 0 then
        return
    end
    capture_combo_editor()
    local index = widget:Get() + 1
    if index < 1 or index > #HERO_DISPLAY_LIST then
        index = 1
    end
    state.editor_display = HERO_DISPLAY_LIST[index]
    update_combo_editor()
end, true)

if state.editor_display then
    update_combo_editor()
end

local PANEL = {
    X = 52,
    Y = 108,
    WIDTH = 140,
    HEIGHT = 32,
    RADIUS = 8,
    font = nil,
}

local PANEL_COLORS = {
    bg = Color(15, 15, 15, 210),
    text_off = Color(231, 76, 60, 255),
    text_on = Color(52, 152, 219, 255),
    text_auto = Color(46, 204, 113, 255),
    shadow = Color(0, 0, 0, 140),
}

local function ensure_font()
    if not PANEL.font then
        PANEL.font = Render.LoadFont("Tahoma", Enum.FontCreate.FONTFLAG_OUTLINE + Enum.FontCreate.FONTFLAG_ANTIALIAS)
    end
end

local function draw_panel()
    if not ui.enable:Get() then
        return
    end
    local hero = Heroes.GetLocal()
    if not hero or Entity.GetUnitName(hero) ~= RUBICK_NAME or not Entity.IsAlive(hero) then
        return
    end

    ensure_font()
    local text
    local color
    if ui.mode:Get() == 1 then
        text = "Rubick: Auto"
        color = PANEL_COLORS.text_auto
    else
        if auto_mode_active then
            text = "Rubick: On"
            color = PANEL_COLORS.text_on
        else
            text = "Rubick: Off"
            color = PANEL_COLORS.text_off
        end
    end

    local p1 = Vec2(PANEL.X, PANEL.Y)
    local p2 = Vec2(PANEL.X + PANEL.WIDTH, PANEL.Y + PANEL.HEIGHT)
    Render.Blur(p1, p2, 8, 1.0, PANEL.RADIUS)
    Render.FilledRect(p1, p2, PANEL_COLORS.bg, PANEL.RADIUS)

    local size = Render.TextSize(PANEL.font, 16, text)
    local tx = PANEL.X + (PANEL.WIDTH - size.x) / 2
    local ty = PANEL.Y + (PANEL.HEIGHT - size.y) / 2
    Render.Text(PANEL.font, 16, text, Vec2(tx + 1, ty + 1), PANEL_COLORS.shadow)
    Render.Text(PANEL.font, 16, text, Vec2(tx, ty), color)
end

local function reset_state()
    if state.particle then
        Particle.Destroy(state.particle)
        state.particle = nil
    end
    state.stage = "idle"
    state.pending_plan = nil
    state.blink_time = 0
    state.next_allowed_time = 0
    state.refresher_used = false
    state.last_radius = 0
    state.combo_mode = false
    state.combo_queue = {}
    state.combo_index = 1
    state.combo_key_down = false
    state.combo_min_targets = 1
end

local function get_local_rubick()
    if not Engine.IsInGame() then
        return nil
    end
    local hero = Heroes.GetLocal()
    if not hero or not Entity.IsAlive(hero) then
        return nil
    end
    if Entity.GetUnitName(hero) ~= RUBICK_NAME then
        return nil
    end
    return hero
end

local function count_alive_enemies(hero)
    local alive = 0
    for _, enemy in ipairs(Heroes.GetAll()) do
        if enemy ~= hero and not Entity.IsSameTeam(hero, enemy) and Entity.IsAlive(enemy) and not NPC.IsIllusion(enemy) then
            alive = alive + 1
        end
    end
    return alive
end

local function adjusted_min_targets(hero)
    local min_required = ui.min_targets:Get()
    if not ui.adjust_for_dead:Get() then
        return min_required
    end
    local alive = count_alive_enemies(hero)
    return clamp(min_required, 1, math.max(alive, 1))
end

local function get_enemy_priority(hero)
    local items = ui.enemy_selector:List()
    if not items then
        return {}
    end
    local enabled = {}
    for _, name in ipairs(items) do
        if ui.enemy_selector:Get(name) then
            table.insert(enabled, name)
        end
    end
    local map = {}
    for _, enemy in ipairs(Heroes.GetAll()) do
        if enemy ~= hero and not Entity.IsSameTeam(hero, enemy) and not NPC.IsIllusion(enemy) and Entity.IsAlive(enemy) then
            map[Entity.GetUnitName(enemy)] = enemy
        end
    end
    local prioritized = {}
    for _, name in ipairs(enabled) do
        local hero_unit = map[name]
        if hero_unit then
            table.insert(prioritized, hero_unit)
        end
    end
    return prioritized
end

local function refresh_enemy_selector(hero)
    local current = ui.enemy_selector:List()
    if current and #current > 0 then
        return
    end
    local entries = {}
    for _, enemy in ipairs(Heroes.GetAll()) do
        if enemy ~= hero and not Entity.IsSameTeam(hero, enemy) and not NPC.IsIllusion(enemy) then
            local unit_name = Entity.GetUnitName(enemy)
            table.insert(entries, { unit_name, "panorama/images/heroes/icons/" .. unit_name .. "_png.vtex_c", false })
        end
    end
    if #entries > 0 then
        ui.enemy_selector:Update(entries, false, false)
    end
end

local function get_blink(hero)
    for _, name in ipairs(BLINK_ITEMS) do
        local item = NPC.GetItem(hero, name, true)
        if item and Ability.IsReady(item) then
            return item
        end
    end
    return nil
end

local function find_best_cluster(heroes, radius, min_targets)
    if #heroes == 0 then
        return nil, 0
    end
    local best_position = nil
    local best_count = 0
    for i = 1, #heroes do
        local pos_i = Entity.GetAbsOrigin(heroes[i])
        local count = 0
        for j = 1, #heroes do
            local pos_j = Entity.GetAbsOrigin(heroes[j])
            if distance(pos_i, pos_j) <= radius then
                count = count + 1
            end
        end
        if count > best_count or (count == best_count and best_position and distance(pos_i, best_position) < 50) then
            best_position = pos_i
            best_count = count
        end
    end
    if best_count < min_targets then
        return nil, best_count
    end
    return best_position, best_count
end

local function plan_no_target(hero, ability, info, min_targets)
    local radius = get_effect_radius(ability, info)
    local prioritized = get_enemy_priority(hero)
    if #prioritized > 0 then
        local best_position, count = find_best_cluster(prioritized, radius, clamp(min_targets, 1, #prioritized))
        if best_position then
            return {
                ability = ability,
                type = "no_target",
                cast_position = best_position,
                radius = radius,
                range = radius,
                enemy_count = count,
            }
        end
    end

    local enemies = {}
    for _, enemy in ipairs(Heroes.GetAll()) do
        if enemy ~= hero and not Entity.IsSameTeam(hero, enemy) and Entity.IsAlive(enemy) and not NPC.IsIllusion(enemy) and not Entity.IsDormant(enemy) then
            table.insert(enemies, enemy)
        end
    end
    local best_position, count = find_best_cluster(enemies, radius, min_targets)
    if not best_position then
        return nil
    end
    return {
        ability = ability,
        type = "no_target",
        cast_position = best_position,
        radius = radius,
        range = radius,
        enemy_count = count,
    }
end

local function plan_point(hero, ability, info, min_targets)
    local radius = get_effect_radius(ability, info)
    local range = get_cast_range(ability, info)
    local prioritized = get_enemy_priority(hero)
    if #prioritized > 0 then
        local best_position, count = find_best_cluster(prioritized, radius, clamp(min_targets, 1, #prioritized))
        if best_position and distance(Entity.GetAbsOrigin(hero), best_position) <= range then
            return {
                ability = ability,
                type = "point",
                cast_position = best_position,
                radius = radius,
                range = range,
                enemy_count = count,
            }
        end
    end

    local enemies = {}
    for _, enemy in ipairs(Heroes.GetAll()) do
        if enemy ~= hero and not Entity.IsSameTeam(hero, enemy) and Entity.IsAlive(enemy) and not NPC.IsIllusion(enemy) and not Entity.IsDormant(enemy) then
            table.insert(enemies, enemy)
        end
    end
    local best_position, count = find_best_cluster(enemies, radius, min_targets)
    if not best_position or distance(Entity.GetAbsOrigin(hero), best_position) > range then
        return nil
    end
    return {
        ability = ability,
        type = "point",
        cast_position = best_position,
        radius = radius,
        range = range,
        enemy_count = count,
    }
end

local function plan_unit(hero, ability, info)
    if not ability_targets_enemies(info) then
        return nil
    end
    local range = get_cast_range(ability, info)
    local prioritized = get_enemy_priority(hero)
    local origin = Entity.GetAbsOrigin(hero)
    local best_target
    local best_distance = math.huge

    local function consider(enemy)
        if not enemy or not Entity.IsAlive(enemy) or NPC.IsIllusion(enemy) or Entity.IsDormant(enemy) then
            return
        end
        local dist = distance(origin, Entity.GetAbsOrigin(enemy))
        if dist <= range and dist < best_distance then
            best_target = enemy
            best_distance = dist
        end
    end

    for _, enemy in ipairs(prioritized) do
        consider(enemy)
    end
    if not best_target then
        for _, enemy in ipairs(Heroes.GetAll()) do
            if enemy ~= hero and not Entity.IsSameTeam(hero, enemy) then
                consider(enemy)
            end
        end
    end

    if not best_target then
        return nil
    end

    return {
        ability = ability,
        type = "unit",
        target = best_target,
        cast_position = Entity.GetAbsOrigin(best_target),
        range = range,
        radius = 0,
        enemy_count = 1,
    }
end

local function ability_is_ready(hero, ability)
    if not ability then
        return nil
    end
    if Ability.IsHidden and Ability.IsHidden(ability) then
        return nil
    end
    if Ability.GetLevel(ability) and Ability.GetLevel(ability) <= 0 then
        return nil
    end
    if not Ability.IsCastable(ability, NPC.GetMana(hero)) then
        return nil
    end
    return ability
end

local function build_plan(hero, ability_name, min_targets)
    if BASE_RUBICK_ABILITIES[ability_name] then
        return nil
    end
    local ability = NPC.GetAbility(hero, ability_name)
    if not ability or not Ability.IsStolen(ability) then
        return nil
    end
    if not ability_is_ready(hero, ability) then
        return nil
    end
    if not Ability.IsStolen(ability) then
        return nil
    end

    local info = SPELLS[ability_name]
    if not info then
        return nil
    end

    if info.type ~= "no_target" and not ability_targets_enemies(info) then
        return nil
    end

    local plan
    if info.type == "no_target" then
        plan = plan_no_target(hero, ability, info, min_targets)
    elseif info.type == "point" then
        plan = plan_point(hero, ability, info, min_targets)
    elseif info.type == "unit" then
        plan = plan_unit(hero, ability, info)
    end

    if plan then
        plan.tech = ability_name
    end
    return plan
end

local function start_combo(hero)
    if combos_enabled() then
        capture_combo_editor()
    end

    local hero_buckets, leftover = collect_ready_stolen(hero)
    local ordered = build_priority_list(hero_buckets, leftover)
    if #ordered == 0 then
        return false
    end

    local queue = {}
    local min_targets = adjusted_min_targets(hero)
    for _, ability_name in ipairs(ordered) do
        local plan = build_plan(hero, ability_name, min_targets)
        if valid_plan(plan) then
            table.insert(queue, ability_name)
        end
    end

    if #queue == 0 then
        return false
    end

    state.combo_mode = true
    state.combo_queue = queue
    state.combo_index = 1
    state.combo_min_targets = min_targets
    state.pending_plan = nil
    state.stage = "idle"
    state.refresher_used = false
    return true
end

local function needs_blink(hero, plan)
    if not plan then
        return false
    end
    local hero_pos = Entity.GetAbsOrigin(hero)
    local ability = plan.ability
    local range = plan.range or Ability.GetCastRange(ability) or 0
    local dist = distance(hero_pos, plan.cast_position)

    if plan.type == "no_target" then
        local threshold = math.max(plan.radius - 120, plan.radius * 0.6)
        return dist > threshold
    elseif plan.type == "point" then
        if range <= 0 then
            range = 900
        end
        return dist > (range - 120)
    elseif plan.type == "unit" then
        if range <= 0 then
            range = 350
        end
        return dist > range
    end
    return false
end

local function blink_position(hero, plan)
    local hero_pos = Entity.GetAbsOrigin(hero)
    local target_pos = plan.cast_position
    local direction = vec_normalize(vec_sub(target_pos, hero_pos))
    local offset = ui.blink_offset:Get()

    if plan.type == "no_target" then
        return vec_add(target_pos, vec_scale(direction, offset))
    end

    local range = plan.range or Ability.GetCastRange(plan.ability)
    if not range or range <= 0 then
        range = plan.radius + 150
    end
    local desired = vec_add(target_pos, vec_scale(direction, -(range - 75) + offset))
    return desired
end

local function draw_radius(plan, hero)
    if not ui.visual_debug:Get() then
        if state.particle then
            Particle.Destroy(state.particle)
            state.particle = nil
        end
        return
    end

    local radius = plan and plan.radius or 0
    local position = plan and plan.cast_position
    if not position or radius <= 0 then
        if state.particle then
            Particle.Destroy(state.particle)
            state.particle = nil
        end
        return
    end

    if not state.particle or state.last_radius ~= radius then
        if state.particle then
            Particle.Destroy(state.particle)
        end
        state.particle = Particle.Create("particles/ui_mouseactions/drag_selected_ring.vpcf", Enum.ParticleAttachment.PATTACH_CUSTOMORIGIN)
        state.last_radius = radius
    end

    local in_range = not needs_blink(hero, plan)
    local color = in_range and ui.radius_color:Get() or ui.out_of_range_color:Get()
    Particle.SetControlPoint(state.particle, 0, Vector(position.x, position.y, position.z))
    Particle.SetControlPoint(state.particle, 1, Vector(color.r, color.g, color.b))
    Particle.SetControlPoint(state.particle, 7, Vector(radius, 255, 255))
end

local function cast_plan(hero, plan)
    if not plan then
        return false
    end

    if plan.type == "no_target" then
        Ability.CastNoTarget(plan.ability)
        return true
    elseif plan.type == "point" then
        Ability.CastPosition(plan.ability, plan.cast_position)
        return true
    elseif plan.type == "unit" then
        Ability.CastTarget(plan.ability, plan.target)
        return true
    end

    return false
end

local function get_refresher(hero)
    if not ui.use_refresher:Get() then
        return nil
    end
    local item = NPC.GetItem(hero, "item_refresher", true)
    if item and Ability.IsReady(item) then
        return item
    end
    return nil
end

local function try_use_refresher(hero)
    if state.refresher_used then
        return false
    end
    if NPC.IsChannellingAbility(hero) then
        return false
    end
    local refresher = get_refresher(hero)
    if not refresher then
        return false
    end
    Ability.CastNoTarget(refresher)
    state.refresher_used = true
    state.next_allowed_time = get_time() + 0.2
    return true
end

local function handle_toggle()
    if ui.mode:Get() == 1 then
        auto_mode_active = true
        return
    end
    local key_down = ui.toggle_key:IsDown()
    if key_down and not last_key_state then
        auto_mode_active = not auto_mode_active
    end
    last_key_state = key_down
end

local function valid_plan(plan)
    if not plan then
        return false
    end
    if plan.type == "unit" and (not plan.target or not Entity.IsAlive(plan.target)) then
        return false
    end
    return true
end

local function handle_auto_cast(hero)
    local now = get_time()
    local combo_active = state.combo_mode
    if combos_enabled() then
        capture_combo_editor()
    end
    if not combo_active and not auto_mode_active then
        reset_state()
        return
    end
    if now < state.next_allowed_time then
        return
    end

    if state.stage == "wait_cast" then
        if now - state.blink_time >= 0.05 then
            local plan = state.pending_plan
            if plan then
                local refreshed = build_plan(hero, plan.tech, adjusted_min_targets(hero))
                if valid_plan(refreshed) then
                    plan = refreshed
                    state.pending_plan = plan
                end
            end
            if plan and cast_plan(hero, plan) then
                state.stage = "post_cast"
                state.next_allowed_time = now + 0.2
                draw_radius(nil, hero)
                return
            end
            state.stage = "idle"
            state.pending_plan = nil
        end
        return
    elseif state.stage == "post_cast" then
        if now >= state.next_allowed_time then
            if try_use_refresher(hero) then
                state.stage = "idle"
                state.pending_plan = nil
                return
            end
            state.stage = "idle"
            state.pending_plan = nil
        end
        return
    end

    if NPC.IsSilenced(hero) or NPC.IsStunned(hero) or NPC.IsChannellingAbility(hero) then
        return
    end

    local chosen = nil
    local combo_min_targets = state.combo_min_targets

    if combo_active then
        while state.combo_index <= #state.combo_queue do
            local tech = state.combo_queue[state.combo_index]
            state.combo_index = state.combo_index + 1
            local plan = build_plan(hero, tech, combo_min_targets)
            if valid_plan(plan) then
                local info = SPELLS[tech]
                plan.name = info and info.friendly or tech
                plan.tech = tech
                plan.needs_blink = needs_blink(hero, plan)
                chosen = plan
                break
            end
        end
        if not chosen then
            state.combo_mode = false
            state.combo_queue = {}
            state.combo_index = 1
            state.combo_min_targets = 1
            combo_active = false
        end
    end

    if not chosen then
        if not auto_mode_active then
            draw_radius(nil, hero)
            return
        end
        local min_targets = adjusted_min_targets(hero)
        local available_plans = {}
        local hero_buckets, leftover = collect_ready_stolen(hero)
        local ordered = build_priority_list(hero_buckets, leftover)
        for _, ability_name in ipairs(ordered) do
            local plan = build_plan(hero, ability_name, min_targets)
            if valid_plan(plan) then
                local info = SPELLS[ability_name]
                plan.name = info and info.friendly or ability_name
                plan.tech = ability_name
                plan.needs_blink = needs_blink(hero, plan)
                table.insert(available_plans, plan)
            end
        end

        if #available_plans == 0 then
            draw_radius(nil, hero)
            return
        end

        for _, plan in ipairs(available_plans) do
            if not plan.needs_blink then
                chosen = plan
                break
            end
        end
        if not chosen then
            chosen = available_plans[1]
        end
    end

    draw_radius(chosen, hero)

    state.refresher_used = false

    if chosen.needs_blink then
        local blink = get_blink(hero)
        if not blink then
            return
        end
        local blink_pos = blink_position(hero, chosen)
        Ability.CastPosition(blink, Vector(blink_pos.x, blink_pos.y, blink_pos.z))
        state.stage = "wait_cast"
        state.pending_plan = chosen
        state.blink_time = now
        state.next_allowed_time = now + 0.05
    else
        if cast_plan(hero, chosen) then
            state.stage = "post_cast"
            state.next_allowed_time = now + 0.2
            state.pending_plan = nil
            draw_radius(nil, hero)
        end
    end
end

local function find_nearest_allied_tower(hero, position)
    local best = nil
    local best_distance = math.huge
    for i = 0, Towers.Count() - 1 do
        local tower = Towers.Get(i)
        if tower and Entity.IsAlive(tower) and Entity.IsSameTeam(hero, tower) then
            local dist = distance(position, Entity.GetAbsOrigin(tower))
            if dist < best_distance then
                best = tower
                best_distance = dist
            end
        end
    end
    return best
end

local function find_nearest_ally(hero, position)
    local best = nil
    local best_distance = math.huge
    for _, ally in ipairs(Heroes.GetAll()) do
        if ally ~= hero and Entity.IsSameTeam(hero, ally) and Entity.IsAlive(ally) and not NPC.IsIllusion(ally) then
            local dist = distance(position, Entity.GetAbsOrigin(ally))
            if dist < best_distance then
                best = ally
                best_distance = dist
            end
        end
    end
    return best
end

local function handle_telekinesis(hero)
    if not ui.tele_enable:Get() then
        return
    end
    local land = NPC.GetAbility(hero, TELEKINESIS_LAND_NAME)
    if not land or not Ability.IsReady(land) then
        return
    end

    local lifted_target
    for _, enemy in ipairs(Heroes.GetAll()) do
        if enemy ~= hero and not Entity.IsSameTeam(hero, enemy) and Entity.IsAlive(enemy) and NPC.HasModifier(enemy, TELEKINESIS_MODIFIER) then
            lifted_target = enemy
            break
        end
    end

    if not lifted_target then
        return
    end

    local victim_pos = Entity.GetAbsOrigin(lifted_target)
    local anchor
    local preference = ui.tele_preference:Get()

    if preference == 0 then
        local tower = find_nearest_allied_tower(hero, victim_pos)
        if tower then
            anchor = Entity.GetAbsOrigin(tower)
        end
    elseif preference == 1 then
        local ally = find_nearest_ally(hero, victim_pos)
        if ally then
            anchor = Entity.GetAbsOrigin(ally)
        end
    end

    if not anchor then
        anchor = Entity.GetAbsOrigin(hero)
    end

    local direction = vec_normalize(vec_sub(anchor, victim_pos))
    if direction.x == 0 and direction.y == 0 then
        direction = vec_normalize(vec_sub(Entity.GetAbsOrigin(hero), victim_pos))
    end
    if direction.x == 0 and direction.y == 0 then
        direction = vec3(1, 0, 0)
    end

    local gap = ui.tele_gap:Get()
    local anchor_distance = vec_length2d(vec_sub(anchor, victim_pos))
    local desired_distance = anchor_distance - gap
    if desired_distance < gap then
        desired_distance = anchor_distance - math.min(20, anchor_distance * 0.3)
    end

    local max_dist = ui.tele_max_distance:Get()
    if max_dist == 0 then
        local tele = NPC.GetAbility(hero, TELEKINESIS_NAME)
        if tele then
            max_dist = Ability.GetLevelSpecialValueFor(tele, "max_land_distance") or 375
        end
    end
    if max_dist <= 0 then
        max_dist = 375
    end

    desired_distance = clamp(desired_distance, math.min(gap, anchor_distance), max_dist - 20)
    if desired_distance <= 0 then
        desired_distance = math.min(math.max(anchor_distance * 0.5, gap * 0.5), max_dist * 0.5)
    end
    local drop_position = vec_add(victim_pos, vec_scale(direction, desired_distance))

    Ability.CastPosition(land, Vector(drop_position.x, drop_position.y, drop_position.z))
end

function script.OnUpdate()
    local hero = get_local_rubick()
    if not hero then
        reset_state()
        return
    end

    ui.toggle_key:Visible(ui.mode:Get() == 0)
    refresh_enemy_selector(hero)
    handle_toggle()

    if not ui.enable:Get() then
        reset_state()
        return
    end

    local combo_down = ui.combo_key:IsDown()
    if combo_down and not state.combo_key_down then
        start_combo(hero)
    end
    state.combo_key_down = combo_down

    handle_auto_cast(hero)
    handle_telekinesis(hero)
end

function script.OnDraw()
    draw_panel()
end

function script.OnGameEnd()
    reset_state()
    auto_mode_active = false
    last_key_state = false
end

return script

