local commander = { ui = {} }

local menu_info = {
    first_tab = "Utility",
    section = "Unit Commander",
    second_tab = "General",
    third_tab = "",
    group = "Настройки",
}

local runtime = {
    hero = nil,
    team = nil,
    player_id = nil,
    player = nil,
    agents = {},
    focus_target = nil,
    threat_memory = {},
    last_focus_check = 0,
}

local STATES = {
    FOLLOW = "FOLLOW",
    CHASE = "CHASE",
    HOLD = "HOLD",
    MANUAL = "MANUAL",
    CASTING = "CASTING",
}

local DEFAULTS = {
    follow_distance = 425,
    attack_radius = 900,
    order_cooldown = 0.3,
    cast_cooldown = 0.2,
    manual_lock = 1.2,
    dominator_range = 900,
}

local DOMINATOR_ITEMS = {
    item_helm_of_the_dominator = true,
    item_helm_of_the_overlord = true,
}

local DOMINATOR_PRIORITY = {
    npc_dota_neutral_black_dragon = 600,
    npc_dota_neutral_granite_golem = 590,
    npc_dota_neutral_rock_golem = 560,
    npc_dota_neutral_elder_jungle_stalker = 540,
    npc_dota_neutral_prowler_acolyte = 520,
    npc_dota_neutral_big_thunder_lizard = 500,
    npc_dota_neutral_dark_troll_warlord = 480,
    npc_dota_neutral_enraged_wildkin = 470,
    npc_dota_neutral_polar_furbolg_ursa_warrior = 460,
    npc_dota_neutral_polar_furbolg_champion = 450,
    npc_dota_neutral_satyr_hellcaller = 440,
    npc_dota_neutral_centaur_khan = 420,
    npc_dota_neutral_ogre_magi = 400,
    npc_dota_neutral_ogre_mauler = 390,
    npc_dota_neutral_mud_golem = 360,
    npc_dota_neutral_wildkin = 340,
    npc_dota_neutral_fel_beast = 320,
    npc_dota_neutral_harpy_storm = 310,
    npc_dota_neutral_harpy_scout = 280,
    npc_dota_neutral_satyr_trickster = 260,
    npc_dota_neutral_satyr_soulstealer = 250,
}

local ANCIENT_UNITS = {
    npc_dota_neutral_black_dragon = true,
    npc_dota_neutral_granite_golem = true,
    npc_dota_neutral_rock_golem = true,
    npc_dota_neutral_elder_jungle_stalker = true,
    npc_dota_neutral_big_thunder_lizard = true,
    npc_dota_neutral_prowler_acolyte = true,
}

local ABILITY_DATA = {}

local SafeOrder

local function RegisterAbility(name, data)
    ABILITY_DATA[name] = data
    if data.aliases then
        for _, alias in ipairs(data.aliases) do
            ABILITY_DATA[alias] = data
        end
    end
end

RegisterAbility("mud_golem_hurl_boulder", {
    behavior = "target",
    allow_neutrals = true,
    min_interval = 0.4,
    score = 30,
    aliases = {
        "granite_golem_hurl_boulder",
        "ancient_rock_golem_hurl_boulder",
    },
})

RegisterAbility("dark_troll_warlord_ensnare", {
    behavior = "target",
    allow_neutrals = true,
    min_interval = 0.6,
    score = 25,
})

RegisterAbility("dark_troll_warlord_raise_dead", {
    behavior = "no_target",
    always_cast = true,
    min_interval = 9,
    score = 15,
})

RegisterAbility("forest_troll_high_priest_heal", {
    behavior = "ally",
    prefer_hero = true,
    ally_max_health = 0.92,
    min_interval = 1.5,
})

RegisterAbility("centaur_khan_war_stomp", {
    behavior = "no_target",
    radius = 315,
    min_enemies = 1,
    allow_neutrals = true,
    score = 30,
})

RegisterAbility("centaur_conqueror_war_stomp", {
    behavior = "no_target",
    radius = 315,
    min_enemies = 1,
    allow_neutrals = true,
    score = 30,
})

RegisterAbility("polar_furbolg_ursa_warrior_thunder_clap", {
    behavior = "no_target",
    radius = 325,
    min_enemies = 1,
    allow_neutrals = true,
    score = 24,
    aliases = {
        "polar_furbolg_champion_thunder_clap",
    },
})

RegisterAbility("hellbear_smasher_slam", {
    behavior = "no_target",
    radius = 325,
    min_enemies = 1,
    allow_neutrals = true,
    score = 24,
})

RegisterAbility("ogre_bruiser_ogre_smash", {
    behavior = "point",
    allow_neutrals = true,
    range_bonus = 50,
    min_interval = 1.0,
    score = 28,
    aliases = {
        "ogre_mauler_smash",
    },
})

