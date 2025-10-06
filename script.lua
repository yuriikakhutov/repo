local commander = { ui = {} }

-------------------------------------------------------------------------------
-- Runtime state
-------------------------------------------------------------------------------
local runtime = {
    hero = nil,
    team = nil,
    player = nil,
    player_id = nil,
    config = nil,
    agents = {},
    threat_expiry = {},
    last_scan = 0,
    last_dominator_scan = 0,
    last_cast = {},
}

local STATES = {
    FOLLOW = "FOLLOW",
    ENGAGE = "ENGAGE",
    HOLD = "HOLD",
    MANUAL = "MANUAL",
}

-------------------------------------------------------------------------------
-- Dominator priorities
-------------------------------------------------------------------------------
local GOLD_PRIORITY = {
    npc_dota_neutral_black_dragon = 200,
    npc_dota_neutral_granite_golem = 200,
    npc_dota_neutral_rock_golem = 200,
    npc_dota_neutral_elder_jungle_stalker = 180,
    npc_dota_neutral_prowler_acolyte = 175,
    npc_dota_neutral_big_thunder_lizard = 170,
    npc_dota_neutral_dark_troll_warlord = 155,
    npc_dota_neutral_enraged_wildkin = 150,
    npc_dota_neutral_polar_furbolg_ursa_warrior = 150,
    npc_dota_neutral_polar_furbolg_champion = 140,
    npc_dota_neutral_satyr_hellcaller = 140,
    npc_dota_neutral_centaur_khan = 135,
    npc_dota_neutral_ogre_magi = 130,
    npc_dota_neutral_ogre_mauler = 125,
    npc_dota_neutral_mud_golem = 120,
    npc_dota_neutral_wildkin = 115,
    npc_dota_neutral_fel_beast = 105,
    npc_dota_neutral_harpy_storm = 100,
    npc_dota_neutral_harpy_scout = 95,
    npc_dota_neutral_satyr_trickster = 90,
    npc_dota_neutral_satyr_soulstealer = 90,
}

local ANCIENT_UNITS = {
    npc_dota_neutral_black_dragon = true,
    npc_dota_neutral_granite_golem = true,
    npc_dota_neutral_rock_golem = true,
    npc_dota_neutral_elder_jungle_stalker = true,
    npc_dota_neutral_big_thunder_lizard = true,
    npc_dota_neutral_prowler_acolyte = true,
}

