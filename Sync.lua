-- Sync.lua
-- Sends and receives profession data between guild members.
--
-- Each profession is sent as its own separate transmission so large
-- datasets don't collide in the chunk buffer. Enchanting arrives as
-- one sequence, Leatherworking as another, and so on.
--
-- Message format per chunk:
--   playerKey | transmissionID | totalChunks | chunkIndex | data
--
-- Discord note:
-- If you want to pipe this data to Discord later, the easiest route is a
-- small companion app that reads the SavedVariables file on disk at:
--   WTF\Account\<account>\SavedVariables\wowcraft.lua
-- No addon changes needed for that, it's just file reading.

WowCraftSync = {}

local PREFIX    = "WowCraft"
local MAX_CHUNK = 200
local SEP       = "\031"  -- ASCII unit separator, won't appear in recipe names

-- incoming buffers keyed by "playerKey|transmissionID"
local incoming = {}

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
-- Each transmission carries one profession's data:
--   PROF:Leatherworking:375:375|REC:Leatherworking:recipe1,recipe2,...
-- ============================================================

local function EscapeString(str)
    str = str:gsub("\\", "\\\\")
    str = str:gsub("|", "\\|")
    str = str:gsub(":", "\\:")
    str = str:gsub(",", "\\,")
    return str
end

local function UnescapeString(str)
    str = str:gsub("\\,", "\001")
    str = str:gsub("\\:", "\002")
    str = str:gsub("\\|", "\003")
    str = str:gsub("\\\\", "\\")
    str = str:gsub("\001", ",")
    str = str:gsub("\002", ":")
    str = str:gsub("\003", "|")
    return str
end

-- Serialises a single profession's data into a string
local function SerialiseProfession(profName, prof, recipes)
    local parts = {}

    table.insert(parts, "PROF:"
        .. EscapeString(profName) .. ":"
        .. (prof.level or 0) .. ":"
        .. (prof.maxLevel or 375))

    if recipes and #recipes > 0 then
        local escaped = {}
        for _, r in ipairs(recipes) do
            table.insert(escaped, EscapeString(r))
        end
        table.insert(parts, "REC:"
            .. EscapeString(profName) .. ":"
            .. table.concat(escaped, ","))
    end

    return table.concat(parts, "|")
end

-- Deserialises a single profession transmission back into data
local function Deserialise(str)
    if not str or str == "" then return nil end

    local data = { professions = {}, recipes = {} }

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

-- Sends one profession as a chunked transmission
-- txID is a short unique ID so the receiver can tell transmissions apart
local function SendProfession(playerKey, txID, profName, prof, recipes, delayOffset)
    local serialised = SerialiseProfession(profName, prof, recipes)
    local chunks     = ChunkString(serialised)
    local total      = #chunks

    for i, chunk in ipairs(chunks) do
        local msg = playerKey .. SEP .. txID .. SEP .. total .. SEP .. i .. SEP .. chunk
        C_Timer.After(delayOffset + (i - 1) * 0.3, function()
            SendGuild(msg)
        end)
    end

    return total
end

-- Broadcasts all local profession data to the guild
-- Each profession is sent as a separate transmission with its own ID
function WowCraftSync.BroadcastMyData()
    local snapshot  = WowCraftData.GetLocalSnapshot()
    local profCount = 0
    for _ in pairs(snapshot.professions) do profCount = profCount + 1 end

    if profCount == 0 then
        print("|cff00ccff[WowCraft]|r Nothing to sync yet. Open your tradeskill windows first.")
        return
    end

    local playerKey  = WowCraftStorage.GetPlayerKey()
    local delayOffset = 0
    local txCounter  = 0

    -- sort professions so send order is consistent
    local profNames = {}
    for name in pairs(snapshot.professions) do table.insert(profNames, name) end
    table.sort(profNames)

    for _, profName in ipairs(profNames) do
        local prof    = snapshot.professions[profName]
        local recipes = snapshot.recipes and snapshot.recipes[profName]
        txCounter     = txCounter + 1

        -- txID is playerKey+number, unique per transmission
        local txID    = txCounter
        local chunks  = SendProfession(playerKey, txID, profName, prof, recipes, delayOffset)

        -- next profession starts after this one finishes sending
        delayOffset = delayOffset + chunks * 0.3 + 0.5
    end

    print("|cff00ccff[WowCraft]|r Syncing " .. profCount .. " profession(s) to the guild...")
