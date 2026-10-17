local ADDON, ns = ...

-- Route tab: this character's farming route (Logic/Route.lua rows) with the
-- reset timers, a "Show completed" box, a List / Arrow mode toggle,
-- Oregon-Trail flavour lines, a tick box per kill row and a Map button. Also
-- defines ns.UI.RouteRemaining for the minimap tooltip and ns.UI.RouteNextStep
-- for the route arrow (UI\Arrow.lua).
--
-- The pure helpers (RouteContext, RouteRemaining, RouteNextStep, RouteCheck,
-- RouteToggle, RouteRowLines, RouteFlavour, FormatDuration) are unit-tested;
-- the widget code below them is compile-checked only.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local GREY = "|cff808080"
local GREEN = "|cff33ff99"

-- Pure helpers -------------------------------------------------------------------

local function memo(fn)
  local cache = {}
  return function(id)
    local v = cache[id]
    if v == nil then
      v = fn(id) and true or false
      cache[id] = v
    end
    return v
  end
end

local function charDB()
  return ns.db and ns.db.char or nil
end

local function ticksStore()
  local char = charDB()
  if not char then return {} end
  char.ticks = char.ticks or {}
  return char.ticks
end

-- Active holidays with a boss to queue for -> { {title=, mounts=} }, sorted by
-- holiday key so the order is stable.
local function holidaySteps()
  local active = ns.Game.ActiveHolidays() or {}
  local holidays = (ns.Data and ns.Data.Holidays) or {}
  local keys = {}
  for key in pairs(active) do
    local h = holidays[key]
    if active[key] and type(h) == "table" and h.stepTitle and type(h.mounts) == "table" and #h.mounts > 0 then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  local steps = {}
  for i, key in ipairs(keys) do
    local h = holidays[key]
    steps[i] = { title = L[h.stepTitle], mounts = h.mounts }
  end
  return steps
end

-- Route.Build context for this character at `now` (epoch seconds, defaults to
-- Game.Now()). stateOf(mountID, routeBoss): the governing spec's state,
-- "done" | "open", or for manual specs "manual-done" (ticked, not expired) |
-- "manual-open"; untracked mounts are "open".
function UI.RouteContext(now)
  local Game = ns.Game
  now = now or Game.Now()
  local snap = ns.Lockouts.Snapshot(Game.SavedRows())
  local ticks = ticksStore()
  local function stateOf(mountID, routeBoss)
    local spec = ns.Lockouts.SpecFor(mountID, routeBoss)
    local state = ns.Lockouts.State(spec, snap, Game.IsQuestDone, Game.IsLfgDone)
    if state == "manual" then
      return ns.Resets.IsTicked(ticks, mountID, now) and "manual-done" or "manual-open"
    end
    if state == "done" then return "done" end
    return "open"
  end
  local char = charDB()
  return {
    faction = Game.Faction(),
    isOwned = memo(Game.IsOwned),
    isQuestDone = Game.IsQuestDone,
    stateOf = stateOf,
    showCompleted = (char and char.showCompleted) == true,
    holidaySteps = holidaySteps(),
  }
end

local function countLeft(rows)
  local n = 0
  for _, row in ipairs(rows) do
    if row.kind == "kill" and row.state ~= "done" then n = n + 1 end
  end
  return n
end

-- Kill rows of this character's route that are not done yet.
function UI.RouteRemaining(now)
  local rows = ns.Route.Build((ns.Data and ns.Data.Route) or {}, UI.RouteContext(now))
  return countLeft(rows)
end

-- Next-step hook for the route arrow (UI\Arrow.lua): the first kill row of
-- this character's route at `now` that is not done, not in `skipped`
-- ({ [row.key] = true }) and not locked -> row, { travel titles above it }
-- (outermost first); nil, {} when none remain.
function UI.RouteNextStep(now, skipped)
  if not (ns.Arrow and ns.Arrow.NextStep) then return nil, {} end
  local rows = ns.Route.Build((ns.Data and ns.Data.Route) or {}, UI.RouteContext(now))
  return ns.Arrow.NextStep(rows, skipped)
end

local function isManual(state)
  return state == "manual-open" or state == "manual-done"
end