RegisterAbility("ogre_magi_frost_armor", {
    behavior = "ally",
    prefer_hero = true,
    ally_max_health = 0.95,
    avoid_modifier = "modifier_ogre_magi_frost_armor",
    min_interval = 5,
    aliases = {
        "neutral_ogre_magi_ice_armor",
    },
})

RegisterAbility("satyr_hellcaller_shockwave", {
    behavior = "point",
    allow_neutrals = true,
    min_interval = 0.7,
    score = 26,
})

RegisterAbility("satyr_trickster_purge", {
    behavior = "target",
    allow_neutrals = true,
    min_interval = 4,
    score = 10,
})

RegisterAbility("satyr_soulstealer_mana_burn", {
    behavior = "target",
    only_heroes = true,
    min_interval = 4,
    score = 12,
    aliases = {
        "satyr_mindstealer_mana_burn",
    },
})

RegisterAbility("harpy_storm_chain_lightning", {
    behavior = "target",
    allow_neutrals = true,
    min_interval = 2.5,
    score = 16,
})

RegisterAbility("harpy_scout_chain_lightning", {
    behavior = "target",
    allow_neutrals = true,
    min_interval = 2.5,
    score = 12,
})

RegisterAbility("enraged_wildkin_tornado", {
    behavior = "point",
    allow_neutrals = true,
    min_interval = 5,
    score = 20,
    aliases = {
        "wildkin_tornado",
    },
})

RegisterAbility("wildkin_hurricane", {
    behavior = "point",
    allow_neutrals = true,
    min_interval = 6,
    score = 15,
})

RegisterAbility("fel_beast_haunt", {
    behavior = "target",
    allow_neutrals = true,
    min_interval = 4,
    score = 14,
})

RegisterAbility("ancient_black_dragon_fireball", {
    behavior = "point",
    allow_neutrals = true,
    min_interval = 4,
    score = 34,
    aliases = {
        "black_dragon_fireball",
    },
})

RegisterAbility("ancient_black_drake_fireball", {
    behavior = "point",
    allow_neutrals = true,
    min_interval = 4.5,
    score = 22,
})

RegisterAbility("ancient_thunderhide_slam", {
    behavior = "no_target",
    radius = 315,
    min_enemies = 1,
    allow_neutrals = true,
    score = 32,
    aliases = {
        "big_thunder_lizard_slam",
    },
})

RegisterAbility("ancient_thunderhide_frenzy", {
    behavior = "ally",
    prefer_hero = true,
    include_self = false,
    min_interval = 6,
    score = 18,
    aliases = {
        "big_thunder_lizard_frenzy",
    },
})

RegisterAbility("ancient_rumblehide_piercing_roar", {
    behavior = "no_target",
    radius = 300,
    min_enemies = 1,
    allow_neutrals = true,
    min_interval = 6,
    score = 20,
})

RegisterAbility("prowler_acolyte_heal", {
    behavior = "ally",
    prefer_hero = true,
    ally_max_health = 0.85,
    min_interval = 3,
    score = 18,
})

RegisterAbility("alpha_wolf_command_aura", {
    behavior = "ally",
    prefer_hero = true,
    include_self = false,
    min_interval = 6,
    score = 8,
})

RegisterAbility("kobold_taskmaster_speed_aura", {
    behavior = "no_target",
    always_cast = true,
    min_interval = 6,
    score = 6,
})

RegisterAbility("ghost_frost_attack", {
    behavior = "target",
    allow_neutrals = true,
    min_interval = 3,
    score = 8,
})

RegisterAbility("ogre_seer_bloodlust", {
    behavior = "ally",
    prefer_hero = true,
    include_self = true,
    min_interval = 4,
    score = 18,
})

RegisterAbility("dark_troll_priest_heal", {
    behavior = "ally",
    prefer_hero = true,
    ally_max_health = 0.9,
    min_interval = 1.8,
    score = 14,
})

local function EnsureMenu()
    if commander.menu_ready then
        return
    end

    if not Menu or not Menu.Create then
        return
    end

    local ok, group = pcall(
        Menu.Create,
        menu_info.first_tab,
        menu_info.section,
        menu_info.second_tab,
        menu_info.third_tab,
        menu_info.group
    )

    if not ok or not group then
        return
    end

    commander.ui.group = group
    commander.ui.enable = group:Switch("Включить", true)
    commander.ui.debug = group:Switch("Отладочная информация", false)
    commander.ui.follow_distance = group:Slider("Дистанция следования", 150, 1200, DEFAULTS.follow_distance, "%d")
    commander.ui.attack_radius = group:Slider("Радиус атаки", 300, 2000, DEFAULTS.attack_radius, "%d")
    commander.ui.order_cooldown = group:Slider(
        "Задержка приказов (мс)",
        80,
        600,
        math.floor(DEFAULTS.order_cooldown * 1000),
        "%d"
    )
    commander.ui.cast_cooldown = group:Slider(
        "Пауза между кастами (мс)",
        80,
        500,
        math.floor(DEFAULTS.cast_cooldown * 1000),
        "%d"
    )
    commander.ui.manual_lock = group:Slider(
        "Ручной контроль (мс)",
        300,
        2500,
        math.floor(DEFAULTS.manual_lock * 1000),
        "%d"
    )
    commander.ui.dominator = group:Switch("Автоиспользование Доминирования", true)

    commander.menu_ready = true
