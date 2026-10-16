# AzerothTrail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Retail WoW addon with a Dungeon-Journal-style mount browser (Journal / Holidays / Misc tabs) and a per-character farming route that auto-ticks from lockouts and resets itself.

**Architecture:** A Python build tool turns SimpleArmory's `mounts.json` + `planner.json` (MIT) and Rarity's `DB/Mounts/*.lua` (GPL-2.0) into generated Lua data files. Pure-Lua logic modules (filters, lockouts, route, resets, attempts) take plain tables and functions, so they are unit-tested outside the game; a thin `Game` adapter is the only code that calls the WoW API; UI modules render what the logic returns.

**Tech Stack:** Lua 5.1 (WoW Retail 12.x), Ace3 (AceAddon-3.0, AceDB-3.0, AceConsole-3.0), LibDataBroker-1.1, LibDBIcon-1.0; Python 3 build tool (stdlib only); Lua tests run under `lupa` (Lua 5.1/LuaJIT) via a Python runner.

**Spec:** `docs/superpowers/specs/2026-10-16-azerothtrail-design.md`

## Global Constraints

- Retail only (Midnight 12.x). `## Interface:` = the number printed in-game by `/dump (select(4, GetBuildInfo()))` (owner runs it in Task 1).
- No network at runtime; all data ships in `Data/`.
- License GPL-2.0 for the addon. Credit SimpleArmory (MIT, keep its notice), Rarity (GPL-2.0), Ace3, LibDataBroker-1.1, LibDBIcon-1.0, TomTom (optional) in `LICENSE`/`CREDITS.md`, README, generated-file headers.
- TomTom and Rarity are optional: every call to them is guarded; the addon works without them.
- Never call combat-restricted or protected APIs; never rely on combat-log events.
- Route is for the logged-in character only. Journal filters do not affect the Route.
- Default filters: all source checkboxes on, **Collected off**.
- Attempt counts are account-wide; manual ticks are per character.
- Mount belongs to the expansion it was released in (SimpleArmory's top-level category).
- Every user-facing string goes through `ns.L` (enUS only in v1).
- Drop rates display as `~1 in N (approx.)`.
- Slash commands: `/azt` and `/azerothtrail`.

## Review Focus

1. **Lockout data not loaded yet** (fresh login before `UPDATE_INSTANCE_INFO`): route shows steps as open, no Lua error; refreshes when the event fires. → Task 6 test `snapshot of nil rows is empty`, Task 11 refresh wiring.
2. **Mount ID in data but unknown to this client** (removed/renamed in a patch): `C_MountJournal.GetMountInfoByID` returns nil → row skipped, counts exclude it, no error. → Task 9 test `unknown mount is skipped`.
3. **Manual tick across a reset while logged out:** a tick made before the reset is gone on next login. → Task 5 test `prune drops expired ticks`.
4. **Faction edge cases:** Neutral (unchosen Pandaren) character: faction-flagged steps hidden, capital text reads "your capital". → Task 7 test `neutral hides faction steps`.
5. **Search text with Lua pattern characters** (`[`, `%`, `(`): plain substring match, no error. → Task 8 test `search treats pattern chars literally`.

---

## File Structure

```
AzerothTrail/
  AzerothTrail.toc            load order
  embeds.xml                  library includes
  Libs/                       vendored Ace3 subset, LibDataBroker-1.1, LibDBIcon-1.0 (+ their licenses)
  Core/Locale.lua             ns.L (enUS strings, flavour text)
  Core/Init.lua               AceAddon object, AceDB defaults, slash commands, event wiring
  Data/Mounts.lua             GENERATED: ns.Data.Mounts, ns.Data.Expansions order
  Data/Route.lua              GENERATED: ns.Data.Route (planner tree)
  Data/Lockouts.lua           hand-written: mountID -> lockout spec
  Data/Holidays.lua           hand-written: holiday key -> calendar title, lfg dungeon, coords
  Logic/Resets.lua            manual-tick expiry
  Logic/Lockouts.lua          saved-instance snapshot + per-mount state
  Logic/Route.lua             builds visible route rows
  Logic/Journal.lua           filtering, grouping, counts
  Logic/Attempts.lua          attempt counting from snapshot transitions
  Game/API.lua                the only WoW API calls (ns.Game)
  Integrations/Map.lua        waypoint / map / TomTom
  Integrations/Rarity.lua     read Rarity attempts if loaded
  UI/Frame.lua                main window, tabs, minimap button
  UI/List.lua                 shared grouped mount list (Journal expansion, Holidays, Misc)
  UI/JournalHome.lua          expansion grid
  UI/Tooltip.lua              mount tooltip + click handling
  UI/RouteView.lua            route tab
  tools/build_data.py         data generator
  tools/test_build_data.py    unittest for the generator
  tools/fixtures/             tiny SimpleArmory/Rarity samples
  tools/run_tests.py          Lua test runner (lupa)
  tests/harness.lua           describe/it/eq
  tests/wow_stub.lua          minimal globals for loading addon files
  tests/*_spec.lua            Lua tests
  LICENSE  CREDITS.md  README.md  .pkgmeta
```

All addon Lua files start with `local ADDON, ns = ...` and attach to `ns` (no globals except the AceAddon object `AzerothTrail` and saved variable `AzerothTrailDB`).

---

### Task 1: Scaffold, licenses, test harness

**Files:**
- Create: `AzerothTrail.toc`, `Core/Locale.lua`, `Core/Init.lua` (stub: `ns.version = "0.1.0"`), `LICENSE` (GPL-2.0 full text), `CREDITS.md`, `README.md`, `.pkgmeta`, `tools/run_tests.py`, `tests/harness.lua`, `tests/wow_stub.lua`, `tests/load_spec.lua`

**Interfaces:**
- Produces: `python tools/run_tests.py` runs every `tests/*_spec.lua`, exits non-zero on any failure. `tests/harness.lua` exposes globals `describe(name, fn)`, `it(name, fn)`, `eq(actual, expected, msg)` (deep-compares tables), `ok(cond, msg)`. Helper `load_addon(files)` returns `ns` after running each listed file with `("AzerothTrail", ns)`.

- [ ] **Step 1:** Ask the owner to run `/dump (select(4, GetBuildInfo()))` in game and give the number; ask for their WoW install path (for Task 15). Use the number for `## Interface:`.
- [ ] **Step 2:** `python -m pip install lupa`. Runner imports `lupa.lua51`, falling back to `lupa.luajit21`; fails loudly if neither exists.
- [ ] **Step 3: Write failing test** `tests/load_spec.lua`:

```lua
describe("load", function()
  it("loads locale and init into ns", function()
    local ns = load_addon({"Core/Locale.lua", "Core/Init.lua"})
    ok(ns.L, "ns.L exists")
    eq(ns.L["Journal"], "Journal")
    eq(ns.version, "0.1.0")
  end)
  it("missing locale key returns the key", function()
    local ns = load_addon({"Core/Locale.lua"})
    eq(ns.L["Some Unknown Key"], "Some Unknown Key")
  end)
end)
```

- [ ] **Step 4:** `python tools/run_tests.py` → FAIL (files missing).
- [ ] **Step 5:** Implement. `ns.L` is a table with an `__index` that returns the key. `.toc`: `## Title: AzerothTrail`, `## Notes:`, `## Author:` James, `## Version: @project-version@`, `## SavedVariables: AzerothTrailDB`, `## SavedVariablesPerCharacter: AzerothTrailCharDB`, `## OptionalDeps: TomTom, Rarity`, `## IconTexture: 132261`, then files in the order of the File Structure (Libs via `embeds.xml` first). `.pkgmeta` ignores `tools`, `tests`, `docs`. `CREDITS.md` lists every source in Global Constraints with URL and license.
- [ ] **Step 6:** Tests PASS.
- [ ] **Step 7:** Commit `chore: scaffold addon, licenses and Lua test runner`.

### Task 2: Vendor libraries

**Files:** Create `Libs/LibStub`, `Libs/CallbackHandler-1.0`, `Libs/AceAddon-3.0`, `Libs/AceDB-3.0`, `Libs/AceConsole-3.0`, `Libs/AceEvent-3.0`, `Libs/LibDataBroker-1.1`, `Libs/LibDBIcon-1.0`, `embeds.xml`. Modify `CREDITS.md`.

- [ ] **Step 1:** Download current releases: Ace3 from `https://github.com/WoWUIDev/Ace3` (latest tag), LibDataBroker-1.1 from `https://github.com/tekkub/libdatabroker-1-1`, LibDBIcon-1.0 from `https://github.com/BigWigsMods/LibDBIcon-1.0` (check the actual repo URL; use the one CurseForge lists). Put each in its own temp dir, copy only the library folders plus each license file into `Libs/`.
- [ ] **Step 2:** `embeds.xml` includes each lib's `.xml`/`.lua` in dependency order (LibStub, CallbackHandler, Ace*, LDB, LibDBIcon).
- [ ] **Step 3:** Add each library + license to `CREDITS.md`.
- [ ] **Step 4:** Commit `chore: vendor Ace3, LibDataBroker, LibDBIcon`.

### Task 3: Data generator

**Files:** Create `tools/build_data.py`, `tools/test_build_data.py`, `tools/fixtures/sa_mounts.json`, `tools/fixtures/sa_planner.json`, `tools/fixtures/rarity_sample.lua`, `tools/sources.json`. Generate `Data/Mounts.lua`, `Data/Route.lua`.

**Interfaces:**
- Produces `Data/Mounts.lua`:

```lua
local ADDON, ns = ...
ns.Data = ns.Data or {}
ns.Data.Expansions = { "Classic", "The Burning Crusade", ..., "Midnight" }  -- oldest first, SimpleArmory names
ns.Data.Mounts = {
  [395] = { name="Drake of the North Wind", spell=88742, item=63040, icon="inv_misc_stormdragonpale",
            exp="Cataclysm", tab="journal", section="dungeon", group="Dungeon Drop",
            chance=100, quest=nil, coords={ m=325, x=60.0, y=58.0 } },
  ...
}
```

  `tab` ∈ `journal|holiday|misc`; `section` (journal) ∈ `dungeon|raid|world|reputation|vendor|other`; `section` (misc) ∈ `achievement|profession|shop|tradingpost|other`; `section` (holiday) = holiday key (`hallowsend`, `brewfest`, `loveisintheair`, `noblegarden`, `winterveil`, `lunarfestival`, `midsummer`, `darkmoon`, `timewalking`, `anniversary`, `other`); `tradingNow=true` for SimpleArmory's current "Limited Time › Trading Post: <Month>" items.
- Produces `Data/Route.lua`: `ns.Data.Route = { <node>, ... }`, node = `{ title=, type=, capital=bool, alliance=bool, horde=bool, notes=, bosses={ {mount=395, boss="Altairus", note=} }, steps={ <node>... } }` (SimpleArmory's tree, keys renamed, `ID`→`mount`).
- Both files start with a header comment naming the SimpleArmory and Rarity commit SHAs, their licenses, and "GENERATED by tools/build_data.py — do not edit".

**Classification (exact):**

| SimpleArmory | tab / section |
|---|---|
| expansion category, subcat `Dungeon Drop`, `Challenge Mode` | journal / dungeon |
| `Raid Drop`, `Raid Renown` | journal / raid |
| `Rare Spawn`, `World Boss`, `Zone Drop`, `Nemesis Drop`, `Prey Drop`, `Tormentors`, `Treasure` | journal / world |
| `Reputation`, `Paragon Reputation`, `Renown`, and any subcat that is a faction name (`Cenarion Expedition`, `Kurenai/The Mag'har`, `Netherwing`, `Sha'tari Skyguard`, `Golden Lotus`, `Order of the Cloud Serpent`, `Shado-Pan`, `The Tillers`) | journal / reputation |
| `Vendor`, `Kun-Lai Vendor` | journal / vendor |
| `Achievement` inside an expansion | misc / achievement (keep `exp`) |
| any other expansion subcat | journal / other |
| top-level `Professions` | misc / profession |
| top-level `Promotion` subcat `Blizzard Store` | misc / shop |
| top-level `Limited Time` subcat starting `Trading Post`, and `Past Limited Time` subcats starting `Trading Post` | misc / tradingpost (`tradingNow` only for `Limited Time`) |
| top-level `World Events` | holiday / key from subcat (`Hallow's End`→`hallowsend`, …; unknown→`other`) |
| everything else (`Mounts`, `Racial`, `Mythic+`, `PVP`, `Other`, rest of `Promotion`/`Limited Time`/`Past Limited Time`) | misc / other |

  `exp` for non-expansion categories = `nil`.

**Rarity join:** parse each `["Name"] = { ... }` block in `DB/Mounts/*.lua` with regex for `spellId = N`, `itemId = N`, `chance = N`, `questId = N` or `questId = { N, ... }` (keep first), first `{ m = N, x = F, y = F }` in `coords`. Join on spell ID (SimpleArmory mounts use key `spellid`). Unmatched Rarity entries are ignored.

- [ ] **Step 1: Write failing tests** in `tools/test_build_data.py` (unittest) using fixtures:
  - `test_dungeon_drop_classified`: fixture Cataclysm/Dungeon Drop mount 395 → `tab=="journal"`, `section=="dungeon"`, `exp=="Cataclysm"`.
  - `test_faction_subcat_is_reputation`: TBC/Netherwing mount → `section=="reputation"`.
  - `test_world_event_is_holiday`: World Events/Hallow's End mount → `tab=="holiday"`, `section=="hallowsend"`.
  - `test_trading_post_now`: Limited Time/"Trading Post: October" → `section=="tradingpost"`, `tradingNow is True`; Past Limited Time/"Trading Post Originals" → `tradingNow` falsy.
  - `test_rarity_join`: fixture Rarity entry spellId 127158 chance 100 questId 32099 coords m=379 → mount gets `chance==100`, `quest==32099`, `coords=={"m":379,"x":53.7,"y":64.7}`.
  - `test_route_tree_renamed`: planner fixture → first kill node `bosses[0]["mount"]==395`, `capital` preserved, `isAlliance`→`alliance`.
  - `test_lua_emit_round_trip`: emitted Lua string for a mount contains `[395] = {` and escapes quotes in names (`Mimiron's Head` → `"Mimiron's Head"`, `"` inside → `\"`).
- [ ] **Step 2:** `python -m unittest tools/test_build_data.py -v` → FAIL.
- [ ] **Step 3:** Implement `build_data.py`: `load_sa(mounts_path, planner_path)`, `parse_rarity(lua_texts) -> {spell_id: dict}`, `classify(category, subcat) -> (tab, section)`, `build_mounts(sa, rarity) -> dict`, `build_route(planner) -> list`, `emit_lua(...) -> str`, `main()` which downloads the files pinned in `tools/sources.json` (`{"simplearmory":{"repo":"kevinclement/SimpleArmory","commit":"<sha>"},"rarity":{"repo":"WowRarity/Rarity","commit":"<sha>"}}`) into `tools/.cache/` (gitignored) and writes `Data/Mounts.lua`, `Data/Route.lua`. `--update` resolves current `master` SHAs and rewrites `sources.json`.
- [ ] **Step 4:** Tests PASS.
- [ ] **Step 5:** `python tools/build_data.py --update` then `python tools/build_data.py`; generated files exist, `Data/Mounts.lua` has > 1000 entries.
- [ ] **Step 6:** Commit `feat: data generator from SimpleArmory and Rarity` (include generated files).

### Task 4: Hand-written lockout and holiday data

**Files:** Create `Data/Lockouts.lua`, `Data/Holidays.lua`, `tests/data_spec.lua`.

**Interfaces:**
- `ns.Data.Lockouts[mountID] = spec`, spec is one of:
  - `{ instance=<instanceID from GetSavedInstanceInfo>, boss="<encounter name as in GetSavedInstanceEncounterInfo, enUS>", difficulties={<difficultyID>...}, reset="daily"|"weekly" }` — done when killed on **every** listed difficulty.
  - `{ quest=<questID>, reset="daily"|"weekly" }`
  - `{ lfg=<LFG dungeonID>, reset="daily" }`
  - `{ manual=true, reset="daily"|"weekly" }` (no detectable flag)
  - Any spec may add `requires={ quest=<questID>, text="<unlock needed>" }` (garrison, Mechagon, etc.).
- `ns.Data.Holidays[key] = { title="<calendar event title, enUS>", lfg=<dungeonID or nil>, coords={m=,x=,y=} or nil, mounts={mountID...}, stepTitle="<route text>" }` for `hallowsend` (lfg 285), `brewfest` (lfg 287), `loveisintheair` (lfg 288) at minimum.
- When a Rarity `quest` exists in `ns.Data.Mounts[id].quest` and no Lockouts entry is written, Logic treats it as `{ quest=…, reset="weekly" }` (Task 6).

- [ ] **Step 1: Write failing test** `tests/data_spec.lua`:

```lua
it("every route boss has a lockout spec or a Rarity quest", function()
  local ns = load_addon({"Data/Mounts.lua","Data/Route.lua","Data/Lockouts.lua"})
  local missing = {}
  local function walk(n) for _,b in ipairs(n.bosses or {}) do
      if not ns.Data.Lockouts[b.mount] and not (ns.Data.Mounts[b.mount] or {}).quest then missing[#missing+1]=b.mount end end
    for _,c in ipairs(n.steps or {}) do walk(c) end end
  for _,n in ipairs(ns.Data.Route) do walk(n) end
  eq(missing, {})
end)
it("lockout specs are well-formed", function() --[[ each spec has exactly one of instance/quest/lfg/manual; reset is daily|weekly; instance specs have boss and non-empty difficulties ]] end)
```

- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Author entries for every route boss. Difficulty IDs: 1 Normal dungeon, 2 Heroic dungeon, 23 Mythic dungeon, 3/4 10/25 Normal legacy raid, 5/6 10/25 Heroic legacy raid, 14 Normal, 15 Heroic, 16 Mythic, 17 LFR, 9 40-player. Use route `note` text ("Heroic only", "Mythic only", "Heroic 25 only") to choose difficulties; heroic dungeons from Cataclysm and older are `reset="daily"`. Mark uncertain IDs with `-- verify in game` (Task 10's `/azt dump` confirms).
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat: lockout and holiday data`.

### Task 5: Resets (manual ticks)

**Files:** Create `Logic/Resets.lua`, `tests/resets_spec.lua`.

**Interfaces:** `ns.Resets.Expiry(kind, now, untilDaily, untilWeekly) -> number`; `ns.Resets.Tick(store, mountID, kind, now, untilDaily, untilWeekly)`; `ns.Resets.Untick(store, mountID)`; `ns.Resets.IsTicked(store, mountID, now) -> boolean`; `ns.Resets.Prune(store, now)`. `store` is a plain table `{[mountID]=expiresAt}`.

- [ ] **Step 1: Failing tests:** `Expiry("daily", 1000, 50, 900) == 1050`; `Expiry("weekly", 1000, 50, 900) == 1900`; tick then `IsTicked(store, 395, 1049) == true` and `IsTicked(store, 395, 1050) == false`; **`prune drops expired ticks`**: store `{[1]=10,[2]=100}`, `Prune(store, 50)` → `{[2]=100}`; `Untick` removes.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** Commit `feat: manual tick resets`.

### Task 6: Lockout state

**Files:** Create `Logic/Lockouts.lua`, `tests/lockouts_spec.lua`.

**Interfaces:**
- `ns.Lockouts.Snapshot(rows) -> snap`; `rows` = list of `{ instance=, difficulty=, bosses={ {name=, killed=bool} } }` or nil; `snap[instance][difficulty][bossName] = true` for killed bosses.
- `ns.Lockouts.SpecFor(mountID) -> spec or nil` (Data.Lockouts, else Rarity quest → `{quest=q, reset="weekly"}`).
- `ns.Lockouts.State(spec, snap, isQuestDone, isLfgDone) -> "done"|"open"|"manual"` (`isQuestDone(id)`, `isLfgDone(id)` are functions).

- [ ] **Step 1: Failing tests:**
  - `snapshot of nil rows is empty`: `eq(Snapshot(nil), {})`.
  - instance spec `{instance=657,boss="Altairus",difficulties={2}}` with snap killed on 2 → `"done"`; on 1 only → `"open"`.
  - multi-difficulty `{difficulties={14,15}}` killed on 14 only → `"open"`; both → `"done"`.
  - quest spec with `isQuestDone` returning true → `"done"`.
  - lfg spec with `isLfgDone` false → `"open"`.
  - manual spec → `"manual"`.
  - `SpecFor` falls back to Rarity quest.
- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `feat: lockout state from saved instances and quest flags`.

### Task 7: Route builder

**Files:** Create `Logic/Route.lua`, `tests/route_spec.lua`.

**Interfaces:** `ns.Route.Build(tree, ctx) -> rows`.
- `ctx = { faction="Horde"|"Alliance"|"Neutral", isOwned=fn(mountID)->bool, isQuestDone=fn(questID)->bool, stateOf=fn(mountID)->"done"|"open"|"manual-done"|"manual-open", showCompleted=bool, holidaySteps={ {title=, mounts={...}} } }`
- `row = { depth=int, kind="travel"|"kill", title=string, notes=string|nil, bosses={ {mount=, boss=, note=, state=, locked=bool, lockedText=string|nil} }, state="done"|"open"|"manual", auto=bool }`

Rules:
1. Skip nodes with `alliance` when faction ≠ Alliance, with `horde` when faction ≠ Horde.
2. `capital=true` nodes: title becomes `L["Hearthstone to %s"]` with `Orgrimmar`/`Stormwind`/`L["your capital"]` (Neutral), followed by the node's own title if any (`"and Portal to X"`).
3. Kill node keeps only bosses whose mount is not owned; with none left the node is dropped.
4. Kill node `state`: `"done"` if every boss is `done`/`manual-done` (`auto=true` if any came from `done`), `"manual"` if any boss is `manual-open`, else `"open"`. Done nodes are dropped unless `showCompleted`.
5. Travel node is dropped if no descendant row survives.
6. Active holiday steps come first as kill rows at depth 0.
6a. Access: a boss whose `ns.Data.Lockouts[mount].requires` (`{quest=<questID>, text="<why>"}`, optional, authored in Task 4 for e.g. garrison or Mechagon unlocks) is not met per `ctx.isQuestDone` keeps its row but gets `locked=true, lockedText=text`; the row is flagged, never hidden. Test: `locked boss stays visible and flagged`.
7. Output is the depth-first flattening.

- [ ] **Step 1: Failing tests** (small inline trees): faction filter both ways; **`neutral hides faction steps`** (Neutral drops `alliance` and `horde` nodes, capital title contains "your capital"); owned boss removed and empty kill dropped; travel with no surviving children dropped; done kill hidden unless `showCompleted`; mixed `done`+`manual-open` → `"manual"`; holiday steps first.
- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `feat: per-character route builder`.

### Task 8: Journal logic

**Files:** Create `Logic/Journal.lua`, `tests/journal_spec.lua`.

**Interfaces:**
- `ns.Journal.DefaultFilters = { dungeon=true, raid=true, world=true, reputation=true, vendor=true, other=true, collected=false }`
- `ns.Journal.Select(mounts, query) -> list` where `query = { tab=, exp=, section=nil, filters=, search=, isOwned=fn, exists=fn }`; returns `{ {id=, m=<mount table>} }` sorted by section order (journal: dungeon, raid, world, reputation, vendor, other) then name.
- `ns.Journal.Counts(mounts, exp, isOwned, exists) -> owned, total` (journal tab only).
- Section filter flags apply to `tab="journal"`; `collected` applies to all tabs.

- [ ] **Step 1: Failing tests:** filter out raid when `raid=false`; collected hidden by default, shown with `collected=true`; search is case-insensitive substring of name; **`search treats pattern chars literally`** (`search="[("` returns empty list, no error; a mount named `"Test (Rare)"` matches `"(rare"`); counts exclude holiday/misc and non-existent mounts.
- [ ] **Steps 2–5:** FAIL → implement (use `string.find(s, q, 1, true)`) → PASS → commit `feat: journal filtering and counts`.

### Task 9: Attempts

**Files:** Create `Logic/Attempts.lua`, `tests/attempts_spec.lua`.

**Interfaces:**
- `ns.Attempts.Newly(prev, curr, mountIDs, specFor, isOwned) -> {mountID...}` where `prev`/`curr` = `{ snap=, quests={[id]=bool}, lfg={[id]=bool} }`; returns mounts whose spec state went `open`→`done` and are not owned.
- `ns.Attempts.Add(store, mountID)`; `ns.Attempts.Get(store, mountID) -> int`. `store` account-wide `{[mountID]=count}`.

- [ ] **Step 1: Failing tests:** open→done increments; done→done does not; owned mount not counted; **`unknown mount is skipped`** (mountID with no spec → ignored, no error); manual specs never counted.
- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `feat: attempt counting from lockout transitions`.

### Task 10: Game adapter, init, debug dump

**Files:** Create `Game/API.lua`. Modify `Core/Init.lua`.

**Interfaces (`ns.Game`):** `IsOwned(mountID)`, `Exists(mountID)` (GetMountInfoByID non-nil), `MountInfo(mountID) -> name, icon, spellID`, `SavedRows()` (GetNumSavedInstances / GetSavedInstanceInfo (`instanceId` is return 14) / GetSavedInstanceEncounterInfo, only `locked` rows), `IsQuestDone(id)` (C_QuestLog.IsQuestFlaggedCompleted), `IsLfgDone(id)` (`GetLFGDungeonRewards(id)` first return), `UntilDaily()` (C_DateAndTime.GetSecondsUntilDailyReset), `UntilWeekly()` (C_DateAndTime.GetSecondsUntilWeeklyReset), `Faction()` (UnitFactionGroup "player"), `ActiveHolidays() -> {[key]=true}` (C_Calendar.OpenCalendar once, then today's events of type HOLIDAY matched to `Data.Holidays[*].title`), `ExpansionLogo(index) -> fileID|nil` (GetExpansionDisplayInfo), `CharKey()` ("Name-Realm").

`Core/Init.lua`: AceAddon `AzerothTrail` with AceConsole/AceEvent. DB defaults: global `{ filters=DefaultFilters, attempts={}, minimap={hide=false}, window={} }`; char `{ ticks={}, showCompleted=false, last=nil }`. On `PLAYER_ENTERING_WORLD`: `RequestRaidInfo()`, `Resets.Prune`. On `UPDATE_INSTANCE_INFO`, `QUEST_TURNED_IN`, `LFG_UPDATE_RANDOM_INFO`, `NEW_MOUNT_ADDED`: rebuild a `curr` state, run `Attempts.Newly(char.last, curr, …)`, `Attempts.Add` each, store `char.last = curr`, fire `ns.Refresh()` (UI hook; no-op until Task 12). Slash: `/azt` toggles window; `/azt dump` prints `SavedRows()` (instance ID, difficulty ID, boss names, killed) to chat.

- [ ] **Step 1:** Implement; `tests/load_spec.lua` gains a case loading every non-UI file with `tests/wow_stub.lua` (stub supplies `LibStub` returning a fake AceAddon with `NewAddon`, plus no-op globals used at file load).
- [ ] **Step 2:** `python tools/run_tests.py` PASS.
- [ ] **Step 3 (in game, owner):** link addon (Task 15 script), `/reload`, `/azt dump` after a known lockout; confirm instance IDs, difficulty IDs and boss names match `Data/Lockouts.lua`; fix mismatches. Kill one tracked boss on a character without the mount; check `AzerothTrailDB.global.attempts[<id>]` went up by 1 (`/dump AzerothTrailDB.global.attempts`). **This is the spec's risk #1 — if the count does not move, stop and report before UI work.**
- [ ] **Step 4:** Commit `feat: game adapter, events, /azt dump`.

### Task 11: Map and Rarity integrations

**Files:** Create `Integrations/Map.lua`, `Integrations/Rarity.lua`, `tests/rarity_spec.lua`.

**Interfaces:**
- `ns.Map.Show(mountID)`: coords = `Data.Holidays` coords for holiday mounts else `Data.Mounts[id].coords`. If `C_Map.CanSetUserWaypointOnMap(m)`: `C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(m, x/100, y/100))`, `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`, `OpenWorldMap(m)`. Otherwise (instance map): `C_EncounterJournal.GetInstanceForGameMap(m)` → journal instance; walk `C_Map.GetMapInfo(m).parentMapID` upward until `C_EncounterJournal.GetDungeonEntrancesForMap(parent)` contains that journal instance; use its `position`. If TomTom global exists: `TomTom:AddWaypoint(map, x, y, { title=name, persistent=false })`. If nothing resolves, print `L["No map location for %s"]`.
- `ns.RarityBridge.Attempts(itemID) -> int|nil`: nil unless `C_AddOns.IsAddOnLoaded("Rarity")` and `Rarity.db.profile.groups` exists; scan groups for an entry with `itemId == itemID`, return its `attempts` (number) else nil. Wrapped in `pcall`.

- [ ] **Step 1: Failing tests** for `RarityBridge.Attempts` with a stubbed `Rarity` global: returns 42 for matching itemId; nil when Rarity absent; nil (no error) when `Rarity.db` is malformed.
- [ ] **Steps 2–4:** FAIL → implement → PASS.
- [ ] **Step 5 (in game):** Map button target for one outdoor mount (Sha of Anger) and one instance (Vortex Pinnacle) opens the map with a pin at the entrance; with TomTom installed an arrow appears.
- [ ] **Step 6:** Commit `feat: map waypoints, TomTom and Rarity bridges`.

### Task 12: Main window, tabs, minimap button

**Files:** Create `UI/Frame.lua`. Modify `Core/Init.lua` (set `ns.Refresh`).

- Window: `CreateFrame("Frame", "AzerothTrailFrame", UIParent, "PortraitFrameTemplate")`, ~ 800×560, movable, saved position in `db.global.window`, `UISpecialFrames` entry (Esc closes), portrait = addon icon. Four tabs via `PanelTabButtonTemplate`: Journal, Holidays, Misc, Route; selected tab saved in `db.global.window.tab`.
- Minimap: LDB launcher `AzerothTrail` (left-click toggles window, tooltip shows "Route: N steps left") + LibDBIcon with `db.global.minimap`.
- `ns.Refresh()` re-renders the visible tab only.

- [ ] **Step 1:** Implement. **Step 2 (in game):** `/azt` opens/closes, Esc closes, tab and position persist across `/reload`, minimap button toggles. **Step 3:** Commit `feat: main window, tabs, minimap button`.

### Task 13: Journal home, list, tooltip

**Files:** Create `UI/JournalHome.lua`, `UI/List.lua`, `UI/Tooltip.lua`.

- Home: grid of expansion cards in `Data.Expansions` order; card = `ExpansionLogo(i)` (fallback: expansion name text), `owned / total` from `Journal.Counts`, progress bar. Click → expansion list; back button returns.
- `UI/List.lua`: `ns.UI.List(parent, query)` renders a scrollable list (`ScrollBox` + `CreateScrollBoxListLinearView`) grouped by `section` with headers; left filter panel (checkboxes bound to `db.global.filters`, Collected included; section boxes hidden on Holidays/Misc tabs) + `SearchBoxTemplate`. Row: icon (`MountInfo` icon), name (grey + strikethrough look if owned), source line (`group` + boss/zone from route data when available), **Map** button → `ns.Map.Show`.
- Tooltip (`UI/Tooltip.lua`) on row hover: name; `~1 in N (approx.)` when `chance`; `Times farmed: N` from `Attempts.Get`, plus `Rarity: N` when the bridge returns a number; lockout state for this character (`Saved`/`Available`/`Manual`/`—`); hint line "Ctrl-click to preview".
- Ctrl+left-click row: `DressUpMount(mountID)`.

- [ ] **Step 1:** Implement. **Step 2 (in game):** home shows logos and counts; Cataclysm list groups Dungeons/Raids/…; unticking Raid hides raid rows; Collected off hides owned mounts; search `"drake"` filters; tooltip shows rate/attempts; Ctrl-click opens dressing room; Map works. **Step 3:** Commit `feat: journal home, mount list, tooltip`.

### Task 14: Holidays, Misc and Route tabs

**Files:** Create `UI/RouteView.lua`. Modify `UI/Frame.lua`.

- Holidays tab: `List` with `tab="holiday"`, section headers = holiday titles with `L["Active now"]` badge from `ActiveHolidays()`.
- Misc tab: `List` with `tab="misc"`, headers Achievement / Profession / Shop / Trading Post / Other; Trading Post rows with `tradingNow` show `L["Trading Post — this month"]`.
- Route tab: header shows character name, `L["Weekly reset in %s"]` and `L["Daily reset in %s"]` (`SecondsToTime`), a "Show completed" checkbox (`db.char.showCompleted`), and the opening flavour line `L["You have %d lockouts left. Saddle up?"]`. Rows from `Route.Build(Data.Route, ctx)`; indentation by `depth`; travel rows italic grey; kill rows show boss → mount, notes, a checkbox (auto rows: checked + disabled + "auto" tag; manual rows: clickable → `Resets.Tick/Untick` with the spec's `reset`), Map button. When zero kill rows remain: `L["%s has reached Oregon. Nothing left to farm until reset."]`.
- `stateOf(mountID)` for the route: `Lockouts.State` → `"done"`/`"open"`, or for `"manual"` → `Resets.IsTicked` ? `"manual-done"` : `"manual-open"`.

- [ ] **Step 1:** Implement. **Step 2 (in game):** Horde and Alliance characters show their capital; a saved raid shows "auto" ticked; manual tick persists through `/reload` and is gone after the daily/weekly reset; owned mounts' steps hidden; during an active holiday its boss is first. **Step 3:** Commit `feat: holidays, misc and route tabs`.

### Task 15: Dev install, release prep

**Files:** Create `tools/link_addon.ps1`. Modify `README.md`.

- `link_addon.ps1 -WowPath "<path>"` creates a directory junction `<WowPath>\_retail_\Interface\AddOns\AzerothTrail` → repo root (refuses if the target exists and is not a junction).
- README: features, install, `/azt` commands, credits section copied from `CREDITS.md`, license.
- Search CurseForge and Wago for "AzerothTrail"; record the result in README's release notes section.

- [ ] **Step 1:** Implement script and README. **Step 2:** `python tools/run_tests.py` and `python -m unittest tools/test_build_data.py` PASS. **Step 3:** Commit `chore: dev install script and release readme`.