-- Tick box for a route row -> checked, enabled, auto.
-- Rows with manual bosses: enabled, checked when every manual boss is ticked,
-- never tagged "auto" (the tick is the player's). Other kill rows: disabled
-- (the game decides), checked when done, "auto" when Route.Build says so.
-- Travel rows: nil (no box).
function UI.RouteCheck(row)
  if row.kind ~= "kill" then return nil end
  local anyManual, allTicked = false, true
  for _, b in ipairs(row.bosses or {}) do
    if isManual(b.state) then
      anyManual = true
      if b.state ~= "manual-done" then allTicked = false end
    end
  end
  if anyManual then return allTicked, true, false end
  return row.state == "done", false, row.auto == true
end

-- Click on a manual row: untick every manual boss when all are ticked, else
-- tick them all until the next reset of their spec (`reset`, default daily).
-- -> true when the row had manual bosses.
function UI.RouteToggle(row, store, now, untilDaily, untilWeekly)
  local checked, enabled = UI.RouteCheck(row)
  if not enabled then return false end
  for _, b in ipairs(row.bosses or {}) do
    if isManual(b.state) then
      if checked then
        ns.Resets.Untick(store, b.mount)
      else
        local spec = ns.Lockouts.SpecFor(b.mount, b.boss)
        local kind = (spec and (spec.reset == "weekly" or spec.reset == "daily")) and spec.reset or "daily"
        ns.Resets.Tick(store, b.mount, kind, now, untilDaily, untilWeekly)
      end
    end
  end
  return true
end

local function mountName(mountID)
  local name = ns.Game.MountInfo(mountID)
  if name then return name end
  local m = ns.Data and ns.Data.Mounts and ns.Data.Mounts[mountID]
  return (m and m.name) or tostring(mountID)
end

-- Display text for a route row -> title, { detail lines }.
-- Kill rows: one line per boss "<boss> → <mount>" (just the mount without a
-- boss), its note in grey, a locked boss's lockedText in grey; then the row
-- notes in grey. Travel rows: the notes only.
function UI.RouteRowLines(row)
  local lines = {}
  if row.kind == "kill" then
    for _, b in ipairs(row.bosses or {}) do
      local text = mountName(b.mount)
      if b.boss and b.boss ~= "" then text = b.boss .. " → " .. text end
      if b.note and b.note ~= "" then text = text .. "  " .. GREY .. b.note .. "|r" end
      if b.locked then
        text = text .. "  " .. GREY .. "(" .. L[b.lockedText or "Locked"] .. ")|r"
      end
      lines[#lines + 1] = text
    end
  end
  if type(row.notes) == "string" and row.notes ~= "" then
    lines[#lines + 1] = GREY .. row.notes .. "|r"
  end
  return row.title or "", lines
end

-- Opening line: lockouts left, or the Oregon line when none are.
function UI.RouteFlavour(remaining, name)
  if remaining > 0 then
    return string.format(L["You have %d lockouts left. Saddle up?"], remaining)
  end
  return string.format(L["%s has reached Oregon. Nothing left to farm until reset."], name or L["Your party"])
end

-- Seconds -> "2 Days 3 Hr" via SecondsToTime (FrameXML), else "2d 3h 4m".
function UI.FormatDuration(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  if type(SecondsToTime) == "function" then
    local text = SecondsToTime(seconds, true)
    if type(text) == "string" and text ~= "" then return text end
  end
  local d = math.floor(seconds / 86400)
  local h = math.floor((seconds % 86400) / 3600)
  local m = math.floor((seconds % 3600) / 60)
  if d > 0 then return string.format("%dd %dh %dm", d, h, m) end
  if h > 0 then return string.format("%dh %dm", h, m) end
  return string.format("%dm", m)
end

-- Widgets ----------------------------------------------------------------------------

local HEADER_HEIGHT = 78
local INDENT = 18
local LINE_HEIGHT = 14
local TRAVEL_HEIGHT = 22
local KILL_BASE = 28
local CHECK_SIZE = 22
local MAP_WIDTH, MAP_RIGHT = 56, 6
local TITLE_RIGHT = MAP_RIGHT + MAP_WIDTH + 40 -- room for the "auto" tag
local LINE_RIGHT = MAP_RIGHT + MAP_WIDTH + 8
local KILL_TITLE_Y, TRAVEL_TITLE_Y = -6, -5

local function rowExtent(row)
  local _, lines = UI.RouteRowLines(row)
  if row.kind == "kill" then return KILL_BASE + LINE_HEIGHT * #lines end
  return TRAVEL_HEIGHT + LINE_HEIGHT * #lines
end

local function firstMount(row)
  local b = row.bosses and row.bosses[1]
  return b and b.mount or nil
end

local function setupRow(frame)
  local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(frame)
  highlight:SetColorTexture(1, 1, 1, 0.06)

  local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  check:SetSize(CHECK_SIZE, CHECK_SIZE)
  check:SetScript("OnClick", function(self)
    local data = frame.data
    local char = charDB()
    if not (data and char) then return end
    char.ticks = char.ticks or {}
    local Game = ns.Game
    UI.RouteToggle(data, char.ticks, Game.Now(), Game.UntilDaily(), Game.UntilWeekly())
    ns.Refresh()
  end)
  frame.Check = check

  local map = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  map:SetSize(MAP_WIDTH, 22)
  map:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -MAP_RIGHT, -3)
  map:SetText(L["Map"])
  map:SetScript("OnClick", function()
    local id = frame.data and firstMount(frame.data)
    if id and ns.Map then ns.Map.Show(id) end
  end)
  frame.Map = map

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)
  frame.Title = title

  local auto = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  auto:SetPoint("LEFT", title, "RIGHT", 6, 0)
  auto:SetText(GREEN .. L["auto"] .. "|r")
  frame.Auto = auto

  -- Detail lines: one single-line FontString each (pooled), so the row
  -- height from rowExtent always matches what is drawn.
  frame.Lines = {}

  frame:RegisterForClicks("LeftButtonUp")
  frame:SetScript("OnEnter", function(self)
    local id = self.data and firstMount(self.data)
    if id then UI.ShowMountTooltip(self, id) end
  end)
  frame:SetScript("OnLeave", function() UI.HideMountTooltip() end)
  frame:SetScript("OnClick", function(self, button)
    local id = self.data and firstMount(self.data)
    if button == "LeftButton" and IsControlKeyDown() and id then UI.PreviewMount(id) end
  end)
end

local function detailLine(frame, i)
  local line = frame.Lines[i]
  if not line then
    line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line:SetJustifyH("LEFT")
    line:SetWordWrap(false)
    line:SetHeight(LINE_HEIGHT)
    -- Same-edge anchor pairs only (a RIGHT anchor would also pin the
    -- vertical centre). Line 1 hangs under the title and reaches further
    -- right (to the Map button) than the title, which leaves room for "auto".
    if i == 1 then
      line:SetPoint("TOPLEFT", frame.Title, "BOTTOMLEFT", 0, -3)
      line:SetPoint("TOPRIGHT", frame.Title, "BOTTOMRIGHT", TITLE_RIGHT - LINE_RIGHT, -3)
    else
      line:SetPoint("TOPLEFT", frame.Lines[i - 1], "BOTTOMLEFT", 0, 0)
      line:SetPoint("TOPRIGHT", frame.Lines[i - 1], "BOTTOMRIGHT", 0, 0)
    end
    frame.Lines[i] = line
  end
  return line
end

local function initRow(frame, data)
  if not frame.Title then setupRow(frame) end
  frame.data = data
  local titleText, lines = UI.RouteRowLines(data)
  local left = 6 + (data.depth or 0) * INDENT

  frame.Title:ClearAllPoints()
  if data.kind == "kill" then
    local checked, enabled, auto = UI.RouteCheck(data)
    frame.Check:ClearAllPoints()
    frame.Check:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -2)
    frame.Check:SetChecked(checked and true or false)
    frame.Check:SetEnabled(enabled and true or false)
    -- A disabled button still eats the mouse: let hover and ctrl-click
    -- reach the row through it.
    frame.Check:EnableMouse(enabled and true or false)
    frame.Check:Show()
    -- Check top is -2, so the title top is -6 (= KILL_TITLE_Y).
    frame.Title:SetPoint("TOPLEFT", frame.Check, "TOPRIGHT", 4, KILL_TITLE_Y + 2)
    frame.Title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TITLE_RIGHT, KILL_TITLE_Y)
    frame.Title:SetFontObject("GameFontNormal")
    frame.Title:SetTextColor(1, 0.82, 0)
    frame.Auto:SetShown(auto and true or false)
    frame.Map:SetShown(firstMount(data) ~= nil)
  else
    -- Travel hint. WoW ships no italic font, so travel rows are grey only.
    frame.Check:Hide()
    frame.Auto:Hide()
    frame.Map:Hide()
    frame.Title:SetPoint("TOPLEFT", frame, "TOPLEFT", left + 4, TRAVEL_TITLE_Y)
    frame.Title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TITLE_RIGHT, TRAVEL_TITLE_Y)
    frame.Title:SetFontObject("GameFontHighlight")
    frame.Title:SetTextColor(0.6, 0.6, 0.6)
  end
  frame.Title:SetText(titleText)
  for i, text in ipairs(lines) do
    local line = detailLine(frame, i)
    line:SetText(text)
    line:Show()
  end
  for i = #lines + 1, #frame.Lines do frame.Lines[i]:Hide() end
