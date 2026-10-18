-- Pure helpers of UI/ChecklistView.lua: the Route tab's sub-view setting, the
-- checklist context (UI.RouteContext's stateOf, Journal.Gate, holidays), row
-- text, header labels and tick boxes (UI.RouteCheck / UI.RouteToggle on a
-- one-boss route row). The frames are built in tests/ui_build_spec.lua.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/JournalHome.lua",
  "UI/Tabs.lua", "UI/RouteView.lua", "UI/ChecklistView.lua" }

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

describe("route sub-view", function()
  it("defaults to the route and saves the checklist per character", function()
    local ns = loadUI()
    local UI = ns.UI
    eq(ns.db.char.routeView, "route", "AceDB default")
    eq(UI.RouteSubView(ns.db.char), "route")
    eq(UI.SetRouteSubView(ns.db.char, "checklist"), "checklist")
    eq(ns.db.char.routeView, "checklist")
    eq(UI.RouteSubView(ns.db.char), "checklist")
    eq(UI.SetRouteSubView(ns.db.char, "bogus"), "route", "anything else is the route")
    eq(UI.RouteSubView(nil), "route")
    eq(UI.RouteSubView({ routeView = "weird" }), "route")
    eq(ns.db.char.checklistHideDone, false, "Hide done defaults off")
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
  it("hand ticks an open tracked lockout until its reset, keyed like the route", function()
    local ns = loadUI()
    local UI = ns.UI
    local out = UI.ChecklistBuild(NOW)
    local koralon = out.weekly[2]
    eq(koralon.key, "12@Koralon")
    eq({ UI.ChecklistCheck(koralon) }, { false, true, false }, "open + tracked: enabled override")
    local store = {}
    eq(UI.ChecklistToggle(koralon, store, NOW, 3600, 86400), true)
    eq(store, { ["12@Koralon"] = NOW + 86400 }, "weekly spec, per-boss key")
    ns.db.char.ticks = store
    out = UI.ChecklistBuild(NOW)
    local again = out.weekly[3]
    eq(again.key, "12@Koralon")
    eq(again.state, "manual-done")
    eq({ UI.ChecklistCheck(again) }, { true, true, false })
    UI.ChecklistToggle(again, store, NOW, 3600, 86400)
    eq(store, {}, "second click unticks")
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
