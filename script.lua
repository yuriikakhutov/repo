---@diagnostic disable: undefined-global

local auto_dominator = {}

local DOMINATOR_ITEMS = {
    "item_helm_of_the_dominator",
    "item_helm_of_the_overlord",
}

local BIG_NEUTRAL_NAMES = {
    npc_dota_neutral_alpha_wolf = true,
    npc_dota_neutral_centaur_khan = true,
    npc_dota_neutral_dark_troll_warlord = true,
    npc_dota_neutral_enraged_wildkin = true,
    npc_dota_neutral_hellbear_smasher = true,
    npc_dota_neutral_mud_golem = true,
    npc_dota_neutral_ogre_bruiser = true,
    npc_dota_neutral_ogre_magi = true,
    npc_dota_neutral_polar_furbolg_ursa_warrior = true,
    npc_dota_neutral_satyr_hellcaller = true,
    npc_dota_neutral_warpine_raider = true,
}

local BIG_NEUTRAL_MIN_HEALTH = 700
local CAST_RANGE_BUFFER = 50
local ORDER_COOLDOWN = 0.25

local last_cast_time = 0

local function is_big_neutral(npc)
    if not npc or not Entity.IsNPC(npc) then
        return false
    end

    if not Entity.IsAlive(npc) or Entity.IsDormant(npc) then
        return false
    end

    if not NPC.IsNeutral(npc) or NPC.IsAncient(npc) then
        return false
    end

    local name = NPC.GetUnitName(npc)
    if name and BIG_NEUTRAL_NAMES[name] then
        return true
    end

    local max_health = Entity.GetMaxHealth(npc)
    if max_health and max_health >= BIG_NEUTRAL_MIN_HEALTH then
        return true
    end

    return false
end

local function get_dominator_item(hero)
    for _, item_name in ipairs(DOMINATOR_ITEMS) do
        local item = NPC.GetItem(hero, item_name, true)
        if item and Ability.IsReady(item) then
            return item
        end
    end

    return nil
end

local function find_best_target(origin, range)
    local best_target = nil
    local best_health = -1

    for _, npc in pairs(NPCs.GetAll()) do
        if is_big_neutral(npc) then
            local npc_pos = Entity.GetAbsOrigin(npc)
            local distance = npc_pos:Distance2D(origin)
            if distance <= range then
                local health = Entity.GetHealth(npc) or 0
                if health > best_health then
                    best_health = health
                    best_target = npc
                end
            end
        end
    end

    return best_target
end

function auto_dominator.OnUpdate()
    if not Engine.IsInGame() then
        return
    end

    local hero = Heroes.GetLocal()
    if not hero or not Entity.IsAlive(hero) or Entity.IsDormant(hero) then
        return
    end

    if NPC.IsIllusion(hero) or NPC.IsStunned(hero) or NPC.IsChannellingAbility(hero) then
        return
    end

    local dominator = get_dominator_item(hero)
    if not dominator then
        return
    end

    local mana = NPC.GetMana(hero)
    if not Ability.IsCastable(dominator, mana) then
        return
    end

    local game_time = GameRules.GetGameTime()
    if last_cast_time > 0 and (game_time - last_cast_time) < ORDER_COOLDOWN then
        return
    end

    local hero_origin = Entity.GetAbsOrigin(hero)
    local cast_range = Ability.GetCastRange(dominator) or 0
    if cast_range < 0 then
        cast_range = 0
    end
    cast_range = cast_range + CAST_RANGE_BUFFER

    local target = find_best_target(hero_origin, cast_range)
    if not target then
        return
    end

    Ability.CastTarget(dominator, target)
    last_cast_time = game_time
end

return auto_dominator
