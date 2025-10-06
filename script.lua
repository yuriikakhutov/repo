local dominator_helper = {}

local hero_state = {
    hero = nil,
    team = nil,
    last_scan = 0,
    last_cast = {
        item_helm_of_the_dominator = 0,
        item_helm_of_the_overlord = 0,
    },
}

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

local SCAN_INTERVAL = 0.15

local function reset_state()
    hero_state.hero = nil
    hero_state.team = nil
    hero_state.last_scan = 0
    hero_state.last_cast.item_helm_of_the_dominator = 0
    hero_state.last_cast.item_helm_of_the_overlord = 0
end

local function is_item_ready(item, mana)
    if not item then
        return false
    end

    if Ability.GetLevel and Ability.GetLevel(item) <= 0 then
        return false
    end

    if Ability.GetCooldownTimeRemaining then
        local ok, remaining = pcall(Ability.GetCooldownTimeRemaining, item)
        if ok and remaining and remaining > 0 then
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
    if not hero or not name then
        return nil
    end

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

local function is_valid_target(unit, allow_ancients)
    if not unit or not Entity.IsAlive(unit) then
        return false
    end

    if Entity.GetTeamNum(unit) ~= Enum.TeamNum.TEAM_NEUTRAL then
        return false
    end

    local name = NPC.GetUnitName(unit)
    if not allow_ancients and (ANCIENT_UNITS[name] or (NPC.IsAncient and NPC.IsAncient(unit))) then
        return false
    end

    if NPC.IsCourier and NPC.IsCourier(unit) then
        return false
    end

    if NPC.IsRoshan and NPC.IsRoshan(unit) then
        return false
    end

    return true
end

local function creep_score(unit, prefer_ancients)
    local name = NPC.GetUnitName(unit)
    local score = GOLD_PRIORITY[name] or 0

    if prefer_ancients then
        if ANCIENT_UNITS[name] or (NPC.IsAncient and NPC.IsAncient(unit)) then
            score = score + 300
        end
    end

    if score <= 0 then
        if NPC.GetBountyXP then
            local ok, xp = pcall(NPC.GetBountyXP, unit)
            if ok and xp and xp > 0 then
                score = score + xp / 2
            end
        end
    end

    if score <= 0 then
        score = 10
    end

    local health = Entity.GetHealth(unit) or 0
    score = score - health * 0.001

    return score
end

local function find_best_creep(hero, allow_ancients, prefer_ancients, range)
    local origin = Entity.GetAbsOrigin(hero)
    if not origin then
        return nil
    end

    local neutrals = NPCs.InRadius(origin, range, hero_state.team, Enum.TeamType.TEAM_NEUTRAL)
    if not neutrals or #neutrals == 0 then
        return nil
    end

    local best_unit = nil
    local best_score = -math.huge

    for _, unit in ipairs(neutrals) do
        if is_valid_target(unit, allow_ancients) then
            local distance = origin:Distance(Entity.GetAbsOrigin(unit))
            if distance <= range then
                local score = creep_score(unit, prefer_ancients)
                if score > best_score then
                    best_score = score
                    best_unit = unit
                end
            end
        end
    end

    return best_unit
end

local function cast_item_on_creep(hero, item_name, allow_ancients, prefer_ancients)
    local item = get_item(hero, item_name)
    if not item then
        return
    end

    local mana = NPC.GetMana and NPC.GetMana(hero) or 0
    if not is_item_ready(item, mana) then
        return
    end

    local now = GlobalVars.GetCurTime()
    if now - (hero_state.last_cast[item_name] or 0) < SCAN_INTERVAL then
        return
    end

    local range = Ability.GetCastRange and Ability.GetCastRange(item) or 0
    if not range or range <= 0 then
        range = 1200
    else
        range = range + 50
    end

    local target = find_best_creep(hero, allow_ancients, prefer_ancients, range)
    if not target then
        return
    end

    hero_state.last_cast[item_name] = now

    if Ability.CastTarget then
        local ok = pcall(Ability.CastTarget, item, target)
        if ok then
            return
        end
    end

    local player = Player.GetLocal and Player.GetLocal() or nil
    if not player then
        return
    end

    Player.PrepareUnitOrders(
        player,
        Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET,
        target,
        Entity.GetAbsOrigin(target),
        item,
        Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_HERO_ONLY,
        hero
    )
end

function dominator_helper.OnUpdate()
    if not Engine.IsInGame() then
        reset_state()
        return
    end

    local hero = hero_state.hero
    if not hero or not Entity.IsAlive(hero) then
        hero = Heroes.GetLocal()
        if hero and Entity.IsAlive(hero) then
            hero_state.hero = hero
            hero_state.team = Entity.GetTeamNum(hero)
        else
            return
        end
    end

    local now = GlobalVars.GetCurTime()
    if now - hero_state.last_scan < SCAN_INTERVAL then
        return
    end
    hero_state.last_scan = now

    cast_item_on_creep(hero, "item_helm_of_the_overlord", true, true)
    cast_item_on_creep(hero, "item_helm_of_the_dominator", false, false)
end

function dominator_helper.OnGameEnd()
    reset_state()
end

return dominator_helper

