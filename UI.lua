-- UI.lua
-- Guild profession browser window
-- Open with /wcshow
-- Left panel: guild members who have synced
-- Right panel: their professions and recipes
-- Search bar: find who has a specific recipe across all members

WowCraftUI = {}

local frame         = nil
local memberList    = nil
local recipePanel   = nil
local searchBox     = nil
local selectedKey   = nil
local memberButtons = {}

local FRAME_W     = 700
local FRAME_H     = 500
local LEFT_W      = 200
local BUTTON_H    = 28
local HEADER_H    = 36
local PADDING     = 10

-- Colour helpers
local function Hex(r, g, b) return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end
local BLUE   = Hex(0.0, 0.8, 1.0)
local WHITE  = Hex(1.0, 1.0, 1.0)
local GREY   = Hex(0.6, 0.6, 0.6)
local GOLD   = Hex(1.0, 0.82, 0.0)
local GREEN  = Hex(0.0, 1.0, 0.4)
local RESET  = "|r"

-- ============================================================
-- Helpers
-- ============================================================

local function FormatLastSeen(ts)
    if not ts then return GREY .. "Never" .. RESET end
    local diff = time() - ts
    if diff < 60     then return GREEN .. "Just now" .. RESET end
    if diff < 3600   then return GREEN .. math.floor(diff / 60) .. "m ago" .. RESET end
    if diff < 86400  then return GREY .. math.floor(diff / 3600) .. "h ago" .. RESET end
    return GREY .. math.floor(diff / 86400) .. "d ago" .. RESET
end

local function ShortName(playerKey)
    return playerKey:match("^([^%-]+)") or playerKey
end

-- ============================================================
-- Recipe panel — shows one member's professions and recipes
-- ============================================================

local recipeLines = {}

local function ClearRecipePanel()
    for _, line in ipairs(recipeLines) do
        line:Hide()
    end
    recipeLines = {}
end

local function AddRecipeLine(parent, text, yOffset)
    local line = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, yOffset)
    line:SetWidth(FRAME_W - LEFT_W - PADDING * 3)
    line:SetJustifyH("LEFT")
    line:SetText(text)
    line:Show()
    table.insert(recipeLines, line)
    return line:GetStringHeight() + 4
end

local function PopulateRecipePanel(playerKey)
    ClearRecipePanel()
    if not recipePanel then return end

    local data     = WowCraftStorage.GetMember(playerKey)
    local lastSeen = WowCraftStorage.GetLastSeen(playerKey)
    local yOffset  = -PADDING

    if not data then
        AddRecipeLine(recipePanel, GREY .. "No data available for this player." .. RESET, yOffset)
        return
    end

    -- Header
    local name = ShortName(playerKey)
    yOffset = yOffset - AddRecipeLine(recipePanel, GOLD .. name .. RESET .. "  " .. FormatLastSeen(lastSeen), yOffset)
    yOffset = yOffset - 6

    if not data.professions or next(data.professions) == nil then
        AddRecipeLine(recipePanel, GREY .. "No professions scanned yet." .. RESET, yOffset)
        return
    end

    -- Sort professions alphabetically
    local profNames = {}
    for name in pairs(data.professions) do table.insert(profNames, name) end
    table.sort(profNames)

    for _, profName in ipairs(profNames) do
        local prof    = data.professions[profName]
        local recipes = data.recipes and data.recipes[profName]
        local level   = prof.level or 0
        local maxLvl  = prof.maxLevel or 375

        -- Profession header
        yOffset = yOffset - AddRecipeLine(recipePanel,
            BLUE .. profName .. RESET .. "  " .. GREY .. level .. "/" .. maxLvl .. RESET, yOffset)

        if recipes and #recipes > 0 then
            -- Sort recipes alphabetically
            local sorted = {}
            for _, r in ipairs(recipes) do table.insert(sorted, r) end
            table.sort(sorted)

            for _, recipeName in ipairs(sorted) do
                yOffset = yOffset - AddRecipeLine(recipePanel, "  " .. WHITE .. recipeName .. RESET, yOffset)
            end
        else
            yOffset = yOffset - AddRecipeLine(recipePanel, "  " .. GREY .. "No recipes scanned." .. RESET, yOffset)
        end

        yOffset = yOffset - 6
    end

    recipePanel:SetHeight(math.abs(yOffset) + PADDING)
end

-- ============================================================
-- Search — highlights members who have a matching recipe
-- ============================================================

local function DoSearch(query)
    query = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
    ClearRecipePanel()
    if not recipePanel then return end

    if query == "" then
        -- Clear search, restore selected member view
        if selectedKey then
            PopulateRecipePanel(selectedKey)
        end
        return
    end

    local yOffset = -PADDING
    local found   = false

    -- Sort members alphabetically for consistent results
    local allMembers = WowCraftStorage.GetAllMembers()
    local keys = {}
    for k in pairs(allMembers) do table.insert(keys, k) end
    table.sort(keys)

    AddRecipeLine(recipePanel, GOLD .. 'Search results for "' .. query .. '"' .. RESET, yOffset)
    yOffset = yOffset - 20

    for _, playerKey in ipairs(keys) do
        local data = allMembers[playerKey]
        if data and data.recipes then
            local matched = {}
            for profName, recipes in pairs(data.recipes) do
                for _, recipeName in ipairs(recipes) do
                    if recipeName:lower():find(query, 1, true) then
                        table.insert(matched, profName .. ": " .. recipeName)
                    end
                end
            end

            if #matched > 0 then
                found = true
                table.sort(matched)
                yOffset = yOffset - AddRecipeLine(recipePanel, BLUE .. ShortName(playerKey) .. RESET, yOffset)
                for _, m in ipairs(matched) do
                    yOffset = yOffset - AddRecipeLine(recipePanel, "  " .. WHITE .. m .. RESET, yOffset)
                end
                yOffset = yOffset - 6
            end
        end
    end

    if not found then
        AddRecipeLine(recipePanel, GREY .. "No guild members found with that recipe." .. RESET, yOffset)
    end

    recipePanel:SetHeight(math.abs(yOffset) + PADDING)
