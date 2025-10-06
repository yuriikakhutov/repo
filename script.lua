local commander = {}

local state = {
    hero = nil,
    team = nil,
    player = nil,
    player_id = nil,
    units = {},
    manual_lock = {},
    last_dominate_attempt = 0,
}

local FOLLOW_DISTANCE = 425
local ATTACK_RADIUS = 1000
local ORDER_COOLDOWN = 0.25
local CAST_COOLDOWN = 0.35
local MANUAL_SUPPRESSION = 0.9

local DOMINATOR_ITEMS = {
    "item_helm_of_the_dominator",
    "item_helm_of_the_overlord",
}

local DOMINATOR_PRIORITY = {
    npc_dota_neutral_black_dragon = 500,
    npc_dota_neutral_granite_golem = 480,
    npc_dota_neutral_elder_jungle_stalker = 460,
    npc_dota_neutral_prowler_acolyte = 450,
    npc_dota_neutral_rock_golem = 440,
    npc_dota_neutral_big_thunder_lizard = 420,
    npc_dota_neutral_dark_troll_warlord = 350,
    npc_dota_neutral_enraged_wildkin = 340,
    npc_dota_neutral_polar_furbolg_ursa_warrior = 330,
    npc_dota_neutral_polar_furbolg_champion = 330,
    npc_dota_neutral_satyr_hellcaller = 320,
    npc_dota_neutral_centaur_khan = 310,
    npc_dota_neutral_ogre_magi = 300,
    npc_dota_neutral_ogre_mauler = 295,
    npc_dota_neutral_mud_golem = 250,
    npc_dota_neutral_fel_beast = 240,
    npc_dota_neutral_wildkin = 230,
    npc_dota_neutral_harpy_storm = 220,
    npc_dota_neutral_alpha_wolf = 215,
}

local ANCIENT_NEUTRALS = {
    npc_dota_neutral_black_dragon = true,
    npc_dota_neutral_granite_golem = true,
    npc_dota_neutral_rock_golem = true,
    npc_dota_neutral_elder_jungle_stalker = true,
    npc_dota_neutral_prowler_acolyte = true,
    npc_dota_neutral_big_thunder_lizard = true,
}

local ability_data = {}

local function register_ability(name, data)
    ability_data[name] = data
    if data.aliases then
        for _, alias in ipairs(data.aliases) do
            ability_data[alias] = data
        end
    end
end

register_ability("mud_golem_hurl_boulder", {
    type = "target",
    allow_neutrals = true,
    min_interval = 0.2,
    message = "boulder",
    aliases = {
        "granite_golem_hurl_boulder",
        "ancient_rock_golem_hurl_boulder",
    },
})

register_ability("dark_troll_warlord_ensnare", {
    type = "target",
    allow_neutrals = true,
})

register_ability("dark_troll_warlord_raise_dead", {
    type = "no_target",
    always = true,
    min_interval = 8,
})

register_ability("forest_troll_high_priest_heal", {
    type = "ally",
    prefer_hero = true,
    ally_max_hp = 0.92,
})

register_ability("satyr_hellcaller_shockwave", {
    type = "point",
    allow_neutrals = true,
})

register_ability("satyr_trickster_purge", {
    type = "target",
    allow_neutrals = true,
    min_interval = 4,
})

register_ability("satyr_soulstealer_mana_burn", {
    type = "target",
    only_heroes = true,
    min_interval = 4,
    aliases = {
        "satyr_mindstealer_mana_burn",
    },
})

register_ability("harpy_storm_chain_lightning", {
    type = "target",
    allow_neutrals = true,
    min_interval = 2.5,
})

register_ability("centaur_khan_war_stomp", {
    type = "no_target",
    radius = 325,
    min_enemies = 1,
    allow_neutrals = true,
})