end

-- Asks online guildmates to broadcast their data
function WowCraftSync.RequestAllData()
    SendGuild("REQUEST" .. SEP .. WowCraftStorage.GetPlayerKey())
    print("|cff00ccff[WowCraft]|r Requested data from online guild members.")
end

-- ============================================================
-- Receiving
-- ============================================================

local function ProcessIncomingData(playerKey, data)
    -- merge into existing stored data rather than overwriting everything
    -- so receiving Enchanting doesn't wipe previously received Leatherworking
    local existing = WowCraftStorage.GetMember(playerKey) or { professions = {}, recipes = {} }

    if data.professions then
        for profName, prof in pairs(data.professions) do
            existing.professions[profName] = prof
        end
    end

    if data.recipes then
        for profName, recipes in pairs(data.recipes) do
            existing.recipes[profName] = recipes
        end
    end

    WowCraftStorage.SaveMember(playerKey, existing)

    local profCount = 0
    for _ in pairs(existing.professions) do profCount = profCount + 1 end

    print("|cff00ccff[WowCraft]|r Got data from "
        .. (playerKey:match("^([^%-]+)") or playerKey)
        .. " (" .. profCount .. " profession(s) total).")

    if WowCraftUI and WowCraftUI.Refresh then
        WowCraftUI.Refresh()
    end
end

function WowCraftSync.OnAddonMessage(msg, channel, sender)
    print("|cffff0000[DEBUG]|r raw msg from " .. tostring(sender) .. ": " .. msg:sub(1, 40))

    -- someone is asking for our data
    if msg:sub(1, 7) == "REQUEST" then
        C_Timer.After(math.random(0, 3), function()
            WowCraftSync.BroadcastMyData()
        end)
        return
    end

    -- parse: playerKey SEP txID SEP total SEP index SEP chunk
    local playerKey, txID, total, index, chunk = msg:match(
        "^([^" .. SEP .. "]+)" .. SEP ..
        "([^" .. SEP .. "]+)" .. SEP ..
        "([^" .. SEP .. "]+)" .. SEP ..
        "([^" .. SEP .. "]+)" .. SEP ..
        "(.+)$"
    )

    total = tonumber(total)
    index = tonumber(index)

    if not playerKey or not txID or not total or not index or not chunk then return end
    if playerKey == WowCraftStorage.GetPlayerKey() then return end

    -- each transmission has its own buffer keyed by playerKey+txID
    local bufKey = playerKey .. "|" .. txID
    if index == 1 then
        incoming[bufKey] = { chunks = {}, total = total }
    end

    if not incoming[bufKey] then
        incoming[bufKey] = { chunks = {}, total = total }
    end

    incoming[bufKey].chunks[index] = chunk

    local received = 0
    for _ in pairs(incoming[bufKey].chunks) do received = received + 1 end

    if received == total then
        local ordered = {}
        for i = 1, total do
            ordered[i] = incoming[bufKey].chunks[i] or ""
        end
        local assembled = table.concat(ordered)
        incoming[bufKey] = nil
        print("|cffff0000[DEBUG]|r assembled: " .. assembled:sub(1, 80))
        local data = Deserialise(assembled)
        if data then
            ProcessIncomingData(playerKey, data)
        else
            print("|cff00ccff[WowCraft]|r Got bad data from " .. playerKey .. ", ignoring.")
        end
    end
end