end

local function MenuEnabled()
    EnsureMenu()
    if commander.ui.enable and commander.ui.enable.Get then
        return commander.ui.enable:Get()
    end
    return true
end

local function ReadConfig()
    EnsureMenu()
    runtime.config = runtime.config or {}

    if not commander.ui.enable then
        runtime.config.debug = false
        runtime.config.follow_distance = DEFAULTS.follow_distance
        runtime.config.attack_radius = DEFAULTS.attack_radius
        runtime.config.order_cooldown = DEFAULTS.order_cooldown
        runtime.config.cast_cooldown = DEFAULTS.cast_cooldown
        runtime.config.manual_lock = DEFAULTS.manual_lock
        runtime.config.auto_dominate = true
        return
    end

    local function slider_value(widget, default_value)
        if widget and widget.Get then
            local value = widget:Get()
            if value ~= nil then
                return value
            end
        end
        return default_value
    end

    local function switch_value(widget, default_value)
        if widget and widget.Get then
            local value = widget:Get()
            if value ~= nil then
                return value
            end
        end
        return default_value
    end

    runtime.config.debug = switch_value(commander.ui.debug, false)
    runtime.config.follow_distance = slider_value(commander.ui.follow_distance, DEFAULTS.follow_distance)
    runtime.config.attack_radius = slider_value(commander.ui.attack_radius, DEFAULTS.attack_radius)
    runtime.config.order_cooldown = slider_value(commander.ui.order_cooldown, math.floor(DEFAULTS.order_cooldown * 1000)) / 1000
    runtime.config.cast_cooldown = slider_value(commander.ui.cast_cooldown, math.floor(DEFAULTS.cast_cooldown * 1000)) / 1000
    runtime.config.manual_lock = slider_value(commander.ui.manual_lock, math.floor(DEFAULTS.manual_lock * 1000)) / 1000
    runtime.config.auto_dominate = switch_value(commander.ui.dominator, true)
end

local function ResetRuntime()
    runtime.hero = nil
    runtime.team = nil
    runtime.player_id = nil
    runtime.player = nil
    runtime.agents = {}
    runtime.focus_target = nil
    runtime.threat_memory = {}
    runtime.last_focus_check = 0
end

local function Distance(a, b)
    if not a or not b then
        return math.huge
    end
    if a.Distance then
        return a:Distance(b)
    end
    local ax = a.GetX and a:GetX() or a.x or a[1] or 0
    local ay = a.GetY and a:GetY() or a.y or a[2] or 0
    local az = a.GetZ and a:GetZ() or a.z or a[3] or 0
    local bx = b.GetX and b:GetX() or b.x or b[1] or 0
    local by = b.GetY and b:GetY() or b.y or b[2] or 0
    local bz = b.GetZ and b:GetZ() or b.z or b[3] or 0
    local dx = ax - bx
    local dy = ay - by
    local dz = az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function AcquirePlayer()
    if runtime.player and runtime.player_id then
        return runtime.player
    end

    if runtime.player_id and PlayerResource and PlayerResource.GetPlayer then
        runtime.player = PlayerResource.GetPlayer(runtime.player_id)
        if runtime.player then
            return runtime.player
        end
    end

    if Players and Players.GetLocal then
        runtime.player = Players.GetLocal()
        if runtime.player then
            if Player and Player.GetPlayerID then
                runtime.player_id = Player.GetPlayerID(runtime.player)
            end
            return runtime.player
        end
    end

    return nil
end

local function UpdateHeroContext()
    local hero = Heroes and Heroes.GetLocal and Heroes.GetLocal() or nil
    if not hero or not Entity.IsAlive(hero) then
        ResetRuntime()
        return false
    end

    runtime.hero = hero
    runtime.team = Entity.GetTeamNum(hero)

    if runtime.player_id == nil then
        if Hero and Hero.GetPlayerID then
            runtime.player_id = Hero.GetPlayerID(hero)
        end
    end

    AcquirePlayer()
    return true
end

local function GetAbilityCharges(ability)
    if not ability then
        return nil
    end

    if Ability.GetCurrentAbilityCharges then
        return Ability.GetCurrentAbilityCharges(ability)
    end
    if Ability.GetCurrentCharges then
        return Ability.GetCurrentCharges(ability)
    end
    if Ability.GetRemainingCharges then
        return Ability.GetRemainingCharges(ability)
    end
    if Ability.GetCharges then
        return Ability.GetCharges(ability)
    end

    return nil
