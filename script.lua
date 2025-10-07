local commander = { ui = {} }

-------------------------------------------------------------------------------
-- Runtime state
-------------------------------------------------------------------------------
local runtime = {
    hero = nil,
    team = nil,
    player = nil,
    player_id = nil,
    config = {
        enabled = true,
        follow_radius = 300,
        drop_radius = 500,
        attack_radius = 300,
        order_cooldown = 0.25,
        manual_pause = 1.5,
        cast_on_enemy_creeps = true,
        helm_scan_rate = 0.3,
    },
    agents = {},
    last_helm_scan = 0,
    menu_ready = false,
}

local STATES = {
    FOLLOW = "FOLLOW",
    ENGAGE = "ENGAGE",
    MANUAL = "MANUAL",
}

-------------------------------------------------------------------------------
-- Utility helpers
-------------------------------------------------------------------------------
local function ResetRuntime()
    runtime.hero = nil
    runtime.team = nil
    runtime.player = nil
    runtime.player_id = nil
    runtime.agents = {}
    runtime.last_helm_scan = 0
end

local function IsValidHandle(handle)
    if not handle then
        return false
    end
    local t = type(handle)
    if t ~= "userdata" and t ~= "table" then
        return false
    end
    if handle.IsNull and type(handle.IsNull) == "function" then
        local ok, res = pcall(handle.IsNull, handle)
        if ok and res then
            return false
        end
    end
    return true
end

local function AcquirePlayer()
    if IsValidHandle(runtime.player) then
        return runtime.player
    end

    runtime.player = nil

    if runtime.player_id and PlayerResource and PlayerResource.GetPlayer then
        local ok, player = pcall(PlayerResource.GetPlayer, runtime.player_id)
        if ok and IsValidHandle(player) then
            runtime.player = player
            return runtime.player
        end
    end

    if Players and Players.GetLocal then
        local ok, player = pcall(Players.GetLocal)
        if ok and IsValidHandle(player) then
            runtime.player = player
            if Player and Player.GetPlayerID then
                local ok_id, pid = pcall(Player.GetPlayerID, player)
                if ok_id and type(pid) == "number" then
                    runtime.player_id = pid
                end
            end
        end
    end

    return runtime.player
end

local function UpdateHeroContext()
    local hero = Heroes and Heroes.GetLocal and Heroes.GetLocal() or nil
    if not hero or not Entity.IsAlive(hero) then
        ResetRuntime()
        return false
    end

    runtime.hero = hero
    runtime.team = Entity.GetTeamNum(hero)

    if not runtime.player_id and Entity.GetPlayerOwnerID then
        local ok, pid = pcall(Entity.GetPlayerOwnerID, hero)
        if ok and type(pid) == "number" and pid >= 0 then
            runtime.player_id = pid
        end
    end

    AcquirePlayer()
    return true
end

local function EnsureMenu()
    if runtime.menu_ready or not Menu or not Menu.Create then
        return
    end

    local tab = Menu.Create("Scripts", "Other", "Dominator Commander")
    if not tab then
        return
    end

    tab:Icon("\u{f0c0}")

    local main = tab:Create("General")

    commander.ui.enable = main:Switch("Включить", true, "\u{f205}")
    commander.ui.follow = main:Slider("Радиус следования", 100, 600, 300, "%d")
    commander.ui.drop = main:Slider("Радиус отрыва", 200, 900, 500, "%d")
    commander.ui.attack = main:Slider("Радиус атаки от героя", 150, 600, 300, "%d")
    commander.ui.cooldown = main:Slider("Задержка приказов (мс)", 10, 500, 25, "%d")
    commander.ui.manual = main:Slider("Пауза после ручного приказа (мс)", 100, 4000, 1500, "%d")

    local spells = tab:Create("Abilities")
    commander.ui.enemy_creeps = spells:Switch("Кастовать по вражеским крипам", true, "\u{f0e7}")

    local helms = tab:Create("Helm")
    commander.ui.helm_rate = helms:Slider("Частота проверки (мс)", 50, 1000, 300, "%d")

    runtime.menu_ready = true
end

