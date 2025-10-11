---@diagnostic disable: undefined-global, param-type-mismatch

local rubick = {}

--#region Helpers & constants
local function get_script_dir()
    local info = debug.getinfo(1, "S")
    if not info or not info.source then
        return ""
    end
    local source = info.source
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    local last_slash = source:match(".*[\\/]")
    if not last_slash then
        return ""
    end
    return last_slash
end

local SCRIPT_DIR = get_script_dir()
if SCRIPT_DIR ~= "" and not SCRIPT_DIR:match("[\\/]$") then
    SCRIPT_DIR = SCRIPT_DIR .. "/"
end

local function join_path(relative)
    if relative:match("^%a:[\\/]") or relative:sub(1, 1) == "/" then
        return relative
    end
    return (SCRIPT_DIR or "") .. relative
end

local JSON
local ok, json_lib = pcall(dofile, join_path("assets/JSON.lua"))
if ok then
    JSON = json_lib
else
    print("[Rubick Spell Stealer] Failed to load JSON library: " .. tostring(json_lib))
end

local ability_behavior_flags = {
    DOTA_ABILITY_BEHAVIOR_HIDDEN = 1,
    DOTA_ABILITY_BEHAVIOR_PASSIVE = 2,
    DOTA_ABILITY_BEHAVIOR_NO_TARGET = 4,
    DOTA_ABILITY_BEHAVIOR_UNIT_TARGET = 8,
    DOTA_ABILITY_BEHAVIOR_POINT = 16,
    DOTA_ABILITY_BEHAVIOR_AOE = 32,
    DOTA_ABILITY_BEHAVIOR_NOT_LEARNABLE = 64,
    DOTA_ABILITY_BEHAVIOR_CHANNELLED = 128,
    DOTA_ABILITY_BEHAVIOR_ITEM = 256,
    DOTA_ABILITY_BEHAVIOR_TOGGLE = 512,
    DOTA_ABILITY_BEHAVIOR_DIRECTIONAL = 1024,
    DOTA_ABILITY_BEHAVIOR_IMMEDIATE = 2048,
    DOTA_ABILITY_BEHAVIOR_AUTOCAST = 4096,
    DOTA_ABILITY_BEHAVIOR_OPTIONAL_UNIT_TARGET = 8192,
    DOTA_ABILITY_BEHAVIOR_OPTIONAL_POINT = 16384,
    DOTA_ABILITY_BEHAVIOR_OPTIONAL_NO_TARGET = 32768,
    DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING = 1073741824,
}

local target_team_tokens = {
    DOTA_UNIT_TARGET_TEAM_NONE = true,
    DOTA_UNIT_TARGET_TEAM_FRIENDLY = true,
    DOTA_UNIT_TARGET_TEAM_ENEMY = true,
    DOTA_UNIT_TARGET_TEAM_BOTH = true,
    DOTA_UNIT_TARGET_TEAM_CUSTOM = true,
}

local target_type_base_flags = {
    DOTA_UNIT_TARGET_HERO = 1,
    DOTA_UNIT_TARGET_CREEP = 2,
    DOTA_UNIT_TARGET_BUILDING = 4,
    DOTA_UNIT_TARGET_COURIER = 16,
    DOTA_UNIT_TARGET_OTHER = 32,
    DOTA_UNIT_TARGET_TREE = 64,
    DOTA_UNIT_TARGET_CUSTOM = 128,
    DOTA_UNIT_TARGET_SELF = 256,
}

local function trim(str)
    return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_number_from_value(value)
    if type(value) == "number" then
        return value
    end
    if type(value) ~= "string" then
        return nil
    end
    local max_value = nil
    for token in value:gmatch("%-?%d+%.?%d*") do
        local numeric = tonumber(token)
        if numeric then
            if not max_value or numeric > max_value then
                max_value = numeric
            end
        end
    end
    return max_value
end

