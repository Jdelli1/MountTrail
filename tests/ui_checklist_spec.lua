-- Pure helpers of UI/ChecklistView.lua (the Checklist tab, F16): the
-- checklist context (UI.RouteContext's stateOf, Journal.Gate, holidays), row
-- text, header labels and tick boxes (UI.RouteCheck / UI.RouteToggle on a
-- one-boss route row). The frames are built in tests/ui_build_spec.lua.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/JournalHome.lua",
  "UI/Tabs.lua", "UI/LockoutHelpers.lua", "UI/ChecklistView.lua" }

local NOW = 1000000

local MOUNTS = {
  [10] = { name = "Drake", exp = "Cataclysm" },
  [11] = { name = "Proto", exp = "Wrath of the Lich King" },
  [12] = { name = "Mammoth", exp = "Wrath of the Lich King" },
  [13] = { name = "Owned", exp = "Classic" },
  [14] = { name = "Alliance Ram", exp = "Classic", faction = "Alliance" },
  [15] = { name = "Rare", exp = "Legion", quest = 500 },
  [16] = { name = "Kodo", exp = "Classic", tab = "holiday", section = "brewfest" },
  [17] = { name = "Old", exp = "Classic", unobtainable = true },
  [18] = { name = "Garn Nighthowl", exp = "Wrath of the Lich King", group = "Rare Spawn" },
}

local ROUTE = {
  {
    title = "Run The Vortex Pinnacle (Dungeon)",
    bosses = { { mount = 10, boss = "Altairus" } },
  },
  {
    title = "Run Vault of Archavon (Raid)",
    bosses = {
      { mount = 12, boss = "Archavon" },
      { mount = 12, boss = "Koralon" },
      { mount = 13, boss = "X" },
      { mount = 14, boss = "Y" },
      { mount = 17, boss = "Z" },
    },
  },
  { title = "Run Utgarde Pinnacle (Dungeon)", bosses = { { mount = 11, boss = "Skadi" } } },
}

local LOCKOUTS = {
  [10] = { instance = 657, boss = "Altairus", difficulties = { 2 }, reset = "daily" },
  [11] = { manual = true, reset = "daily" },
  [12] = { instance = 624, boss = "Archavon the Stone Watcher", difficulties = { 3 }, reset = "weekly" },
  [13] = { manual = true, reset = "weekly" },
  [14] = { manual = true, reset = "weekly" },
  [16] = { lfg = 287, reset = "daily" },
  [17] = { manual = true, reset = "weekly" },
  [18] = { camp = true, zone = "Frostfire Ridge" },
}
local BOSS = {
  Koralon = { instance = 624, boss = "Koralon the Flame Watcher", difficulties = { 3 }, reset = "weekly" },
}
local HOLIDAYS = { brewfest = { title = "Brewfest", mounts = { 16 }, stepTitle = "Queue for Coren Direbrew (Brewfest)" } }

local function loadUI(game)
  reset_ui_stub()
  local files = toc_lua_files()
  for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  local stubGame = {
    MountInfo = function() return nil end,
    IsOwned = function(id) return id == 13 end,
    Exists = function() return true end,
    Faction = function() return "Horde" end,
    SavedRows = function() return {} end,
    IsQuestDone = function() return false end,
    IsLfgDone = function() return false end,
    ActiveHolidays = function() return {} end,
    MountSourceText = function() return nil end,
    Now = function() return NOW end,
    UntilDaily = function() return 3600 end,
    UntilWeekly = function() return 86400 end,
    PlayerName = function() return "Adventurer" end,
  }
  for k, v in pairs(game or {}) do stubGame[k] = v end
  for k, v in pairs(stubGame) do ns.Game[k] = v end
  ns.Data.Mounts = MOUNTS
  ns.Data.Route = ROUTE
  ns.Data.Lockouts = LOCKOUTS
  ns.Data.BossLockouts = BOSS
  ns.Data.Holidays = HOLIDAYS
  return ns
end

local function keys(list)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = e.key end
  return out
end

