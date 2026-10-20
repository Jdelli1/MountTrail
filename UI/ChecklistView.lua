local ADDON, ns = ...

-- The Checklist tab (F16: it replaced the retired Route tab): this
-- character's daily and weekly lockouts (Logic/Checklist.lua) under a flat
-- header (character name, reset timers, the Oregon-Trail flavour line with
-- the lockouts left, and a Filter button top right). The list has two
-- collapsible headers ("Daily · resets in ..." with done/total, F4's
-- header rows, collapse state in ns.db.global.collapsed under
-- "checklist|daily" / "checklist|weekly"), each split into collapsible
-- expansion sub-headers ("checklist|daily|<exp>", done/total, Checklist.Rows;
-- rows under them indented like the lists'), each split again into
-- collapsible category headers (Raids, Dungeons, World bosses, Rares,
-- Holidays, Other: "checklist|daily|<exp>|<category>", one step further in).
-- The Filter button (view.CreateFilterDropdown: UI.CreateFilterDropdown
-- with "Show raids" ... "Show other", saved per character in
-- ns.db.char.checklistFilters) hides categories; every count follows it.
-- Rows look like the mount lists
-- (UI.InitMountRow: icon, name, grey "boss · instance" line, pin; click =
-- waypoint, hover = tooltip). Only lockouts the game can't report get a
-- tick box in front of the icon (UI.RouteCheck / UI.RouteToggle on a
-- one-boss route row, UI\LockoutHelpers.lua).
-- Done entries disappear on their own (Checklist.Rows); the headers count them.
-- A lockout that drops several mounts (e.g. Malygos' two drakes) is one row named
-- after its boss ("<instance> · <n> mounts", hover lists the mounts:
-- UI.ChecklistGroupLines). Rares of the N'Zoth assaults and the Arathi /
-- Darkshore warfronts add a light-blue live status to their grey line (F17,
-- UI.EventStatusTexts over Logic/Events.lua), and a header whose open entries
-- all share one shows it too. Also defines UI.ChecklistRemaining for the
-- minimap tooltip.
-- Layout as the other tabs: the list on the left, the detail pane
-- (UI/DetailPane.lua) on the right showing the selected row's mount (a plain
-- left-click selects; modifier clicks and the tick boxes keep their
-- actions; no hover tooltip, no location icon). The header strip: the
-- character's name, a summary line ("Daily: 6 left, resets in 9 hr" ...),
-- the flavour line, then chips All / Daily / Weekly / Rare spawns (with
-- what is left) that show one group or all (ns.db.char.checklistShow), and
-- a "Pop out rares" button (UI.ToggleRareTracker) beside Filter.
-- After Daily and Weekly, "Rare spawns (no lockout)" lists the camp specs
-- (rares with no kill flag and no reset) by expansion and zone, headers
-- counting the mounts left ("(12 left)"); each row's box records when the
-- player last checked the spawn (UI.ChecklistCampClick, right-click clears),
-- shown as "Last checked 3 hr ago" and aged by a 60 s ticker while the tab
-- is on screen. The Filter's "Show rare spawns (no lockout)" hides the group.
--
-- The pure helpers (ChecklistContext, ChecklistBuild, ChecklistRemaining,
-- ChecklistDescription, ChecklistHeaderLabel, ChecklistCheck,
-- ChecklistToggle, ChecklistFilterItems, ToggleChecklistFilter,
-- ApplyChecklistFilterAction, ChecklistFiltersAreDefault) are unit-tested in
-- tests/ui_checklist_spec.lua; the widget code is built under a stub by
-- tests/ui_build_spec.lua.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local GREY = "|cff808080"
local DOT = " \194\183 " -- " · "

-- Pure helpers -------------------------------------------------------------------

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

-- Lockouts this character has left at `now` in the categories its Filter
-- menu shows (the header's flavour line and the minimap tooltip).
function UI.ChecklistRemaining(now)
  local char = ns.db and ns.db.char
  local filters = char and type(char.checklistFilters) == "table" and char.checklistFilters or nil
  return ns.Checklist.Remaining(UI.ChecklistBuild(now), filters)
end

-- Event rares' live status (F17) -------------------------------------------------
-- Rows whose mount is in a Data/Events.lua group (N'Zoth assaults in Uldum
-- and the Vale, the Arathi / Darkshore warfronts) get that group's line from
-- Logic/Events.lua; a header whose open entries all share one shows it too
-- (Checklist.Rows opts.status). Read through the Game wrappers at most once
-- a minute, sooner when the game reports a change (AREA_POIS_UPDATED,
-- CONTRIBUTION_COLLECTOR_UPDATE: UI.EventStatusChanged, Core/Init.lua).

local STATUS_TTL = 60 -- seconds a read stays fresh
local STATUS_THROTTLE = 2 -- seconds between redraws for reported changes
local STATUS_COLOR = "|cff71d5ff" -- light blue: information, not a done / open state
local statusCache = { texts = nil, at = nil }
local redrawPending = false

-- { [group key] = line } at `now` (default Game.Now()), cached for a minute.
function UI.EventStatusTexts(now)
  local Game = ns.Game
  now = now or Game.Now()
  local at = statusCache.at
  if statusCache.texts and at and now >= at and now - at < STATUS_TTL then return statusCache.texts end
  statusCache.texts = ns.Events.Statuses(ns.Data and ns.Data.EventGroups, {
    poisForMap = Game.AreaPOIsForMap,
    poiInfo = Game.AreaPOIInfo,
    secondsLeft = Game.AreaPOISecondsLeft,
    contributionsForMap = Game.ContributionsForMap,
    formatDuration = UI.FormatDuration,
  })
  statusCache.at = now
  return statusCache.texts
end

-- The game reported a change: the next read is fresh, and the checklist (when
-- on screen) redraws once within STATUS_THROTTLE seconds, however many events
-- arrive (AREA_POIS_UPDATED fires often).
function UI.EventStatusChanged()
  statusCache.texts = nil
  if redrawPending then return end
  redrawPending = true
  local function redraw()
    redrawPending = false
    local checklist = UI.ChecklistView
    if checklist and checklist.IsShown() then checklist.Refresh() end
  end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(STATUS_THROTTLE, redraw)
  else
    redraw()
  end
end

-- Checklist.Rows opts.status over `texts` (UI.EventStatusTexts): an entry's
-- line by its mount's event group, nil for other entries.
function UI.ChecklistStatusOf(texts)
  local groups = ns.Data and ns.Data.EventGroups
  return function(entry)
    local key = ns.Events.GroupOf(entry and entry.m, groups)
    return key and texts and texts[key] or nil
  end
end

-- The UiMap a click on this entry's row opens: its event zone while the
-- group's line reads "status unknown", else nil (the normal waypoint click).
function UI.ChecklistEventMap(entry, texts)
  local key, def = ns.Events.GroupOf(entry and entry.m, ns.Data and ns.Data.EventGroups)
  if not key or not ns.Events.IsUnknown(texts and texts[key]) then return nil end
  return ns.Events.ZoneMap(def)
end

local mapHooked = false
-- Opens the event zone's world map so the client loads its data, and drops the
-- cached lines so the checklist redraws once the data arrives. Not in combat
-- (Map.OpenZone says so). The map closing also invalidates the cache (guarded,
-- hooked once).
function UI.OpenEventMap(uiMapID)
  local map = ns.Map
  if not (map and type(map.OpenZone) == "function") then return false end
  local good, opened = pcall(map.OpenZone, uiMapID)
  if not good then
    if ns.Game and ns.Game.ReportError then ns.Game.ReportError(opened) end
    return false
  end
  if not opened then return false end
  if not mapHooked and type(WorldMapFrame) == "table" and type(WorldMapFrame.HookScript) == "function" then
    mapHooked = pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnHide", function() UI.EventStatusChanged() end)
  end
  UI.EventStatusChanged()
  return true
end

-- A row's grey line with its status appended in light blue.
function UI.ChecklistStatusDesc(desc, status)
  if not status or status == "" then return desc end
  local colored = STATUS_COLOR .. status .. "|r"
  if not desc or desc == "" then return colored end
  return desc .. DOT .. colored
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

-- Header label of a reset group: "Daily · resets in 1 Hr"; the rare spawns
-- with no lockout ("camp") have no reset: "Rare spawns (no lockout)".
function UI.ChecklistHeaderLabel(reset, untilDaily, untilWeekly)
  if reset == "camp" then return L["Rare spawns (no lockout)"] end
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
  lines[#lines + 1] = tipLine(L["Click to set waypoint"], HINT)
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

-- Filter menu (F14) -------------------------------------------------------------
-- Categories as Logic/Checklist.lua orders them; ns.db.char.checklistFilters
-- = { [category] = false } stores only hidden ones (missing = shown).

local FILTER_LABELS = {
  raids = "Show raids", dungeons = "Show dungeons", worldbosses = "Show world bosses",
  rares = "Show rares", holidays = "Show holidays", other = "Show other",
  camp = "Show rare spawns (no lockout)",
}

-- UI.CreateFilterDropdown items: a "Show <category>" checkbox per filter key
-- (Checklist.FILTERS: the categories, then the rare spawns with no lockout),
-- then Check all / Uncheck all. `filters` may be nil (all shown).
function UI.ChecklistFilterItems(filters)
  local items = {}
  for _, key in ipairs(ns.Checklist.FILTERS) do
    items[#items + 1] = { kind = "checkbox", key = key, label = L[FILTER_LABELS[key]],
      checked = ns.Checklist.Shown(filters, key) }
  end
  items[#items + 1] = { kind = "divider" }
  items[#items + 1] = { kind = "button", action = "checkAll", label = L["Check all"] }
  items[#items + 1] = { kind = "button", action = "uncheckAll", label = L["Uncheck all"] }
  return items
end

-- Flips category `key` in `filters` -> its new state (shown = nothing stored).
function UI.ToggleChecklistFilter(filters, key)
  local on = not ns.Checklist.Shown(filters, key)
  if on then filters[key] = nil else filters[key] = false end
  return on
end

-- "checkAll" / "reset" (the dropdown's reset arrow): every category shown;
-- "uncheckAll": every category hidden.
function UI.ApplyChecklistFilterAction(filters, action)
  for _, key in ipairs(ns.Checklist.FILTERS) do
    if action == "uncheckAll" then
      filters[key] = false
    elseif action == "checkAll" or action == "reset" then
      filters[key] = nil
    end
  end
end

-- True when every category is shown (no reset arrow).
function UI.ChecklistFiltersAreDefault(filters)
  for _, key in ipairs(ns.Checklist.FILTERS) do
    if not ns.Checklist.Shown(filters, key) then return false end
  end
  return true
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

-- Rare spawns with no lockout (camp entries) -------------------------------------
-- Their box is not a lockout tick: a click records when the player last
-- checked the spawn (ns.db.char.campChecked = { [tick key] = Game.Now() }),
-- shown on the row as "Last checked 3 hr ago". The row is never done; it
-- leaves the list when the mount is owned.

local function isCamp(entry)
  return type(entry) == "table" and entry.reset == "camp"
end

-- Seconds -> "23 min" / "3 hr" / "1 day" / "2 days" (at least "1 min").
function UI.FormatAgo(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  if seconds < 3600 then return string.format(L["%d min"], math.max(1, math.floor(seconds / 60))) end
  if seconds < 86400 then return string.format(L["%d hr"], math.floor(seconds / 3600)) end
  local days = math.floor(seconds / 86400)
  return string.format(days == 1 and L["%d day"] or L["%d days"], days)
end

-- Records a check of `key`'s spawn at `now` (a later click moves it on).
function UI.CampMark(store, key, now)
  store[key] = now
end

function UI.CampClear(store, key)
  store[key] = nil
end

-- "Last checked 3 hr ago", or nil when never checked.
function UI.CampCheckedText(store, key, now)
  local at = type(store) == "table" and store[key] or nil
  if type(at) ~= "number" then return nil end
  return string.format(L["Last checked %s ago"], UI.FormatAgo(now - at))
end

-- A camp row's grey line with its last check appended.
function UI.ChecklistCampDesc(desc, checked)
  if not checked or checked == "" then return desc end
  if not desc or desc == "" then return checked end
  return desc .. DOT .. checked
end

-- Click on a camp row's box: the right button clears the time, any other
-- marks it at `now`. -> true for camp entries, false (nothing stored) else.
function UI.ChecklistCampClick(entry, store, now, button)
  if not isCamp(entry) then return false end
  if button == "RightButton" then
    UI.CampClear(store, entry.key)
  else
    UI.CampMark(store, entry.key, now)
  end
  return true
end

-- Tick box of an entry -> checked, enabled, auto (UI.RouteCheck). A camp
-- entry's box is always enabled and checked while `campStore` (default
-- ns.db.char.campChecked) has a time for it.
function UI.ChecklistCheck(entry, campStore)
  if isCamp(entry) then
    local char = ns.db and ns.db.char
    local store = campStore or (char and char.campChecked)
    return (type(store) == "table" and store[entry.key] ~= nil) and true or false, true, false
  end
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
local SUB_OFFSET = 16 -- per header level under the reset header (UI/List.lua: sub-header indicator 22 vs 6, +16 per level)
local TOP_HEIGHT = 96 -- the tab's own header: name, summary, flavour line, chips
local HEADER_HEIGHT = 24 -- UI/List.lua section headers
local SUB_HEADER_HEIGHT = 20 -- UI/List.lua sub-headers

local view = {}
UI.ChecklistView = view

local root, header, frame, scrollBox, empty, pane
local selectedKey -- the selected row's entry key (the detail pane's mount)

-- Chips: which group the list shows.
local SHOWS = { "all", "daily", "weekly", "camp" }
local SHOW_LABELS = { all = "All", daily = "Daily", weekly = "Weekly", camp = "Rare spawns" }

-- The group shown (ns.db.char.checklistShow), "all" by default.
function view.Show()
  local char = ns.db and ns.db.char
  local v = char and char.checklistShow
  return SHOW_LABELS[v] and v or "all"
end

-- A Checklist.Build output limited to the chip's group.
function UI.ChecklistOnly(built, show)
  if show == "all" or not SHOW_LABELS[show] then return built end
  local out = { daily = {}, weekly = {}, camp = {} }
  out[show] = built[show] or {}
  return out
end

-- What is left per group under `filters` -> { daily =, weekly =, camp = }.
function UI.ChecklistLeft(built, filters)
  local C = ns.Checklist
  return {
    daily = C.Remaining({ daily = built.daily or {} }, filters),
    weekly = C.Remaining({ weekly = built.weekly or {} }, filters),
    camp = C.CampLeft(built, filters),
  }
end

local function charDB()
  return ns.db and ns.db.char or nil
end

local function collapsedDB()
  local global = ns.db and ns.db.global
  if not global then return nil end
  if type(global.collapsed) ~= "table" then global.collapsed = {} end
  return global.collapsed
end

-- This character's checklist filters (ns.db.char.checklistFilters), nil
-- before the database is up.
function view.Filters()
  local char = charDB()
  if not char then return nil end
  if type(char.checklistFilters) ~= "table" then char.checklistFilters = {} end
  return char.checklistFilters
end

-- The Filter button for the checklist (UI.CreateFilterDropdown) on
-- `parent` (the tab's header), or nil on clients without the 11.x dropdown.
function view.CreateFilterDropdown(parent)
  return UI.CreateFilterDropdown(parent, {
    -- /azt debug: without the dropdown there is no checklist filter.
    fallbackName = "checklist filter (all categories shown)",
    items = function() return UI.ChecklistFilterItems(view.Filters()) end,
    onChange = function(kind, value)
      local filters = view.Filters()
      if not filters then return end
      if kind == "toggle" then
        UI.ToggleChecklistFilter(filters, value)
      else
        UI.ApplyChecklistFilterAction(filters, value)
      end
      ns.Refresh()
    end,
    isDefault = function() return UI.ChecklistFiltersAreDefault(view.Filters()) end,
    reset = function()
      local filters = view.Filters()
      if filters then
        UI.ApplyChecklistFilterAction(filters, "reset")
        ns.Refresh()
      end
    end,
  })
end

local function onTick(self, button)
  local row = self:GetParent()
  local entry = row and row.entry
  local char = charDB()
  if not (entry and char) then return end
  local Game = ns.Game
  if isCamp(entry) then
    if type(char.campChecked) ~= "table" then char.campChecked = {} end
    UI.ChecklistCampClick(entry, char.campChecked, Game.Now(), button)
    if UI.DebugTrace then
      UI.DebugTrace("checked box on mount %s (rare spawn, %s)", tostring(entry.id), tostring(button))
    end
    ns.Refresh()
    return
  end
  -- Only camp rows take the right button (the redraw resets the box).
  if button == "RightButton" then ns.Refresh() return end
  char.ticks = char.ticks or {}
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
    if check.RegisterForClicks then check:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    row.Check = check
  end
  row.entry = data.entry
  -- Recycled rows: re-anchor for this row's depth (indented under a sub-header).
  local inset = math.max(0, (data.depth or 1) - 1) * SUB_OFFSET
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

-- The summary line: what is left per group and when it resets.
function UI.ChecklistSummary(left, untilDaily, untilWeekly)
  return string.format(L["Daily: %d left, reset in %s"], left.daily, UI.FormatDuration(untilDaily))
    .. "    " .. string.format(L["Weekly: %d left, reset in %s"], left.weekly, UI.FormatDuration(untilWeekly))
    .. "    " .. string.format(L["Rare spawns: %d"], left.camp)
end

-- The flat header strip: name, reset timers, flavour line, and the Filter
-- button in the top right (none on clients without the 11.x dropdown: every
-- category shown).
local function buildHeader(parent)
  local top = CreateFrame("Frame", nil, parent)
  top:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  top:SetHeight(TOP_HEIGHT)

  -- Flat header strip with a thin rule underneath.
  local strip = top:CreateTexture(nil, "BACKGROUND")
  strip:SetAllPoints(top)
  strip:SetColorTexture(1, 1, 1, 0.04)
  local rule = top:CreateTexture(nil, "BORDER")
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
  rule:SetColorTexture(1, 1, 1, 0.1)

  -- Header lines span the header with same-edge anchor pairs, each chained
  -- under the one above (the Filter button overlays the name line's right
  -- end; the name is short and left-justified).
  local name = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  name:SetPoint("TOPLEFT", top, "TOPLEFT", 8, -6)
  name:SetPoint("TOPRIGHT", top, "TOPRIGHT", -8, -6)
  name:SetJustifyH("LEFT")
  top.Name = name

  local resets = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  resets:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
  resets:SetPoint("TOPRIGHT", name, "BOTTOMRIGHT", 0, -4)
  resets:SetJustifyH("LEFT")
  top.Resets = resets

  local flavour = top:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  flavour:SetPoint("TOPLEFT", resets, "BOTTOMLEFT", 0, -8)
  flavour:SetPoint("TOPRIGHT", resets, "BOTTOMRIGHT", 0, -8)
  flavour:SetJustifyH("LEFT")
  top.Flavour = flavour

  local filter = view.CreateFilterDropdown(top)
  if filter then
    filter:SetPoint("TOPRIGHT", top, "TOPRIGHT", -8, -4)
    top.ChecklistFilter = filter
  end

  -- Pop out the rare tracker (UI/RareTracker.lua).
  local pop = CreateFrame("Button", nil, top, "UIPanelButtonTemplate")
  pop:SetSize(110, 22)
  pop:SetText(L["Pop out rares"])
  if filter then
    pop:SetPoint("RIGHT", filter, "LEFT", -6, 0)
  else
    pop:SetPoint("TOPRIGHT", top, "TOPRIGHT", -8, -4)
  end
  pop:SetScript("OnClick", function() if UI.ToggleRareTracker then UI.ToggleRareTracker() end end)
  top.PopOut = pop

  -- Chips: All / Daily / Weekly / Rare spawns.
  top.Chips = {}
  local prev
  for i, key in ipairs(SHOWS) do
    local chip = CreateFrame("Button", nil, top)
    chip:SetHeight(18)
    if prev then
      chip:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    else
      chip:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 6, 6)
    end
    local bg = chip:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(chip)
    bg:SetColorTexture(1, 1, 1, 0.06)
    chip.Bg = bg
    local text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", chip, "CENTER", 0, 0)
    chip.Text = text
    local hl = chip:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(chip)
    hl:SetColorTexture(1, 1, 1, 0.08)
    chip.key = key
    chip:SetScript("OnClick", function()
      local char = ns.db and ns.db.char
      if char then char.checklistShow = key end
      ns.Refresh()
    end)
    top.Chips[i] = chip
    prev = chip
  end
  return top
end

-- Paints the chips: label with what is left, the shown one gold.
local function paintChips(left, show)
  for _, chip in ipairs(header.Chips) do
    local key = chip.key
    local label = L[SHOW_LABELS[key]]
    if key ~= "all" then label = string.format("%s (%d)", label, left[key] or 0) end
    chip.Text:SetText(label)
    chip:SetWidth((chip.Text.GetStringWidth and chip.Text:GetStringWidth() or 60) + 16)
    local on = key == show
    chip.Bg:SetColorTexture(1, on and 0.82 or 1, on and 0 or 1, on and 0.3 or 0.06)
    chip.selected = on
  end
end

-- Builds the tab inside `parent` (its content frame): the header, then the
-- list under it (header.Checklist).
function view.Build(parent)
  root = CreateFrame("Frame", nil, parent)
  root:SetAllPoints(parent)
  -- The detail pane on the right, full height; header and list to its left.
  if UI.CreateDetailPane then
    pane = UI.CreateDetailPane(root)
    pane:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    root.Detail = pane
  end
  header = buildHeader(root)
  if pane then
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", pane, "TOPLEFT", 0, 0)
  end

  frame = CreateFrame("Frame", nil, root)
  frame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  if pane then
    frame:SetPoint("BOTTOMRIGHT", pane, "BOTTOMLEFT", 0, 0)
  else
    frame:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  end
  header.Checklist = frame
  scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  scrollBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 0)
  frame.ScrollBox = scrollBox

  local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

  local listView = CreateScrollBoxListLinearView()
  listView:SetElementExtentCalculator(function(_, row)
    if row.header then return (row.depth or 1) >= 2 and SUB_HEADER_HEIGHT or HEADER_HEIGHT end
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
  root:HookScript("OnShow", view.StartTicker)
  root:HookScript("OnHide", view.StopTicker)
  if root:IsVisible() then view.StartTicker() end
  return root
end

-- Redraws the tab (when built): the header lines, the Filter button's reset
-- arrow and the list. -> the Checklist.Build output; nil before Build.
function view.Refresh()
  if not frame then return nil end
  local Game = ns.Game
  local built = UI.ChecklistBuild(Game.Now())
  local untilDaily, untilWeekly = Game.UntilDaily(), Game.UntilWeekly()
  local filters = view.Filters()
  local statusTexts = UI.EventStatusTexts(Game.Now())
  local show = view.Show()
  local rows = ns.Checklist.Rows(UI.ChecklistOnly(built, show), {
    collapsed = collapsedDB() or {},
    filters = filters,
    label = function(reset) return UI.ChecklistHeaderLabel(reset, untilDaily, untilWeekly) end,
    status = UI.ChecklistStatusOf(statusTexts),
  })
  local sourceText = UI.MemoText(Game.MountSourceText)
  local char = charDB()
  local campStore = char and char.campChecked
  local now = Game.Now()
  -- The selection stays while its entry is listed; else the first entry.
  local selectedRow, firstRow
  for _, row in ipairs(rows) do
    if not row.header then
      firstRow = firstRow or row
      if row.entry and row.entry.key == selectedKey then selectedRow = row end
    end
  end
  selectedRow = selectedRow or firstRow
  selectedKey = selectedRow and selectedRow.entry and selectedRow.entry.key or nil
  local n = 0
  for _, row in ipairs(rows) do
    if row.header then
      n = 0
    else
      n = n + 1
      local e = row.entry
      row.owned = false
      row.alt = n % 2 == 0
      row.desc = UI.ChecklistStatusDesc(UI.ChecklistDescription(e, sourceText(e.id)), row.status)
      if row.camp then
        row.desc = UI.ChecklistCampDesc(row.desc, UI.CampCheckedText(campStore, e.key, now))
      end
      row.tag = e.auto and L["auto"] or nil
      if pane then
        row.selected = row == selectedRow
        row.onSelect = view.SelectHandler
      else
        row.pin = UI.LocationIcon(e.id, e.boss)
      end
      -- The click goes to this lockout's boss (its instance's entrance) and
      -- the hover's lockout line is that boss's (UI.InitMountRow).
      row.routeBoss = e.boss
      row.eventMap = UI.ChecklistEventMap(e, statusTexts)
      if e.grouped then
        -- One lockout, several mounts: the boss names the row and the
        -- tooltip lists what it can drop (UI.InitMountRow's hooks).
        row.name = e.name
        row.tooltip = function(owner) UI.ShowChecklistGroupTooltip(owner, e) end
      end
      if pane then
        row.tooltip = function() end -- the pane shows what the tooltip would
      end
    end
  end
  if pane then
    local se = selectedRow and selectedRow.entry
    pane:SetMount(se and se.id or nil, se and se.boss or nil)
  end
  if ScrollBoxConstants then
    scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
  else
    scrollBox:SetDataProvider(CreateDataProvider(rows))
  end
  empty:SetShown(#rows == 0)

  local name = Game.PlayerName()
  header.Name:SetText(name or "")
  local left = UI.ChecklistLeft(built, filters)
  header.Resets:SetText(UI.ChecklistSummary(left, untilDaily, untilWeekly))
  paintChips(left, show)
  -- Lockouts left in the categories the Filter menu shows.
  header.Flavour:SetText(UI.RouteFlavour(ns.Checklist.Remaining(built, filters), name))
  local filter = header.ChecklistFilter
  if filter and type(filter.ValidateResetState) == "function" then filter:ValidateResetState() end
  return built
end

-- Selects a row's entry for the detail pane (a plain left-click).
function view.Select(entryKey)
  selectedKey = entryKey
  ns.Refresh()
end
view.SelectHandler = function(mountID, row)
  -- UI.InitMountRow passes the mount; the row frame carries its entry.
  local e = row and row.entry
  view.Select(e and e.key or selectedKey)
end

-- True while the tab is on screen.
function view.IsShown()
  return root ~= nil and root:IsVisible() and true or false
end

-- A light 60 s ticker while the tab is on screen, so the rare spawns' "Last
-- checked ... ago" lines age without an OnUpdate per row (started on show,
-- cancelled on hide; none without C_Timer.NewTicker).
local AGE_TICK = 60
local ticker

function view.StartTicker()
  if ticker or not (type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function") then return end
  ticker = C_Timer.NewTicker(AGE_TICK, function()
    if view.IsShown() then view.Refresh() end
  end)
end

function view.StopTicker()
  if ticker and type(ticker.Cancel) == "function" then ticker:Cancel() end
  ticker = nil
end

UI.RegisterView("checklist", view)