-------------------------------------------------------------------------------
-- Ability metadata
-------------------------------------------------------------------------------
local ABILITY_DATA = {
    mud_golem_hurl_boulder = {
        behavior = "target",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Бросаю валун",
    },
    ancient_rock_golem_hurl_boulder = {
        behavior = "target",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Бросаю валун",
    },
    granite_golem_hurl_boulder = {
        behavior = "target",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Бросаю валун",
    },
    dark_troll_warlord_ensnare = {
        behavior = "target",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Хватаю сетью",
    },
    dark_troll_warlord_raise_dead = {
        behavior = "no_target",
        always_cast = true,
        requires_charges = true,
        message = "Призываю скелетов",
    },
    dark_troll_summoner_raise_dead = {
        behavior = "no_target",
        always_cast = true,
        requires_charges = true,
        message = "Призываю скелетов",
    },
    forest_troll_high_priest_heal = {
        behavior = "ally_target",
        prefer_anchor = true,
        prefer_ally_hero = true,
        ally_max_health_pct = 0.90,
        message = "Лечу союзника",
    },
    prowler_acolyte_heal = {
        behavior = "ally_target",
        prefer_anchor = true,
        prefer_ally_hero = true,
        ally_max_health_pct = 0.85,
        message = "Лечу союзника",
    },
    neutral_ogre_magi_ice_armor = {
        behavior = "ally_target",
        prefer_anchor = true,
        prefer_ally_hero = true,
        avoid_modifier = "modifier_ogre_magi_frost_armor",
        message = "Накладываю броню",
    },
    ogre_magi_frost_armor = {
        behavior = "ally_target",
        prefer_anchor = true,
        prefer_ally_hero = true,
        avoid_modifier = "modifier_ogre_magi_frost_armor",
        message = "Накладываю броню",
    },
    satyr_trickster_purge = {
        behavior = "target",
        allow_creeps = true,
        allow_neutrals = true,
        allow_allies = true,
        prefer_anchor = true,
        message = "Снимаю эффекты",
    },
    satyr_soulstealer_mana_burn = {
        behavior = "target",
        only_heroes = true,
        message = "Выжигаю ману",
    },
    satyr_mindstealer_mana_burn = {
        behavior = "target",
        only_heroes = true,
        message = "Выжигаю ману",
    },
    satyr_hellcaller_shockwave = {
        behavior = "point",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Шоковая волна",
    },
    harpy_storm_chain_lightning = {
        behavior = "target",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Цепная молния",
    },
    harpy_scout_take_off = {
        behavior = "no_target",
        always_cast = true,
        message = "Взлёт",
    },
    centaur_khan_war_stomp = {
        behavior = "no_target",
        radius = 315,
        min_enemies = 1,
        allow_creeps = true,
        allow_neutrals = true,
        trigger_range = 175,
        message = "Оглушаю врагов",
    },
    polar_furbolg_ursa_warrior_thunder_clap = {
        behavior = "no_target",
        radius = 315,
        min_enemies = 1,
        allow_creeps = true,
        allow_neutrals = true,
        trigger_range = 175,
        message = "Громовой удар",
    },
    polar_furbolg_champion_thunder_clap = {
        behavior = "no_target",
        radius = 315,
        min_enemies = 1,
        allow_creeps = true,
        allow_neutrals = true,
        trigger_range = 175,
        message = "Громовой удар",
    },
    hellbear_smasher_slam = {
        behavior = "no_target",
        radius = 350,
        min_enemies = 1,
        allow_creeps = true,
        allow_neutrals = true,
        trigger_range = 175,
        message = "Мощный удар",
    },
    ogre_bruiser_ogre_smash = {
        behavior = "point",
        allow_creeps = true,
        allow_neutrals = true,
        trigger_range = 180,
        message = "Размазываю врага",
    },
    ogre_mauler_smash = {
        behavior = "point",
        allow_creeps = true,
        allow_neutrals = true,
        trigger_range = 180,
        message = "Размазываю врага",
    },
    ancient_black_dragon_fireball = {
        behavior = "point",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Огненный шар",
    },
    black_dragon_fireball = {
        behavior = "point",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Огненный шар",
    },
    ancient_thunderhide_slam = {
        behavior = "no_target",
        radius = 315,
        min_enemies = 1,
        allow_creeps = true,
        allow_neutrals = true,
        trigger_range = 175,
        message = "Громовой топот",
    },
    big_thunder_lizard_slam = {
        behavior = "no_target",
        radius = 315,
        min_enemies = 1,
        allow_creeps = true,
        allow_neutrals = true,
        trigger_range = 175,
        message = "Громовой топот",
    },
    ancient_thunderhide_frenzy = {
        behavior = "ally_target",
        prefer_anchor = true,
        include_self = false,
        message = "Бешенство",
    },
    big_thunder_lizard_frenzy = {
        behavior = "ally_target",
        prefer_anchor = true,
        include_self = false,
        message = "Бешенство",
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
    },
    wildkin_hurricane = {
        behavior = "point",
        allow_creeps = true,
        allow_neutrals = true,
        message = "Сильный порыв",
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
        message = "Магический щит",
    },
}

-------------------------------------------------------------------------------
-- Utility helpers
-------------------------------------------------------------------------------
local function reset_runtime()
    runtime.hero = nil
    runtime.team = nil
    runtime.player = nil
    runtime.player_id = nil
    runtime.config = nil
    runtime.agents = {}
    runtime.threat_expiry = {}
    runtime.last_scan = 0
    runtime.last_dominator_scan = 0
    runtime.last_cast = {}
end

local function is_valid_handle(handle)
    if not handle then
        return false
    end
    local t = type(handle)
    if t ~= "userdata" and t ~= "table" then
        return false
    end
    if handle.IsNull then
        local ok, result = pcall(handle.IsNull, handle)
        if ok and result then
            return false
        end
    end
    return true
end

local function ensure_menu()
    if commander.menu_root then
        return
    end
    if not Menu or not Menu.Create then
        return
    end

    local tab = Menu.Create("Scripts", "Other", "Dominator Commander")
    if not tab then
        return
    end

    local main = tab:Create("Main")
    commander.ui.enable = main:Switch("Включить скрипт", true, "\u{f0b2}")
    commander.ui.follow_radius = main:Slider("Радиус следования", 150, 600, 300, "%d")
    commander.ui.engage_radius = main:Slider("Радиус атаки от героя", 200, 600, 300, "%d")
    commander.ui.disengage_radius = main:Slider("Дистанция отступления", 300, 900, 500, "%d")
    commander.ui.allow_creep_spells = main:Switch("Кастовать по вражеским крипам", true, "\u{f6e2}")
    commander.ui.debug = main:Switch("Отображать состояние", false, "\u{f05a}")
    commander.ui.manual_override = main:Slider("Пауза после ручного приказа (сек)", 10, 300, 120, "%.1f")

    local helm_group = tab:Create("Helm")
    commander.ui.helm_range = helm_group:Slider("Поиск нейтралов (радиус)", 600, 1600, 1200, "%d")
    commander.ui.scan_interval = helm_group:Slider("Интервал поиска (мс)", 5, 50, 15, "%d")

    commander.menu_root = tab
end

