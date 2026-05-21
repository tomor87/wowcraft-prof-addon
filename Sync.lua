-- Sync.lua
-- Handles broadcasting local profession/recipe data to guild members
-- and receiving data from other guild members who have the addon.
--
-- Data is serialised, split into chunks (WoW addon messages are capped at 255 chars),
-- sent invisibly over the GUILD addon channel, then reassembled on the receiving end.
--
-- No messages appear in guild chat. This is all background traffic.
--
-- Discord integration note:
-- WowCraftDB (SavedVariables) is written to disk on logout/reload at:
-- World of Warcraft\_anniversary_\WTF\Account\<account>\SavedVariables\wowcraft.lua
-- A companion app or Discord bot can read this file and post profession data to Discord.

WowCraftSync = {}

local PREFIX    = "WowCraft"
local MAX_CHUNK = 200    -- safely under the 255 char hard limit
local SEP       = "\031" -- ASCII unit separator, invisible and safe in addon messages
local SYNC_COOLDOWN = 300 -- seconds between syncs (5 minutes)

-- Buffer for reassembling incoming chunked messages, keyed by playerKey
local incoming = {}

-- Timestamp of last sync broadcast, to enforce cooldown
local lastSyncTime = 0

-- ============================================================
-- Initialisation
-- ============================================================

function WowCraftSync.Init()
    -- Register our prefix so the client passes addon messages to us
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    else
        RegisterAddonMessagePrefix(PREFIX)
    end
end

-- ============================================================
-- Serialisation
-- Converts Lua tables into a compact string for transmission.
-- Supports strings, numbers, booleans, and nested tables.
-- ============================================================

local function Serialise(val)
    local t = type(val)
    if t == "string" then
        return "s:" .. val:gsub(SEP, "")
    elseif t == "number" then
        return "n:" .. tostring(val)
    elseif t == "boolean" then
        return "b:" .. (val and "1" or "0")
    elseif t == "table" then
        local parts = {}
        for k, v in pairs(val) do
            table.insert(parts, Serialise(k) .. "=" .. Serialise(v))
        end
        return "t:{" .. table.concat(parts, ",") .. "}"
    end
    return "n:0"
end

local function Deserialise(str)
    if not str or str == "" then return nil end

    local tag = str:sub(1, 2)

    if tag == "s:" then
        return str:sub(3)

    elseif tag == "n:" then
        return tonumber(str:sub(3))

    elseif tag == "b:" then
        return str:sub(3) == "1"

    elseif tag == "t:" then
        local inner = str:sub(4, -2) -- strip leading "t:{" and trailing "}"
        if inner == "" then return {} end

        local result = {}
        local depth   = 0
        local current = ""
        local parts   = {}

        for i = 1, #inner do
            local c = inner:sub(i, i)
            if c == "{" then
                depth   = depth + 1
                current = current .. c
            elseif c == "}" then
                depth   = depth - 1
                current = current .. c
            elseif c == "," and depth == 0 then
                table.insert(parts, current)
                current = ""
            else
                current = current .. c
            end
        end
        if current ~= "" then
            table.insert(parts, current)
        end

        for _, part in ipairs(parts) do
            local eqPos = part:find("=")
            if eqPos then
                local k = Deserialise(part:sub(1, eqPos - 1))
                local v = Deserialise(part:sub(eqPos + 1))
                if k ~= nil then result[k] = v end
            end
        end

        return result
    end

    return nil
end

-- ============================================================
-- Chunking
-- Splits a long string into MAX_CHUNK sized pieces.
-- ============================================================

local function ChunkString(str)
    local chunks = {}
    local len = #str
    local i = 1
    while i <= len do
        table.insert(chunks, str:sub(i, i + MAX_CHUNK - 1))
        i = i + MAX_CHUNK
    end
    return chunks
end

-- ============================================================
-- Sending
-- ============================================================

local function SendGuild(msg)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")
    else
        SendAddonMessage(PREFIX, msg, "GUILD")
    end
end