end

-- ============================================================
-- Member list — left panel buttons
-- ============================================================

local function ClearMemberList()
    for _, btn in ipairs(memberButtons) do
        btn:Hide()
    end
    memberButtons = {}
end

local function SelectMember(playerKey)
    selectedKey = playerKey
    if searchBox then searchBox:SetText("") end
    PopulateRecipePanel(playerKey)

    -- Highlight selected button
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
    if not memberList then return end

    local allMembers = WowCraftStorage.GetAllMembers()
    local keys = {}
    for k in pairs(allMembers) do table.insert(keys, k) end
    table.sort(keys)

    local myKey = WowCraftStorage.GetPlayerKey()

    -- Put yourself at the top
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
        btn:SetSize(LEFT_W - PADDING, BUTTON_H)
        btn:SetPoint("TOPLEFT", memberList, "TOPLEFT", PADDING / 2, -yOffset)
        btn.playerKey = playerKey

        local label = ShortName(playerKey)
        if playerKey == myKey then label = label .. " " .. GREY .. "(you)" .. RESET end
        btn:SetText(label)
        btn:GetFontString():SetJustifyH("LEFT")

        btn:SetScript("OnClick", function()
            SelectMember(playerKey)
        end)

        btn:Show()
        table.insert(memberButtons, btn)
        yOffset = yOffset + BUTTON_H + 2
    end

    memberList:SetHeight(math.max(yOffset, FRAME_H - HEADER_H - 60))

    -- Auto select first entry
    if #keys > 0 and not selectedKey then
        SelectMember(keys[1])
    elseif selectedKey then
        PopulateRecipePanel(selectedKey)
    end
end

-- ============================================================
-- Build the main window
-- ============================================================

local function BuildFrame()
    -- Main window
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

    -- Title
    frame.TitleText:SetText("WowCraft — Guild Profession Browser")

    -- --------------------------------------------------------
    -- Search bar
    -- --------------------------------------------------------
    local searchContainer = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    searchContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -HEADER_H)
    searchContainer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -HEADER_H)
    searchContainer:SetHeight(30)

    searchBox = CreateFrame("EditBox", nil, searchContainer)
    searchBox:SetPoint("TOPLEFT", searchContainer, "TOPLEFT", 6, -4)
    searchBox:SetPoint("BOTTOMRIGHT", searchContainer, "BOTTOMRIGHT", -6, 4)
    searchBox:SetFontObject("GameFontNormal")
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(64)

    local placeholder = searchContainer:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    placeholder:SetText("Search recipes...")

    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        placeholder:SetShown(text == "")
        DoSearch(text)
    end)

    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    -- --------------------------------------------------------
    -- Sync button
    -- --------------------------------------------------------
    local syncBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    syncBtn:SetSize(80, 24)
    syncBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING - 16, -HEADER_H - 4)
    syncBtn:SetText("Sync")
    syncBtn:SetScript("OnClick", function()
        WowCraftSync.BroadcastMyData()
        PopulateMemberList()
    end)

    -- Request button
    local reqBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reqBtn:SetSize(80, 24)
    reqBtn:SetPoint("RIGHT", syncBtn, "LEFT", -4, 0)
    reqBtn:SetText("Request")
    reqBtn:SetScript("OnClick", function()
        WowCraftSync.RequestAllData()
    end)

    -- --------------------------------------------------------
    -- Left panel — member list (scrollable)
    -- --------------------------------------------------------
    local leftScroll = CreateFrame("ScrollFrame", "WowCraftLeftScroll", frame, "UIPanelScrollFrameTemplate")
    leftScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -HEADER_H - 40)
    leftScroll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, PADDING)
    leftScroll:SetWidth(LEFT_W)

    memberList = CreateFrame("Frame", nil, leftScroll)
    memberList:SetWidth(LEFT_W - PADDING)
    memberList:SetHeight(FRAME_H)
    leftScroll:SetScrollChild(memberList)

    -- Divider
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_W + PADDING * 2, -HEADER_H - 40)
    divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_W + PADDING * 2, PADDING)
    divider:SetWidth(1)

    -- --------------------------------------------------------
    -- Right panel — recipe list (scrollable)
    -- --------------------------------------------------------
    local rightScroll = CreateFrame("ScrollFrame", "WowCraftRightScroll", frame, "UIPanelScrollFrameTemplate")
    rightScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_W + PADDING * 3 + 1, -HEADER_H - 40)
    rightScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING - 16, PADDING)

    recipePanel = CreateFrame("Frame", nil, rightScroll)
    recipePanel:SetWidth(FRAME_W - LEFT_W - PADDING * 4 - 16)
    recipePanel:SetHeight(FRAME_H)
    rightScroll:SetScrollChild(recipePanel)
end

-- ============================================================
-- Public API
-- ============================================================

function WowCraftUI.Toggle()
    if not frame then
        BuildFrame()
    end

    if frame:IsShown() then
        frame:Hide()
    else
        PopulateMemberList()
        frame:Show()
    end
end

function WowCraftUI.Refresh()
    if frame and frame:IsShown() then
        PopulateMemberList()
    end
end
