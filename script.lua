local agent_script = { ui = {} }

--[[
    Unit Commander (rewrite)
    ------------------------
    Controls all allied units except the hero and courier. Provides a
    configuration menu, enlarged debug overlays, and automatic spell usage for
    neutral creeps using UCZone API v2 friendly helpers.
]]

-------------------------------------------------------------------------------
-- Runtime state
-------------------------------------------------------------------------------
local runtime = {
    hero = nil,
    hero_owner_id = nil,
    team = nil,
    player = nil,
    player_id = nil,
    config = nil,
    agents = {},
    threat_expiry = {},
    menu_ready = false,
    debug_font = nil,
}

local STATES = {
    FOLLOW = "FOLLOW",
    ENGAGE = "ENGAGE",
    FARM = "FARM",
    MANUAL = "MANUAL",
}

-------------------------------------------------------------------------------
-- Utility helpers
-------------------------------------------------------------------------------
local function ResetRuntime()
    runtime.hero = nil
    runtime.hero_owner_id = nil
    runtime.team = nil
    runtime.player = nil
    runtime.player_id = nil
    runtime.config = nil
    runtime.agents = {}
    runtime.threat_expiry = {}
    runtime.debug_font = nil
end

local function IsValidHandle(handle)
    if not handle then
        return false
    end

    local t = type(handle)
    if t ~= "userdata" and t ~= "table" then
        return false
    end

    local is_null = handle.IsNull
    if type(is_null) == "function" then
        local ok, result = pcall(is_null, handle)
        if ok and result then
            return false
        end
    end

    return true
end

local function EnsureFont()
    if not runtime.debug_font then
        runtime.debug_font = Render.LoadFont("Arial", 16, Enum.FontCreate.FONTFLAG_OUTLINE)
    end
    return runtime.debug_font
end

local function GetPlayerOwnerID(unit)
    if NPC and NPC.GetPlayerOwnerID then
        local ok, owner = pcall(NPC.GetPlayerOwnerID, unit)
        if ok and type(owner) == "number" and owner >= 0 then
            return owner
        end
    end

    if Entity and Entity.GetPlayerOwnerID then
        local ok, owner = pcall(Entity.GetPlayerOwnerID, unit)
        if ok and type(owner) == "number" and owner >= 0 then
            return owner
        end
    end

    return nil
end

local function GetEntityOwner(unit)
    if Entity and Entity.GetOwner then
        local ok, owner = pcall(Entity.GetOwner, unit)
        if ok and owner and owner ~= unit then
            return owner
        end
    end
    return nil
end

local function IsOwnedByHero(unit)
    if not runtime.hero then
        return false
    end

    local current = unit
    local safety = 0
    while current and safety < 10 do
        if current == runtime.hero then
            return true
        end
        current = GetEntityOwner(current)
        safety = safety + 1
    end

    return false
end

local function AcquirePlayerHandle()
    if IsValidHandle(runtime.player) then
        return runtime.player
    end

    runtime.player = nil

    if runtime.player_id then
        if PlayerResource and PlayerResource.GetPlayer then
            local ok, candidate = pcall(PlayerResource.GetPlayer, runtime.player_id)
            if ok and IsValidHandle(candidate) then
                runtime.player = candidate
                return runtime.player
            end
        end

        if Players and Players.GetPlayer then
            local ok, candidate = pcall(Players.GetPlayer, runtime.player_id)
            if ok and IsValidHandle(candidate) then
                runtime.player = candidate
                return runtime.player
            end
        end
    end

    if Players and Players.GetLocal then
        local ok, candidate = pcall(Players.GetLocal)
        if ok and IsValidHandle(candidate) then
            runtime.player = candidate
            if Player and Player.GetPlayerID then
                local ok_id, pid = pcall(Player.GetPlayerID, candidate)
                if ok_id and type(pid) == "number" and pid >= 0 then
                    runtime.player_id = pid
                end
            end
            return runtime.player
        end
    end

    return nil
end

local function UpdateHeroContext()
    runtime.hero = Heroes and Heroes.GetLocal and Heroes.GetLocal() or nil
    if not runtime.hero or not Entity.IsAlive(runtime.hero) then
        ResetRuntime()
        return false
    end

    runtime.team = Entity.GetTeamNum(runtime.hero)

    local owner_id = GetPlayerOwnerID(runtime.hero)
    if not owner_id and Hero and Hero.GetPlayerID then
        local ok, pid = pcall(Hero.GetPlayerID, runtime.hero)
        if ok and type(pid) == "number" and pid >= 0 then
            owner_id = pid
        end
    end

    runtime.hero_owner_id = owner_id

    if owner_id and owner_id >= 0 then
        runtime.player_id = runtime.player_id or owner_id
    end

    AcquirePlayerHandle()
    return true