local function extract_radius(ability_kv)
    local radius = parse_number_from_value(ability_kv.AbilityAOERadius)
    if not radius then
        radius = parse_number_from_value(ability_kv.AbilityRadius)
    end

    local function consider(value)
        local parsed = parse_number_from_value(value)
        if parsed and parsed > 0 then
            if not radius or parsed > radius then
                radius = parsed
            end
        end
    end

    if type(ability_kv.AbilityValues) == "table" then
        for key, data in pairs(ability_kv.AbilityValues) do
            if type(key) == "string" and key:lower():find("radius") then
                if type(data) == "table" then
                    for _, value in pairs(data) do
                        consider(value)
                    end
                else
                    consider(data)
                end
            elseif type(key) == "string" and key:lower():find("aoe") then
                if type(data) == "table" then
                    for _, value in pairs(data) do
                        consider(value)
                    end
                else
                    consider(data)
                end
            end
        end
    end

    if type(ability_kv.AbilitySpecial) == "table" then
        for _, entry in pairs(ability_kv.AbilitySpecial) do
            if type(entry) == "table" then
                for key, value in pairs(entry) do
                    if key ~= "var_type" and type(key) == "string" then
                        local lower = key:lower()
                        if lower:find("radius") or lower:find("aoe") then
                            consider(value)
                        end
                    end
                end
            end
        end
    end

    return radius
end

local function split_tokens(value)
    local tokens = {}
    if not value then
        return tokens
    end

    local value_type = type(value)
    if value_type == "string" then
        for token in value:gmatch("[^|]+") do
            tokens[trim(token)] = true
        end
    elseif value_type == "table" then
        for _, token in pairs(value) do
            if type(token) == "string" then
                tokens[trim(token)] = true
            end
        end
    elseif value_type == "number" then
        -- handled later by runtime decoding
    end
    return tokens
end

local function bit_flag_test(value, flag)
    if not value or not flag or flag == 0 then
        return false
    end
    return (value % (flag * 2)) >= flag
end

local function decode_behavior_value(value)
    local tokens = {}
    if not value then
        return tokens
    end
    for name, flag in pairs(ability_behavior_flags) do
        if flag and bit_flag_test(value, flag) then
            tokens[name] = true
        end
    end
    return tokens
end

local function decode_target_team(value)
    local tokens = {}
    if not value then
        return tokens
    end
    if value == 0 then
        tokens.DOTA_UNIT_TARGET_TEAM_NONE = true
    end
    if value == 1 then
        tokens.DOTA_UNIT_TARGET_TEAM_FRIENDLY = true
    end
    if value == 2 then
        tokens.DOTA_UNIT_TARGET_TEAM_ENEMY = true
    end
    if value == 3 then
        tokens.DOTA_UNIT_TARGET_TEAM_BOTH = true
        tokens.DOTA_UNIT_TARGET_TEAM_FRIENDLY = true
        tokens.DOTA_UNIT_TARGET_TEAM_ENEMY = true
    end
    if value == 4 then
        tokens.DOTA_UNIT_TARGET_TEAM_CUSTOM = true
    end
    return tokens
end

local function decode_target_type(value)
    local tokens = {}
    if not value then
        return tokens
    end
    if value == 0 then
        tokens.DOTA_UNIT_TARGET_NONE = true
        return tokens
    end
    for name, flag in pairs(target_type_base_flags) do
        if bit_flag_test(value, flag) then
            tokens[name] = true
        end
    end
    if bit_flag_test(value, target_type_base_flags.DOTA_UNIT_TARGET_HERO) and bit_flag_test(value, target_type_base_flags.DOTA_UNIT_TARGET_CREEP) then
        tokens.DOTA_UNIT_TARGET_HEROES_AND_CREEPS = true
    end
    if value == 18 then
        tokens.DOTA_UNIT_TARGET_BASIC = true
    end
    if value == 55 then
        tokens.DOTA_UNIT_TARGET_ALL = true
    end
    if value == 19 then
        tokens.DOTA_UNIT_TARGET_HEROES_AND_CREEPS = true
    end
    return tokens
end

