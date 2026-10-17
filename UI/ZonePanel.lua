local ADDON, ns = ...

-- Zone side panel (TomCat's Tours style): a slim list docked to the main
-- window's right edge, "Mounts in <zone>", every mount the player can still
-- get whose location is the current zone (Zone.MountsFor: coords, source
-- "Zone:", dungeon / raid entrances). Rows look and click like the mount
-- lists (UI.InitMountRow: left-click waypoint, Shift map, Ctrl preview,
-- hover tooltip). Toggled by the title-bar pin button and `/azt zone`; the
-- open state is saved in ns.db.global.zonePanel.open. The panel is a child
-- of the main window, so it is shown only while the window is (v1: no
-- detached mode). It recomputes on ZONE_CHANGED_NEW_AREA, ZONE_CHANGED,
-- ZONE_CHANGED_INDOORS and PLAYER_ENTERING_WORLD (only when the zone,
-- Zone.Key, changed) and on ns.Refresh() (debounced to the next frame), and
-- only while it is visible. While shown, the window's clamp rect includes
-- the panel so both stay on screen.
-- UI.ZoneContext / UI.ZoneMounts / UI.ZoneTitle / UI.ZoneRows are unit-tested
-- (tests/ui_zone_spec.lua); the widget is built under the stub in
-- tests/ui_build_spec.lua.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local GREY = "|cff9d9d9d"

-- Session caches ---------------------------------------------------------------

-- Mount Journal source text per mount (static for the session; a nil reply
-- is not cached, so a mount the client did not know yet is asked again).
local sourceTexts = {}
local function sourceText(id)
  local v = sourceTexts[id]
  if v == nil then
    local text = ns.Game.MountSourceText(id)
    if type(text) ~= "string" then return nil end
    sourceTexts[id] = text
    v = text
  end
  return v
end

-- The source text's "Zone:" value per mount (UI.SourceZone; false: none).
local sourceZones = {}
local function sourceZone(id)
  local v = sourceZones[id]
  if v == nil then
    local text = sourceText(id)
    if text == nil then return nil end
    v = UI.SourceZone(text) or false
    sourceZones[id] = v
  end
  return v or nil
end

-- Map and Encounter Journal data is static for the session: each lookup is
-- asked once per argument. A nil reply is asked again next time, unless
-- `cacheNil` (then it is stored as false: GetInstanceForGameMap says "none"
-- for most maps).
local sessionCaches = {}
local function sessionMemo(name, cacheNil)
  local cache = sessionCaches[name]
  if not cache then
    cache = {}
    sessionCaches[name] = cache
  end
  return function(arg)
    if arg == nil then return nil end
    local v = cache[arg]
    if v == nil then
      v = ns.Game[name](arg)
      if v == nil then
        if not cacheNil then return nil end
        v = false
      end
      cache[arg] = v
    end
    return v or nil
  end
end

-- Pure-ish glue ----------------------------------------------------------------

-- Zone.MountsFor's ctx from the live game: map / Encounter Journal lookups
-- (Game.MapInfo, MapChildren, DungeonEntrances, InstanceForMap,
-- JournalInstanceName), the
-- holiday-aware coords (Map.CoordsFor), the source "Zone:" (UI.SourceZone),
-- the instance sub-group of dungeon / raid mounts (UI.SubGroup), the route
-- instance (UI.RouteEntry), UI.GroupKey, the Journal's gate (other faction,
-- unobtainable and mounts unknown to the client left out) and the Collected
-- filter (ns.db.global.filters.collected); currentInstance
-- (Game.CurrentInstanceName) for when the player's map is unknown.
function UI.ZoneContext()
  local game = ns.Game
  local db = ns.db and ns.db.global
  local filters = (db and db.filters) or ns.Journal.DefaultFilters
  local subGroupCtx = { sourceText = sourceText, mapName = UI.MemoText(game.MapName) }
  return {
    mounts = (ns.Data and ns.Data.Mounts) or {},
    mapInfo = sessionMemo("MapInfo"),
    entrances = sessionMemo("DungeonEntrances"),
    children = sessionMemo("MapChildren"),
    instanceForMap = sessionMemo("InstanceForMap", true),
    instanceName = sessionMemo("JournalInstanceName"),
    coords = function(id, m)
      local map = ns.Map
      if map and type(map.CoordsFor) == "function" then return map.CoordsFor(id) end
      return m.coords
    end,
    sourceZone = sourceZone,
    subGroup = function(id, m)
      if m.tab ~= "journal" or (m.section ~= "dungeon" and m.section ~= "raid") then return nil end
      local key, label = UI.SubGroup(id, m, m.section, subGroupCtx)
      if key and key ~= UI.OTHER_GROUP then return label end
      return nil
    end,
    routeInstance = function(id)
      local entry = UI.RouteEntry(id)
      return entry and entry.instance or nil
    end,
    key = UI.GroupKey,
    gate = ns.Zone.Gate(UI.Memo(game.IsOwned), UI.Memo(game.Exists), game.Faction()),
    showCollected = filters.collected == true,
    currentInstance = game.CurrentInstanceName and game.CurrentInstanceName() or nil,
  }
