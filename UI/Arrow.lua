local ADDON, ns = ...

-- Route arrow mode (Ruling R19): instead of (or as well as) reading the Route
-- list, the player can switch to a small movable frame that shows the next
-- route step and an arrow pointing at it, like Questie / RestedXP.
--
--   * ns.db.char.routeMode is "list" (default) or "arrow"; the Route tab's
--     List / Arrow toggle and `/azt arrow` switch it.
--   * Next step: ns.UI.RouteNextStep (UI\RouteView.lua) -> ns.Arrow.NextStep.
--     It is recomputed on every ns.Refresh() (lockout, quest and calendar
--     events already trigger one) through a Frame.lua refresh hook, so the
--     frame follows the route while the main window is closed.
--   * The arrow points at the step's first boss that is not done yet
--     (Arrow.TargetBoss). On a new target: the game's user waypoint is set and
--     super-tracked (the built-in on-screen pointer), and a TomTom waypoint
--     replaces the previous one when TomTom is installed. The Map button only
--     opens the world map there (no second TomTom waypoint).
--   * Skip hides a step for this session only (not saved).
--
-- The pure helpers (Bearing, NextStep, TargetBoss, Mode, SetMode, ToggleMode) are
-- unit-tested in tests/arrow_spec.lua; the frame code is compile-checked only.
-- Every WoW API call below is guarded: a missing API or a nil result hides the
-- arrow, it never raises an error (caught errors are shown only with
-- /azt debug). No protected or secure calls are made.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local Arrow = {}
ns.Arrow = Arrow

local TAU = 2 * math.pi

-- Pure helpers ---------------------------------------------------------------------

-- Coordinate convention (pinned by tests/arrow_spec.lua):
--   * world coordinates are those of C_Map.GetWorldPosFromMapPos, in yards:
--     X grows to the north, Y grows to the west;
--   * facing is GetPlayerFacing(): radians, 0 = north, increasing
--     counter-clockwise (pi/2 = west, pi = south, 3pi/2 = east).
-- Bearing(px, py, tx, ty, facing) -> angle, distance: angle is the target's
-- direction relative to where the player faces, counter-clockwise, in
-- [0, 2pi) (0 = straight ahead, pi/2 = to the left); distance in yards.
-- Texture:SetRotation turns counter-clockwise for positive radians, so a
-- texture that points up at rotation 0 is rotated by `angle` directly.
function Arrow.Bearing(px, py, tx, ty, facing)
  local north, west = tx - px, ty - py
  local angle = (math.atan2(west, north) - (facing or 0)) % TAU
  if angle >= TAU then angle = 0 end -- -tiny % TAU can round up to TAU
  return angle, math.sqrt(north * north + west * west)
end

