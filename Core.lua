-- Core.lua
-- Bootstrap file. Initialises all modules, registers events, and slash commands.

local addonName, addon = ...

local frame = CreateFrame("Frame")

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("CRAFT_SHOW")
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        WowCraftStorage.Init()
        WowCraftSync.Init()
        print("|cff00ccff[WowCraft]|r Loaded. Type /wcraft for options.")

    elseif event == "TRADE_SKILL_SHOW" then
        -- Standard professions (Alchemy, LW, Cooking etc)
        WowCraftData.OnTradeskillShow()

    elseif event == "CRAFT_SHOW" then
        -- Enchanting uses the legacy CraftFrame API
        WowCraftData.OnCraftShow()

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix == "WowCraft" then
            WowCraftSync.OnAddonMessage(msg, channel, sender)
        end
    end
end)

-- ============================================================
-- Slash commands
-- ============================================================

local function DoHelp()
    print("|cff00ccff[WowCraft]|r Commands:")
    print("  /wcraft   - show this help")
    print("  /wcscan   - show how many professions scanned so far")
    print("  /wcsync   - broadcast your data to online guild members")
    print("  /wcrequest - ask online guild members to send their data")
    print("  /wcshow   - open the guild profession browser")
    print("  /wcreset  - clear all stored data")
end

local function DoScan()
    local snapshot = WowCraftData.GetLocalSnapshot()
    local count = 0
    for _ in pairs(snapshot.professions) do count = count + 1 end
    print("|cff00ccff[WowCraft]|r " .. count .. " profession(s) scanned so far. Open each tradeskill window to scan recipes.")
end

local function DoSync()
    WowCraftSync.BroadcastMyData()
end

local function DoRequest()
    WowCraftSync.RequestAllData()
end

local function DoShow()
    if WowCraftUI and WowCraftUI.Toggle then
        WowCraftUI.Toggle()
    else
        print("|cff00ccff[WowCraft]|r UI not loaded yet.")
    end
end

local function DoReset()
    WowCraftStorage.Reset()
end

SLASH_WOWCRAFT1  = "/wcraft"
SLASH_WCSCAN1    = "/wcscan"
SLASH_WCSYNC1    = "/wcsync"
SLASH_WCREQUEST1 = "/wcrequest"
SLASH_WCSHOW1    = "/wcshow"
SLASH_WCRESET1   = "/wcreset"

SlashCmdList["WOWCRAFT"]   = DoHelp
SlashCmdList["WCSCAN"]     = DoScan
SlashCmdList["WCSYNC"]     = DoSync
SlashCmdList["WCREQUEST"]  = DoRequest
SlashCmdList["WCSHOW"]     = DoShow
SlashCmdList["WCRESET"]    = DoReset
