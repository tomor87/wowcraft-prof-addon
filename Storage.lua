-- Storage.lua
-- Everything that touches WowCraftDB lives here.
-- WowCraftDB is the SavedVariables table — WoW writes it to disk on logout
-- so data survives between sessions without us doing anything special.
--
-- Data is keyed by "Name-Realm" strings so characters on different realms
-- don't collide. We call that the playerKey throughout the codebase.

WowCraftStorage = {}

-- Called on PLAYER_LOGIN once SavedVariables have been loaded by the client
function WowCraftStorage.Init()
    if not WowCraftDB then
        WowCraftDB = {}
    end

    -- profession/recipe data for each guild member, keyed by playerKey
    if not WowCraftDB.members then
        WowCraftDB.members = {}
    end

    -- unix timestamps of each member's last sync, keyed by playerKey
    if not WowCraftDB.lastSeen then
        WowCraftDB.lastSeen = {}
    end
end

-- Returns "Name-Realm" for the logged in character
function WowCraftStorage.GetPlayerKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

-- Saves a member's profession/recipe data and stamps the current time
function WowCraftStorage.SaveMember(playerKey, data)
    WowCraftDB.members[playerKey]  = data
    WowCraftDB.lastSeen[playerKey] = time()
end

function WowCraftStorage.GetMember(playerKey)
    return WowCraftDB.members[playerKey]
end

function WowCraftStorage.GetAllMembers()
    return WowCraftDB.members
end

function WowCraftStorage.GetLastSeen(playerKey)
    return WowCraftDB.lastSeen[playerKey]
end

function WowCraftStorage.RemoveMember(playerKey)
    WowCraftDB.members[playerKey]  = nil
    WowCraftDB.lastSeen[playerKey] = nil
end

-- Wipes everything — useful if the data gets into a weird state
function WowCraftStorage.Reset()
    WowCraftDB.members  = {}
    WowCraftDB.lastSeen = {}
    print("|cff00ccff[WowCraft]|r All stored data cleared.")
end