-- rows: Route.Build rows; skipped: { [row.key] = true } (may be nil).
-- -> the first kill row that is not done, not skipped and whose first boss is
-- not locked, plus the titles of the travel rows above it (its ancestors in
-- the depth-first list, outermost first); nil, {} when none remain.
function Arrow.NextStep(rows, skipped)
  skipped = skipped or {}
  local path, depthCount = {}, 0 -- path[d + 1]: title of the travel row at depth d, or false
  for _, row in ipairs(rows or {}) do
    local depth = row.depth or 0
    for d = depth + 1, depthCount do path[d] = nil end
    depthCount = depth + 1
    if row.kind == "kill" then
      local first = row.bosses and row.bosses[1]
      if row.state ~= "done" and not skipped[row.key] and not (first and first.locked) then
        local hints = {}
        for d = 1, depth do
          if path[d] then hints[#hints + 1] = path[d] end
        end
        return row, hints
      end
      path[depth + 1] = false
    else
      path[depth + 1] = row.title or ""
    end
  end
  return nil, {}
end

-- The boss of a route row the arrow points at: the first one whose state is
-- not "done" / "manual-done" (falls back to the first boss). -> boss, index;
-- nil when the row has no bosses.
function Arrow.TargetBoss(row)
  local bosses = row and row.bosses
  if not (bosses and bosses[1]) then return nil end
  for i, b in ipairs(bosses) do
    if b.state ~= "done" and b.state ~= "manual-done" then return b, i end
  end
  return bosses[1], 1
end

local function charStore(char)
  if char then return char end
  return ns.db and ns.db.char or nil
end

-- Route mode of `char` (default ns.db.char): "arrow" or "list" (anything else).
function Arrow.Mode(char)
  char = charStore(char)
  return (char and char.routeMode == "arrow") and "arrow" or "list"
end

-- Stores `mode` ("arrow", anything else means "list") -> the stored mode.
function Arrow.SetMode(char, mode)
  mode = mode == "arrow" and "arrow" or "list"
  char = charStore(char)
  if char then char.routeMode = mode end
  return mode
end

-- Flips list <-> arrow -> the new mode.
function Arrow.ToggleMode(char)
  char = charStore(char)
  return Arrow.SetMode(char, Arrow.Mode(char) == "arrow" and "list" or "arrow")
end

-- Frame ---------------------------------------------------------------------------

-- Interface\Minimap\MinimapArrow is the minimap's player arrow (points up at
-- rotation 0). If the client cannot load it, SetTexture returns false and the
-- yellow micro-stream arrow is used instead (also an up-pointing arrow).
local ARROW_TEXTURE = "Interface\\Minimap\\MinimapArrow"
local FALLBACK_TEXTURE = "Interface\\Buttons\\UI-MicroStream-Yellow"
local WIDTH, HEIGHT = 220, 90
local ARROW_SIZE = 44
local TEXT_LEFT = 8 + ARROW_SIZE + 6
local BUTTON_WIDTH, BUTTON_HEIGHT = 54, 20
local UPDATE_INTERVAL = 0.1 -- OnUpdate throttle: 10 Hz
local MAX_HINTS = 2 -- innermost travel rows shown on the "via:" line

local frame
local skipped = {} -- session only: { [row.key] = true }
-- target: Map.Resolve result for the targeted boss's mount; world: its world
-- position { c=, x=, y= }, computed once per retarget (nil until it resolves).
local current = { row = nil, key = nil, target = nil, world = nil, tomtomUid = nil }

-- A caught error: dropped, or shown when /azt debug is on (Game.ReportError).
-- The pointer updates at 10 Hz, so a repeat of the last message is dropped.
local lastSwallowed
local function swallowed(err)
  local msg = tostring(err)
  if msg == lastSwallowed then return end
  lastSwallowed = msg
  local game = ns.Game
  if game and type(game.ReportError) == "function" then game.ReportError(msg) end
end

-- pcall(fn, ...) that reports a failure through swallowed() -> good, results.
local function guarded(fn, ...)
  return (function(good, ...)
    if not good then swallowed((...)) end
    return good, ...
  end)(pcall(fn, ...))
end

-- Calls lib[method](...) (no self) when present; its results, or nil on a
-- missing function or an error.
local function try(lib, method, ...)
  if type(lib) ~= "table" or type(lib[method]) ~= "function" then return nil end
  return (function(good, ...)
    if not good then return nil end
    return ...
  end)(guarded(lib[method], ...))
end

-- A number the addon may do arithmetic on (12.x can hand out secret values).
local function plain(v)
  if type(v) ~= "number" then return false end
  if type(issecretvalue) == "function" and issecretvalue(v) then return false end
  return true
end

local function vectorXY(v)
  if type(v) ~= "table" then return nil end
  local x, y = v.x, v.y
  if (x == nil or y == nil) and type(v.GetXY) == "function" then
    local good, vx, vy = guarded(v.GetXY, v)
    if good then x, y = vx, vy end
  end
  if plain(x) and plain(y) then return x, y end
  return nil
end

-- Map position (Vector2D, 0-1) on mapID -> continentID, worldX, worldY or nil.
local function worldOf(mapID, mapPos)
  if not (mapID and mapPos) then return nil end
  local continent, worldPos = try(C_Map, "GetWorldPosFromMapPos", mapID, mapPos)
  local wx, wy = vectorXY(worldPos)
  if not wx then return nil end
  return continent, wx, wy
end

local function playerFacing()
  if type(GetPlayerFacing) ~= "function" then return nil end
  local good, facing = guarded(GetPlayerFacing)
  if good and plain(facing) then return facing end
  return nil
end