local function read_config()
    runtime.config = runtime.config or {}
    if commander.ui.enable then
        runtime.config.enabled = commander.ui.enable:Get()
    else
        runtime.config.enabled = true
    end
    local function slider_value(widget, default)
        if not widget then
            return default
        end
        local ok, value = pcall(widget.Get, widget)
        if ok and type(value) == "number" then
            return value
        end
        return default
    end

    runtime.config.follow_radius = slider_value(commander.ui.follow_radius, 300)
    runtime.config.engage_radius = slider_value(commander.ui.engage_radius, 300)
    runtime.config.disengage_radius = slider_value(commander.ui.disengage_radius, 500)
    if commander.ui.allow_creep_spells then
        runtime.config.allow_creep_spells = commander.ui.allow_creep_spells:Get() and true or false
    else
        runtime.config.allow_creep_spells = true
    end
    runtime.config.debug = commander.ui.debug and commander.ui.debug:Get() or false
    runtime.config.manual_override = slider_value(commander.ui.manual_override, 120) / 100
    if runtime.config.manual_override < 0.3 then
        runtime.config.manual_override = 0.3
    end
    runtime.config.helm_range = slider_value(commander.ui.helm_range, 1200)
    runtime.config.scan_interval = slider_value(commander.ui.scan_interval, 15) / 100
end

local function acquire_player()
    if is_valid_handle(runtime.player) then
        return runtime.player
    end

    runtime.player = nil
    if runtime.player_id and PlayerResource and PlayerResource.GetPlayer then
        local ok, player = pcall(PlayerResource.GetPlayer, runtime.player_id)
        if ok and is_valid_handle(player) then
            runtime.player = player
            return runtime.player
        end
    end

    if Players and Players.GetLocal then
        local ok, player = pcall(Players.GetLocal)
        if ok and is_valid_handle(player) then
            runtime.player = player
            if Player and Player.GetPlayerID then
                local ok_id, pid = pcall(Player.GetPlayerID, player)
                if ok_id and type(pid) == "number" then
                    runtime.player_id = pid
                end
            end
            return runtime.player
        end
    end

    return nil
end

local function update_hero_context()
    if runtime.hero and Entity.IsAlive(runtime.hero) then
        return true
    end

    runtime.hero = Heroes and Heroes.GetLocal and Heroes.GetLocal() or nil
    if not runtime.hero or not Entity.IsAlive(runtime.hero) then
        return false
    end

    runtime.team = Entity.GetTeamNum(runtime.hero)

    if Hero and Hero.GetPlayerID then
        local ok, pid = pcall(Hero.GetPlayerID, runtime.hero)
        if ok and type(pid) == "number" then
            runtime.player_id = pid
        end
    end

    acquire_player()
    return true
end

local function safe_order(unit, order, target, position, ability)
    local player = acquire_player()
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

local function safe_cast_target(unit, ability, target)
    if Ability.CastTarget then
        local ok = pcall(Ability.CastTarget, ability, target)
        if ok then
            return
        end
    end
    safe_order(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET, target, nil, ability)
end

local function safe_cast_position(unit, ability, position)
    if Ability.CastPosition then
        local ok = pcall(Ability.CastPosition, ability, position)
        if ok then
            return
        end
    end
    safe_order(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION, nil, position, ability)
end

local function safe_cast_no_target(unit, ability)
    if Ability.CastNoTarget then
        local ok = pcall(Ability.CastNoTarget, ability)
        if ok then
            return
        end
    end
    safe_order(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, nil, ability)
end

local function get_player_owner_id(unit)
    if not unit then
        return nil
    end
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

local function get_entity_owner(unit)
    if Entity and Entity.GetOwner then
        local ok, owner = pcall(Entity.GetOwner, unit)
        if ok and owner and owner ~= unit then
            return owner
        end
    end
    return nil
end

local function is_owned_by_hero(unit)
    if not runtime.hero then
        return false
    end
    local current = unit
    local safety = 0
    while current and safety < 12 do
        if current == runtime.hero then
            return true
        end
        current = get_entity_owner(current)
        safety = safety + 1
    end
    return false
end

local function should_manage_unit(unit)
    if not unit or not Entity.IsAlive(unit) then
        return false
    end
    if unit == runtime.hero then
        return false
    end
    if Entity.GetTeamNum(unit) ~= runtime.team then
        return false
    end
    if NPC.IsCourier and NPC.IsCourier(unit) then
        return false
    end

    if runtime.player_id and NPC.IsControllableByPlayer and NPC.IsControllableByPlayer(unit, runtime.player_id) then
        return true
    end

    local owner = get_player_owner_id(unit)
    if owner and runtime.player_id and owner == runtime.player_id then
        return true
    end

    if is_owned_by_hero(unit) then
        return true
    end

    return false
end

local function get_unit_health_pct(unit)
    if not unit or not Entity.IsAlive(unit) then
        return 0
    end
    local health = Entity.GetHealth(unit) or 0
    local max_health = Entity.GetMaxHealth(unit) or 1
    if max_health <= 0 then
        return 0
    end
    return health / max_health