describe("checklist tab", function()
  it("the route sub-view helpers and setting are gone (the tab is built in ui_build_spec)", function()
    local ns = loadUI()
    eq(ns.UI.RouteSubView, nil)
    eq(ns.UI.SetRouteSubView, nil)
    eq(ns.db.char.routeView, nil, "no sub-view setting")
    eq(ns.db.char.showCompleted, nil, "no Show completed setting")
    eq(type(ns.UI.ChecklistView.Build), "function")
  end)

  it("UI.ChecklistRemaining counts open lockouts in the shown categories", function()
    local ns = loadUI()
    local built = ns.UI.ChecklistBuild(NOW)
    local all = ns.Checklist.Remaining(built, {})
    ok(all > 0, "open lockouts")
    eq(ns.UI.ChecklistRemaining(NOW), all)
    ns.db.char.checklistFilters = { raids = false, dungeons = false, worldbosses = false, rares = false,
      holidays = false, other = false }
    eq(ns.UI.ChecklistRemaining(NOW), 0, "every category hidden")
    ns.db.char.checklistFilters = nil
    eq(ns.UI.ChecklistRemaining(NOW), all, "no filters saved: all shown")
    eq(ns.UI.ChecklistRemaining(), all, "defaults now to Game.Now()")
  end)

  it("feeds the minimap tooltip line", function()
    local ns = loadUI()
    fire_frame_event("PLAYER_LOGIN")
    local launcher = ns.UI.launcher
    ok(launcher, "launcher registered")
    local lines = {}
    launcher.OnTooltipShow({ AddLine = function(_, text) lines[#lines + 1] = text end })
    eq(lines[#lines], string.format("Checklist: %d lockouts left", ns.UI.ChecklistRemaining(NOW)))
  end)
end)

describe("UI.ChecklistBuild", function()
  it("lists this character's lockouts from the route and the data", function()
    local out = loadUI().UI.ChecklistBuild(NOW)
    -- Horde, 13 owned, 14 Alliance-only, 17 unobtainable, 16 Brewfest off.
    eq(keys(out.daily), { 11, 10 }, "Wrath before Cataclysm")
    eq(keys(out.weekly), { 12, "12@Koralon", 15 }, "quest-flag mount 15 from the data")
    eq(out.weekly[3].spec, { quest = 500, reset = "weekly" })
  end)

  it("adds holiday mounts while their holiday is active", function()
    local out = loadUI({ ActiveHolidays = function() return { brewfest = true } end }).UI.ChecklistBuild(NOW)
    eq(keys(out.daily), { 16, 11, 10 })
  end)

  it("reads done states like the route: game lockouts, LFG flags and hand ticks", function()
    local ns = loadUI({
      SavedRows = function()
        return { { instance = 624, difficulty = 3, bosses = { { name = "Koralon the Flame Watcher", killed = true } } } }
      end,
      IsLfgDone = function(id) return id == 287 end,
      ActiveHolidays = function() return { brewfest = true } end,
    })
    ns.db.char.ticks = { [11] = NOW + 10 }
    local out = ns.UI.ChecklistBuild(NOW)
    eq(keys(out.daily), { 10, 16, 11 }, "done ones sink")
    eq(out.daily[2].state, "done")
    eq(out.daily[3].state, "manual-done")
    eq(keys(out.weekly), { 12, 15, "12@Koralon" })
    eq(out.weekly[3].auto, true)
  end)
end)

describe("UI.ChecklistDescription", function()
  it("route rows: boss · instance; holidays: the queue step; else the row description", function()
    local ns = loadUI({ ActiveHolidays = function() return { brewfest = true } end })
    local UI = ns.UI
    local out = UI.ChecklistBuild(NOW)
    eq(UI.ChecklistDescription(out.daily[3]), "Altairus · The Vortex Pinnacle")
    eq(UI.ChecklistDescription(out.daily[1]), "Queue for Coren Direbrew (Brewfest)")
    eq(UI.ChecklistDescription(out.weekly[2]), "Koralon · Vault of Archavon")
    eq(UI.ChecklistDescription(out.weekly[3], "Drop: Big Rare\nZone: Azsuna"), "Drop: Big Rare · Azsuna")
    eq(UI.ChecklistDescription({ id = 99, m = { name = "x" }, boss = "Trash" }), "Trash")
  end)

  it("appends a locked spec's unlock text in grey", function()
    local UI = loadUI().UI
    local text = UI.ChecklistDescription({ id = 10, m = MOUNTS[10], boss = "Altairus",
      title = "Run The Vortex Pinnacle (Dungeon)", locked = true, lockedText = "Needs a key" })
    eq(text, "Altairus · The Vortex Pinnacle  |cff808080(Needs a key)|r")
  end)
end)

describe("UI.ChecklistHeaderLabel", function()
  it("names the reset and its countdown", function()
    local UI = loadUI().UI
    eq(UI.ChecklistHeaderLabel("daily", 3600, 86400), "Daily · resets in " .. UI.FormatDuration(3600))
    eq(UI.ChecklistHeaderLabel("weekly", 3600, 86400), "Weekly · resets in " .. UI.FormatDuration(86400))
  end)
end)

describe("checklist tick boxes", function()
  it("an open game-tracked lockout is display-only; a stored hand tick for it is ignored", function()
    local ns = loadUI()
    local UI = ns.UI
    local out = UI.ChecklistBuild(NOW)
    local koralon = out.weekly[2]
    eq(koralon.key, "12@Koralon")
    eq({ UI.ChecklistCheck(koralon) }, { false, false, false }, "open + tracked by the game: display-only")
    local store = {}
    eq(UI.ChecklistToggle(koralon, store, NOW, 3600, 86400), false)
    eq(store, {})
    ns.db.char.ticks = { ["12@Koralon"] = NOW + 86400 }
    out = UI.ChecklistBuild(NOW)
    local again
    for _, e in ipairs(out.weekly) do if e.key == "12@Koralon" then again = e end end
    eq(again.state, "open", "only the game's lockouts tick a tracked row")
    eq(again.done, false)
  end)

  it("a lockout the game reports done is checked, disabled and auto", function()
    local ns = loadUI({
      SavedRows = function()
        return { { instance = 657, difficulty = 2, bosses = { { name = "Altairus", killed = true } } } }
      end,
    })
    local out = ns.UI.ChecklistBuild(NOW)
    local drake = out.daily[2]
    eq(drake.id, 10)
    eq({ ns.UI.ChecklistCheck(drake) }, { true, false, true })
    local store = {}
    eq(ns.UI.ChecklistToggle(drake, store, NOW, 3600, 86400), false)
    eq(store, {})
  end)

  it("manual daily specs tick until the daily reset under the mountID", function()
    local ns = loadUI()
    local out = ns.UI.ChecklistBuild(NOW)
    local proto = out.daily[1]
    eq(proto.id, 11)
    local store = {}
    ns.UI.ChecklistToggle(proto, store, NOW, 3600, 86400)
    eq(store, { [11] = NOW + 3600 })
  end)
end)

-- F10: a kill that can drop several mounts (a synthetic "Grand Hoarder" boss) is one
-- checklist entry: the boss as the name, "<instance> · <n> mounts" below,
-- and a tooltip listing the mounts it can drop.
local HOARD = { instance = 2579, boss = "Grand Hoarder", difficulties = { 23 }, reset = "weekly" }

-- loadUI plus a Hoard Vault node whose `n` rows (mounts 101..)
-- share Data.BossLockouts["Grand Hoarder"].
local function loadHoard(n, game)
  local ns = loadUI(game)
  local mounts, bosses = {}, {}
  for id, m in pairs(MOUNTS) do mounts[id] = m end
  for i = 1, n do
    mounts[100 + i] = { name = "Legacy " .. i, exp = "Classic" }
    bosses[i] = { mount = 100 + i, boss = "Grand Hoarder" }
  end
  local route = { { title = "Run Hoard Vault (Dungeon)", bosses = bosses } }
  for _, node in ipairs(ROUTE) do route[#route + 1] = node end
  local boss = { ["Grand Hoarder"] = HOARD }
  for k, v in pairs(BOSS) do boss[k] = v end
  ns.Data.Mounts = mounts
  ns.Data.Route = route
  ns.Data.BossLockouts = boss
  return ns
end

local function hoardEntry(out)
  for _, e in ipairs(out.weekly) do
    if e.boss == "Grand Hoarder" then return e end
  end
  return nil
end

local function texts(lines)
  local out = {}
  for _, l in ipairs(lines) do out[#out + 1] = l.left end
  return out
end

describe("checklist lockout groups", function()
  it("one entry per lockout: the Hoarder rows are one weekly entry", function()
    local ns = loadHoard(3)
    local out = ns.UI.ChecklistBuild(NOW)
    local e = hoardEntry(out)
    eq(e.mounts, { 101, 102, 103 })
    eq(e.id, 101)
    eq(e.name, "Grand Hoarder")
    eq(e.grouped, true)
    eq(e.key, "101@Grand Hoarder")
    eq(keys(out.weekly), { "101@Grand Hoarder", 12, "12@Koralon", 15 }, "one row, not three")
  end)

  it("grey line: <instance> · <n> mounts; single-mount entries unchanged", function()
    local ns = loadHoard(3)
    local UI = ns.UI
    local out = UI.ChecklistBuild(NOW)
    eq(UI.ChecklistDescription(hoardEntry(out)), "Hoard Vault · 3 mounts")
    eq(UI.ChecklistDescription(out.weekly[3]), "Koralon · Vault of Archavon")
    -- No instance known: the usual description (the name line already is
    -- the boss), then the count.
    eq(UI.ChecklistDescription({ id = 16, m = MOUNTS[16], grouped = true, mounts = { 16, 1 }, holiday = "brewfest" }),
      "Queue for Coren Direbrew (Brewfest) · 2 mounts")
    eq(UI.ChecklistDescription({ id = 1, m = {}, grouped = true, mounts = { 1, 2 }, boss = "Rukhmar" },
      "Drop: Rukhmar\nZone: Spires of Arak"), "Drop: Rukhmar · Spires of Arak · 2 mounts")
  end)

  it("UI.ChecklistGroupLines: boss, instance, Can drop: and the mounts, then the click hint", function()
    local ns = loadHoard(3)
    local lines = ns.UI.ChecklistGroupLines(hoardEntry(ns.UI.ChecklistBuild(NOW)))
    eq(texts(lines), {
      "Grand Hoarder", "Hoard Vault", "Can drop:", "Legacy 1", "Legacy 2", "Legacy 3",
      "Click to set waypoint",
    })
    eq({ lines[4].r, lines[4].g, lines[4].b }, { 1, 1, 1 }, "mount names in white")
  end)

  it("UI.ChecklistGroupLines: at most 15 mounts, then +N more", function()
    local ns = loadHoard(18)
    local lines = texts(ns.UI.ChecklistGroupLines(hoardEntry(ns.UI.ChecklistBuild(NOW))))
    eq(lines[3], "Can drop:")
    eq(lines[4], "Legacy 1")
    eq(lines[18], "Legacy 15")
    eq(lines[19], "+3 more")
    eq(#lines, 20)
  end)

  it("UI.ShowChecklistGroupTooltip paints the lines on GameTooltip", function()
    local ns = loadHoard(2)
    local calls, tip = {}, {}
    function tip:SetOwner(owner, anchor) calls[#calls + 1] = { "SetOwner", anchor } end
    function tip:SetText(text) calls[#calls + 1] = { "SetText", text } end
    function tip:AddLine(text) calls[#calls + 1] = { "AddLine", text } end
    function tip:Show() calls[#calls + 1] = { "Show" } end
    local old = GameTooltip
    GameTooltip = tip
    ns.UI.ShowChecklistGroupTooltip({}, hoardEntry(ns.UI.ChecklistBuild(NOW)))
    GameTooltip = old
    eq(calls[1], { "SetOwner", "ANCHOR_RIGHT" })
    eq(calls[2], { "SetText", "Grand Hoarder" })
    eq(calls[3], { "AddLine", "Hoard Vault" })
    eq(calls[4], { "AddLine", "Can drop:" })
    eq(calls[#calls], { "Show" })
  end)
end)

-- F14: the checklist's Filter menu (UI.CreateFilterDropdown items) over
-- ns.db.char.checklistFilters = { [category] = false }.
describe("checklist filter menu", function()
  it("AceDB default: every category shown", function()
    local ns = loadUI()
    eq(ns.db.char.checklistFilters, {})
  end)

  it("one Show checkbox per category, then Check all / Uncheck all", function()
    local UI = loadUI().UI
    local items = UI.ChecklistFilterItems({ rares = false })
    local labels, kinds = {}, {}
    for _, item in ipairs(items) do
      kinds[#kinds + 1] = item.kind
      labels[#labels + 1] = item.label or "-"
    end
    eq(kinds, { "checkbox", "divider", "checkbox", "checkbox", "checkbox", "checkbox", "checkbox", "checkbox",
      "checkbox", "divider", "button", "button" })
    eq(labels, { "Show completed", "-", "Show raids", "Show dungeons", "Show world bosses", "Show rares",
      "Show holidays", "Show other", "Show rare spawns (no lockout)", "-", "Check all", "Uncheck all" })
    table.remove(items, 1)
    table.remove(items, 1)
    eq(items[1].key, "raids")
    eq(items[1].checked, true)
    eq(items[4].key, "rares")
    eq(items[4].checked, false)
    eq(items[7].key, "camp")
    eq(items[7].checked, true)
    eq(items[9].action, "checkAll")
    eq(items[10].action, "uncheckAll")
    eq(UI.ChecklistFilterItems(nil)[3].checked, true, "no store: all shown")
  end)

  it("toggling stores only hidden categories", function()
    local UI = loadUI().UI
    local filters = {}
    eq(UI.ToggleChecklistFilter(filters, "raids"), false)
    eq(filters, { raids = false })
    eq(UI.ToggleChecklistFilter(filters, "raids"), true)
    eq(filters, {}, "shown again: nothing stored")
  end)

  it("Check all / Uncheck all / reset, and the defaults test", function()
    local UI = loadUI().UI
    local filters = {}
    eq(UI.ChecklistFiltersAreDefault(filters), true)
    UI.ApplyChecklistFilterAction(filters, "uncheckAll")
    eq(filters, { raids = false, dungeons = false, worldbosses = false, rares = false, holidays = false, other = false,
      camp = false })
    eq(UI.ChecklistFiltersAreDefault(filters), false)
    UI.ApplyChecklistFilterAction(filters, "checkAll")
    eq(filters, {})
    filters.dungeons = false
    UI.ApplyChecklistFilterAction(filters, "reset")
    eq(filters, {})
    eq(UI.ChecklistFiltersAreDefault(nil), true)
  end)
end)

-- F17: live status of event rares on the checklist.
describe("checklist event status", function()
  local function withEvents(game)
    local calls = { pois = 0, contributions = 0 }
    local ns = loadUI(game)
    ns.Game.AreaPOIsForMap = function(map)
      calls.pois = calls.pois + 1
      if map == 1527 then return { 6488 } end
      return {}
    end
    ns.Game.AreaPOIInfo = function(map, id) return { name = "x" } end
    ns.Game.AreaPOISecondsLeft = function(id) if id == 6488 then return 7200 end end
    ns.Game.ContributionsForMap = function(map)
      calls.contributions = calls.contributions + 1
      if map == 14 then return { { id = 116, state = 1, stateName = "Contributing", percent = 0.25 } } end
      return nil
    end
    return ns, calls
  end

  it("UI.EventStatusTexts: one line per event group from the Game wrappers", function()
    local ns = withEvents()
    local texts = ns.UI.EventStatusTexts(NOW)
    eq(texts["Assault: Uldum"], "Uldum: Aqir assault — " .. ns.UI.FormatDuration(7200) .. " left")
    eq(texts["Assault: Vale of Eternal Blossoms"], "Status unknown — click to load")
    eq(texts["Warfront: Arathi"], "Arathi warfront: Contributing (25%)")
    eq(texts["Warfront: Darkshore"], "Status unknown — click to load")
  end)

  it("is cached: re-read after 60 s or once the game reports a change (EventStatusChanged)", function()
    local ns, calls = withEvents()
    ns.UI.EventStatusTexts(NOW)
    local after = calls.pois
    ok(after > 0, "read once")
    ns.UI.EventStatusTexts(NOW + 59)
    eq(calls.pois, after, "cached within 60 s")
    ns.UI.EventStatusTexts(NOW + 60)
    eq(calls.pois, after * 2, "re-read after 60 s")
    local timers = {}
    local oldTimer = C_Timer
    C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay, fn } end }
    ns.UI.EventStatusChanged()
    ns.UI.EventStatusChanged()
    eq(#timers, 1, "one redraw for a burst of events")
    eq(timers[1][1], 2, "throttled to one every 2 s")
    ns.UI.EventStatusTexts(NOW + 61)
    eq(calls.pois, after * 3, "a reported change re-reads at once")
    timers[1][2]() -- the redraw runs (no window: nothing to draw, no error)
    ns.UI.EventStatusChanged()
    eq(#timers, 2, "the next burst schedules again")
    C_Timer = oldTimer
  end)

  it("UI.ChecklistStatusOf maps an entry's mount group to its line", function()
    local ns = withEvents()
    local statusOf = ns.UI.ChecklistStatusOf({ ["Assault: Uldum"] = "U", ["Warfront: Arathi"] = "A" })
    eq(statusOf({ m = { group = "Assault: Uldum" } }), "U")
    eq(statusOf({ m = { group = "Warfront: Arathi" } }), "A")
    eq(statusOf({ m = { group = "Rare Spawn" } }), nil)
    eq(statusOf({}), nil)
  end)

  it("UI.ChecklistEventMap: the zone map of a row whose status is unknown, else nil", function()
    local ns = withEvents()
    local texts = ns.UI.EventStatusTexts(NOW)
    local entry = function(group) return { m = { group = group } } end
    eq(ns.UI.ChecklistEventMap(entry("Assault: Vale of Eternal Blossoms"), texts), 1530)
    eq(ns.UI.ChecklistEventMap(entry("Warfront: Arathi"), texts), nil, "known status: normal click")
    eq(ns.UI.ChecklistEventMap(entry("Assault: Uldum"), texts), nil, "known status: normal click")
    eq(ns.UI.ChecklistEventMap(entry("Warfront: Darkshore"), texts), 62)
    eq(ns.UI.ChecklistEventMap(entry("Rare Spawn"), texts), nil)
    eq(ns.UI.ChecklistEventMap({}, texts), nil)
  end)

  it("a click on an unknown-status row opens its zone map and refreshes the status", function()
    local ns = withEvents()
    local opened, redraws = {}, 0
    ns.Map.OpenZone = function(map) opened[#opened + 1] = map; return true end
    local waypoints = 0
    ns.Map.SetWaypoint = function() waypoints = waypoints + 1 end
    IsControlKeyDown, IsShiftKeyDown = nil, nil
    local before = ns.UI.EventStatusTexts(NOW)
    ns.UI.ChecklistView = { IsShown = function() return true end, Refresh = function() redraws = redraws + 1 end }
    local timers = {}
    local oldTimer = C_Timer
    C_Timer = { After = function(delay, fn) timers[#timers + 1] = fn end }
    ns.UI.HandleRowClick(10, "LeftButton", "Boss", 1530)
    eq(opened, { 1530 })
    eq(waypoints, 0, "no waypoint on an unknown row")
    ok(ns.UI.EventStatusTexts(NOW) ~= before, "cache cleared: re-read")
    timers[1]()
    eq(redraws, 1, "checklist redrawn")
    ns.UI.HandleRowClick(10, "LeftButton", "Boss") -- known status: waypoint
    eq(waypoints, 1)
    eq(opened, { 1530 })
    C_Timer = oldTimer
  end)

  it("UI.ChecklistStatusDesc appends the line in light blue; HeaderText shows a header's", function()
    local ns = withEvents()
    eq(ns.UI.ChecklistStatusDesc("Drop: Ishak", "Uldum: Aqir assault"),
      "Drop: Ishak \194\183 |cff71d5ffUldum: Aqir assault|r")
    eq(ns.UI.ChecklistStatusDesc("", "S"), "|cff71d5ffS|r")
    eq(ns.UI.ChecklistStatusDesc("D", nil), "D")
    eq(ns.UI.HeaderText({ text = "Rares", owned = 0, total = 2, status = "Uldum: Aqir assault" }),
      "Rares  |cff9d9d9d(0/2)|r  |cff71d5ffUldum: Aqir assault|r")
  end)
end)

-- Rare Spawns with no lockout (camp specs): their own checklist group, with a
-- "last checked" box per row (ns.db.char.campChecked).
describe("checklist rare spawns (no lockout)", function()
  it("UI.ChecklistBuild lists camp mounts in their own group", function()
    local out = loadUI().UI.ChecklistBuild(NOW)
    eq(keys(out.camp), { 18 })
    eq(out.camp[1].zone, "Frostfire Ridge")
    eq(out.camp[1].done, false)
  end)

  it("UI.FormatAgo: short minutes / hours / days", function()
    local UI = loadUI().UI
    eq(UI.FormatAgo(0), "1 min")
    eq(UI.FormatAgo(59), "1 min")
    eq(UI.FormatAgo(23 * 60 + 30), "23 min")
    eq(UI.FormatAgo(3600), "1 hr")
    eq(UI.FormatAgo(3 * 3600 + 1800), "3 hr")
    eq(UI.FormatAgo(86400), "1 day")
    eq(UI.FormatAgo(2 * 86400 + 5), "2 days")
    eq(UI.FormatAgo(-30), "1 min", "clock skew: never negative")
  end)

  it("UI.CampMark / CampClear / CampCheckedText over the store", function()
    local UI = loadUI().UI
    local store = {}
    eq(UI.CampCheckedText(store, 18, NOW), nil, "never checked: no text")
    UI.CampMark(store, 18, NOW - 3 * 3600)
    eq(store, { [18] = NOW - 3 * 3600 })
    eq(UI.CampCheckedText(store, 18, NOW), "Last checked 3 hr ago")
    UI.CampMark(store, 18, NOW - 60)
    eq(UI.CampCheckedText(store, 18, NOW), "Last checked 1 min ago", "a second click updates the time")
    UI.CampClear(store, 18)
    eq(store, {})
    eq(UI.CampCheckedText(nil, 18, NOW), nil)
  end)

  it("the camp row's box: always enabled, checked while a time is stored, never auto", function()
    local ns = loadUI()
    local entry = ns.UI.ChecklistBuild(NOW).camp[1]
    eq({ ns.UI.ChecklistCheck(entry, {}) }, { false, true, false })
    eq({ ns.UI.ChecklistCheck(entry, { [18] = NOW }) }, { true, true, false })
  end)

  it("UI.ChecklistCampClick: left marks (again), right clears; other entries are not camp rows", function()
    local ns = loadUI()
    local UI = ns.UI
    local out = UI.ChecklistBuild(NOW)
    local store = {}
    eq(UI.ChecklistCampClick(out.camp[1], store, NOW, "LeftButton"), true)
    eq(store, { [18] = NOW })
    eq(UI.ChecklistCampClick(out.camp[1], store, NOW + 600, "LeftButton"), true)
    eq(store, { [18] = NOW + 600 }, "clicking again updates the time, it does not untick")
    eq(UI.ChecklistCampClick(out.camp[1], store, NOW, "RightButton"), true)
    eq(store, {})
    eq(UI.ChecklistCampClick(out.daily[1], store, NOW, "LeftButton"), false)
    eq(store, {})
  end)

  it("the row line appends the last check; the header label has no reset timer", function()
    local ns = loadUI()
    local UI = ns.UI
    eq(UI.ChecklistCampDesc("Drop: Nok-Karosh · Frostfire Ridge", "Last checked 3 hr ago"),
      "Drop: Nok-Karosh · Frostfire Ridge \194\183 Last checked 3 hr ago")
    eq(UI.ChecklistCampDesc("Drop: X", nil), "Drop: X")
    eq(UI.ChecklistCampDesc("", "Last checked 1 min ago"), "Last checked 1 min ago")
    eq(UI.ChecklistHeaderLabel("camp", 3600, 86400), "Rare Spawns (no lockout)")
    eq(UI.HeaderText({ text = "Gorgrond", left = 3 }), "Gorgrond  |cff9d9d9d(3 left)|r")
  end)

  it("the AceDB default store is empty", function()
    eq(loadUI().db.char.campChecked, {})
  end)
end)