-- -> angle, distance; or nil, nil, status text.
local function pointer()
  local t = current.target
  if not (t and t.map and t.x and t.y) then return nil, nil, L["No waypoint for this step"] end
  if not current.world then
    if type(CreateVector2D) ~= "function" then return nil, nil, L["Arrow unavailable here"] end
    local wc, wx, wy = worldOf(t.map, CreateVector2D(t.x / 100, t.y / 100))
    if not wx then return nil, nil, L["Arrow unavailable here"] end
    current.world = { c = wc, x = wx, y = wy }
  end
  local tc, tx, ty = current.world.c, current.world.x, current.world.y
  local mapID = try(C_Map, "GetBestMapForUnit", "player")
  local pc, px, py = worldOf(mapID, mapID and try(C_Map, "GetPlayerMapPosition", mapID, "player"))
  local facing = playerFacing()
  if not (tx and px and facing) then return nil, nil, L["Arrow unavailable here"] end
  if tc ~= nil and pc ~= nil and tc ~= pc then return nil, nil, L["Target is on another continent"] end
  return Arrow.Bearing(px, py, tx, ty, facing)
end

local function updatePointer()
  if not (frame and current.row) then return end
  local good, angle, distance, status = guarded(pointer)
  if good and angle then
    frame.Arrow:SetRotation(angle)
    frame.Arrow:Show()
    frame.Status:SetText(string.format(L["%d yd"], math.floor(distance + 0.5)))
  else
    frame.Arrow:Hide()
    frame.Status:SetText(good and status or L["Arrow unavailable here"])
  end
end

local function targetMount(row)
  local b = Arrow.TargetBoss(row)
  return b and b.mount or nil
end

local function removeTomTom()
  local uid = current.tomtomUid
  current.tomtomUid = nil
  if uid and type(TomTom) == "table" and type(TomTom.RemoveWaypoint) == "function" then
    guarded(TomTom.RemoveWaypoint, TomTom, uid)
  end
end

-- Points the game (user waypoint + super-track) and TomTom at the targeted
-- boss's mount location (Arrow.TargetBoss) when the step or its target
-- changed. retarget(nil) drops the TomTom waypoint; the game's user waypoint
-- is left for the player to clear.
local function retarget(row)
  local key = row and (tostring(row.key) .. ":" .. tostring(targetMount(row))) or nil
  if key == current.key then return end
  current.key = key
  current.target = nil
  current.world = nil
  removeTomTom()
  if not row then return end
  local mountID = targetMount(row)
  if not (mountID and ns.Map and ns.Map.Resolve) then return end
  local good, target = guarded(ns.Map.Resolve, mountID)
  if not (good and type(target) == "table") then return end
  current.target = target
  if not (target.map and target.x and target.y) then return end
  local fx, fy = target.x / 100, target.y / 100
  if try(C_Map, "CanSetUserWaypointOnMap", target.map) == true then
    local point = try(UiMapPoint, "CreateFromCoordinates", target.map, fx, fy)
    if point then
      try(C_Map, "SetUserWaypoint", point)
      try(C_SuperTrack, "SetSuperTrackedUserWaypoint", true)
    end
  end
  if type(TomTom) == "table" and type(TomTom.AddWaypoint) == "function" then
    local added, uid = guarded(TomTom.AddWaypoint, TomTom, target.map, fx, fy,
      { title = row.title, persistent = false })
    if added then current.tomtomUid = uid end
  end
end

local function arrowDB()
  if not ns.db then return nil end
  ns.db.global.arrow = ns.db.global.arrow or {}
  return ns.db.global.arrow
end

local function savePosition(f)
  local db = arrowDB()
  if not db then return end
  local point, _, relPoint, x, y = f:GetPoint(1)
  db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
end

local function restorePosition(f)
  local db = arrowDB()
  f:ClearAllPoints()
  if db and db.point then
    f:SetPoint(db.point, UIParent, db.relPoint or db.point, db.x or 0, db.y or 0)
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  end
end

local function textLine(f, font, y)
  local fs = f:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint("TOPLEFT", f, "TOPLEFT", TEXT_LEFT, y)
  fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, y)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function button(f, label)
  local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  b:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
  b:SetText(label)
  return b
end