end

local function get_ability_charges(ability)
    if not ability then
        return nil
    end
    if Ability.GetCurrentCharges then
        local ok, charges = pcall(Ability.GetCurrentCharges, ability)
        if ok then
            return charges
        end
    end
    if Ability.GetCharges then
        local ok, charges = pcall(Ability.GetCharges, ability)
        if ok then
            return charges
        end
    end
    if Ability.GetRemainingCharges then
        local ok, charges = pcall(Ability.GetRemainingCharges, ability)
        if ok then
            return charges
        end
    end
    return nil
end

local function is_ability_ready(unit, ability, metadata)
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
        local ok, cd = pcall(Ability.GetCooldownTimeRemaining, ability)
        if ok and cd and cd > 0 then
            return false
        end
    end
    if metadata and metadata.requires_charges then
        local charges = get_ability_charges(ability)
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
        local ok, castable = pcall(Ability.IsCastable, ability, NPC.GetMana(unit) or 0)
        if ok then
            return castable
        end
    end
    return false
end

local function enemy_matches(enemy, metadata)
    if not enemy or not Entity.IsAlive(enemy) then
        return false
    end
    if Entity.GetTeamNum(enemy) == runtime.team then
        return false
    end
    if NPC.IsCourier and NPC.IsCourier(enemy) then
        return false
    end
    if metadata and metadata.only_heroes and not NPC.IsHero(enemy) then
        return false
    end
    local is_creep = NPC.IsCreep(enemy) and not NPC.IsHero(enemy)
    local is_neutral = Entity.GetTeamNum(enemy) == Enum.TeamNum.TEAM_NEUTRAL
    local allow_creep_spells = true
    if runtime.config and runtime.config.allow_creep_spells ~= nil then
        allow_creep_spells = runtime.config.allow_creep_spells
    end
    if metadata then
        if is_creep and metadata.allow_creeps == false then
            return false
        end
        if is_neutral and metadata.allow_neutrals == false then
            return false
        end
    end
    if is_creep and not allow_creep_spells and (not metadata or not metadata.only_heroes) then
        return false
    end
    return true
end

local function ally_matches(ally, metadata)
    if not ally or not Entity.IsAlive(ally) then
        return false
    end
    if Entity.GetTeamNum(ally) ~= runtime.team then
        return false
    end
    if metadata then
        if metadata.include_self == false and ally == runtime.hero then
            return false
        end
        if metadata.ally_max_health_pct and get_unit_health_pct(ally) >= metadata.ally_max_health_pct then
            return false
        end
        if metadata.ally_min_health_pct and get_unit_health_pct(ally) <= metadata.ally_min_health_pct then
            return false
        end
        if metadata.avoid_modifier and NPC.HasModifier(ally, metadata.avoid_modifier) then
            return false
        end
    end
    return true
end

local function find_enemy_target(unit, metadata, cast_range, anchor_pos)
    local best_target
    local best_score = -math.huge
    local centers = {}
    local unit_pos = Entity.GetAbsOrigin(unit)
    if unit_pos then
        table.insert(centers, unit_pos)
    end
    if anchor_pos then
        table.insert(centers, anchor_pos)
    end

    local radius_bonus = metadata and metadata.range_bonus or 0

    for _, center in ipairs(centers) do
        local enemies = NPCs.InRadius(center, cast_range + radius_bonus, runtime.team, Enum.TeamType.TEAM_ENEMY) or {}
        for _, enemy in ipairs(enemies) do
            if enemy_matches(enemy, metadata) then
                local pos = Entity.GetAbsOrigin(enemy)
                if pos then
                    local distance = center:Distance(pos)
                    if distance <= cast_range + radius_bonus then
                        local score = -distance
                        if NPC.IsHero(enemy) then
                            score = score + 300
                        end
                        local idx = Entity.GetIndex(enemy)
                        if runtime.threat_expiry[idx] and runtime.threat_expiry[idx] > GlobalVars.GetCurTime() then
                            score = score + 120
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
            local neutrals = NPCs.InRadius(center, cast_range + radius_bonus, runtime.team, Enum.TeamType.TEAM_NEUTRAL) or {}
            for _, enemy in ipairs(neutrals) do
                if enemy_matches(enemy, metadata) then
                    local pos = Entity.GetAbsOrigin(enemy)
                    if pos then
                        local distance = center:Distance(pos)
                        if distance <= cast_range + radius_bonus then
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

