-- Storage.lua
-- Handles all reading and writing to WowCraftDB (SavedVariables)

WowCraftStorage = {}

-- Called from Core.lua on PLAYER_LOGIN after SavedVariables are loaded
function WowCraftStorage.Init()
    if not WowCraftDB then
        WowCraftDB = {}
    end

    -- guild member profession data, keyed by "Name-Realm"
    if not WowCraftDB.members then
        WowCraftDB.members = {}
    end

    -- when each member's data was last updated, keyed by "Name-Realm"
    if not WowCraftDB.lastSeen then
        WowCraftDB.lastSeen = {}
    end
end

-- Returns the full player key "Name-Realm" for the local player
function WowCraftStorage.GetPlayerKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end

-- Saves profession data for a given player key
-- data is a table of professions, see Data.lua for structure
function WowCraftStorage.SaveMember(playerKey, data)
    WowCraftDB.members[playerKey] = data
    WowCraftDB.lastSeen[playerKey] = time()
end

-- Returns stored data for a given player key, or nil if not found
function WowCraftStorage.GetMember(playerKey)
    return WowCraftDB.members[playerKey]
end

-- Returns the full members table
function WowCraftStorage.GetAllMembers()
    return WowCraftDB.members
end

-- Returns the last seen timestamp for a player key, or nil
function WowCraftStorage.GetLastSeen(playerKey)
    return WowCraftDB.lastSeen[playerKey]
end

-- Removes a member's data entirely (e.g. if they leave the guild)
function WowCraftStorage.RemoveMember(playerKey)
    WowCraftDB.members[playerKey] = nil
    WowCraftDB.lastSeen[playerKey] = nil
end

-- Wipes all stored data — useful for a full resync
function WowCraftStorage.Reset()
    WowCraftDB.members = {}
    WowCraftDB.lastSeen = {}
    print("|cff00ccff[WowCraft]|r All stored data has been cleared.")
end
