local ADDON, ns = ...

-- Route tab: this character's farming route (Logic/Route.lua rows) with the
-- reset timers, a "Show completed" box, a List / Arrow mode toggle,
-- Oregon-Trail flavour lines, a tick box per kill row and a location pin
-- (clicks as on the mount lists, aimed at UI.RouteTargetMount). Also
-- defines ns.UI.RouteRemaining for the minimap tooltip and ns.UI.RouteNextStep
-- for the route arrow (UI\Arrow.lua).
--
-- The pure helpers (RouteContext, RouteRemaining, RouteNextStep, RouteCheck,
-- RouteToggle, RouteTargetMount, RouteRowLines, RouteFlavour, FormatDuration)
-- are unit-tested;
-- the widget code below them is built under a stub by tests/ui_build_spec.lua.
-- Look: a flat header strip, the flat minimal checkbox where the client has
-- it (MinimalCheckboxTemplate, else SettingsCheckboxTemplate, else
-- UICheckButtonTemplate), a two-segment
-- List / Arrow control and striped borderless rows, all in the GameFont
-- families.

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

-- Key of a route boss's hand tick in ns.db.char.ticks: the mountID, or
-- "<mountID>@<routeBoss>" when a per-boss spec (Data.BossLockouts) governs
-- the row, so ticking e.g. the Dawn of the Infinites row does not also tick
-- the same mounts' own dungeon rows.
function UI.RouteTickKey(mountID, routeBoss)
  local per = ns.Data and ns.Data.BossLockouts
  if routeBoss and per and per[routeBoss] then
    return tostring(mountID) .. "@" .. tostring(routeBoss)
  end
  return mountID
end

-- Route.Build context for this character at `now` (epoch seconds, defaults to
-- Game.Now()). stateOf(mountID, routeBoss): "done" when the game reports the
-- governing spec done (the auto path always wins); else "manual-done" while a
-- hand tick (any spec kind: manual specs, or a manual override of an
-- instance / quest / LFG spec) has not expired; else "manual-open" for manual
-- specs and "open" otherwise (untracked mounts too).
function UI.RouteContext(now)
  local Game = ns.Game
  now = now or Game.Now()
  local snap = ns.Lockouts.Snapshot(Game.SavedRows())
  local ticks = ticksStore()
  local function stateOf(mountID, routeBoss)
    local spec = ns.Lockouts.SpecFor(mountID, routeBoss)
    local state = ns.Lockouts.State(spec, snap, Game.IsQuestDone, Game.IsLfgDone)
    if state == "done" then return "done" end
    if ns.Resets.IsTicked(ticks, UI.RouteTickKey(mountID, routeBoss), now) then return "manual-done" end
    if state == "manual" then return "manual-open" end
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

-- Whether the player may tick (or untick) a route boss by hand: a hand tick
-- (manual-done), a manual spec, or an open boss whose spec the game tracks
-- (instance / quest / LFG: a manual override). "done" belongs to the game;
-- untracked mounts have nothing to reset.
local function tickable(b)
  local state = b.state
  if state == "manual-open" or state == "manual-done" then return true end
  if state ~= "open" then return false end
  return ns.Lockouts.SpecFor(b.mount, b.boss) ~= nil
end