local function choose_ally_target(unit, metadata, cast_range, anchor_unit)
    local anchor_pos = anchor_unit and Entity.GetAbsOrigin(anchor_unit)
    if metadata and metadata.prefer_anchor and anchor_unit and ally_matches(anchor_unit, metadata) then
        local unit_pos = Entity.GetAbsOrigin(unit)
        if unit_pos and anchor_pos and unit_pos:Distance(anchor_pos) <= cast_range + (metadata.range_bonus or 0) then
            return anchor_unit
        end
    end
    if metadata and metadata.prefer_ally_hero and runtime.hero and ally_matches(runtime.hero, metadata) then
        local unit_pos = Entity.GetAbsOrigin(unit)
        local hero_pos = Entity.GetAbsOrigin(runtime.hero)
        if unit_pos and hero_pos and unit_pos:Distance(hero_pos) <= cast_range + (metadata.range_bonus or 0) then
            return runtime.hero
        end
    end
    local unit_pos = Entity.GetAbsOrigin(unit)
    if not unit_pos then
        return nil
    end
    local best_target
    local best_score = -math.huge
    local allies = NPCs.InRadius(unit_pos, cast_range + (metadata.range_bonus or 0), runtime.team, Enum.TeamType.TEAM_FRIEND) or {}
    for _, ally in ipairs(allies) do
        if ally_matches(ally, metadata) then
            local pos = Entity.GetAbsOrigin(ally)
            if pos then
                local distance = unit_pos:Distance(pos)
                if distance <= cast_range + (metadata.range_bonus or 0) then
                    local score = -distance
                    if NPC.IsHero(ally) then
                        score = score + 100
                    end
                    if metadata and metadata.prefer_anchor and anchor_pos and ally == anchor_unit then
                        score = score + 50
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

local function ally_needs_dispel(ally)
    if not ally or not Entity.IsAlive(ally) then
        return false
    end
    if NPC.IsStunned and NPC.IsStunned(ally) then
        return true
    end
    if NPC.IsSilenced and NPC.IsSilenced(ally) then
        return true
    end
    if NPC.IsRooted and NPC.IsRooted(ally) then
        return true
    end
    if NPC.IsHexed and NPC.IsHexed(ally) then
        return true
    end
    if NPC.IsDisarmed and NPC.IsDisarmed(ally) then
        return true
    end
    return false
end

local function find_dispel_target(unit, metadata, cast_range, anchor_unit)
    if metadata and metadata.prefer_anchor and anchor_unit and ally_matches(anchor_unit, metadata) and ally_needs_dispel(anchor_unit) then
        return anchor_unit
    end
    if runtime.hero and ally_matches(runtime.hero, metadata) and ally_needs_dispel(runtime.hero) then
        local unit_pos = Entity.GetAbsOrigin(unit)
        local hero_pos = Entity.GetAbsOrigin(runtime.hero)
        if unit_pos and hero_pos and unit_pos:Distance(hero_pos) <= cast_range + (metadata and metadata.range_bonus or 0) then
            return runtime.hero
        end
    end
    local unit_pos = Entity.GetAbsOrigin(unit)
    if not unit_pos then
        return nil
    end
    local allies = NPCs.InRadius(unit_pos, cast_range + (metadata and metadata.range_bonus or 0), runtime.team, Enum.TeamType.TEAM_FRIEND) or {}
    for _, ally in ipairs(allies) do
        if ally_matches(ally, metadata) and ally_needs_dispel(ally) then
            return ally
        end
    end
    return nil
end

local function should_cast_no_target(unit, metadata, ability)
    if metadata and metadata.always_cast then
        return true
    end
    local radius = metadata and metadata.radius
    if (not radius or radius <= 0) and Ability.GetAOERadius then
        local ok, aoe = pcall(Ability.GetAOERadius, ability)
        if ok and aoe and aoe > 0 then
            radius = aoe
        end
    end
    radius = radius or 250
    local unit_pos = Entity.GetAbsOrigin(unit)
    if not unit_pos then
        return false
    end
    local enemies = NPCs.InRadius(unit_pos, radius, runtime.team, Enum.TeamType.TEAM_ENEMY) or {}
    local neutrals = NPCs.InRadius(unit_pos, radius, runtime.team, Enum.TeamType.TEAM_NEUTRAL) or {}
    local count = 0
    for _, enemy in ipairs(enemies) do
        if enemy_matches(enemy, metadata) then
            count = count + 1
        end
    end
    if metadata and metadata.allow_neutrals ~= false then
        for _, enemy in ipairs(neutrals) do
            if enemy_matches(enemy, metadata) then
                count = count + 1
            end
        end
    end
    local need = metadata and metadata.min_enemies or 1
    return count >= need
end

local function ability_cast_range(unit, ability, metadata)
    if metadata and metadata.range then
        return metadata.range
    end
    if Ability.GetCastRange then
        local ok, range = pcall(Ability.GetCastRange, ability)
        if ok and range and range > 0 then
            return range
        end
    end
    if Ability.GetSpecialValueFor then
        local ok, value = pcall(Ability.GetSpecialValueFor, ability, "cast_range")
        if ok and value and value > 0 then
            return value
        end
    end
    return 600
end

