# In-game verification checklist

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

- [ ] `/reload` with `/console scriptErrors 1`, `/azt`: the Journal tab shows a 4 x 3 grid of expansion cards in Data.Expansions order (Classic first, Midnight last), each with its logo (or the expansion name when the client has no logo), `owned / total` and a green progress bar. Counts look right for this character's faction (faction-only mounts of the other faction are not counted).
- [ ] Click the Cataclysm card: the list opens with Back and the title "Cataclysm"; rows are grouped under headers in the order Dungeon drops, Raid drops, World drops / rares, Delves, Treasures & caches, Quests, Zone activities, Reputation, Vendors, Other (empty sections have no header). Back returns to the grid.
- [ ] Untick Raid drops in the left panel's Sources list: raid rows and the Raid drops header disappear; tick again and they return. The setting survives `/reload` (`/dump AzerothTrailDB.global.filters`).
- [ ] Collected off (default): owned mounts are hidden. Collected on: owned mounts appear with a grey name, a line through the name and a desaturated icon.
- [ ] Type `drake` in the search box: only rows whose name or source group contains "drake" stay; the clear (x) button restores the list.
- [ ] Row: icon (from the mount journal), name, and a grey source line, e.g. Drake of the North Wind reads `Dungeon Drop · Altairus (Vortex Pinnacle (Dungeon))`.
- [ ] Hover a row: tooltip shows the name, `~1 in N (approx.)` for mounts with a drop rate, `Times farmed: N`, `Rarity: N` when Rarity is installed and tracks the item, `Lockout: Saved/Available/Manual/—` (save to a tracked instance and check it flips to Saved after the lockout data arrives), and "Ctrl-click to preview".
- [ ] Ctrl+left-click a row opens the dressing room on the mount; a plain click does nothing.
- [ ] Map button on a row behaves as in the Task 11 checks (pin / entrance / open / "No map location").
- [ ] ScrollBox: the list scrolls with the mouse wheel and the minimal scroll bar; header rows (24 px) and mount rows (40 px) do not overlap. If the list stays empty or errors with a template message, check that `factory("Frame", ...)` / `factory("Button", ...)` (frame types, no template) are accepted by this client's ScrollBox element factory.
- [ ] Filter panel: the checkbox labels render (UICheckButtonTemplate `.Text`/`.text`); the search box shows its "Search" placeholder.
- [ ] While the window is open on a list, killing a tracked boss (UPDATE_INSTANCE_INFO) refreshes the list without resetting the scroll position.

## Task 14: Holidays, Misc and Route tabs

