-- Core.lua
-- Entry point. Loads everything else, registers events, handles slash commands.
--
-- Load order matters — Storage and Data have to be ready before Core runs,
-- which is why they're listed first in the TOC.

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
        print("|cff00ccff[WowCraft]|r Loaded. Type /wcraft for commands.")

    elseif event == "TRADE_SKILL_SHOW" then
        WowCraftData.OnTradeskillShow()

    elseif event == "CRAFT_SHOW" then
        -- Enchanting uses a separate event and API, handled in Data.lua
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
-- Each command needs its own SLASH_ global and SlashCmdList entry.
-- WoW derives the lookup key from the variable name prefix, so
-- SLASH_WCSCAN1 maps to SlashCmdList["WCSCAN"]. They can't share.
-- ============================================================

SLASH_WOWCRAFT1  = "/wcraft"
SLASH_WCSCAN1    = "/wcscan"
SLASH_WCSYNC1    = "/wcsync"
SLASH_WCREQUEST1 = "/wcrequest"
SLASH_WCSHOW1    = "/wcshow"
SLASH_WCRESET1   = "/wcreset"

SlashCmdList["WOWCRAFT"] = function()
    print("|cff00ccff[WowCraft]|r Commands:")
    print("  /wcscan     — show how many professions scanned")
    print("  /wcsync     — broadcast your data to the guild")
    print("  /wcrequest  — ask online guildmates to send their data")
    print("  /wcshow     — open the profession browser")
    print("  /wcreset    — wipe all stored data")
end

SlashCmdList["WCSCAN"] = function()
    local snapshot = WowCraftData.GetLocalSnapshot()
    local count    = 0
    for _ in pairs(snapshot.professions) do count = count + 1 end
    print("|cff00ccff[WowCraft]|r " .. count .. " profession(s) scanned. Open each tradeskill window to scan recipes.")
end

SlashCmdList["WCSYNC"] = function()
    WowCraftSync.BroadcastMyData()
end

SlashCmdList["WCREQUEST"] = function()
    WowCraftSync.RequestAllData()
end

SlashCmdList["WCSHOW"] = function()
    if WowCraftUI and WowCraftUI.Toggle then
        WowCraftUI.Toggle()
    else
        print("|cff00ccff[WowCraft]|r UI not loaded.")
    end
end

SlashCmdList["WCRESET"] = function()
    WowCraftStorage.Reset()
end

-- debug: print any WowCraft addon messages we receive
local debugFrame = CreateFrame("Frame")
debugFrame:RegisterEvent("CHAT_MSG_ADDON")
debugFrame:SetScript("OnEvent", function(self, event, prefix, msg, channel, sender)
    if prefix == "WowCraft" then
        print("|cffff0000[WowCraft DEBUG]|r got message from " .. sender .. ": " .. msg:sub(1, 50))
    end
end)