end

-- Zone.MountsFor for `mapID` (default: the player's map, Game.PlayerMap)
-- with `ctx` (default UI.ZoneContext()) -> list, zone. An error (reported
-- through Game.ReportError) gives an empty list.
function UI.ZoneMounts(mapID, ctx)
  if mapID == nil then mapID = ns.Game.PlayerMap() end
  local good, list, zone = pcall(function()
    return ns.Zone.MountsFor(mapID, ctx or UI.ZoneContext())
  end)
  if not good then
    if ns.Game.ReportError then ns.Game.ReportError(list) end
    return {}, nil
  end
  return list, zone
end

-- Header text: "Mounts in <zone>  (n)" (the count in grey).
function UI.ZoneTitle(zone, n)
  local name = zone and zone.name or L["this zone"]
  return string.format(L["Mounts in %s"], name) .. "  " .. GREY .. "(" .. (n or 0) .. ")|r"
end

-- Zone.MountsFor rows -> UI.InitMountRow data: striped every other row, the
-- list's description (UI.RowDescription) and pin (UI.HasLocation).
function UI.ZoneRows(list)
  local rows = {}
  for i, entry in ipairs(list or {}) do
    rows[i] = {
      id = entry.id, m = entry.m, owned = entry.owned == true, alt = i % 2 == 0,
      desc = UI.RowDescription(entry.id, sourceText(entry.id)),
      pin = UI.HasLocation(entry.id),
    }
  end
  return rows
end

-- Saved state ------------------------------------------------------------------

local function stateDB()
  local global = ns.db and ns.db.global
  if not global then return nil end
  if type(global.zonePanel) ~= "table" then global.zonePanel = { open = false } end
  return global.zonePanel
end

-- Whether the panel is set to open (saved).
function UI.ZonePanelOpen()
  local db = stateDB()
  return db ~= nil and db.open == true
end

-- Widget -----------------------------------------------------------------------

local PANEL_WIDTH = 260
local PANEL_GAP = 2 -- between the window's right edge and the panel
local HEADER = 34 -- title strip
local BUTTON_SIZE = 20 -- title-bar toggle

local panel   -- the panel frame (UI.zonePanel)
local button  -- the title-bar toggle (frame.ZoneButton)
local lastKey -- Zone.Key of the last rebuild (the zone root + instance)
local dirty = true -- rebuild on the next refresh even if the zone is the same
local pending = false -- a debounced rebuild is scheduled (C_Timer.After(0))

local function paintButton()
  if button then button.Selected:SetShown(UI.ZonePanelOpen()) end
end

local function report(err)
  if ns.Game.ReportError then ns.Game.ReportError(err) end
end

-- The window's clamp rect takes the docked panel in while it is shown, so
-- the window keeps it on screen; the point is set again to re-clamp now.
local function applyClamp(open)
  local frame = UI.frame
  if not (frame and type(frame.SetClampRectInsets) == "function") then return end
  frame:SetClampRectInsets(0, open and (PANEL_WIDTH + PANEL_GAP) or 0, 0, 0)
  local point, rel, relPoint, x, y = frame:GetPoint(1)
  if point then
    frame:ClearAllPoints()
    frame:SetPoint(point, rel, relPoint, x, y)
  end
end

-- Rebuilds the list when the panel is on screen and the player's zone
-- (Zone.Key: the zone root and instance, not the raw map, so walking between
-- sub-zones keeps the list and its scroll) changed, or `force`, or data
-- changed since (dirty). Off screen it only marks dirty.
function UI.RefreshZonePanel(force)
  if not (panel and panel:IsVisible()) then
    dirty = true
    return
  end
  local mapID = ns.Game.PlayerMap()
  local good, ctx = pcall(UI.ZoneContext)
  if not good then
    report(ctx)
    ctx = nil
  end
  local key
  if ctx then
    local good2, k = pcall(ns.Zone.Key, mapID, ctx)
    if good2 then key = k else report(k) end
  end
  local sameZone = key == lastKey
  if not (force or dirty) and sameZone then return end
  lastKey, dirty = key, false
  local list, zone = {}, nil
  if ctx then list, zone = UI.ZoneMounts(mapID, ctx) end
  local rows = UI.ZoneRows(list)
  panel.Title:SetText(UI.ZoneTitle(zone, #rows))
  -- Same zone (a data refresh): keep the scroll position; a new zone starts
  -- at the top.
  local provider = CreateDataProvider(rows)
  if sameZone and ScrollBoxConstants then
    panel.ScrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)
  else
    panel.ScrollBox:SetDataProvider(provider)
  end
  panel.Empty:SetShown(#rows == 0)
end

-- Shows or hides the panel (saved), and repaints the toggle.
function UI.SetZonePanelOpen(open)
  local db = stateDB()
  if db then db.open = open and true or false end
  if panel then
    panel:SetShown(open and true or false)
    applyClamp(open)
    if open then UI.RefreshZonePanel(true) end
  end
  paintButton()
end

-- `/azt zone`: with the window closed, opens it with the panel; else flips
-- the panel. -> the panel's new open state.
function ns.ToggleZonePanel()
  local frame = UI.frame
  if not (frame and frame:IsShown()) then
    -- Open before the window shows: its OnShow hook then builds the list once.
    local db = stateDB()
    if db then db.open = true end
    if panel then
      panel:Show()
      applyClamp(true)
    end
    paintButton()
    if ns.ToggleWindow then ns.ToggleWindow() end
    return true
  end
  local open = not UI.ZonePanelOpen()
  UI.SetZonePanelOpen(open)
  return open
end

local function buildPanel(frame)
  local p = CreateFrame("Frame", "AzerothTrailZonePanel", frame)
  p:SetWidth(PANEL_WIDTH)
  p:SetPoint("TOPLEFT", frame, "TOPRIGHT", PANEL_GAP, 0)
  p:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", PANEL_GAP, 0)
  p:EnableMouse(true)

  -- Flat dark fill with a faint 1 px edge (the window's inset look).
  local fill = p:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(p)
  fill:SetColorTexture(0.06, 0.06, 0.07, 0.94)
  p.Fill = fill
  p.Edge = UI.FlatBorder(p, 1, 1, 1, 0.1)

  -- Title strip with a thin gold rule underneath.
  local strip = p:CreateTexture(nil, "BORDER")
  strip:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1)
  strip:SetPoint("TOPRIGHT", p, "TOPRIGHT", -1, -1)
  strip:SetHeight(HEADER)
  strip:SetColorTexture(1, 1, 1, 0.04)
  local rule = p:CreateTexture(nil, "BORDER")
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, 0)
  rule:SetColorTexture(1, 0.82, 0, 0.25)

  local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  close:SetSize(BUTTON_SIZE + 4, BUTTON_SIZE + 4)
  close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -4, -6)
  close:SetScript("OnClick", function() UI.SetZonePanelOpen(false) end)
  p.CloseButton = close

  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("LEFT", strip, "LEFT", 10, 0)
  title:SetPoint("RIGHT", close, "LEFT", -4, 0)
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)
  p.Title = title

  local scrollBox = CreateFrame("Frame", nil, p, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -2)
  scrollBox:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -16, 4)
  p.ScrollBox = scrollBox
  local scrollBar = CreateFrame("EventFrame", nil, p, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
  p.ScrollBar = scrollBar
  local view = CreateScrollBoxListLinearView()
  view:SetElementExtentCalculator(function() return UI.MOUNT_ROW_HEIGHT end)
  view:SetElementFactory(function(factory) factory("Button", UI.InitMountRow) end)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  local empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  empty:SetPoint("LEFT", scrollBox, "LEFT", 12, 0)
  empty:SetPoint("RIGHT", scrollBox, "RIGHT", -12, 0)
  empty:SetText(L["Nothing left to collect here"])
  empty:Hide()
  p.Empty = empty

  return p
end

-- The title-bar toggle: the map-pin icon left of the close button, a gold
-- band while the panel is open.
local function buildButton(frame)
  local b = CreateFrame("Button", nil, frame)
  b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  if frame.CloseButton then
    b:SetPoint("RIGHT", frame.CloseButton, "LEFT", -2, 0)
  else
    b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -2)
  end
  local selected = b:CreateTexture(nil, "BACKGROUND")
  selected:SetAllPoints(b)
  selected:SetColorTexture(1, 0.82, 0, 0.22)
  selected:Hide()
  b.Selected = selected
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
  icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  local atlas, texture = UI.PinIcon()
  if atlas then icon:SetAtlas(atlas) else icon:SetTexture(texture) end
  b.Icon = icon
  local highlight = b:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(b)
  highlight:SetColorTexture(1, 1, 1, 0.12)
  b:SetScript("OnClick", function() UI.SetZonePanelOpen(not UI.ZonePanelOpen()) end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(L["Zone panel"], 1, 1, 1)
    GameTooltip:AddLine(L["Mounts you can still get in your current zone"], nil, nil, nil, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return b
end

UI.AddWindowHook(function(frame)
  panel = buildPanel(frame)
  UI.zonePanel = panel
  button = buildButton(frame)
  frame.ZoneButton = button
  panel:SetShown(UI.ZonePanelOpen())
  applyClamp(UI.ZonePanelOpen())
  paintButton()
  -- The panel shows with the window: rebuild if anything changed meanwhile.
  frame:HookScript("OnShow", function() UI.RefreshZonePanel() end)
end)

-- Data changed (filters, a new mount, lockouts...): rebuild when visible,
-- once per burst: ns.Refresh often comes several times in one frame
-- (lockout, quest and LFG events), so the rebuild waits for the next frame
-- (C_Timer.After(0)); without C_Timer it runs at once.
UI.AddRefreshHook(function()
  dirty = true
  if not (panel and panel:IsVisible()) or pending then return end
  local timer = C_Timer
  if type(timer) == "table" and type(timer.After) == "function" then
    pending = true
    local good, err = pcall(timer.After, 0, function()
      pending = false
      UI.RefreshZonePanel()
    end)
    if good then return end
    pending = false
    report(err)
  end
  UI.RefreshZonePanel()
end)

local events = CreateFrame("Frame")
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
  "PLAYER_ENTERING_WORLD" }) do
  events:RegisterEvent(event)
end
events:SetScript("OnEvent", function() UI.RefreshZonePanel() end)
