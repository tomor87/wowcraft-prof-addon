-- Core.lua
-- Bootstrap file. Initialises storage, registers events, and slash commands.

local addonName, addon = ...

local frame = CreateFrame("Frame")

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("TRADE_SKILL_SHOW")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        WowCraftStorage.Init()
        print("|cff00ccff[WowCraft]|r Loaded. Type /wcraft for options.")

    elseif event == "TRADE_SKILL_SHOW" then
        WowCraftData.OnTradeskillShow()
    end
end)

local function DoScan()
    local snapshot = WowCraftData.GetLocalSnapshot()
    local count = 0
    for _ in pairs(snapshot.professions) do count = count + 1 end
    print("|cff00ccff[WowCraft]|r Found " .. count .. " profession(s). Open each tradeskill window to scan recipes.")
end

local function DoReset()
    WowCraftStorage.Reset()
end

local function DoHelp()
    print("|cff00ccff[WowCraft]|r Commands:")
    print("  /wcraft - show this help")
    print("  /wcscan - scan your profession levels")
    print("  /wcreset - clear all stored data")
end

SLASH_WOWCRAFT1 = "/wcraft"
SlashCmdList["WOWCRAFT"] = DoHelp

SLASH_WCSCAN1 = "/wcscan"
SlashCmdList["WCSCAN"] = DoScan

SLASH_WCRESET1 = "/wcreset"
SlashCmdList["WCRESET"] = DoReset