end

-------------------------------------------------------------------------------
-- Menu configuration
-------------------------------------------------------------------------------
local function EnsureMenu()
    if runtime.menu_ready then
        return
    end

    if not Menu or not Menu.Create then
        return
    end

    local tab = Menu.Create("Scripts", "Other", "Unit Commander")
    if not tab then
        return
    end

    tab:Icon("\u{f0c0}")

    local main_group = tab:Create("Main")
    local settings = main_group:Create("Settings")

    agent_script.ui.enable = settings:Switch("Включить Unit Commander", true, "\u{f0c0}")
    agent_script.ui.enable:ToolTip("Автоматически управлять всеми подвластными юнитами, кроме героя и курьера.")

    agent_script.ui.debug = settings:Switch("Показать отладку", true, "\u{f05a}")
    agent_script.ui.debug:ToolTip("Показывать крупные подписи над юнитами с их текущим состоянием.")

    agent_script.ui.follow_distance = settings:Slider("Дистанция следования", 100, 900, 400, "%d")
    agent_script.ui.follow_distance:ToolTip("Как далеко юниты могут отходить от героя до начала преследования.")

    agent_script.ui.attack_radius = settings:Slider("Радиус агрессии", 300, 2000, 900, "%d")
    agent_script.ui.attack_radius:ToolTip("Максимальная дистанция поиска целей для атаки.")

    agent_script.ui.order_cooldown = settings:Slider("Задержка приказов (сек)", 10, 200, 50, "%.1f")
    agent_script.ui.order_cooldown:ToolTip("Минимальный интервал между приказами (значение делится на 100).")

    agent_script.ui.channel_wait = settings:Slider("Задержка после канала (сек)", 10, 200, 20, "%.1f")
    agent_script.ui.channel_wait:ToolTip("Ожидание после начала канала способности (значение делится на 100).")

    agent_script.ui.manual_override = settings:Slider("Ручное управление (сек)", 50, 500, 250, "%.1f")
    agent_script.ui.manual_override:ToolTip("Сколько секунд AI не вмешивается после вашего приказа (значение делится на 100).")

    runtime.menu_ready = true
end

local function ReadConfig()
    if not runtime.menu_ready then
        EnsureMenu()
    end

    runtime.config = runtime.config or {}

    local function slider_value(slider)
        if not slider then
            return 0
        end
        return (slider:Get() or 0) / 100
    end

    runtime.config.enabled = agent_script.ui.enable and agent_script.ui.enable:Get() or false
    runtime.config.debug = agent_script.ui.debug and agent_script.ui.debug:Get() or false
    runtime.config.follow_distance = (agent_script.ui.follow_distance and agent_script.ui.follow_distance:Get() or 400)
    runtime.config.attack_radius = (agent_script.ui.attack_radius and agent_script.ui.attack_radius:Get() or 900)
    runtime.config.order_cooldown = slider_value(agent_script.ui.order_cooldown)
    runtime.config.channel_wait = slider_value(agent_script.ui.channel_wait)
    runtime.config.manual_override = slider_value(agent_script.ui.manual_override)

    if runtime.config.order_cooldown < 0.05 then
        runtime.config.order_cooldown = 0.05
    end
    if runtime.config.channel_wait < 0.05 then
        runtime.config.channel_wait = 0.05
    end
    if runtime.config.manual_override < 0.1 then
        runtime.config.manual_override = 0.1
    end
end

