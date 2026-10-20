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
-- pop-out or the main window when dropped near one (UI.SnapRect). Alt-drag
-- a row to move it: the order is saved per window (done rows stay last).
-- Windows that are not the player's own list (quick lists, the zone's
-- rares) group their rows under expansion headers when they span several
-- (UI.PopoutGroups). Right-click a window's title for its appearance:
-- opacity and font size (sliders, 20-100 % and 8-24), background and text
-- colour and font (saved per window, UI.PopoutStyle; "Apply to all
-- pop-outs" makes it every window's look, new ones too; "Reset
-- appearance"). Windows snapped together move
-- together: dragging one takes those snapped under it or to its right along
-- (UI.SnapChain), so the top of a stack moves the whole stack.
-- Each row carries a small expansion tag (UI.ExpansionBadge). Each
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

-- The windows that move with `lead` when it is dragged: those snapped under
-- it or to its right (edges within `tolerance`, overlapping), then theirs in
-- turn. rects = { [key] = rect } (UI.SnapRect's rects, `lead` among them).
-- -> sorted list of keys, `lead` not in it.
function UI.SnapChain(lead, rects, tolerance)
  tolerance = tolerance or 2
  local out, seen, queue = {}, { [lead] = true }, { lead }
  while #queue > 0 do
    local cur = rects[table.remove(queue, 1)]
    for k, o in pairs(rects) do
      if not seen[k] and cur then
        local below = math.abs(o.top - cur.bottom) <= tolerance and o.left < cur.right and o.right > cur.left
        local beside = math.abs(o.left - cur.right) <= tolerance and o.bottom < cur.top and o.top > cur.bottom
        if below or beside then
          seen[k] = true
          out[#out + 1] = k
          queue[#queue + 1] = k
        end
      end
    end
  end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

local function rectOf(f)
  local l, t, r, b = f:GetLeft(), f:GetTop(), f:GetRight(), f:GetBottom()
  if not (l and t and r and b) then return nil end
  return { left = l, top = t, right = r, bottom = b }
end

-- Rows in a saved order (Alt-drag): `order` = row keys in the player's order;
-- rows it names come first in that order, the rest after in their own
-- order; done rows stay last either way. -> the rows, re-sorted in place.
function UI.ApplyOrder(rows, order)
  if type(order) ~= "table" or #order == 0 then return rows end
  local rank = {}
  for i, key in ipairs(order) do rank[key] = i end
  local base = {}
  for i, row in ipairs(rows) do base[row] = i end
  table.sort(rows, function(a, b)
    if a.done ~= b.done then return not a.done end
    local ra, rb = rank[a.key], rank[b.key]
    if ra and rb then return ra < rb end
    if ra or rb then return ra ~= nil end
    return base[a] < base[b]
  end)
  return rows
end

-- Rows split by expansion for windows that are not the player's own list
-- -> list of { exp =, rows = { ... }, left = } in expansion order (Data
-- order; unknown last), each group's rows in their given order; one group
-- with exp = nil when the window is a custom list or spans one expansion.
function UI.PopoutGroups(rows, source, expansions)
  local function expOf(row) return row.entry and (row.entry.exp or (row.entry.m and row.entry.m.exp)) or nil end
  if source.kind ~= "list" then
    local seen, n = {}, 0
    for _, row in ipairs(rows) do
      local e = expOf(row) or "?"
      if not seen[e] then seen[e], n = true, n + 1 end
    end
    if n > 1 then
      local rank = {}
      for i, e in ipairs(expansions or (ns.Data and ns.Data.Expansions) or {}) do rank[e] = i end
      local groups, byExp = {}, {}
      for _, row in ipairs(rows) do
        local e = expOf(row) or "?"
        local g = byExp[e]
        if not g then
          g = { exp = expOf(row), rows = {}, left = 0 }
          byExp[e] = g
          groups[#groups + 1] = g
        end
        g.rows[#g.rows + 1] = row
        if not row.done then g.left = g.left + 1 end
      end
      table.sort(groups, function(a, b)
        return (rank[a.exp] or 999) < (rank[b.exp] or 999)
      end)
      return groups
    end
  end
  local left = 0
  for _, row in ipairs(rows) do if not row.done then left = left + 1 end end
  return { { exp = nil, rows = rows, left = left } }
end

-- Appearance of a window (right-click its title). Saved per window as
-- { alpha =, bg = { r, g, b }, text = { r, g, b }, size =, font = };
-- missing fields take the defaults (the window's own look). Opacity runs
-- 0.2-1 and the font size 8-24 (whole points): the menu's two sliders.
UI.POPOUT_STYLE = { alpha = 0.92, bg = { 0.06, 0.06, 0.07 }, text = nil, size = nil, font = nil }
local ALPHA_MIN, SIZE_MIN, SIZE_MAX = 0.2, 8, 24
UI.POPOUT_FONTS = {
  { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
  { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
  { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
  { name = "Skurri", path = "Fonts\\SKURRI.TTF" },
}

-- A saved style over the defaults -> a full style table.
function UI.PopoutStyle(saved)
  local d = UI.POPOUT_STYLE
  saved = type(saved) == "table" and saved or {}
  local alpha, size = tonumber(saved.alpha), tonumber(saved.size)
  return {
    alpha = alpha and math.max(ALPHA_MIN, math.min(1, alpha)) or d.alpha,
    bg = type(saved.bg) == "table" and saved.bg or d.bg,
    text = type(saved.text) == "table" and saved.text or d.text,
    size = size and math.max(SIZE_MIN, math.min(SIZE_MAX, math.floor(size + 0.5))) or d.size,
    font = type(saved.font) == "string" and saved.font or d.font,
  }
end

-- The text size a window has until one is chosen: the small font's own (the
-- font object's height), held to the slider's range; 11 when it cannot be
-- read.
function UI.PopoutDefaultSize()
  local fo = _G.GameFontHighlightSmall
  local _, height
  if type(fo) == "table" and type(fo.GetFont) == "function" then _, height = fo:GetFont() end
  height = tonumber(height)
  if not height then return 11 end
  return math.max(SIZE_MIN, math.min(SIZE_MAX, math.floor(height + 0.5)))
end

-- The order after moving `key` to position `to` among `keys` (the rows as
-- shown) -> new list of keys.
function UI.MoveKey(keys, key, to)
  local out = {}
  for _, k in ipairs(keys) do
    if k ~= key then out[#out + 1] = k end
  end
  to = math.max(1, math.min(to, #out + 1))
  table.insert(out, to, key)
  return out
end

-- A row's click (the row or its pin): UI.GoTo for its mount and boss.
function UI.PopoutGo(row)
  if row then UI.RowGo(row.id, row.entry and row.entry.boss) end
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
  -- The mount's expansion: a small coloured tag.
  r.Badge = UI.ExpansionBadge(r)
  r.Badge:SetPoint("LEFT", check, "RIGHT", 2, 0)
  local name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  name:SetPoint("LEFT", r.Badge, "RIGHT", 5, 0)
  name:SetPoint("RIGHT", zone, "LEFT", -6, 0)
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)
  r.Name = name
  -- The row: left-click as the pin; a custom list's row: right-click menu.
  -- Alt-drag: move the row (the drop line shows where it lands).
  r:RegisterForDrag("LeftButton")
  r:SetScript("OnDragStart", function(self)
    if not (type(IsAltKeyDown) == "function" and IsAltKeyDown()) or not self.data then return end
    w.dragKey = self.data.key
    w.DropLine:Show()
    w:SetScript("OnUpdate", function() UI.PopoutDragUpdate(w) end)
  end)
  r:SetScript("OnDragStop", function()
    if not w.dragKey then return end
    w.justDragged = true
    UI.PopoutDragDrop(w)
  end)
  r:SetScript("OnClick", function(self, button)
    if w.justDragged then
      w.justDragged = nil
      return
    end
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

-- The expansion group of the row being dragged (nil: none / no groups).
local function dragGroup(w)
  for _, s in ipairs(w.slots or {}) do
    if s.key == w.dragKey then return s.group end
  end
end

-- Where a dragged row would land: the row slot under the cursor.
local function dropIndex(w)
  local top = w.Content:GetTop()
  if not (top and type(GetCursorPosition) == "function") then return nil end
  local _, y = GetCursorPosition()
  local eff = w.Content.GetEffectiveScale and w.Content:GetEffectiveScale() or 1
  local offset = top - y / eff
  local h = w.rowHeight or ROW_HEIGHT
  local slots = w.slots or {}
  local i = 1
  for _, slot in ipairs(slots) do
    if slot.y + h / 2 < offset then i = i + 1 end
  end
  -- A row stays in its expansion's group: the slots of that group only.
  local g = dragGroup(w)
  local lo, hi
  for k, s in ipairs(slots) do
    if g and s.group == g then
      lo = lo or k
      hi = k + 1
    end
  end
  if lo then i = math.max(lo, math.min(hi, i)) end
  return i
end

function UI.PopoutDragUpdate(w)
  local i = dropIndex(w)
  if not i then return end
  local slots = w.slots or {}
  local h = w.rowHeight or ROW_HEIGHT
  -- Above the slot's row, or under the group's last row at its end.
  local g, nxt, prev = dragGroup(w), slots[i], slots[i - 1]
  local y = 0
  if nxt and (g == nil or nxt.group == g) then
    y = nxt.y
  elseif prev then
    y = prev.y + h
  end
  w.DropLine:ClearAllPoints()
  w.DropLine:SetPoint("TOPLEFT", w.Content, "TOPLEFT", 0, -y)
  w.DropLine:SetPoint("TOPRIGHT", w.Content, "TOPRIGHT", 0, -y)
  w.dropAt = i
end

-- Ends an Alt-drag: the row moves to the drop slot; the order is saved.
function UI.PopoutDragDrop(w)
  local key, to = w.dragKey, w.dropAt or dropIndex(w)
  w.dragKey, w.dropAt = nil, nil
  w:SetScript("OnUpdate", nil)
  w.DropLine:Hide()
  if not (key and to) then return end
  local keys = {}
  for _, row in ipairs(w.rows or {}) do
    if not row.done then
      keys[#keys + 1] = row.key
      if row.key == key and #keys < to then to = to - 1 end -- its own slot goes away
    end
  end
  local db = popoutsDB()
  if db then
    db[w.key] = db[w.key] or {}
    db[w.key].order = UI.MoveKey(keys, key, to)
  end
  UI.RefreshPopouts()
end

-- Rows follow the window's width (it can be resized).
local function layoutWidth(w)
  local width = math.max(MIN_W, w:GetWidth() or WIDTH)
  w.Content:SetWidth(width - 12)
  for _, r in ipairs(w.rowFrames) do r:SetWidth(width - 24) end
end

-- Expansion group headers in a window, reused between refreshes.
local GROUP_HEIGHT = 18
local function groupHeader(w, i)
  local h = w.groupFrames[i]
  if h then return h end
  h = CreateFrame("Frame", nil, w.Content)
  h:SetHeight(GROUP_HEIGHT)
  local text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  text:SetPoint("LEFT", h, "LEFT", 2, 0)
  h.Text = text
  local rule = h:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 1)
  rule:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 1)
  h.Rule = rule
  w.groupFrames[i] = h
  return h
end

-- A font string in the window's style: the style's font / size when set
-- (else the given font object) and text colour.
local function styleText(fs, style, fontObject, sizeDelta, color)
  fs:SetFontObject(fontObject)
  if (style.font or style.size) and fs.GetFont and fs.SetFont then
    local path, size, flags = fs:GetFont()
    if style.size then size = style.size + (sizeDelta or 0) end
    path = style.font or path
    if path and size then fs:SetFont(path, size, flags or "") end
  end
  local c = color or style.text
  if c then
    fs:SetTextColor(c[1], c[2], c[3])
  else
    local fo = _G[fontObject]
    if type(fo) == "table" and fo.GetTextColor then fs:SetTextColor(fo:GetTextColor()) end
  end
end

-- The look every window has unless it has its own ("Apply to all pop-outs").
local function sharedStyle()
  local global = ns.db and ns.db.global
  return global and type(global.popoutStyle) == "table" and global.popoutStyle or nil
end

-- The window's own style, else the shared one, over the defaults.
local function styleOf(w)
  local db = popoutsDB()
  local state = db and db[w.key]
  return UI.PopoutStyle(state and state.style or sharedStyle())
end

-- The window's background and title in its style.
local function applyChrome(w, style)
  w.Fill:SetColorTexture(style.bg[1], style.bg[2], style.bg[3], style.alpha)
  styleText(w.Title, style, "GameFontNormal", 2, nil)
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
  local db = popoutsDB()
  local state = db and db[w.key]
  UI.ApplyOrder(rows, state and state.order)
  local style = styleOf(w)
  applyChrome(w, style)
  local rowHeight = math.max(ROW_HEIGHT, (style.size or 11) + 9)
  local groupHeight = math.max(GROUP_HEIGHT, (style.size or 11) + 7)
  w.rowHeight = rowHeight
  local groups = UI.PopoutGroups(rows, w.source)
  -- w.rows in display order (Plot all, Alt-drag); w.slots: where each open
  -- row sits (the drop slots).
  w.rows, w.slots = {}, {}
  w.Title:SetText(UI.PopoutTitle(w.source, store) .. "  |cff9d9d9d(" .. string.format(L["%d left"], left) .. ")|r")
  local width = math.max(MIN_W, w:GetWidth() or WIDTH) - 24
  local y = 0
  local now = ns.Game.Now()
  local n, usedHeaders = 0, 0
  for gi, g in ipairs(groups) do
    if g.exp ~= nil or #groups > 1 then
      usedHeaders = usedHeaders + 1
      local h = groupHeader(w, usedHeaders)
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", w.Content, "TOPLEFT", 0, -y)
      h:SetWidth(width)
      h:SetHeight(groupHeight)
      local c = (UI.EXPANSION_COLORS and UI.EXPANSION_COLORS[g.exp]) or { 0.8, 0.8, 0.8 }
      h.Text:SetText((g.exp and L[g.exp] or L["Other"]) .. "  |cff9d9d9d(" .. string.format(L["%d left"], g.left) .. ")|r")
      styleText(h.Text, style, "GameFontNormalSmall", 0, c)
      h.Rule:SetColorTexture(c[1], c[2], c[3], 0.35)
      h:Show()
      y = y + groupHeight + 2
    end
    for _, row in ipairs(g.rows) do
      n = n + 1
      w.rows[n] = row
      local r = rowFrame(w, n)
      r.data = row
      r:SetHeight(rowHeight)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", w.Content, "TOPLEFT", 0, -y)
      r:SetWidth(width)
      r:Show()
      r.Name:SetText(row.name)
      UI.SetExpansionBadge(r.Badge, row.entry and (row.entry.exp or (row.entry.m and row.entry.m.exp)))
      styleText(r.Name, style, row.done and "GameFontDisableSmall" or "GameFontHighlightSmall", 0,
        row.done and { 0.5, 0.5, 0.5 } or nil)
      styleText(r.Zone, style, "GameFontDisableSmall", -1, { 0.55, 0.55, 0.55 })
      local zoneText = row.zone or ""
      if row.camp and row.checked then
        zoneText = string.format(L["checked %s ago"], UI.FormatAgo(now - row.checked))
      end
      r.Zone:SetText(zoneText)
      r.Check:SetChecked(row.done or (row.camp and row.checked ~= nil) or false)
      r.Check:SetEnabled(row.camp and true or false)
      if not row.done then w.slots[#w.slots + 1] = { key = row.key, y = y, group = gi } end
      y = y + rowHeight
    end
  end
  for i = n + 1, #w.rowFrames do w.rowFrames[i]:Hide() end
  for i = usedHeaders + 1, #w.groupFrames do w.groupFrames[i]:Hide() end
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
  w.rowFrames, w.groupFrames = {}, {}
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
  strip:SetScript("OnDragStart", function()
    -- The windows snapped under / beside this one come along, pinned to it.
    w.followers = {}
    local lead = rectOf(w)
    if lead then
      local rects = { [key] = lead }
      for k, o in pairs(windows) do
        if o ~= w and o:IsShown() then rects[k] = rectOf(o) end
      end
      for _, k in ipairs(UI.SnapChain(key, rects)) do
        local o, r = windows[k], rects[k]
        local f = { w = o, dx = r.left - lead.left, dy = r.top - lead.top }
        o:ClearAllPoints()
        o:SetPoint("TOPLEFT", w, "TOPLEFT", f.dx, f.dy)
        w.followers[#w.followers + 1] = f
      end
    end
    w:StartMoving()
  end)
  strip:SetScript("OnDragStop", function()
    w:StopMovingOrSizing()
    if w.SetUserPlaced then w:SetUserPlaced(false) end
    local followers = w.followers or {}
    w.followers = nil
    local moving = { [w] = true }
    for _, f in ipairs(followers) do moving[f.w] = true end
    -- Snap to another open pop-out (not one moving with it) or the main window.
    local mine = rectOf(w)
    local left, top = mine and mine.left, mine and mine.top
    if mine then
      local others = {}
      for _, o in pairs(windows) do
        if not moving[o] and o:IsShown() then others[#others + 1] = rectOf(o) end
      end
      if UI.frame and UI.frame:IsShown() then others[#others + 1] = rectOf(UI.frame) end
      local sl, st = UI.SnapRect(mine, others)
      if sl then left, top = sl, st end
      w:ClearAllPoints()
      w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    savePosition(w)
    for _, f in ipairs(followers) do
      if left then
        f.w:ClearAllPoints()
        f.w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left + f.dx, top + f.dy)
      end
      savePosition(f.w)
    end
  end)
  strip:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then UI.ShowPopoutStyleMenu(w, self) end
  end)
  strip:SetScript("OnEnter", function(self) UI.ShowHint(self, L["Drag to move"], L["Right-click: appearance"]) end)
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
  -- Where an Alt-dragged row lands.
  local dropLine = content:CreateTexture(nil, "OVERLAY")
  dropLine:SetHeight(2)
  dropLine:SetColorTexture(1, 0.82, 0, 0.9)
  dropLine:Hide()
  w.DropLine = dropLine

  local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  empty:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -6)
  empty:SetText(source.kind == "list" and L["Nothing on this list yet."] or L["Nothing left here."])
  empty:Hide()
  w.Empty = empty
  windows[key] = w
  return w
end

-- Saves `change(style)` into window `w`'s style and redraws. chromeOnly: a
-- change of the background only (the opacity slider, many times a second):
-- the windows are repainted without rebuilding their rows.
local function setStyle(w, change, chromeOnly)
  local db = popoutsDB()
  if not db then return end
  db[w.key] = db[w.key] or {}
  local st = db[w.key].style
  if not st then
    st = {}
    for k, v in pairs(sharedStyle() or {}) do st[k] = v end
  end
  change(st)
  db[w.key].style = st
  if chromeOnly then
    for _, win in pairs(windows) do
      if win:IsShown() then applyChrome(win, styleOf(win)) end
    end
  else
    UI.RefreshPopouts()
  end
end

-- Blizzard's colour picker for a style colour (presets cover most uses).
local function pickColor(w, field, current)
  local cp = ColorPickerFrame
  if not (cp and cp.SetupColorPickerAndShow) then return end
  local c = current or { 1, 1, 1 }
  local function apply()
    local r, g, b = cp:GetColorRGB()
    setStyle(w, function(st) st[field] = { r, g, b } end)
  end
  cp:SetupColorPickerAndShow({
    r = c[1], g = c[2], b = c[3], hasOpacity = false,
    swatchFunc = apply,
    cancelFunc = function() setStyle(w, function(st) st[field] = current end) end,
  })
end

local BG_PRESETS = {
  { "Dark", { 0.06, 0.06, 0.07 } }, { "Black", { 0, 0, 0 } }, { "Slate", { 0.1, 0.12, 0.16 } },
  { "Bronze", { 0.16, 0.11, 0.05 } }, { "Forest", { 0.05, 0.12, 0.07 } }, { "Wine", { 0.15, 0.05, 0.07 } },
}
local TEXT_PRESETS = {
  { "White", { 1, 1, 1 } }, { "Gold", { 1, 0.82, 0 } }, { "Light grey", { 0.8, 0.8, 0.8 } },
  { "Green", { 0.5, 0.9, 0.5 } }, { "Sky", { 0.55, 0.8, 1 } },
}

local function same(a, b)
  if a == nil or b == nil then return a == b end
  return math.abs(a[1] - b[1]) < 0.01 and math.abs(a[2] - b[2]) < 0.01 and math.abs(a[3] - b[3]) < 0.01
end

-- The appearance menu of a window (right-click its title): opacity and font
-- size are sliders right in it; the colours and the font each open their own
-- flat menu of choices (the current one ticked; Back returns).
function UI.ShowPopoutStyleMenu(w, owner)
  local db = popoutsDB()
  local function current() return styleOf(w) end
  local main
  local function sub(title, choices)
    return function()
      local list = { { title = title } }
      for _, it in ipairs(choices()) do list[#list + 1] = it end
      list[#list + 1] = { separator = true }
      list[#list + 1] = { text = L["Back"], submenu = main }
      return list
    end
  end
  local function choice(text, checked, change)
    return { text = text, checked = checked, keepOpen = true, onClick = function() setStyle(w, change) end }
  end
  main = function()
    local s = current()
    return {
      { title = L["Appearance"] },
      { slider = true, text = L["Opacity"], min = math.floor(ALPHA_MIN * 100 + 0.5), max = 100, step = 1,
        value = math.floor(s.alpha * 100 + 0.5), format = "%d%%",
        onChange = function(pct) setStyle(w, function(st) st.alpha = pct / 100 end, true) end },
      { text = L["Background colour"], submenu = sub(L["Background colour"], function()
        local out = {}
        for _, p in ipairs(BG_PRESETS) do
          out[#out + 1] = choice(L[p[1]], same(current().bg, p[2]), function(st) st.bg = p[2] end)
        end
        out[#out + 1] = { text = L["Custom..."], onClick = function() pickColor(w, "bg", current().bg) end }
        return out
      end) },
      { text = L["Text colour"], submenu = sub(L["Text colour"], function()
        local out = { choice(L["Default"], current().text == nil, function(st) st.text = nil end) }
        for _, p in ipairs(TEXT_PRESETS) do
          out[#out + 1] = choice(L[p[1]], same(current().text, p[2]), function(st) st.text = p[2] end)
        end
        out[#out + 1] = { text = L["Custom..."], onClick = function() pickColor(w, "text", current().text) end }
        return out
      end) },
      { slider = true, text = L["Font size"], min = SIZE_MIN, max = SIZE_MAX, step = 1,
        value = s.size or UI.PopoutDefaultSize(), format = "%d",
        onChange = function(size) setStyle(w, function(st) st.size = size end) end },
      { text = L["Font"], submenu = sub(L["Font"], function()
        local out = { choice(L["Default"], current().font == nil, function(st) st.font = nil end) }
        for _, f in ipairs(UI.PopoutFonts()) do
          out[#out + 1] = choice(f.name, current().font == f.path, function(st) st.font = f.path end)
        end
        return out
      end) },
      { separator = true },
      { text = L["Apply to all pop-outs"], onClick = function()
        -- This window's look becomes every window's (and new ones').
        local mine = db and db[w.key] and db[w.key].style or sharedStyle()
        if ns.db and ns.db.global then
          ns.db.global.popoutStyle = mine and { alpha = mine.alpha, bg = mine.bg, text = mine.text,
            size = mine.size, font = mine.font } or nil
        end
        for _, state in pairs(db or {}) do
          if type(state) == "table" then state.style = nil end
        end
        UI.RefreshPopouts()
      end },
      { text = L["Reset appearance"], onClick = function()
        -- Back to the add-on's own look ({}: not the shared one either).
        if db and db[w.key] then db[w.key].style = sharedStyle() and {} or nil end
        UI.RefreshPopouts()
      end },
    }
  end
  UI.ShowMenu(owner, main, "cursor")
end

-- The fonts offered: the game's own, then LibSharedMedia's when another
-- add-on brings it (first 12).
function UI.PopoutFonts()
  local out = {}
  for _, f in ipairs(UI.POPOUT_FONTS) do out[#out + 1] = f end
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if LSM and LSM.List and LSM.Fetch then
    local seen = {}
    for _, f in ipairs(out) do seen[string.lower(f.path)] = true end
    local n = 0
    for _, name in ipairs(LSM:List("font") or {}) do
      local path = LSM:Fetch("font", name, true)
      if path and not seen[string.lower(path)] and n < 12 then
        out[#out + 1] = { name = name, path = path }
        seen[string.lower(path)] = true
        n = n + 1
      end
    end
  end
  return out
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
