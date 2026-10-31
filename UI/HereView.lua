local ADDON, ns = ...

-- The Here view (the navigation column's "Here"): every mount still to get
-- in the player's zone (UI.ZoneMounts, the zone panel's list) as a full list
-- with the detail pane, grouped by source (Journal.SourceRank: Dungeon
-- drops, Vendors, Achievements, ...), under a strip naming the zone with a
-- Pop out button (the zone's mounts pop-out, which follows the player too).
-- It follows the player: the zone panel's events redraw it while it is on
-- screen, when the map changed.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local view = {}

local root, list, title
local shownMap -- the map the list was built for

-- UI.List's select: the zone's mounts, by source, then name; the search box
-- narrows by name. -> entries { id =, m =, section = }, the zone.
function UI.HereSelect(zoneList, query)
  local needle = query and query.search and string.lower(query.search) or ""
  -- The home page's fuzzy search (UI.SearchMatches) when it is loaded.
  local match
  if UI.SearchMatches and query and query.search then
    local ids = {}
    for i, e in ipairs(zoneList or {}) do ids[i] = e.id end
    match = UI.SearchMatches(ids, query.search, query.sourceText)
  end
  local out = {}
  for _, e in ipairs(zoneList or {}) do
    local m = e.m or {}
    local name = (ns.Game.MountInfo and ns.Game.MountInfo(e.id)) or m.name or ""
    local hit
    if match then hit = match[e.id] == true else hit = needle == "" or string.find(string.lower(name), needle, 1, true) end
    if hit then
      out[#out + 1] = { id = e.id, m = m, section = m.section or "other", name = string.lower(name) }
    end
  end
  table.sort(out, function(a, b)
    local ra, rb = ns.Journal.SourceRank(a.section), ns.Journal.SourceRank(b.section)
    if ra ~= rb then return ra < rb end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  return out
end

function view.Build(parent)
  root = CreateFrame("Frame", nil, parent)
  root:SetAllPoints(parent)
  local _
  _, title = UI.PageHeader(root, false)
  local pop = UI.PageButton(root, L["Pop out"])
  pop:SetScript("OnClick", function() if UI.OpenPopout then UI.OpenPopout({ kind = "zonemounts" }) end end)
  root.PopOut = pop
  local holder = CreateFrame("Frame", nil, root)
  holder:SetPoint("TOPLEFT", root, "TOPLEFT", 0, UI.PAGE_TOP)
  holder:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  list = UI.List(holder, function()
    return { view = "here", sourceText = ns.Game.MountSourceText }
  end, {
    select = function(_, query)
      local zoneList, zone = {}, nil
      if UI.ZoneMounts then zoneList, zone = UI.ZoneMounts() end
      title:SetText(string.format(L["Mounts in %s"], zone and zone.name or L["this zone"]))
      return UI.HereSelect(zoneList, query)
    end,
  })
  root.List = list
  return root
end

function view.Refresh()
  if not list then return end
  shownMap = ns.Game.PlayerMap()
  list:Refresh()
end

function view.IsShown()
  return root ~= nil and root:IsVisible() and true or false
end

-- A new map while on screen: redraw (from the top).
local events = CreateFrame("Frame")
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
  "PLAYER_ENTERING_WORLD" }) do
  events:RegisterEvent(event)
end
events:SetScript("OnEvent", function()
  if not view.IsShown() then return end
  if ns.Game.PlayerMap() == shownMap then return end
  shownMap = ns.Game.PlayerMap()
  list:Refresh(true)
end)

UI.RegisterView("here", view)