-------------------------------------------------------------------------------
-- Ability metadata
-------------------------------------------------------------------------------
local ABILITY_DATA = {
    mud_golem_hurl_boulder = {
        behavior = "target",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Бросаю валун",
        aliases = {
            "ancient_rock_golem_hurl_boulder",
            "granite_golem_hurl_boulder",
        },
    },
    dark_troll_warlord_ensnare = {
        behavior = "target",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Бросаю сеть",
    },
    dark_troll_warlord_raise_dead = {
        behavior = "no_target",
        always_cast = true,
        ignore_is_castable = true,
        message = "Призываю скелетов",
        aliases = {
            "dark_troll_summoner_raise_dead",
            "dark_troll_warlord_raise_dead_datadriven",
        },
    },
    forest_troll_high_priest_heal = {
        behavior = "ally_target",
        prefer_anchor = true,
        prefer_ally_hero = true,
        ally_max_health_pct = 0.92,
        message = "Лечу союзника",
    },
    satyr_hellcaller_shockwave = {
        behavior = "point",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Шоковая волна",
    },
    satyr_trickster_purge = {
        behavior = "target",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Снимаю эффекты",
    },
    satyr_soulstealer_mana_burn = {
        behavior = "target",
        only_heroes = true,
        min_mana = 75,
        message = "Выжигаю ману",
        aliases = {
            "satyr_mindstealer_mana_burn",
        },
    },
    harpy_storm_chain_lightning = {
        behavior = "target",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Цепная молния",
    },
    centaur_khan_war_stomp = {
        behavior = "no_target",
        radius = 315,
        min_enemies = 1,
        allow_creeps = true,
        allow_neutrals = true,
        message = "Оглушаю врагов",
    },
    polar_furbolg_ursa_warrior_thunder_clap = {
        behavior = "no_target",
        radius = 315,
        min_enemies = 1,
        allow_creeps = true,
        allow_neutrals = true,
        message = "Громовой удар",
        aliases = {
            "polar_furbolg_champion_thunder_clap",
        },
    },
    hellbear_smasher_slam = {
        behavior = "no_target",
        radius = 350,
        min_enemies = 1,
        allow_creeps = true,
        allow_neutrals = true,
        message = "Мощный удар",
    },
    ogre_bruiser_ogre_smash = {
        behavior = "point",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Размазываю врага",
        range_bonus = 50,
        aliases = {
            "ogre_mauler_smash",
        },
    },
    neutral_ogre_magi_ice_armor = {
        behavior = "ally_target",
        prefer_anchor = true,
        prefer_ally_hero = true,
        avoid_modifier = "modifier_ogre_magi_frost_armor",
        message = "Накладываю броню",
        aliases = {
            "ogre_magi_frost_armor",
        },
    },
    ancient_black_dragon_fireball = {
        behavior = "point",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Огненный шар",
        aliases = {
            "black_dragon_fireball",
        },
    },
    ancient_thunderhide_slam = {
        behavior = "no_target",
        radius = 315,
        min_enemies = 1,
        allow_creeps = true,
        allow_neutrals = true,
        message = "Громовой топот",
        aliases = {
            "big_thunder_lizard_slam",
        },
    },
    ancient_thunderhide_frenzy = {
        behavior = "ally_target",
        prefer_anchor = true,
        include_self = false,
        message = "Бешенство",
        aliases = {
            "big_thunder_lizard_frenzy",
        },
    },
    fel_beast_haunt = {
        behavior = "target",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Пугаю врага",
    },
    enraged_wildkin_tornado = {
        behavior = "point",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Призываю торнадо",
        aliases = {
            "wildkin_tornado",
        },
    },
    wildkin_hurricane = {
        behavior = "point",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Сильный порыв",
    },
    prowler_acolyte_heal = {
        behavior = "ally_target",
        prefer_ally_hero = true,
        ally_max_health_pct = 0.85,
        message = "Лечу союзника",
    },
    kobold_taskmaster_speed_aura = {
        behavior = "no_target",
        always_cast = true,
        ignore_is_castable = true,
        message = "Ускоряю отряд",
    },
    neutral_spell_immunity = {
        behavior = "no_target",
        always_cast = true,
        message = "Щит",
    },
}

local function ExpandAbilityAliases()
    local pending = {}
    for name, metadata in pairs(ABILITY_DATA) do
        if metadata.aliases then
            for _, alias in ipairs(metadata.aliases) do
                if not ABILITY_DATA[alias] then
                    table.insert(pending, { alias, metadata })
                end
            end
        end
    end

    for _, entry in ipairs(pending) do
        ABILITY_DATA[entry[1]] = entry[2]
    end
end

ExpandAbilityAliases()

-------------------------------------------------------------------------------
-- Ability helpers
-------------------------------------------------------------------------------
local function GetAbilityCharges(ability)
    if not ability then
        return nil
    end

    local readers = {
        "GetCurrentAbilityCharges",
        "GetCurrentCharges",
        "GetRemainingCharges",
        "GetCharges",
    }

    for _, name in ipairs(readers) do
        local getter = Ability[name]
        if type(getter) == "function" then
            local ok, value = pcall(getter, ability)
            if ok and type(value) == "number" then
                return value
            end
        end
    end

    return nil