end

local function IsAbilityReady(unit, ability, metadata)
    if not ability then
        return false
    end

    if Ability.IsHidden and Ability.IsHidden(ability) then
        return false
    end

    if Ability.IsPassive and Ability.IsPassive(ability) then
        return false
    end

    if Ability.GetLevel and Ability.GetLevel(ability) <= 0 then
        return false
    end

    local cooldown = Ability.GetCooldownTimeRemaining and Ability.GetCooldownTimeRemaining(ability) or 0
    if cooldown > 0 then
        return false
    end

    if metadata and metadata.requires_charges then
        local charges = GetAbilityCharges(ability)
        if not charges or charges <= 0 then
            return false
        end
    end

    if metadata and metadata.ignore_mana then
        return Ability.IsReady(ability)
    end

    if Ability.IsCastable then
        return Ability.IsCastable(ability, NPC.GetMana(unit))
    end
    if Ability.IsReady then
        return Ability.IsReady(ability)
    end
    return false
end

local function GetCastRange(unit, ability, metadata)
    if metadata and metadata.range then
        return metadata.range
    end
    local range = Ability.GetCastRange(ability)
    if range and range > 0 then
        if NPC.HasItem and NPC.HasItem(unit, "item_aether_lens", true) then
            range = range + 225
        end
        if metadata and metadata.range_bonus then
            range = range + metadata.range_bonus
        end
        return range
    end
    if metadata and metadata.range_bonus then
        return 600 + metadata.range_bonus
    end
    return 600
end

local function IsValidEnemy(enemy)
    if not enemy or not Entity.IsAlive(enemy) then
        return false
    end
    if Entity.GetTeamNum(enemy) == runtime.team then
        return false
    end
    if NPC.IsCourier(enemy) then
        return false
    end
    return true
end

local function IsValidAlly(ally)
    if not ally or not Entity.IsAlive(ally) then
        return false
    end
    if Entity.GetTeamNum(ally) ~= runtime.team then
        return false
    end
    return true
end

local function CountEnemiesAround(position, radius, metadata)
    if not position then
        return 0
    end
    local total = 0
    local enemies = NPCs.InRadius(position, radius, runtime.team, Enum.TeamType.TEAM_ENEMY) or {}
    for _, enemy in ipairs(enemies) do
        if IsValidEnemy(enemy) then
            if metadata and metadata.only_heroes and not NPC.IsHero(enemy) then
                goto continue
            end
            total = total + 1
        end
        ::continue::
    end

    if metadata and metadata.allow_neutrals then
        local neutrals = NPCs.InRadius(position, radius, runtime.team, Enum.TeamType.TEAM_NEUTRAL) or {}
        for _, enemy in ipairs(neutrals) do
            if Entity.IsAlive(enemy) then
                total = total + 1
            end
        end
    end
    return total
end

local function FindEnemyTarget(unit, metadata, cast_range, anchor_position, focus_target)
    if focus_target and IsValidEnemy(focus_target) then
        local pos = Entity.GetAbsOrigin(focus_target)
        local unit_pos = Entity.GetAbsOrigin(unit)
        if pos and unit_pos and Distance(pos, unit_pos) <= cast_range + (metadata and metadata.range_bonus or 0) then
            if not metadata or not metadata.only_heroes or NPC.IsHero(focus_target) then
                return focus_target
            end
        end
    end

    local origin = Entity.GetAbsOrigin(unit)
    local centers = {}
    if origin then
        table.insert(centers, origin)
    end
    if anchor_position then
        table.insert(centers, anchor_position)
    end

    local best_target = nil
    local best_score = -math.huge

    for _, center in ipairs(centers) do
        local enemies = NPCs.InRadius(center, cast_range + (metadata and metadata.range_bonus or 0), runtime.team, Enum.TeamType.TEAM_ENEMY) or {}
        for _, enemy in ipairs(enemies) do
            if IsValidEnemy(enemy) then
                if metadata and metadata.only_heroes and not NPC.IsHero(enemy) then
                    goto continue_enemy
                end
                local enemy_pos = Entity.GetAbsOrigin(enemy)
                if enemy_pos then
                    local distance = Distance(center, enemy_pos)
                    if distance <= cast_range + (metadata and metadata.range_bonus or 0) then
                        local score = -distance
                        if NPC.IsHero(enemy) then
                            score = score + 250
                        end
                        local idx = Entity.GetIndex(enemy)
                        if runtime.threat_memory[idx] and runtime.threat_memory[idx] > GlobalVars.GetCurTime() then
                            score = score + 120
                        end
                        if metadata and metadata.score then
                            score = score + metadata.score
                        end
                        if score > best_score then
                            best_score = score
                            best_target = enemy
                        end
                    end
                end
            end
            ::continue_enemy::
        end
        if metadata and metadata.allow_neutrals then
            local neutrals = NPCs.InRadius(center, cast_range + (metadata.range_bonus or 0), runtime.team, Enum.TeamType.TEAM_NEUTRAL) or {}
            for _, neutral in ipairs(neutrals) do
                if Entity.IsAlive(neutral) then
                    local neutral_pos = Entity.GetAbsOrigin(neutral)
                    if neutral_pos then
                        local distance = Distance(center, neutral_pos)
                        if distance <= cast_range + (metadata and metadata.range_bonus or 0) then
                            local score = -distance + (metadata and metadata.score or 0)
                            if score > best_score then
                                best_score = score
                                best_target = neutral
                            end
                        end
                    end
                end
            end
        end
    end

    return best_target