local function ReadConfig()
    if commander.ui.enable then
        runtime.config.enabled = commander.ui.enable:Get()
    end
    if commander.ui.follow then
        runtime.config.follow_radius = commander.ui.follow:Get()
    end
    if commander.ui.drop then
        runtime.config.drop_radius = commander.ui.drop:Get()
    end
    if commander.ui.attack then
        runtime.config.attack_radius = commander.ui.attack:Get()
    end
    if commander.ui.cooldown then
        runtime.config.order_cooldown = (commander.ui.cooldown:Get() or 0) / 1000
    end
    if commander.ui.manual then
        runtime.config.manual_pause = (commander.ui.manual:Get() or 0) / 1000
    end
    if commander.ui.enemy_creeps then
        runtime.config.cast_on_enemy_creeps = commander.ui.enemy_creeps:Get()
    end
    if commander.ui.helm_rate then
        runtime.config.helm_scan_rate = (commander.ui.helm_rate:Get() or 0) / 1000
    end

    if runtime.config.order_cooldown < 0.05 then
        runtime.config.order_cooldown = 0.05
    end
    if runtime.config.manual_pause < 0.3 then
        runtime.config.manual_pause = 0.3
    end
    if runtime.config.helm_scan_rate < 0.05 then
        runtime.config.helm_scan_rate = 0.05
    end
end

local function SafeOrder(unit, order, target, position, ability)
    local player = AcquirePlayer()
    if not player or not Player or not Player.PrepareUnitOrders then
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

local function SafeAttack(unit, target)
    SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, target, nil, nil)
end

local function SafeMove(unit, position)
    SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, position, nil)
end

local function SafeHold(unit)
    SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_HOLD_POSITION, nil, nil, nil)
end

-------------------------------------------------------------------------------
-- Dominator prioritisation
-------------------------------------------------------------------------------
local GOLD_PRIORITY = {
    npc_dota_neutral_black_dragon = 200,
    npc_dota_neutral_granite_golem = 200,
    npc_dota_neutral_rock_golem = 200,
    npc_dota_neutral_elder_jungle_stalker = 180,
    npc_dota_neutral_big_thunder_lizard = 170,
    npc_dota_neutral_prowler_acolyte = 170,
    npc_dota_neutral_dark_troll_warlord = 155,
    npc_dota_neutral_enraged_wildkin = 150,
    npc_dota_neutral_polar_furbolg_ursa_warrior = 150,
    npc_dota_neutral_satyr_hellcaller = 140,
    npc_dota_neutral_centaur_khan = 135,
    npc_dota_neutral_ogre_magi = 130,
    npc_dota_neutral_ogre_mauler = 125,
    npc_dota_neutral_mud_golem = 120,
    npc_dota_neutral_wildkin = 115,
    npc_dota_neutral_fel_beast = 105,
    npc_dota_neutral_harpy_storm = 100,
    npc_dota_neutral_satyr_trickster = 95,
    npc_dota_neutral_satyr_soulstealer = 95,
}

local ANCIENTS = {
    npc_dota_neutral_black_dragon = true,
    npc_dota_neutral_granite_golem = true,
    npc_dota_neutral_rock_golem = true,
    npc_dota_neutral_elder_jungle_stalker = true,
    npc_dota_neutral_big_thunder_lizard = true,
    npc_dota_neutral_prowler_acolyte = true,
}

local function GetBounty(unit)
    if NPC.GetGoldBounty then
        local ok, value = pcall(NPC.GetGoldBounty, unit)
        if ok and type(value) == "number" then
            return value
        end
    end
    return GOLD_PRIORITY[NPC.GetUnitName(unit) or ""] or 0
end

