local ADDON, ns = ...

-- Pop-out checklists: slim movable windows that stay on screen without the
-- main window, any number at once, each showing one set:
--   { kind = "camp", exp = }                 rare spawns with no lockout of an expansion
--   { kind = "daily" | "weekly", exp = [, category = ] }   that reset's lockouts
--                                            of an expansion (one category, e.g. "rares")
--   { kind = "zone" }                        the rares of the zone the player is in
--   { kind = "list", list = id }             a custom list (Logic/Lists.lua)
--   { kind = "quick", key = }                a quick list (Logic/QuickLists.lua)
-- Opened by right-clicking a Checklist header (that set), a custom list's
-- header menu, and /azt rares (the zone's rares). Rows come from the
-- Checklist (UI.ChecklistBuild), so they match it: a box (a lockout ticked
-- and dimmed when the game says done; a rare spawn's "last checked" box,
-- left-click marks, right-click clears), the name (the rare's for rare
-- rows) and its zone. A click on the row is UI.GoTo: every spawn point of
-- a rare that has several on TomTom, else the waypoint. "Plot all" in the
-- title puts the spawn points of every row whose box is not ticked on
-- TomTom at once (Map.PlotMounts). Ctrl-click a window's x to close every
-- pop-out. A custom list's rows are its mounts (ones already known left out);
-- right-click one to take it off the list. Each window can be resized with
-- its corner grip (right-click: fit to its rows again) and snaps to another
-- pop-out or the main window when dropped near one (UI.SnapRect). Each
-- window's position and open
-- state are saved by its set (ns.db.global.popouts) and come back after
-- /reload.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local WIDTH = 280
local TITLE_HEIGHT = 26
local ROW_HEIGHT = 20
local MAX_HEIGHT = 460
local AGE_TICK = 60
local CASCADE = 24
local SNAP = 16 -- how close (px) a dropped window must be to snap
local MIN_W, MIN_H = 200, 70

local function popoutsDB()
  local global = ns.db and ns.db.global
  if not global then return nil end
  if type(global.popouts) ~= "table" then global.popouts = {} end
  return global.popouts
end

local function listsDB()
  local global = ns.db and ns.db.global
  if not global then return nil end
  if type(global.lists) ~= "table" then global.lists = {} end
  return global.lists
end
UI.ListsDB = listsDB

-- Pure helpers -------------------------------------------------------------------

-- The saved key of a set: "camp|Legion", "daily|Legion|rares", "zone", "list|3".
function UI.PopoutKey(source)
  if type(source) ~= "table" or not source.kind then return nil end
  if source.kind == "list" then return "list|" .. tostring(source.list) end
  if source.kind == "quick" then return "quick|" .. tostring(source.key) end
  if source.kind == "zone" then return "zone" end
  local key = source.kind .. "|" .. tostring(source.exp)
  if source.category then key = key .. "|" .. source.category end
  return key
end

-- The window's title for a set ("Legion rare spawns", "Legion dailies -
-- Rares", a list's name).
function UI.PopoutTitle(source, store)
  if source.kind == "list" then
    local l = store and ns.Lists.Get(store, source.list)
    return l and l.name or L["List"]
  end
  if source.kind == "zone" then return L["Rare spawns here"] end
  if source.kind == "quick" then
    local q = ns.QuickLists and ns.QuickLists.Get(source.key)
    return q and L[q.name] or L["List"]
  end
  local exp = L[source.exp or ""] or tostring(source.exp)
  local title
  if source.kind == "camp" then
    title = string.format(L["%s rare spawns"], exp)
  elseif source.kind == "weekly" then
    title = string.format(L["%s weeklies"], exp)
  else
    title = string.format(L["%s dailies"], exp)
  end
  if source.category then title = title .. " \194\183 " .. ns.Checklist.CategoryLabel(source.category) end
  return title
end

local function rareLike(e)
  return e.category == "rares" or e.reset == "camp"
end

-- The name a row shows: the rare's (its spot's NPC) for rare rows, else the
-- entry's (a grouped lockout's boss, else the mount).
local function rowName(e, spots)
  if rareLike(e) then
    return (spots[1] and spots[1].name) or e.boss or e.name or (e.m and e.m.name) or tostring(e.id)
  end
  return e.name or (e.m and e.m.name) or tostring(e.id)
