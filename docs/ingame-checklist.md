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