-- Tick box for a route row -> checked, enabled, auto.
-- Rows with a tickable boss: enabled, checked when every tickable boss is
-- ticked, never tagged "auto" (the tick is the player's). Other kill rows:
-- disabled (the game decides), checked when done, "auto" when Route.Build
-- says so. Travel rows: nil (no box).
function UI.RouteCheck(row)
  if row.kind ~= "kill" then return nil end
  local anyTickable, allTicked = false, true
  for _, b in ipairs(row.bosses or {}) do
    if tickable(b) then
      anyTickable = true
      if b.state ~= "manual-done" then allTicked = false end
    end
  end
  if anyTickable then return allTicked, true, false end
  return row.state == "done", false, row.auto == true
end

-- Click on a tickable row: untick every tickable boss when all are ticked,
-- else tick them all until the next reset of their spec (`reset`, default
-- daily). Ticks are keyed by UI.RouteTickKey. -> true when the row had a
-- tickable boss. Hand ticks never count attempts (Core\Init.lua reads only
-- the game's lockout data).
function UI.RouteToggle(row, store, now, untilDaily, untilWeekly)
  local checked, enabled = UI.RouteCheck(row)
  if not enabled then return false end
  for _, b in ipairs(row.bosses or {}) do
    if tickable(b) then
      local key = UI.RouteTickKey(b.mount, b.boss)
      if checked then
        ns.Resets.Untick(store, key)
      else
        local spec = ns.Lockouts.SpecFor(b.mount, b.boss)
        local kind = (spec and (spec.reset == "weekly" or spec.reset == "daily")) and spec.reset or "daily"
        ns.Resets.Tick(store, key, kind, now, untilDaily, untilWeekly)
      end
    end
  end
  return true
end

-- The mount a route row's clicks, pin and tooltip are about: the first boss
-- not done by the game or by hand (as the route arrow targets), else the
-- first boss; nil for rows without bosses.
function UI.RouteTargetMount(row)
  local bosses = type(row) == "table" and row.bosses or nil
  if not (type(bosses) == "table" and bosses[1]) then return nil end
  for _, b in ipairs(bosses) do
    if b.state ~= "done" and b.state ~= "manual-done" then return b.mount end
  end
  return bosses[1].mount
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
local PIN_ROOM = UI.PIN_ROOM or 32 -- the location pin (UI.CreatePin) and a gap
local TITLE_RIGHT = PIN_ROOM + 32 -- room for the "auto" tag
local LINE_RIGHT = PIN_ROOM
local KILL_TITLE_Y, TRAVEL_TITLE_Y = -6, -5

-- Flat minimal checkbox of the current panels, else the Settings one, else
-- the classic one (checked lazily: an unused fallback is never looked up).
local function checkTemplate()
  return UI.TemplateChain("MinimalCheckboxTemplate", "SettingsCheckboxTemplate", "UICheckButtonTemplate")
end

local function rowExtent(row)
  local _, lines = UI.RouteRowLines(row)
  if row.kind == "kill" then return KILL_BASE + LINE_HEIGHT * #lines end
  return TRAVEL_HEIGHT + LINE_HEIGHT * #lines
end

local function setupRow(frame)
  -- Borderless rows: a faint stripe on every other row, soft hover highlight.
  local stripe = frame:CreateTexture(nil, "BACKGROUND")
  stripe:SetAllPoints(frame)
  stripe:SetColorTexture(1, 1, 1, 0.025)
  frame.Stripe = stripe
  local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(frame)
  highlight:SetColorTexture(1, 1, 1, 0.07)

  local check = CreateFrame("CheckButton", nil, frame, checkTemplate())
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

  -- Location pin, level with the tick box (kill rows with a location only).
  local pin = UI.CreatePin(frame)
  pin:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(UI.PIN_RIGHT or 8), -5)
  frame.Pin = pin

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

  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  frame:SetScript("OnEnter", function(self)
    local id = UI.RouteTargetMount(self.data)
    if id then UI.ShowMountTooltip(self, id) end
  end)
  frame:SetScript("OnLeave", function() UI.HideMountTooltip() end)
  frame:SetScript("OnClick", function(self, button)
    -- As on the mount lists (UI.RowClickAction): left-click waypoint,
    -- Shift+left-click world map, Ctrl+left-click preview,
    -- Shift+right-click achievement.
    UI.HandleRowClick(UI.RouteTargetMount(self.data), button)
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
    -- right (to the pin) than the title, which leaves room for "auto".
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
  frame.Stripe:SetShown(data.alt == true)

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
    frame.Auto:SetShown(auto and true or false)
    frame.Pin:SetShown(data.pin == true)
  else
    -- Travel hint. WoW ships no italic font, so travel rows are grey only
    -- (the GameFontDisable family).
    frame.Check:Hide()
    frame.Auto:Hide()
    frame.Pin:Hide()
    frame.Title:SetPoint("TOPLEFT", frame, "TOPLEFT", left + 4, TRAVEL_TITLE_Y)
    frame.Title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TITLE_RIGHT, TRAVEL_TITLE_Y)
    frame.Title:SetFontObject("GameFontDisable")
  end
  frame.Title:SetText(titleText)
  for i, text in ipairs(lines) do
    local line = detailLine(frame, i)
    line:SetText(text)
    line:Show()
  end
  for i = #lines + 1, #frame.Lines do frame.Lines[i]:Hide() end
end

local MODE_WIDTH, MODE_HEIGHT = 60, 20

local view = {}
local root, header, scrollBox

local function routeMode()
  return (ns.Arrow and ns.Arrow.Mode()) or "list"
end

-- One segment of the List / Arrow control: selected = gold-tinted fill and
-- GameFontNormalSmall, else a dark fill and GameFontDisableSmall.
local function paintSegment(button, selected)
  if selected then
    button.Bg:SetColorTexture(1, 0.82, 0, 0.22)
    button.Label:SetFontObject("GameFontNormalSmall")
  else
    button.Bg:SetColorTexture(0, 0, 0, 0.35)
    button.Label:SetFontObject("GameFontDisableSmall")
  end
end

local function paintMode()
  local arrow = routeMode() == "arrow"
  paintSegment(header.ArrowMode, arrow)
  paintSegment(header.ListMode, not arrow)
end

local function refresh()
  if not root then return end
  local Game = ns.Game
  local ctx = UI.RouteContext(Game.Now())
  local rows = ns.Route.Build((ns.Data and ns.Data.Route) or {}, ctx)
  for i, row in ipairs(rows) do
    row.alt = i % 2 == 0
    -- The pin: the target mount has a location (UI.HasLocation).
    local id = row.kind == "kill" and UI.RouteTargetMount(row) or nil
    row.pin = id ~= nil and UI.HasLocation(id) or nil
  end
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

  -- Flat header strip with a thin rule underneath.
  local strip = header:CreateTexture(nil, "BACKGROUND")
  strip:SetAllPoints(header)
  strip:SetColorTexture(1, 1, 1, 0.04)
  local rule = header:CreateTexture(nil, "BORDER")
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  rule:SetColorTexture(1, 1, 1, 0.1)

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

  local flavour = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  flavour:SetPoint("TOPLEFT", resets, "BOTTOMLEFT", 0, -8)
  flavour:SetPoint("TOPRIGHT", resets, "BOTTOMRIGHT", 0, -8)
  flavour:SetJustifyH("LEFT")
  header.Flavour = flavour

  local show = CreateFrame("CheckButton", nil, header, checkTemplate())
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

  -- List / Arrow toggle on the resets line's right end (ns.db.char.routeMode):
  -- a flat two-segment control in a 1 px frame.
  local modes = CreateFrame("Frame", nil, header)
  -- 1 px frame + two segments + a 1 px divider between them.
  modes:SetSize(MODE_WIDTH * 2 + 3, MODE_HEIGHT + 2)
  modes:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8, -30)
  UI.FlatBorder(modes, 1, 1, 1, 0.15)
  header.ModeControl = modes

  local function modeButton(mode, label)
    local button = CreateFrame("Button", nil, modes)
    button:SetSize(MODE_WIDTH, MODE_HEIGHT)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(button)
    button.Bg = bg
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    highlight:SetColorTexture(1, 1, 1, 0.08)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    text:SetText(L[label])
    button.Label = text
    button:SetScript("OnClick", function()
      if ns.Arrow then ns.Arrow.SetMode(nil, mode) end
      ns.Refresh()
    end)
    return button
  end
  header.ListMode = modeButton("list", "List")
  header.ListMode:SetPoint("TOPLEFT", modes, "TOPLEFT", 1, -1)
  header.ArrowMode = modeButton("arrow", "Arrow")
  header.ArrowMode:SetPoint("TOPRIGHT", modes, "TOPRIGHT", -1, -1)
  local divider = modes:CreateTexture(nil, "BORDER")
  divider:SetWidth(1)
  divider:SetPoint("TOPLEFT", header.ListMode, "TOPRIGHT", 0, 0)
  divider:SetPoint("BOTTOMLEFT", header.ListMode, "BOTTOMRIGHT", 0, 0)
  divider:SetColorTexture(1, 1, 1, 0.15)

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