register_ability("polar_furbolg_ursa_warrior_thunder_clap", {
    type = "no_target",
    radius = 350,
    min_enemies = 1,
    allow_neutrals = true,
    aliases = {
        "polar_furbolg_champion_thunder_clap",
    },
})

register_ability("hellbear_smasher_slam", {
    type = "no_target",
    radius = 350,
    min_enemies = 1,
    allow_neutrals = true,
})

register_ability("ogre_bruiser_ogre_smash", {
    type = "point",
    allow_neutrals = true,
    range_bonus = 60,
    aliases = {
        "ogre_mauler_smash",
    },
})

register_ability("neutral_ogre_magi_ice_armor", {
    type = "ally",
    prefer_hero = true,
    ally_max_hp = 0.97,
    avoid_modifier = "modifier_ogre_magi_frost_armor",
    aliases = {
        "ogre_magi_frost_armor",
    },
})

register_ability("ancient_black_dragon_fireball", {
    type = "point",
    allow_neutrals = true,
    min_interval = 4,
    aliases = {
        "black_dragon_fireball",
    },
})

register_ability("ancient_thunderhide_slam", {
    type = "no_target",
    radius = 325,
    min_enemies = 1,
    allow_neutrals = true,
    aliases = {
        "big_thunder_lizard_slam",
    },
})

register_ability("ancient_thunderhide_frenzy", {
    type = "ally",
    prefer_hero = true,
    include_self = false,
    min_interval = 6,
    aliases = {
        "big_thunder_lizard_frenzy",
    },
})

register_ability("fel_beast_haunt", {
    type = "target",
    allow_neutrals = true,
    min_interval = 4,
})

register_ability("enraged_wildkin_tornado", {
    type = "point",
    allow_neutrals = true,
    min_interval = 12,
    aliases = {
        "wildkin_tornado",
    },
})

register_ability("wildkin_hurricane", {
    type = "point",
    allow_neutrals = true,
    min_interval = 6,
})

register_ability("prowler_acolyte_heal", {
    type = "ally",
    prefer_hero = true,
    ally_max_hp = 0.85,
})

register_ability("kobold_taskmaster_speed_aura", {
    type = "no_target",
    always = true,
    min_interval = 12,
})

register_ability("neutral_spell_immunity", {
    type = "no_target",
    always = true,
    min_interval = 14,
})

local function reset_state()
    state.hero = nil
    state.team = nil
    state.player = nil
    state.player_id = nil
    state.units = {}
    state.manual_lock = {}
    state.last_dominate_attempt = 0
end

local function current_time()
    if GlobalVars and GlobalVars.GetCurTime then
        return GlobalVars.GetCurTime()
    end
    return os.clock()
end

local function ensure_player()
    state.player = Players and Players.GetLocal and Players.GetLocal() or nil
    if state.player and Player and Player.GetPlayerID then
        local ok, pid = pcall(Player.GetPlayerID, state.player)
        if ok and type(pid) == "number" and pid >= 0 then
            state.player_id = pid
        end
    end
end

local function ensure_hero()
    if not Heroes or not Heroes.GetLocal then
        return false
    end

    local hero = Heroes.GetLocal()
    if not hero or not Entity.IsAlive(hero) then
        state.hero = nil
        return false
    end

    state.hero = hero
    state.team = Entity.GetTeamNum(hero)

    if Hero and Hero.GetPlayerID then
        local ok, pid = pcall(Hero.GetPlayerID, hero)
        if ok and type(pid) == "number" and pid >= 0 then
            state.player_id = pid
        end
    end

    if not state.player then
        ensure_player()
    end

    return true
end

local function is_valid_enemy(unit)
    if not unit or not Entity.IsAlive(unit) then
        return false
    end
    if Entity.GetTeamNum(unit) == state.team then
        return false
    end
    if NPC.IsCourier and NPC.IsCourier(unit) then
        return false
    end
    return true
end

