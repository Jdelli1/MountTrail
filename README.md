# MountTrail

MountTrail is a World of Warcraft Retail (Midnight 12.x) addon that tracks which mounts you are missing and the daily / weekly lockouts this character has left to farm them.

## Features

- **Journal by expansion**: browse every farmable mount grouped by expansion, with filters, search, a tooltip with drop details, your attempts on this character and in total over all your characters (the game's kill statistics where it keeps them, else MountTrail's own per-character counter; Rarity's count when larger), and Ctrl-click to preview the mount.
- **Journal front page**: a minimal overview: your collected total over every expansion (count, percent and a slim bar), then one flat tile per expansion with its logo, a progress bar, owned / total and percent (green with a check once complete); click a tile for its mount list.
- **Click a row for a waypoint**: left-click a mount row (on any tab, or a Checklist row) to set a waypoint at the mount's location or its dungeon / raid entrance: the game's own map pin by default, or a TomTom waypoint (the previous MountTrail one is replaced) or both, as chosen on the settings page. Chat confirms the place, e.g. `Waypoint: The Vortex Pinnacle (entrance)`. Shift-left-click opens the world map there instead (not in combat). A map-pin icon on the right marks rows a click can pin (an exact spot or a dungeon / raid entrance); a map icon marks mounts known only by zone (fishing, zone-wide drops), where a click opens that zone's map and chat says there is no exact spot.
- **World map tab**: an MountTrail tab in the Map & Quest Log's side tabs (under Quests, Events and Map Legend). Select it to see "Mounts in <zone>" for the map you are looking at, with the same rows as the zone panel; it follows the map as you browse, and a world or continent map asks you to open a zone. Clicking a quest-log tab (or opening a quest) switches back. The tab stays selected next time if you left it selected.
- **Mount detail pane**: every mount list has a pane on its right; click a mount to see Blizzard's 3D preview (rotate, zoom, with or without your character riding it), its flavor text and the tooltip's details (source, drop chance, attempts, lockout, achievement progress), with Waypoint, Map and Achievement buttons.
- **Waypoints to the NPC**: a waypoint goes to the vendor that sells the mount, or to the rare's spawn point nearest you (every spawn point is known), named in chat; raid and dungeon mounts still go to the entrance.
- **Pop-out checklists and custom lists**: right-click any Checklist header (an expansion's dailies, weeklies or rare spawns, or one category) to pop it out as its own small window, or right-click the Daily, Weekly or Rare spawns chip at the top to pop out that whole group (every expansion, under expansion headers; the Lists chip offers a menu of lists to pop out); open as many as you like, they stay on screen and come back after /reload. Build your own lists with the "+ List" button on any mount and pop them out too. One button sets the waypoint everywhere: a rare with several spawn points gets them all on TomTom.
- **Zone panel**: a slim side panel docked to the window's right edge (the pin button in the title bar, or `/mtrail zone`) listing "Mounts in <zone>": every mount you can still get whose location is your current zone, by its map coordinates, any `Zone:` line of its Mount Journal source (where it drops, or where the vendor that sells it stands, also in a city inside the zone; in the right version of a zone that exists more than once, such as TBC and WoD Nagrand or the Midnight Eversong Woods), or a dungeon / raid whose entrance is in the zone (inside an instance: that instance's mounts). Owned and other-faction mounts are hidden unless the Collected filter is on (in every list, owned mounts then show on a light green row with a green name). Rows behave like the lists (click for a waypoint, hover for the tooltip); it updates as you change zones. The open state is saved.
- **Holidays**: holiday mounts, with the ones whose event is currently running highlighted.
- **Achievements**: achievement-reward mounts, grouped by expansion. Hovering one shows the achievement that rewards it with its criteria progress; Shift-right-click the row to open that achievement in the Achievements window.
- **Timewalking**: mounts from the Timewalking vendors.
- **Misc**: mounts that do not belong to an expansion or holiday, by category: Professions, In-game Shop, Trading Post, PvP, Racial, Mythic+, Promotions, Class, Black Market, Collection rewards and Other (Feats of Strength, Old School Ride, Make-A-Wish, Guild Vendor, Unknown), then Unobtainable: past limited-time offers you own (seasons, Remix, Plunderstorm; with Collected on), plus every unobtainable mount you do not own when `Show unobtainable mounts` is on.
- **Filters per tab**: each list tab's Filter button offers its own categories as `Show ...` checkboxes, plus Collected and Check all / Uncheck all: the Journal its sources (`Show dungeon drops`, `Show raid drops`, ...), Misc its categories (`Show profession mounts`, `Show in-game shop mounts`, ..., `Show unobtainable mounts`), Holidays each holiday, Achievements each expansion and General; Timewalking has Collected only. Choices are saved account-wide per tab (Collected is shared); the reset arrow next to the button restores that tab's defaults.
- **Daily / weekly checklist**: the Checklist tab shows, for the character you are logged in on (its name, the weekly and daily reset timers and how many lockouts are left in the header), every lockout this character can still spend on a mount, under collapsible "Daily" and "Weekly" headers with their reset countdowns and done/total counts, each split into collapsible expansion sub-headers and, under those, category headers (Raids, Dungeons, World bosses, Rares, Holidays, Other), each with its own done/total; a Filter button (Show raids / dungeons / world bosses / rares / holidays / other / rare spawns (no lockout), saved per character) narrows the list and its counts: one row per lockout (each Vault of Archavon watcher counts; a kill that can drop several mounts, such as Malygos' two drakes, is one row named after the boss that lists its mounts on hover; clicking a checklist row sets the waypoint at that boss's instance entrance), plus tracked mounts the route does not list (rare-spawn quest flags, which reset daily, world-boss ones weekly, and holiday bosses such as Ahune while the holiday is on). Owned, other-faction and unobtainable mounts are left out. Rows tick themselves from this character's lockouts; only lockouts the game can't report get a clickable box (a ticked game-tracked row always means a real lockout on this character); not-done rows come first. Click a row for a waypoint, hover for the tooltip; finished rows disappear on their own (the header counts them).
- **Alt lockout matrix**: `/mtrail alts` (or the Alts button in the Checklist header) opens a movable window with one column per character you have logged in on (name in its class colour, the current one first) and one row per daily / weekly mount lockout, under Weekly and Daily headers then expansion sub-headers (click a header to collapse it). A green check means that character is saved, a dim square that it can still farm it, a dash that the lockout is not for its faction and `?` that it has no lockout data yet (log in on it once); hover a cell to see which. Each character's lockouts count as open again once the reset after its last login has passed, and hand ticks expire as on the Checklist. Click a row's name for a waypoint; right-click a name to hide that character ("Show all" brings them back). The Checklist's Filter categories apply. The window remembers its position. It is customised like a pop-out: right-click its title for the appearance menu (opacity, background, header and text colour, font size, font, Apply to all pop-outs, Reset appearance), drag its corner grip to size it (the character columns that fit follow the width; right-click the grip to fit them again), and it snaps to a pop-out or the main window when dropped near one.
- **Rare spawns with no lockout**: rare-spawn mounts whose rare has no known kill flag (long-respawn rares such as Nok-Karosh, Gorok or the Time-Lost Proto-Drake, every expansion) are listed on the Checklist under a third group, "Rare spawns (no lockout)", after Daily and Weekly: by expansion, then by zone (the zone the game's source text names), each header showing how many mounts are left. These rows have no reset and never count as done; each row's box records when you last checked the spawn ("Last checked 3 hr ago", refreshed every minute while the tab is open; click again to update, right-click to clear), and a row leaves the list once you own the mount. The Filter's `Show rare spawns (no lockout)` hides the group; the lockouts-left counts never include it.
- **Live status for event rares**: on the checklist, the rares of the N'Zoth assaults (Uldum, Vale of Eternal Blossoms) show which assault is running in their zone and how long it has left (e.g. `Uldum: Aqir assault — 2 Days 4 Hr left`), and the Arathi / Darkshore warfront rares show the warfront's state as the game names it (e.g. `Arathi warfront: Contributing (63%)`); a category header shows the line too when every rare under it shares it. It is information only: the game's data does not say which assault or warfront phase a given rare belongs to, so the addon never claims a rare is up. When the game has not sent the zone's data yet the line reads `Status unknown — click to load`.
- **Route planner: retired for now.** The ordered farming route (the old Route tab with its route list, Show completed box and List / Arrow switch) and the route arrow (`/mtrail arrow`) are gone from the addon for now; the Checklist tab replaced the Route tab (a saved Route tab opens the Checklist). The route data stays: the checklist reads its lockouts, bosses and entrances from it.
- **Settings page**: Options > AddOns > MountTrail (or `/mtrail options`) chooses where a row's left-click puts the waypoint: the in-game map pin (default), a TomTom arrow only, or both (the TomTom choices use the in-game pin when TomTom is not loaded). It also lists unobtainable mounts you do not own on the Misc tab under "Unobtainable" (`Show unobtainable mounts`, off by default; owned ones stay where they are and the Journal counts never include them), shows or hides the minimap button and turns debug messages on or off (the same as `/mtrail debug`).
- **Optional integrations**: [TomTom](https://www.curseforge.com/wow/addons/tomtom) waypoints and [Rarity](https://github.com/WowRarity/Rarity) attempt counts are used when those addons are installed. Neither is required.

## Install

CurseForge and Wago packages will follow once in-game verification is done. For now, install it as a development link.

### Development install

`tools/link_addon.ps1` creates a directory junction from your WoW AddOns folder to this repository, so edits show up after `/reload`:

```powershell
powershell -ExecutionPolicy Bypass -File tools/link_addon.ps1 -WowPath "C:\Program Files (x86)\World of Warcraft"
```

The junction is created at `<WowPath>\_retail_\Interface\AddOns\MountTrail`. The script is safe to run again (an existing junction is left alone) and refuses to touch an existing folder that is not a junction. To unlink, delete the junction itself with `cmd /c rmdir "<WowPath>\_retail_\Interface\AddOns\MountTrail"`, which does not delete the repository.

## Slash commands

| Command | Action |
| --- | --- |
| `/mtrail` | Show or hide the window |
| `/mtrail dump` | List saved instances (instance ID, difficulty ID, bosses) for checking `Data/Lockouts.lua` |
| `/mtrail zone` | Show or hide the zone panel (opens the window too when it is closed) |
| `/mtrail rares` | Show or hide the rare spawns of your zone (the window follows you into a new zone, sub-zone or cave) |
| `/mtrail alts` | Show or hide the alt lockout matrix (which characters are still unsaved) |
| `/mtrail options` | Open the MountTrail page in Options > AddOns |
| `/mtrail debug` | Toggle debug mode: errors MountTrail catches around maps and waypoints go to the error handler (off by default) |
| `/mtrail help` | List the commands |
| `/mounttrail`, `/mtl` | Same as `/mtrail` |
| `/azt`, `/azerothtrail` | The old name's commands, still the same as `/mtrail` |

## Development

```bash
python -m pip install lupa
python tools/run_tests.py
python -m unittest tools/test_build_data.py
python tools/build_data.py [--update]
```

`tools/build_data.py` regenerates `Data/Mounts.lua` and `Data/Route.lua` from the sources pinned in `tools/sources.json`; `--update` moves those pins forward.

`python tools/verify_data.py` checks `Data/` against the game's own DB2 tables (Mount, Encounter Journal loot, instances, LFG dungeons, and the assault / warfront IDs behind the event-rare status: AreaPOI, Contribution, UiMap; via wago.tools) and writes [docs/data-verification.md](docs/data-verification.md); it exits 1 on any error not in `tools/verify_allow.json` (tests: `python -m unittest tools/test_verify_data.py`). Besides mount identity, route and lockout specs it checks that every collectable Mount.db2 mount is in the data, that each mount's section agrees with the game's source, and that every rare-spawn mount is on the checklist.

## Status

The addon is built and unit-tested, but **in-game verification is still pending**. See [docs/ingame-checklist.md](docs/ingame-checklist.md) for the open checks, starting with attempt counting under Midnight restrictions.

## Release notes

- **Name availability**: check pending (search pages not reachable from build environment). On 2026-10-16 the CurseForge search page answered with a Cloudflare challenge (HTTP 403) and the Wago search page is rendered client-side, so neither returned a usable result. Search both sites for "MountTrail" by hand before the first upload.

## Credits

MountTrail builds on the work of others. Thank you to everyone below.

### Data sources

| Project | License | Used for |
| --- | --- | --- |
| [SimpleArmory](https://github.com/kevinclement/SimpleArmory) | MIT, copy at `Data/LICENSE-SimpleArmory.txt` | Route and mount data |
| [Rarity](https://github.com/WowRarity/Rarity) | GPL-2.0 | Drop rates, quest IDs, coordinates |
| [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings) | MIT, copy at `Data/LICENSE-AllTheThings.txt` | Where the NPC behind a mount stands: rare spawn points, vendors, daily quests |
| Blizzard game data (DB2 tables via [wago.tools](https://wago.tools)) | Blizzard | Mount source text, map tree, zone versions, verification |

`Data/Mounts.lua` and `Data/Route.lua` are generated by `tools/build_data.py` from the commits pinned in `tools/sources.json`; each file's header names those commits. `Data/LICENSE-SimpleArmory.txt` reproduces SimpleArmory's MIT license verbatim and is refreshed by the same script. `Data/Spots.lua` is generated by `tools/build_spots.py` from the AllTheThings commit pinned there (NPC IDs, coordinates, daily quests, factions), with names and zones from the game's own mount source text; `Data/LICENSE-AllTheThings.txt` reproduces AllTheThings' MIT license verbatim. `Data/Zones.lua` is generated by `tools/build_zones.py` from the game's UiMap and ContentTuning tables.

### Libraries

The libraries below are bundled unmodified under `Libs/` and loaded through `embeds.xml`.

| Library | Source | Version | License |
| --- | --- | --- | --- |
| LibStub, CallbackHandler-1.0, AceAddon-3.0, AceDB-3.0, AceConsole-3.0, AceEvent-3.0 | [Ace3](https://github.com/WoWUIDev/Ace3) | tag `Release-r1403`, commit `d295b12f8b889a30e86e0e901c5494df4b149c49` | Ace3 BSD-style license, copy at `Libs/LICENSE-Ace3.txt` (LibStub's own header places it in the public domain) |
| LibDataBroker-1.1 | [tekkub/libdatabroker-1-1](https://github.com/tekkub/libdatabroker-1-1) | tag `v1.1.4`, commit `1a63ede0248c11aa1ee415187c1f9c9489ce3e02` | No license file or header upstream; bundled as a standard LDB library (see note below) |
| LibDBIcon-1.0 | [CurseForge: libdbicon-1-0](https://www.curseforge.com/wow/addons/libdbicon-1-0) (author Funkeh/funkydude, no official GitHub repo) | `v12.1.1` (CurseForge file 9119909, svn r165, `LibDBIcon-1.0.lua` MINOR 57) | CurseForge lists "Ace3 Style BSD"; the library's .toc says `X-License: All Rights Reserved` (see note below) |

Notes:

- LibDBIcon-1.0 states conflicting licenses (CurseForge page vs its own .toc) and ships no license file. It is a standard, widely embedded library; if the author objects it can be removed, since the minimap button is optional.
- LibDataBroker-1.1 has no stated license upstream. Same caveat as above.
- Ace3 libraries not listed above (AceGUI, AceConfig, and so on) are deliberately not included.
- Ace3's license forbids stand-alone redistribution of its libraries. They are bundled here only as embedded libraries of MountTrail and are not offered separately.

### Optional integrations

- [TomTom](https://www.curseforge.com/wow/addons/tomtom) by jnwhiteh: optional waypoint integration, not bundled. Licensed "All Rights Reserved" per its CurseForge page; the integration calls its public API only, no code copied.

## License

GNU General Public License v2.0, see [LICENSE](LICENSE).
