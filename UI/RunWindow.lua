local ADDON, ns = ...

-- Tonight's run (Logic/Run.lua): one click on the Checklist's "Start run"
-- (or /mtrail run) orders this character's open daily and weekly lockouts
-- (the categories the Checklist's Filter shows; locked ones and the rare
-- spawns with no lockout left out) into a ride: the player's continent
-- first, nearest stop next (Map.Locate places each stop where its waypoint
-- would go). A small movable window shows the stop to ride to, where it is
-- and what comes after; the waypoint moves along by itself as the game
-- reports each kill (every ns.Refresh), or with Next (a skip: the lockout
-- stays open on the Checklist). The run lives in ns.db.char.run until the
-- next daily reset, so it survives /reload.
--
-- The pure helpers (RunEntries, RunStops, RunIsOpen, RunTitle, RunWhere) are
-- unit-tested in tests/ui_run_spec.lua; the frame code is built under the stub by
-- tests/ui_build_spec.lua. WoW API calls are guarded as in UI/Arrow.lua.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local GREY = "|cff808080"
local DOT = " \194\183 " -- " · "
local UPCOMING = 3

-- Pure helpers -------------------------------------------------------------------

-- Open entries of a Checklist.Build output a run rides to: daily and
-- weekly, not done, not locked, in a category `filters` shows -> { entry },
-- checklist order.
function UI.RunEntries(built, filters)
  local out = {}
  for _, reset in ipairs({ "daily", "weekly" }) do
    for _, e in ipairs((built and built[reset]) or {}) do
      if not e.done and not e.locked and ns.Checklist.Shown(filters, e.category) then
        out[#out + 1] = e
      end
    end
  end
  return out
end

-- Entries -> run stops { key =, id =, boss =, name =, place = locate(id, boss) }
-- (locate may return nil: the stop goes last).
function UI.RunStops(entries, locate)
  local stops = {}
  for i, e in ipairs(entries or {}) do
    stops[i] = { key = e.key, id = e.id, boss = e.boss, name = e.name, place = locate and locate(e.id, e.boss) or nil }
  end
  return stops
end

-- { [entry.key] = entry } of a Checklist.Build output's open entries, and
-- the isOpen(key) a run follows: still listed and not done or locked.
function UI.RunIsOpen(built)
  local open = {}
  for _, reset in ipairs({ "daily", "weekly" }) do
    for _, e in ipairs((built and built[reset]) or {}) do
      if not e.done and not e.locked then open[e.key] = e end
    end
  end
  return function(key) return open[key] ~= nil end, open
end

-- "Tonight's run · 3 / 12".
function UI.RunTitle(behind, total)
  return string.format(L["Tonight's run · %d / %d"], behind, total)
end

-- Where a stop is: "Northrend · Icecrown" (either alone), "" when unknown.
function UI.RunWhere(stop, mapName)
  local place = stop and stop.place
  if type(place) ~= "table" then return "" end
  local area = place.areaName
  local zone = place.map and mapName and mapName(place.map) or nil
  if zone == area then zone = nil end
  if area and zone then return area .. DOT .. zone end
  return area or zone or ""
end

-- Run state --------------------------------------------------------------------------

local function charDB()
  return ns.db and ns.db.char or nil
end

-- This character's run, or nil (none, or past its reset: then dropped).
function UI.CurrentRun(now)
  local char = charDB()
  if not char then return nil end
  local run = char.run
  if run == nil then return nil end
  if ns.Run.Expired(run, now or ns.Game.Now()) then
    char.run = nil
    return nil
  end
  return run
end

local function say(msg)
  local addon = ns.addon
  if addon and addon.Print then addon:Print(msg) end
end

local frame
-- The stop key the waypoint was last set for. false at load: the first
-- paint of a session adopts the current stop without a new waypoint (the
-- game keeps its own over /reload, and lockout data may not be in yet);
-- nil: point at the current stop on the next paint.
local pointedAt = false

local function setWaypoint(stop)
  if not (stop and ns.Map and ns.Map.SetWaypoint) then return end
  local good, err = pcall(ns.Map.SetWaypoint, stop.id, nil, stop.boss)
  if not good and ns.Game.ReportError then ns.Game.ReportError(err) end
end

-- Plans and stores a new run from the checklist as it stands, opens the
-- window and points at the first stop. -> the run, or nil when nothing is
-- open.
function UI.StartRun()
  local char = charDB()
  if not char then return nil end
  local Game = ns.Game
  local now = Game.Now()
  local filters = type(char.checklistFilters) == "table" and char.checklistFilters or nil
  local entries = UI.RunEntries(UI.ChecklistBuild(now), filters)
  if #entries == 0 then
    say(L["No lockouts left to farm on this character."])
    return nil
  end
  local locate = ns.Map and ns.Map.Locate
  local stops = UI.RunStops(entries, locate and function(id, boss)
    local good, place = pcall(locate, id, boss)
    return good and place or nil
  end)
  local here = ns.Map and ns.Map.PlayerWorld and ns.Map.PlayerWorld() or nil
  char.run = ns.Run.New(ns.Run.Plan(stops, here), now, now + (Game.UntilDaily() or 0))
  char.runShown = true
  pointedAt = nil
  say(string.format(L["Tonight's run: %d stops. The waypoint moves on as you clear each one."], #stops))
  ns.Refresh()
  return char.run
end

function UI.StopRun()
  local char = charDB()
  if char then
    char.run = nil
    char.runShown = nil
  end
  pointedAt = nil
  ns.Refresh()
end

-- The Checklist button / `/mtrail run`: a run in progress shows or hides its
-- window; none starts one.
function UI.ToggleRun()
  local char = charDB()
  if not char then return end
  if UI.CurrentRun() then
    char.runShown = not char.runShown
    ns.Refresh()
  else
    UI.StartRun()
  end
end

-- Frame ------------------------------------------------------------------------------

local WIDTH, HEIGHT = 260, 132
local BUTTON_HEIGHT = 20

local function runDB()
  if not ns.db then return nil end
  if type(ns.db.global.runWindow) ~= "table" then ns.db.global.runWindow = {} end
  return ns.db.global.runWindow
end

local function savePosition(f)
  local db = runDB()
  if not db then return end
  local point, _, relPoint, x, y = f:GetPoint(1)
  db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
end

local function restorePosition(f)
  local db = runDB()
  f:ClearAllPoints()
  if db and db.point then
    f:SetPoint(db.point, UIParent, db.relPoint or db.point, db.x or 0, db.y or 0)
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -160)
  end
end

local function line(f, font, anchor, y)
  local fs = f:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint("TOPLEFT", anchor or f, anchor and "BOTTOMLEFT" or "TOPLEFT", anchor and 0 or 10, y)
  fs:SetPoint("RIGHT", f, "RIGHT", -10, 0)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function button(f, label, width, onClick, tip)
  local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  b:SetSize(width, BUTTON_HEIGHT)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  if tip then
    b:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(tip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  end
  return b
end

local function createFrame()
  local f = CreateFrame("Frame", "MountTrailRunWindow", UIParent, "BackdropTemplate")
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
    f:SetBackdropColor(0, 0, 0, 0.8)
  end
  restorePosition(f)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function()
    local char = charDB()
    if char then char.runShown = false end
    f:Hide()
  end)

  f.Title = line(f, "GameFontNormal", nil, -8)
  f.Title:SetPoint("RIGHT", close, "LEFT", -2, 0)
  f.Name = line(f, "GameFontHighlight", f.Title, -6)
  f.Detail = line(f, "GameFontHighlightSmall", f.Name, -3)
  f.Where = line(f, "GameFontDisableSmall", f.Detail, -3)
  f.Then = line(f, "GameFontDisableSmall", f.Where, -6)

  f.StopButton = button(f, L["Stop"], 56, function() UI.StopRun() end, L["End tonight's run"])
  f.StopButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
  f.NextButton = button(f, L["Next"], 56, function()
    local run = UI.CurrentRun()
    if not run then return end
    local isOpen = UI.RunIsOpen(UI.ChecklistBuild(ns.Game.Now()))
    ns.Run.Skip(run, isOpen)
    ns.Refresh()
  end, L["Skip this stop and move the waypoint on (the lockout stays on the Checklist)"])
  f.NextButton:SetPoint("RIGHT", f.StopButton, "LEFT", -4, 0)
  f.GoButton = button(f, L["Waypoint"], 76, function()
    local run = UI.CurrentRun()
    if not run then return end
    local isOpen = UI.RunIsOpen(UI.ChecklistBuild(ns.Game.Now()))
    setWaypoint(ns.Run.Current(run, isOpen))
  end, L["Set the waypoint for this stop again"])
  f.GoButton:SetPoint("RIGHT", f.NextButton, "LEFT", -4, 0)
  f.RetryButton = button(f, L["Retry skipped"], 100, function()
    local run = UI.CurrentRun()
    if not run then return end
    ns.Run.Unskip(run)
    pointedAt = nil
    ns.Refresh()
  end)
  f.RetryButton:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
  return f
end

local function nameOf(stop, open)
  local e = open[stop.key]
  return (e and e.name) or stop.name or tostring(stop.id)
end

local function paint(f, run, built)
  local isOpen, open = UI.RunIsOpen(built)
  local behind, total = ns.Run.Progress(run, isOpen)
  f.Title:SetText(UI.RunTitle(behind, total))
  local stop = ns.Run.Current(run, isOpen)
  local onStop = stop ~= nil
  f.GoButton:SetShown(onStop)
  f.NextButton:SetShown(onStop)
  local skipped = ns.Run.SkippedOpen(run, isOpen)
  f.RetryButton:SetShown(not onStop and skipped > 0)
  if not stop then
    pointedAt = nil
    f.Name:SetText(L["Run complete!"])
    f.Detail:SetText(skipped > 0 and string.format(L["%d skipped stops are still open."], skipped)
      or UI.RouteFlavour(0, ns.Game.PlayerName()))
    f.Where:SetText("")
    f.Then:SetText("")
    return
  end
  local e = open[stop.key]
  f.Name:SetText(nameOf(stop, open))
  local sourceText = ns.Game.MountSourceText and ns.Game.MountSourceText(stop.id) or nil
  f.Detail:SetText(e and UI.ChecklistDescription(e, sourceText) or "")
  f.Where:SetText(UI.RunWhere(stop, ns.Game.MapName))
  local names = {}
  for _, s in ipairs(ns.Run.Upcoming(run, isOpen, UPCOMING)) do names[#names + 1] = nameOf(s, open) end
  f.Then:SetText(#names > 0 and (GREY .. string.format(L["Then: %s"], table.concat(names, ", ")) .. "|r") or "")
  -- A new stop: the waypoint moves on by itself.
  if pointedAt == false then
    pointedAt = stop.key
  elseif stop.key ~= pointedAt then
    pointedAt = stop.key
    setWaypoint(stop)
  end
end

local function refresh()
  local char = charDB()
  local run = char and UI.CurrentRun()
  if not (run and char.runShown) then
    if frame then frame:Hide() end
    return
  end
  local f = frame or createFrame()
  paint(f, run, UI.ChecklistBuild(ns.Game.Now()))
  f:Show()
end

-- Runs on every ns.Refresh() (UI\Frame.lua refresh hook), so the window
-- follows kills while the main window is closed. An error goes to the error
-- handler instead of breaking the caller's refresh.
if UI.AddRefreshHook then
  UI.AddRefreshHook(function()
    local good, err = pcall(refresh)
    if not good and type(geterrorhandler) == "function" then
      local handler = geterrorhandler()
      if handler then handler(err) end
    end
  end)
end