local function is_valid_friend(unit)
    if not unit or not Entity.IsAlive(unit) then
        return false
    end
    if Entity.GetTeamNum(unit) ~= state.team then
        return false
    end
    if NPC.IsCourier and NPC.IsCourier(unit) then
        return false
    end
    return true
end

local function should_control(unit)
    if not unit or not Entity.IsAlive(unit) then
        return false
    end
    if unit == state.hero then
        return false
    end
    if NPC.IsIllusion and NPC.IsIllusion(unit) then
        return false
    end
    if NPC.IsCourier and NPC.IsCourier(unit) then
        return false
    end
    if NPC.IsWaitingToSpawn and NPC.IsWaitingToSpawn(unit) then
        return false
    end
    if Entity.GetTeamNum(unit) ~= state.team then
        return false
    end

    if state.player_id and state.player_id >= 0 then
        if NPC.IsControllableByPlayer and NPC.IsControllableByPlayer(unit, state.player_id) then
            return true
        end
        if Entity.IsControllableByPlayer and Entity.IsControllableByPlayer(unit, state.player_id) then
            return true
        end
    end

    if state.hero then
        local owner = NPC.GetOwnerNPC and NPC.GetOwnerNPC(unit)
        if owner and owner == state.hero then
            return true
        end
    end

    return false
end

local function order(unit, order_type, target, position, ability)
    if not state.player or not Player or not Player.PrepareUnitOrders then
        return
    end
    if not Enum or not Enum.UnitOrder or not Enum.PlayerOrderIssuer then
        return
    end

    Player.PrepareUnitOrders(
        state.player,
        order_type,
        target,
        position,
        ability,
        Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY,
        unit,
        false,
        false,
        true
    )
end

local function move_to(unit, position)
    order(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, position, nil)
end

local function attack(unit, target)
    order(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, target, nil, nil)
end

local function cast_target(unit, ability, target)
    if Ability and Ability.CastTarget then
        Ability.CastTarget(ability, target)
    else
        order(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET, target, nil, ability)
    end
end

local function cast_position(unit, ability, position)
    if Ability and Ability.CastPosition then
        Ability.CastPosition(ability, position)
    else
        order(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION, nil, position, ability)
    end
end

local function cast_no_target(unit, ability)
    if Ability and Ability.CastNoTarget then
        Ability.CastNoTarget(ability)
    else
        order(unit, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, nil, ability)
    end
end

local function ability_recently_used(ability, data)
    if not data or not data.min_interval or not Ability or not Ability.SecondsSinceLastUse then
        return false
    end
    local since = Ability.SecondsSinceLastUse(ability)
    if not since or since < 0 then
        return false
    end
    return since < data.min_interval
end

local function ability_ready(unit, ability, data)
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
    if ability_recently_used(ability, data) then
        return false
    end
    if Ability.IsReady then
        return Ability.IsReady(ability)
    end
    if Ability.IsCastable then
        return Ability.IsCastable(ability, NPC.GetMana(unit))
    end
    return false
end

local function ability_range(unit, ability, data)
    if data and data.range then
        return data.range
    end
    if Ability.GetCastRange then
        local ok, range = pcall(Ability.GetCastRange, ability)
        if ok and type(range) == "number" and range > 0 then
            if data and data.range_bonus then
                range = range + data.range_bonus
            end
            return range
        end
    end
    local base = 600
    if data and data.range_bonus then
        base = base + data.range_bonus
    end
    return base
end

local function enemies_near(center, radius, include_neutrals)
    local result = {}
    if not center then
        return result
    end

    local enemies = NPCs and NPCs.InRadius and NPCs.InRadius(center, radius, state.team, Enum.TeamType.TEAM_ENEMY) or {}
    for _, enemy in ipairs(enemies) do
        if is_valid_enemy(enemy) then
            table.insert(result, enemy)
        end
    end

    if include_neutrals then
        local neutrals = NPCs and NPCs.InRadius and NPCs.InRadius(center, radius, state.team, Enum.TeamType.TEAM_NEUTRAL) or {}
        for _, enemy in ipairs(neutrals) do
            if is_valid_enemy(enemy) then
                table.insert(result, enemy)
            end
        end
    end

    return result