local function try_cast_ability(unit, agent, now, ability, metadata, anchor_unit)
    if not is_ability_ready(unit, ability, metadata) then
        return false
    end

    local behavior = metadata and metadata.behavior
    if not behavior then
        return false
    end

    local cast_range = ability_cast_range(unit, ability, metadata)
    local anchor_pos = anchor_unit and Entity.GetAbsOrigin(anchor_unit)

    if metadata and metadata.trigger_range then
        local target = agent.current_target
        if target and Entity.IsAlive(target) then
            local unit_pos = Entity.GetAbsOrigin(unit)
            local target_pos = Entity.GetAbsOrigin(target)
            if unit_pos and target_pos then
                local distance = unit_pos:Distance(target_pos)
                if distance > metadata.trigger_range then
                    return false
                end
            end
        end
    end

    if behavior == "target" then
        if metadata and metadata.allow_allies then
            local ally = find_dispel_target(unit, metadata, cast_range, anchor_unit)
            if ally then
                safe_cast_target(unit, ability, ally)
                agent.next_order_time = now + 0.15
                agent.last_action = metadata.message or "Помогаю"
                return true
            end
        end
        local enemy = find_enemy_target(unit, metadata, cast_range, anchor_pos)
        if enemy then
            safe_cast_target(unit, ability, enemy)
            agent.next_order_time = now + 0.15
            agent.last_action = metadata.message or "Кастую"
            return true
        end
    elseif behavior == "point" then
        local enemy = find_enemy_target(unit, metadata, cast_range, anchor_pos)
        if enemy then
            local pos = Entity.GetAbsOrigin(enemy)
            if pos then
                safe_cast_position(unit, ability, pos)
                agent.next_order_time = now + 0.15
                agent.last_action = metadata.message or "Кастую"
                return true
            end
        end
    elseif behavior == "ally_target" then
        local ally = choose_ally_target(unit, metadata, cast_range, anchor_unit)
        if ally then
            safe_cast_target(unit, ability, ally)
            agent.next_order_time = now + 0.15
            agent.last_action = metadata.message or "Поддерживаю"
            return true
        end
    elseif behavior == "no_target" then
        if should_cast_no_target(unit, metadata, ability) then
            safe_cast_no_target(unit, ability)
            agent.next_order_time = now + 0.15
            agent.last_action = metadata.message or "Активирую"
            return true
        end
    end

    return false
end

local function try_cast_abilities(unit, agent, now, anchor_unit)
    if NPC.IsChannellingAbility and NPC.IsChannellingAbility(unit) then
        agent.state = STATES.ENGAGE
        agent.last_action = "Канализирую"
        agent.next_order_time = now + 0.4
        return true
    end

    for slot = 0, 23 do
        local ability = NPC.GetAbilityByIndex(unit, slot)
        if ability then
            local name = Ability.GetName(ability)
            local metadata = ABILITY_DATA[name]
            if metadata and try_cast_ability(unit, agent, now, ability, metadata, anchor_unit) then
                return true
            end
        end
    end
    return false
end

-------------------------------------------------------------------------------
-- Unit control
-------------------------------------------------------------------------------
local function create_agent(unit)
    return {
        unit = unit,
        handle = Entity.GetIndex(unit),
        state = STATES.FOLLOW,
        last_action = "Ожидание",
        next_order_time = 0,
        manual_until = 0,
        current_target = nil,
    }
end

local function attack_target(unit, target, agent, now)
    safe_order(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, target, nil, nil)
    agent.state = STATES.ENGAGE
    agent.current_target = target
    agent.last_action = "Атакую"
    agent.next_order_time = now + 0.2
end

local function move_to_hero(unit, hero_pos, agent, now)
    safe_order(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, hero_pos, nil)
    agent.state = STATES.FOLLOW
    agent.last_action = "Двигаюсь к герою"
    agent.next_order_time = now + 0.2
end

local function hold_position(unit, agent, now)
    safe_order(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_HOLD_POSITION, nil, Entity.GetAbsOrigin(unit), nil)
    agent.state = STATES.HOLD
    agent.last_action = "Ожидаю"
    agent.current_target = nil
    agent.next_order_time = now + 0.2
end

local function find_attack_target(hero_pos, engage_radius)
    local best
    local best_score = -math.huge
    local enemies = NPCs.InRadius(hero_pos, engage_radius, runtime.team, Enum.TeamType.TEAM_ENEMY) or {}
    for _, enemy in ipairs(enemies) do
        if Entity.IsAlive(enemy) and Entity.GetTeamNum(enemy) ~= runtime.team and not (NPC.IsCourier and NPC.IsCourier(enemy)) then
            local pos = Entity.GetAbsOrigin(enemy)
            if pos then
                local distance = hero_pos:Distance(pos)
                if distance <= engage_radius then
                    local score = -distance
                    if NPC.IsHero(enemy) then
                        score = score + 400
                    end
                    if score > best_score then
                        best_score = score
                        best = enemy
                    end
                end
            end
        end
    end
    return best