end

local function IsAbilityReady(unit, ability, metadata)
    if not ability then
        return false
    end

    if Ability.GetLevel and Ability.GetLevel(ability) <= 0 then
        return false
    end

    if Ability.IsHidden and Ability.IsHidden(ability) then
        return false
    end

    if Ability.IsPassive and Ability.IsPassive(ability) then
        return false
    end

    if Ability.GetCooldownTimeRemaining then
        local ok, remaining = pcall(Ability.GetCooldownTimeRemaining, ability)
        if ok and remaining and remaining > 0 then
            return false
        end
    end

    if metadata and metadata.requires_charges then
        local charges = GetAbilityCharges(ability)
        if not charges or charges <= 0 then
            return false
        end
    end

    if metadata and metadata.ignore_is_castable then
        return true
    end

    if Ability.IsReady then
        local ok, ready = pcall(Ability.IsReady, ability)
        if ok and ready then
            return true
        end
    end

    if Ability.IsCastable then
        local ok, castable = pcall(Ability.IsCastable, ability, NPC.GetMana(unit))
        if ok then
            return castable
        end
    end

    return false
end

local function GetAbilityCastRange(unit, ability, metadata)
    if metadata and metadata.range then
        return metadata.range
    end

    if Ability.GetCastRange then
        local ok, range = pcall(Ability.GetCastRange, ability)
        if ok and range and range > 0 then
            return range
        end
    end

    if ability and Ability.GetSpecialValueFor then
        local ok, value = pcall(Ability.GetSpecialValueFor, ability, "cast_range")
        if ok and value and value > 0 then
            return value
        end
    end

    return 600
end

local function SafeOrder(unit, order, target, position, ability)
    local player = AcquirePlayerHandle()
    if not player then
        return
    end

    Player.PrepareUnitOrders(
        player,
        order,
        target,
        position,
        ability,
        Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY,
        unit
    )
end

local function SafeCastTarget(unit, ability, target)
    if Ability.CastTarget then
        local ok = pcall(Ability.CastTarget, ability, target)
        if ok then
            return
        end
    end
    SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET, target, nil, ability)
end

local function SafeCastPosition(unit, ability, position)
    if Ability.CastPosition then
        local ok = pcall(Ability.CastPosition, ability, position)
        if ok then
            return
        end
    end
    SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION, nil, position, ability)
end

local function SafeCastNoTarget(unit, ability)
    if Ability.CastNoTarget then
        local ok = pcall(Ability.CastNoTarget, ability)
        if ok then
            return
        end
    end
    SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, nil, ability)
end

local function GetUnitHealthPercent(unit)
    if not unit or not Entity.IsAlive(unit) then
        return 0
    end

    local health = Entity.GetHealth(unit) or 0
    local max_health = Entity.GetMaxHealth(unit) or 0

    if max_health <= 0 then
        return 0
    end

    return health / max_health
end

local function EnemyMatches(enemy, metadata)
    if not enemy or not Entity.IsAlive(enemy) then
        return false
    end

    if Entity.GetTeamNum(enemy) == runtime.team then
        return false
    end

    if NPC.IsCourier and NPC.IsCourier(enemy) then
        return false
    end

    local is_hero = NPC.IsHero(enemy)
    local is_creep = NPC.IsCreep(enemy) and not is_hero
    local is_neutral = Entity.GetTeamNum(enemy) == Enum.TeamNum.TEAM_NEUTRAL

    if metadata then
        if metadata.only_heroes and not is_hero then
            return false
        end
        if is_creep and metadata.allow_creeps == false then
            return false
        end
        if is_neutral and metadata.allow_neutrals == false then
            return false
        end
        if metadata.min_mana and NPC.GetMana(enemy) < metadata.min_mana then
            return false
        end
        if metadata.avoid_modifier and NPC.HasModifier(enemy, metadata.avoid_modifier) then
            return false
        end
    end

    return true
end

