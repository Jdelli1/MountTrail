# MountTrail

MountTrail is a World of Warcraft Retail (Midnight 12.x) addon that tracks
which mounts you are missing and the daily / weekly lockouts this character
has left to farm them.

- [Install and requirements](#install-and-requirements)
- [The window](#the-window)
- [Clicking a mount](#clicking-a-mount)
- [Pop-outs](#pop-outs)
- [Zone panel and world map tab](#zone-panel-and-world-map-tab)
- [Alt lockout matrix](#alt-lockout-matrix)
- [Search](#search)
- [Options](#options)
- [Slash commands](#slash-commands)
- [Optional addons](#optional-addons)
- [Known limits](#known-limits)
- [Credits](#credits)

## Install and requirements

- **TomTom is required.** [TomTom](https://www.curseforge.com/wow/addons/tomtom)
  carries every waypoint. Without it MountTrail still loads, but a popup at
  login and a red error on each waypoint click (on screen and in chat) say to
  install it.
- CurseForge and Wago packages will follow once in-game verification is done.
  For now, install MountTrail as a development link: see
  [CONTRIBUTING.md](CONTRIBUTING.md#setup) (`tools/link_addon.ps1`).

## The window

`/mtrail` (or the minimap button) opens the window. It is 900 x 560 by default.
Drag the corner grip to resize it. Its three boxes (navigation, list, detail
pane) share the width: drag the navigation's right edge or the detail pane's
left edge to resize them (saved; right-click either edge for the default).

### Navigation column

The left column replaces the old tabs:

- **Home**: the front page.
- **Lockouts**: the daily / weekly checklist, with how many lockouts are left.
- **Current Zone**: every mount still to get in your zone, grouped by source,
  following you as you move. Right-click it (or use `Pop out`) for a small
  window that follows you.
- **Alts**: the [alt lockout matrix](#alt-lockout-matrix).
- **Browse** by source: Drops, Vendors & Reputation, Quests & Activities,
  Achievements, Professions, In-game Shop, Trading Post, PvP, Mythic+,
  Holidays, Timewalking, Other.
- **My lists**: each of your own lists, with `+` to start one, and its
  lockouts open today in green. It starts with an example, Mythic Mounts
  (every mount that drops in Mythic dungeons), yours to edit, rename or delete.
- **Quick lists**: the built-in ones. Daily lockouts, Weekly lockouts and Rare
  Spawns each open Lockouts on that group, with what is left as the badge.

Working with the column:

- Click a list to open it as a page: its mounts by source, Collected and the
  detail pane as on any list, and a `Pop out` button.
- Right-click a list to pop it out; Shift-right-click one of your own lists to
  rename or delete it.
- Click a list's star to make it a favourite, pinned to the top of its section
  (click again to unpin).
- Alt-drag an entry of My lists, Quick lists or Browse to put the section in
  your own order (saved; a list never moves above a favourite).
- Click a heading (Browse, My lists, Quick lists) to collapse or expand it
  (saved).
- The settings can hide My lists or Quick lists (`Show My lists`,
  `Show Quick lists`). The column scrolls when your lists outgrow it.

### Home

- Your collected total over every expansion (count, percent and a slim bar),
  with a chip per tab showing its own owned / total.
- One flat tile per expansion with its logo, a progress bar, owned / total and
  percent (green with a check once complete). Click a tile for its mount list.
- Every bar takes its completion colour: red under 25 %, yellow under 75 %,
  green below complete and blue once complete (the total bar too).
- A search box over every mount (see [Search](#search)).

### Mount lists

Every list (an expansion, a Browse page, a list page, Holidays, Achievements,
Timewalking) groups its mounts under headers.

- **Tooltip**: drop details, your attempts on this character and in total over
  all your characters (the game's kill statistics where it keeps them, else
  MountTrail's own per-character counter; Rarity's count when larger).
- **Filters**: each list's Filter button offers its own categories as
  `Show ...` checkboxes, plus Collected and Check all / Uncheck all. The
  Journal has its sources (`Show dungeon drops`, `Show raid drops`, ...), Misc
  its categories (`Show profession mounts`, `Show in-game shop mounts`, ...,
  `Show unobtainable mounts`), Holidays each holiday, Achievements each
  expansion and General; Timewalking has Collected only. Choices are saved
  account-wide per list (Collected is shared); the reset arrow next to the
  button restores that list's defaults.
- **Collected**: owned and other-faction mounts are hidden unless Collected is
  on; owned mounts then show on a light green row with a green name.
- **Collapse**: click a header to collapse it. Shift-click any header to
  collapse every header of that list at once, or, on a collapsed header, to
  expand them all again (nested ones too). This works in every list, the
  Lockouts view, the zone panel, the alt lockouts window and pop-out group
  headers.

Browse pages:

- **Holidays**: holiday mounts. Holidays on the calendar now come first, and
  each header shows when the holiday ends or next starts.
- **Achievements**: achievement-reward mounts, grouped by expansion. Hovering
  one shows the achievement that rewards it, with its criteria progress.
- **Timewalking**: mounts from the Timewalking vendors.
- The other categories are a page of their mounts grouped by expansion. What
  used to be the Misc tab (Professions, In-game Shop, Trading Post, PvP,
  Racial, Mythic+, Promotions, Class, Black Market, Collection rewards, Other)
  is split among them. Unobtainable mounts: past limited-time offers you own
  (seasons, Remix, Plunderstorm; with Collected on), plus every unobtainable
  mount you do not own when `Show unobtainable mounts` is on.

### Detail pane

Every mount list has a pane on its right. Click a mount to see:

- Blizzard's 3D preview (rotate, zoom, with or without your character riding
  it).
- Its flavour text and the tooltip's details: source, drop chance, attempts,
  lockout, achievement progress.
- Where to find it: the vendor that sells it or the rare that drops it, by
  name, its zones and how many spawn points.
- With AllTheThings installed, its "How to get it" note (the Skyshards for the
  Thundering Ruby Cloud Serpent, ...).
- `Wowhead`: the mount's Wowhead page (guides, comments) as a link to copy.

### Lockouts

The Lockouts view shows, for the character you are logged in on, every lockout
it can still spend on a mount.

- The header has the character's name, the weekly and daily reset timers and
  how many lockouts are left.
- "Daily" and "Weekly" headers carry their reset countdowns and done / total
  counts. Each splits into expansion sub-headers, then category headers
  (Raids, Dungeons, World bosses, Rares, Holidays, Other), each with its own
  done / total. All of them collapse.
- One row per lockout. Each Vault of Archavon watcher counts. A kill that can
  drop several mounts, such as Malygos' two drakes, is one row named after the
  boss, listing its mounts on hover.
- Also listed: tracked mounts the route does not list (rare-spawn quest flags,
  which reset daily; world-boss ones, weekly; holiday bosses such as Ahune
  while the holiday is on).
- Owned, other-faction and unobtainable mounts are left out.
- Rows tick themselves from this character's lockouts. Only lockouts the game
  can't report get a clickable box, so a ticked game-tracked row always means a
  real lockout on this character. Not-done rows come first; finished rows
  disappear on their own (the header counts them).
- The Filter button (Show raids / dungeons / world bosses / rares / holidays /
  other / rare spawns (no lockout), saved per character) narrows the list and
  its counts.
- The Daily, Weekly and Rare Spawns chips at the top: right-click one to pop
  out that whole group.
- `Show completed` (top of the Filter menu): lockouts already done stay
  listed, dimmed, after the open ones (off by default; saved account-wide;
  the Filter's reset arrow turns it off too).

**Rare Spawns (no lockout).** Rare-spawn mounts whose rare has no known kill
flag (long-respawn rares such as Nok-Karosh, Gorok or the Time-Lost
Proto-Drake, every expansion) are listed under a third group after Daily and
Weekly: by expansion, then by zone (the zone the game's source text names),
each header showing how many mounts are left.

- These rows have no reset and never count as done.
- Each row's box records when you last checked the spawn ("Last checked 3 hr
  ago", refreshed every minute while the view is open). Click again to update,
  right-click to clear.
- A row leaves the list once you own the mount.
- The Filter's `Show rare spawns (no lockout)` hides the group; the
  lockouts-left counts never include it.

**Live status for event rares.**

- The rares of the N'Zoth assaults (Uldum, Vale of Eternal Blossoms) show which
  assault is running in their zone and how long it has left, e.g.
  `Uldum: Aqir assault — 2 Days 4 Hr left`.
- The Arathi / Darkshore warfront rares show the warfront's state as the game
  names it, e.g. `Arathi warfront: Contributing (63%)`.
- A category header shows the line too when every rare under it shares it.
- This is information only: the game's data does not say which assault or
  warfront phase a given rare belongs to, so the addon never claims a rare is
  up. When the game has not sent the zone's data yet the line reads
  `Status unknown — click to load`.

## Clicking a mount

In the lists with a detail pane (Home's lists, Browse, list pages, Current
Zone, Lockouts):

| Click | Does |
| --- | --- |
| Left-click | Shows the mount in the detail pane. |
| Right-click | Plots it on TomTom: its spot, its dungeon / raid entrance, or every spawn point of a rare that has several. An achievement mount opens its achievement instead; an event rare with unknown status opens the zone map. |
| Shift-click | Opens the world map there (not in combat). |
| Ctrl-click | Previews the mount in the dressing room. |

Hovering a row lists the clicks that do something for that mount.

In the zone panel and the world map tab, a left-click sets the waypoint (an
achievement mount opens its achievement), Shift-left-click opens the world map,
Ctrl-left-click previews and Shift-right-click opens the achievement. A map-pin
icon marks rows a click can pin (an exact spot or a dungeon / raid entrance); a
map icon marks mounts known only by zone (fishing, zone-wide drops), where a
click opens that zone's map and chat says there is no exact spot.

Where a waypoint goes:

- The vendor that sells the mount, or the rare's spawn point nearest you
  (every spawn point is known), named in chat.
- Raid and dungeon mounts go to the entrance; a Lockouts row goes to its boss's
  instance entrance.
- Chat confirms the place, e.g. `Waypoint: The Vortex Pinnacle (entrance)`.
  The previous MountTrail waypoint is replaced.

## Pop-outs

**Wrong-difficulty warning**: with a pop-out open, zoning into a raid or
dungeon (or changing its difficulty) checks the pop-out's mounts: one that
drops in this instance but not on this difficulty gets a warning before you
pull (Options: `Warn about the wrong difficulty`).

A pop-out is a small window that stays on screen without the main window. Open
as many as you like; they come back after /reload.

What you can pop out:

- Right-click any Lockouts header: an expansion's dailies, weeklies or rare
  spawns, or one category.
- Right-click the Daily, Weekly or Rare Spawns chip: that whole group, every
  expansion, under expansion headers.
- Any list: your own lists (build them with `+ List` on any mount) and the
  quick lists.
- `/mtrail rares`: the rare spawns of your zone.
- `/mtrail here`, a right-click on the zone panel's title or on Current Zone:
  every mount you can still get in your zone, under source headers (Dungeon
  drops, Vendors, Achievements, ...) when it has more than one source.

The two zone pop-outs follow you into each new zone, sub-zone or cave.

In a pop-out:

- A click goes to the mount (every spawn point of a rare that has several on
  TomTom), Shift-click opens the world map there and Ctrl-click previews it.
- `Plot all` in the title puts the spawn points of every row whose box is not
  ticked on TomTom at once.
- Right-click a row of your own list to take it off the list.
- Alt-drag a row to reorder it (saved per window).
- Windows that span several expansions group their rows under expansion
  headers; click one to collapse it, Shift-click to collapse or expand all.
  Each row carries a small expansion tag.
- Drag the corner grip to resize (right-click it to fit the rows again).
  Windows snap to each other and to the main window, and a snapped stack moves
  together.
- Right-click the title for the window's menu: `Show completed` (done rows
  stay listed, dimmed; off by default, saved per window), then opacity and font size
  sliders, background, header and text colour, font, `Apply to all pop-outs`,
  `Reset appearance`.
- Ctrl-click a window's x to close every pop-out.

## Zone panel and world map tab

**Zone panel.** A slim side panel docked to the window's right edge (the pin
button in the title bar, or `/mtrail zone`) listing "Mounts in <zone>": every
mount you can still get whose location is your current zone.

- A mount is in the zone by its map coordinates, by any `Zone:` line of its
  Mount Journal source (where it drops, or where the vendor that sells it
  stands, also in a city inside the zone), or by a dungeon / raid whose
  entrance is in the zone. Inside an instance it lists that instance's mounts.
- A zone that exists more than once (TBC and WoD Nagrand, the Midnight
  Eversong Woods) gets the right version's mounts.
- When the mounts come from more than one source, they are grouped under
  collapsible source headers.
- It updates as you change zones, and its open state is saved.

**World map tab.** A MountTrail tab in the Map & Quest Log's side tabs (under
Quests, Events and Map Legend). Select it to see "Mounts in <zone>" for the map
you are looking at, with the same rows as the zone panel.

- It follows the map as you browse; a world or continent map asks you to open
  a zone.
- Clicking a quest-log tab (or opening a quest) switches back.
- The tab stays selected next time if you left it selected.

## Alt lockout matrix

`/mtrail alts` (or Alts in the navigation column) opens a movable window with
one column per character you have logged in on (name in its class colour, the
current one first) and one row per daily / weekly mount lockout, under Weekly
and Daily headers, then expansion sub-headers.

| Cell | Means |
| --- | --- |
| Green check | That character is saved. |
| Dim square | It can still farm it. |
| Dash | The lockout is not for its faction. |
| `?` | No lockout data yet (log in on it once). |

- Hover a cell to see which. Each character's lockouts count as open again
  once the reset after its last login has passed; hand ticks expire as on the
  Lockouts view. The Lockouts Filter categories apply.
- Click a row's name for a waypoint. Right-click a character's name to hide it
  ("Show all" brings them back).
- The window remembers its position. It is customised like a pop-out:
  right-click its title for the appearance menu, drag its corner grip to size
  it (the character columns that fit follow the width; right-click the grip to
  fit them again), and it snaps to a pop-out or the main window.

## Search

Every search box (Home, Browse, Holidays, Achievements, Timewalking, Current
Zone, the list pages) matches the same way: names, abbreviations (tbc, icc,
...), bosses, zones, with some tolerance for typos. When a page has nothing for
a place, it shows that place's expansion instead (icc on Vendors: the Wrath of
the Lich King vendors). On Home, typing opens a results page grouped by what
matched; Back returns home.

## Options

Options > AddOns > MountTrail (or `/mtrail options`). The cogwheel in the
window's title bar has the same settings, plus `Reset text sizes` and
`All options...`.

| Setting | Does |
| --- | --- |
| `Show unobtainable mounts` | Lists unobtainable mounts you do not own under "Unobtainable" (off by default; owned ones stay where they are, and the Journal counts never include them). |
| `Window scale` | 80-150 %: everything in the window, text included. |
| `Gold text size`, `White text size`, `Grey text size` | Text by colour (headers, titles and mount names; body text; second lines): -2 to +6 points each. Rows grow to fit. |
| `Navigation text size` | The navigation column's text, +0 to +6. |
| `Show My lists`, `Show Quick lists` | Show or hide those navigation sections. |
| `Colour pop-out names by rarity` | Off by default; needs Mount Journal Enhanced or MountsRarity. |
| `Warn about the wrong difficulty` | On by default: entering an instance on a difficulty where a mount in your open pop-outs does not drop (Normal instead of Heroic, Heroic instead of Mythic, 10 instead of 25...) shows a warning on screen and in chat, e.g. "Wrong difficulty for Invincible: you are on 25 Player, it drops on 25 Player (Heroic)." Once per instance and difficulty; mounts you own are left out. |
| `Show minimap button` | Shows or hides the minimap button. |
| Debug messages | The same as `/mtrail debug`. |

## Your lists

- **Add a mount**: select it, then `+ List` in the detail pane and tick a
  list (or `New list...` to start one with it). The button reads `Lists (2)`
  once the mount is on some of your lists.
- **Remove a mount**: the same menu, untick the list. On a list's own page the
  menu starts with `Remove from <list>`. In a list's pop-out, right-click the
  mount's row.
- `+` next to My lists starts an empty list or imports one.

## Guides

Step-by-step directions for a mount, like a leveling guide: what to do, where
to go (plotted on TomTom), and when a step is done.

- The **Guides** section of the navigation column lists them. Click one to
  follow it: a small window shows the current step (or every step: right-click
  its title), with **Back** and **Next**. Right-click the title for `Change
  appearance` (the pop-outs' look options); drag its corner to any size. Next plots the next step's points;
  Back takes them off and returns to the step before; on the last step Next
  reads **Finish** and closes the guide. Each character keeps its
  own place in every guide, and the guide comes back after a /reload.
- A step moves on by itself when its done lines hold (a quest turned in, items
  in your bags, the mount learned, a spot reached), except right after Back.
- A mount with a guide shows a **Guide** button in the detail pane.
- `+` next to Guides: **New guide...** (a template to fill in) or **Import
  guide...** (paste one). Right-click a guide to edit it (a built-in one as a
  copy), export it (its text, ready to copy), go back to step 1 or delete it.

A guide is plain text, one keyword per line, so it can be written anywhere and
shared by copy and paste. `**words**` are highlighted, and `[item:ID]`,
`[quest:ID]`, `[mount:ID]`, `[spell:ID]` or `[achievement:ID]` become the
game's links with their tooltips. A `macro` line gives the step **Copy macro**
and **Make macro** buttons, and `#author` / `#credit` lines credit the people
behind a guide. **[docs/GUIDES.md](docs/GUIDES.md) explains
how to write guides**: every keyword, done lines, highlighting, links, finding
IDs and coordinates, and what the editor's messages mean.

```
#guide Thundering Ruby Cloud Serpent
#mount 517
step Travel to the Vale of Eternal Blossoms
  goto 390 56.2 42.6 Vale of Eternal Blossoms
  reach 200
step Kill mobs in the Vale until you have **ten Skyshards**
step Use the Sky Crystal near Alani, then kill her: [mount:517] can drop
  goto 390 35.6 26 Alani
  mount 517
```

## Sharing lists

Shift-right-click one of your lists in the navigation column for:

- **Share in chat**: puts the list's line (`MountTrail: !MT1!...`) in the chat box. Anyone
  with MountTrail sees it as a link, `[MountTrail: Mythic Mounts (13)]`, and
  clicking it offers the import; players without MountTrail see the text.
  The same works for a line pasted by hand into any chat: say, party, raid,
  guild, whispers, channels. A list too long for one chat message is sent as
  a link that asks your MountTrail for it instead (you need to be online).
- **Send to player...**: sends the list straight to a player by name
  (`Name-Realm` for another realm). They are asked whether to import it.
- **Export...**: the list as one line of text (`MountTrail: !MT1!...`) to copy with
  Ctrl+C and paste anywhere: Discord, a guide, a forum post.

To import a pasted line, click `+` next to My lists and pick `Import list...`
(or type `/mtrail import`). Every import asks first, lets you rename the list,
and adds a number when the name is taken. Mounts your version of MountTrail
doesn't know are left out.

## Slash commands

| Command | Action |
| --- | --- |
| `/mtrail` | Show or hide the window |
| `/mtrail zone` | Show or hide the zone panel (opens the window too when it is closed) |
| `/mtrail here` | Show or hide every mount still to get in your zone, in a pop-out that follows you |
| `/mtrail rares` | Show or hide the rare spawns of your zone, in a pop-out that follows you |
| `/mtrail alts` | Show or hide the alt lockout matrix |
| `/mtrail import` | Paste a list someone shared |
| `/mtrail sharetest` | Check that sharing is set up; shows one of your lists as a clickable link (only you see it) |
| `/mtrail options` | Open the MountTrail page in Options > AddOns |
| `/mtrail dump` | List saved instances (instance ID, difficulty ID, bosses) for checking `Data/Lockouts.lua` |
| `/mtrail debug` | Toggle debug mode: errors MountTrail catches around maps and waypoints go to the error handler (off by default) |
| `/mtrail help` | List the commands |
| `/mounttrail`, `/mtl` | Same as `/mtrail` |
| `/azt`, `/azerothtrail` | The old name's commands, still the same as `/mtrail` |

## Optional addons

None of these are required; MountTrail uses them when they are loaded.

- [Rarity](https://github.com/WowRarity/Rarity): attempt counts (the tooltip's
  total uses Rarity's count when it is larger).
- [Mount Journal Enhanced](https://www.curseforge.com/wow/addons/mount-journal-enhanced)
  or the [MountsRarity](https://www.curseforge.com/wow/addons/mountsrarity)
  addon: the tooltip and the detail pane show how rare a mount is ("Rarity
  0.28% of characters", in its quality colour: legendary under 2 %, epic under
  10 %, rare under 20 %, uncommon under 50 %). The option
  `Colour pop-out names by rarity` colours pop-out rows the same way.
- [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings): the detail
  pane's "How to get it" note.

## Known limits

- **In-game verification is still pending.** The addon is built and
  unit-tested; see [docs/ingame-checklist.md](docs/ingame-checklist.md) for
  the open checks, starting with attempt counting under Midnight restrictions.
- **Event rares** never show as "up": the game's data cannot tell which
  assault or warfront phase spawns them (see [Lockouts](#lockouts)).
- **Name availability**: check pending. On 2026-10-16 the CurseForge search
  page answered with a Cloudflare challenge (HTTP 403) and the Wago search page
  is rendered client-side, so neither returned a usable result. Search both
  sites for "MountTrail" by hand before the first upload.

## Development

Planned features and ideas: [docs/ROADMAP.md](docs/ROADMAP.md).

Tests, the data tools and code conventions are in
[CONTRIBUTING.md](CONTRIBUTING.md); the code layout is in
[ARCHITECTURE.md](ARCHITECTURE.md).

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

### Integrations

- [TomTom](https://www.curseforge.com/wow/addons/tomtom) by jnwhiteh: required for waypoints, not bundled (install it separately). Licensed "All Rights Reserved" per its CurseForge page; the integration calls its public API only, no code copied.
- [MountsRarity](https://github.com/sgade/MountsRarity) by sgade (GPL-3.0): how many characters own each mount. Not bundled: read at run time from the MountsRarity-2.0 library when Mount Journal Enhanced or the MountsRarity add-on has loaded it (public API only, no code or data copied).

## License

GNU General Public License v2.0, see [LICENSE](LICENSE).
