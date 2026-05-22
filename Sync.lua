-- Sync.lua
-- Sends and receives profession data between guild members.
--
-- WoW addon messages have a 255 char limit so we chunk anything larger
-- and reassemble it on the other end. Nothing shows in guild chat,
-- this all happens in the background.
--
-- Message format per chunk:
--   playerKey | totalChunks | chunkIndex | data
--
-- Discord note:
-- If you want to pipe this data to Discord later, the easiest route is a
-- small companion app that reads the SavedVariables file on disk at:
--   WTF\Account\<account>\SavedVariables\wowcraft.lua
-- No addon changes needed for that, it's just file reading.

WowCraftSync = {}

local PREFIX        = "WowCraft"
local MAX_CHUNK     = 200
local SEP           = "\031"  -- ASCII unit separator, won't appear in recipe names
local SYNC_COOLDOWN = 300     -- 5 min cooldown so nobody accidentally spams the guild

local incoming     = {}  -- chunk buffers keyed by playerKey
local lastSyncTime = 0

-- ============================================================
-- Init
-- ============================================================

function WowCraftSync.Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    else
        RegisterAddonMessagePrefix(PREFIX)
    end
end

-- ============================================================
-- Serialisation
--
-- Using a simple key=value pipe format rather than something
-- fancy. Recipe names are plain strings so this is safe enough.
-- Format for a member data table:
--   PROF:Leatherworking:375:375|REC:Leatherworking:Heavy Knothide Armor Kit,Rugged Armor Kit
-- ============================================================

local function EscapeString(str)
    -- pipe and colon are our delimiters so escape them if they appear in a value
    -- In practice recipe names don't contain these but better safe than sorry
    str = str:gsub("\\", "\\\\")
    str = str:gsub("|", "\\|")
    str = str:gsub(":", "\\:")
    str = str:gsub(",", "\\,")
    return str
end

local function UnescapeString(str)
    str = str:gsub("\\,", "\001")  -- temp placeholder
    str = str:gsub("\\:", "\002")
    str = str:gsub("\\|", "\003")
    str = str:gsub("\\\\", "\\")
    str = str:gsub("\001", ",")
    str = str:gsub("\002", ":")
    str = str:gsub("\003", "|")
    return str
end

local function Serialise(data)
    local parts = {}

    -- profession levels
    if data.professions then
        for profName, prof in pairs(data.professions) do
            table.insert(parts, "PROF:"
                .. EscapeString(profName) .. ":"
                .. (prof.level or 0) .. ":"
                .. (prof.maxLevel or 375))
        end
    end

    -- recipes per profession
    if data.recipes then
        for profName, recipes in pairs(data.recipes) do
            if #recipes > 0 then
                local escaped = {}
                for _, r in ipairs(recipes) do
                    table.insert(escaped, EscapeString(r))
                end
                table.insert(parts, "REC:"
                    .. EscapeString(profName) .. ":"
                    .. table.concat(escaped, ","))
            end
        end
    end

    return table.concat(parts, "|")
end

local function Deserialise(str)
    if not str or str == "" then return nil end

    local data = { professions = {}, recipes = {} }

    -- split on | but not escaped \|
    local segments = {}
    local current  = ""
    for i = 1, #str do
        local c = str:sub(i, i)
        if c == "|" and str:sub(i - 1, i - 1) ~= "\\" then
            table.insert(segments, current)
            current = ""
        else
            current = current .. c
        end
    end
    if current ~= "" then table.insert(segments, current) end

    for _, segment in ipairs(segments) do
        -- split on : but not escaped \:
        local fields = {}
        local field  = ""
        for i = 1, #segment do
            local c = segment:sub(i, i)
            if c == ":" and segment:sub(i - 1, i - 1) ~= "\\" then
                table.insert(fields, field)
                field = ""
            else
                field = field .. c
            end
        end
        if field ~= "" then table.insert(fields, field) end

        local recordType = fields[1]

        if recordType == "PROF" and fields[2] and fields[3] and fields[4] then
            local profName = UnescapeString(fields[2])
            data.professions[profName] = {
                level    = tonumber(fields[3]) or 0,
                maxLevel = tonumber(fields[4]) or 375,
            }

        elseif recordType == "REC" and fields[2] and fields[3] then
            local profName  = UnescapeString(fields[2])
            local recipeStr = fields[3]
            local recipes   = {}

            -- split recipe list on , but not escaped \,
            local recipeName = ""
            for i = 1, #recipeStr do
                local c = recipeStr:sub(i, i)
                if c == "," and recipeStr:sub(i - 1, i - 1) ~= "\\" then
                    if recipeName ~= "" then
                        table.insert(recipes, UnescapeString(recipeName))
                        recipeName = ""
                    end
                else
                    recipeName = recipeName .. c
                end
            end
            if recipeName ~= "" then
                table.insert(recipes, UnescapeString(recipeName))
            end

            data.recipes[profName] = recipes
        end
    end

    return data
