# In-game verification checklist

> **Route planner retired (F16):** the Route tab is now **Checklist**. Skip any older step that mentions the route list, "Show completed", the List / Arrow toggle, `/azt arrow` or "Route: N steps left"; those features are gone for now.

- [ ] Run `/dump (select(4, GetBuildInfo()))`; put that number in AzerothTrail.toc's `## Interface:` line (add it to the list). Until it is listed, enable "Load out of date AddOns" on the character screen for this first login.

## FIRST: risk check — attempt counting

Spec risk #1: attempt counting via lockout/flag transitions under Midnight restrictions. Do this before relying on any UI work. **If the count does not move, stop and report before UI work continues.**

- [ ] Link the addon (Task 15 script), log in on a character that does NOT own the target mount, `/reload`, wait a few seconds after login (saved-instance data must arrive first).
- [ ] `/dump AzerothTrailDB.global.attempts` and note the value for the mount (nil = 0).
- [ ] Kill one tracked instance boss (an entry in Data/Lockouts.lua with `instance=`, e.g. 213 Swift White Hawkstrider, Kael'thas in Magisters' Terrace heroic) on a fresh lockout.
- [ ] `/dump AzerothTrailDB.global.attempts[<mountID>]` went up by exactly 1. If not, `/azt dump` to see whether the lockout appears at all, and `/dump AzerothTrailDB.char` (AceDB per-character sections keyed "Name - Realm"; look at `last.snap`) to see what was observed.
- [ ] `/reload` and check the count did not go up again (done -> done must not recount; a kill from before the reload must not be recounted when data arrives). Include a mount tracked by a quest flag that is already done this week (a MoP world boss or Rukhmar from Data/Mounts.lua `quest=`, killed before the reload): its count must not move either.
- [ ] Optional: a quest-flag mount (MoP world boss / Rukhmar, Data/Mounts.lua `quest=`) and a holiday LFG boss (Data/Holidays.lua `lfg=`) each count +1 when killed. Note: hidden tracking quests may not fire `QUEST_TURNED_IN`; the count is then picked up at the next `UPDATE_INSTANCE_INFO` / `LFG_UPDATE_RANDOM_INFO` / login, as long as that happens before the reset.

Items are added by each task; verify in game.

## Task 4: lockout and holiday data

- [ ] Run `/azt dump` while saved to instances and confirm instance IDs, difficulty IDs and boss names against Data/Lockouts.lua (entries marked `-- verify in game` first).
- [ ] Midnight mounts (2817, 2805, 2607, 2950, 3058, 3030) are `manual` because their instance IDs are unknown: once `/azt dump` shows the instance ID and encounter name, replace them with instance specs.
- [ ] Check whether LFR kills appear in `/azt dump` (expected: no).

## Task 10: game adapter, init, debug dump