local function AllyMatches(ally, metadata)
    if not ally or not Entity.IsAlive(ally) then
        return false
    end

    if metadata then
        if metadata.include_self == false and ally == runtime.hero then
            return false
        end
        if metadata.ally_max_health_pct then
            if GetUnitHealthPercent(ally) >= metadata.ally_max_health_pct then
                return false
            end
        end
        if metadata.ally_min_health_pct then
            if GetUnitHealthPercent(ally) <= metadata.ally_min_health_pct then
                return false
            end
        end
        if metadata.avoid_modifier and NPC.HasModifier(ally, metadata.avoid_modifier) then
            return false
        end
    end

    return true
end

local function FindEnemyTarget(unit, metadata, cast_range, current_target, anchor_pos)
    local unit_pos = Entity.GetAbsOrigin(unit)
    local centers = {}

    if unit_pos then
        centers[#centers + 1] = unit_pos
    end
    if anchor_pos then
        centers[#centers + 1] = anchor_pos
    end

    local best_target
    local best_score = -math.huge

    if current_target and EnemyMatches(current_target, metadata) then
        local pos = Entity.GetAbsOrigin(current_target)
        if pos and unit_pos and unit_pos:Distance(pos) <= cast_range + (metadata and metadata.range_bonus or 0) then
            best_target = current_target
            best_score = 1000
        end
    end

    for _, center in ipairs(centers) do
        local enemies = NPCs.InRadius(center, cast_range + (metadata and metadata.range_bonus or 0), runtime.team, Enum.TeamType.TEAM_ENEMY) or {}
        for _, enemy in ipairs(enemies) do
            if EnemyMatches(enemy, metadata) then
                local pos = Entity.GetAbsOrigin(enemy)
                if pos then
                    local distance = center:Distance(pos)
                    if distance <= cast_range + (metadata and metadata.range_bonus or 0) then
                        local score = -distance
                        if NPC.IsHero(enemy) then
                            score = score + 300
                        end

                        local idx = Entity.GetIndex(enemy)
                        if runtime.threat_expiry[idx] and runtime.threat_expiry[idx] > GlobalVars.GetCurTime() then
                            score = score + 150
                        end

                        if score > best_score then
                            best_score = score
                            best_target = enemy
                        end
                    end
                end
            end
        end

        if metadata and metadata.allow_neutrals ~= false then
            local neutrals = NPCs.InRadius(center, cast_range + (metadata and metadata.range_bonus or 0), runtime.team, Enum.TeamType.TEAM_NEUTRAL) or {}
            for _, enemy in ipairs(neutrals) do
                if EnemyMatches(enemy, metadata) then
                    local pos = Entity.GetAbsOrigin(enemy)
                    if pos then
                        local distance = center:Distance(pos)
                        if distance <= cast_range + (metadata and metadata.range_bonus or 0) then
                            local score = -distance
                            if score > best_score then
                                best_score = score
                                best_target = enemy
                            end
                        end
                    end
                end
            end
        end
    end

    return best_target
end

local function ChooseAllyTarget(unit, metadata, cast_range, anchor_unit, anchor_pos)
    if metadata and metadata.prefer_anchor and anchor_unit and AllyMatches(anchor_unit, metadata) then
        local anchor_position = anchor_pos or Entity.GetAbsOrigin(anchor_unit)
        local unit_pos = Entity.GetAbsOrigin(unit)
        if anchor_position and unit_pos and unit_pos:Distance(anchor_position) <= cast_range + (metadata and metadata.range_bonus or 0) then
            return anchor_unit
        end
    end

    if metadata and metadata.prefer_ally_hero and runtime.hero and AllyMatches(runtime.hero, metadata) then
        local hero_pos = Entity.GetAbsOrigin(runtime.hero)
        local unit_pos = Entity.GetAbsOrigin(unit)
        if hero_pos and unit_pos and unit_pos:Distance(hero_pos) <= cast_range + (metadata and metadata.range_bonus or 0) then
            return runtime.hero
        end
    end

    local unit_pos = Entity.GetAbsOrigin(unit)
    if not unit_pos then
        return nil
    end

    local best_target
    local best_score = -math.huge

    local friends = NPCs.InRadius(unit_pos, cast_range + (metadata and metadata.range_bonus or 0), runtime.team, Enum.TeamType.TEAM_FRIEND) or {}
    for _, ally in ipairs(friends) do
        if AllyMatches(ally, metadata) then
            local pos = Entity.GetAbsOrigin(ally)
            if pos then
                local distance = unit_pos:Distance(pos)
                if distance <= cast_range + (metadata and metadata.range_bonus or 0) then
                    local score = -distance
                    if NPC.IsHero(ally) then
                        score = score + 120
                    end
                    if score > best_score then
                        best_score = score
                        best_target = ally
                    end
                end
            end
        end
    end

    return best_target
end

local function ShouldCastNoTargetAbility(unit, metadata, ability)
    if metadata and metadata.always_cast then
        return true
    end

    local radius = metadata and metadata.radius
    if not radius and Ability.GetAOERadius then
        local ok, value = pcall(Ability.GetAOERadius, ability)
        if ok and value and value > 0 then
            radius = value
        end
    end
    radius = radius or 250

    local unit_pos = Entity.GetAbsOrigin(unit)
    if not unit_pos then
        return false
    end

    local enemies = NPCs.InRadius(unit_pos, radius, runtime.team, Enum.TeamType.TEAM_ENEMY) or {}
    local neutrals = NPCs.InRadius(unit_pos, radius, runtime.team, Enum.TeamType.TEAM_NEUTRAL) or {}

    local total = 0
    for _, enemy in ipairs(enemies) do
        if EnemyMatches(enemy, metadata) then
            total = total + 1
        end
    end

    if metadata and metadata.allow_neutrals ~= false then
        for _, enemy in ipairs(neutrals) do
            if EnemyMatches(enemy, metadata) then
                total = total + 1
            end
        end
    end

    local minimum = 1
    if metadata and metadata.min_enemies then
        minimum = metadata.min_enemies
    end

    return total >= minimum
end

local function TryCastAbility(unit, agent, now, ability, metadata, current_target, anchor_unit, anchor_pos)
    if not IsAbilityReady(unit, ability, metadata) then
        return false
    end

    local behavior = metadata and metadata.behavior
    local cast_range = GetAbilityCastRange(unit, ability, metadata)

    if behavior == "target" then
        local enemy = FindEnemyTarget(unit, metadata, cast_range, current_target, anchor_pos)
        if enemy then
            SafeCastTarget(unit, ability, enemy)
            agent.last_action = metadata and metadata.message or "Использую способность"
            agent.next_order_time = now + runtime.config.order_cooldown
            return true
        end
    elseif behavior == "point" then
        local enemy = FindEnemyTarget(unit, metadata, cast_range, current_target, anchor_pos)
        local cast_pos = enemy and Entity.GetAbsOrigin(enemy)
        if not cast_pos and metadata and metadata.always_cast then
            cast_pos = Entity.GetAbsOrigin(unit)
        end
        if cast_pos then
            SafeCastPosition(unit, ability, cast_pos)
            agent.last_action = metadata and metadata.message or "Использую способность"
            agent.next_order_time = now + runtime.config.order_cooldown
            return true
        end
    elseif behavior == "no_target" then
        if ShouldCastNoTargetAbility(unit, metadata, ability) then
            SafeCastNoTarget(unit, ability)
            agent.last_action = metadata and metadata.message or "Использую способность"
            agent.next_order_time = now + runtime.config.order_cooldown
            return true
        end
    elseif behavior == "ally_target" then
        local ally = ChooseAllyTarget(unit, metadata, cast_range, anchor_unit, anchor_pos)
        if ally then
            SafeCastTarget(unit, ability, ally)
            agent.last_action = metadata and metadata.message or "Поддерживаю союзника"
            agent.next_order_time = now + runtime.config.order_cooldown
            return true
        end
    end

    return false
end

local function TryCastAbilities(unit, agent, now, current_target, anchor_unit, anchor_pos)
    if NPC.IsChannellingAbility and NPC.IsChannellingAbility(unit) then
        agent.state = STATES.ENGAGE
        agent.last_action = "Канализирую"
        agent.next_order_time = now + runtime.config.channel_wait
        return true
    end

    for slot = 0, 23 do
        local ability = NPC.GetAbilityByIndex(unit, slot)
        if ability then
            local name = Ability.GetName(ability)
            local metadata = ABILITY_DATA[name]
            if metadata then
                if TryCastAbility(unit, agent, now, ability, metadata, current_target, anchor_unit, anchor_pos) then
                    return true
                end
            end
        end
    end

    return false
end

-------------------------------------------------------------------------------
-- Agent management
-------------------------------------------------------------------------------
local function CreateAgent(unit)
    return {
        unit = unit,
        handle = Entity.GetIndex(unit),
        state = STATES.FOLLOW,
        last_action = "Инициализация",
        next_order_time = 0,
        manual_until = 0,
        current_target = nil,
    }
end

local function MoveToPosition(unit, position, agent, now)
    SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, position, nil)
    agent.state = STATES.FOLLOW
    agent.last_action = "Следую к герою"
    agent.next_order_time = now + runtime.config.order_cooldown
end

local function HoldPosition(unit, agent, now)
    SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_HOLD_POSITION, nil, Entity.GetAbsOrigin(unit), nil)
    agent.state = STATES.FOLLOW
    agent.last_action = "Ожидаю"
    agent.next_order_time = now + runtime.config.order_cooldown
