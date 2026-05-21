-- Data.lua
-- Scans the local player's professions and recipes using the TBC Classic API
-- Hooks into tradeskill window events so scanning happens automatically
-- Note: Enchanting uses the legacy CraftFrame API, not the standard TradeSkill API

WowCraftData = {}

-- Professions we want to track
local TRACKED_PROFESSIONS = {
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

-- Professions that have scannable recipe lists via the standard TradeSkill API
local HAS_RECIPES = {
    ["Alchemy"]        = true,
    ["Blacksmithing"]  = true,
    ["Engineering"]    = true,
    ["Tailoring"]      = true,
    ["Leatherworking"] = true,
    ["Jewelcrafting"]  = true,
    ["Cooking"]        = true,
}

-- Scans all recipes in the open standard tradeskill window
-- Returns a table of recipe names
local function ScanOpenTradeskill()
    local recipes = {}
    local numSkills = GetNumTradeSkills()

    if not numSkills or numSkills == 0 then
        return recipes
    end

    for i = 1, numSkills do
        local name, skillType = GetTradeSkillInfo(i)
        if name and skillType ~= "header" then
            table.insert(recipes, name)
        end
    end

    return recipes
end

-- Scans all recipes in the open Enchanting CraftFrame window
-- Uses GetNumCrafts() and GetCraftInfo() which are the correct APIs for Enchanting in TBC
-- Returns a table of recipe names
local function ScanOpenCraftSkill()
    local recipes = {}
    local numCrafts = GetNumCrafts()

    if not numCrafts or numCrafts == 0 then
        return recipes
    end

    for i = 1, numCrafts do
        local name, _, skillType = GetCraftInfo(i)
        if name and skillType ~= "header" then
            table.insert(recipes, name)
        end
    end

    return recipes
end

-- Saves profession and recipe data for the given profession name, level and recipes
local function SaveProfessionData(profName, level, maxLevel, recipes)
    local playerKey = WowCraftStorage.GetPlayerKey()
    local existing = WowCraftStorage.GetMember(playerKey) or {}

    if not existing.professions then existing.professions = {} end
    if not existing.recipes then existing.recipes = {} end

    existing.professions[profName] = {
        level    = level,
        maxLevel = maxLevel,
    }

    if recipes then
        existing.recipes[profName] = recipes
        print("|cff00ccff[WowCraft]|r Scanned " .. profName .. ": " .. level .. "/" .. maxLevel .. " — " .. #recipes .. " recipes.")
    else
        print("|cff00ccff[WowCraft]|r Scanned " .. profName .. ": " .. level .. "/" .. maxLevel .. ".")
    end

    WowCraftStorage.SaveMember(playerKey, existing)
end

-- Called when a standard tradeskill window opens (TRADE_SKILL_SHOW)
function WowCraftData.OnTradeskillShow()
    local profName, level, maxLevel = GetTradeSkillLine()

    if not profName or profName == "UNKNOWN" then
        print("|cff00ccff[WowCraft]|r Could not identify this profession window.")
        return
    end

    if not TRACKED_PROFESSIONS[profName] then
        return
    end

    local recipes = nil
    if HAS_RECIPES[profName] then
        recipes = ScanOpenTradeskill()
    end

    SaveProfessionData(profName, level, maxLevel, recipes)
end

-- Called when the Enchanting CraftFrame window opens (CRAFT_SHOW)
-- Enchanting uses a completely separate API from all other professions in TBC Classic:
-- GetNumCrafts() instead of GetNumTradeSkills()
-- GetCraftInfo() instead of GetTradeSkillInfo()
-- GetCraftLine() does not exist on this client so we hardcode the profession name
function WowCraftData.OnCraftShow()
    local recipes = ScanOpenCraftSkill()
    -- GetCraftLine() is not available on TBC Anniversary
    -- Enchanting is the only profession using CraftFrame so hardcoding is safe
    SaveProfessionData("Enchanting", 375, 375, recipes)
end

-- Returns a summary of what has been scanned so far for the local player
function WowCraftData.GetLocalSnapshot()
    local playerKey = WowCraftStorage.GetPlayerKey()
    local stored = WowCraftStorage.GetMember(playerKey)

    if not stored then
        local fresh = { professions = {}, recipes = {} }
        WowCraftStorage.SaveMember(playerKey, fresh)
        return fresh
    end

    return stored
end