end

-- The rows of a set -> list of { key =, id =, entry =, name =, zone =, done
-- =, camp =, checked = (a rare spawn's last check), spots = Map.Spots, listOnly
-- = (a custom list's mount the Checklist does not track) } - open ones first,
-- then by name - and how many are left (not done).
-- ctx: { zoneIDs = { [mountID] = true } (kind "zone"), campStore =
-- ns.db.char.campChecked, store = the lists store (kind "list"), isOwned =
-- fn(id) }.
function UI.PopoutRows(source, built, ctx)
  ctx = ctx or {}
  local map = ns.Map
  local faction = ns.Game.Faction and ns.Game.Faction() or nil
  local rows, left = {}, 0
  local function add(e, opts)
    local spots = map and map.Spots and map.Spots(e.id, faction) or {}
    local name = (opts and opts.name) or rowName(e, spots)
    local zone = e.zone
    if not zone and spots[1] and ns.Game.MapName then zone = ns.Game.MapName(spots[1].pts[1]) end
    local camp = e.reset == "camp"
    local row = { key = e.key, id = e.id, entry = e, name = name, zone = zone, done = e.done == true,
      camp = camp, spots = spots, listOnly = e.listOnly }
    if camp and type(ctx.campStore) == "table" then row.checked = ctx.campStore[e.key] end
    if not row.done then left = left + 1 end
    rows[#rows + 1] = row
  end
  local function expOf(e) return e.exp or (e.m and e.m.exp) end
  local kind = source.kind
  if kind == "daily" or kind == "weekly" then
    for _, e in ipairs(built[kind] or {}) do
      if expOf(e) == source.exp and (not source.category or e.category == source.category) then add(e) end
    end
  elseif kind == "camp" then
    for _, e in ipairs(built.camp or {}) do
      if expOf(e) == source.exp then add(e) end
    end
  elseif kind == "zone" then
    local ids = ctx.zoneIDs or {}
    for _, reset in ipairs({ "daily", "weekly", "camp" }) do
      for _, e in ipairs(built[reset] or {}) do
        if ids[e.id] and rareLike(e) then add(e) end
      end
    end
  elseif kind == "list" or kind == "quick" then
    local ids
    if kind == "quick" then
      ids = ns.QuickLists and ns.QuickLists.Mounts(source.key) or {}
    else
      local l = ctx.store and ns.Lists.Get(ctx.store, source.list)
      ids = (l and l.mounts) or {}
    end
    -- A mount the Checklist tracks shows its lockout; any other mount of
    -- the list is a plain row (done when collected).
    local byMount = {}
    for _, reset in ipairs({ "daily", "weekly", "camp" }) do
      for _, e in ipairs(built[reset] or {}) do
        for _, id in ipairs(e.mounts or { e.id }) do
          if byMount[id] == nil then byMount[id] = e end
        end
      end
    end
    local mounts = (ns.Data and ns.Data.Mounts) or {}
    for _, id in ipairs(ids) do
      local m = mounts[id]
      local mountName = (ns.Game.MountInfo and ns.Game.MountInfo(id)) or (m and m.name) or tostring(id)
      -- Mounts already known are left out (the Checklist's entries are
      -- not-owned ones already).
      local owned = ctx.isOwned and ctx.isOwned(id) and true or false
      local e = byMount[id]
      if e then
        add(e, { name = mountName })
      elseif not owned then
        add({ id = id, m = m, key = "list:" .. tostring(id), name = mountName, listOnly = true,
          mounts = { id } }, { name = mountName })
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.done ~= b.done then return not a.done end
    if a.name ~= b.name then return string.lower(a.name) < string.lower(b.name) end
    return tostring(a.key) < tostring(b.key)
  end)
  return rows, left
end

-- The mounts "Plot all" plots: rows whose box is not ticked (not done,
-- and a rare spawn not marked checked).
function UI.PopoutPlotIDs(rows)
  local ids = {}
  for _, row in ipairs(rows or {}) do
    if not (row.done or (row.camp and row.checked ~= nil)) then ids[#ids + 1] = row.id end
  end
  return ids
end

-- Where a dropped window snaps: rect = { left =, top =, right =, bottom = }
-- (screen units, top > bottom), others = list of such rects (the other
-- open pop-outs, the main window). Edge to edge within `threshold`: under
-- or above another (its left edge too when close), or beside it (its top
-- too when close); the nearest snap wins. -> left, top, or nil.
function UI.SnapRect(rect, others, threshold)
  threshold = threshold or SNAP
  local w, h = rect.right - rect.left, rect.top - rect.bottom
  local best, bestD
  local function try(d, left, top)
    if d <= threshold and (not bestD or d < bestD) then best, bestD = { left, top }, d end
  end
  local function near(a, b) return math.abs(a - b) <= threshold * 2 end
  for _, o in ipairs(others or {}) do
    local overlapX = rect.left < o.right + threshold and rect.right > o.left - threshold
    local overlapY = rect.bottom < o.top + threshold and rect.top > o.bottom - threshold
    if overlapX then
      local left = near(rect.left, o.left) and o.left or rect.left
      try(math.abs(rect.top - o.bottom), left, o.bottom) -- under it
      try(math.abs(rect.bottom - o.top), left, o.top + h) -- above it
    end
    if overlapY then
      local top = near(rect.top, o.top) and o.top or rect.top
      try(math.abs(rect.left - o.right), o.right, top) -- right of it
      try(math.abs(rect.right - o.left), o.left - w, top) -- left of it
    end
  end
  if best then return best[1], best[2] end
  return nil
end

local function rectOf(f)
  local l, t, r, b = f:GetLeft(), f:GetTop(), f:GetRight(), f:GetBottom()
  if not (l and t and r and b) then return nil end
  return { left = l, top = t, right = r, bottom = b }
end

-- A row's click (the row or its pin): UI.GoTo for its mount and boss.
function UI.PopoutGo(row)
  if row then UI.GoTo(row.id, row.entry and row.entry.boss) end
end

-- Widget -----------------------------------------------------------------------

local windows = {} -- key -> window frame
local ticker

local function savePosition(w)
  local db = popoutsDB()
  if not db then return end
  local state = db[w.key] or {}
  local point, _, relPoint, x, y = w:GetPoint(1)
  state.point, state.relPoint, state.x, state.y = point, relPoint, x, y
  db[w.key] = state
end

local function zoneIDs()
  local ids = {}
  if not UI.ZoneMounts then return ids end
  local list = UI.ZoneMounts()
  for _, entry in ipairs(list or {}) do ids[entry.id] = true end
  return ids
end

local function rowFrame(w, i)
  local r = w.rowFrames[i]
  if r then return r end
  r = CreateFrame("Button", nil, w.Content)
  r:SetHeight(ROW_HEIGHT)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(r)
  hl:SetColorTexture(1, 1, 1, 0.06)
  local check = CreateFrame("CheckButton", nil, r,
    UI.TemplateChain("MinimalCheckboxTemplate", "SettingsCheckboxTemplate", "UICheckButtonTemplate"))
  check:SetSize(18, 18)
  check:SetPoint("LEFT", r, "LEFT", 2, 0)
  if check.RegisterForClicks then check:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  check:SetScript("OnClick", function(_, button)
    local row = r.data
    local char = ns.db and ns.db.char
    if row and row.camp and char then
      if type(char.campChecked) ~= "table" then char.campChecked = {} end
      UI.ChecklistCampClick(row.entry, char.campChecked, ns.Game.Now(), button)
    end
    ns.Refresh()
  end)
  r.Check = check
  local zone = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  zone:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  zone:SetJustifyH("RIGHT")
  zone:SetWordWrap(false)
  r.Zone = zone
  local name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  name:SetPoint("LEFT", check, "RIGHT", 2, 0)
  name:SetPoint("RIGHT", zone, "LEFT", -6, 0)
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)
  r.Name = name
  -- The row: left-click as the pin; a custom list's row: right-click menu.
  r:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
      UI.PopoutGo(self.data)
    elseif button == "RightButton" and w.source.kind == "list" and self.data then
      local data = self.data
      UI.ShowMenu(self, {
        { title = data.name },
        { text = string.format(L["Remove from %s"], UI.PopoutTitle(w.source, listsDB())), onClick = function()
          local store = listsDB()
          if store then ns.Lists.Remove(store, w.source.list, data.id) end
          ns.Refresh()
        end },
      }, "cursor")
    end
  end)
  r:SetScript("OnEnter", function(self)
    if self.data and UI.ShowMountTooltip then UI.ShowMountTooltip(self, self.data.id) end
  end)
  r:SetScript("OnLeave", function() if UI.HideMountTooltip then UI.HideMountTooltip() end end)
  w.rowFrames[i] = r
  return r
end

-- Rows follow the window's width (it can be resized).
local function layoutWidth(w)
  local width = math.max(MIN_W, w:GetWidth() or WIDTH)
  w.Content:SetWidth(width - 12)
  for _, r in ipairs(w.rowFrames) do r:SetWidth(width - 24) end
end

local function refreshWindow(w, built)
  if not w:IsShown() then return end
  local char = ns.db and ns.db.char
  local store = listsDB()
  if w.source.kind == "list" and not (store and ns.Lists.Get(store, w.source.list)) then
    UI.ClosePopout(w.key) -- the list was deleted
    return
  end
  local rows, left = UI.PopoutRows(w.source, built, {
    zoneIDs = w.source.kind == "zone" and zoneIDs() or nil,
    campStore = char and char.campChecked,
    store = store,
    isOwned = ns.Game.IsOwned,
  })
  w.rows = rows
  w.Title:SetText(UI.PopoutTitle(w.source, store) .. "  |cff9d9d9d(" .. string.format(L["%d left"], left) .. ")|r")
  local width = math.max(MIN_W, w:GetWidth() or WIDTH) - 24
  local y = 0
  local now = ns.Game.Now()
  for i, row in ipairs(rows) do
    local r = rowFrame(w, i)
    r.data = row
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", w.Content, "TOPLEFT", 0, -y)
    r:SetWidth(width)
    r:Show()
    r.Name:SetText(row.name)
    r.Name:SetFontObject(row.done and "GameFontDisableSmall" or "GameFontHighlightSmall")
    local zoneText = row.zone or ""
    if row.camp and row.checked then
      zoneText = string.format(L["checked %s ago"], UI.FormatAgo(now - row.checked))
    end
    r.Zone:SetText(zoneText)
    r.Check:SetChecked(row.done or (row.camp and row.checked ~= nil) or false)
    r.Check:SetEnabled(row.camp and true or false)
    y = y + ROW_HEIGHT
  end
  for i = #rows + 1, #w.rowFrames do w.rowFrames[i]:Hide() end
  w.Empty:SetShown(#rows == 0)
  if #rows == 0 then y = 30 end
  w.Content:SetHeight(math.max(y, 1))
  w.contentHeight = y
  -- Fit the rows until the player sizes the window; then keep that size.
  if not w.userSized then w:SetHeight(math.min(MAX_HEIGHT, TITLE_HEIGHT + y + 10)) end
end

-- Redraws every open pop-out (one Checklist build for all).
function UI.RefreshPopouts()
  local any = false
  for _, w in pairs(windows) do
    if w:IsShown() then any = true break end
  end
  if not any then return end
  local built = UI.ChecklistBuild(ns.Game.Now())
  for _, w in pairs(windows) do refreshWindow(w, built) end
end

local function openCount()
  local n = 0
  for _, w in pairs(windows) do if w:IsShown() then n = n + 1 end end
  return n
end

local function startTicker()
  if ticker or not (type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function") then return end
  ticker = C_Timer.NewTicker(AGE_TICK, function() UI.RefreshPopouts() end)
end

local function stopTickerIfIdle()
  if openCount() == 0 and ticker then
    if ticker.Cancel then ticker:Cancel() end
    ticker = nil
  end
end

local function build(key, source)
  local w = CreateFrame("Frame", nil, UIParent)
  w.key, w.source = key, source
  w.rowFrames = {}
  w:SetSize(WIDTH, 120)
  w:SetFrameStrata("MEDIUM")
  w:SetMovable(true)
  w:SetClampedToScreen(true)
  w:EnableMouse(true)
  w:Hide()
  local db = popoutsDB()
  local state = db and db[key]
  if state and state.width and state.height then
    w:SetSize(math.max(MIN_W, state.width), math.max(MIN_H, state.height))
    w.userSized = true
  end
  w:ClearAllPoints()
  if state and state.point then
    w:SetPoint(state.point, UIParent, state.relPoint or state.point, state.x or 0, state.y or 0)
  else
    local n = openCount()
    w:SetPoint("RIGHT", UIParent, "RIGHT", -60 - n * CASCADE, 60 - n * CASCADE)
  end

  local fill = w:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(w)
  fill:SetColorTexture(0.06, 0.06, 0.07, 0.92)
  w.Fill = fill
  w.Edge = UI.FlatBorder(w, 1, 1, 1, 0.12)

  -- Title strip: drag to move.
  local strip = CreateFrame("Frame", nil, w)
  strip:SetPoint("TOPLEFT", w, "TOPLEFT", 1, -1)
  strip:SetPoint("TOPRIGHT", w, "TOPRIGHT", -1, -1)
  strip:SetHeight(TITLE_HEIGHT)
  strip:EnableMouse(true)
  strip:RegisterForDrag("LeftButton")
  strip:SetScript("OnDragStart", function() w:StartMoving() end)
  strip:SetScript("OnDragStop", function()
    w:StopMovingOrSizing()
    if w.SetUserPlaced then w:SetUserPlaced(false) end
    -- Snap to another open pop-out or the main window.
    local mine = rectOf(w)
    if mine then
      local others = {}
      for _, o in pairs(windows) do
        if o ~= w and o:IsShown() then others[#others + 1] = rectOf(o) end
      end
      if UI.frame and UI.frame:IsShown() then others[#others + 1] = rectOf(UI.frame) end
      local left, top = UI.SnapRect(mine, others)
      if left then
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
      end
    end
    savePosition(w)
  end)
  strip:SetScript("OnEnter", function(self) UI.ShowHint(self, L["Drag to move"]) end)
  strip:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  local stripBg = strip:CreateTexture(nil, "BACKGROUND")
  stripBg:SetAllPoints(strip)
  stripBg:SetColorTexture(1, 1, 1, 0.05)
  local rule = w:CreateTexture(nil, "BORDER")
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, 0)
  rule:SetColorTexture(1, 0.82, 0, 0.3)
  w.Strip = strip

  -- Close: a flat x in the title strip.
  local close = UI.FlatButton(strip, "x", "plain", 18)
  close:SetWidth(18)
  close:SetPoint("RIGHT", strip, "RIGHT", -4, 0)
  close:SetScript("OnClick", function()
    if type(IsControlKeyDown) == "function" and IsControlKeyDown() then
      UI.CloseAllPopouts()
    else
      UI.ClosePopout(key)
    end
  end)
  close:SetScript("OnEnter", function(self) UI.ShowHint(self, L["Close"], L["Ctrl-click: close every pop-out"]) end)
  close:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  w.Close = close

  -- Plot all: every open row's spawn points on TomTom (Map.PlotMounts).
  local plot = UI.FlatButton(strip, L["Plot all"], "green", 16)
  plot:SetPoint("RIGHT", close, "LEFT", -4, 0)
  plot:SetScript("OnClick", function()
    if ns.Map and ns.Map.PlotMounts then
      ns.Map.PlotMounts(UI.PopoutPlotIDs(w.rows), UI.PopoutTitle(w.source, listsDB()))
    end
  end)
  plot:SetScript("OnEnter", function(self) UI.ShowHint(self, L["Plot every unticked row on TomTom"]) end)
  plot:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  w.PlotAll = plot

  local titleText = strip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleText:SetPoint("LEFT", strip, "LEFT", 8, 0)
  titleText:SetPoint("RIGHT", plot, "LEFT", -4, 0)
  titleText:SetJustifyH("LEFT")
  titleText:SetWordWrap(false)
  w.Title = titleText

  local scroll = CreateFrame("ScrollFrame", nil, w)
  scroll:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 6, -4)
  scroll:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -6, 6)
  if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(WIDTH - 12, 1)

  -- Resize grip: any size; right-click fits the rows again.
  UI.SetResizeLimits(w, MIN_W, MIN_H)
  w.Grip = UI.ResizeGrip(w, function(gw, gh)
    w.userSized = true
    local st = popoutsDB()
    if st then
      st[key] = st[key] or {}
      st[key].width, st[key].height = math.floor(gw + 0.5), math.floor(gh + 0.5)
    end
    savePosition(w)
    layoutWidth(w)
  end, function()
    w.userSized = nil
    w:SetWidth(WIDTH)
    local st = popoutsDB()
    if st and st[key] then st[key].width, st[key].height = nil, nil end
    layoutWidth(w)
    UI.RefreshPopouts()
  end, L["Right-click: fit to its rows"])
  w:SetScript("OnSizeChanged", function() layoutWidth(w) end)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, (w.contentHeight or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - delta * 30)))
  end)
  w.Scroll, w.Content = scroll, content

  local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  empty:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -6)
  empty:SetText(source.kind == "list" and L["Nothing on this list yet."] or L["Nothing left here."])
  empty:Hide()
  w.Empty = empty
  windows[key] = w
  return w