end

local function FindAllyTarget(unit, metadata, cast_range, anchor_unit, anchor_position)
    if metadata and metadata.prefer_hero and runtime.hero and IsValidAlly(runtime.hero) then
        local hero_pos = Entity.GetAbsOrigin(runtime.hero)
        local unit_pos = Entity.GetAbsOrigin(unit)
        if hero_pos and unit_pos and Distance(hero_pos, unit_pos) <= cast_range + (metadata and metadata.range_bonus or 0) then
            if not metadata.ally_max_health or (Entity.GetHealth(runtime.hero) / math.max(1, Entity.GetMaxHealth(runtime.hero))) <= metadata.ally_max_health then
                if not metadata.avoid_modifier or not NPC.HasModifier(runtime.hero, metadata.avoid_modifier) then
                    return runtime.hero
                end
            end
        end
    end

    if anchor_unit and metadata and metadata.prefer_anchor and IsValidAlly(anchor_unit) then
        local anchor_pos = anchor_position or Entity.GetAbsOrigin(anchor_unit)
        local unit_pos = Entity.GetAbsOrigin(unit)
        if anchor_pos and unit_pos and Distance(anchor_pos, unit_pos) <= cast_range + (metadata and metadata.range_bonus or 0) then
            return anchor_unit
        end
    end

    local unit_pos = Entity.GetAbsOrigin(unit)
    if not unit_pos then
        return nil
    end

    local best_target = nil
    local best_score = -math.huge
    local allies = NPCs.InRadius(unit_pos, cast_range + (metadata and metadata.range_bonus or 0), runtime.team, Enum.TeamType.TEAM_FRIEND) or {}
    for _, ally in ipairs(allies) do
        if IsValidAlly(ally) then
            if metadata and metadata.include_self == false and ally == unit then
                goto continue_ally
            end
            if metadata and metadata.avoid_modifier and NPC.HasModifier(ally, metadata.avoid_modifier) then
                goto continue_ally
            end
            if metadata and metadata.ally_max_health then
                local health = Entity.GetHealth(ally)
                local max_health = Entity.GetMaxHealth(ally)
                if max_health > 0 and health / max_health > metadata.ally_max_health then
                    goto continue_ally
                end
            end
            local ally_pos = Entity.GetAbsOrigin(ally)
            if ally_pos then
                local distance = Distance(unit_pos, ally_pos)
                if distance <= cast_range + (metadata and metadata.range_bonus or 0) then
                    local score = -distance
                    if NPC.IsHero(ally) then
                        score = score + 150
                    end
                    if metadata and metadata.score then
                        score = score + metadata.score
                    end
                    if score > best_score then
                        best_score = score
                        best_target = ally
                    end
                end
            end
        end
        ::continue_ally::
    end

    return best_target
end

local function CastAbility(unit, ability, metadata, target, position)
    if metadata.behavior == "target" or metadata.behavior == "ally" then
        if target then
            if Ability.CastTarget then
                Ability.CastTarget(ability, target)
            else
                SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET, target, nil)
            end
            return true
        end
    elseif metadata.behavior == "point" then
        if position then
            if Ability.CastPosition then
                Ability.CastPosition(ability, position)
            else
                SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION, nil, position)
            end
            return true
        end
    elseif metadata.behavior == "no_target" then
        if Ability.CastNoTarget then
            Ability.CastNoTarget(ability)
        else
            SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, nil)
        end
        return true
    end
    return false
end

local function ShouldCastNoTarget(unit, ability, metadata)
    if metadata.always_cast then
        return true
    end
    local radius = metadata.radius or Ability.GetAOERadius(ability) or 250
    local unit_pos = Entity.GetAbsOrigin(unit)
    if not unit_pos then
        return false
    end
    local enemies = CountEnemiesAround(unit_pos, radius, metadata)
    local threshold = metadata.min_enemies or 1
    return enemies >= threshold
