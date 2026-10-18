local ADDON, ns = ...

-- The Route tab's Checklist sub-view (ns.db.char.routeView = "checklist"):
-- this character's daily and weekly lockouts (Logic/Checklist.lua) under
-- two collapsible headers ("Daily · resets in ..." with done/total, F4's
-- header rows, collapse state in ns.db.global.collapsed under
-- "checklist|daily" / "checklist|weekly"), each split into collapsible
-- expansion sub-headers ("checklist|daily|<exp>", done/total, Checklist.Rows;
-- rows under them indented like the lists'). Rows look like the mount lists
-- (UI.InitMountRow: icon, name, grey "boss · instance" line, pin; click =
-- waypoint, hover = tooltip). Only lockouts the game can't report get a
-- tick box in front of the icon, working like the route's (UI.RouteCheck /
-- UI.RouteToggle on a one-boss route row, so the ticks are the route's own).
-- Done entries disappear on their own (Checklist.Rows); the headers count them.
-- A lockout that drops several mounts (e.g. Malygos' two drakes) is one row named
-- after its boss ("<instance> · <n> mounts", hover lists the mounts:
-- UI.ChecklistGroupLines). UI/RouteView.lua owns the header and the Route ·
-- Checklist switch and calls UI.ChecklistView.Build / Refresh.
--
-- The pure helpers (RouteSubView, SetRouteSubView, ChecklistContext,
-- ChecklistBuild, ChecklistDescription, ChecklistHeaderLabel, ChecklistCheck,
-- ChecklistToggle) are unit-tested in tests/ui_checklist_spec.lua; the
-- widget code is built under a stub by tests/ui_build_spec.lua.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local GREY = "|cff808080"
local DOT = " \194\183 " -- " · "

-- Pure helpers -------------------------------------------------------------------

-- The Route tab's sub-view: "checklist" or "route" (anything else).
function UI.RouteSubView(char)
  return (char and char.routeView == "checklist") and "checklist" or "route"
end

-- Saves the sub-view in `char` (ns.db.char); unknown views become "route".
-- -> the saved view.
function UI.SetRouteSubView(char, view)
  view = view == "checklist" and "checklist" or "route"
  if char then char.routeView = view end
  return view
end

-- Checklist.Build context for this character at `now`: the route tree, the
-- route's stateOf (game lockouts + hand ticks, UI.RouteContext), the
-- Journal gate (known to the client, faction, obtainable, not owned),
-- active holidays and tick keys as the route keys them (UI.RouteTickKey).
function UI.ChecklistContext(now)
  local Game = ns.Game
  local data = ns.Data or {}
  local route = UI.RouteContext(now)
  local memo = UI.Memo
  local isOwned, exists = memo(Game.IsOwned), memo(Game.Exists)
  local faction = route.faction
  return {
    tree = data.Route or {},
    mounts = data.Mounts or {},
    specFor = ns.Lockouts.SpecFor,
    stateOf = route.stateOf,
    gate = function(id, m) return ns.Journal.Gate(id, m, isOwned, exists, faction) end,
    faction = faction,
    holidays = data.Holidays or {},
    active = Game.ActiveHolidays() or {},
    expansions = data.Expansions or {},
    keyOf = UI.RouteTickKey,
    bossLockouts = data.BossLockouts or {},
    isQuestDone = Game.IsQuestDone,
    nameOf = function(id, m) return Game.MountInfo(id) or m.name end,
  }
end

-- This character's checklist at `now` (Checklist.Build).
function UI.ChecklistBuild(now)
  return ns.Checklist.Build(UI.ChecklistContext(now))
end

-- Grey row line of an entry: "<boss> · <instance>" for route rows (either
-- alone when the other is unknown), the holiday's queue step for holiday
-- mounts, else UI.RowDescription over `sourceText` (the client's source
-- text). A lockout that drops several mounts (entry.grouped: its name line
-- is the boss) reads "<instance> · <n> mounts" instead (the holiday step or
-- row description when the instance is unknown). A locked spec adds its
-- unlock text in grey.
function UI.ChecklistDescription(entry, sourceText)
  local boss = entry.boss
  if boss == "" then boss = nil end
  local instance = UI.InstanceName(entry.title)
  local grouped = entry.grouped and entry.mounts and #entry.mounts > 1
  if grouped then boss = nil end
  local text
  if boss and instance then
    text = boss .. DOT .. instance
  elseif boss or instance then
    text = boss or instance
  else
    local h = entry.holiday and ns.Data and ns.Data.Holidays and ns.Data.Holidays[entry.holiday]
    if h and h.stepTitle then
      text = L[h.stepTitle]
    else
      text = UI.RowDescription(entry.id, sourceText) or ""
    end
  end
  if grouped then
    local count = string.format(L["%d mounts"], #entry.mounts)
    text = (text ~= "" and (text .. DOT) or "") .. count
  end
  if entry.locked then
    text = text .. "  " .. GREY .. "(" .. L[entry.lockedText or "Locked"] .. ")|r"
  end
  return text
end

local LABELS = { daily = "Daily", weekly = "Weekly" }

-- Header label of a reset group: "Daily · resets in 1 Hr".
function UI.ChecklistHeaderLabel(reset, untilDaily, untilWeekly)
  local seconds = reset == "weekly" and untilWeekly or untilDaily
  return string.format(L["%s · resets in %s"], L[LABELS[reset] or reset], UI.FormatDuration(seconds))
end

local GROUP_MAX = 15
local WHITE = { 1, 1, 1 }
local SOFT = { 0.9, 0.9, 0.9 }
local GOLD = { 1, 0.82, 0 }
local DIM = { 0.6, 0.6, 0.6 }
local HINT = { 0.5, 0.9, 0.5 }

local function tipLine(text, color, wrap)
  return { left = text, r = color[1], g = color[2], b = color[3], wrap = wrap }
end

-- Tooltip lines of a lockout that drops several mounts: the entry's name (the
-- boss, title line), its instance, "Can drop:" and each member mount (white;
-- at most 15, then "+N more"), the click hints (click = the first mount).
-- -> { { left=, r=, g=, b=, wrap= } }.
function UI.ChecklistGroupLines(entry)
  local lines = { tipLine(entry.name or tostring(entry.id), WHITE) }
  local instance = UI.InstanceName(entry.title)
  if instance then lines[#lines + 1] = tipLine(instance, SOFT) end
  lines[#lines + 1] = tipLine(L["Can drop:"], GOLD)
  local mounts, names = entry.mounts or { entry.id }, entry.names or {}
  for i, id in ipairs(mounts) do
    if i > GROUP_MAX then
      lines[#lines + 1] = tipLine(string.format(L["+%d more"], #mounts - GROUP_MAX), DIM)
      break
    end
    local name = names[i] or (ns.Game.MountInfo and ns.Game.MountInfo(id)) or tostring(id)
    lines[#lines + 1] = tipLine(name, WHITE)
  end
  lines[#lines + 1] = tipLine(L["Click: waypoint · Shift-click: map · Ctrl-click: preview"], HINT)
  return lines
end

-- Paints UI.ChecklistGroupLines on GameTooltip beside `owner` (a row's
-- tooltip hook; UI.HideMountTooltip hides it).
function UI.ShowChecklistGroupTooltip(owner, entry)
  local tip = GameTooltip
  if not (tip and entry) then return end
  local lines = UI.ChecklistGroupLines(entry)
  tip:SetOwner(owner, "ANCHOR_RIGHT")
  tip:SetText(lines[1].left, lines[1].r, lines[1].g, lines[1].b)
  for i = 2, #lines do
    local l = lines[i]
    tip:AddLine(l.left, l.r, l.g, l.b, l.wrap)
  end
  tip:Show()
end

-- An entry as a one-boss route kill row, for UI.RouteCheck / UI.RouteToggle.
local function tickRow(entry)
  return {
    kind = "kill",
    bosses = { { mount = entry.id, boss = entry.boss, state = entry.state } },
    state = entry.done and "done" or "open",
    auto = entry.auto == true,
  }
end

-- Tick box of an entry -> checked, enabled, auto (UI.RouteCheck).
function UI.ChecklistCheck(entry)
  return UI.RouteCheck(tickRow(entry))
end

-- Click on an entry's tick box: UI.RouteToggle (hand tick until the spec's
-- reset, keyed by UI.RouteTickKey; a second click unticks). -> true when
-- the entry was tickable.
function UI.ChecklistToggle(entry, store, now, untilDaily, untilWeekly)
  return UI.RouteToggle(tickRow(entry), store, now, untilDaily, untilWeekly)
end

-- Widgets ----------------------------------------------------------------------------

local CHECK_SIZE = 22
local CHECK_LEFT = 6
local ICON_LEFT = CHECK_LEFT + CHECK_SIZE + 4
local SUB_OFFSET = 16 -- under an expansion sub-header (UI/List.lua: sub-header indicator 22 vs 6)
local HEADER_HEIGHT = 24 -- UI/List.lua section headers
local SUB_HEADER_HEIGHT = 20 -- UI/List.lua sub-headers

local view = {}
UI.ChecklistView = view

local frame, scrollBox, empty

local function charDB()
  return ns.db and ns.db.char or nil
end

local function collapsedDB()
  local global = ns.db and ns.db.global
  if not global then return nil end
  if type(global.collapsed) ~= "table" then global.collapsed = {} end
  return global.collapsed
end

local function onTick(self)
  local row = self:GetParent()
  local entry = row and row.entry
  local char = charDB()
  if not (entry and char) then return end
  char.ticks = char.ticks or {}
  local Game = ns.Game
  local toggled = UI.ChecklistToggle(entry, char.ticks, Game.Now(), Game.UntilDaily(), Game.UntilWeekly())
  if UI.DebugTrace then
    UI.DebugTrace("tick box on mount %s (checklist) -> %s", tostring(entry.id), toggled and "toggled" or "not tickable")
  end
  ns.Refresh()
end

-- A mount row (UI.InitMountRow) with a tick box in front of the icon; done
-- entries are dimmed (GameFontDisable name, grey icon).
local function initRow(row, data)
  UI.InitMountRow(row, data)
  if not row.Check then
    local check = CreateFrame("CheckButton", nil, row,
      UI.TemplateChain("MinimalCheckboxTemplate", "SettingsCheckboxTemplate", "UICheckButtonTemplate"))
    check:SetSize(CHECK_SIZE, CHECK_SIZE)
    check:SetScript("OnClick", onTick)
    row.Check = check
  end
  row.entry = data.entry
  -- Recycled rows: re-anchor for this row's depth (indented under a sub-header).
  local inset = data.depth == 2 and SUB_OFFSET or 0
  row.Check:ClearAllPoints()
  row.Check:SetPoint("LEFT", row, "LEFT", CHECK_LEFT + inset, 0)
  row.Icon:SetPoint("LEFT", row, "LEFT", ICON_LEFT + inset, 0)
  local checked, enabled = UI.ChecklistCheck(data.entry)
  row.Check:SetChecked(checked and true or false)
  row.Check:SetEnabled(enabled and true or false)
  row.Check:EnableMouse(enabled and true or false)
  -- Only lockouts the game can't report get a box; the icon keeps its place.
  row.Check:SetShown(enabled and true or false)
  if data.done then
    row.Name:SetFontObject("GameFontDisable")
    row.Icon:SetDesaturated(true)
  end
end

local function toggleHeader(key)
  local store = collapsedDB()
  if not store then return end
  UI.ToggleCollapsed(store, key)
  ns.Refresh()
end

local function initHeader(f, data)
  f.onToggle = toggleHeader
  UI.InitListHeader(f, data)
end

-- Builds the sub-view under `top` (the Route header) inside `parent`;
-- hidden until shown. -> the container frame.
function view.Build(parent, top)
  frame = CreateFrame("Frame", nil, parent)
  frame:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -2)
  frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

  scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  scrollBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 0)
  frame.ScrollBox = scrollBox

  local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

  local listView = CreateScrollBoxListLinearView()
  listView:SetElementExtentCalculator(function(_, row)
    if row.header then return row.depth == 2 and SUB_HEADER_HEIGHT or HEADER_HEIGHT end
    return UI.MOUNT_ROW_HEIGHT
  end)
  listView:SetElementFactory(function(factory, row)
    if row.header then
      factory("Frame", initHeader)
    else
      factory("Button", initRow)
    end
  end)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, listView)

  empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  empty:SetPoint("CENTER", scrollBox, "CENTER", 0, 0)
  empty:SetText(L["No lockouts left to farm on this character."])
  empty:Hide()
  frame.Empty = empty

  frame:Hide()
  return frame
end

-- Redraws the checklist (when built). -> the Checklist.Build output, for the
-- header's flavour line; nil before Build.
function view.Refresh()
  if not frame then return nil end
  local Game = ns.Game
  local built = UI.ChecklistBuild(Game.Now())
  local untilDaily, untilWeekly = Game.UntilDaily(), Game.UntilWeekly()
  local rows = ns.Checklist.Rows(built, {
    collapsed = collapsedDB() or {},
    label = function(reset) return UI.ChecklistHeaderLabel(reset, untilDaily, untilWeekly) end,
  })
  local sourceText = UI.MemoText(Game.MountSourceText)
  local n = 0
  for _, row in ipairs(rows) do
    if row.header then
      n = 0
    else
      n = n + 1
      local e = row.entry
      row.owned = false
      row.alt = n % 2 == 0
      row.desc = UI.ChecklistDescription(e, sourceText(e.id))
      row.tag = e.auto and L["auto"] or nil
      row.pin = UI.LocationIcon(e.id, e.boss)
      -- The click goes to this lockout's boss (its instance's entrance) and
      -- the hover's lockout line is that boss's (UI.InitMountRow).
      row.routeBoss = e.boss
      if e.grouped then
        -- One lockout, several mounts: the boss names the row and the
        -- tooltip lists what it can drop (UI.InitMountRow's hooks).
        row.name = e.name
        row.tooltip = function(owner) UI.ShowChecklistGroupTooltip(owner, e) end
      end
    end
  end
  if ScrollBoxConstants then
    scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
  else
    scrollBox:SetDataProvider(CreateDataProvider(rows))
  end
  empty:SetShown(#rows == 0)
  return built
end

function view.SetShown(shown)
  if frame then frame:SetShown(shown and true or false) end
end
