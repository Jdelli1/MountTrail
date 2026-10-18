local ADDON, ns = ...

-- Options > AddOns > AzerothTrail (F9), built with the modern Settings API: a
-- vertical-layout category (Settings.RegisterVerticalLayoutCategory) with
-- proxy settings over our own saved variables, registered with
-- Settings.RegisterAddOnCategory on PLAYER_LOGIN (after AceDB's
-- OnInitialize, so ns.db exists). The page holds:
--   "Waypoints": In-game map pin / TomTom arrow / Both
--                (ns.db.global.settings.waypoints, read by Map.SetWaypoint;
--                the TomTom choices fall back to the in-game pin when TomTom
--                is not loaded, as the labels and tooltips say),
--   "Show unobtainable mounts" (ns.db.global.settings.showUnobtainable: off by
--                default; on lists not-owned unobtainable mounts on the Misc
--                tab under "Unobtainable"; a change refreshes the window),
--   "Show minimap button" (ns.db.global.minimap.hide, LibDBIcon Show / Hide),
--   "Debug messages" (ns.db.global.debug, the same flag as /azt debug).
-- `/azt options` opens it (Settings.OpenToCategory(category:GetID())). Every
-- Settings call is guarded: a client without the API simply has no page.

local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })

local Options = {}
ns.Options = Options

-- Proxy setting variable names: global to the settings system, so prefixed.
Options.WAYPOINTS = "AZEROTHTRAIL_WAYPOINTS"
Options.UNOBTAINABLE = "AZEROTHTRAIL_UNOBTAINABLE"
Options.MINIMAP = "AZEROTHTRAIL_MINIMAP"
Options.DEBUG = "AZEROTHTRAIL_DEBUG"

local MODES = { "game", "tomtom", "both" }
local VALID = { game = true, tomtom = true, both = true }

-- The dropdown's entries -> { { value =, label =, tooltip = } } in order.
-- Without TomTom the TomTom choices say they use the in-game pin instead.
function Options.WaypointOptions(tomtomLoaded)
  local fallback = L["TomTom is not loaded: the in-game map pin is used instead."]
  return {
    { value = "game", label = L["In-game map pin"],
      tooltip = L["The game's own map pin, tracked on screen."] },
    { value = "tomtom", label = tomtomLoaded and L["TomTom arrow"] or L["TomTom arrow (not loaded)"],
      tooltip = tomtomLoaded and L["Only a TomTom waypoint and its arrow."] or fallback },
    { value = "both", label = tomtomLoaded and L["Both"] or L["Both (TomTom not loaded)"],
      tooltip = tomtomLoaded and L["The in-game map pin and a TomTom waypoint."] or fallback },
  }
end

-- Whether TomTom is loaded (its global, as Integrations/Map.lua uses it).
local function tomtomLoaded()
  return type(TomTom) == "table"
end

-- ns.db.global.settings, created when missing.
local function settings()
  local global = ns.db.global
  if type(global.settings) ~= "table" then global.settings = {} end
  return global.settings
end

local function getWaypoints()
  local mode = settings().waypoints
  return VALID[mode] and mode or "game"
end

local function setWaypoints(value)
  if VALID[value] then settings().waypoints = value end
end

-- Whether not-owned unobtainable mounts are listed (on Misc); false without
-- a db.
function Options.ShowUnobtainable()
  local global = ns.db and ns.db.global
  local saved = global and global.settings
  return type(saved) == "table" and saved.showUnobtainable == true
end

-- Saves the choice and redraws the open window (UI\List.lua reads it).
local function setUnobtainable(on)
  settings().showUnobtainable = on and true or false
  ns.Refresh()
end

local function minimapDb()
  local global = ns.db.global
  if type(global.minimap) ~= "table" then global.minimap = { hide = false } end
  return global.minimap
end

local function getMinimap()
  return not minimapDb().hide
end

-- Shows or hides the minimap button (LibDBIcon reads `hide` only when it
-- registers the button, so it is told as well).
local function setMinimap(shown)
  minimapDb().hide = not shown
  local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
  if type(DBIcon) ~= "table" then return end
  local method = shown and DBIcon.Show or DBIcon.Hide
  if type(method) == "function" then pcall(method, DBIcon, ADDON) end