end

-- Opens (or brings back) the pop-out of `source` -> its window.
function UI.OpenPopout(source)
  local key = UI.PopoutKey(source)
  if not key then return nil end
  local w = windows[key] or build(key, source)
  w.source = source
  local db = popoutsDB()
  if db then
    local state = db[key] or {}
    state.open, state.source = true, source
    db[key] = state
  end
  w:Show()
  if w.Raise then w:Raise() end
  startTicker()
  refreshWindow(w, UI.ChecklistBuild(ns.Game.Now()))
  return w
end

function UI.ClosePopout(key)
  local w = windows[key]
  if w then w:Hide() end
  local db = popoutsDB()
  if db and db[key] then db[key].open = false end
  stopTickerIfIdle()
end

-- Closes every open pop-out (Ctrl-click on any pop-out's x).
function UI.CloseAllPopouts()
  for key, w in pairs(windows) do
    if w:IsShown() then UI.ClosePopout(key) end
  end
end

-- /azt rares: the zone's rares, opened or closed.
function UI.ToggleZonePopout()
  local w = windows.zone
  if w and w:IsShown() then
    UI.ClosePopout("zone")
    return false
  end
  UI.OpenPopout({ kind = "zone" })
  return true
end

UI.PopoutWindows = windows

UI.AddRefreshHook(function() UI.RefreshPopouts() end)

-- Back on screen after /reload when they were open; the zone's window
-- follows the player.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    local db = popoutsDB()
    for _, state in pairs(db or {}) do
      if type(state) == "table" and state.open and type(state.source) == "table" then
        UI.OpenPopout(state.source)
      end
    end
  elseif windows.zone and windows.zone:IsShown() then
    UI.RefreshPopouts()
  end
end)