end

local function select_enemy(unit, data, range, hero_pos)
    local unit_pos = Entity.GetAbsOrigin(unit)
    local anchors = {}
    if unit_pos then
        table.insert(anchors, unit_pos)
    end
    if hero_pos then
        table.insert(anchors, hero_pos)
    end

    local best_target
    local best_score = -math.huge

    for _, anchor in ipairs(anchors) do
        local targets = enemies_near(anchor, range, data and data.allow_neutrals)
        for _, enemy in ipairs(targets) do
            if not data or not data.only_heroes or NPC.IsHero(enemy) then
                local enemy_pos = Entity.GetAbsOrigin(enemy)
                if enemy_pos then
                    local distance = unit_pos and unit_pos:Distance(enemy_pos) or anchor:Distance(enemy_pos)
                    if distance <= range + 50 then
                        local score = 0
                        if NPC.IsHero and NPC.IsHero(enemy) then
                            score = score + 400
                        end
                        if NPC.IsTower and NPC.IsTower(enemy) then
                            score = score + 120
                        end
                        score = score - distance * 0.5
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

local function select_ally(unit, data, range, hero)
    local unit_pos = Entity.GetAbsOrigin(unit)
    if not unit_pos then
        return nil
    end

    local best
    local best_score = -math.huge

    local function consider(candidate)
        if not is_valid_friend(candidate) then
            return
        end
        if candidate == unit and data and data.include_self == false then
            return
        end
        if data and data.only_heroes and (not NPC.IsHero(candidate)) then
            return
        end
        local pos = Entity.GetAbsOrigin(candidate)
        if not pos or unit_pos:Distance(pos) > range then
            return
        end
        if data and data.avoid_modifier and NPC.HasModifier and NPC.HasModifier(candidate, data.avoid_modifier) then
            return
        end
        local hp = Entity.GetHealth(candidate)
        local max_hp = Entity.GetMaxHealth(candidate)
        local hp_pct = 1
        if hp and max_hp and max_hp > 0 then
            hp_pct = hp / max_hp
        end
        if data and data.ally_max_hp and hp_pct > data.ally_max_hp then
            return
        end
        if data and data.ally_min_hp and hp_pct < data.ally_min_hp then
            return
        end
        local score = -hp_pct * 100
        if NPC.IsHero and NPC.IsHero(candidate) then
            score = score + 200
        end
        if hero and candidate == hero then
            score = score + 150
        end
        if data and data.prefer_hero and hero and candidate == hero then
            score = score + 200
        end
        if score > best_score then
            best_score = score
            best = candidate
        end
    end

    if data and data.prefer_hero and hero then
        consider(hero)
    end

    local allies = NPCs and NPCs.InRadius and NPCs.InRadius(unit_pos, range, state.team, Enum.TeamType.TEAM_FRIEND) or {}
    for _, ally in ipairs(allies) do
        consider(ally)
    end

    return best
end

local function should_cast_no_target(unit, ability, data)
    if data and data.always then
        return true
    end

    local radius = data and data.radius or (Ability and Ability.GetAOERadius and Ability.GetAOERadius(ability)) or 275
    local unit_pos = Entity.GetAbsOrigin(unit)
    if not unit_pos then
        return false
    end

    local targets = enemies_near(unit_pos, radius, data and data.allow_neutrals)
    local required = 1
    if data and data.min_enemies then
        required = data.min_enemies
    end

    return #targets >= required
end