end

local function TryCastAbility(unit, agent, now, ability, metadata, anchor_position, focus_target)
    if not IsAbilityReady(unit, ability, metadata) then
        return false
    end

    agent.last_cast = agent.last_cast or {}
    local ability_name = Ability.GetName(ability)
    local next_allowed = agent.last_cast[ability_name] or 0
    if now < next_allowed then
        return false
    end

    local cast_range = GetCastRange(unit, ability, metadata)
    local success = false

    if metadata.behavior == "target" then
        local target = FindEnemyTarget(unit, metadata, cast_range, anchor_position, focus_target)
        if target then
            success = CastAbility(unit, ability, metadata, target, Entity.GetAbsOrigin(target))
        end
    elseif metadata.behavior == "point" then
        local target = FindEnemyTarget(unit, metadata, cast_range, anchor_position, focus_target)
        local pos = target and Entity.GetAbsOrigin(target)
        if metadata.always_cast and not pos then
            pos = Entity.GetAbsOrigin(unit)
        end
        if pos then
            success = CastAbility(unit, ability, metadata, nil, pos)
        end
    elseif metadata.behavior == "ally" then
        local ally = FindAllyTarget(unit, metadata, cast_range, runtime.hero, anchor_position)
        if ally then
            success = CastAbility(unit, ability, metadata, ally, Entity.GetAbsOrigin(ally))
        end
    elseif metadata.behavior == "no_target" then
        if ShouldCastNoTarget(unit, ability, metadata) then
            success = CastAbility(unit, ability, metadata)
        end
    end

    if success then
        agent.state = STATES.CASTING
        agent.last_action = "cast " .. ability_name
        agent.next_order = now + runtime.config.order_cooldown
        agent.last_cast[ability_name] = now + (metadata.min_interval or runtime.config.cast_cooldown)
        return true
    end

    return false
end

local function TryCastAbilities(unit, agent, now, anchor_position, focus_target)
    for slot = 0, 23 do
        local ability = NPC.GetAbilityByIndex(unit, slot)
        if ability then
            local name = Ability.GetName(ability)
            local metadata = ABILITY_DATA[name]
            if metadata then
                if TryCastAbility(unit, agent, now, ability, metadata, anchor_position, focus_target) then
                    return true
                end
            end
        end
    end
    return false
end

SafeOrder = function(unit, order, target, position)
    local player = AcquirePlayer()
    if not player then
        return
    end
    Player.PrepareUnitOrders(
        player,
        order,
        target,
        position,
        nil,
        Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY,
        unit
    )
end

local function Attack(unit, agent, target, now)
    SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, target, nil)
    agent.state = STATES.CHASE
    agent.last_action = "attack"
    agent.next_order = now + runtime.config.order_cooldown
    agent.current_target = target
end

local function MoveTo(unit, agent, position, now)
    SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, position)
    agent.state = STATES.FOLLOW
    agent.last_action = "follow"
    agent.next_order = now + runtime.config.order_cooldown
end

local function Hold(unit, agent, now)
    SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_HOLD_POSITION, nil, Entity.GetAbsOrigin(unit))
    agent.state = STATES.HOLD
    agent.last_action = "hold"
    agent.next_order = now + runtime.config.order_cooldown
end

local function AcquireAttackTarget(unit, anchor_position, focus_target)
    if focus_target and IsValidEnemy(focus_target) then
        local pos = Entity.GetAbsOrigin(focus_target)
        local unit_pos = Entity.GetAbsOrigin(unit)
        if pos and unit_pos and Distance(pos, unit_pos) <= runtime.config.attack_radius + 200 then
            return focus_target
        end
    end

    local best_target = nil
    local best_score = -math.huge
    local origin = Entity.GetAbsOrigin(unit)
    local centers = {}
    if origin then
        table.insert(centers, origin)
    end
    if anchor_position then
        table.insert(centers, anchor_position)
    end

    for _, center in ipairs(centers) do
        local enemies = NPCs.InRadius(center, runtime.config.attack_radius, runtime.team, Enum.TeamType.TEAM_ENEMY) or {}
        for _, enemy in ipairs(enemies) do
            if IsValidEnemy(enemy) then
                local enemy_pos = Entity.GetAbsOrigin(enemy)
                if enemy_pos then
                    local distance = Distance(center, enemy_pos)
                    if distance <= runtime.config.attack_radius then
                        local score = -distance
                        if NPC.IsHero(enemy) then
                            score = score + 400
                        end
                        local idx = Entity.GetIndex(enemy)
                        if runtime.threat_memory[idx] and runtime.threat_memory[idx] > GlobalVars.GetCurTime() then
                            score = score + 200
                        end
                        if score > best_score then
                            best_score = score
                            best_target = enemy
                        end
                    end
                end
            end
        end
    end

    return best_target