local function TryCastHelm(item, allow_ancients)
    if not item then
        return
    end
    if not Ability.IsReady or not Ability.IsReady(item) then
        return
    end
    local hero = runtime.hero
    local hero_pos = hero and Entity.GetAbsOrigin(hero)
    if not hero_pos then
        return
    end

    local range = 800
    if Ability.GetCastRange then
        local ok, r = pcall(Ability.GetCastRange, item)
        if ok and r and r > 0 then
            range = r
        end
    end

    local creeps = NPCs.InRadius(hero_pos, range, runtime.team, Enum.TeamType.TEAM_NEUTRAL)
    if not creeps then
        return
    end

    local best, best_score
    for _, creep in ipairs(creeps) do
        if Entity.IsAlive(creep) then
            local name = NPC.GetUnitName(creep) or ""
            local is_ancient = ANCIENTS[name] or NPC.IsAncient and NPC.IsAncient(creep)
            if not is_ancient or allow_ancients then
                if NPC.IsCreep(creep) and not NPC.IsHero(creep) then
                    local score = GetBounty(creep)
                    if not best or score > best_score then
                        best = creep
                        best_score = score
                    end
                end
            end
        end
    end

    if best then
        if Ability.CastTarget then
            local ok = pcall(Ability.CastTarget, item, best)
            if ok then
                return
            end
        end
        SafeOrder(runtime.hero, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET, best, nil, item)
    end
end

-------------------------------------------------------------------------------
-- Ability metadata
-------------------------------------------------------------------------------
local ABILITY_DATA = {
    mud_golem_hurl_boulder = { behavior = "target", allow_creeps = true, allow_neutrals = true },
    ancient_rock_golem_hurl_boulder = { behavior = "target", allow_creeps = true, allow_neutrals = true },
    granite_golem_hurl_boulder = { behavior = "target", allow_creeps = true, allow_neutrals = true },
    dark_troll_warlord_ensnare = { behavior = "target", allow_creeps = true, allow_neutrals = true },
    dark_troll_warlord_raise_dead = { behavior = "no_target", always_cast = true, requires_charges = true },
    dark_troll_summoner_raise_dead = { behavior = "no_target", always_cast = true, requires_charges = true },
    forest_troll_high_priest_heal = { behavior = "ally_target", prefer_anchor = true, ally_max_health_pct = 0.92 },
    prowler_acolyte_heal = { behavior = "ally_target", prefer_anchor = true, ally_max_health_pct = 0.85 },
    satyr_hellcaller_shockwave = { behavior = "point", allow_creeps = true, allow_neutrals = true },
    satyr_trickster_purge = { behavior = "target", allow_creeps = true, allow_neutrals = true },
    satyr_soulstealer_mana_burn = { behavior = "target", only_heroes = true },
    satyr_mindstealer_mana_burn = { behavior = "target", only_heroes = true },
    harpy_storm_chain_lightning = { behavior = "target", allow_creeps = true, allow_neutrals = true },
    centaur_khan_war_stomp = { behavior = "no_target", requires_melee_range = true, radius = 315 },
    polar_furbolg_ursa_warrior_thunder_clap = { behavior = "no_target", requires_melee_range = true, radius = 325 },
    polar_furbolg_champion_thunder_clap = { behavior = "no_target", requires_melee_range = true, radius = 325 },
    hellbear_smasher_slam = { behavior = "no_target", requires_melee_range = true, radius = 350 },
    ogre_bruiser_ogre_smash = { behavior = "point", allow_creeps = true, requires_melee_range = true },
    ogre_mauler_smash = { behavior = "point", allow_creeps = true, requires_melee_range = true },
    neutral_ogre_magi_ice_armor = { behavior = "ally_target", prefer_anchor = true, avoid_modifier = "modifier_ogre_magi_frost_armor" },
    ogre_magi_frost_armor = { behavior = "ally_target", prefer_anchor = true, avoid_modifier = "modifier_ogre_magi_frost_armor" },
    ancient_black_dragon_fireball = { behavior = "point", allow_creeps = true, allow_neutrals = true },
    ancient_thunderhide_slam = { behavior = "no_target", requires_melee_range = true, radius = 300 },
    big_thunder_lizard_slam = { behavior = "no_target", requires_melee_range = true, radius = 300 },
    ancient_thunderhide_frenzy = { behavior = "ally_target", include_self = false, prefer_anchor = true },
    big_thunder_lizard_frenzy = { behavior = "ally_target", include_self = false, prefer_anchor = true },
    fel_beast_haunt = { behavior = "target", allow_creeps = true, allow_neutrals = true },
    enraged_wildkin_tornado = { behavior = "point", allow_creeps = true, allow_neutrals = true },
    wildkin_hurricane = { behavior = "point", allow_creeps = true, allow_neutrals = true },
    kobold_taskmaster_speed_aura = { behavior = "no_target", always_cast = true, ignore_is_castable = true },
    neutral_spell_immunity = { behavior = "no_target", always_cast = true, ignore_is_castable = true },
}

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