local function try_cast(unit, info, ability, data, now, hero_pos)
    if not ability_ready(unit, ability, data) then
        return false
    end

    local ability_type = data and data.type
    if ability_type == "target" then
        local range = ability_range(unit, ability, data)
        local target = select_enemy(unit, data, range, hero_pos)
        if target then
            cast_target(unit, ability, target)
            info.next_action = now + CAST_COOLDOWN
            info.current_target = target
            return true
        end
    elseif ability_type == "point" then
        local range = ability_range(unit, ability, data)
        local target = select_enemy(unit, data, range, hero_pos)
        local position = target and Entity.GetAbsOrigin(target)
        if position then
            cast_position(unit, ability, position)
            info.next_action = now + CAST_COOLDOWN
            info.current_target = target
            return true
        end
    elseif ability_type == "ally" then
        local range = ability_range(unit, ability, data)
        local ally = select_ally(unit, data, range, state.hero)
        if ally then
            cast_target(unit, ability, ally)
            info.next_action = now + CAST_COOLDOWN
            return true
        end
    elseif ability_type == "no_target" then
        if should_cast_no_target(unit, ability, data) then
            cast_no_target(unit, ability)
            info.next_action = now + CAST_COOLDOWN
            return true
        end
    end

    return false
end

local function process_abilities(unit, info, now, hero_pos)
    if NPC.IsSilenced and NPC.IsSilenced(unit) then
        return false
    end
    if NPC.IsStunned and NPC.IsStunned(unit) then
        return false
    end
    if NPC.IsChannellingAbility and NPC.IsChannellingAbility(unit) then
        return false
    end

    for slot = 0, 23 do
        local ability = NPC.GetAbilityByIndex and NPC.GetAbilityByIndex(unit, slot)
        if not ability then
            break
        end
        local name = Ability and Ability.GetName and Ability.GetName(ability)
        if name then
            local data = ability_data[name]
            if data and try_cast(unit, info, ability, data, now, hero_pos) then
                return true
            end
        end
    end

    return false
end

local function select_attack_target(unit, info, hero_pos)
    local unit_pos = Entity.GetAbsOrigin(unit)
    local best
    local best_score = -math.huge
    local centers = {}

    if unit_pos then
        table.insert(centers, unit_pos)
    end
    if hero_pos then
        table.insert(centers, hero_pos)
    end

    for _, center in ipairs(centers) do
        local enemies = enemies_near(center, ATTACK_RADIUS, true)
        for _, enemy in ipairs(enemies) do
            local enemy_pos = Entity.GetAbsOrigin(enemy)
            if enemy_pos then
                local distance = unit_pos and unit_pos:Distance(enemy_pos) or center:Distance(enemy_pos)
                local score = -distance
                if NPC.IsHero and NPC.IsHero(enemy) then
                    score = score + 400
                end
                if info.current_target and enemy == info.current_target then
                    score = score + 80
                end
                if score > best_score then
                    best_score = score
                    best = enemy
                end
            end
        end
    end

    return best
end

local function process_unit(unit, info, now, hero_pos)
    local handle = Entity.GetIndex(unit)
    local lock = state.manual_lock[handle]
    if lock and lock > now then
        return
    end

    if info.next_action and info.next_action > now then
        return
    end

    if process_abilities(unit, info, now, hero_pos) then
        return
    end

    if info.current_target and (not Entity.IsAlive(info.current_target) or Entity.GetTeamNum(info.current_target) == state.team) then
        info.current_target = nil
    end

    local target = select_attack_target(unit, info, hero_pos)
    if target then
        if info.current_target ~= target then
            attack(unit, target)
            info.current_target = target
            info.next_action = now + ORDER_COOLDOWN
        end
        return
    end

    if not hero_pos then
        return
    end

    local unit_pos = Entity.GetAbsOrigin(unit)
    if not unit_pos then
        return
    end

    local distance = unit_pos:Distance(hero_pos)
    if distance > FOLLOW_DISTANCE then
        move_to(unit, hero_pos)
        info.next_action = now + ORDER_COOLDOWN
    end