end

local function AttackTarget(unit, target, agent, now)
    SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, target, nil, nil)
    agent.state = STATES.ENGAGE
    local target_name = NPC.GetUnitName(target) or "цель"
    agent.last_action = string.format("Атакую %s", target_name)
    agent.current_target = target
    agent.next_order_time = now + runtime.config.order_cooldown
end

local function AcquireAttackTarget(unit, anchor_pos)
    local radius = runtime.config.attack_radius or 900
    local unit_pos = Entity.GetAbsOrigin(unit)
    local centers = {}
    if unit_pos then
        centers[#centers + 1] = unit_pos
    end
    if anchor_pos then
        centers[#centers + 1] = anchor_pos
    end

    local best_target
    local best_score = -math.huge

    for _, center in ipairs(centers) do
        local enemies = NPCs.InRadius(center, radius, runtime.team, Enum.TeamType.TEAM_ENEMY) or {}
        for _, enemy in ipairs(enemies) do
            if Entity.IsAlive(enemy) and Entity.GetTeamNum(enemy) ~= runtime.team and (not NPC.IsCourier(enemy)) then
                local pos = Entity.GetAbsOrigin(enemy)
                if pos then
                    local distance = center:Distance(pos)
                    local score = -distance
                    if NPC.IsHero(enemy) then
                        score = score + 400
                    end
                    local idx = Entity.GetIndex(enemy)
                    if runtime.threat_expiry[idx] and runtime.threat_expiry[idx] > GlobalVars.GetCurTime() then
                        score = score + 200
                    end
                    if score > best_score then
                        best_score = score
                        best_target = enemy
                    end
                end
            end
        end

        local neutrals = NPCs.InRadius(center, radius, runtime.team, Enum.TeamType.TEAM_NEUTRAL) or {}
        for _, enemy in ipairs(neutrals) do
            if Entity.IsAlive(enemy) then
                local pos = Entity.GetAbsOrigin(enemy)
                if pos then
                    local distance = center:Distance(pos)
                    local score = -distance
                    if score > best_score then
                        best_score = score
                        best_target = enemy
                    end
                end
            end
        end
    end

    return best_target
end

local function ProcessAgent(agent, now)
    local unit = agent.unit
    if not unit or not Entity.IsAlive(unit) then
        return
    end

    local manual_remaining = agent.manual_until - now
    if manual_remaining > 0 then
        agent.state = STATES.MANUAL
        agent.last_action = string.format("Ручное управление (%.1f)", manual_remaining)
        return
    end

    if now < agent.next_order_time then
        return
    end

    local anchor_unit = runtime.hero
    local anchor_pos = anchor_unit and Entity.GetAbsOrigin(anchor_unit)
    local current_target = agent.current_target

    if TryCastAbilities(unit, agent, now, current_target, anchor_unit, anchor_pos) then
        return
    end

    if agent.current_target and (not Entity.IsAlive(agent.current_target) or Entity.GetTeamNum(agent.current_target) == runtime.team) then
        agent.current_target = nil
    end

    local target = AcquireAttackTarget(unit, anchor_pos)
    if target then
        AttackTarget(unit, target, agent, now)
        return
    end

    if anchor_pos then
        local unit_pos = Entity.GetAbsOrigin(unit)
        if unit_pos then
            local distance = unit_pos:Distance(anchor_pos)
            if distance > runtime.config.follow_distance then
                MoveToPosition(unit, anchor_pos, agent, now)
                return
            end
        end
        HoldPosition(unit, agent, now)
    else
        HoldPosition(unit, agent, now)
    end
end

-------------------------------------------------------------------------------
-- Unit filtering
-------------------------------------------------------------------------------
local function ShouldManageUnit(unit)
    if not unit or not Entity.IsAlive(unit) then
        return false
    end

    if unit == runtime.hero then
        return false
    end

    if NPC.IsCourier and NPC.IsCourier(unit) then
        return false
    end

    if Entity.GetTeamNum(unit) ~= runtime.team then
        return false
    end

    if runtime.player_id and NPC.IsControllableByPlayer and NPC.IsControllableByPlayer(unit, runtime.player_id) then
        return true
    end

    local owner_id = GetPlayerOwnerID(unit)
    if owner_id and runtime.player_id and owner_id == runtime.player_id then
        return true
    end
    if owner_id and runtime.hero_owner_id and owner_id == runtime.hero_owner_id then
        return true
    end

    if IsOwnedByHero(unit) then
        return true
    end

    return false
end

-------------------------------------------------------------------------------
-- Callbacks
-------------------------------------------------------------------------------
function agent_script.OnUpdate()
    if not Engine.IsInGame() then
        ResetRuntime()
        return
    end

    EnsureMenu()
    ReadConfig()

    if not runtime.config.enabled then
        runtime.agents = {}
        return
    end

    if not UpdateHeroContext() then
        return
    end

    local player = AcquirePlayerHandle()
    if not player then
        runtime.agents = {}
        return
    end

    local now = GlobalVars.GetCurTime()
    local next_agents = {}

    for _, unit in ipairs(NPCs.GetAll()) do
        if ShouldManageUnit(unit) then
            local handle = Entity.GetIndex(unit)
            local agent = runtime.agents[handle]
            if not agent then
                agent = CreateAgent(unit)
            end
            agent.unit = unit
            agent.handle = handle
            ProcessAgent(agent, now)
            next_agents[handle] = agent
        end
    end

    runtime.agents = next_agents
end

function agent_script.OnDraw()
    if not runtime.config or not runtime.config.debug then
        return
    end

    local font = EnsureFont()
    for _, agent in pairs(runtime.agents) do
        local unit = agent.unit
        if unit and Entity.IsAlive(unit) then
            local origin = Entity.GetAbsOrigin(unit)
            local offset = NPC.GetHealthBarOffset(unit) or 0
            if origin then
                local screen_pos, visible = Render.WorldToScreen(origin + Vector(0, 0, offset + 32))
                if visible then
                    local line1 = string.format("[%s]", agent.state or "?")
                    local line2 = agent.last_action or ""
                    local color = Color(180, 220, 255, 255)
                    if agent.state == STATES.MANUAL then
                        color = Color(255, 165, 0, 255)
                    elseif agent.state == STATES.ENGAGE then
                        color = Color(255, 90, 90, 255)
                    end
                    local size1 = Render.TextSize(font, 16, line1)
                    Render.Text(font, 16, line1, Vec2(screen_pos.x - size1.x / 2, screen_pos.y), color)
                    local size2 = Render.TextSize(font, 14, line2)
                    Render.Text(font, 14, line2, Vec2(screen_pos.x - size2.x / 2, screen_pos.y + 18), Color(240, 240, 240, 255))
                end
            end
        end
    end
end

local function FlagManualControl(unit)
    if not unit then
        return
    end
    local handle = Entity.GetIndex(unit)
    local agent = runtime.agents[handle]
    if agent then
        agent.manual_until = GlobalVars.GetCurTime() + runtime.config.manual_override
        agent.state = STATES.MANUAL
        agent.last_action = "Ручное управление"
    end
end

function agent_script.OnPrepareUnitOrders(data)
    if not runtime.config or not runtime.config.enabled then
        return true
    end

    local player = data.player or AcquirePlayerHandle()
    if not player then
        return true
    end

    if data.orderIssuer == Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY then
        if data.npc then
            FlagManualControl(data.npc)
        end
        return true
    end

    local selected = Player.GetSelectedUnits and Player.GetSelectedUnits(player)
    if selected then
        for _, unit in ipairs(selected) do
            FlagManualControl(unit)
        end
    end

    return true
end

function agent_script.OnEntityHurt(data)
    if not runtime.config or not runtime.config.enabled then
        return
    end

    if not data or not data.target or not data.source then
        return
    end

    if runtime.hero and data.target == runtime.hero then
        local idx = Entity.GetIndex(data.source)
        runtime.threat_expiry[idx] = GlobalVars.GetCurTime() + 3
    end
end

function agent_script.OnGameEnd()
    ResetRuntime()
end

return agent_script