- [ ] `/reload`: no Lua errors (enable `/console scriptErrors 1`). `/azt` with no window yet prints a short message; `/azt help` lists commands; `/azerothtrail` behaves the same.
- [ ] `/azt dump` after a known lockout: each line reads `<name>: <instanceID> / <difficultyID> - <boss> (killed|alive), ...`. Confirm instance IDs, difficulty IDs and boss names match Data/Lockouts.lua; fix mismatches there. (Instance ID is the 14th return of `GetSavedInstanceInfo`; confirm it is not nil on this client.)
- [ ] `/dump C_MountJournal.GetMountInfoByID(6)` returns 12 values with isCollected 11th (Game.IsOwned relies on it).
- [ ] Note: Darkmoon Faire and Timewalking events can be hidden from the calendar API by the calendar filter CVars `calendarShowDarkmoon` and `calendarShowWeeklyHolidays` (Calendar > Filter). If one of those holidays shows as not active while it is on, check `/dump GetCVar("calendarShowDarkmoon"), GetCVar("calendarShowWeeklyHolidays")` before suspecting the title match.
- [ ] During a holiday (e.g. Hallow's End, Brewfest): the calendar HOLIDAY event title matches Data/Holidays.lua `title` exactly (enUS client). Check with `/run C_Calendar.OpenCalendar() local t=C_DateAndTime.GetCurrentCalendarTime() for i=1,C_Calendar.GetNumDayEvents(0,t.monthDay) do local e=C_Calendar.GetDayEvent(0,t.monthDay,i) print(e.calendarType, e.title) end`.
- [ ] `/dump GetExpansionDisplayInfo(11)` (Midnight, 0-based level) returns a table with `logo`; Game.ExpansionLogo(12) maps Data.Expansions index 12 to level 11.
- [ ] `/dump C_DateAndTime.GetSecondsUntilDailyReset(), C_DateAndTime.GetSecondsUntilWeeklyReset()` both return numbers.
- [ ] `/dump GetLFGDungeonRewards(285)` first return is true after the Headless Horseman daily is done, false before.
- [ ] Saved variables: only `AzerothTrailDB` is written (the `AzerothTrailCharDB` per-character variable was dropped from the .toc; AceDB keeps per-character data under `AzerothTrailDB.char`).

## Task 11: map waypoints, TomTom and Rarity bridges

_Superseded by F5 (no Map buttons on rows; Map.Show removed): use row left-click (Map.SetWaypoint) and Shift+left-click (Map.OpenMap) for these checks._

Map.Show has no slash command; test it with the Map button once the mount list (Task 13) or route (Task 14) exists.

- [ ] Outdoor mount: Map button for Heavenly Onyx Cloud Serpent (473, Sha of Anger, Kun-Lai Summit `m=379`) opens the world map on Kun-Lai Summit with a user waypoint pin near 53.7, 64.7, and the pin is super-tracked (on-screen navigation marker).
- [ ] Instance mount: Map button for Drake of the North Wind (395, The Vortex Pinnacle, `m=325`) opens the map on the parent zone (Uldum) with the pin at the dungeon entrance. If it only opens the map with no pin, check `/dump C_Map.CanSetUserWaypointOnMap(325)` (expected false), `/dump C_EncounterJournal.GetInstanceForGameMap(325)` (expected the Vortex Pinnacle journal instance, 68), `/dump C_Map.GetMapInfo(325).parentMapID` and `/dump C_EncounterJournal.GetDungeonEntrancesForMap(249)` (an entry with that `journalInstanceID` and a `position`).
- [ ] With TomTom installed: both buttons also add a TomTom waypoint (arrow appears, titled with the mount name). Without TomTom: no Lua error.
- [ ] A mount with no coords (e.g. a vendor mount) prints "No map location for <name>" in chat; a map-only mount whose instance has no journal entrance just opens the map there.
- [ ] With Rarity installed and some attempts recorded on an item: `/dump Rarity.db.profile.groups` shows items with `itemId` and `attempts` (the shape RarityBridge reads); the attempts surface wherever the UI shows Rarity counts (Task 13 tooltip).

## Task 12: main window, tabs, minimap button

- [ ] `/reload` with `/console scriptErrors 1`: no Lua errors. `/azt` opens the window (portrait shows the addon icon, title "AzerothTrail", four tabs Journal / Holidays / Misc / Route below the frame); `/azt` again closes it.
- [ ] Esc closes the window; the close button (X) closes it.
- [ ] Tabs without a view show "Coming soon"; clicking a tab highlights it and switches content.
- [ ] Drag the window by its title bar, pick a tab other than Journal, `/reload`, `/azt`: same position and same tab. The window cannot be dragged off screen.
- [ ] Minimap button appears with the addon icon; left-click toggles the window; tooltip shows "AzerothTrail" and "Left-click: open/close" (plus "Route: N steps left" once Task 14 is in).
- [ ] Visual check: tabs sit flush under the frame and are sized to their text (PanelTemplates_TabResize); the inset starts below the portrait; content is not hidden behind the portrait or the close button.

## Task 13: journal home, mount list, tooltip

_Superseded by F5 (no Map buttons on rows): where the checks below say Map button on a list or Route row, left-click the row instead._

- [ ] `/reload` with `/console scriptErrors 1`, `/azt`: the Journal tab shows a 4 x 3 grid of expansion cards in Data.Expansions order (Classic first, Midnight last), each with its logo (or the expansion name when the client has no logo), `owned / total` and a green progress bar. Counts look right for this character's faction (faction-only mounts of the other faction are not counted).
- [ ] Click the Cataclysm card: the list opens with Back and the title "Cataclysm"; rows are grouped under headers in the order Dungeon drops, Raid drops, World drops / rares, Delves, Treasures & caches, Quests, Zone activities, Reputation, Vendors, Other (empty sections have no header). Back returns to the grid.
- [ ] Untick Raid drops in the left panel's Sources list: raid rows and the Raid drops header disappear; tick again and they return. The setting survives `/reload` (`/dump AzerothTrailDB.global.filters`).
- [ ] Collected off (default): owned mounts are hidden. Collected on: owned mounts appear with a light green name, a light translucent green row background and a full-colour icon (no strikethrough; see F10 fix round 1).
- [ ] Type `drake` in the search box: only rows whose name or source group contains "drake" stay; the clear (x) button restores the list.
- [ ] Row: icon (from the mount journal), name, and a grey source line, e.g. Drake of the North Wind reads `Dungeon Drop · Altairus (Vortex Pinnacle (Dungeon))`.
- [ ] Hover a row: tooltip shows the name, the F2b lines (`1 in N chance`, `Lucky if you obtain in K or less`, `Attempts`, `Chance so far` for tracked mounts; see F2b), `Lockout: Saved/Available/Manual/—` (save to a tracked instance and check it flips to Saved after the lockout data arrives), and "Ctrl-click to preview".
- [ ] Ctrl+left-click a row opens the dressing room on the mount; a plain click does nothing.
- [ ] Map button on a row behaves as in the Task 11 checks (pin / entrance / open / "No map location").
- [ ] ScrollBox: the list scrolls with the mouse wheel and the minimal scroll bar; header rows (24 px) and mount rows (40 px) do not overlap. If the list stays empty or errors with a template message, check that `factory("Frame", ...)` / `factory("Button", ...)` (frame types, no template) are accepted by this client's ScrollBox element factory.
- [ ] Filter panel: the checkbox labels render (UICheckButtonTemplate `.Text`/`.text`); the search box shows its "Search" placeholder.
- [ ] While the window is open on a list, killing a tracked boss (UPDATE_INSTANCE_INFO) refreshes the list without resetting the scroll position.

## Task 14: Holidays, Misc and Route tabs

_Superseded by F5 (no Map buttons on rows): where the checks below say Map button on a list or Route row, left-click the row instead._

- [ ] `/reload` with `/console scriptErrors 1`, `/azt`: the Holidays, Misc and Route tabs build without Lua errors (no "Coming soon" left on any tab).
- [ ] Holidays tab: mounts grouped under holiday titles (Hallow's End, Brewfest, Love is in the Air, ...); the header of a holiday that is on today reads `<title>  Active · ends in 6d` in green, every other one a grey `Starts in 9d` / `Starts Feb 9` (see "Holiday header dates"; the calendar loads asynchronously: the badge may appear a moment after the first open).
- [ ] Misc tab: headers Achievements / Professions / Shop / Trading Post / Other; this month's Trading Post mounts (`tradingNow` in Data/Mounts.lua) show `· Trading Post — this month` in green after the source line.
- [ ] Route tab header: character name, `Weekly reset in ...` and `Daily reset in ...` (SecondsToTime text matching the in-game calendar resets), a "Show completed" box (state survives `/reload`: `/dump AzerothTrailDB.char`), and `You have N lockouts left. Saddle up?` where N matches the minimap tooltip's `Route: N steps left`.
- [ ] Horde character: the first step reads "Start in Orgrimmar"; Alliance character: "Start in Stormwind". Faction-only steps of the other faction are absent.
- [ ] Rows are indented by depth; travel rows are grey with no box (WoW ships no italic font, so they are not italic); kill rows show `<boss> → <mount>` lines with notes in grey, a box and a Map button.
- [ ] A saved raid (e.g. a cleared Vault of Archavon watcher) shows its row ticked, greyed (disabled) and tagged green "auto" with Show completed on, and is hidden with it off. Open instance rows have an unticked, greyed box that cannot be clicked (superseded the manual override: only the game ticks tracked rows).
- [ ] Manual row (e.g. a Midnight `manual` mount): click the box, it ticks and the row disappears (Show completed off) or stays ticked (on); `/reload` keeps it ticked (`/dump AzerothTrailDB.char` -> `ticks[<mountID>]` = expiry); after the daily (or weekly, per the spec's `reset`) reset it is unticked again. Clicking a ticked manual row unticks it.
- [ ] Steps whose mounts are all owned are hidden.
- [ ] During an active holiday (Hallow's End / Brewfest / Love is in the Air) its queue step is the first route row; after the holiday boss is done today it is hidden (Show completed off).
- [ ] Boss with an unlock requirement (spec `requires`) shows its text in grey after the boss line.
- [ ] Hover a kill row: mount tooltip of its first mount; Koralon/Emalon/Toravon mounts show `Lockout: Saved` once that boss is killed this week (BossLockouts). Ctrl+click previews the mount.
- [ ] With every step done: `<Name> has reached Oregon. Nothing left to farm until reset.`
- [ ] ScrollBox: rows with several boss lines do not overlap (row height = 28 + 14 per detail line); scroll position is kept when ticking a manual row.

## Task 16: delve, treasure, quest and activity sources

- [ ] Journal list (e.g. The War Within): the left panel's Sources list shows all ten boxes (Dungeon drops, Raid drops, World drops / rares, Delves, Treasures & caches, Quests, Zone activities, Reputation, Vendors, Other), each label fully visible and none clipped by the panel's bottom edge or overlapping the scroll list; each box filters its section and survives `/reload`.
- [ ] A Delves header appears for a known delve mount through the game's source text (e.g. Delver's Dirigible, 2144: generated as a quest mount, listed under Delves when `/dump C_MountJournal.GetMountInfoExtraByID(2144)` 3rd return mentions "Delve").
- [ ] A mount whose source text mentions a cache (and not a delve) is listed under Treasures & caches; note which mount was checked here.

## Task 17: route arrow mode

- [ ] `/reload` with `/console scriptErrors 1`: no Lua errors. Route tab header shows a **List / Arrow** toggle (active mode's button highlighted) on the resets line, right of the timers. Click Arrow: the small "AzerothTrailArrow" frame appears; click List: it hides. `/azt arrow` toggles too and prints `Route mode: Arrow` / `Route mode: List`; `/azt help` lists `/azt arrow`. The mode survives `/reload` (`/dump AzerothTrailDB.char` -> `routeMode`).
- [ ] Arrow frame shows the next step's title (e.g. "Run Throne of the Four Winds"), `<boss> → <mount>`, a grey `via: ...` line with the (up to two innermost) travel steps above it, the distance `N yd` and Map / Skip buttons. It stays up and updates with the main window closed.
- [ ] Arrow texture: `Interface\Minimap\MinimapArrow` loads (not a green square); if it does not, the yellow `UI-MicroStream-Yellow` fallback shows. Note which one in this checklist.
- [ ] Outdoors in the target's zone (or same continent): the arrow points at the target; walk/turn in a full circle and check it keeps pointing at the same spot (confirms world X = north, Y = west, facing counter-clockwise and `SetRotation` counter-clockwise). If it mirrors (points left when the target is right), the rotation sign is wrong. The distance shrinks as you walk towards it and roughly matches the built-in waypoint's distance.
- [ ] On a new step the built-in user waypoint is set and super-tracked (the game's own on-screen pointer and map pin), without opening the world map.
- [ ] Target on another continent: `Target is on another continent`, no arrow. Inside an instance (or wherever position is restricted): `Arrow unavailable here`, no arrow, no Lua error. A step with no coordinates: `No waypoint for this step`.
- [ ] Kill the step's boss (or tick a manual row in the list): after the lockout update the frame advances to the next step and re-targets (waypoint and TomTom move).
- [ ] With TomTom installed: TomTom's arrow follows the current step; after Skip or advance the old TomTom waypoint is removed (only one AzerothTrail waypoint in `/way list`). Switching to List removes it.
- [ ] Skip moves to the next step; `/reload` brings the skipped step back (session only).
- [ ] With every step done or skipped: the Oregon line, no arrow, no buttons.
- [ ] Drag the frame, `/reload`: same position (`/dump AzerothTrailDB.global.arrow`). It cannot be dragged off screen.
- [ ] Map button on the arrow frame opens the world map at the arrow's current target and does not add a second TomTom waypoint (`/way list` still shows one AzerothTrail waypoint).
- [ ] A row with several bosses where the first is already done (e.g. a Vault of Archavon row after killing Archavon): the arrow, its detail line and the waypoint point at the first boss that is not done.

## Final review fixes

_Superseded by F5 (no Map buttons on rows): where the checks below say Map button on a list or Route row, left-click the row instead._

- [ ] Map in combat: click a Map button (Journal list, Route list and the arrow frame) while in combat and again after combat, then click quest and map pins on the world map. Watch chat and the error frame for "Interface action failed because of an AddOn" / "action blocked"; note any that name AzerothTrail.
- [ ] (Superseded: game-tracked rows can no longer be ticked by hand; old hand ticks on them are ignored.) ~~Manual override: on an open instance row (e.g. Eye of Eternity, Malygos), click the box: it ticks, the row counts as done (hidden with Show completed off, `Route: N steps left` drops by one) and `/dump AzerothTrailDB.char` shows `ticks[<mountID>]` with the spec's reset (weekly here). The attempt count (`/dump AzerothTrailDB.global.attempts`) does not move. Click again to untick. After the boss is really killed, the row shows the green "auto" tag and a disabled box (the game wins). A Koralon tick is stored as `ticks["<mountID>@Koralon"]` and does not tick the same mount's own Archavon row.~~
- [ ] `/azt debug`: prints `Debug: on ...`; `/azt help` lists it; the setting survives `/reload` (`/dump AzerothTrailDB.global.debug`). With it on, a caught map / arrow error (e.g. a Map click in combat, or the arrow inside an instance) shows in the error frame / BugSack prefixed `AzerothTrail:`; with it off (default) nothing shows.
- [ ] Attempts per difficulty group: on a mount listing separate difficulties (e.g. 2219 Sureki Skyrazor, Queen Ansurek {14,15,16}), a Heroic-only kill adds +1; a Mythic kill the same week adds +1 more. On an any-of raid (e.g. Al'Akir, {{3,4,5,6}}) a second size the same week does not add another.
- [ ] Quest turn-ins and dungeon-finder updates right after login do not count instance attempts (only `UPDATE_INSTANCE_INFO` reads the saved-instance list).

## UI restyle (flat panel look)

The window now follows Blizzard's current flat panel style. This section supersedes the earlier notes about tabs "below the frame", the left panel's Sources list and the highlighted List / Arrow buttons (Tasks 12, 13, 16, 17). The route arrow frame (UI/Arrow.lua) was not restyled (parked).

- [ ] Fallbacks not triggered: `/reload` with `/console scriptErrors 1`, `/azt` (open the window), open each tab once, open the Journal list's Filter menu, then `/azt debug`. Besides `Debug: on ...` it must print **no** `Template ... missing, using ...` lines (each such line is a template, or a template method such as `DropdownButton:SetupMenu`, this client lacks, with the fallback used instead). With debug already on before opening the window, the same fallbacks show in the error frame / BugSack as `AzerothTrail: template ... missing`. Turn debug off again.
- [ ] Window: flat dark frame (PortraitFrameFlatTemplate) with the addon icon in the portrait, title "AzerothTrail", close button; no stone border or marble background. Esc, drag by the title bar, saved position and saved tab still work (`/reload` keeps both).
- [ ] Content area: a slightly darker flat fill with a faint 1 px edge below the portrait, no classic stone inset border; nothing hidden behind the portrait or close button.
- [ ] Tabs: Journal / Holidays / Misc / Route sit at the top, right of the portrait, standing on the content's top edge (PanelTopTabButtonTemplate); the selected tab is raised/merged into the content, each tab sized to its text; clicking switches content.
- [ ] Filter dropdown (Journal list, e.g. Cataclysm): the list is full width; the top row has the search box and a **Filter** button like the Mount Journal's. The menu shows Collected, a divider, a "Sources" title, the ten source checkboxes, a divider, then Check all / Uncheck all. Ticking a box filters the list immediately and the menu stays open; Check all / Uncheck all tick/untick every source and keep the menu open. The settings survive `/reload` (`/dump AzerothTrailDB.global.filters`).
- [ ] Reset arrow: after changing any filter a small reset (red X / arrow) appears on the Filter button; clicking it restores the defaults (Collected off, all sources on) and hides it. On Holidays / Misc the menu shows Collected only, and the reset there restores Collected only.
- [ ] Search box: typing filters the list; the clear (X) button empties it.
- [ ] Rows: no borders; every other mount row has a faint stripe (restarting under each header); hovering a row highlights it softly; icons are cropped (no baked-in square edge) and, if the client has `UI-HUD-ActionBar-IconFrame-Mask`, rounded. Section headers are a faint band with a thin gold line under them. Owned rows (Collected on) have a light green name and row tint and a full-colour icon; unowned names are gold; source lines a readable light grey (dimmed GameFontHighlightSmall).
- [ ] Journal home cards: dark flat cards with a thin light edge that turns gold on hover, the logo centred, `owned / total` above a slim green progress bar. The list page has a flat strip behind Back and the expansion title.
- [ ] Route tab: flat header strip with a thin line under it; Show completed is the flat minimal checkbox (`MinimalCheckboxTemplate`; if `/azt debug` reported it missing, the Settings checkbox or the classic one is used instead and should still tick, untick and grey out when disabled). List / Arrow is one framed two-segment control (the 1 px frame visible on all four sides and between the segments): the active segment is gold-tinted with gold text, the other dark with grey text; clicking switches mode as before. Route rows are borderless and striped; travel rows grey, kill rows gold; tick boxes are the same minimal checkbox, disabled ones look disabled.
- [ ] Classic fallback (optional, only if a fallback was reported above): the window still opens with the classic stone frame, inset and bottom tabs, and/or the old left checkbox filter panel; every function still works.
- [ ] Combat / taint: open the Filter menu and change filters in and out of combat; no "Interface action failed because of an AddOn" naming AzerothTrail.

## F1: Achievements and Timewalking tabs

Supersedes the four-tab notes above: there are now six tabs.

- [ ] `/reload` with `/console scriptErrors 1`, `/azt`: six top tabs in this order: Journal, Holidays, Achievements, Timewalking, Misc, Route. All fit on one row right of the portrait inside the 800 px window (nothing overlaps the window's right edge); each is sized to its text with a little padding, Misc and Route no narrower than ~70 px, none wider than ~116 px. No label is truncated ("..."); if one is on this client/locale, note which.
- [ ] Achievements tab: only achievement-reward mounts (e.g. Red Proto-Drake and Black Proto-Drake are here; Time-Lost Proto-Drake, a world rare, is not). Headers are expansion names in expansion order (Wrath of the Lich King ... Midnight); a "General" header, if any, comes last. Collected filter (Filter menu, Collected only) and search work.
- [ ] Timewalking tab: one "Timewalking" header with the Timewalking vendor mounts (e.g. Ironbound Wraithcharger, Eclipse Dragonhawk, Yu'lei, Daughter of Jade). Collected filter and search work.
- [ ] Holidays tab: no Timewalking header or Timewalking mounts any more; the other holiday headers and their date badges are unchanged.
- [ ] Misc tab: headers Professions, Shop, Trading Post, Other only (no Achievements header); the "Trading Post — this month" tag is unchanged.
- [ ] Journal home counts are unchanged from before this update (achievement and Timewalking mounts were never counted there).
- [ ] Saved tab: select Achievements, `/reload`, `/azt`: Achievements is still selected; same for Timewalking. A saved tab key from an older version that no longer exists opens Journal.
- [ ] Classic fallback (only if `/azt debug` reported PanelTopTabButtonTemplate missing): six bottom tabs, all clickable.

## F2: Achievement hover and Shift+right-click

The mount -> achievement map is built in the background the first time an achievement mount is hovered or the Achievements tab is opened, and saved per faction and client build (`/dump AzerothTrailDB.global.achievementMap`: one entry each for Alliance, Horde and Neutral, keyed `<toc>:<build>:v2`).

- [ ] Fresh map: `/run AzerothTrailDB.global.achievementMap = {}` then `/reload`, `/azt`, open the Achievements tab. No hitch or freeze (the scan reads at most 200 achievements per frame); within a few seconds `/dump AzerothTrailDB.global.achievementMap.Alliance` (or `.Horde`) shows `build = "120105:<build>:v2"` and `ids` lists this faction's achievement mounts (an achievement ID, or `false` for none found); the other faction's mounts are absent. Note any obviously wrong pairs, especially Crimson Cloud Serpent vs Heavenly Crimson Cloud Serpent (different achievements). A map saved by the first F2 build (top-level `build`/`ids`) is replaced.
- [ ] Hover (Achievements tab), e.g. Red Proto-Drake: after the item tooltip and the farming lines comes `Achievement: Glory of the Hero` (gold; green with "(completed)" when earned), its description (white, wrapped), then up to 8 criteria (completed green, others grey; counted ones show `(n/m)`), then `+N more` when there are more, then `Click to set waypoint`. Check a meta achievement (e.g. Glory of the Raider) and a counter achievement (e.g. Mountacular, `Progress (n/m)` or a named criterion).
- [ ] First hover before the map exists: clear it as above, `/reload`, `/azt`, open the Achievements tab and hover a row at once (keep the mouse on it): the tooltip shows `Achievement: looking up...`, then repaints with the achievement when the scan finishes.
- [ ] Shift+right-click an achievement mount row: the Achievements window opens on that achievement (loads Blizzard_AchievementUI if it was not loaded). Plain right-click and Shift+left-click do nothing; Ctrl+left-click still previews. Route rows behave the same.
- [ ] Combat: clear the map, `/reload`, enter combat (training dummy), open the Achievements tab and hover a row: `looking up...` stays until combat ends, then the scan runs (no achievement reads in combat). Shift+right-click a known achievement mount in combat: chat shows `Can't open achievements in combat` and nothing opens; after combat it opens.
- [ ] Cache: `/reload` again: hovering shows the achievement immediately (no `looking up...`), and the map is not rebuilt (same table). After a client patch the build changes and the map is rebuilt once.
- [ ] Other tabs: hovering a non-achievement mount (Journal, Misc, Holidays, Timewalking) shows no achievement lines and no Shift-right-click hint.
- [ ] Factions: log in a Horde character, hover Pandaren Kite (Horde) on the Achievements tab: it shows the Horde Pandaren Ambassador achievement. Then an Alliance alt: the Alliance kite shows its own (Alliance) achievement after a fresh scan; `/dump AzerothTrailDB.global.achievementMap` keeps both faction entries.
- [ ] Money / progress-bar criteria: hover a mount whose achievement has a progress bar (e.g. a gold or reputation-count achievement): the criterion shows the client's own text (with coin icons for money) instead of raw numbers.

## F3: Kill statistics

51 mounts carry the game's kill statistic IDs from Rarity (`stats = { ... }` in Data/Mounts.lua, e.g. `stats = { 1097 }` on Rivendare's Deathcharger). The game keeps these per character and counts kills from before the addon was installed, so for these mounts the tooltip shows them instead of our attempt counter. Saved as `AzerothTrailDB.global.stats["Name-Realm"][mountID] = kills`.

- [ ] Login: `/reload` (out of combat), then `/dump AzerothTrailDB.global.stats`: an entry for this character (`Name-Realm`) with a number for each statistic mount, 0 for bosses this character never killed. Compare a few against the game's Statistics window (Achievements > Statistics > Dungeons & Raids), e.g. Rivendare's Deathcharger (Baron Rivendare kills, mount 69) and Ashes of Al'ar (Kael'thas kills, mount 183); a mount with several statistics (e.g. Mimiron's Head, 304, `stats = { 2869, 2883 }`) shows their sum (`/run print(GetStatistic(2869), GetStatistic(2883))`).
- [ ] Hover a statistic mount (e.g. Journal > Classic > Rivendare's Deathcharger): `Attempts  N` (two columns) is this character's kill count (only this character has data), with no grey `(this character: N)` line; Rarity's count does not replace it. `Lockout:` and the hints unchanged.
- [ ] Log in an alt, `/reload`, hover the same mount: `Attempts  <sum over both>` with the grey `(this character: <alt's count>)` right under it. A character with 0 kills still shows the split.
- [ ] Hover a mount without statistics that has a drop chance or a lockout (e.g. a dungeon mount Rarity has no statistic for): `Attempts  N` is the larger of our attempt counter and Rarity's count. A reputation or vendor mount without either shows no `Attempts` line.
- [ ] Kill a statistic boss (e.g. Baron Rivendare in Stratholme): after the lockout update (`UPDATE_INSTANCE_INFO`, a few seconds after the kill) the tooltip's count goes up by one without `/reload`.
- [ ] Combat: enter combat (training dummy), `/reload` while still in combat if possible, or kill a statistic boss and stay in combat: no statistics are read until combat ends (`/dump AzerothTrailDB.global.stats` unchanged), then they update. No "Interface action failed" or Lua errors naming AzerothTrail.
- [ ] Note any statistic mount whose count looks wrong (e.g. counts a difficulty that cannot drop the mount, or misses one that can): that is Rarity's statistic list, reported per mount ID.

## F4: Collapsible groups and sub-groups

_Superseded by F5 (no Map buttons on rows): where the checks below say Map button on a list or Route row, left-click the row instead._

List rows are now a tree: section header > sub-header > mounts. Dungeon and raid sections split by instance (the client's name first: the source text's `Zone:`, else the coords map name; the route step's instance only as the last resort, else "Other"; names that differ only in case or a leading "The " are one group, labelled with the client's name), World drops by zone (source text `Zone:`, else coords map name, else "Other"), Reputation by the data's faction group (SimpleArmory's catch-alls "Reputation", "Renown" and "Paragon Reputation" go to Other); every other section stays flat. A section stays flat when "Other" is its only sub-group with a shown mount (e.g. Collected off and every named instance owned). Header counts `(owned/total)` cover every mount the view's other filters (search, sources, faction) select, owned ones included even while Collected is off. Collapsed headers are saved in `AzerothTrailDB.global.collapsed` as `"<view>|<expansion>|<section>[|<sub-group>]" = true`; expanded headers are not stored.

- [ ] `/reload`, `/azt`, Journal > Wrath of the Lich King: "Raid drops (n/m)" with indented, smaller sub-headers (Eye of Eternity, Icecrown Citadel, Obsidian Sanctum, Onyxia, Ulduar, Vault of Archavon ...), each with its own `(owned/total)` and a +/- indicator (campaign quest-log icon; if it shows as text, note it). Sub-groups are alphabetical, "Other" last.
- [ ] World drops (e.g. Mists of Pandaria): sub-headers are zone names (Kun-Lai Summit, Townlong Steppes, ...). Note any mount that lands in "Other" although it has a clear zone, and any instance that appears twice under slightly different names (route name vs the client's zone name).
- [ ] Reputation (e.g. Mists of Pandaria): sub-headers per faction group (Golden Lotus, Order of the Cloud Serpent, Shado-Pan, The Tillers), then "Other" for the catch-all groups; no "Reputation" sub-header under the Reputation section.
- [ ] Instance names: Cataclysm > Dungeon drops shows one "The Vortex Pinnacle" (or the client's spelling) sub-header, not a second "Vortex Pinnacle". Mount rows under a sub-header are indented so their icons line up with the sub-header's +/- indicator; rows in flat sections are not.
- [ ] Header mouse: press on a header, drag off it and release: nothing toggles. Scroll the list with the mouse over a header: the hover band follows the header under the mouse (no band stuck on a header that scrolled away).
- [ ] Counts: with Collected off, a section with owned mounts shows e.g. `(2/5)` and lists only the 3 missing ones; tick Collected: the same `(2/5)`, now 5 rows (owned ones tinted green). A section or sub-group whose mounts are all owned disappears while Collected is off.
- [ ] Left-click a section header: its sub-headers and mounts fold away, the indicator turns to "+", the scroll position stays. Click again: they come back. Same for a sub-header (only its mounts fold). Right-click on a header does nothing. Hover highlights the header band.
- [ ] Persistence: collapse Raid drops under Wrath, `/reload`, `/azt`, Wrath again: still collapsed; Raid drops under Cataclysm is not (keys are per expansion). `/dump AzerothTrailDB.global.collapsed` shows `["journal|Wrath of the Lich King|raid"] = true`.
- [ ] Other tabs: Holidays, Achievements, Timewalking and Misc headers collapse the same way (flat, no sub-headers), saved as `holidays||brewfest`, `achievements||Classic`, etc. The holiday date badges and the Trading Post tag are unchanged.
- [ ] Mount rows: striping restarts under every header and sub-header; Ctrl+left-click previews, Shift+right-click opens the achievement, the Map button works, hover tooltips unchanged.
- [ ] Search and source filters: typing in the search box or unticking a source updates rows and counts; the empty-list message still appears when nothing matches.
- [ ] Combat: collapse and expand headers in combat: no "Interface action failed" or Lua errors naming AzerothTrail.
- [ ] Non-English client (if available): sub-groups still form from route names and map names; `Zone:` parsing falls back to ZONE_COLON. Note a locale where most world mounts land in "Other".

## F2b: Rarity-style tooltip and descriptive row text

The mount tooltip now follows Rarity's layout. After the item's own tooltip (or name + flavor text): `Mount [CATA]` (expansion tag in gold), the kind of source in light blue (`Drops from NPC(s)`, `Found in a treasure / cache`, `Delve reward`, `Quest reward`, `Zone activity reward`, `Reputation reward`, `Sold by a vendor`, `Achievement reward`, `Crafted by a profession`, `In-game shop`, `Trading Post`, `Holiday event`; none for "other"), the client's own source lines (gold label, white value, markup and icons removed), `Dropped by <boss> in <instance>` from the route when no source line names that boss, then for mounts with a drop rate `1 in N chance` and `Lucky if you obtain in K or less` (grey), `Attempts  A` (two columns), `(this character: N)` (grey, kill statistics on several characters only), `Chance so far  P%` (two columns, only with a drop rate), then `Lockout:`, the achievement block and the hints. The old `~1 in N (approx.)`, `Times farmed`, `Kills:` and `Rarity:` lines are gone. A = kill statistics over every character for statistic mounts with a reading, else the larger of our attempt counter and Rarity's count. The grey line under each mount row's name is now a description: `Drop: Ultraxion · Dragon Soul`, `Achievement: <name>`, `Vendor: <name> · <zone>`, `Quest: <name>`, another labelled source line, the route's `<boss> (<instance>)`, a lone `Zone:`, else the old category text.

- [ ] Hover Experiment 12-B (Journal > Cataclysm > Raid drops > Dragon Soul): after the item tooltip `Mount [CATA]` (tag gold), `Drops from NPC(s)` (light blue), `Drop: Ultraxion` / `Zone: Dragon Soul` (labels gold, values white, no stray `|c` codes or icons), no extra `Dropped by` line (the Drop line names Ultraxion), `1 in 100 chance`, `Lucky if you obtain in 69 or less` (grey), `Attempts` with the number right-aligned, `Chance so far` right-aligned with two decimals. Check the arithmetic: with Attempts 30 it reads 26.03%.
- [ ] A statistic mount on two characters (see F3): `Attempts` is the sum over both; the grey `(this character: N)` sits right under it. On a character that is the only one with a reading there is no grey line.
- [ ] A mount without statistics but with Rarity installed and a Rarity count higher than ours: `Attempts` shows Rarity's number; with Rarity disabled it shows ours. A vendor, shop or profession mount without a drop chance, statistics or lockout shows no `Attempts` / `Chance so far` lines at all.
- [ ] A dungeon mount whose source text has no `Drop:` line naming the route boss (e.g. a route mount whose journal source only says `Zone:`): `Dropped by <boss> in <instance>` (white) right after the source lines.
- [ ] Source kinds: hover one mount from each Journal section (dungeon, raid, world, delve, treasure, quest, activity, reputation, vendor) and from Achievements, Misc (profession, shop, trading post) and Holidays: the blue line matches the list above; Misc > Other and Journal > Other show none. A mount without an expansion shows just `Mount`.
- [ ] Long source lines (e.g. a vendor mount with a cost line, or a quest chain) wrap inside the tooltip instead of stretching it across the screen. Note any `Cost:` line that reads oddly without its currency icon (icons are stripped).
- [ ] Route tab: hovering a boss row still shows the full mount tooltip with the same layout.
- [ ] Achievement mounts: the achievement block and both hints still follow `Lockout:`; the `looking up...` repaint still works (see F2).
- [ ] Mount rows (Journal, Wrath > Raid drops): the grey line reads e.g. `Drop: Sartharion · The Obsidian Sanctum` instead of the category; one line, cut off with "..." when too long, never wrapping into the next row. Achievements tab: `Achievement: <name>`. Vendors: `Vendor: <name> · <zone>`. Rows whose mount has no client source text fall back to the route's `<boss> (<instance>)` or the old category text. Holiday rows keep their green Trading Post / tag after the description.
- [ ] Achievements tab before the achievement map exists (clear it as in F2, `/reload`, open the tab): rows without an `Achievement:` source line switch from the category text to `Achievement: <name>` once the scan finishes, without reopening the tab.
- [ ] Performance: scroll quickly through a long list (Journal > Classic, Collected on): no hitch compared with before (descriptions are computed once per refresh).
- [ ] Non-English client (if available): labels and values come out in the client's language; drop / zone / vendor / quest / achievement lines are recognised via the client's own words (BATTLE_PET_SOURCE_n, ZONE_COLON). Note a locale where rows fall back to the category text although the Mount Journal shows a source.

### F2b fix round 1

- [ ] Item data not cached: log in fresh (or after clearing the cache folder), open a list you have not hovered this session and hover a mount whose item tooltip loads late (the first hover briefly shows "Retrieving item information"): once the item tooltip fills in, our block (`Mount [..]`, source lines, odds, `Lockout:`, hints) is still there below it. Move to another row while it loads: the other row's tooltip is not overwritten by the first one.
- [ ] Source text with several labels on one line (e.g. a mount whose Mount Journal source reads `Drop: X Zone: Y` without a line break): the tooltip shows two lines (`Drop: X`, `Zone: Y`) and the row reads `Drop: X · Y`.
- [ ] Achievement scan finishing while the Journal or Holidays tab is open: that tab redraws (no Lua error); on the Achievements tab rows switch to `Achievement: <name>`.
- [ ] Holidays tab while an event is on the calendar (e.g. Darkmoon Faire, first week of the month): its section is at the top with the header name in green and the green `Active · ends in Nd` badge; the other holidays follow in the usual order with normal header text. With two events active at once, both are on top in the usual order. When nothing is active the order is unchanged.

## F5: Click a row to set a waypoint
- [ ] Instance-map mounts: click Rivendare's Deathcharger: the pin goes on the Stratholme entrance in Eastern Plaguelands (dungeon maps take no pins), chat `Waypoint: Stratholme (entrance)`, and no dungeon map opens.
- [ ] Raid / dungeon entrances: click Onyxian Drake, Drake of the South Wind (Throne of the Four Winds) and Invincible's Reins (Icecrown Citadel): each pins the instance entrance (chat `Waypoint: <instance> (entrance)`), not a spot inside the zone and not just an opened map. Note any raid / dungeon mount that still says "Opened map" or "No exact spot".
- [ ] Location icons: a map-pin icon on rows where a click drops a waypoint (exact spot, or a dungeon / raid entrance, e.g. Onyxian Drake -> Dustwallow Marsh entrance); a map icon on rows known only by zone (e.g. Great Sea Ray). Clicking a zone-only row opens that zone's map and chat says "No exact spot for <mount> (anywhere in <zone>): opened the map".

The per-row Map buttons are gone (mount lists and Route). Left-click a mount row: the game's user waypoint goes on the mount's spot (or its dungeon / raid entrance) and is super-tracked, a TomTom waypoint is added when TomTom is installed (the previous AzerothTrail TomTom waypoint is removed first), and chat says `Waypoint: <zone>` or `Waypoint: <instance> (entrance)`; the world map is not opened. Mounts with only a map (no point to pin) open the world map there and print `Opened map: <zone>`; mounts without a location print `No map location for <name>`. Shift+left-click opens the world map at the target without setting a waypoint. Neither opens the world map in combat: chat says `Can't open the map in combat` instead (a pin / entrance waypoint is still set in combat). When the target map takes no user waypoint and TomTom is missing or fails, left-click opens the map there instead and says `Opened map: <place>`. The same chat line repeated within 2 s (a double click) is printed once. Ctrl+left-click previews, Shift+right-click opens the achievement, plain right-click does nothing. Rows with a location show a small pin on the right. Route rows behave the same, aimed at the first boss that is not done. The route arrow (`/azt arrow`) is unchanged and keeps its own Map button.

- [ ] Pin icon: rows show the chat map-pin icon (`Waypoint-MapPin-ChatIcon`, the icon in the client's own map pin links), crisp at 16 px and vertically centred on the row's right end; it does not overlap the mount name (long names are cut off before it). If it shows the old map item icon instead, `/dump C_Texture.GetAtlasInfo("Waypoint-MapPin-ChatIcon")` returned nil: note it. Vendor / shop mounts without coords show no pin.
- [ ] Outdoor mount: left-click Heavenly Onyx Cloud Serpent (MoP > World drops, Sha of Anger): chat `Waypoint: Kun-Lai Summit`, the on-screen navigation marker appears (super-tracked) and the world map stays closed; open the map yourself: the pin is near 53.7, 64.7.
- [ ] Instance mount: left-click Drake of the North Wind (Cataclysm > Dungeon drops > The Vortex Pinnacle): chat `Waypoint: The Vortex Pinnacle (entrance)` and the pin is on the Uldum entrance. A raid mount (e.g. Experiment 12-B, Dragon Soul): `Waypoint: Dragon Soul (entrance)` at the Caverns of Time entrance. Note any instance whose label reads like a floor name instead of the instance.
- [ ] Map-only mount (e.g. Red Qiraji Battle Tank): the world map opens on that map, chat `Opened map: <zone>`, no pin and no TomTom waypoint.
- [ ] No location (e.g. a vendor or shop mount): chat `No map location for <name>`, nothing else happens.
- [ ] Shift+left-click a mount with a location: the world map opens at its zone / entrance map; no new waypoint (the previous one stays) and no chat line.
- [ ] TomTom installed: click three different mounts in a row: `/way list` shows only the last one from AzerothTrail (titled with the mount name). Clicking a map-only or no-location mount leaves the last TomTom waypoint in place. Without TomTom: no Lua error.
- [ ] Route tab: rows have no Map button; kill rows with a location show the pin. Left-click a row whose first boss is done (or ticked) and a later one is not: the waypoint is for the later boss's mount, and hovering shows that mount's tooltip. Clicking the tick box still only ticks. Travel rows do nothing on click.
- [ ] Tooltip hint line reads only `Click to set waypoint` (Shift-click map, Ctrl-click preview and Shift-right-click achievement still work, unlisted).
- [ ] Combat: in combat, left-click an outdoor mount: the waypoint and TomTom waypoint are set and chat says `Waypoint: ...`. Left-click a map-only mount and Shift+left-click any mount: the world map stays closed and chat says `Can't open the map in combat`. No "Interface action failed" / "action blocked" naming AzerothTrail. After combat both open the map again.
- [ ] Double click: double-click a row: one `Waypoint: ...` line in chat, not two. Click it again after a few seconds: the line prints again.
- [ ] Fallback: a mount whose entrance map takes no user waypoint (if you find one, e.g. `/dump C_Map.CanSetUserWaypointOnMap(<parent>)` false) with TomTom disabled: left-click opens the world map there and says `Opened map: <instance> (entrance)`. With TomTom enabled it says `Waypoint: ...` and only TomTom has the point.
- [ ] Pins are cheap: scroll and toggle filters on a long list (Journal > Classic, Collected on): no hitch (the pin only checks the data's coords).
- [ ] Route arrow mode still works as in Task 17 (its own waypoint and TomTom waypoint, its Map button).

## F6: Zone side panel

A slim panel (260 px) docked to the main window's right edge lists "Mounts in <zone> (n)": every mount you can still get whose location is your current zone. A mount is listed when (a) its coordinates (or its holiday's) are on the zone's map or a map inside it (micro maps, cave / dungeon floors; never the continent), (b) its Mount Journal source says `Zone: <this zone>` (case and a leading "The" ignored), or (c) it drops in a dungeon / raid whose entrance is in the zone (C_EncounterJournal.GetDungeonEntrancesForMap on the zone, the map you stand on and the zone's micro / zone sub-maps; matched by the instance name from EJ_GetInstanceInfo against the list's instance sub-group or the route's instance, or by the mount's coordinates map belonging to that journal instance). Inside an instance the panel lists that instance's mounts, titled with the instance name. Owned, other-faction and unobtainable mounts are hidden; ticking Collected (Filter menu) shows owned ones tinted green. Toggle: the map-pin button in the window's title bar (left of the close button, gold band while open), the panel's own close button, or `/azt zone` (opens the window too when it is closed). The open state is saved in `AzerothTrailDB.global.zonePanel.open`. The panel is part of the window: it hides with it (Esc, close button) and comes back with it.

- [ ] Title-bar button: the pin icon sits left of the window's close button, vertically centred in the title bar, and does not overlap the title text; hover shows "Zone panel" with a one-line hint. Dragging the title bar still moves the window (the drag area now stops left of the button). If the icon is missing or a big map item icon shows instead, note it.
- [ ] Docking: click the button: the panel appears flush against the window's right edge (a 2 px gap, same top and bottom), with a dark fill, a faint edge, a gold rule under the title, and its own close button. Move the window: the panel follows. Press Esc: both close; `/azt`: both come back (open state remembered). Note if the panel's edge clashes with the window's border art.
- [ ] Persistence: open the panel, `/reload`, `/azt`: the panel is open; close it with its X, `/reload`, `/azt`: closed. `/dump AzerothTrailDB.global.zonePanel` shows `{ open = false }`.
- [ ] Outdoor zone (e.g. Kun-Lai Summit): "Mounts in Kun-Lai Summit (n)" lists e.g. Heavenly Onyx Cloud Serpent (Sha of Anger) if not owned, with the same icon, name, grey description and pin as the Journal list; left-click sets the waypoint (`Waypoint: Kun-Lai Summit`), Ctrl-click previews, hover shows the full tooltip.
- [ ] Sub-zone: walk into a micro map / cave of the zone (e.g. a city district): the title still names the zone (not the sub-zone) and the list does not change. Standing on a continent-level map (rare): only mounts pinned to that map show; the panel never lists a whole continent.
- [ ] Dungeon entrances (c): in Uldum, The Vortex Pinnacle's Drake of the North Wind is listed (entrance in the zone). In Tanaris, the Caverns of Time raids' mounts (e.g. Experiment 12-B / Dragon Soul, if not owned) are listed. Note any zone whose entrances do not pull in their instance mounts, and any mount listed in a zone it has nothing to do with.
- [ ] Source text (b): a mount whose Mount Journal source reads `Zone: <zone>` but has no coordinates appears when you are in that zone.
- [ ] Inside an instance (e.g. The Vortex Pinnacle on any difficulty): the title becomes "Mounts in The Vortex Pinnacle" and lists its mounts; leave: it switches back to the zone.
- [ ] Zone changes: fly from one zone to the next with the panel open: the title and list update on arrival (ZONE_CHANGED_NEW_AREA); moving between sub-zones of one zone causes no flicker or hitch. Loading screens / hearthstone: the list is right after arrival (PLAYER_ENTERING_WORLD).
- [ ] Filters and data: tick Collected: owned mounts of the zone appear tinted green; untick: they go. Learn a mount from the zone (or `/azt` refresh after a lockout change): it disappears without reopening the panel. Other-faction mounts never show.
- [ ] Empty zone (e.g. a capital with nothing left): the title shows `(0)` and the grey line "Nothing left to collect here".
- [ ] `/azt zone` with the window closed: window and panel open; again: only the panel closes; again: it reopens. `/azt help` lists `/azt zone`.
- [ ] Screen edge: move the window to the right edge of the screen: the panel may run off screen (the window is clamped, the panel is not). Note whether that is a problem in practice.
- [ ] Combat: zone changes and toggling the panel in combat give no "Interface action failed" or Lua errors naming AzerothTrail.
- [ ] Performance: with the panel open, the first open costs a short moment (reads every mount's source once per session); later zone changes and refreshes are instant.

### F6 fix round 1

- [ ] Nested zones: in Valdrakken the title reads "Mounts in Valdrakken" and also lists mounts pinned to Thaldraszus itself (its outer zone), but not those on other Thaldraszus sub-maps; in Thaldraszus, Valdrakken's mounts show (it is inside). Same for Dornogal / Isle of Dorn.
- [ ] On-screen: with the panel open, drag the window against the right screen edge: the window stops so the panel stays fully on screen. Close the panel: the window can go up to the edge again. Open the panel while the window touches the right edge: the window jumps left to make room (note if it does not until you drag it).
- [ ] Sub-zones: scroll the panel down, then walk between sub-zones of the same zone (e.g. districts of a city, the Caverns of Time in Tanaris): the list and its scroll position stay put. Kill something that triggers a lockout refresh: the list rebuilds without jumping to the top.
- [ ] Inside an instance whose map the client does not report (`/dump C_Map.GetBestMapForUnit("player")` prints nil): the title is the instance name (from GetInstanceInfo) and its mounts are listed by name. Delves / scenarios on micro or orphan maps that the journal knows: titled with the journal instance. Note any outdoor micro map (e.g. the Caverns of Time) that gets mistaken for an instance.
- [ ] Bursts: with the panel open, log in / zone into an instance (several lockout events fire at once): no hitch; the panel rebuilds once.


## F7: Daily / weekly checklist
- [ ] Repeatable content is not on the checklist: Rivendare's Deathcharger (Stratholme, no lockout) and the Infinite Timereaver (Timewalking) are absent from Daily; they stay Route steps.

The Route tab header has a second segmented control, `Route | Checklist`, just left of `List | Arrow` on the reset-timer line (saved per character in `AzerothTrailDB.char.routeView`). Checklist lists every lockout this character can still spend on a mount: one row per lockout (F10) from the route (mount, boss) pairs whose boss has a lockout spec (Lockouts / BossLockouts / Rarity quest flag / LFG / manual), plus spec'd mounts the route does not name (rare-spawn quest flags; holiday-boss mounts only while their holiday is on the calendar). Owned, other-faction and unobtainable mounts are left out. Rows sit under two collapsible headers, `Daily · resets in <time>` and `Weekly · resets in <time>`, each with `(done/total)`; not-done rows first, then expansion order, then name. The tick box works exactly like the route's (game kills tick it and tag it `auto`; only manual lockouts the game can't report can be ticked by hand until the next reset; game-tracked rows are display-only; the ticks are the route's own). `Hide done` (in the `Show completed` spot) hides finished rows; the header counts stay.

- [ ] Switch: the two controls sit side by side on the reset line's right end, the same height and style, without overlapping the reset text (`Weekly reset in ...    Daily reset in ...`). Note if the reset text runs under them at your UI scale. Click `Checklist`: the route list is replaced by the checklist, `Show completed` disappears, the flavour line counts the checklist rows left. `/reload` with Checklist selected: it opens on Checklist again; another character starts on Route.
- [ ] Headers: `Daily · resets in 5 Hr 12 Min (n/m)` and `Weekly · resets in 3 Days 4 Hr (n/m)`, with the +/- indicator as on the list tabs; click one: it collapses (remembered across `/reload`, shared with no list tab). The countdowns match the reset timers on the line above.
- [ ] Rows: the same look as the Journal rows (icon, gold name, grey line, pin on the right) with a tick box in front of the icon only on lockouts the game can't report (e.g. Qiraji Battle Tanks); the grey line reads `<boss> · <instance>` (e.g. `Altairus · The Vortex Pinnacle`, `Koralon · Vault of Archavon`), holiday rows `Queue for ...`, other rows the Journal row text. Left-click sets the waypoint, Ctrl-click previews, hover shows the full tooltip.
- [ ] Vault of Archavon (Wrath, Grand Black War Mammoth for your faction): four weekly rows, one per watcher; kill Koralon only: only the Koralon row disappears from Weekly (the header count goes up); the Route tab shows it done (green `auto`).
- [ ] Hand ticks: an open dungeon row (e.g. Drake of the North Wind) has no tick box. Tick a manual row instead (e.g. a Qiraji Battle Tank): it disappears from the checklist and the header count goes up; the Route tab's row is ticked too (untick it there with Show completed on). On a character with no lockouts (`/raidinfo` empty) no game-tracked row is ticked. Game-done rows are not in the checklist; on the Route tab (Show completed on) they are greyed, tagged `auto`, with no tick box, and hovering / clicking the row still works.
- [ ] Holidays: during Brewfest / Hallow's End / Love is in the Air the holiday-boss mounts are listed under Daily (`Queue for ...`) and tick after the daily LFG reward; outside the event they are gone.
- [ ] Rare-spawn mounts (e.g. Legion Argus rares, Battle for Azeroth Arathi / Darkshore rares): listed under Weekly (the Rarity quest flag spec). Note any whose flag is really daily (they would belong under Daily).
- [ ] Everything done: with every row done, both headers remain with full counts and no rows; a character with nothing to farm shows "No lockouts left to farm on this character."
- [ ] Route arrow: with the arrow mode on, switching to Checklist leaves the arrow frame working (it follows the route).

## F8: Attempts per character and in total

The tooltip's attempt block is now two right-aligned double lines, `Attempts (this character)  N` and `Total attempts  T`, replacing the single `Attempts` line and the grey `(this character: N)` line; `Chance so far` is computed from T. N = this character's kill statistics reading (statistic mounts, see F3), else this character's own attempt counter. T = the kill statistics summed over every character when the mount has statistics and any reading, else every character's counter plus the old account-wide counter; then Rarity's count when it is larger. Our counter is now per character: `AzerothTrailDB.global.attemptsByChar["Name-Realm"][mountID]`. The account-wide `AzerothTrailDB.global.attempts` from earlier versions is kept as a legacy bucket: it is counted in `Total attempts` only (never as this character's) and is no longer incremented.

- [ ] Upgrade: on a character with attempts counted before this version, `/dump AzerothTrailDB.global.attempts` still shows the old numbers. Hover one of those mounts: `Attempts (this character)  0` and `Total attempts  <old number>` (or Rarity's count if larger).
- [ ] Counting: kill a tracked non-statistic boss (e.g. Altairus in The Vortex Pinnacle, Drake of the North Wind): a few seconds later (`UPDATE_INSTANCE_INFO`) both lines go up by one without `/reload`; `/dump AzerothTrailDB.global.attemptsByChar` shows `["Name-Realm"] = { [395] = 1 }` and `global.attempts` did not change.
- [ ] Alt: log in another character and hover the same mount: `Attempts (this character)  0`, `Total attempts` unchanged (it includes the first character). Kill it there too: this character 1, total +1.
- [ ] Statistic mount (e.g. Rivendare's Deathcharger) on two characters with readings: `Attempts (this character)` is this character's kill statistic, `Total attempts` the sum over both. On a character that has no reading yet (logged in before this version and not since): this character shows its own counter (usually 0) and the total is the other characters' statistics.
- [ ] Rarity installed with a higher count than ours on a mount: `Total attempts` shows Rarity's number, `Attempts (this character)` stays ours. Disable Rarity: the total drops back to ours.
- [ ] `Chance so far` follows the total: e.g. a 1 in 100 mount with `Total attempts  30` reads `26.03%` whatever the per-character number is.
- [ ] Layout: both labels gold, numbers white and right-aligned; no grey `(this character: N)` line anywhere. Vendor / shop mounts still have no attempt lines.

## F9: Settings page

AzerothTrail has its own page under Options > AddOns, built with the modern Settings API (a vertical-layout category with proxy settings, registered on login). It holds a `Waypoints` dropdown (`In-game map pin`, the default; `TomTom arrow`; `Both`), a `Show minimap button` checkbox and a `Debug messages` checkbox. The waypoint choice is saved in `AzerothTrailDB.global.settings.waypoints` (`"game"`, `"tomtom"` or `"both"`); the checkboxes use the existing `AzerothTrailDB.global.minimap.hide` and `AzerothTrailDB.global.debug` (the same flag as `/azt debug`). `/azt options` opens the page. A mount row's left-click (and the zone panel / checklist rows) follows the waypoint choice: in-game pin only, TomTom only (the in-game pin when TomTom is not loaded or refuses the point), or both as before. The chat line (`Waypoint: ...`) is the same in every mode. The route arrow (`/azt arrow`) keeps its own waypoints and does not read this setting.

- [ ] Page: Esc > Options > AddOns: `AzerothTrail` is listed (alphabetically among the addons); selecting it shows `Waypoints` (dropdown), `Show minimap button` and `Debug messages` (checkboxes), each with a tooltip on hover. No Lua error on login or when opening the page. Note if the page is missing or empty.
- [ ] `/azt options` opens the Settings panel directly on the AzerothTrail page; `/azt help` lists it. In combat: note whether the panel opens (and that no "Interface action failed" names AzerothTrail).
- [ ] Default (fresh install or `/run AzerothTrailDB.global.settings = nil` then `/reload`): `Waypoints` shows `In-game map pin`. Left-click Heavenly Onyx Cloud Serpent: the game's map pin is set and super-tracked, chat `Waypoint: Kun-Lai Summit`, and with TomTom installed `/way list` gains no AzerothTrail waypoint.
- [ ] `TomTom arrow` with TomTom loaded: left-click a mount: only a TomTom waypoint (its arrow points there, `/way list` shows it titled with the mount name), no new in-game map pin; click another mount: the previous AzerothTrail TomTom waypoint is replaced. Chat line unchanged.
- [ ] `TomTom arrow` / `Both` without TomTom (disable it, `/reload`): the dropdown labels read `TomTom arrow (not loaded)` and `Both (TomTom not loaded)`, their tooltips say the in-game map pin is used instead, and a left-click sets the in-game pin. No Lua error.
- [ ] `Both`: left-click sets the in-game pin and the TomTom waypoint, as before F9.
- [ ] Entrance map that takes no in-game pin (see the F5 fallback check): with `In-game map pin` the world map opens there (`Opened map: ...`) even when TomTom is installed; with `TomTom arrow` or `Both` TomTom takes it.
- [ ] Persistence: choose `TomTom arrow`, `/reload`, reopen the page: still `TomTom arrow`; `/dump AzerothTrailDB.global.settings` shows `{ waypoints = "tomtom" }`. Shared by every character (global).
- [ ] `Show minimap button`: untick: the minimap button disappears at once; `/reload`: still hidden; tick: it comes back at its old position. If a minimap-button collector (e.g. MinimapButtonButton) holds the button, note how it reacts.
- [ ] `Debug messages`: tick it, then `/azt debug`: chat says `Debug: off` and the checkbox on the open page unticks (or shows unticked when the page is reopened). `/azt debug` again: the box is ticked.
- [ ] Defaults button on the page (if the client shows one for addon pages): resets to `In-game map pin`, minimap button shown, debug off.

## F10: Checklist: one row per lockout

A kill that can drop several mounts is one checklist row instead of one per mount. Entries that spend the same lockout are merged: route rows under one per-boss spec (`Data.BossLockouts`, e.g. a Vault of Archavon watcher, when several of its rows are for this character), mounts whose instance specs are identical (instance, boss, difficulties, reset: e.g. Malygos' Azure Drake + Blue Drake), and mounts on one Rarity quest flag or one holiday LFG reward. Manual (hand-ticked) specs never merge. The merged row is named after the boss (or the holiday, or for a quest flag the first mount), its grey line reads `<instance> · <n> mounts`, its icon is the first mount still to get, its click (waypoint, map) goes to the boss's instance entrance (preview: the first mount), and hovering shows the boss, the instance, `Can drop:` and the mounts (white, at most 15, then `+N more`). Owned mounts drop out of the list; a merged row with one mount left looks like a normal row; with none left it is gone. The header `(done/total)` counts lockouts. On the shipped data (nothing owned, no holiday on) Weekly has 117 rows (123 without merging); during a holiday Daily lists one row per holiday boss (12 instead of 17 with all three on).

The planner's Chrono-Lord Deios (Dawn of the Infinites) "Quantum Courser" rows for 16 old dungeon mounts are not real (owner-confirmed): the generator leaves out planner rows whose note mentions the Quantum Courser, the Dawn of the Infinites route step is gone and so is its per-boss spec.

- [ ] Route tab and checklist: no Dawn of the Infinites step or Chrono-Lord Deios row; the old dungeon mounts (e.g. Drake of the North Wind, Vitreous Stone Drake) keep their own dungeon rows.

- [ ] Kill Malygos (10 or 25): the one `Malygos` row disappears and Weekly's done count goes up by one (not by two).
- [ ] Eye of Eternity: Azure Drake and Blue Drake are one `Malygos` row (`Eye of Eternity · 2 mounts`); own one of them: the row turns back into a normal row for the other drake.
- [ ] Draenor rares sharing one Rarity quest flag (e.g. Shadowhide Pearltusk, Giant Coldsnout, Garn Steelmaw, Smoky Direwolf): one Weekly row named after the first of them with `· 4 mounts`. Note whether they really share one weekly flag in game (if not, their quest IDs in the data need fixing).
- [ ] Holidays: during Brewfest the Ram, Kodo and Bomber are one Daily `Brewfest` row (`Queue for Coren Direbrew (Brewfest) · 3 mounts`); Hallow's End and Love is in the Air likewise.
- [ ] Single-mount rows (e.g. Altairus, Koralon) look and hover exactly as before (mount name, `<boss> · <instance>`, the full mount tooltip).

### F10 fix round 1

- The 16 planner rows "Chrono-Lord Deios — Mythic only - from Quantum Courser item" are bogus (owner-confirmed) and gone (see above).
- A checklist row's click (waypoint, Shift-click map) goes to its boss's instance when a per-boss spec governs that boss (e.g. a Vault of Archavon watcher row), not to the first mount's own source; route rows pass the boss they target too. The chat line names that instance (`Waypoint: <instance> (entrance)`).
- A spec may carry `exp` (a Data.Expansions name) for the checklist's sort order; the Vault of Archavon watchers sort under Wrath of the Lich King.
- Owned (collected) rows in every mount list (Journal, Holidays, Achievements, Timewalking, Misc, zone panel), shown with the Collected filter on: a light translucent green row background, a light green name, the icon in full colour, no strikethrough.

- [ ] Checklist: click the Koralon (or Emalon / Toravon) row: the waypoint is the Vault of Archavon entrance (Wintergrasp) and chat names Vault of Archavon.
- [ ] Route tab: click a kill row: the waypoint goes to the boss's instance as before.
- [ ] Collected on (Journal): owned rows have a faint green tint (still readable with the every-other-row stripe and the hover highlight), a light green name and a coloured icon; scroll quickly up and down: no tint left on a missing mount's row. Note whether the green is too strong or too faint at your UI scale.
- [ ] Zone panel with Collected on: owned mounts of the zone are tinted green the same way.

## F13: Journal home (redesign)

The Journal tab's front page is a slim summary strip (`Mount Collection` left; `<owned> / <total> collected  ·  <pct>%` right, counting every mount on the Journal, Holidays, Achievements, Timewalking and Misc tabs for your faction, unobtainable ones only when owned; a full-width 4 px gold bar under it; below the bar one chip per tab, `<Tab>  owned / total`, that lights on hover and opens that tab on click) above a 4 x 3 grid of flat tiles (180 x 128, 12 px gaps): dark flat fill with a faint 1 px edge, the expansion logo centred in the upper part (the name only when the client has no logo), a 3 px bar across the bottom with `owned / total` left and `pct%` right. A completed expansion (owned == total > 0) gets a green bar and the Great Vault's small green check (`activities-icon-checkmark`, else the scenario check texture) in its top-right corner. Percentages round down (99% until the last mount). The expansion list page is unchanged.

- [ ] Journal tab: the strip and all 12 tiles fit the window with even margins (nothing clipped at the right or bottom, no overlap with the top tabs).
- [ ] The summary numbers equal the sum of the tiles' `owned / total` (add a few up); the gold bar's fill matches the percent.
- [ ] Logos are centred, not stretched, and do not touch the bar; note any expansion whose logo looks too small or too large in its tile.
- [ ] Hover a tile: the fill brightens slightly and the edge turns gold; leave: back to the faint edge. Click: that expansion's list opens; Back returns to the front page with fresh numbers.
- [ ] An expansion you have completed shows a green bar and the check top-right; note whether the check atlas rendered (green tick) or the fallback texture. A tile with nothing to collect reads `0 / 0`, `0%`, no check.
- [ ] Learn a mount, then return to the Journal home: its tile, the summary text and bar update.

## F11: Show unobtainable mounts

Options > AddOns > AzerothTrail has a `Show unobtainable mounts` checkbox (off by default, saved account-wide). On: every unobtainable mount you do not own (removed rewards, old store and promotion mounts, retired holiday or achievement mounts) is listed on the Misc tab under its own `Unobtainable` header, after Other, and on no other tab. Owned unobtainable mounts stay where they were (shown with the Collected filter). The Journal home and expansion counts never include unobtainable mounts. The data has 299 unobtainable mounts (274 for both factions, 13 Alliance-only, 12 Horde-only), so at most 287 / 286 rows, minus the ones you own or the client does not know.

- [ ] Options > AddOns > AzerothTrail: the checkbox sits under the Waypoints dropdown, unticked on a fresh install; its tooltip mentions the Misc tab.
- [ ] With the AzerothTrail window open on Misc, tick it: an `Unobtainable` header appears at the bottom at once (no reopen needed), counts `(0/N)`; untick: it disappears.
- [ ] On: the Journal expansion lists, Holidays, Achievements and Timewalking show no unobtainable mount you do not own (e.g. a retired Gladiator or old store mount appears only under Misc > Unobtainable).
- [ ] Collected on: an owned unobtainable mount shows in its usual tab and section (green row), not under Unobtainable.
- [ ] Journal home tile and summary numbers are the same with the option on and off.
- [ ] Hover and click an Unobtainable row: tooltip and waypoint (when it has a location) work as on other rows; collapse the header and `/reload`: it stays collapsed.
- [ ] `/reload`: the checkbox keeps its state.

## F12: Checklist by expansion, boss-aware hover, data fixes

Route tab > Checklist: Daily and Weekly are each split into collapsible expansion sub-headers (Data.Expansions order; an expansion the data does not know after them; mounts without an expansion last as `Other`). Each sub-header reads `<expansion>  (done/total)`; the Daily / Weekly headers still count the whole reset group. A sub-header whose lockouts are all done is left out (its entries disappear as before); a group whose only expansion would be `Other` stays flat. Collapse state is saved under `checklist|daily|<expansion>` / `checklist|weekly|<expansion>`.

- [ ] Checklist: under Daily and Weekly, expansion sub-headers in expansion order (Classic first, Midnight last), smaller and indented like the Journal's sub-headers; rows under them are indented (tick box and icon) by the same step.
- [ ] Sub-header counts: e.g. Weekly > Wrath of the Lich King `(1/7)` after one Wrath kill; the Weekly header's own count is unchanged from before F12 (the sum over its sub-headers).
- [ ] Collapse one sub-header (e.g. Weekly > Cataclysm), `/reload`: it stays collapsed, the others stay open; collapsing Weekly still hides everything under it.
- [ ] Finish every lockout of one expansion: its sub-header disappears; the reset header still counts those lockouts as done.

Boss-aware hover and pins (F10 carry-over): a checklist or route row's tooltip `Lockout:` line reports the row's own boss (its per-boss spec when Data.BossLockouts has one), and a row whose boss has a per-boss instance spec shows the map pin (its click goes to that instance's entrance) even when the mount itself has no spot.

- [ ] Checklist > Weekly > Wrath of the Lich King: kill Koralon only (10 or 25), then hover the Koralon row and the Archavon row: Koralon reads `Lockout: Saved` only once both sizes are done, Archavon reads `Lockout: Available`; Emalon / Toravon rows each show their own state.
- [ ] Route tab: hover the Vault of Archavon kill row: the `Lockout:` line follows the boss the row targets (the first one not done).
- [ ] The Koralon / Emalon / Toravon rows show the map pin (not the zone icon); click: waypoint at the Vault of Archavon entrance.

Boss names (data verifier, build 12.1.5.70448): a lockout spec's boss now matches the saved-instance boss when either name contains the other, ignoring case (was: one a prefix of the other). The game's DungeonEncounter table names Sharkbait's boss `Lord Harlan Sweete` (spec: `Harlan Sweete`) and G.M.O.D.'s `Mekkatorque` (spec: `High Tinker Mekkatorque`); both now match either way. The verifier warns when a spec's name would also match another boss of the same instance (none today).

- [ ] Freehold Mythic: kill Harlan Sweete; `/azt dump` lists the boss name the client uses; the Sharkbait row is ticked `auto` (Checklist) and its tooltip reads `Lockout: Saved`.
- [ ] Battle of Dazar'alor (Normal or higher): kill Mekkatorque; `/azt dump` shows its name; G.M.O.D. reads `Lockout: Saved`.
- [ ] King's Rest Mythic: kill Dazar; `/azt dump`: note the exact boss name (the journal calls it `Dazar, The First King`, its linked DungeonEncounter 2143 `King Dazar`; the spec now says `Dazar`, contained in both); the Tomb Stalker row should tick `auto`. If it does not, report the dumped name.

Rare-spawn resets: a mount whose only lockout is its Rarity quest flag now resets daily when SimpleArmory files it under `Rare Spawn` (or `<covenant> Rare Spawn`) or under a BfA zone-rare group starting `Warfront: ` (Arathi, Darkshore) or `Assault: ` (Uldum, Vale of Eternal Blossoms); weekly otherwise (`World Boss`, Garrison, ...). Explicit Data/Lockouts.lua entries still win. That moves 45 mounts from Weekly to Daily (all obtainable spec'd mounts: 17 daily / 124 weekly before F12, 63 / 78 after, Ahune included). The game's tables do not say how a hidden tracking quest resets, so this is the owner's rule, to be confirmed:

- [ ] Checklist > Daily lists the rare-spawn mounts (e.g. Legion > Vile Fiend, Shadowlands > Gorespine, The War Within > Darkfuse Spy-Eye), Weekly the world bosses (e.g. Mists of Pandaria > Son of Galleon, Warlords of Draenor > Solar Spirehawk).
- [ ] Kill one daily rare (e.g. a Mechagon or Korthia rare with a mount): its row ticks `auto`; after the daily reset it is back. If it stays ticked until the weekly reset instead, report the mount (it needs a weekly entry in Data/Lockouts.lua).
- [ ] Tanaan Jungle (Tundra Icehoof, Armored Razorback, Warsong Direfang share quest 39287): one Daily row; confirm it returns after the daily reset.
- [ ] BfA zone rares under Daily: Battle for Azeroth > Warfront: Arathi (e.g. Skullripper, Witherbark Direwing), Warfront: Darkshore (e.g. Umber Nightsaber), Assault: Uldum (e.g. Waste Marauder) and Assault: Vale of Eternal Blossoms (e.g. Xinlao). Kill one: it ticks `auto` and is back after the daily reset (if it waits for the weekly reset, report the mount).

Ahune (Midsummer Fire Festival): the game's LfgDungeons table has ID 286 `The Frost Lord Ahune` in the holiday-boss group (Group_ID 11, with 285 / 287 / 288), so Sun Festival's Painted Roc (3036, Mount.db2 `Drop: Ahune; Holiday: Midsummer`) gets a daily `lfg = 286` spec and Midsummer a route step `Queue for Ahune (Midsummer Fire Festival)`. The step has no map pin (the location is not in the verified tables). The verifier now also checks every `lfg` spec and holiday `lfg` against LfgDungeons.

- [ ] During Midsummer: Checklist > Daily lists Sun Festival's Painted Roc (description `Queue for Ahune (Midsummer Fire Festival)`); the Route tab shows the queue step.
- [ ] Queue for and kill Ahune: the row ticks `auto` (the daily LFG reward is marked done) and comes back after the daily reset. If it does not tick, report it (the LFG ID may not be the one the reward check uses).
- [ ] Holidays tab > Midsummer Fire Festival: the Painted Roc row shows `Lockout: Available` / `Saved` like the Brewfest mounts.

Data fixes (verifier, build 12.1.5.70448):

- [ ] Checklist > Daily > Wrath of the Lich King: Bronze Drake (Culling of Stratholme) has a tick box (manual: the game reports no `Infinite Corruptor` kill); tick it after a timed heroic run: the row disappears and Daily's done count goes up; it is back after the daily reset.
- [ ] Hover Swift Armored Vorquin and Majestic Armored Vorquin (Misc > Other, Dracthyr): each tooltip shows its own reins item (Swift: item 198810, Majestic: 198811); the item's name matches the mount.
- [ ] Route tab: no `Run The Stonevault (Dungeon)` step and no `Flightpath to The Ringing Deeps` travel step; the Checklist has no Stonevault Mechsuit row (it is a quest reward: `Repurposed, Restored`).

## F15: Misc categories and per-tab filters

Misc is split by SimpleArmory category (regenerated from the pinned commit; only misc `section` values changed in Data/Mounts.lua, plus the group of the four season mounts below). Headers, in order, with the data's mount counts (obtainable ones in brackets; the rest show only with `Show unobtainable mounts`, under Unobtainable): Professions 34 (34), In-game Shop 66 (57), Trading Post 131 (86), PvP 127 (83), Racial 91 (91), Mythic+ 25 (24), Promotions 72 (42), Class 19 (19), Black Market 7 (7), Collection rewards 17 (17), Other 60 (5), then Unobtainable: the 84 past limited-time offers (Limited Time / Past Limited Time other than Trading Post: seasons, Remix, Plunderstorm...; all unobtainable, so only owned ones show, with Collected on), plus with the option every not-owned unobtainable mount. Faction and client knowledge lower the numbers you see.

- [ ] Misc tab (Collected on): the headers above in that order; e.g. Racial lists the Brown Horse / Black Stallion (Alliance) or wolves / kodos (Horde), Class the Paladin chargers / Warlock dreadsteeds / Death Knight and Demon Hunter mounts, Black Market the BMAH mounts, Collection rewards the mount-count achievement mounts (e.g. Albino Drake), Mythic+ the Timelost Saddle mounts, Other only Feats of Strength / Old School Ride / Make-A-Wish / Guild Vendor / Unknown mounts.
- [ ] Season mounts also sold for PvP / Mythic+ currency are listed there, not under Unobtainable: Vicious Lightbloom Boar under PvP (group Vicious Saddle), Breath of Blight / Breath of Ruin under Mythic+ (group Timelost Saddle).
- [ ] Hover a Misc row: the kind line under the name reads `PvP reward`, `Racial mount`, `Mythic+ reward`, `Promotion`, `Class mount`, `Black Market Auction House`, or `Collection reward` by category. An unobtainable mount keeps its own kind line (e.g. `Drops from NPC(s)`, `PvP reward`) with a grey `No longer obtainable` line right under it; a past limited-time offer under Unobtainable shows only the grey line.
- [ ] Misc > Filter: `Collected`, a `Categories` title, `Show profession mounts` ... `Show other mounts`, `Show unobtainable mounts` (twelve; no limited-time entry), Check all / Uncheck all. Untick `Show in-game shop mounts`: the In-game Shop header disappears at once and the reset arrow appears next to the button; tick it again: back, arrow gone.
- [ ] The Misc menu lists `Show unobtainable mounts` whether the Options checkbox is on or off; unticking it hides the Unobtainable header (owned limited-time mounts, and with the option every not-owned unobtainable mount); the option itself stays as it was.
- [ ] Journal expansion list > Filter: `Sources` with `Show dungeon drops`, `Show raid drops`, ... (ten). Untick `Show raid drops`: Raid drops disappear on the Journal list only (Misc / Holidays unchanged).
- [ ] Holidays > Filter: one `Show <holiday>` per holiday (Hallow's End ... Anniversary, `Show other mounts`); unticking Brewfest hides that header only on Holidays.
- [ ] Achievements > Filter: `Expansions` with `Show Classic achievements` ... `Show Midnight achievements`, `Show General achievements`; unticking one hides that expansion's header.
- [ ] Timewalking > Filter: `Collected` only.
- [ ] Reset arrow per tab: hide a Misc category, switch to Holidays: no reset arrow there; click the arrow on Misc: Misc categories back and Collected off, the Holidays choices untouched.
- [ ] Upgrade from an earlier version with a Journal source unticked (e.g. raid): after login it is still unticked on the Journal (`/dump AzerothTrailDB.global.filters` shows `journal = { raid = false }` and no flat `raid` key); Collected kept.
- [ ] `/reload`: every tab keeps its filter choices.

## F14: Checklist levels and filter

Route tab > Checklist: under each expansion sub-header the lockouts are split again into collapsible category headers, in this order: Raids, Dungeons, World bosses, Rares, Holidays, Other, each with its own done/total (smaller, one step further in than the expansion; rows under them indented to match). An instance lockout is a raid when any of its difficulties is a raid one (legacy 10/25, 40-player, Normal/Heroic/Mythic/LFR raid), else a dungeon; a hand-ticked or quest-flag lockout follows the mount's journal section (raid / dungeon) or its SimpleArmory group (`World Boss`; rare spawns: `Rare Spawn`, `<covenant> Rare Spawn`, `Warfront: ...`, `Assault: ...`); LFG holiday bosses and holiday mounts are Holidays; the rest Other. A lone category keeps its header (e.g. Weekly > Classic > Raids) unless it is Other. Collapse keys: `checklist|<reset>|<expansion>|<category>`.

Real data (every obtainable spec'd mount, nothing owned, all holidays on; per character the numbers drop with what you own): Daily 55 = Dungeons 9, Rares 42, Holidays 4; Weekly 76 = Raids 48, Dungeons 13, World bosses 6, Other 9 (vendor / quest / garrison flags such as Shadowhide Pearltusk, Loyal Gorger, Hand of Bahmethra).

- [ ] Checklist > Weekly > Shadowlands: `Raids` (Sanctum Gloomcharger, Vengeance, Zereth Overseer), `Dungeons` (Marrowfang, Cartel Master's Gearglider), `Other`; Battle for Azeroth > Dungeons lists Sharkbait, Underrot Crawg, Tomb Stalker, Aerial Unit R-21/X, Mechagon Peacekeeper; Midnight > Dungeons lists The Writhing Brood, Lucent Hawkstrider and Spectral Hawkstrider (see the fix round below), Midnight > Raids Ashes of Belo'ren, Primeval Skyfriend and Luminous Sporeglider.
- [ ] Mists of Pandaria under Weekly shows `Raids` and `World bosses` (Son of Galleon, the Cloud Serpents, Cobalt Primordial Direhorn); Daily > Battle for Azeroth > `Rares` holds the Warfront / Assault rares.
- [ ] Weekly > Wrath of the Lich King > Raids holds the four Grand Black War Mammoth rows (Archavon, Koralon, Emalon, Toravon in the grey line); Daily > Wrath > Dungeons the Blue Proto-Drake and the Bronze Drake (tick box).
- [ ] During a holiday: Daily > Other > `Holidays` (the queue bosses, which have no expansion: last, under the `Other` expansion sub-header).
- [ ] Collapse Weekly > Shadowlands > Raids, `/reload`: still collapsed; Dungeons under it stays open. Collapsing Weekly > Shadowlands hides its categories too.
- [ ] Category header looks: the same small font and faint band as the expansion sub-headers, the +/- one step further right; the rows under it line up with that step (tick box and icon).

Filter: on the Checklist the Route header shows a `Filter` button at the top right (where `Show completed` sits on the route; hidden on the route). Its menu: `Show raids`, `Show dungeons`, `Show world bosses`, `Show rares`, `Show holidays`, `Show other`, Check all / Uncheck all. Saved per character (`ns.db.char.checklistFilters`, only unticked ones stored).

- [ ] Untick `Show rares`: Daily drops every Rares header at once, Daily's done/total and the flavour line (`You have N lockouts left`) drop by the same number; the reset arrow appears next to the button. Tick it again: back, arrow gone.
- [ ] Untick everything but `Show dungeons`: only Dungeons headers remain (e.g. Weekly > Shadowlands > Dungeons: Marrowfang, Cartel Master's Gearglider). Click the reset arrow: every category back.
- [ ] Log in on another character: its filters are its own (all shown by default). `/reload`: the choices stay.
- [ ] Switch to Route: no Filter button; back to Checklist: the button and its choices are back.

### F14 fix round 1: Midnight Mythic mounts

Game data (DB2 12.1.5.70448) shows SimpleArmory's `unavailable` flag on two Midnight dungeon steps is wrong. JournalEncounterItem lists Lucent Hawkstrider (item 260231) under Degentrius (Magisters' Terrace) and Spectral Hawkstrider (item 262914) under The Restless Heart (Windrunner Spire). The generator now clears the flag for exactly those two rows (tools/build_data.py `_AVAILABLE_BOSS_ROWS`). The verifier gains a check: a route row marked unavailable whose mount item is in Encounter Journal loot warns `marked unavailable but in Encounter Journal loot` (none now; the old route had these two).

The Midnight hand-tick specs are now instance specs (instance = JournalInstance MapID, boss = DungeonEncounter name): Lucent Hawkstrider 2811 / Degentrius, Spectral Hawkstrider 2805 / Restless Heart, The Writhing Brood 2993 / Zul'jan (dungeons, Mythic 23); Primeval Skyfriend 3004 / Ula'tek and Ashes of Belo'ren 2913 / Midnight Falls (raids, Mythic 16). Luminous Sporeglider (Sporefall, kills on 4 separate weeks) stays a hand tick. The difficulties are taken from the mount source text and are not confirmed in game.

- [ ] Route tab: `Run Magister's Terrace (Midnight Dungeon)` and `Run Windrunner Spire (Dungeon)` steps are listed. Checklist > Weekly > Midnight > Dungeons lists Lucent Hawkstrider, Spectral Hawkstrider and The Writhing Brood, with no tick box on any of them (the game tracks them now).
- [ ] Kill Degentrius on Mythic: `/azt dump` lists Magisters' Terrace with instance ID 2811 and the boss `Degentrius`. The Lucent Hawkstrider row ticks `auto`. If it does not, report the dumped instance ID, difficulty and boss name. Do the same for Windrunner Spire (2805, `Restless Heart`) and Altar of Fangs (2993, `Zul'jan`). If The Writhing Brood also drops on Heroic, report that too: its source text names no difficulty.
- [ ] Mythic March on Quel'Danas (Midnight Falls) and Mythic The Venomous Abyss (Ula'tek): Ashes of Belo'ren and Primeval Skyfriend tick `auto` (Checklist > Weekly > Midnight > Raids). A Heroic kill must not tick them.
- [ ] Midnight Mythic+ runs: the Lucent / Spectral Hawkstriders also come from the Challenger's Cache (Mythic+). A Mythic+ run creates no lockout, so their rows only tick `auto` after a Mythic 0 kill; note whether that matches how you farm them.
- [ ] Luminous Sporeglider keeps its tick box.

## F16: Route planner retired

The route planner is retired for now. The `Route` tab is now the `Checklist` tab (sixth tab, label `Checklist`): it shows only the daily / weekly checklist under a flat header with the character name, the weekly and daily reset timers, the flavour line (`You have N lockouts left. Saddle up?` / `<name> has reached Oregon. ...`, counting the categories the Filter shows) and the `Filter` button top right. The route list, the `Route | Checklist` switch, `Show completed` and the `List | Arrow` control are gone. The route arrow (UI/Arrow.lua) is parked: `AzerothTrailDB.char.routeMode` is forced to `list` on every load and `/azt arrow` is no longer a command. This section supersedes every earlier item that mentions the Route tab, its route rows, Show completed, List / Arrow, the arrow frame or `/azt arrow` (Tasks 14, 16, 17 and the later route-row checks); the Checklist checks keep applying with "Route tab > Checklist" read as "Checklist tab".

- [ ] `/reload` with `/console scriptErrors 1`, `/azt`: six tabs, the last one `Checklist`; no Lua errors; no "Coming soon" on it.
- [ ] A character that had the Route tab selected before this update opens on `Checklist` (`/dump AzerothTrailDB.global.window.tab` -> `"checklist"`).
- [ ] A character that was in arrow mode: no `AzerothTrailArrow` frame after login; `/dump AzerothTrailDB.char.routeMode` -> `"list"`; `routeView` and `showCompleted` are gone from `AzerothTrailDB.char`.
- [ ] Checklist header: name, `Weekly reset in ...    Daily reset in ...`, the flavour line, `Filter` top right (the name line does not run under it). No other buttons.
- [ ] `/azt arrow` prints the command list (no `/azt arrow` in it); `/azt help` does not list it.
- [ ] Minimap button tooltip: `Checklist: N lockouts left`, N equal to the flavour line's number (with the same Filter choices).
- [ ] Tick boxes, collapse, Filter, row clicks and hovers on the checklist work as before (F10-F14 checks).

## F17: Live status for event rares

On the Checklist, rows of the N'Zoth assault rares (`Assault: Uldum`: Drake of the Four Winds, Waste Marauder, Malevolent Drone; `Assault: Vale of Eternal Blossoms`: Clutch of Ha-Li, Ren's Stalwart Hound, Xinlao) and the warfront rares (`Warfront: Arathi`, `Warfront: Darkshore`) add a light-blue line after their grey description. Assaults: the zone's current assault from the area POIs the game reports for Uldum (maps 1527 / 249) and the Vale (1530 / 390), AreaPOI IDs 6486 N'Zoth / 6487 Amathet / 6488 Aqir and 6489 N'Zoth / 6490 Mogu / 6491 Mantid (AreaPOI.db2 12.1.5.70448), with `GetAreaPOISecondsLeft` as the time left: `Uldum: Aqir assault — 2 Days 4 Hr left`. Warfronts: the contributions the Arathi Highlands (14) / Darkshore (62) map shows this character (Contribution IDs 11 / 116 `Battle for Stromgarde`, 117 / 118 `Battle for Darkshore`), with the game's own state name (`GetContributionAppearance(...).stateName`) plus the percentage while contributing or the time left when the game's appearance uses it: `Arathi warfront: <state> (63%)`. Nothing claims which rare is up: the client's data does not tie a rare to an assault or a warfront phase. Unknown / API missing / zone data not loaded: `Status unknown — click to load`. A category header (e.g. Daily > Battle for Azeroth > Rares) shows the line only when every rare left under it has the same one. The lines are re-read at most once a minute, and within 2 s after `AREA_POIS_UPDATED` / `CONTRIBUTION_COLLECTOR_UPDATE`.

- [ ] `/reload`, Checklist > Daily > Battle for Azeroth > Rares: each Uldum / Vale rare row ends with a light-blue line. Open the world map on Uldum (the N'Zoth version) and compare: the assault named in the row matches the map's assault icon, and the time left matches the icon's tooltip (to the minute; SecondsToTime text).
- [ ] Same for the Vale of Eternal Blossoms.
- [ ] A character that never unlocked the 8.3 assaults (or before opening the map): the rows read `Status unknown — click to load`; left-click the row (it opens that zone's map; in combat it only says so), then close the map: within a few seconds (or a minute at most) the line updates. Report if it never does.
- [ ] Arathi Highlands / Darkshore warfront rares: the line names the state the warfront's map pin tooltip shows (hover the contribution table pin on the zone map). Note what the state names read for each phase (e.g. Contributing / Active / Under attack / Destroyed) and whether a percentage or time left appears; report the exact text so the faction / control wording can be refined.
- [ ] Note if the map lists both factions' contributions (two parts joined by ` / `) and which is yours.
- [ ] Collect (or hide with Filter / own) every BfA rare except the three Uldum ones: the Rares header reads `Rares  (x/y)  Uldum: ... assault ...`.
- [ ] No Lua errors with `/console scriptErrors 1` while flying through Uldum / the Vale (AREA_POIS_UPDATED fires often); the window stays responsive (the checklist redraws at most every 2 s for these events).

## Data audit: rare spawns with no lockout, completeness, sources

Game data (Mount.db2 SourceText, build 12.1.5.70448; `tools/verify_data.py` checks 5-7) drove this round. Every Mount.db2 mount a player can collect is in `Data/Mounts.lua` (the 58 left out carry Mount.Flags ServerOnly, ExcludeFromJournalIfNotLearned or ShowInSpellbook: legacy duplicates, test rows, Divine Steed, Soar). Rare-spawn mounts with no kill flag (37, every expansion: e.g. Nok-Karosh, Gorok, Poundfist, Pathrunner, Silthide, Luk'hok, Nakk the Thunderer, Time-Lost Proto-Drake, Aeonaxx) are `camp` specs: no reset, listed on the Checklist under a third group `Rare spawns (no lockout)` by expansion and zone (the source text's Zone / Location) until the mount is owned. Each row's box records when you last checked the spawn (`AzerothTrailDB.char.campChecked`), shown as `Last checked 3 hr ago`; right-click clears it. The three Tanaan Jungle mounts (Tundra Icehoof, Armored Razorback, Warsong Direfang) are now one daily hand-tick row each (four rares, each its own kill; Deathtalon's quest alone used to tick all three). Horrid Dredwing, Armored Bonehoof Tauralus and Wild Glimmerfur Prowler (covenant rares) now reset daily under Rares. Stonevault Mechsuit moved to Quests.

- [ ] `/reload`, Checklist: after Daily and Weekly a header `Rare spawns (no lockout)  (N left)` with no reset timer. Under it expansion headers, under those zone headers (Warlords of Draenor > Frostfire Ridge: Garn Nighthowl, Great Greytusk; Gorgrond: Sunhide Gronnling; Nagrand: Bloodhoof Bull, Mottled Meadowstomper; Shadowmoon Valley; Talador), each with `(N left)`.
- [ ] Click a rare-spawn row's box: it shows checked and the grey line ends `Last checked 1 min ago`; leave the tab open a few minutes: the text ages (2 min, 3 min...) without a click. Click again: back to `1 min`. Right-click the box: unchecked, no text. `/reload`: the time stays; another character has its own.
- [ ] The row never disappears when ticked; it goes only once the mount is learned (or with `Show rare spawns (no lockout)` off in Filter, which also hides the group's header). Collapse the group, an expansion and a zone: the keys stay collapsed after `/reload`.
- [ ] The flavour line and the minimap tooltip (`N lockouts left`) do not count rare-spawn rows.
- [ ] Tanaan Jungle: Daily > Warlords of Draenor > Rares lists Tundra Icehoof, Armored Razorback and Warsong Direfang as three rows with tick boxes; killing Deathtalon does not tick them.
- [ ] Shadowlands: Horrid Dredwing (Harika the Horrid), Armored Bonehoof Tauralus (Sabriel the Bonecleaver), Wild Glimmerfur Prowler (Valfir the Unrelenting) are under Daily > Shadowlands > Rares; after a kill the row ticks `auto` and is back the next day. Report if a kill does not tick (Rarity quest IDs 59612 / 58784 / 61632).
- [ ] Hover a rare-spawn row: no `Lockout:` line, attempts as before; kill the rare: no attempt is counted by AzerothTrail (Rarity's own count still shows).
- [ ] Journal > The War Within: Stonevault Mechsuit is under Quests, not Dungeon drops.

## Search all mounts

A search box sits in the Journal front page's strip, after the title, with the one-line hint "Search all mounts" (hover: a tooltip lists what it finds). Typing in it opens "Search all mounts": a list over every tab's mounts (your faction; unobtainable ones only when owned or with Show unobtainable on), grouped by what matched — Mount name, Boss / rare, Dungeon / raid, Zone, Achievement, Expansion, Other matches — best group first. The page's own search box takes over the typing. Each word of the query is matched on its own against the mount's name, the game's source text (Drop -> boss, Zone / Location, Achievement, Vendor / Quest / other lines), the scanned achievement, the data group, the coordinates' map, the expansion and the section / holiday name; filler words (of, the, ...) are ignored. Words match exactly, as the start of a word, inside a word (3+ letters), or with a typo (1 edit at 4-5 letters, 2 at 6+). Abbreviations: bc/tbc, wrath/wotlk, cata, mop, wod, bfa, sl, df, tww, icc, toc, aq, bwl, mc, zg, za, ssc, tk, bt, tot, hfc, brf, tos, abt, bod, cn, sod, sfo, voti, atdh. With three or more words, two thirds of them must match. One letter searches nothing.

- [ ] Type `invincible`: the page opens, Invincible under "Mount name". Rows have the usual tooltip, pin click, Ctrl-click preview.
- [ ] `invincable` and `glroy of the raider` still find the right mounts (typos).
- [ ] `glory of the raider cata` and `cata raider glory`: the Cataclysm raider achievement mount first, under "Achievement". `flirty of the raider cata` still finds it.
- [ ] `icc` lists the Icecrown Citadel mounts under "Dungeon / raid" (or "Boss / rare" when the source text names the boss).
- [ ] A zone name (e.g. `stranglethorn`) lists mounts with that zone under "Zone".
- [ ] Collected (Filter) shows owned results tinted green; off hides them.
- [ ] Typing feels instant (no hitch per key) on a full collection.
- [ ] Back returns to the front page with an empty home search box; searching again starts fresh.
- [ ] The home search box's hint fits on one line (no wrapped second line).

## Window scale

A small grip in the main window's bottom-right corner scales the whole window, zone panel included, between 60% and 150%. Dragging it moves the corner with the cursor while the top-left corner stays put; right-click resets to 100%; hovering shows the current size. The scale is saved in `AzerothTrailDB.global.window.scale` with the position.

- [ ] Drag the grip down-right: the window grows smoothly, top-left fixed; up-left: it shrinks, stopping at 60%. It never goes past 150%.
- [ ] Text, tiles and lists stay sharp and laid out the same at 60%, 100% and 150%; the zone panel scales with the window.
- [ ] Right-click the grip: back to 100%. Hover: "Window size: N%".
- [ ] `/reload`: the window comes back at the same size and place.
- [ ] The grip does not cover a list's scroll bar.

## World map tab

An AzerothTrail tab (our icon in a round mask) sits in the Map & Quest Log's column of side tabs, under Map Legend and under any other add-on's tab there. Selecting it covers the quest log with "Mounts in <zone>" for the map being viewed: the zone panel's list (coords, `Zone:` source text, dungeon / raid entrances; owned only with Collected on), rows with tooltip, click for a waypoint, Shift-click map, Ctrl-click preview. World and continent maps say "Open a zone on the map to see its mounts". Blizzard's quest log mode is never changed: clicking Quests / Events / Map Legend, Blizzard switching mode, or opening a quest's details uncovers the quest log. The selection is saved (`AzerothTrailDB.global.mapTab.selected`).

- [ ] Open the map (M) with the quest log side panel shown: the AzerothTrail tab is under Map Legend, round icon, not overlapping another add-on's tab. Hover: "AzerothTrail: mounts on this map".
- [ ] Click it: the tab looks selected, Blizzard's tabs look unselected, the column shows the viewed zone's mounts. Scrolling over it does not scroll the quest log underneath.
- [ ] Browse to another zone (or zoom out and in): the list and title follow the viewed map, not where you stand. A continent / Azeroth: "Open a zone on the map to see its mounts".
- [ ] Rows: tooltip, click sets a waypoint, Shift-click, Ctrl-click preview work as in the main window.
- [ ] Click Quests (also when Quests was the mode before): the quest log is back and Quests looks selected. Same for Events and Map Legend.
- [ ] With the tab selected, click a quest on the map: the quest details show (the tab is left).
- [ ] Close and reopen the map: the tab is still selected; `/reload` too. Leave it on Quests: the map opens on Quests.
- [ ] No Lua errors or "AddOn action blocked" with the map open in combat, tracking quests, or using the objective tracker afterwards (taint check).

## Zone matching: same-named zones, neighbours' entrances, map IDs

The zone panel and the world map tab list a mount where its coordinates are (the zone, its sub-zones and dungeon floors) and in every zone its source text names on a `Zone:` / `Location:` line (a drop's zone, a vendor's zone, each name of a comma list), including a zone inside the one shown (Boralus in Tiragarde Sound, Valdrakken in Thaldraszus, Dornogal on the Isle of Dorn). A name match is kept to the version of that zone from the mount's expansion (`Data/Zones.lua`, generated by `tools/build_zones.py` from the game's UiMap and ContentTuning tables): TBC vs WoD Nagrand and Shadowmoon Valley, Cataclysm Uldum vs the 8.3 assault Uldum, MoP vs 8.3 Vale of Eternal Blossoms, Classic vs Shadowlands Tirisfal Glades, TBC vs Midnight Eversong Woods, Isle of Quel'Danas and Silvermoon City, and more. A dungeon entrance a zone map shows near its edge only counts when the dungeon lies in that zone. A floor's dungeon comes from the entrance above it (or, for the player, the instance they are in), never from GetInstanceForGameMap with a UI map ID.

- [ ] Map tab, Netherstorm: no Thundering Onyx Cloud Serpent (Timeless Isle). Timeless Isle: it is there.
- [ ] Map tab, Blasted Lands and Stranglethorn Vale: no Karazhan mounts (Fiery Warhorse, Midnight). Deadwind Pass: both. Stranglethorn Vale still lists Swift Zulian Panther (Zul'Gurub is in Northern Stranglethorn).
- [ ] Map tab, Westfall: no Infinite Timereaver.
- [ ] Map tab, Isle of Quel'Danas (the TBC one under Eastern Kingdoms): no Peridot Dragonhawk; the Midnight Isle of Quel'Danas (Quel'Thalas): it is there. Same for Eversong Woods (Fiery Dragonhawk, Crimson Silvermoon Hawkstrider) and Silvermoon City's Midnight vendor mounts.
- [ ] Map tab, Nagrand / Shadowmoon Valley in Outland: no WoD mounts (Mottled Meadowstomper, Bloodhoof Bull, Swift Breezestrider); the Draenor versions list them.
- [ ] Map tab, Uldum and Vale of Eternal Blossoms: the Cataclysm / MoP versions show the camels / cranes and serpents, not the 8.3 assault rares; the assault versions show the assault mounts, not the old ones.
- [ ] Map tab, both Tirisfal Glades: mounts without an expansion in the data (the Undercity skeletal horses) are listed in every version of a zone by design; note any that should not be.
- [ ] Inside a dungeon (e.g. Karazhan, any floor): the zone panel lists that dungeon's mounts and names it.
- [ ] A mount sold by a vendor in the zone is listed there even when it drops elsewhere; a mount whose source names two zones (two vendors) is listed in both.
- [ ] Map tab, Tiragarde Sound / Thaldraszus / Isle of Dorn: the Boralus / Valdrakken / Dornogal vendor mounts are listed too.

## Mount detail pane

Every mount list (Journal expansion lists, Holidays, Achievements, Timewalking, Misc, the front page's search) has a 300 px pane on its right. A plain left-click on a row selects it (gold tint and a gold bar on its left edge) and the pane shows it: Blizzard's own mount preview (the Mount Journal's model scene: drag to rotate, mouse wheel to zoom, the rotate / zoom buttons on hover, a "Rider" checkbox bound to the Mount Journal's own show-player setting), the icon and name (a check when owned), the client's flavor text, then the tooltip's lines without the click hints (source, chance, attempts, lockout, achievement progress), scrolling with the mouse wheel when long, and Waypoint / Map / Achievement buttons (greyed out when not available). Rows no longer show the hover tooltip in these lists; Shift-click (map), Ctrl-click (dressing room) and Shift-right-click (achievement) on a row work as before. The first mount is selected when nothing is; the selection stays through refreshes and collapsing its header, and moves to the first mount when its mount leaves the list. The Checklist and the zone panel keep the old rows (left-click waypoint, hover tooltip).

- [ ] Open Misc (or Holidays): the pane shows the first mount with its 3D model; the list's rows are narrower but readable, the search box and Filter fit above them.
- [ ] Click another row: it turns gold, the model and text change. Drag the model to rotate, wheel to zoom, hover for the buttons.
- [ ] No gift-box "present" model appears in place of a mount (also for a mount you just learned).
- [ ] Tick "Rider": your character sits on the mount; untick: the mount alone. The Mount Journal (Shift-P) follows the same setting.
- [ ] A mount without a model (rare): its large icon instead.
- [ ] Waypoint / Map buttons do what a row click used to; Achievement opens the achievement for achievement mounts, greyed out otherwise.
- [ ] Long achievement criteria scroll inside the pane with the mouse wheel.
- [ ] Shift-click / Ctrl-click / Shift-right-click on rows still work; hovering a row shows no tooltip; rows have no map / pin icon on their right (the pane's buttons replace it).
- [ ] Journal: open an expansion, collapse the selected row's header: the pane keeps showing it. Back and into another expansion: the first mount there is selected.
- [ ] Checklist and zone panel rows: unchanged (left-click waypoint, hover tooltip).

## Holiday header dates

Every Holidays header shows dates read from the in-game calendar (`C_Calendar`; `Logic/HolidayDates.lua`, `Game.HolidaySchedule`). A running holiday: the name in green and a green `Active · ends in 6d` (whole days; under a day `5h`, under an hour `<1h`). Every other holiday: a normal header and a grey badge for its next run, `Starts in 9d` within 30 days, `Starts Feb 9` beyond. Days and hours are counted on the calendar's own clock (realm time). The calendar is read once per day and again when the game says it changed; the addon never changes the month the Blizzard calendar window shows. With the calendar unreadable a running holiday keeps the plain `Active now`.

- [ ] Holidays tab with a holiday running (Darkmoon Faire is on the first week of a month; any event day will do): its header reads `<title>  (owned/total)  Active · ends in Nd` in green. Open the Blizzard calendar (click the minimap clock, or `/run ToggleCalendar()`), click the holiday on today's date: the popup says when it ends. N is the whole days from now to that end (6 days 3 hours left shows `6d`).
- [ ] Every other holiday header ends in a grey `Starts in Nd` (the run begins within 30 days) or `Starts <Mon> <day>` (later). Compare two or three with the "Begins" date in the calendar's popup for that holiday (browse the calendar to its month): the day and month match, and N is the whole days from now to the Begins time.
- [ ] The farthest holiday (the one whose next run is months away, e.g. Noblegarden, Midsummer or Winter Veil, depending on the season) also shows a date, not a bare header. **If only holidays within about a month have a date, report it:** the calendar then serves only the neighbouring months to an addon that does not browse it, and the headers beyond that stay without a badge (no error). The fix then needs a different way to read the calendar.
- [ ] Day events carry the whole run's times: pick the day of a running holiday and run `/run for i=1,C_Calendar.GetNumDayEvents(0,DAY) do local e=C_Calendar.GetDayEvent(0,DAY,i) print(i,e.title,e.calendarType,e.sequenceType,e.startTime.month.."/"..e.startTime.monthDay,e.endTime.month.."/"..e.endTime.monthDay) end` (replace `DAY` with the day of the month; offset `0` is the month the calendar window shows, which is the current month after you open it once). Repeat on the run's first, a middle and its last day: the holiday's start and end print the same on each. If they differ per day, report it: the countdown would be wrong.
- [ ] With less than a day left on a running holiday the badge counts hours (`Active · ends in 5h`), under an hour `Active · ends in <1h`. (Only checkable on a holiday's last day.)
- [ ] On the day a holiday begins, before its start time: the calendar lists it for today, so the section is already at the top in green with the plain `Active now`; after the start time it turns into `Active · ends in Nd`.
- [ ] Fresh login, open the Holidays tab straight away: the dates may be missing (or `Active now`) for a moment, then fill in without clicking anything; no Lua error with `/azt debug` on.
- [ ] Open the Blizzard calendar, browse a few months ahead, close it, reopen it: it opens on the current month as before, and the Holidays tab's dates are unchanged.
- [ ] Type in the Holidays search box: no stutter (the calendar is not re-read per keystroke).
- [ ] The next day (or after server midnight with the tab open and a click on another tab and back): every `in Nd` is one lower.
- [ ] The other tabs (Journal, Achievements, Timewalking, Misc, Checklist) look unchanged; the Checklist still lists holiday mounts only while their holiday runs.

## Waypoints to vendors and rare spawn points

`Data/Spots.lua` (generated by `tools/build_spots.py` from AllTheThings, MIT, pinned in `tools/sources.json`) lists the NPC behind each mount with all its coordinates: every spawn point of a rare (with its daily quest when it has one), and the vendor that sells a mount; when the game's source text names zones, only NPCs standing there are kept and they carry the source's own name. `Data/SpotsExtra.lua` is for hand-added spots (same shape). A waypoint (row click, the pane's Waypoint button) now goes: raid / dungeon entrance, else the holiday's place, else the vendor (if the mount has one) or the rare, at the point nearest you on your continent (other faction's vendors skipped), else the old single location. Chat names the NPC: `Waypoint: Unger Statforth (Wetlands)`. The zone panel / map tab also list a mount whose vendor or spawn point is in the zone.

- [ ] Brown Horse (Misc, Racial, Alliance): Waypoint goes to Unger Statforth in the Wetlands; chat names him.
- [ ] A Horde character on a mount sold by both factions' vendors: the Horde vendor.
- [ ] Mottled Meadowstomper (Luk'hok, WoD Nagrand): standing in Nagrand, the waypoint goes to the spawn point nearest you; from elsewhere on Draenor too; from another continent the first point.
- [ ] Garn Nighthowl (Nok-Karosh): Frostfire Ridge 13.1, 50.4.
- [ ] Tanaan Jungle mounts: the nearest of Terrorfist, Deathtalon, Vengeance and Doomroller.
- [ ] Primordial Direhorns: the nearest Zandalari Warbringer zone point.
- [ ] A raid mount (Invincible) still goes to the raid entrance; a holiday mount to its holiday place.
- [ ] Map tab on a zone with a mount vendor (e.g. Iskaara's Tatto in the Azure Span): the vendor's mounts are listed.
- [ ] Detail pane, a rare with several spawn points (Mottled Meadowstomper / Luk'hok): "Where to find it" lists Luk'hok (daily if it has a kill quest), the map name, and each spawn point as a small gold button; clicking one sets a waypoint there and chat says "Waypoint: Luk'hok (Nagrand)". A vendor mount lists the vendor ("vendor" after the name); the other faction's vendors are not listed.

## Checklist: list + detail pane, summary and chips

The Checklist follows the other tabs: its list on the left, the detail pane on the right showing the selected entry's mount (a plain left-click selects; Shift / Ctrl / Shift-right-click and the tick boxes keep their actions; no hover tooltip, no location icon on rows). The header: your name with Filter on the right, the summary line ("Daily: 6 left, reset in 9h 0m    Weekly: 11 left, reset in 3d 0h    Rare spawns: 37"), the Oregon line, then chips All / Daily (n) / Weekly (n) / Rare spawns (n): a chip shows that group only (gold while chosen), All shows everything; the choice is saved per character.

- [ ] Checklist: the pane shows the first entry; click another row: it turns gold and the pane follows (model, lockout line, spawn points / vendor).
- [ ] Tick boxes (manual lockouts, rare spawn "last checked") still tick without changing the selection; Shift-click still opens the map.
- [ ] Chips: Daily shows only the daily group, Weekly only weekly, Rare spawns only the camp group; All everything. Counts match the headers. /reload keeps the chip.
- [ ] Hover a rare header (an expansion or zone under Rare spawns, or a "Rares" category under Daily / Weekly): a green "Right-click to pop out <expansion> rares" hint. Right-click: the tracker opens on that expansion (or switches to it). Other headers do nothing on right-click.

## Pop-out rare tracker

A slim movable window (`/azt rares`, or right-click a rare header in the Checklist) that stays on screen without the main window. Title: "<Expansion> rare spawns (n left)"; click it for a menu: Current zone, or any expansion with rare-spawn mounts left. Rows come from the Checklist (daily / weekly rares and rare spawns with no lockout; owned and other-faction mounts left out): a box (daily kill: ticked and dimmed when the game says done; rare spawns: the Checklist's last-checked box, left-click marks, right-click clears), the rare's name, its zone (or "checked 3 hr ago"), and a pin button for a waypoint to its nearest spawn point. A rare with several spawn points lists each as a small gold coordinate button underneath. Clicking a row sets the waypoint too; hovering shows the mount tooltip. Drag the title to move; position, open state and choice are saved and it comes back after /reload. Scroll with the mouse wheel when long.

- [ ] Checklist > right-click the Warlords of Draenor header under Rare spawns: the tracker opens on Warlords of Draenor. The title shows a small arrow; hovering says "Click to choose the expansion; drag to move"; the menu lists Current zone and every expansion with rares left. WoD lists Nok-Karosh, Luk'hok, Pathrunner, Gorok, Poundfist, Silthide, Nakk the Thunderer... (those whose mounts you don't own).
- [ ] Luk'hok shows several coordinate buttons; each sets a waypoint there ("Waypoint: Luk'hok (Nagrand)"). The pin button goes to the nearest one.
- [ ] Tick Nok-Karosh's box: "checked 1 min ago"; the Checklist's Rare spawns row shows the same; right-click clears.
- [ ] A daily rare killed today: ticked and dimmed, at the bottom, no pin button.
- [ ] Current zone: shows only the zone's rares and follows you as you fly to another zone.
- [ ] Close the main window: the tracker stays. Drag it somewhere, /reload: same place, still open. Close button hides it (and stays hidden after /reload).
