-- UI.lua
-- The guild profession browser. Open with /wcshow.
--
-- Left panel lists everyone who has synced data.
-- Right panel shows their professions and recipes when you click them.
-- Search bar at the top finds a recipe across every guild member at once.
--
-- The recipe list uses a proper scrolling child frame so it handles
-- people with hundreds of recipes without falling apart.

WowCraftUI = {}

local frame      = nil
local memberList = nil
local recipePanel  = nil
local searchBox  = nil
local selectedKey  = nil
local memberButtons = {}

local FRAME_W  = 700
local FRAME_H  = 500
local LEFT_W   = 200
local BUTTON_H = 28
local HEADER_H = 36
local PAD      = 10

-- colours
local C_BLUE  = "|cff00ccff"
local C_WHITE = "|cffffffff"
local C_GREY  = "|cff999999"
local C_GOLD  = "|cffffd100"
local C_GREEN = "|cff00ff66"
local C_END   = "|r"

-- ============================================================
-- Small utilities
-- ============================================================

local function FirstName(playerKey)
    -- "Tomor-Spineshatter" -> "Tomor"
    return playerKey:match("^([^%-]+)") or playerKey
end

local function TimeSince(ts)
    if not ts then return C_GREY .. "never synced" .. C_END end
    local diff = time() - ts
    if diff < 60    then return C_GREEN .. "just now" .. C_END end
    if diff < 3600  then return C_GREEN .. math.floor(diff / 60) .. "m ago" .. C_END end
    if diff < 86400 then return C_GREY  .. math.floor(diff / 3600) .. "h ago" .. C_END end
    return C_GREY .. math.floor(diff / 86400) .. "d ago" .. C_END
end

-- ============================================================
-- Recipe panel
-- Clears and rebuilds the right hand side for a given player.
-- Uses a growing frame inside a ScrollFrame so long lists scroll
-- properly rather than getting clipped.
-- ============================================================

local function ClearRecipePanel()
    if not recipePanel then return end
    local children = { recipePanel:GetChildren() }
    for _, child in ipairs(children) do child:Hide() end
    -- also clear font strings
    recipePanel:SetHeight(10)
end

local function AddLine(text, yAcc)
    local fs = recipePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", recipePanel, "TOPLEFT", PAD, -yAcc)
    fs:SetWidth(FRAME_W - LEFT_W - PAD * 4 - 16)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetText(text)
    return yAcc + fs:GetStringHeight() + 4
end

local function PopulateRecipes(playerKey)
    ClearRecipePanel()

    local data     = WowCraftStorage.GetMember(playerKey)
    local lastSeen = WowCraftStorage.GetLastSeen(playerKey)
    local y        = PAD

    if not data then
        y = AddLine(C_GREY .. "No data stored for this player yet." .. C_END, y)
        recipePanel:SetHeight(y + PAD)
        return
    end

    -- name + last sync time as a header
    y = AddLine(C_GOLD .. FirstName(playerKey) .. C_END .. "   " .. TimeSince(lastSeen), y)
    y = y + 6

    if not data.professions or not next(data.professions) then
        y = AddLine(C_GREY .. "No professions scanned yet." .. C_END, y)
        recipePanel:SetHeight(y + PAD)
        return
    end

    -- sort professions so the order is consistent
    local profNames = {}
    for name in pairs(data.professions) do table.insert(profNames, name) end
    table.sort(profNames)

    for _, profName in ipairs(profNames) do
        local prof    = data.professions[profName]
        local recipes = data.recipes and data.recipes[profName]

        y = AddLine(
            C_BLUE .. profName .. C_END ..
            "  " .. C_GREY .. (prof.level or 0) .. "/" .. (prof.maxLevel or 375) .. C_END,
            y)

        if recipes and #recipes > 0 then
            local sorted = {}
            for _, r in ipairs(recipes) do table.insert(sorted, r) end
            table.sort(sorted)
            for _, r in ipairs(sorted) do
                y = AddLine("   " .. C_WHITE .. r .. C_END, y)
            end
        else
            y = AddLine("   " .. C_GREY .. "Open this tradeskill window to scan recipes." .. C_END, y)
        end

        y = y + 6
    end

    recipePanel:SetHeight(y + PAD)
end

-- ============================================================
-- Search
-- Scans every stored member for a matching recipe name and
-- lists results in the right panel.
-- ============================================================

local function DoSearch(query)
    query = query:lower():gsub("^%s+", ""):gsub("%s+$", "")

    if query == "" then
        if selectedKey then PopulateRecipes(selectedKey) end
        return
    end

    ClearRecipePanel()

    local y      = PAD
    local found  = false
    local all    = WowCraftStorage.GetAllMembers()

    local keys = {}
    for k in pairs(all) do table.insert(keys, k) end
    table.sort(keys)

    y = AddLine(C_GOLD .. 'Searching for "' .. query .. '"' .. C_END, y)
    y = y + 6

    for _, playerKey in ipairs(keys) do
        local data = all[playerKey]
        if data and data.recipes then
            local hits = {}
            for profName, recipes in pairs(data.recipes) do
                for _, r in ipairs(recipes) do
                    if r:lower():find(query, 1, true) then
                        table.insert(hits, profName .. ": " .. r)
                    end
                end
            end

            if #hits > 0 then
                found = true
                table.sort(hits)
                y = AddLine(C_BLUE .. FirstName(playerKey) .. C_END, y)
                for _, hit in ipairs(hits) do
                    y = AddLine("   " .. C_WHITE .. hit .. C_END, y)
                end
                y = y + 4
            end
        end
    end

    if not found then
        y = AddLine(C_GREY .. "Nobody in the database has that recipe." .. C_END, y)
    end

    recipePanel:SetHeight(y + PAD)