end

local function ShouldManage(unit)
    if not unit or not Entity.IsAlive(unit) then
        return false
    end
    if runtime.hero and unit == runtime.hero then
        return false
    end
    if NPC.IsCourier(unit) then
        return false
    end
    if Entity.GetTeamNum(unit) ~= runtime.team then
        return false
    end
    if runtime.player_id and NPC.IsControllableByPlayer and NPC.IsControllableByPlayer(unit, runtime.player_id) then
        return true
    end
    if Entity.GetOwner and Entity.GetOwner(unit) == runtime.hero then
        return true
    end
    return false
end

local function ProcessAgent(agent, now)
    local unit = agent.unit
    if not unit or not Entity.IsAlive(unit) then
        return
    end

    if agent.manual_until and agent.manual_until > now then
        agent.state = STATES.MANUAL
        agent.last_action = "manual"
        return
    end

    if agent.next_order and agent.next_order > now then
        return
    end

    local anchor_pos = runtime.hero and Entity.GetAbsOrigin(runtime.hero) or nil
    local focus_target = runtime.focus_target

    if TryCastAbilities(unit, agent, now, anchor_pos, focus_target) then
        return
    end

    if agent.current_target and (not IsValidEnemy(agent.current_target) or Distance(Entity.GetAbsOrigin(agent.current_target), Entity.GetAbsOrigin(unit)) > runtime.config.attack_radius * 1.5) then
        agent.current_target = nil
    end

    local target = AcquireAttackTarget(unit, anchor_pos, focus_target)
    if target then
        Attack(unit, agent, target, now)
        return
    end

    if anchor_pos then
        local unit_pos = Entity.GetAbsOrigin(unit)
        if unit_pos then
            local distance = Distance(unit_pos, anchor_pos)
            if distance > runtime.config.follow_distance then
                MoveTo(unit, agent, anchor_pos, now)
            else
                Hold(unit, agent, now)
            end
        end
    else
        Hold(unit, agent, now)
    end
end

local function TrackFocusTarget(now)
    if not runtime.hero then
        runtime.focus_target = nil
        return
    end
    if runtime.focus_target and (not IsValidEnemy(runtime.focus_target) or Distance(Entity.GetAbsOrigin(runtime.focus_target), Entity.GetAbsOrigin(runtime.hero)) > runtime.config.attack_radius * 1.6) then
        runtime.focus_target = nil
    end
    if runtime.focus_target then
        return
    end
    if now - runtime.last_focus_check < 0.25 then
        return
    end
    runtime.last_focus_check = now
    local hero_pos = Entity.GetAbsOrigin(runtime.hero)
    if not hero_pos then
        return
    end
    local enemies = NPCs.InRadius(hero_pos, runtime.config.attack_radius, runtime.team, Enum.TeamType.TEAM_ENEMY) or {}
    local best
    local best_score = -math.huge
    for _, enemy in ipairs(enemies) do
        if IsValidEnemy(enemy) then
            local enemy_pos = Entity.GetAbsOrigin(enemy)
            if enemy_pos then
                local distance = Distance(hero_pos, enemy_pos)
                local score = -distance
                if NPC.IsHero(enemy) then
                    score = score + 300
                end
                local idx = Entity.GetIndex(enemy)
                if runtime.threat_memory[idx] and runtime.threat_memory[idx] > GlobalVars.GetCurTime() then
                    score = score + 180
                end
                if score > best_score then
                    best_score = score
                    best = enemy
                end
            end
        end
    end
    runtime.focus_target = best
end

local function TryDominate(now)
    if not runtime.config.auto_dominate then
        return
    end
    if not runtime.hero or not Entity.IsAlive(runtime.hero) then
        return
    end

    if not NPC.GetItemByIndex then
        return
    end

    for slot = 0, 8 do
        local item = NPC.GetItemByIndex(runtime.hero, slot)
        if item then
            local name = Ability.GetName(item)
            if DOMINATOR_ITEMS[name] then
                if Ability.IsCastable(item, NPC.GetMana(runtime.hero)) and Ability.GetCooldownTimeRemaining(item) <= 0 then
                    local cast_range = Ability.GetCastRange(item)
                    cast_range = cast_range > 0 and cast_range or DEFAULTS.dominator_range
                    local hero_pos = Entity.GetAbsOrigin(runtime.hero)
                    if hero_pos then
                        local best_target
                        local best_score = -math.huge
                        local neutrals = NPCs.InRadius(hero_pos, cast_range, runtime.team, Enum.TeamType.TEAM_NEUTRAL) or {}
                        for _, neutral in ipairs(neutrals) do
                            local is_ancient = NPC.IsAncient and NPC.IsAncient(neutral)
                            if Entity.IsAlive(neutral) and not is_ancient then
                                local name_neutral = NPC.GetUnitName(neutral)
                                local priority = DOMINATOR_PRIORITY[name_neutral] or 0
                                if priority > best_score then
                                    best_score = priority
                                    best_target = neutral
                                end
                            elseif name == "item_helm_of_the_overlord" and Entity.IsAlive(neutral) and is_ancient then
                                local name_neutral = NPC.GetUnitName(neutral)
                                local priority = DOMINATOR_PRIORITY[name_neutral] or (ANCIENT_UNITS[name_neutral] and 350 or 0)
                                if priority > best_score then
                                    best_score = priority
                                    best_target = neutral
                                end
                            end
                        end
                        if best_target then
                            Ability.CastTarget(item, best_target)
                            return
                        end
                    end
                end
            end
        end
    end
