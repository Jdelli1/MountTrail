# In-game verification checklist

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