end

local function process_agent(agent, now, hero_pos)
    local unit = agent.unit
    if not unit or not Entity.IsAlive(unit) then
        return
    end

    if agent.manual_until and agent.manual_until > now then
        agent.state = STATES.MANUAL
        agent.last_action = "Ручной приказ"
        return
    end

    if now < (agent.next_order_time or 0) then
        return
    end

    if try_cast_abilities(unit, agent, now, runtime.hero) then
        return
    end

    local hero_distance
    local unit_pos = Entity.GetAbsOrigin(unit)
    if unit_pos and hero_pos then
        hero_distance = unit_pos:Distance(hero_pos)
    end

    if hero_distance and hero_distance > runtime.config.follow_radius then
        move_to_hero(unit, hero_pos, agent, now)
        agent.current_target = nil
        return
    end

    local target = agent.current_target
    if target and (not Entity.IsAlive(target) or Entity.GetTeamNum(target) == runtime.team) then
        target = nil
        agent.current_target = nil
    end

    if target then
        local target_pos = Entity.GetAbsOrigin(target)
        if not target_pos or hero_pos:Distance(target_pos) > runtime.config.disengage_radius then
            hold_position(unit, agent, now)
            return
        end
        attack_target(unit, target, agent, now)
        return
    end

    local engage_radius = runtime.config.engage_radius
    local enemy = hero_pos and find_attack_target(hero_pos, engage_radius) or nil
    if enemy then
        agent.current_target = enemy
        attack_target(unit, enemy, agent, now)
        return
    end

    if hero_distance and hero_distance > 60 then
        move_to_hero(unit, hero_pos, agent, now)
    else
        hold_position(unit, agent, now)
    end
end

-------------------------------------------------------------------------------
-- Dominator casting
-------------------------------------------------------------------------------
local function is_valid_neutral(unit, allow_ancients)
    if not unit or not Entity.IsAlive(unit) then
        return false
    end
    if Entity.GetTeamNum(unit) ~= Enum.TeamNum.TEAM_NEUTRAL then
        return false
    end
    if NPC.IsCourier and NPC.IsCourier(unit) then
        return false
    end
    if NPC.IsRoshan and NPC.IsRoshan(unit) then
        return false
    end
    if not allow_ancients and (ANCIENT_UNITS[NPC.GetUnitName(unit)] or (NPC.IsAncient and NPC.IsAncient(unit))) then
        return false
    end
    return true
end

local function neutral_score(unit, prefer_ancients)
    local name = NPC.GetUnitName(unit)
    local score = GOLD_PRIORITY[name] or 0
    if prefer_ancients and (ANCIENT_UNITS[name] or (NPC.IsAncient and NPC.IsAncient(unit))) then
        score = score + 300
    end
    if score <= 0 and NPC.GetBountyXP then
        local ok, xp = pcall(NPC.GetBountyXP, unit)
        if ok and xp and xp > 0 then
            score = score + xp / 2
        end
    end
    if score <= 0 then
        score = 10
    end
    local health = Entity.GetHealth(unit) or 0
    score = score - health * 0.001
    return score
end

local function find_best_neutral(hero, allow_ancients, prefer_ancients, range)
    local hero_pos = Entity.GetAbsOrigin(hero)
    if not hero_pos then
        return nil
    end
    local neutrals = NPCs.InRadius(hero_pos, range, runtime.team, Enum.TeamType.TEAM_NEUTRAL)
    if not neutrals or #neutrals == 0 then
        return nil
    end
    local best_unit
    local best_score = -math.huge
    for _, unit in ipairs(neutrals) do
        if is_valid_neutral(unit, allow_ancients) then
            local pos = Entity.GetAbsOrigin(unit)
            if pos and hero_pos:Distance(pos) <= range then
                local score = neutral_score(unit, prefer_ancients)
                if score > best_score then
                    best_score = score
                    best_unit = unit
                end
            end
        end
    end
    return best_unit
end

local function is_item_ready(item, mana)
    if not item then
        return false
    end
    if Ability.GetLevel and Ability.GetLevel(item) <= 0 then
        return false
    end
    if Ability.GetCooldownTimeRemaining then
        local ok, cd = pcall(Ability.GetCooldownTimeRemaining, item)
        if ok and cd and cd > 0 then
            return false
        end
    end
    if Ability.IsReady then
        local ok, ready = pcall(Ability.IsReady, item)
        if ok and ready then
            return true
        end
    end
    if Ability.IsCastable then
        local ok, castable = pcall(Ability.IsCastable, item, mana or 0)
        if ok then
            return castable
        end
    end
    return false
end

local function get_item(hero, name)
    if NPC.GetItem then
        local ok, item = pcall(NPC.GetItem, hero, name, true)
        if ok and item then
            return item
        end
    end
    if NPC.GetItemByName then
        local ok, item = pcall(NPC.GetItemByName, hero, name, true, true)
        if ok and item then
            return item
        end
    end
    return nil
