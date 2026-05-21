# WowCraft — Guild Profession Tracker

A World of Warcraft addon for **TBC Classic (Anniversary Realms)** that tracks guild members' professions and recipes, so you can always find who has what — without relying on Discord.

## The Problem

Most guilds use a Discord channel to share profession lists. Players post screenshots or manually update a pinned message. Half the guild never sees it, nobody keeps it updated, and you still end up asking in guild chat who has Enchant Weapon - Mongoose.

## The Solution

WowCraft lets every guild member scan their own professions and recipes, broadcast that data invisibly to the guild, and browse the full picture from inside the game.

---

## Features

- Automatic recipe scanning when you open a tradeskill window
- Full support for Enchanting (which uses a separate API in TBC Classic)
- Cooking support
- Guild-wide sync via invisible addon messages (nothing appears in chat)
- Persistent storage — data survives logouts and reloads
- Searchable recipe browser — find who has a specific recipe instantly
- 5 minute sync cooldown to prevent spam
- Zero performance impact — no update loops, all event-driven

---

## Installation

1. Download the latest release (or clone this repo)
2. Extract/copy the `wowcraft` folder into:
   ```
   World of Warcraft\_anniversary_\Interface\AddOns\wowcraft\
   ```
3. Launch WoW and enable **WowCraft** in your Addons list
4. Log in and open your tradeskill windows to scan your recipes

---

## Usage

### Scanning your professions
Simply open each of your tradeskill windows (Alchemy, Leatherworking, Enchanting etc). WowCraft scans automatically when the window opens and prints a confirmation:
```
[WowCraft] Scanned Leatherworking: 375/375 — 58 recipes.
[WowCraft] Scanned Enchanting: 375/375 — 56 recipes.
```

### Syncing with your guild
```
/wcsync     — broadcast your data to online guild members
/wcrequest  — ask online guild members to send their data to you
```

### Browsing the data
```
/wcshow     — open the guild profession browser
```

Use the search bar at the top to find any recipe across all guild members. Click a member's name in the left panel to see all their professions and recipes.

### Other commands
```
/wcraft     — show all commands
/wcscan     — show how many professions you've scanned so far
/wcreset    — clear all stored data
```

---

## How Syncing Works

When you click Sync (or type `/wcsync`), your profession and recipe data is serialised, split into small packets, and broadcast to online guild members over WoW's addon message channel. This is completely invisible — nothing appears in guild chat. Other guild members with the addon installed receive the packets, reassemble the data, and store it locally.

Data persists in each player's `SavedVariables` file, so you can browse offline guild members' professions even when they're not online.

---

## File Structure

```
wowcraft/
├── wowcraft.toc    — addon metadata and load order
├── Storage.lua     — SavedVariables read/write wrapper
├── Data.lua        — profession and recipe scanner
├── Sync.lua        — guild addon messaging (send/receive)
├── Core.lua        — bootstrap, events, slash commands
└── UI.lua          — guild profession browser window
```

---

## Known Limitations

- **Enchanting level** always shows as 375/375 — the TBC Anniversary client does not expose the Enchanting skill level via the CraftFrame API (`GetCraftLine()` is not available). All recipes scan correctly.
- **Fishing** is not tracked — it has no tradeskill window to scan.
- **First Aid** is not tracked by design.
- Guild members must have the addon installed for their data to appear.
- Data only updates when a member opens their tradeskill windows and syncs.

---

## Planned Features

- [ ] Discord integration via companion app (reads SavedVariables file, posts to Discord bot)
- [ ] Minimap button
- [ ] Online/offline status indicator per guild member
- [ ] Timestamp showing when each member last synced
- [ ] Auto-request on login (ask guild for data automatically when you log in)
- [ ] Version checking (warn if a guildmate is running an older version)

---

## Development

Built for TBC Classic Anniversary (Interface version 20505).

To contribute or develop locally, clone the repo and symlink the folder into your AddOns directory:
```
mklink /D "World of Warcraft\_anniversary_\Interface\AddOns\wowcraft" "path\to\your\clone\wowcraft"
```

Any changes saved in your editor are live after a `/reload` in game.

---

## Author

Tomor