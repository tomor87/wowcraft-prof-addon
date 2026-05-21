-- Data.lua
-- Scans the local player's professions and recipes using the TBC Classic API
-- Hooks into tradeskill window events so scanning happens automatically

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
    ["Fishing"]        = true,
}

-- Professions that have scannable recipe lists
local HAS_RECIPES = {
    ["Alchemy"]        = true,
    ["Blacksmithing"]  = true,
    ["Enchanting"]     = true,
    ["Engineering"]    = true,
    ["Tailoring"]      = true,
    ["Leatherworking"] = true,
    ["Jewelcrafting"]  = true,
    ["Cooking"]        = true,
}

-- Scans all recipes currently visible in the open tradeskill window
-- Returns a table of recipe names
local function ScanOpenTradeskill()
    local recipes = {}
    local numSkills = GetNumTradeSkills()

    if not numSkills or numSkills == 0 then
        return recipes
    end

    for i = 1, numSkills do
        local name, skillType = GetTradeSkillInfo(i)
        -- skillType is "header" for category rows, skip those
        if name and skillType ~= "header" then
            table.insert(recipes, name)
        end
    end

    return recipes
end

-- Called when the player opens a tradeskill window
-- Uses GetTradeSkillLine() to identify the profession and get its level
function WowCraftData.OnTradeskillShow()
    local profName, _, level, maxLevel = GetTradeSkillLine()

    if not profName or profName == "UNKNOWN" then
        print("|cff00ccff[WowCraft]|r Could not identify this profession window.")
        return
    end

    if not TRACKED_PROFESSIONS[profName] then
        return
    end

    local playerKey = WowCraftStorage.GetPlayerKey()
    local existing = WowCraftStorage.GetMember(playerKey) or {}

    if not existing.professions then
        existing.professions = {}
    end

    if not existing.recipes then
        existing.recipes = {}
    end

    -- Update profession level from this window
    existing.professions[profName] = {
        level    = level,
        maxLevel = maxLevel,
    }

    -- Scan recipes if this profession has them
    if HAS_RECIPES[profName] then
        local recipes = ScanOpenTradeskill()
        existing.recipes[profName] = recipes
        print("|cff00ccff[WowCraft]|r Scanned " .. #recipes .. " " .. profName .. " recipes.")
    else
        print("|cff00ccff[WowCraft]|r Recorded " .. profName .. " " .. level .. "/" .. maxLevel .. ".")
    end

    WowCraftStorage.SaveMember(playerKey, existing)
end

-- Returns the locally stored snapshot for this player
-- Unlike before, we no longer try to scan levels without a window open
function WowCraftData.GetLocalSnapshot()
    local playerKey = WowCraftStorage.GetPlayerKey()
    local stored = WowCraftStorage.GetMember(playerKey)

    if stored then
        return stored
    else
        local fresh = {
            professions = {},
            recipes     = {},
        }
        WowCraftStorage.SaveMember(playerKey, fresh)
        return fresh
    end
end

-- Debug helper - prints everything stored for the local player
function WowCraftData.PrintLocalData()
    local playerKey = WowCraftStorage.GetPlayerKey()
    local data = WowCraftStorage.GetMember(playerKey)

    if not data then
        print("|cff00ccff[WowCraft]|r No data stored yet. Open your tradeskill windows to scan.")
        return
    end

    print("|cff00ccff[WowCraft]|r Data for " .. playerKey .. ":")

    if data.professions then
        for name, info in pairs(data.professions) do
            print("  " .. name .. " " .. info.level .. "/" .. info.maxLevel)
            if data.recipes and data.recipes[name] then
                print("    Recipes: " .. #data.recipes[name])
            end
        end
    else
        print("  No professions scanned yet.")
    end
end