end

local function cast_helm(hero, item_name, allow_ancients, prefer_ancients)
    local item = get_item(hero, item_name)
    if not item then
        return
    end
    local mana = NPC.GetMana(hero) or 0
    if not is_item_ready(item, mana) then
        return
    end

    local now = GlobalVars.GetCurTime()
    if runtime.last_cast[item_name] and now - runtime.last_cast[item_name] < runtime.config.scan_interval then
        return
    end

    local range = Ability.GetCastRange and Ability.GetCastRange(item) or runtime.config.helm_range
    if not range or range <= 0 then
        range = runtime.config.helm_range
    end
    local target = find_best_neutral(hero, allow_ancients, prefer_ancients, range)
    if not target then
        return
    end

    runtime.last_cast[item_name] = now

    if Ability.CastTarget then
        local ok = pcall(Ability.CastTarget, item, target)
        if ok then
            return
        end
    end

    safe_order(hero, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET, target, Entity.GetAbsOrigin(target), item)
end

-------------------------------------------------------------------------------
-- Menu debug draw
-------------------------------------------------------------------------------
local debug_font
local function ensure_debug_font()
    if debug_font then
        return debug_font
    end
    debug_font = Render.LoadFont("Arial", 15, Enum.FontCreate.FONTFLAG_OUTLINE)
    return debug_font
end

local function draw_debug()
    if not runtime.config or not runtime.config.debug then
        return
    end
    local font = ensure_debug_font()
    for _, agent in pairs(runtime.agents) do
        local unit = agent.unit
        if unit and Entity.IsAlive(unit) then
            local origin = Entity.GetAbsOrigin(unit)
            local offset = NPC.GetHealthBarOffset(unit) or 0
            if origin then
                local screen, visible = Render.WorldToScreen(origin + Vector(0, 0, offset + 40))
                if visible then
                    local text = string.format("[%s] %s", agent.state or "?", agent.last_action or "")
                    Render.Text(font, 15, text, Vec2(screen.x - Render.TextSize(font, 15, text).x / 2, screen.y), Color(180, 220, 255, 255))
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Event hooks
-------------------------------------------------------------------------------
function commander.OnUpdate()
    if not Engine.IsInGame() then
        reset_runtime()
        return
    end

    ensure_menu()
    read_config()

    if not runtime.config.enabled then
        runtime.agents = {}
        return
    end

    if not update_hero_context() then
        runtime.agents = {}
        return
    end

    local hero = runtime.hero
    local hero_pos = Entity.GetAbsOrigin(hero)
    if not hero_pos then
        return
    end

    local now = GlobalVars.GetCurTime()

    if now - runtime.last_dominator_scan > runtime.config.scan_interval then
        runtime.last_dominator_scan = now
        cast_helm(hero, "item_helm_of_the_overlord", true, true)
        cast_helm(hero, "item_helm_of_the_dominator", false, false)
    end

    local next_agents = {}
    local units = NPCs.GetAll() or {}
    for _, unit in ipairs(units) do
        if should_manage_unit(unit) then
            local handle = Entity.GetIndex(unit)
            local agent = runtime.agents[handle]
            if not agent then
                agent = create_agent(unit)
            end
            agent.unit = unit
            agent.handle = handle
            process_agent(agent, now, hero_pos)
            next_agents[handle] = agent
        end
    end
    runtime.agents = next_agents
end

function commander.OnDraw()
    draw_debug()
end

local function flag_manual_control(unit)
    if not unit then
        return
    end
    local handle = Entity.GetIndex(unit)
    local agent = runtime.agents[handle]
    if agent then
        agent.manual_until = GlobalVars.GetCurTime() + (runtime.config.manual_override or 0.5)
        agent.state = STATES.MANUAL
        agent.last_action = "Ручной приказ"
    end
end

function commander.OnPrepareUnitOrders(data)
    if not runtime.config or not runtime.config.enabled then
        return true
    end
    if data.orderIssuer == Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY and data.npc then
        flag_manual_control(data.npc)
        return true
    end
    local player = acquire_player()
    if not player then
        return true
    end
    local selected = Player.GetSelectedUnits and Player.GetSelectedUnits(player) or {}
    for _, unit in ipairs(selected) do
        flag_manual_control(unit)
    end
    return true
end

function commander.OnEntityHurt(event)
    if not runtime.hero or not event then
        return
    end
    if event.target ~= runtime.hero then
        return
    end
    local attacker = event.source
    if not attacker and event.entindex_attacker and EntIndexToHScript then
        attacker = EntIndexToHScript(event.entindex_attacker)
    end
    if attacker then
        runtime.threat_expiry[Entity.GetIndex(attacker)] = GlobalVars.GetCurTime() + 3
    end
end

function commander.OnGameEnd()
    reset_runtime()
end

return commander