end

local function dominator_target(hero, item)
    if not hero or not item then
        return nil
    end
    local hero_pos = Entity.GetAbsOrigin(hero)
    if not hero_pos then
        return nil
    end

    local range = ability_range(hero, item, { range_bonus = 0 })
    if range < 700 then
        range = 700
    end
    local units = NPCs and NPCs.InRadius and NPCs.InRadius(hero_pos, range + 50, state.team, Enum.TeamType.TEAM_NEUTRAL) or {}
    local best
    local best_score = -math.huge
    local allow_ancients = Ability and Ability.GetName and Ability.GetName(item) == "item_helm_of_the_overlord"

    for _, neutral in ipairs(units) do
        if Entity.IsAlive(neutral) and (not NPC.IsWaitingToSpawn or not NPC.IsWaitingToSpawn(neutral)) then
            local name = Entity.GetUnitName(neutral)
            local score = DOMINATOR_PRIORITY[name]
            if score then
                local is_ancient = ANCIENT_NEUTRALS[name] or false
                if not is_ancient or allow_ancients then
                    if not NPC.HasModifier or not NPC.HasModifier(neutral, "modifier_helm_of_the_dominator") then
                        if not NPC.HasModifier or not NPC.HasModifier(neutral, "modifier_helm_of_the_overlord") then
                            if score > best_score then
                                best = neutral
                                best_score = score
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

local function auto_dominate(now)
    if not state.hero then
        return
    end

    if now < state.last_dominate_attempt + 0.35 then
        return
    end

    local item
    for _, name in ipairs(DOMINATOR_ITEMS) do
        item = NPC.GetItem and NPC.GetItem(state.hero, name, true)
        if item and ability_ready(state.hero, item, nil) then
            break
        end
        item = nil
    end

    if not item then
        return
    end

    local target = dominator_target(state.hero, item)
    if target then
        cast_target(state.hero, item, target)
        state.last_dominate_attempt = now
    else
        state.last_dominate_attempt = now
    end
end

function commander.OnUpdate()
    if not Engine or not Engine.IsInGame or not Engine.IsInGame() then
        reset_state()
        return
    end

    if not ensure_hero() then
        return
    end

    ensure_player()

    local now = current_time()
    auto_dominate(now)

    local hero_pos = state.hero and Entity.GetAbsOrigin(state.hero) or nil
    local tracked = {}

    for _, unit in ipairs(NPCs and NPCs.GetAll and NPCs.GetAll() or {}) do
        if should_control(unit) then
            local handle = Entity.GetIndex(unit)
            local info = state.units[handle]
            if not info then
                info = {
                    unit = unit,
                    current_target = nil,
                    next_action = 0,
                }
            end
            info.unit = unit
            tracked[handle] = info
            process_unit(unit, info, now, hero_pos)
        end
    end

    state.units = tracked

    for handle, expiry in pairs(state.manual_lock) do
        if expiry <= now then
            state.manual_lock[handle] = nil
        end
    end
end

function commander.OnPrepareUnitOrders(data)
    if not data or not data.npc then
        return true
    end
    if not Engine or not Engine.IsInGame or not Engine.IsInGame() then
        return true
    end
    if not Entity or not Entity.GetIndex then
        return true
    end

    local now = current_time()
    local handle = Entity.GetIndex(data.npc)
    state.manual_lock[handle] = now + MANUAL_SUPPRESSION

    if data.issuerNpc then
        if type(data.issuerNpc) == "table" then
            for _, unit in ipairs(data.issuerNpc) do
                if unit then
                    state.manual_lock[Entity.GetIndex(unit)] = now + MANUAL_SUPPRESSION
                end
            end
        else
            state.manual_lock[Entity.GetIndex(data.issuerNpc)] = now + MANUAL_SUPPRESSION
        end
    end

    return true
end

function commander.OnGameEnd()
    reset_state()
end

return commander