local function AbilityReady(unit, ability, metadata)
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
        if ok then
            return ready
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

local function GetCastRange(unit, ability)
    if Ability.GetCastRange then
        local ok, range = pcall(Ability.GetCastRange, ability)
        if ok and range and range > 0 then
            return range
        end
    end
    return 600
end

local function GetUnitHealthPct(unit)
    local health = Entity.GetHealth(unit) or 0
    local max_health = Entity.GetMaxHealth(unit) or 0
    if max_health <= 0 then
        return 0
    end
    return health / max_health
end

local function EnemyValid(enemy, metadata)
    if not enemy or not Entity.IsAlive(enemy) then
        return false
    end
    if Entity.GetTeamNum(enemy) == runtime.team then
        return false
    end
    if NPC.IsCourier and NPC.IsCourier(enemy) then
        return false
    end
    if metadata then
        if metadata.only_heroes and not NPC.IsHero(enemy) then
            return false
        end
        if not runtime.config.cast_on_enemy_creeps and NPC.IsCreep(enemy) and not NPC.IsHero(enemy) then
            return false
        end
        if metadata.allow_creeps == false and NPC.IsCreep(enemy) and not NPC.IsHero(enemy) then
            return false
        end
        if metadata.allow_neutrals == false and Entity.GetTeamNum(enemy) == Enum.TeamNum.TEAM_NEUTRAL then
            return false
        end
    end
    return true
end

local function AllyValid(ally, metadata)
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
        if metadata.ally_max_health_pct and GetUnitHealthPct(ally) >= metadata.ally_max_health_pct then
            return false
        end
        if metadata.ally_min_health_pct and GetUnitHealthPct(ally) <= metadata.ally_min_health_pct then
            return false
        end
        if metadata.avoid_modifier and NPC.HasModifier(ally, metadata.avoid_modifier) then
            return false
        end
    end
    return true
end

local function FindEnemyTarget(unit, metadata, cast_range, hero_target)
    local hero = runtime.hero
    local hero_pos = hero and Entity.GetAbsOrigin(hero)
    if not hero_pos then
        return nil
    end

    local hero_target_pos = hero_target and Entity.GetAbsOrigin(hero_target) or nil
    if hero_target and hero_target_pos and EnemyValid(hero_target, metadata) then
        local hero_to_enemy = hero_pos:Distance(hero_target_pos)
        if hero_to_enemy <= runtime.config.drop_radius and hero_to_enemy <= cast_range + 50 then
            return hero_target
        end
    end

    local enemies = NPCs.InRadius(hero_pos, math.min(cast_range + 150, runtime.config.drop_radius), runtime.team, Enum.TeamType.TEAM_ENEMY)
    local best, best_score
    if enemies then
        for _, enemy in ipairs(enemies) do
            if EnemyValid(enemy, metadata) then
                local enemy_pos = Entity.GetAbsOrigin(enemy)
                if enemy_pos then
                    local hero_dist = hero_pos:Distance(enemy_pos)
                    if hero_dist <= runtime.config.drop_radius and hero_dist <= cast_range + 150 then
                        local score = -hero_dist
                        if NPC.IsHero(enemy) then
                            score = score + 400
                        end
                        if not best or score > best_score then
                            best = enemy
                            best_score = score
                        end
                    end
                end
            end
        end
    end
    return best
end