end

-- ============================================================
-- Member list (left panel)
-- ============================================================

local function ClearMemberList()
    for _, btn in ipairs(memberButtons) do btn:Hide() end
    memberButtons = {}
end

local function SelectMember(playerKey)
    selectedKey = playerKey
    if searchBox then searchBox:SetText("") end
    PopulateRecipes(playerKey)

    for _, btn in ipairs(memberButtons) do
        if btn.playerKey == playerKey then
            btn:LockHighlight()
        else
            btn:UnlockHighlight()
        end
    end
end

local function PopulateMemberList()
    ClearMemberList()

    local all   = WowCraftStorage.GetAllMembers()
    local myKey = WowCraftStorage.GetPlayerKey()

    local keys = {}
    for k in pairs(all) do table.insert(keys, k) end
    table.sort(keys)

    -- put yourself first
    for i, k in ipairs(keys) do
        if k == myKey then
            table.remove(keys, i)
            table.insert(keys, 1, k)
            break
        end
    end

    local yOffset = 0
    for _, playerKey in ipairs(keys) do
        local btn = CreateFrame("Button", nil, memberList, "UIPanelButtonTemplate")
        btn:SetSize(LEFT_W - PAD, BUTTON_H)
        btn:SetPoint("TOPLEFT", memberList, "TOPLEFT", PAD / 2, -yOffset)
        btn.playerKey = playerKey

        local label = FirstName(playerKey)
        if playerKey == myKey then
            label = label .. " " .. C_GREY .. "(you)" .. C_END
        end
        btn:SetText(label)
        btn:GetFontString():SetJustifyH("LEFT")
        btn:SetScript("OnClick", function() SelectMember(playerKey) end)
        btn:Show()

        table.insert(memberButtons, btn)
        yOffset = yOffset + BUTTON_H + 2
    end

    memberList:SetHeight(math.max(yOffset, FRAME_H))

    -- keep the selected member highlighted after a refresh
    if selectedKey and WowCraftStorage.GetMember(selectedKey) then
        SelectMember(selectedKey)
    elseif #keys > 0 then
        SelectMember(keys[1])
    end
end

-- ============================================================
-- Build the window
-- Only called once, the first time /wcshow is used.
-- ============================================================

local function BuildFrame()
    frame = CreateFrame("Frame", "WowCraftFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    frame.TitleText:SetText("WowCraft — Guild Professions")

    -- search bar
    local searchBg = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    searchBg:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD, -HEADER_H)
    searchBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -HEADER_H)
    searchBg:SetHeight(30)

    searchBox = CreateFrame("EditBox", nil, searchBg)
    searchBox:SetPoint("TOPLEFT",     searchBg, "TOPLEFT",     6, -4)
    searchBox:SetPoint("BOTTOMRIGHT", searchBg, "BOTTOMRIGHT", -6,  4)
    searchBox:SetFontObject("GameFontNormal")
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(64)

    local hint = searchBg:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hint:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    hint:SetText("Search all recipes...")

    searchBox:SetScript("OnTextChanged", function(self)
        hint:SetShown(self:GetText() == "")
        DoSearch(self:GetText())
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    -- sync / request buttons sit to the right of the search bar
    local syncBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    syncBtn:SetSize(70, 24)
    syncBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 16, -HEADER_H - 3)
    syncBtn:SetText("Sync")
    syncBtn:SetScript("OnClick", function()
        WowCraftSync.BroadcastMyData()
        PopulateMemberList()
    end)

    local reqBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reqBtn:SetSize(80, 24)
    reqBtn:SetPoint("RIGHT", syncBtn, "LEFT", -4, 0)
    reqBtn:SetText("Request")
    reqBtn:SetScript("OnClick", function()
        WowCraftSync.RequestAllData()
    end)

    -- left scroll + member list frame
    local leftScroll = CreateFrame("ScrollFrame", "WowCraftLeftScroll", frame, "UIPanelScrollFrameTemplate")
    leftScroll:SetPoint("TOPLEFT",    frame, "TOPLEFT",    PAD, -HEADER_H - 40)
    leftScroll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD,  PAD)
    leftScroll:SetWidth(LEFT_W)

    memberList = CreateFrame("Frame", nil, leftScroll)
    memberList:SetWidth(LEFT_W - PAD)
    memberList:SetHeight(FRAME_H)
    leftScroll:SetScrollChild(memberList)

    -- divider line between panels
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    divider:SetPoint("TOPLEFT",    frame, "TOPLEFT",    LEFT_W + PAD * 2 + 2, -HEADER_H - 40)
    divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_W + PAD * 2 + 2,  PAD)
    divider:SetWidth(1)

    -- right scroll + recipe panel frame
    local rightScroll = CreateFrame("ScrollFrame", "WowCraftRightScroll", frame, "UIPanelScrollFrameTemplate")
    rightScroll:SetPoint("TOPLEFT",     frame, "TOPLEFT",     LEFT_W + PAD * 3 + 4, -HEADER_H - 40)
    rightScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 16, PAD)

    recipePanel = CreateFrame("Frame", nil, rightScroll)
    recipePanel:SetWidth(FRAME_W - LEFT_W - PAD * 4 - 16)
    recipePanel:SetHeight(FRAME_H)
    rightScroll:SetScrollChild(recipePanel)
end

-- ============================================================
-- Public
-- ============================================================

function WowCraftUI.Toggle()
    if not frame then BuildFrame() end

    if frame:IsShown() then
        frame:Hide()
    else
        PopulateMemberList()
        frame:Show()
    end
end

-- Called by Sync.lua when new data arrives so the window updates
-- automatically if it happens to be open
function WowCraftUI.Refresh()
    if frame and frame:IsShown() then
        PopulateMemberList()
    end
end
