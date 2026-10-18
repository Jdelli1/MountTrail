# AzerothTrail

AzerothTrail is a World of Warcraft Retail (Midnight 12.x) addon that tracks which mounts you are missing and plots an efficient route to farm them.

## Features

- **Journal by expansion**: browse every farmable mount grouped by expansion, with filters, search, a tooltip with drop details, your attempts on this character and in total over all your characters (the game's kill statistics where it keeps them, else AzerothTrail's own per-character counter; Rarity's count when larger), and Ctrl-click to preview the mount.
- **Journal front page**: a minimal overview: your collected total over every expansion (count, percent and a slim bar), then one flat tile per expansion with its logo, a progress bar, owned / total and percent (green with a check once complete); click a tile for its mount list.
- **Click a row for a waypoint**: left-click a mount row (on any tab, or a Route step) to set a waypoint at the mount's location or its dungeon / raid entrance: the game's own map pin by default, or a TomTom waypoint (the previous AzerothTrail one is replaced) or both, as chosen on the settings page. Chat confirms the place, e.g. `Waypoint: The Vortex Pinnacle (entrance)`. Shift-left-click opens the world map there instead (not in combat). A map-pin icon on the right marks rows a click can pin (an exact spot or a dungeon / raid entrance); a map icon marks mounts known only by zone (fishing, zone-wide drops), where a click opens that zone's map and chat says there is no exact spot.
- **Zone panel**: a slim side panel docked to the window's right edge (the pin button in the title bar, or `/azt zone`) listing "Mounts in <zone>": every mount you can still get whose location is your current zone, by its map coordinates, the Mount Journal's `Zone:` line, or a dungeon / raid whose entrance is in the zone (inside an instance: that instance's mounts). Owned and other-faction mounts are hidden unless the Collected filter is on (in every list, owned mounts then show on a light green row with a green name). Rows behave like the lists (click for a waypoint, hover for the tooltip); it updates as you change zones. The open state is saved.
- **Holidays**: holiday mounts, with the ones whose event is currently running highlighted.
- **Achievements**: achievement-reward mounts, grouped by expansion. Hovering one shows the achievement that rewards it with its criteria progress; Shift-right-click the row to open that achievement in the Achievements window.
- **Timewalking**: mounts from the Timewalking vendors.
- **Misc**: profession, shop, Trading Post and other mounts that do not belong to an expansion or holiday.
- **Per-character Route**: an ordered farming route for the character you are logged in on, with automatic ticks when a lockout or quest flag shows a kill, and manual ticks only for the few kills the game does not report (a ticked game-tracked row always means a real lockout on this character), and reset timers for the daily and weekly lockouts.
- **Daily / weekly checklist**: the Route tab's Route / Checklist switch shows every lockout this character can still spend on a mount, under collapsible "Daily" and "Weekly" headers with their reset countdowns and done/total counts, each split into collapsible expansion sub-headers with their own done/total: one row per lockout (each Vault of Archavon watcher counts; a kill that can drop several mounts, such as Malygos' two drakes, is one row named after the boss that lists its mounts on hover; clicking a checklist or route row sets the waypoint at that boss's instance entrance), plus tracked mounts the route does not list (rare-spawn quest flags, which reset daily, world-boss ones weekly, and holiday bosses such as Ahune while the holiday is on). Owned, other-faction and unobtainable mounts are left out. Rows tick themselves from this character's lockouts; only lockouts the game can't report get a clickable box (the route's own ticks); not-done rows come first. Click a row for a waypoint, hover for the tooltip; finished rows disappear on their own (the header counts them).
- **Route arrow mode**: switch the Route tab (or `/azt arrow`) from the list to a small movable frame that shows the next step, the travel steps leading to it and an arrow with the distance to the target. It sets the game's waypoint (and a TomTom waypoint) for each new step, follows the route while the main window is closed, and can skip a step for the session.
- **Settings page**: Options > AddOns > AzerothTrail (or `/azt options`) chooses where a row's left-click puts the waypoint: the in-game map pin (default), a TomTom arrow only, or both (the TomTom choices use the in-game pin when TomTom is not loaded). It also lists unobtainable mounts you do not own on the Misc tab under "Unobtainable" (`Show unobtainable mounts`, off by default; owned ones stay where they are and the Journal counts never include them), shows or hides the minimap button and turns debug messages on or off (the same as `/azt debug`). The route arrow keeps its own waypoints.
- **Optional integrations**: [TomTom](https://www.curseforge.com/wow/addons/tomtom) waypoints and [Rarity](https://github.com/WowRarity/Rarity) attempt counts are used when those addons are installed. Neither is required.

## Install

CurseForge and Wago packages will follow once in-game verification is done. For now, install it as a development link.

### Development install

`tools/link_addon.ps1` creates a directory junction from your WoW AddOns folder to this repository, so edits show up after `/reload`:

```powershell
powershell -ExecutionPolicy Bypass -File tools/link_addon.ps1 -WowPath "C:\Program Files (x86)\World of Warcraft"
```

The junction is created at `<WowPath>\_retail_\Interface\AddOns\AzerothTrail`. The script is safe to run again (an existing junction is left alone) and refuses to touch an existing folder that is not a junction. To unlink, delete the junction itself with `cmd /c rmdir "<WowPath>\_retail_\Interface\AddOns\AzerothTrail"`, which does not delete the repository.

## Slash commands

| Command | Action |
| --- | --- |
| `/azt` | Show or hide the window |
| `/azt dump` | List saved instances (instance ID, difficulty ID, bosses) for checking `Data/Lockouts.lua` |
| `/azt arrow` | Switch the route between the list and the arrow frame |
| `/azt zone` | Show or hide the zone panel (opens the window too when it is closed) |
| `/azt options` | Open the AzerothTrail page in Options > AddOns |
| `/azt debug` | Toggle debug mode: errors AzerothTrail catches around maps, waypoints and the arrow go to the error handler (off by default) |
| `/azt help` | List the commands |
| `/azerothtrail` | Same as `/azt` |

## Development

```bash
python -m pip install lupa
python tools/run_tests.py
python -m unittest tools/test_build_data.py
python tools/build_data.py [--update]
```

`tools/build_data.py` regenerates `Data/Mounts.lua` and `Data/Route.lua` from the sources pinned in `tools/sources.json`; `--update` moves those pins forward.

`python tools/verify_data.py` checks `Data/` against the game's own DB2 tables (Mount, Encounter Journal loot, instances, LFG dungeons; via wago.tools) and writes [docs/data-verification.md](docs/data-verification.md); it exits 1 on any error not in `tools/verify_allow.json` (tests: `python -m unittest tools/test_verify_data.py`).

## Status

The addon is built and unit-tested, but **in-game verification is still pending**. See [docs/ingame-checklist.md](docs/ingame-checklist.md) for the open checks, starting with attempt counting under Midnight restrictions.

## Release notes

- **Name availability**: check pending (search pages not reachable from build environment). On 2026-10-16 the CurseForge search page answered with a Cloudflare challenge (HTTP 403) and the Wago search page is rendered client-side, so neither returned a usable result. Search both sites for "AzerothTrail" by hand before the first upload.

## Credits

AzerothTrail builds on the work of others. Thank you to everyone below.

### Data sources

| Project | License | Used for |
| --- | --- | --- |
| [SimpleArmory](https://github.com/kevinclement/SimpleArmory) | MIT, copy at `Data/LICENSE-SimpleArmory.txt` | Route and mount data |
| [Rarity](https://github.com/WowRarity/Rarity) | GPL-2.0 | Drop rates, quest IDs, coordinates |

`Data/Mounts.lua` and `Data/Route.lua` are generated by `tools/build_data.py` from the commits pinned in `tools/sources.json`; each file's header names those commits. `Data/LICENSE-SimpleArmory.txt` reproduces SimpleArmory's MIT license verbatim and is refreshed by the same script.

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
- Ace3's license forbids stand-alone redistribution of its libraries. They are bundled here only as embedded libraries of AzerothTrail and are not offered separately.

### Optional integrations

- [TomTom](https://www.curseforge.com/wow/addons/tomtom) by jnwhiteh: optional waypoint integration, not bundled. Licensed "All Rights Reserved" per its CurseForge page; the integration calls its public API only, no code copied.

## License

GNU General Public License v2.0, see [LICENSE](LICENSE).
