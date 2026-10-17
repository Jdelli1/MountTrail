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
