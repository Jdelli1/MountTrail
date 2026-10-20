-- F2 UI: achievement lines in the mount tooltip, the row click dispatcher
-- (Ctrl+left-click preview, Shift+right-click achievement) and the tooltip
-- repaint when the achievement scan finishes. Scan and Game are stubbed.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua" }

local MOUNTS = {
  [262] = { name = "Red Proto-Drake", tab = "misc", section = "achievement" },
  [20] = { name = "Vendor Mount", tab = "misc", section = "other" },
}

local INFO = {
  id = 10, name = "Glory of the Hero", description = "Heroic feats.", completed = false, numCriteria = 2,
  criteria = {
    { text = "Done one", completed = true, quantity = 1, required = 1 },
    { text = "Open one", completed = false, quantity = 0, required = 1 },
  },
}

-- lookup: mountID -> achievementID, status (Scan.Lookup stand-in).
local function loadUI(lookup, game)
  reset_ui_stub()
  local files = toc_lua_files()
  for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  ns.Data.Mounts = MOUNTS
  ns.Data.Lockouts, ns.Data.BossLockouts, ns.Data.Route = {}, {}, {}
  local stubGame = {
    MountInfo = function() return nil end,
    IsOwned = function() return false end,
    Exists = function() return true end,
    Faction = function() return "Alliance" end,
    SavedRows = function() return {} end,
    IsQuestDone = function() return false end,
    IsLfgDone = function() return false end,
    MountDescription = function() return nil end,
    AchievementInfo = function(id) if id == 10 then return INFO end end,
    OpenAchievement = function() return true end,
  }
  for k, v in pairs(game or {}) do stubGame[k] = v end
  for k, v in pairs(stubGame) do ns.Game[k] = v end
  ns.AchievementScan.Lookup = lookup or function() return nil, "none" end
  ns.RarityBridge.Attempts = function() return nil end
  return ns
end