local function FindAllyTarget(unit, metadata, cast_range)
    local hero = runtime.hero
    local hero_pos = hero and Entity.GetAbsOrigin(hero)
    if hero and metadata and metadata.prefer_anchor and AllyValid(hero, metadata) then
        local dist = hero_pos and Entity.GetAbsOrigin(unit) and hero_pos:Distance(Entity.GetAbsOrigin(unit)) or nil
        if not dist or dist <= cast_range + 50 then
            return hero
        end
    end

    local unit_pos = Entity.GetAbsOrigin(unit)
    if not unit_pos then
        return nil
    end

    local allies = NPCs.InRadius(unit_pos, cast_range + 100, runtime.team, Enum.TeamType.TEAM_FRIEND)
    local best, best_score
    if allies then
        for _, ally in ipairs(allies) do
            if AllyValid(ally, metadata) then
                local ally_pos = Entity.GetAbsOrigin(ally)
                if ally_pos then
                    local dist = unit_pos:Distance(ally_pos)
                    if dist <= cast_range + 50 then
                        local score = -dist
                        if NPC.IsHero(ally) then
                            score = score + 150
                        end
                        if not best or score > best_score then
                            best = ally
                            best_score = score
                        end
                    end
                end
            end
        end
    end
    return best
end

local function ShouldCastNoTarget(unit, metadata, hero_target)
    if metadata and metadata.always_cast then
        return true
    end
    local radius = (metadata and metadata.radius) or 250
    local hero = runtime.hero
    local hero_pos = hero and Entity.GetAbsOrigin(hero)
    if not hero_pos then
        return false
    end
    local target = hero_target
    local target_pos = target and Entity.GetAbsOrigin(target) or nil
    if target and target_pos and EnemyValid(target, metadata) then
        local dist = hero_pos:Distance(target_pos)
        if dist <= radius + 75 then
            return true
        end
    end
    local enemies = NPCs.InRadius(hero_pos, math.min(radius + 75, runtime.config.drop_radius), runtime.team, Enum.TeamType.TEAM_ENEMY)
    if enemies then
        for _, enemy in ipairs(enemies) do
            if EnemyValid(enemy, metadata) then
                local pos = Entity.GetAbsOrigin(enemy)
                if pos and hero_pos:Distance(pos) <= radius + 75 then
                    return true
                end
            end
        end
    end
    return false
end

local function TryCastAbility(unit, agent, ability, metadata, hero_target)
    if not AbilityReady(unit, ability, metadata) then
        return false
    end

    local behavior = metadata and metadata.behavior or "no_target"
    local cast_range = GetCastRange(unit, ability)

    if behavior == "target" then
        local target = FindEnemyTarget(unit, metadata, cast_range, hero_target)
        if target then
            if metadata and metadata.requires_melee_range then
                local unit_pos = Entity.GetAbsOrigin(unit)
                local target_pos = Entity.GetAbsOrigin(target)
                if unit_pos and target_pos and unit_pos:Distance(target_pos) > 250 then
                    SafeMove(unit, target_pos)
                    agent.state = STATES.ENGAGE
                    agent.last_target = target
                    agent.next_order = GlobalVars.GetCurTime() + runtime.config.order_cooldown
                    return true
                end
            end
            if Ability.CastTarget then
                local ok = pcall(Ability.CastTarget, ability, target)
                if ok then
                    agent.next_order = GlobalVars.GetCurTime() + runtime.config.order_cooldown
                    return true
                end
            end
            SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET, target, nil, ability)
            agent.next_order = GlobalVars.GetCurTime() + runtime.config.order_cooldown
            return true
        end
    elseif behavior == "point" then
        local target = FindEnemyTarget(unit, metadata, cast_range, hero_target)
        if target then
            local pos = Entity.GetAbsOrigin(target)
            if pos then
                if metadata and metadata.requires_melee_range then
                    local unit_pos = Entity.GetAbsOrigin(unit)
                    if unit_pos and unit_pos:Distance(pos) > 250 then
                        SafeMove(unit, pos)
                        agent.state = STATES.ENGAGE
                        agent.last_target = target
                        agent.next_order = GlobalVars.GetCurTime() + runtime.config.order_cooldown
                        return true
                    end
                end
                if Ability.CastPosition then
                    local ok = pcall(Ability.CastPosition, ability, pos)
                    if ok then
                        agent.next_order = GlobalVars.GetCurTime() + runtime.config.order_cooldown
                        return true
                    end
                end
                SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION, nil, pos, ability)
                agent.next_order = GlobalVars.GetCurTime() + runtime.config.order_cooldown
                return true
            end
        end
    elseif behavior == "ally_target" then
        local ally = FindAllyTarget(unit, metadata, cast_range)
        if ally then
            if Ability.CastTarget then
                local ok = pcall(Ability.CastTarget, ability, ally)
                if ok then
                    agent.next_order = GlobalVars.GetCurTime() + runtime.config.order_cooldown
                    return true
                end
            end
            SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET, ally, nil, ability)
            agent.next_order = GlobalVars.GetCurTime() + runtime.config.order_cooldown
            return true
        end
    else -- no_target
        if ShouldCastNoTarget(unit, metadata, hero_target) then
            if Ability.CastNoTarget then
                local ok = pcall(Ability.CastNoTarget, ability)
                if ok then
                    agent.next_order = GlobalVars.GetCurTime() + runtime.config.order_cooldown
                    return true
                end
            end
            SafeOrder(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, nil, ability)
            agent.next_order = GlobalVars.GetCurTime() + runtime.config.order_cooldown
            return true
        end
    end

    return false
