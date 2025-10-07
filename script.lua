---@diagnostic disable: undefined-global

local script = {}

local DARK_TROLL_WARLORD_NAME <const> = "npc_dota_neutral_dark_troll_warlord"
local RAISE_DEAD_SLOT <const> = 0

local function find_player_id()
    if not Players or not Players.GetLocal then
        return nil
    end

    local player = Players.GetLocal()
    if not player or not Player or not Player.GetPlayerID then
        return nil
    end

    local id = Player.GetPlayerID(player)
    if not id or id < 0 then
        return nil
    end

    return id
end

local function can_cast_raise_dead(ability, mana)
    if not ability or Ability.IsHidden and Ability.IsHidden(ability) then
        return false
    end

    if Ability.GetLevel and Ability.GetLevel(ability) <= 0 then
        return false
    end

    if Ability.IsActivated and not Ability.IsActivated(ability) then
        return false
    end

    if Ability.IsReady and not Ability.IsReady(ability) then
        return false
    end

    if Ability.IsCastable and not Ability.IsCastable(ability, mana or 0) then
        return false
    end

    return true
end

local function cast_raise_dead(npc)
    if not NPC or not NPC.GetAbilityByIndex or not Ability or not Ability.CastNoTarget then
        return
    end

    local ability = NPC.GetAbilityByIndex(npc, RAISE_DEAD_SLOT)
    if not ability then
        return
    end

    local mana = NPC.GetMana and NPC.GetMana(npc) or 0
    if not can_cast_raise_dead(ability, mana) then
        return
    end

    Ability.CastNoTarget(ability)
end

function script.OnUpdate()
    local player_id = find_player_id()
    if not player_id then
        return
    end

    if not NPCs or not NPCs.GetAll then
        return
    end

    for _, npc in pairs(NPCs.GetAll()) do
        if npc and Entity and Entity.IsAlive and Entity.IsAlive(npc) and not Entity.IsDormant(npc) then
            if NPC.IsControllableByPlayer and NPC.IsControllableByPlayer(npc, player_id) then
                if NPC.GetUnitName and NPC.GetUnitName(npc) == DARK_TROLL_WARLORD_NAME then
                    cast_raise_dead(npc)
                end
            end
        end
    end
end

return script
