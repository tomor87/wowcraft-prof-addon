-- Data.lua
-- Scans the local player's professions and recipes.
--
-- The scanning hooks into tradeskill window events rather than running
-- on a timer, so there's no performance cost when you're just playing normally.
-- Open a tradeskill window and it scans automatically.
--
-- Enchanting is a special case. Blizzard never ported it to the standard
-- TradeSkill API in Classic — it still uses the old CraftFrame system from
-- vanilla. That means completely different function names and a different
-- event to listen for. See OnCraftShow() below.

WowCraftData = {}

-- Professions we care about. Fishing has no recipe window so it's excluded.
-- First Aid excluded by design.
local TRACKED = {
    ["Alchemy"]        = true,
    ["Blacksmithing"]  = true,
    ["Enchanting"]     = true,
    ["Engineering"]    = true,
    ["Herbalism"]      = true,
    ["Mining"]         = true,
    ["Skinning"]       = true,
    ["Tailoring"]      = true,
    ["Leatherworking"] = true,
    ["Jewelcrafting"]  = true,
    ["Cooking"]        = true,
}

-- These use the standard TradeSkill API and have scannable recipe lists.
-- Enchanting is handled separately via the CraftFrame API.
-- Herbalism/Mining/Skinning have no recipes to scan.
local HAS_RECIPES = {
    ["Alchemy"]        = true,
    ["Blacksmithing"]  = true,
    ["Engineering"]    = true,
    ["Tailoring"]      = true,
    ["Leatherworking"] = true,
    ["Jewelcrafting"]  = true,
    ["Cooking"]        = true,
}

-- Reads every recipe from the currently open standard tradeskill window.
-- Skips header rows (category labels like "Armor", "Weapons" etc).
local function ScanTradeskill()
    local recipes = {}
    local total   = GetNumTradeSkills()
    if not total or total == 0 then return recipes end

    for i = 1, total do
        local name, skillType = GetTradeSkillInfo(i)
        if name and skillType ~= "header" then
            table.insert(recipes, name)
        end
    end

    return recipes
end

-- Same thing but for the Enchanting CraftFrame.
-- GetCraftInfo returns slightly different fields to GetTradeSkillInfo.
local function ScanCraftSkill()
    local recipes = {}
    local total   = GetNumCrafts()
    if not total or total == 0 then return recipes end

    for i = 1, total do
        local name, _, skillType = GetCraftInfo(i)
        if name and skillType ~= "header" then
            table.insert(recipes, name)
        end
    end

    return recipes
end

-- Writes profession + recipe data into storage for the local player.
local function Save(profName, level, maxLevel, recipes)
    local playerKey = WowCraftStorage.GetPlayerKey()
    local existing  = WowCraftStorage.GetMember(playerKey) or {}

    if not existing.professions then existing.professions = {} end
    if not existing.recipes     then existing.recipes     = {} end

    existing.professions[profName] = {
        level    = level,
        maxLevel = maxLevel,
    }

    if recipes then
        existing.recipes[profName] = recipes
        print("|cff00ccff[WowCraft]|r Scanned " .. profName
            .. " " .. level .. "/" .. maxLevel
            .. " — " .. #recipes .. " recipes.")
    else
        print("|cff00ccff[WowCraft]|r Scanned " .. profName
            .. " " .. level .. "/" .. maxLevel .. ".")
    end

    WowCraftStorage.SaveMember(playerKey, existing)
end

-- Fires when a standard tradeskill window opens (TRADE_SKILL_SHOW).
function WowCraftData.OnTradeskillShow()
    local profName, level, maxLevel = GetTradeSkillLine()

    if not profName or profName == "UNKNOWN" then
        print("|cff00ccff[WowCraft]|r Couldn't read this profession window.")
        return
    end

    if not TRACKED[profName] then return end

    Save(profName, level, maxLevel, HAS_RECIPES[profName] and ScanTradeskill() or nil)
end

-- Fires when the Enchanting window opens (CRAFT_SHOW).
-- GetCraftLine() doesn't exist on the TBC Anniversary client so we
-- hardcode the name. Enchanting is the only thing that uses CraftFrame
-- so this is safe. Level is also hardcoded to 375 since the API won't
-- give us the real value — something to revisit if Blizzard ever fixes it.
function WowCraftData.OnCraftShow()
    Save("Enchanting", 375, 375, ScanCraftSkill())
end

-- Returns whatever we've scanned for the local player so far.
-- Sync.lua calls this when broadcasting to the guild.
function WowCraftData.GetLocalSnapshot()
    local playerKey = WowCraftStorage.GetPlayerKey()
    local stored    = WowCraftStorage.GetMember(playerKey)

    if not stored then
        local fresh = { professions = {}, recipes = {} }
        WowCraftStorage.SaveMember(playerKey, fresh)
        return fresh
    end

    return stored
end