end

local function RefreshAgents(now)
    local next_agents = {}
    for _, unit in ipairs(NPCs.GetAll()) do
        if ShouldManage(unit) then
            local idx = Entity.GetIndex(unit)
            local agent = runtime.agents[idx]
            if not agent then
                agent = {
                    unit = unit,
                    next_order = 0,
                    manual_until = 0,
                    state = STATES.FOLLOW,
                    last_action = "spawn",
                }
            end
            agent.unit = unit
            next_agents[idx] = agent
            ProcessAgent(agent, now)
        end
    end
    runtime.agents = next_agents
end

local function FlagManual(unit)
    if not unit then
        return
    end
    local idx = Entity.GetIndex(unit)
    local agent = runtime.agents[idx]
    if agent then
        agent.manual_until = GlobalVars.GetCurTime() + runtime.config.manual_lock
        agent.state = STATES.MANUAL
        agent.last_action = "manual"
    end
end

function commander.OnPrepareUnitOrders(data)
    if not MenuEnabled() then
        return true
    end
    ReadConfig()

    if not UpdateHeroContext() then
        return true
    end

    if data.orderIssuer == Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_HERO_ONLY and data.order == Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET then
        runtime.focus_target = data.target
    end

    if data.orderIssuer == Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY then
        if data.npc then
            FlagManual(data.npc)
        end
        return true
    end

    local player = AcquirePlayer()
    if not player then
        return true
    end

    if Player and Player.GetSelectedUnits then
        local selected = Player.GetSelectedUnits(player)
        if selected then
            for _, unit in ipairs(selected) do
                FlagManual(unit)
            end
        end
    end
    return true
end

function commander.OnEntityHurt(data)
    if not MenuEnabled() then
        return
    end
    if not data or not data.target then
        return
    end
    if runtime.hero and data.target == runtime.hero and data.entindex_attacker then
        runtime.threat_memory[data.entindex_attacker] = GlobalVars.GetCurTime() + 3
    end
end

function commander.OnUpdate()
    if not Engine.IsInGame() then
        ResetRuntime()
        return
    end

    if not MenuEnabled() then
        ResetRuntime()
        return
    end

    ReadConfig()

    if not UpdateHeroContext() then
        return
    end

    local now = GlobalVars.GetCurTime()
    TrackFocusTarget(now)
    TryDominate(now)
    RefreshAgents(now)
end

function commander.OnDraw()
    if not runtime.config or not runtime.config.debug then
        return
    end
    if not Renderer or not Renderer.LoadFont then
        return
    end
    if not commander.debug_font then
        commander.debug_font = Renderer.LoadFont("Tahoma", 16, Enum.FontCreate.FONTFLAG_OUTLINE)
    end
    local font = commander.debug_font
    for _, agent in pairs(runtime.agents) do
        local unit = agent.unit
        if unit and Entity.IsAlive(unit) then
            local origin = Entity.GetAbsOrigin(unit)
            local offset = NPC.GetHealthBarOffset(unit) or 0
            if origin then
                local draw_pos = origin
                if Vector then
                    draw_pos = origin + Vector(0, 0, offset + 40)
                end
                local screen_pos, visible = Renderer.WorldToScreen(draw_pos)
                if visible then
                    local r, g, b = 180, 220, 255
                    if agent.state == STATES.CASTING then
                        r, g, b = 255, 160, 100
                    elseif agent.state == STATES.MANUAL then
                        r, g, b = 255, 210, 90
                    elseif agent.state == STATES.CHASE then
                        r, g, b = 255, 80, 80
                    end
                    local text = string.format("[%s] %s", agent.state or "?", agent.last_action or "")
                    local width, height = 0, 0
                    if Renderer.MeasureText then
                        width, height = Renderer.MeasureText(font, text)
                    else
                        width = #text * 7
                        height = 16
                    end
                    Renderer.DrawText(font, screen_pos.x - width / 2, screen_pos.y, r, g, b, 255, text)
                end
            end
        end
    end
end

function commander.OnGameEnd()
    ResetRuntime()
end

return commander