end

local MODE_WIDTH = 64

local view = {}
local root, header, scrollBox

local function routeMode()
  return (ns.Arrow and ns.Arrow.Mode()) or "list"
end

-- The List / Arrow toggle: the active mode's button keeps its highlight.
local function paintMode()
  local arrow = routeMode() == "arrow"
  if arrow then
    header.ArrowMode:LockHighlight(); header.ListMode:UnlockHighlight()
  else
    header.ListMode:LockHighlight(); header.ArrowMode:UnlockHighlight()
  end
end

local function refresh()
  if not root then return end
  local Game = ns.Game
  local ctx = UI.RouteContext(Game.Now())
  local rows = ns.Route.Build((ns.Data and ns.Data.Route) or {}, ctx)
  local name = Game.PlayerName()

  header.Name:SetText(name or "")
  header.Resets:SetText(string.format(L["Weekly reset in %s"], UI.FormatDuration(Game.UntilWeekly()))
    .. "    " .. string.format(L["Daily reset in %s"], UI.FormatDuration(Game.UntilDaily())))
  header.ShowCompleted:SetChecked(ctx.showCompleted)
  header.Flavour:SetText(UI.RouteFlavour(countLeft(rows), name))
  paintMode()

  if ScrollBoxConstants then
    scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
  else
    scrollBox:SetDataProvider(CreateDataProvider(rows))
  end