end

local function TryCastAbilities(unit, agent, hero_target)
    for slot = 0, 23 do
        local ability = NPC.GetAbilityByIndex(unit, slot)
        if ability then
            local name = Ability.GetName(ability)
            local metadata = ABILITY_DATA[name]
            if metadata and TryCastAbility(unit, agent, ability, metadata, hero_target) then
                return true
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
        next_order = 0,
        manual_until = 0,
        state = STATES.FOLLOW,
        last_target = nil,
    }
end

local function HeroTarget()
    local hero = runtime.hero
    local hero_pos = hero and Entity.GetAbsOrigin(hero)
    if not hero_pos then
        return nil
    end
    local enemies = NPCs.InRadius(hero_pos, runtime.config.attack_radius, runtime.team, Enum.TeamType.TEAM_ENEMY)
    local best, best_score
    if enemies then
        for _, enemy in ipairs(enemies) do
            if EnemyValid(enemy) then
                local pos = Entity.GetAbsOrigin(enemy)
                if pos then
                    local dist = hero_pos:Distance(pos)
                    if dist <= runtime.config.attack_radius then
                        local score = -dist
                        if NPC.IsHero(enemy) then
                            score = score + 400
                        end
                        if not best or score > best_score then
                            best = enemy
                            best_score = score
                        end
                    end
                end
            end
        end
    end
    return best
end

local function FollowHero(unit)
    local hero = runtime.hero
    if not hero then
        return
    end
    local pos = Entity.GetAbsOrigin(hero)
    if pos then
        SafeMove(unit, pos)
    end
end

local function ProcessAgent(agent, now, hero_target)
    local unit = agent.unit
    if not unit or not Entity.IsAlive(unit) then
        return
    end

    if agent.manual_until and agent.manual_until > now then
        agent.state = STATES.MANUAL
        return
    end

    if agent.next_order and agent.next_order > now then
        return
    end

    local hero = runtime.hero
    local hero_pos = hero and Entity.GetAbsOrigin(hero)
    if not hero_pos then
        return
    end

    local unit_pos = Entity.GetAbsOrigin(unit)
    if not unit_pos then
        return
    end

    local hero_target_pos = hero_target and Entity.GetAbsOrigin(hero_target) or nil
    if hero_target and hero_target_pos then
        local hero_to_enemy = hero_pos:Distance(hero_target_pos)
        if hero_to_enemy > runtime.config.drop_radius then
            hero_target = nil
            hero_target_pos = nil
        end
    end

    if TryCastAbilities(unit, agent, hero_target) then
        agent.state = STATES.ENGAGE
        return
    end

    if hero_target and hero_target_pos then
        local hero_dist = hero_pos:Distance(hero_target_pos)
        if hero_dist <= runtime.config.attack_radius then
            SafeAttack(unit, hero_target)
            agent.state = STATES.ENGAGE
            agent.next_order = now + runtime.config.order_cooldown
            agent.last_target = hero_target
            return
        end
    end

    if agent.last_target then
        local last = agent.last_target
        if not Entity.IsAlive(last) then
            agent.last_target = nil
        else
            local last_pos = Entity.GetAbsOrigin(last)
            if last_pos and hero_pos:Distance(last_pos) <= runtime.config.attack_radius then
                SafeAttack(unit, last)
                agent.state = STATES.ENGAGE
                agent.next_order = now + runtime.config.order_cooldown
                return
            end
        end
    end

    local distance = hero_pos:Distance(unit_pos)
    if distance > runtime.config.follow_radius then
        FollowHero(unit)
        agent.state = STATES.FOLLOW
        agent.next_order = now + runtime.config.order_cooldown
    else
        SafeHold(unit)
        agent.state = STATES.FOLLOW
        agent.next_order = now + runtime.config.order_cooldown
    end