end

local function getDebug()
  return ns.db.global.debug == true
end

local function setDebug(on)
  ns.db.global.debug = on and true or false
end

local function report(err)
  local game = ns.Game
  if game and type(game.ReportError) == "function" then game.ReportError(err) end
end

local REQUIRED = { "RegisterVerticalLayoutCategory", "RegisterProxySetting", "CreateDropdown",
  "CreateCheckbox", "CreateControlTextContainer", "RegisterAddOnCategory" }

local function build(api)
  local VarType = type(api.VarType) == "table" and api.VarType or {}
  local category = api.RegisterVerticalLayoutCategory(L["AzerothTrail"])

  local waypoints = api.RegisterProxySetting(category, Options.WAYPOINTS, VarType.String or "string",
    L["Waypoints"], "game", getWaypoints, setWaypoints)
  local function waypointOptions()
    local container = api.CreateControlTextContainer()
    for _, option in ipairs(Options.WaypointOptions(tomtomLoaded())) do
      container:Add(option.value, option.label, option.tooltip)
    end
    return container:GetData()
  end
  api.CreateDropdown(category, waypoints, waypointOptions,
    L["Where a mount row's left-click puts the waypoint. TomTom arrow and Both need TomTom; without it the in-game map pin is used."])

  local unobtainable = api.RegisterProxySetting(category, Options.UNOBTAINABLE, VarType.Boolean or "boolean",
    L["Show unobtainable mounts"], false, Options.ShowUnobtainable, setUnobtainable)
  api.CreateCheckbox(category, unobtainable,
    L["List mounts you can no longer get on the Misc tab, under Unobtainable. Collected ones stay where they are."])

  local minimap = api.RegisterProxySetting(category, Options.MINIMAP, VarType.Boolean or "boolean",
    L["Show minimap button"], true, getMinimap, setMinimap)
  api.CreateCheckbox(category, minimap, L["Show the AzerothTrail button on the minimap."])

  local debug = api.RegisterProxySetting(category, Options.DEBUG, VarType.Boolean or "boolean",
    L["Debug messages"], false, getDebug, setDebug)
  api.CreateCheckbox(category, debug,
    L["Show errors AzerothTrail catches around maps, waypoints and the arrow (same as /azt debug)."])

  api.RegisterAddOnCategory(category)
  return category
end

-- Registers the page with `api` (the Settings table, default the global) ->
-- the category, or nil when the API is missing, ns.db does not exist yet, or a
-- call failed (reported with /azt debug). Registers once.
function Options.Register(api)
  if Options.category then return Options.category end
  if api == nil then api = Settings end
  if type(api) ~= "table" or not ns.db then return nil end
  for _, name in ipairs(REQUIRED) do
    if type(api[name]) ~= "function" then return nil end
  end
  local good, category = pcall(build, api)
  if not good then
    report(category)
    return nil
  end
  Options.category = category
  return category
end

local function say(msg)
  local addon = ns.addon
  if addon and addon.Print then addon:Print(msg) else print(msg) end
end

-- Opens the settings panel at our page -> true when asked to open.
function Options.Open(api)
  if api == nil then api = Settings end
  local category = Options.category or Options.Register(api)
  if not (category and type(api) == "table" and type(api.OpenToCategory) == "function") then
    say(L["The options page is not available on this client."])
    return false
  end
  local good, err = pcall(function() api.OpenToCategory(category:GetID()) end)
  if not good then
    report(err)
    say(L["The options page is not available on this client."])
    return false
  end
  return true
end

-- Tells an open settings page that `variable` changed elsewhere (e.g. the
-- debug flag via /azt debug), so its control shows the new value.
function Options.Changed(variable, api)
  if api == nil then api = Settings end
  if not (Options.category and type(api) == "table" and type(api.NotifyUpdate) == "function") then return end
  local good, err = pcall(api.NotifyUpdate, variable)
  if not good then report(err) end
end

if IsLoggedIn() then
  Options.Register()
else
  local loginFrame = CreateFrame("Frame")
  loginFrame:RegisterEvent("PLAYER_LOGIN")
  loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    Options.Register()
  end)
end