-- A recording GameTooltip; -> tip, calls.
local function recordingTip()
  local calls, tip = {}, {}
  function tip:SetOwner(owner) self.owner = owner end
  function tip:SetText(text) calls[#calls + 1] = { "SetText", text } end
  function tip:AddLine(text, r, g, b, wrap)
    calls[#calls + 1] = { "AddLine", text, r, g, b, wrap }
  end
  function tip:AddDoubleLine(left, right) calls[#calls + 1] = { "AddDoubleLine", left, right } end
  function tip:Show() calls[#calls + 1] = { "Show" } end
  function tip:IsOwned(owner) return self.owner == owner end
  function tip:Hide() self.owner = nil end
  return tip, calls
end

local function addLines(calls)
  local out = {}
  for _, c in ipairs(calls) do
    if c[1] == "AddLine" then out[#out + 1] = c[2] end
    if c[1] == "AddDoubleLine" then out[#out + 1] = c[2] .. "=" .. c[3] end
  end
  return out
end

describe("ui achievements", function()
  describe("RowClickAction", function()
    local ns = loadUI()
    local act = ns.UI.RowClickAction
    it("Ctrl+left-click previews", function()
      eq(act("LeftButton", true, false), "preview")
      eq(act("LeftButton", true, true), "preview")
    end)
    it("Shift+right-click opens the achievement", function()
      eq(act("RightButton", false, true), "achievement")
      eq(act("RightButton", true, true), "achievement")
    end)
    it("left-click sets a waypoint, Shift+left-click opens the map", function()
      eq(act("LeftButton", false, false), "waypoint")
      eq(act("LeftButton", false, true), "map")
    end)
    it("plain and Ctrl right-clicks are reserved", function()
      eq(act("RightButton", false, false), nil)
      eq(act("RightButton", true, false), nil)
      eq(act("MiddleButton", false, false), nil)
    end)
  end)

  describe("OpenMountAchievement / HandleRowClick", function()
    it("opens the mapped achievement", function()
      local opened
      local ns = loadUI(function(id) if id == 262 then return 10, "ready" end return nil, "none" end,
        { OpenAchievement = function(id) opened = id; return true end })
      eq(ns.UI.OpenMountAchievement(262), true)
      eq(opened, 10)
    end)

    it("is false and opens nothing without a known achievement", function()
      local opened = false
      local ns = loadUI(function() return nil, "pending" end,
        { OpenAchievement = function() opened = true; return true end })
      eq(ns.UI.OpenMountAchievement(262), false)
      eq(ns.UI.OpenMountAchievement(20), false)
      eq(opened, false)
    end)

    it("dispatches by button and modifiers", function()
      local opened, previewed
      local ns = loadUI(function() return 10, "ready" end,
        { OpenAchievement = function(id) opened = id; return true end })
      ns.UI.PreviewMount = function(id) previewed = id end
      local ctrl, shift = false, false
      IsControlKeyDown = function() return ctrl end
      IsShiftKeyDown = function() return shift end
      ns.UI.HandleRowClick(262, "RightButton")
      eq(opened, nil, "plain right-click: nothing")
      shift = true
      ns.UI.HandleRowClick(262, "RightButton")
      eq(opened, 10)
      shift, ctrl = false, true
      ns.UI.HandleRowClick(262, "LeftButton")
      eq(previewed, 262)
      ns.UI.HandleRowClick(nil, "LeftButton") -- no mount: must not error
      IsControlKeyDown, IsShiftKeyDown = nil, nil
      ns.UI.HandleRowClick(262, "RightButton") -- missing APIs: must not error
    end)

    it("left-click sets the waypoint, Shift+left-click opens the map", function()
      local ns = loadUI(function() return nil, "none" end)
      local got = {}
      ns.Map = {
        SetWaypoint = function(id, api, boss) got[#got + 1] = { "waypoint", id, boss } end,
        OpenMap = function(id, api, boss) got[#got + 1] = { "map", id, boss } end,
      }
      local shift = false
      IsControlKeyDown = function() return false end
      IsShiftKeyDown = function() return shift end
      ns.UI.HandleRowClick(262, "LeftButton")
      shift = true
      ns.UI.HandleRowClick(263, "LeftButton")
      shift = false
      ns.UI.HandleRowClick(264, "RightButton")
      eq(got, { { "waypoint", 262 }, { "map", 263 } })
      -- A row about a route boss passes it on (Map: that boss's instance).
      ns.UI.HandleRowClick(262, "LeftButton", "Koralon")
      shift = true
      ns.UI.HandleRowClick(263, "LeftButton", "Koralon")
      shift = false
      eq(got[3], { "waypoint", 262, "Koralon" })
      eq(got[4], { "map", 263, "Koralon" })
      ns.Map = nil
      ns.UI.HandleRowClick(262, "LeftButton") -- no Map module: must not error
      ns.Map = { SetWaypoint = function() error("boom") end }
      local reported = {}
      ns.Game.ReportError = function(err) reported[#reported + 1] = tostring(err) end
      ns.UI.HandleRowClick(262, "LeftButton") -- an error is reported, not raised
      eq(#reported, 1)
      IsControlKeyDown, IsShiftKeyDown = nil, nil
    end)
  end)

  describe("Shift+right-click in combat", function()
    it("prints a note and opens nothing", function()
      local opened = false
      local ns = loadUI(function() return 10, "ready" end, {
        OpenAchievement = function() opened = true; return true end,
        InCombat = function() return true end,
      })
      eq(ns.UI.OpenMountAchievement(262), false)
      eq(opened, false)
      eq(ns.addon.printed[#ns.addon.printed], "Can't open achievements in combat")
    end)

    it("opens normally out of combat without printing", function()
      local ns = loadUI(function() return 10, "ready" end, { InCombat = function() return false end })
      eq(ns.UI.OpenMountAchievement(262), true)
      eq(#ns.addon.printed, 0)
    end)
  end)

  describe("AchievementLines", function()
    it("is empty for other mounts and when nothing matched", function()
      local ns = loadUI(function() return nil, "none" end)
      eq(ns.UI.AchievementLines(20), {})
      eq(ns.UI.AchievementLines(262), {})
    end)

    it("says it is looking up while the scan runs", function()
      local ns = loadUI(function() return nil, "pending" end)
      local lines = ns.UI.AchievementLines(262)
      eq(#lines, 1)
      eq(lines[1].text, "Achievement: looking up...")
    end)

    it("shows the achievement and its criteria once known", function()
      local ns = loadUI(function() return 10, "ready" end)
      local texts = {}
      for i, l in ipairs(ns.UI.AchievementLines(262)) do texts[i] = l.text end
      eq(texts, { "Achievement: Glory of the Hero", "Heroic feats.", "  Done one", "  Open one" })
    end)
  end)

  describe("ShowMountTooltip", function()
    it("adds the achievement block and the Shift-right-click hint for achievement mounts", function()
      local ns = loadUI(function(id) if id == 262 then return 10, "ready" end return nil, "none" end)
      local tip, calls = recordingTip()
      local old = GameTooltip
      GameTooltip = tip
      ns.UI.ShowMountTooltip({}, 262)
      GameTooltip = old
      eq(addLines(calls), {
        "Mount", "Achievement reward", "Lockout: —",
        "Achievement: Glory of the Hero", "Heroic feats.", "  Done one", "  Open one",
        "Click to set waypoint",
      })
      local byText = {}
      for _, c in ipairs(calls) do if c[1] == "AddLine" then byText[c[2]] = c end end
      eq({ byText["Achievement: Glory of the Hero"][3], byText["Achievement: Glory of the Hero"][4] }, { 1, 0.82 })
      eq(byText["Heroic feats."][6], true, "description wraps")
      eq({ byText["  Done one"][3], byText["  Done one"][4] }, { 0.25, 1 }, "completed green")
      eq({ byText["  Open one"][3], byText["  Open one"][4] }, { 0.6, 0.6 }, "open grey")
    end)

    it("is unchanged for other mounts", function()
      local ns = loadUI()
      local tip, calls = recordingTip()
      local old = GameTooltip
      GameTooltip = tip
      ns.UI.ShowMountTooltip({}, 20)
      GameTooltip = old
      eq(addLines(calls), { "Mount", "Lockout: —", "Click to set waypoint" })
    end)

    it("repaints the open tooltip when the scan finishes", function()
      local status = "pending"
      local ns = loadUI(function(id)
        if id ~= 262 then return nil, "none" end
        if status == "ready" then return 10, "ready" end
        return nil, status
      end)
      local tip, calls = recordingTip()
      local old = GameTooltip
      GameTooltip = tip
      local owner = {}
      ns.UI.ShowMountTooltip(owner, 262)
      ok(addLines(calls)[4] == "Achievement: looking up...", "pending line")
      status = "ready"
      local first = #calls
      ns.UI.OnAchievementsReady()
      local repainted = {}
      for i = first + 1, #calls do repainted[#repainted + 1] = calls[i] end
      local lines = addLines(repainted)
      eq(lines[#lines], "Click to set waypoint", "repainted")
      local found = false
      for _, l in ipairs(lines) do
        if l == "Achievement: looking up..." then found = true end
      end
      eq(found, false, "repainted with the achievement, no longer looking up")
      -- A recycled row now shows another mount: the repaint follows the row.
      owner.mountID = 20
      local before = #calls
      ns.UI.OnAchievementsReady()
      local slice = {}
      for i = before + 1, #calls do slice[#slice + 1] = calls[i] end
      local after = addLines(slice)
      eq(after, { "Mount", "Lockout: —", "Click to set waypoint" }, "repainted for mount 20")
      -- Once hidden (or owned by something else) nothing is repainted.
      local n = #calls
      ns.UI.HideMountTooltip()
      ns.UI.OnAchievementsReady()
      tip.owner = {}
      ns.UI.OnAchievementsReady()
      GameTooltip = old
      eq(#calls, n)
    end)
  end)
end)