end

local function build(parent)
  root = CreateFrame("Frame", nil, parent)
  root:SetAllPoints(parent)

  header = CreateFrame("Frame", nil, root)
  header:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
  header:SetHeight(HEADER_HEIGHT)

  -- Header lines span the header with same-edge anchor pairs, each chained
  -- under the one above (the Show completed box overlays the name line's
  -- right end; the name is short and left-justified).
  local name = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  name:SetPoint("TOPLEFT", header, "TOPLEFT", 8, -6)
  name:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8, -6)
  name:SetJustifyH("LEFT")
  header.Name = name

  local resets = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  resets:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
  resets:SetPoint("TOPRIGHT", name, "BOTTOMRIGHT", 0, -4)
  resets:SetJustifyH("LEFT")
  header.Resets = resets

  local flavour = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  flavour:SetPoint("TOPLEFT", resets, "BOTTOMLEFT", 0, -8)
  flavour:SetPoint("TOPRIGHT", resets, "BOTTOMRIGHT", 0, -8)
  flavour:SetJustifyH("LEFT")
  flavour:SetTextColor(0.9, 0.8, 0.55)
  header.Flavour = flavour

  local show = CreateFrame("CheckButton", nil, header, "UICheckButtonTemplate")
  show:SetSize(CHECK_SIZE, CHECK_SIZE)
  local showText = show.Text or show.text
  if not showText then
    showText = show:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    showText:SetPoint("LEFT", show, "RIGHT", 2, 0)
  end
  showText:SetText(L["Show completed"])
  show:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8 - (showText:GetStringWidth() or 90), -6)
  show:SetScript("OnClick", function(self)
    local char = charDB()
    if char then char.showCompleted = self:GetChecked() and true or false end
    ns.Refresh()
  end)
  header.ShowCompleted = show

  -- List / Arrow toggle on the resets line's right end (ns.db.char.routeMode).
  local function modeButton(mode, label)
    local button = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    button:SetSize(MODE_WIDTH, 20)
    button:SetText(L[label])
    button:SetScript("OnClick", function()
      if ns.Arrow then ns.Arrow.SetMode(nil, mode) end
      ns.Refresh()
    end)
    return button
  end
  header.ArrowMode = modeButton("arrow", "Arrow")
  header.ArrowMode:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8, -30)
  header.ListMode = modeButton("list", "List")
  header.ListMode:SetPoint("TOPRIGHT", header.ArrowMode, "TOPLEFT", -2, 0)

  scrollBox = CreateFrame("Frame", nil, root, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  scrollBox:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -20, 0)

  local scrollBar = CreateFrame("EventFrame", nil, root, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

  local listView = CreateScrollBoxListLinearView()
  listView:SetElementExtentCalculator(function(_, row) return rowExtent(row) end)
  listView:SetElementFactory(function(factory) factory("Button", initRow) end)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, listView)
end

view.Build = build
view.Refresh = refresh
UI.RegisterView("route", view)