-- Broadcasts the local player's scanned data to all online guild members.
-- Each chunk is prefixed: playerKey SEP total SEP index SEP data
-- Enforces a 5 minute cooldown to prevent accidental spam.
function WowCraftSync.BroadcastMyData()
    local now = time()
    if now - lastSyncTime < SYNC_COOLDOWN then
        local remaining = SYNC_COOLDOWN - (now - lastSyncTime)
        print("|cff00ccff[WowCraft]|r Please wait " .. remaining .. "s before syncing again.")
        return
    end

    local snapshot = WowCraftData.GetLocalSnapshot()

    -- Check we actually have something to send
    local profCount = 0
    for _ in pairs(snapshot.professions) do profCount = profCount + 1 end
    if profCount == 0 then
        print("|cff00ccff[WowCraft]|r No profession data found. Open your tradeskill windows first, then sync.")
        return
    end

    local playerKey  = WowCraftStorage.GetPlayerKey()
    local serialised = Serialise(snapshot)
    local chunks     = ChunkString(serialised)
    local total      = #chunks

    for i, chunk in ipairs(chunks) do
        local msg = playerKey .. SEP .. total .. SEP .. i .. SEP .. chunk
        SendGuild(msg)
    end

    lastSyncTime = now
    print("|cff00ccff[WowCraft]|r Data synced to guild (" .. total .. " packet(s), " .. profCount .. " profession(s)).")
end

-- Sends a ping to ask all online guild members with the addon to broadcast their data.
-- Useful when you first log in and want to populate your local database.
function WowCraftSync.RequestAllData()
    SendGuild("REQUEST" .. SEP .. WowCraftStorage.GetPlayerKey())
    print("|cff00ccff[WowCraft]|r Requested data from online guild members.")
end

-- ============================================================
-- Receiving
-- ============================================================

-- Processes a fully reassembled serialised data string from another player
local function ProcessIncomingData(playerKey, serialised)
    local data = Deserialise(serialised)
    if not data then
        print("|cff00ccff[WowCraft]|r Received malformed data from " .. playerKey)
        return
    end

    WowCraftStorage.SaveMember(playerKey, data)

    -- Count professions for feedback
    local profCount = 0
    if data.professions then
        for _ in pairs(data.professions) do profCount = profCount + 1 end
    end

    print("|cff00ccff[WowCraft]|r Received data from " .. playerKey .. " (" .. profCount .. " profession(s)).")

    -- Notify the UI to refresh if it's open
    if WowCraftUI and WowCraftUI.Refresh then
        WowCraftUI.Refresh()
    end
end

-- Called from Core.lua when a CHAT_MSG_ADDON event fires for our prefix
function WowCraftSync.OnAddonMessage(msg, channel, sender)
    -- Handle data requests — someone wants our data
    if msg:sub(1, 7) == "REQUEST" then
        -- Small random delay (0-3s) so not everyone responds simultaneously
        local delay = math.random(0, 3)
        C_Timer.After(delay, function()
            WowCraftSync.BroadcastMyData()
        end)
        return
    end

    -- Parse chunked data message: playerKey SEP total SEP index SEP data
    local parts = {}
    local pattern = "([^" .. SEP .. "]*)" .. SEP .. "?"
    for part in msg:gmatch(pattern) do
        table.insert(parts, part)
        if #parts == 4 then break end
    end

    if #parts < 4 then return end

    local playerKey = parts[1]
    local total     = tonumber(parts[2])
    local index     = tonumber(parts[3])
    local chunk     = parts[4]

    if not playerKey or not total or not index or not chunk then return end

    -- Don't process our own messages
    if playerKey == WowCraftStorage.GetPlayerKey() then return end

    -- Initialise buffer for this player if needed
    if not incoming[playerKey] then
        incoming[playerKey] = { chunks = {}, total = total }
    end

    incoming[playerKey].chunks[index] = chunk

    -- Check if we have all chunks
    local received = 0
    for _ in pairs(incoming[playerKey].chunks) do received = received + 1 end

    if received == total then
        -- Reassemble in order
        local assembled = table.concat(incoming[playerKey].chunks)
        incoming[playerKey] = nil -- clear buffer
        ProcessIncomingData(playerKey, assembled)
    end
end