end

-- ============================================================
-- Chunking
-- ============================================================

local function ChunkString(str)
    local chunks = {}
    local i = 1
    while i <= #str do
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

function WowCraftSync.BroadcastMyData()
    local now = time()

    local snapshot  = WowCraftData.GetLocalSnapshot()
    local profCount = 0
    for _ in pairs(snapshot.professions) do profCount = profCount + 1 end

    if profCount == 0 then
        print("|cff00ccff[WowCraft]|r Nothing to sync yet. Open your tradeskill windows first.")
        return
    end

    local playerKey  = WowCraftStorage.GetPlayerKey()
    local serialised = Serialise(snapshot)
    local chunks     = ChunkString(serialised)
    local total      = #chunks

    -- stagger sends by 0.1s each so WoW's rate limiter doesn't drop packets
    for i, chunk in ipairs(chunks) do
        local msg = playerKey .. SEP .. total .. SEP .. i .. SEP .. chunk
        C_Timer.After(i * 0.1, function()
            SendGuild(msg)
        end)
    end

    lastSyncTime = now
    print("|cff00ccff[WowCraft]|r Syncing " .. profCount .. " profession(s) to the guild (" .. total .. " packets)...")
end

-- Asks online guildmates to broadcast their data.
-- Useful when you first log in and want to populate your database.
function WowCraftSync.RequestAllData()
    SendGuild("REQUEST" .. SEP .. WowCraftStorage.GetPlayerKey())
    print("|cff00ccff[WowCraft]|r Requested data from online guild members.")
end

-- ============================================================
-- Receiving
-- ============================================================

local function ProcessIncomingData(playerKey, serialised)
    local data = Deserialise(serialised)
    if not data then
        print("|cff00ccff[WowCraft]|r Got bad data from " .. playerKey .. ", ignoring.")
        return
    end

    WowCraftStorage.SaveMember(playerKey, data)

    local profCount = 0
    if data.professions then
        for _ in pairs(data.professions) do profCount = profCount + 1 end
    end

    print("|cff00ccff[WowCraft]|r Got data from " .. playerKey:match("^([^%-]+)") .. " (" .. profCount .. " profession(s)).")

    if WowCraftUI and WowCraftUI.Refresh then
        WowCraftUI.Refresh()
    end
end

function WowCraftSync.OnAddonMessage(msg, channel, sender)
    -- someone is asking for our data
    if msg:sub(1, 7) == "REQUEST" then
        C_Timer.After(math.random(0, 3), function()
            WowCraftSync.BroadcastMyData()
        end)
        return
    end

    -- parse: playerKey SEP total SEP index SEP chunk
    local playerKey, total, index, chunk = msg:match(
        "^([^" .. SEP .. "]+)" .. SEP ..
        "([^" .. SEP .. "]+)" .. SEP ..
        "([^" .. SEP .. "]+)" .. SEP ..
        "(.+)$"
    )

    total = tonumber(total)
    index = tonumber(index)

    if not playerKey or not total or not index or not chunk then return end
    if playerKey == WowCraftStorage.GetPlayerKey() then return end  -- ignore our own broadcasts

    if not incoming[playerKey] then
        incoming[playerKey] = { chunks = {}, total = total }
    end

    incoming[playerKey].chunks[index] = chunk

    -- check if we have every chunk
    local received = 0
    for _ in pairs(incoming[playerKey].chunks) do received = received + 1 end

    if received == total then
        -- reassemble in index order, not insertion order
        local ordered = {}
        for i = 1, total do
            ordered[i] = incoming[playerKey].chunks[i] or ""
        end
        local assembled = table.concat(ordered)
        incoming[playerKey] = nil
        ProcessIncomingData(playerKey, assembled)
    end
end