- [ ] `/reload` with `/console scriptErrors 1`, `/azt`: the Holidays, Misc and Route tabs build without Lua errors (no "Coming soon" left on any tab).
- [ ] Holidays tab: mounts grouped under holiday titles (Hallow's End, Brewfest, Love is in the Air, ...); the header of a holiday that is on today reads `<title>  Active now` in green (the calendar loads asynchronously: the badge may appear a moment after the first open).
- [ ] Misc tab: headers Achievements / Professions / Shop / Trading Post / Other; this month's Trading Post mounts (`tradingNow` in Data/Mounts.lua) show `· Trading Post — this month` in green after the source line.
- [ ] Route tab header: character name, `Weekly reset in ...` and `Daily reset in ...` (SecondsToTime text matching the in-game calendar resets), a "Show completed" box (state survives `/reload`: `/dump AzerothTrailDB.char`), and `You have N lockouts left. Saddle up?` where N matches the minimap tooltip's `Route: N steps left`.
- [ ] Horde character: the first step reads "Start in Orgrimmar"; Alliance character: "Start in Stormwind". Faction-only steps of the other faction are absent.
- [ ] Rows are indented by depth; travel rows are grey with no box (WoW ships no italic font, so they are not italic); kill rows show `<boss> → <mount>` lines with notes in grey, a box and a Map button.
- [ ] A saved raid (e.g. a cleared Vault of Archavon watcher) shows its row ticked, greyed (disabled) and tagged green "auto" with Show completed on, and is hidden with it off. Open instance rows have an unticked box that can be ticked by hand (manual override, see "Final review fixes").
- [ ] Manual row (e.g. a Midnight `manual` mount): click the box, it ticks and the row disappears (Show completed off) or stays ticked (on); `/reload` keeps it ticked (`/dump AzerothTrailDB.char` -> `ticks[<mountID>]` = expiry); after the daily (or weekly, per the spec's `reset`) reset it is unticked again. Clicking a ticked manual row unticks it.
- [ ] Steps whose mounts are all owned are hidden.
- [ ] During an active holiday (Hallow's End / Brewfest / Love is in the Air) its queue step is the first route row; after the holiday boss is done today it is hidden (Show completed off).
- [ ] Boss with an unlock requirement (spec `requires`) shows its text in grey after the boss line.
- [ ] Hover a kill row: mount tooltip of its first mount; Koralon/Emalon/Toravon and Chrono-Lord Deios mounts show `Lockout: Saved` once that boss is killed this week (BossLockouts). Ctrl+click previews the mount.
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

- [ ] Map in combat: click a Map button (Journal list, Route list and the arrow frame) while in combat and again after combat, then click quest and map pins on the world map. Watch chat and the error frame for "Interface action failed because of an AddOn" / "action blocked"; note any that name AzerothTrail.
- [ ] Manual override: on an open instance row (e.g. Eye of Eternity, Malygos), click the box: it ticks, the row counts as done (hidden with Show completed off, `Route: N steps left` drops by one) and `/dump AzerothTrailDB.char` shows `ticks[<mountID>]` with the spec's reset (weekly here). The attempt count (`/dump AzerothTrailDB.global.attempts`) does not move. Click again to untick. After the boss is really killed, the row shows the green "auto" tag and a disabled box (the game wins). A Dawn of the Infinites (Chrono-Lord Deios) tick is stored as `ticks["<mountID>@Chrono-Lord Deios"]` and does not tick the same mounts' own dungeon rows.
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
- [ ] Rows: no borders; every other mount row has a faint stripe (restarting under each header); hovering a row highlights it softly; icons are cropped (no baked-in square edge) and, if the client has `UI-HUD-ActionBar-IconFrame-Mask`, rounded. Section headers are a faint band with a thin gold line under them. Owned rows (Collected on) are grey with a line through the name and a desaturated icon; unowned names are gold; source lines a readable light grey (dimmed GameFontHighlightSmall).
- [ ] Journal home cards: dark flat cards with a thin light edge that turns gold on hover, the logo centred, `owned / total` above a slim green progress bar. The list page has a flat strip behind Back and the expansion title.
- [ ] Route tab: flat header strip with a thin line under it; Show completed is the flat minimal checkbox (`MinimalCheckboxTemplate`; if `/azt debug` reported it missing, the Settings checkbox or the classic one is used instead and should still tick, untick and grey out when disabled). List / Arrow is one framed two-segment control (the 1 px frame visible on all four sides and between the segments): the active segment is gold-tinted with gold text, the other dark with grey text; clicking switches mode as before. Route rows are borderless and striped; travel rows grey, kill rows gold; tick boxes are the same minimal checkbox, disabled ones look disabled.
- [ ] Classic fallback (optional, only if a fallback was reported above): the window still opens with the classic stone frame, inset and bottom tabs, and/or the old left checkbox filter panel; every function still works.
- [ ] Combat / taint: open the Filter menu and change filters in and out of combat; no "Interface action failed because of an AddOn" naming AzerothTrail.

## F1: Achievements and Timewalking tabs

Supersedes the four-tab notes above: there are now six tabs.

- [ ] `/reload` with `/console scriptErrors 1`, `/azt`: six top tabs in this order: Journal, Holidays, Achievements, Timewalking, Misc, Route. All fit on one row right of the portrait inside the 800 px window (nothing overlaps the window's right edge); each is sized to its text with a little padding, Misc and Route no narrower than ~70 px, none wider than ~116 px. No label is truncated ("..."); if one is on this client/locale, note which.
- [ ] Achievements tab: only achievement-reward mounts (e.g. Red Proto-Drake and Black Proto-Drake are here; Time-Lost Proto-Drake, a world rare, is not). Headers are expansion names in expansion order (Wrath of the Lich King ... Midnight); a "General" header, if any, comes last. Collected filter (Filter menu, Collected only) and search work.
- [ ] Timewalking tab: one "Timewalking" header with the Timewalking vendor mounts (e.g. Ironbound Wraithcharger, Eclipse Dragonhawk, Yu'lei, Daughter of Jade). Collected filter and search work.
- [ ] Holidays tab: no Timewalking header or Timewalking mounts any more; the other holiday headers and the "Active now" badge are unchanged.
- [ ] Misc tab: headers Professions, Shop, Trading Post, Other only (no Achievements header); the "Trading Post — this month" tag is unchanged.
- [ ] Journal home counts are unchanged from before this update (achievement and Timewalking mounts were never counted there).
- [ ] Saved tab: select Achievements, `/reload`, `/azt`: Achievements is still selected; same for Timewalking. A saved tab key from an older version that no longer exists opens Journal.
- [ ] Classic fallback (only if `/azt debug` reported PanelTopTabButtonTemplate missing): six bottom tabs, all clickable.

## F2: Achievement hover and Shift+right-click

The mount -> achievement map is built in the background the first time an achievement mount is hovered or the Achievements tab is opened, and saved per faction and client build (`/dump AzerothTrailDB.global.achievementMap`: one entry each for Alliance, Horde and Neutral, keyed `<toc>:<build>:v2`).

- [ ] Fresh map: `/run AzerothTrailDB.global.achievementMap = {}` then `/reload`, `/azt`, open the Achievements tab. No hitch or freeze (the scan reads at most 200 achievements per frame); within a few seconds `/dump AzerothTrailDB.global.achievementMap.Alliance` (or `.Horde`) shows `build = "120105:<build>:v2"` and `ids` lists this faction's achievement mounts (an achievement ID, or `false` for none found); the other faction's mounts are absent. Note any obviously wrong pairs, especially Crimson Cloud Serpent vs Heavenly Crimson Cloud Serpent (different achievements). A map saved by the first F2 build (top-level `build`/`ids`) is replaced.
- [ ] Hover (Achievements tab), e.g. Red Proto-Drake: after the item tooltip and the farming lines comes `Achievement: Glory of the Hero` (gold; green with "(completed)" when earned), its description (white, wrapped), then up to 8 criteria (completed green, others grey; counted ones show `(n/m)`), then `+N more` when there are more, then `Ctrl-click to preview` and `Shift-right-click to open the achievement`. Check a meta achievement (e.g. Glory of the Raider) and a counter achievement (e.g. Mountacular, `Progress (n/m)` or a named criterion).
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
- [ ] Hover a statistic mount (e.g. Journal > Classic > Rivendare's Deathcharger): `Kills: N` where `Times farmed` used to be (only this character has data). The `Rarity: N` line is still there when Rarity is installed; `Lockout:` and the hints unchanged.
- [ ] Log in an alt, `/reload`, hover the same mount: `Kills: <sum over both> (this character: <alt's count>)`. A character with 0 kills still shows the split.
- [ ] Hover a mount without statistics (e.g. a reputation or vendor mount, or a dungeon mount Rarity has no statistic for): still `Times farmed: N`.
- [ ] Kill a statistic boss (e.g. Baron Rivendare in Stratholme): after the lockout update (`UPDATE_INSTANCE_INFO`, a few seconds after the kill) the tooltip's count goes up by one without `/reload`.
- [ ] Combat: enter combat (training dummy), `/reload` while still in combat if possible, or kill a statistic boss and stay in combat: no statistics are read until combat ends (`/dump AzerothTrailDB.global.stats` unchanged), then they update. No "Interface action failed" or Lua errors naming AzerothTrail.
- [ ] Note any statistic mount whose count looks wrong (e.g. counts a difficulty that cannot drop the mount, or misses one that can): that is Rarity's statistic list, reported per mount ID.
