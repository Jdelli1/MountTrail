local ADDON, ns = ...

-- The browse view: one Browse category (Logic/Browse.lua: Drops, Vendors &
-- Reputation, ...) as a full list with the detail pane, grouped by
-- expansion, under a strip naming the category. The navigation column's
-- Browse entries pick the category (UI.ShowBrowse); it is saved with the
-- window (ns.db.global.window.browse) and comes back with it.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local view = {}
UI.BrowseView = view

local root, list, title
local current = "drops"

local function windowDB()
  local global = ns.db and ns.db.global
  if not global then return nil end
  if type(global.window) ~= "table" then global.window = {} end
  return global.window
end

-- The category on screen (its key).
function UI.BrowseCategory()
  local db = windowDB()
  local saved = db and db.browse
  if saved and ns.Browse.Get(saved) and not ns.Browse.Get(saved).view then current = saved end
  return current
end

-- Shows category `key` (a browse page; a category with its own view opens
-- that view instead).
function UI.ShowBrowse(key)
  local c = ns.Browse.Get(key)
  if not c then return end
  if c.view then
    UI.SelectTab(c.view)
    return
  end
  current = key
  local db = windowDB()
  if db then db.browse = key end
  if UI.CurrentTab and UI.CurrentTab() == "browse" then
    view.Refresh(true)
    if UI.RefreshNav then UI.RefreshNav() end
  else
    UI.SelectTab("browse")
  end
end

function view.Build(parent)
  root = CreateFrame("Frame", nil, parent)
  root:SetAllPoints(parent)
  local strip = root:CreateTexture(nil, "BACKGROUND")
  strip:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  strip:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
  strip:SetHeight(30)
  strip:SetColorTexture(1, 1, 1, 0.04)
  title = root:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalLarge"))
  title:SetPoint("LEFT", root, "TOPLEFT", 10, -15)
  root.Title = title
  local holder = CreateFrame("Frame", nil, root)
  holder:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -36)
  holder:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  list = UI.List(holder, function()
    return { view = "browse", exp = UI.BrowseCategory(), sourceText = ns.Game.MountSourceText }
  end, {
    select = function(mounts, query)
      return ns.Browse.Select(UI.BrowseCategory(), mounts, query, ns.Data and ns.Data.Expansions)
    end,
  })
  root.List = list
  return root
end

function view.Refresh(resetScroll)
  if not list then return end
  local c = ns.Browse.Get(UI.BrowseCategory())
  title:SetText(c and L[c.label] or "")
  list:Refresh(resetScroll)
end

UI.RegisterView("browse", view)
