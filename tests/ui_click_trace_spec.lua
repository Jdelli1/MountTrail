-- /azt debug click trace (UI.HandleRowClick): with debug on, every mount-row
-- click prints what it saw and what happened straight to chat (not through
-- the error handler, which BugSack-style addons capture silently).

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua" }

local function loadUI(debug)
  reset_ui_stub()
  local files = toc_lua_files()
  for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  ns.db.global.debug = debug
  local printed = {}
  ns.addon.Print = function(_, msg) printed[#printed + 1] = msg end
  return ns, printed
end

describe("row click trace", function()
  it("prints the click and the waypoint result when debug is on", function()
    local ns, printed = loadUI(true)
    ns.Map.SetWaypoint = function(id) return "Dustwallow Marsh", "entrance" end
    ns.UI.HandleRowClick(349, "LeftButton")
    eq(printed, {
      "debug: click LeftButton on mount 349 -> waypoint",
      "debug: SetWaypoint(349) -> entrance, Dustwallow Marsh",
    })
  end)

  it("prints a caught error to chat when debug is on", function()
    local ns, printed = loadUI(true)
    ns.Map.SetWaypoint = function() error("boom") end
    ns.UI.HandleRowClick(349, "LeftButton")
    eq(#printed, 2)
    ok(printed[2]:find("debug: SetWaypoint(349) failed: ", 1, true) == 1, printed[2])
    ok(printed[2]:find("boom", 1, true) ~= nil, printed[2])
  end)

  it("reports a click that has no mount", function()
    local ns, printed = loadUI(true)
    ns.UI.HandleRowClick(nil, "LeftButton")
    eq(printed, { "debug: click LeftButton on a row with no mount" })
  end)

  it("prints nothing when debug is off", function()
    local ns, printed = loadUI(false)
    ns.Map.SetWaypoint = function() return "X", "pin" end
    ns.UI.HandleRowClick(349, "LeftButton")
    ns.UI.HandleRowClick(nil, "LeftButton")
    eq(printed, {})
  end)
end)
