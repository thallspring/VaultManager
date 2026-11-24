# Vault Manager — Project Rules & Architecture

## Target Environment & Language
- **Target Client:** World of Warcraft: Forever (`1.60.1` / TBC-era Lua 5.1 API). Avoid modern Retail-only APIs (`C_Container`, `C_Item`, etc.) unless guarded with fallbacks.
- **Strict English Only:** All UI labels, tooltips, chat messages, comments, changelog entries, and commit messages must be strictly in English.

## Data Architecture & Safety
- **Per-Guild Isolation:** All guild-specific data (`vault`, `ledger`, `requests`, `fulfillments`, `roster`, `tabRules`, `scanMetadata`, `uiPrefs`) lives inside `VaultManagerDB.guilds[guildKey]` (`Realm-GuildName`), while `VaultManagerDB.ahPrices` is shared across the realm.
- **Defensive Initialization:** Never assume `GetGuildInfo("player")` is populated during `ADDON_LOADED` or `PLAYER_ENTERING_WORLD`. Always initialize all sub-tables (`uiPrefs`, `vault`, `ledger`, `requests`, `fulfillments`, `roster`, `tabRules`, `scanMetadata`) with `or {}` before reading or writing.
- **P2P Protocol (`Comms.lua`):** Current protocol is `VM.VERSION = 6`. Every outgoing `GUILD` message must include `guildName`, and incoming payloads must strictly match `GetGuildInfo("player")` before updating state. Preserve original scanner metadata (`lastScanBy`, `lastScanTime`) during syncs.
- **Slash Command Independence:** Register `SLASH_VAULTMANAGER1 = "/vm"` at the top level of `Core.lua` before `UI:Init()` so UI errors never break `/vm`.

## Release & Git Workflow
- **Versioning:** Keep `## Version` in `VaultManager.toc` in sync with `CHANGELOG.md` and the header badge (`VAULT MANAGER vX.Y.Z`). Keep `## X-Curse-Project-ID: 1823514` intact.
- **Local Commits Only:** Verify zero Lua syntax errors before committing. Always commit changes locally to `main`, and **never** run `git push` or `git tag` unless explicitly instructed.
- **Token Hygiene:** Only read files explicitly referenced with `@filename` or directly required for the requested edit; avoid scanning the entire codebase unnecessarily.