local function createFrame()
  local f = CreateFrame("Frame", "AzerothTrailArrow", UIParent, "BackdropTemplate")
  frame = f
  f:Hide()
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetUserPlaced(false)
    savePosition(self)
  end)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.75)
  end
  restorePosition(f)

  local arrow = f:CreateTexture(nil, "ARTWORK")
  arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
  arrow:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -10)
  if arrow:SetTexture(ARROW_TEXTURE) == false then arrow:SetTexture(FALLBACK_TEXTURE) end
  f.Arrow = arrow

  f.Title = textLine(f, UI.Font("GameFontNormal"), -8)
  f.Detail = textLine(f, UI.Font("GameFontHighlightSmall"), -24)
  f.Hint = textLine(f, UI.Font("GameFontDisableSmall"), -38)
  f.Status = textLine(f, UI.Font("GameFontHighlightSmall"), -52)

  local done = f:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormal"))
  done:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
  done:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
  done:SetJustifyH("CENTER")
  done:SetWordWrap(true)
  done:SetTextColor(0.9, 0.8, 0.55)
  f.Done = done

  local skip = button(f, L["Skip"])
  skip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
  skip:SetScript("OnClick", function()
    local row = current.row
    if row and row.key ~= nil then
      skipped[row.key] = true
      ns.Refresh()
    end
  end)
  skip:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["Skip this step for this session"], 1, 1, 1)
    GameTooltip:Show()
  end)
  skip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.SkipButton = skip

  -- The waypoints are already set by retarget: Map only opens the world map
  -- at the target (no second TomTom waypoint).
  local map = button(f, L["Map"])
  map:SetPoint("BOTTOMRIGHT", skip, "BOTTOMLEFT", -2, 0)
  map:SetScript("OnClick", function()
    local t = current.target
    if t and t.map then
      if type(OpenWorldMap) == "function" then guarded(OpenWorldMap, t.map) end
      return
    end
    local id = targetMount(current.row)
    if id and ns.addon and ns.addon.Print then
      local name = ns.Game.MountInfo(id)
      local m = ns.Data and ns.Data.Mounts and ns.Data.Mounts[id]
      ns.addon:Print(string.format(L["No map location for %s"], name or (m and m.name) or tostring(id)))
    end
  end)
  f.MapButton = map

  local elapsedSince = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    elapsedSince = elapsedSince + (elapsed or 0)
    if elapsedSince < UPDATE_INTERVAL then return end
    elapsedSince = 0
    updatePointer()
  end)
  return f
end

local function hintText(hints)
  local n = #hints
  if n == 0 then return "" end
  local shown = {}
  for i = math.max(1, n - MAX_HINTS + 1), n do shown[#shown + 1] = hints[i] end
  return string.format(L["via: %s"], table.concat(shown, " > "))
end

local function paint(f, row, hints)
  local stepShown = row ~= nil
  for _, region in ipairs({ f.Title, f.Detail, f.Hint, f.Status, f.MapButton, f.SkipButton }) do
    region:SetShown(stepShown)
  end
  f.Done:SetShown(not stepShown)
  if not row then
    f.Arrow:Hide()
    f.Done:SetText(UI.RouteFlavour(0, ns.Game.PlayerName()))
    return
  end
  local title, lines = UI.RouteRowLines(row)
  local _, index = Arrow.TargetBoss(row)
  f.Title:SetText(title)
  f.Detail:SetText(lines[index or 1] or lines[1] or "")
  f.Hint:SetText(hintText(hints))
  f.MapButton:SetShown(targetMount(row) ~= nil)
end

local function refresh()
  if not ns.db or Arrow.Mode() ~= "arrow" then
    if frame then frame:Hide() end
    current.row = nil
    retarget(nil)
    return
  end
  local f = frame or createFrame()
  local row, hints = UI.RouteNextStep(ns.Game.Now(), skipped)
  current.row = row
  retarget(row)
  paint(f, row, hints or {})
  f:Show()
  updatePointer()
end

-- Runs on every ns.Refresh() (UI\Frame.lua refresh hook). An error is
-- reported to the error handler instead of breaking the caller's refresh.
if UI.AddRefreshHook then
  UI.AddRefreshHook(function()
    local good, err = pcall(refresh)
    if not good and type(geterrorhandler) == "function" then
      local handler = geterrorhandler()
      if handler then handler(err) end
    end
  end)
end