local function merge_sets(target, source)
    target = target or {}
    if source then
        for key in pairs(source) do
            target[key] = true
        end
    end
    return target
end

local function prettify_ability_name(name)
    if not name then
        return "Unknown"
    end
    local cleaned = name:gsub("^ability_", "")
    cleaned = cleaned:gsub("_", " ")
    cleaned = cleaned:gsub("(%a)(%w*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
    return cleaned
end

local function prettify_hero_name(name)
    if not name then
        return "Unknown"
    end
    local cleaned = name:gsub("^npc_dota_hero_", "")
    cleaned = cleaned:gsub("_", " ")
    cleaned = cleaned:gsub("(%a)(%w*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
    return cleaned
end

local function load_json(relative_path)
    if not JSON then
        return nil
    end
    local file_path = join_path(relative_path)
    local file = io.open(file_path, "r")
    if not file then
        print("[Rubick Spell Stealer] Unable to open file: " .. tostring(file_path))
        return nil
    end
    local content = file:read("*a")
    file:close()
    local success, result = pcall(function()
        return JSON:decode(content)
    end)
    if not success then
        print("[Rubick Spell Stealer] Failed to decode JSON: " .. tostring(result))
        return nil
    end
    return result
end

--#endregion

--#region Metadata assembly
local ability_metadata = {}
local ability_switches = {}
local hero_display_names = {}
local hero_ability_order = {}

local function build_ability_metadata()
    local ability_data = load_json("assets/data/npc_abilities.json")
    if ability_data and type(ability_data.DOTAAbilities) == "table" then
        for ability_name, ability_kv in pairs(ability_data.DOTAAbilities) do
            if ability_name ~= "Version" and type(ability_kv) == "table" then
                local behavior_tokens = split_tokens(ability_kv.AbilityBehavior)
                local target_team = split_tokens(ability_kv.AbilityUnitTargetTeam)
                local target_type = split_tokens(ability_kv.AbilityUnitTargetType)
                local cast_range = parse_number_from_value(ability_kv.AbilityCastRange)
                local radius = extract_radius(ability_kv)
                local spell_immunity = ability_kv.SpellImmunityType

                ability_metadata[ability_name] = {
                    name = ability_name,
                    display = prettify_ability_name(ability_name),
                    behavior_tokens = behavior_tokens,
                    behavior_value = nil,
                    target_team_tokens = target_team,
                    target_type_tokens = target_type,
                    cast_range = cast_range,
                    radius = radius,
                    immunity = spell_immunity,
                    is_toggle = behavior_tokens.DOTA_ABILITY_BEHAVIOR_TOGGLE or false,
                    is_passive = behavior_tokens.DOTA_ABILITY_BEHAVIOR_PASSIVE or false,
                    owner = nil,
                }
            end
        end
    end

    local hero_data = load_json("assets/data/npc_heroes.json")
    if not hero_data or type(hero_data.DOTAHeroes) ~= "table" then
        return
    end

    for hero_name, hero_kv in pairs(hero_data.DOTAHeroes) do
        if hero_name ~= "Version" and type(hero_kv) == "table" and hero_name:find("npc_dota_hero_") then
            local display = hero_kv.workshop_guide_name or hero_kv.override_hero or hero_kv.BaseClass or hero_name
            hero_display_names[hero_name] = prettify_hero_name(display)
            local hero_abilities = {}
            for index = 1, 30 do
                local key = "Ability" .. index
                local ability_name = hero_kv[key]
                if ability_name and ability_name ~= "" and ability_name ~= "generic_hidden" then
                    if not ability_name:find("^special_bonus_") and ability_name ~= "attribute_bonus" and ability_name ~= "default_attack" then
                        local meta = ability_metadata[ability_name]
                        if meta then
                            meta.owner = meta.owner or hero_name
                            if not meta.is_passive then
                                table.insert(hero_abilities, ability_name)
                            end
                        end
                    end
                end
            end
            if #hero_abilities > 0 then
                hero_ability_order[hero_name] = hero_abilities
            end
        end
    end
end

build_ability_metadata()

local function get_or_create_metadata(ability, ability_name)
    local meta = ability_metadata[ability_name]
    if not meta then
        meta = {
            name = ability_name,
            display = prettify_ability_name(ability_name),
            behavior_tokens = {},
            behavior_value = nil,
            target_team_tokens = {},
            target_type_tokens = {},
            cast_range = nil,
            radius = nil,
            immunity = nil,
            is_toggle = false,
            is_passive = false,
            owner = nil,
        }
        ability_metadata[ability_name] = meta
    end

    if ability and not meta.behavior_value then
        local value = Ability.GetBehavior(ability)
        if value then
            meta.behavior_value = value
            meta.behavior_tokens = merge_sets(meta.behavior_tokens, decode_behavior_value(value))
            meta.is_toggle = meta.behavior_tokens.DOTA_ABILITY_BEHAVIOR_TOGGLE or meta.is_toggle
            meta.is_passive = meta.behavior_tokens.DOTA_ABILITY_BEHAVIOR_PASSIVE or meta.is_passive
        end
    end

    if ability and (not meta.target_team_tokens or next(meta.target_team_tokens) == nil) then
        local team_value = Ability.GetTargetTeam(ability)
        if team_value then
            meta.target_team_tokens = merge_sets(meta.target_team_tokens, decode_target_team(team_value))
        end
    end

    if ability and (not meta.target_type_tokens or next(meta.target_type_tokens) == nil) then
        local type_value = Ability.GetTargetType(ability)
        if type_value then
            meta.target_type_tokens = merge_sets(meta.target_type_tokens, decode_target_type(type_value))
        end
    end

    if ability and not meta.cast_range then
        local cast_range = Ability.GetCastRange(ability)
        if cast_range and cast_range > 0 then
            meta.cast_range = cast_range
        end
    end

    return meta
end

--#endregion

--#region UI
local ui = {}
local general_group = Menu.Create("Heroes", "Rubick", "Spell Stealer", "General", "Main")
ui.enabled = general_group:Switch("Enable Auto Spell Casting", true, "\u{f0e7}")
ui.skip_channelled = general_group:Switch("Skip Channelled Abilities", true, "\u{f04b}")
ui.ally_hp_threshold = general_group:Slider("Ally HP Threshold", 0, 100, 75, function(value)
    return string.format("%d%%", value)
end)
ui.enemy_radius = general_group:Slider("Default Engagement Radius", 200, 1600, 600, "%d")

local ability_groups = {}
local misc_group = Menu.Create("Heroes", "Rubick", "Spell Stealer", "Ability Toggles", "Miscellaneous")

local function ensure_ability_switch(hero_name, ability_name)
    local existing = ability_switches[ability_name]
    if existing then
        return existing
    end

    local meta = ability_metadata[ability_name]
    local group
    if hero_name and hero_display_names[hero_name] then
        group = ability_groups[hero_name]
        if not group then
            group = Menu.Create("Heroes", "Rubick", "Spell Stealer", "Ability Toggles", hero_display_names[hero_name])
            ability_groups[hero_name] = group
        end
    else
        group = misc_group
    end

    local default_state = true
    if meta then
        if meta.is_passive or meta.behavior_tokens.DOTA_ABILITY_BEHAVIOR_PASSIVE then
            default_state = false
        elseif meta.is_toggle or meta.behavior_tokens.DOTA_ABILITY_BEHAVIOR_TOGGLE then
            default_state = false
        end
    end

    local switch = group:Switch((meta and meta.display) or prettify_ability_name(ability_name), default_state)
    ability_switches[ability_name] = switch
    return switch
end

local sorted_heroes = {}
for hero_name, abilities in pairs(hero_ability_order) do
    table.insert(sorted_heroes, hero_name)
    table.sort(abilities, function(a, b)
        local meta_a = ability_metadata[a]
        local meta_b = ability_metadata[b]
        local display_a = meta_a and meta_a.display or a
        local display_b = meta_b and meta_b.display or b
        return display_a < display_b
    end)
end

table.sort(sorted_heroes, function(a, b)
    local display_a = hero_display_names[a] or a
    local display_b = hero_display_names[b] or b
    return display_a < display_b
end)

for _, hero_name in ipairs(sorted_heroes) do
    for _, ability_name in ipairs(hero_ability_order[hero_name]) do
        ensure_ability_switch(hero_name, ability_name)
    end
end

--#endregion

--#region Target selection
local function convert_team_type(tokens)
    if not tokens then
        return Enum.TeamType.TEAM_ENEMY
    end
    if tokens.DOTA_UNIT_TARGET_TEAM_BOTH then
        return Enum.TeamType.TEAM_BOTH
    end
    if tokens.DOTA_UNIT_TARGET_TEAM_FRIENDLY then
        return Enum.TeamType.TEAM_FRIEND
    end
    return Enum.TeamType.TEAM_ENEMY
end

local function unit_matches_target(unit, tokens, hero)
    if not tokens or next(tokens) == nil then
        return true
    end
    if unit == hero and tokens.DOTA_UNIT_TARGET_SELF then
        return true
    end
    if NPC.IsHero(unit) then
        if tokens.DOTA_UNIT_TARGET_HERO or tokens.DOTA_UNIT_TARGET_ALL or tokens.DOTA_UNIT_TARGET_HEROES_AND_CREEPS then
            return true
        end
    end
    if NPC.IsCreep(unit) and not NPC.IsHero(unit) then
        if tokens.DOTA_UNIT_TARGET_CREEP or tokens.DOTA_UNIT_TARGET_BASIC or tokens.DOTA_UNIT_TARGET_ALL or tokens.DOTA_UNIT_TARGET_HEROES_AND_CREEPS then
            return true
        end
    end
    if NPC.IsTower(unit) then
        if tokens.DOTA_UNIT_TARGET_BUILDING or tokens.DOTA_UNIT_TARGET_ALL then
            return true
        end
    end
    return false
end

local function select_enemy_target(hero, units, tokens, cast_range)
    if not units then
        return nil
    end
    local hero_pos = Entity.GetAbsOrigin(hero)
    local best_unit = nil
    local best_score = nil
    for i = 1, #units do
        local unit = units[i]
        if unit ~= hero and Entity.IsAlive(unit) and not NPC.IsWaitingToSpawn(unit) then
            if unit_matches_target(unit, tokens, hero) then
                local unit_pos = Entity.GetAbsOrigin(unit)
                local distance = hero_pos:Distance(unit_pos)
                if not cast_range or distance <= cast_range + 75.0 then
                    local score = distance
                    if NPC.IsHero(unit) then
                        score = score - 200.0
                    end
                    if not best_score or score < best_score then
                        best_score = score
                        best_unit = unit
                    end
                end
            end
        end
    end
    return best_unit
end

local function select_friendly_target(hero, units, tokens, cast_range, hp_threshold)
    local chosen_unit = nil
    local chosen_hp = nil
    local hero_hp = Entity.GetHealth(hero)
    local hero_max_hp = math.max(Entity.GetMaxHealth(hero), 1)
    local hero_pct = hero_hp / hero_max_hp

    if tokens and tokens.DOTA_UNIT_TARGET_SELF and hero_pct <= hp_threshold then
        chosen_unit = hero
        chosen_hp = hero_pct
    end

    if units then
        for i = 1, #units do
            local unit = units[i]
            if Entity.IsAlive(unit) and (not cast_range or NPC.IsEntityInRange(hero, unit, cast_range + 75.0)) then
                if unit_matches_target(unit, tokens, hero) then
                    local unit_hp = Entity.GetHealth(unit)
                    local unit_max_hp = math.max(Entity.GetMaxHealth(unit), 1)
                    local unit_pct = unit_hp / unit_max_hp
                    if unit_pct <= hp_threshold then
                        if not chosen_hp or unit_pct < chosen_hp then
                            chosen_unit = unit
                            chosen_hp = unit_pct
                        end
                    end
                end
            end
        end
    end

    return chosen_unit
end

local function find_unit_target(hero, ability, meta, cast_range)
    local team_type = convert_team_type(meta.target_team_tokens)
    local search_range = cast_range or meta.cast_range or ui.enemy_radius:Get()
    if search_range <= 0 then
        search_range = ui.enemy_radius:Get()
    end
    local units = Entity.GetUnitsInRadius(hero, search_range + 100.0, team_type, true, true)
    if team_type == Enum.TeamType.TEAM_FRIEND then
        local hp_threshold = (ui.ally_hp_threshold:Get() or 75) / 100
        return select_friendly_target(hero, units, meta.target_type_tokens, search_range, hp_threshold)
    elseif team_type == Enum.TeamType.TEAM_BOTH then
        local hp_threshold = (ui.ally_hp_threshold:Get() or 75) / 100
        local ally = select_friendly_target(hero, units, meta.target_type_tokens, search_range, hp_threshold)
        if ally then
            return ally
        end
        return select_enemy_target(hero, units, meta.target_type_tokens, search_range)
    end
    return select_enemy_target(hero, units, meta.target_type_tokens, search_range)
end

local function find_point_target(hero, ability, meta, cast_range)
    local team_type = convert_team_type(meta.target_team_tokens)
    local search_range = cast_range or meta.cast_range or ui.enemy_radius:Get()
    if search_range <= 0 then
        search_range = ui.enemy_radius:Get()
    end
    local units = Entity.GetUnitsInRadius(hero, search_range + 100.0, team_type, true, true)
    if team_type == Enum.TeamType.TEAM_FRIEND then
        local target = select_friendly_target(hero, units, meta.target_type_tokens, search_range, (ui.ally_hp_threshold:Get() or 75) / 100)
        if target then
            return Entity.GetAbsOrigin(target)
        end
        return nil
    end
    local target = select_enemy_target(hero, units, meta.target_type_tokens, search_range)
    if target then
        return Entity.GetAbsOrigin(target)
    end
    return nil
end

local function should_cast_no_target(hero, meta)
    local radius = meta.radius or ui.enemy_radius:Get()
    if radius <= 0 then
        radius = ui.enemy_radius:Get()
    end
    local enemies = Entity.GetUnitsInRadius(hero, radius, Enum.TeamType.TEAM_ENEMY, true, true)
    if enemies then
        for i = 1, #enemies do
            local unit = enemies[i]
            if unit ~= hero and Entity.IsAlive(unit) and unit_matches_target(unit, meta.target_type_tokens, hero) then
                return true
            end
        end
    end

    if meta.target_team_tokens and meta.target_team_tokens.DOTA_UNIT_TARGET_TEAM_FRIENDLY then
        local allies = Entity.GetUnitsInRadius(hero, radius, Enum.TeamType.TEAM_FRIEND, true, true)
        if allies then
            local hp_threshold = (ui.ally_hp_threshold:Get() or 75) / 100
            for i = 1, #allies do
                local ally = allies[i]
                if Entity.IsAlive(ally) and ally ~= hero then
                    local hp_pct = Entity.GetHealth(ally) / math.max(Entity.GetMaxHealth(ally), 1)
                    if hp_pct <= hp_threshold then
                        return true
                    end
                end
            end
        end
    end

    return false
end

--#endregion

--#region Casting logic
local last_cast_times = {}

local function throttle_cast(name, delay)
    local now = GameRules.GetGameTime()
    if not now then
        return true
    end
    local last = last_cast_times[name]
    if last and (now - last) < delay then
        return false
    end
    last_cast_times[name] = now
    return true
end

local function should_skip(meta)
    if meta.is_passive or meta.behavior_tokens.DOTA_ABILITY_BEHAVIOR_PASSIVE then
        return true
    end
    if meta.is_toggle or meta.behavior_tokens.DOTA_ABILITY_BEHAVIOR_TOGGLE then
        return true
    end
    if meta.behavior_tokens.DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING then
        return true
    end
    return false
end

local function cast_stolen_ability(hero, ability)
    local ability_name = Ability.GetName(ability)
    local meta = get_or_create_metadata(ability, ability_name)
    if should_skip(meta) then
        return false
    end

    local switch = ability_switches[ability_name] or ensure_ability_switch(meta.owner, ability_name)
    if switch and not switch:Get() then
        return false
    end

    if Ability.IsHidden(ability) or not Ability.IsActivated(ability) then
        return false
    end
    if Ability.GetLevel(ability) <= 0 then
        return false
    end
    if Ability.IsInAbilityPhase(ability) then
        return false
    end
    if not Ability.IsReady(ability) then
        return false
    end
    if not Ability.IsCastable(ability, NPC.GetMana(hero)) then
        return false
    end
    if meta.behavior_tokens.DOTA_ABILITY_BEHAVIOR_CHANNELLED and ui.skip_channelled:Get() then
        return false
    end

    local behavior = meta.behavior_tokens or {}
    local cast_range = Ability.GetCastRange(ability)
    if not cast_range or cast_range <= 0 then
        cast_range = meta.cast_range or ui.enemy_radius:Get()
    end

    local has_unit_target = behavior.DOTA_ABILITY_BEHAVIOR_UNIT_TARGET or behavior.DOTA_ABILITY_BEHAVIOR_OPTIONAL_UNIT_TARGET
    local has_point_target = behavior.DOTA_ABILITY_BEHAVIOR_POINT or behavior.DOTA_ABILITY_BEHAVIOR_OPTIONAL_POINT
    local has_no_target = behavior.DOTA_ABILITY_BEHAVIOR_NO_TARGET or behavior.DOTA_ABILITY_BEHAVIOR_OPTIONAL_NO_TARGET or behavior.DOTA_ABILITY_BEHAVIOR_IMMEDIATE

    if has_unit_target then
        local target = find_unit_target(hero, ability, meta, cast_range)
        if target and throttle_cast(ability_name, 0.15) then
            Ability.CastTarget(ability, target)
            return true
        end
    end

    if has_point_target and not has_unit_target then
        local position = find_point_target(hero, ability, meta, cast_range)
        if position and throttle_cast(ability_name, 0.15) then
            Ability.CastPosition(ability, position)
            return true
        end
    end

    if has_no_target and not has_unit_target and not has_point_target then
        if should_cast_no_target(hero, meta) and throttle_cast(ability_name, 0.25) then
            Ability.CastNoTarget(ability)
            return true
        end
    end

    return false
end
--#endregion

--#region Runtime state
local my_hero = nil

local function reset_state()
    my_hero = nil
    last_cast_times = {}
end

local function update_local_hero()
    if my_hero and Heroes.Contains(my_hero) then
        if Entity.GetUnitName(my_hero) == "npc_dota_hero_rubick" then
            return my_hero
        end
    end

    local hero = Heroes.GetLocal()
    if hero and Entity.GetUnitName(hero) == "npc_dota_hero_rubick" then
        my_hero = hero
        return my_hero
    end

    my_hero = nil
    return nil
end
--#endregion

--#region Callbacks
function rubick.OnUpdate()
    if not ui.enabled:Get() then
        return
    end

    if not Engine.IsInGame() then
        reset_state()
        return
    end

    local hero = update_local_hero()
    if not hero or not Entity.IsAlive(hero) then
        return
    end

    if NPC.IsStunned(hero) or NPC.IsSilenced(hero) then
        return
    end
    if ui.skip_channelled:Get() and NPC.IsChannellingAbility(hero) then
        return
    end

    for slot = 0, 24 do
        local ability = NPC.GetAbilityByIndex(hero, slot)
        if ability and Ability.IsStolen(ability) then
            if cast_stolen_ability(hero, ability) then
                return
            end
        end
    end
end

function rubick.OnGameEnd()
    reset_state()
end

--#endregion

return rubick