end

-------------------------------------------------------------------------------
-- Unit filtering
-------------------------------------------------------------------------------
local SKELETON_NAMES = {
    npc_dota_neutral_dark_troll_warlord_skeleton_warrior = true,
    npc_dota_neutral_dark_troll_warlord_skeleton = true,
    npc_dota_neutral_dark_troll_warlord_skeleton_archer = true,
    npc_dota_neutral_dark_troll_warlord_skeleton_melee = true,
}

local function ControlledByPlayer(unit)
    if runtime.player_id and NPC.IsControllableByPlayer and NPC.IsControllableByPlayer(unit, runtime.player_id) then
        return true
    end
    if runtime.hero then
        local owner = nil
        if Entity.GetOwner then
            local ok, value = pcall(Entity.GetOwner, unit)
            if ok then
                owner = value
            end
        end
        local safety = 0
        while owner and safety < 8 do
            if owner == runtime.hero then
                return true
            end
            if Entity.GetOwner then
                local ok, next_owner = pcall(Entity.GetOwner, owner)
                if ok then
                    owner = next_owner
                else
                    owner = nil
                end
            else
                owner = nil
            end
            safety = safety + 1
        end
    end
    return false
end

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
    if ControlledByPlayer(unit) then
        return true
    end
    local name = NPC.GetUnitName(unit) or ""
    if SKELETON_NAMES[name] then
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- Event handlers
-------------------------------------------------------------------------------
function commander.OnUpdate()
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

    local now = GlobalVars.GetCurTime()

    if now - runtime.last_helm_scan >= runtime.config.helm_scan_rate then
        runtime.last_helm_scan = now
        if runtime.hero then
            local dominator = NPC.GetItem(runtime.hero, "item_helm_of_the_dominator", true)
            local overlord = NPC.GetItem(runtime.hero, "item_helm_of_the_overlord", true)
            TryCastHelm(overlord, true)
            TryCastHelm(dominator, false)
        end
    end

    local hero_target = HeroTarget()

    local next_agents = {}
    local units = NPCs.GetAll()
    if units then
        for _, unit in ipairs(units) do
            if ShouldManageUnit(unit) then
                local handle = Entity.GetIndex(unit)
                local agent = runtime.agents[handle]
                if not agent then
                    agent = CreateAgent(unit)
                end
                agent.unit = unit
                agent.handle = handle
                ProcessAgent(agent, now, hero_target)
                next_agents[handle] = agent
            end
        end
    end

    runtime.agents = next_agents
end

local function FlagManual(unit)
    if not unit then
        return
    end
    local handle = Entity.GetIndex(unit)
    local agent = runtime.agents[handle]
    if agent then
        agent.manual_until = GlobalVars.GetCurTime() + runtime.config.manual_pause
        agent.state = STATES.MANUAL
    end
end

function commander.OnPrepareUnitOrders(event)
    if not runtime.config.enabled then
        return true
    end

    if event.orderIssuer == Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY then
        if event.npc then
            FlagManual(event.npc)
        end
        return true
    end

    local player = AcquirePlayer()
    if player and Player.GetSelectedUnits then
        local selected = Player.GetSelectedUnits(player)
        if selected then
            for _, unit in ipairs(selected) do
                FlagManual(unit)
            end
        end
    end

    return true
end

function commander.OnGameEnd()
    ResetRuntime()
end

return commander
