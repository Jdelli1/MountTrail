local ADDON, ns = ...

-- Options > AddOns > MountTrail (F9), built with the modern Settings API: a
-- vertical-layout category (Settings.RegisterVerticalLayoutCategory) with
-- proxy settings over our own saved variables, registered with
-- Settings.RegisterAddOnCategory on PLAYER_LOGIN (after AceDB's
-- OnInitialize, so ns.db exists). The page holds (waypoints are always
-- TomTom's, Integrations/Map.lua: no setting):
--   "Show unobtainable mounts" (ns.db.global.settings.showUnobtainable: off by
--                default; on lists not-owned unobtainable mounts on the Misc
--                tab under "Unobtainable"; a change refreshes the window),
--   "Colour pop-out names by rarity" (ns.db.global.settings.rarityColors: off
--                by default; pop-out rows take the quality colour of how many
--                characters own the mount, Integrations/MountsRarity.lua),
--   "Window scale" (ns.db.global.settings.windowScale, 80-150 %: everything in
--                the main window, text included, UI.ApplyWindowScale) and
--                "Navigation text size" (settings.navTextSize, points added to
--                the navigation column's fonts, 0-6, default 2): sliders,
--                when the client has Settings.CreateSlider,
--   "Show minimap button" (ns.db.global.minimap.hide, LibDBIcon Show / Hide),
--   "Debug messages" (ns.db.global.debug, the same flag as /mtrail debug).
-- `/mtrail options` opens it (Settings.OpenToCategory(category:GetID())). Every
-- Settings call is guarded: a client without the API simply has no page.

local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })

local Options = {}
ns.Options = Options

-- Proxy setting variable names: global to the settings system, so prefixed.
Options.UNOBTAINABLE = "MOUNTTRAIL_UNOBTAINABLE"
Options.MINIMAP = "MOUNTTRAIL_MINIMAP"
Options.RARITY_COLORS = "MOUNTTRAIL_RARITY_COLORS"
Options.WINDOW_SCALE = "MOUNTTRAIL_WINDOW_SCALE"
Options.SHOW_LISTS = "MOUNTTRAIL_SHOW_LISTS"
Options.SHOW_QUICK = "MOUNTTRAIL_SHOW_QUICK"
Options.NAV_TEXT = "MOUNTTRAIL_NAV_TEXT"
Options.DIFFICULTY_WARNING = "MOUNTTRAIL_DIFFICULTY_WARNING"

-- Slider ranges (whole percent for the scale).
Options.SCALE_RANGE = { min = 80, max = 150, step = 5 }
Options.NAV_TEXT_RANGE = { min = 0, max = 6, step = 1 }

local function clamp(v, range, default)
  v = tonumber(v)
  if not v then return default end
  return math.max(range.min, math.min(range.max, math.floor(v / range.step + 0.5) * range.step))
end

-- The window scale in percent (80-150, default 100).
function Options.WindowScale()
  local global = ns.db and ns.db.global
  local saved = global and type(global.settings) == "table" and global.settings.windowScale or nil
  return clamp(saved, Options.SCALE_RANGE, 100)
end

-- Text sizes by colour (UI.FONT_ROLES): gold (headers, titles, mount
-- names), white (body text), grey (second lines): points added, -2..+6.
Options.TEXT_RANGE = { min = -2, max = 6, step = 1 }
Options.TEXT_KEYS = { header = "textHeader", body = "textBody", detail = "textDetail" }
Options.TEXT_VARS = { header = "MOUNTTRAIL_TEXT_HEADER", body = "MOUNTTRAIL_TEXT_BODY", detail = "MOUNTTRAIL_TEXT_DETAIL" }
Options.TEXT_LABELS = { header = "Gold text size", body = "White text size", detail = "Grey text size" }
Options.TEXT_TIPS = {
  header = "Headers, titles and mount names (the gold text).",
  body = "The white text: row names, counts and lines in the detail pane.",
  detail = "The grey second lines: sources, zones and hints.",
}

function Options.TextSize(role)
  local key = Options.TEXT_KEYS[role]
  local global = ns.db and ns.db.global
  local saved = key and global and type(global.settings) == "table" and global.settings[key] or nil
  return clamp(saved, Options.TEXT_RANGE, 0)
end

function Options.SetTextSize(role, points)
  local key = Options.TEXT_KEYS[role]
  if not key or not ns.db then return end
  local global = ns.db.global
  if type(global.settings) ~= "table" then global.settings = {} end
  global.settings[key] = clamp(points, Options.TEXT_RANGE, 0)
  if ns.UI and ns.UI.ApplyTextSizes then ns.UI.ApplyTextSizes() end
end

-- Points added to the navigation's fonts (0-6, default 2).
function Options.NavTextSize()
  local global = ns.db and ns.db.global
  local saved = global and type(global.settings) == "table" and global.settings.navTextSize or nil
  return clamp(saved, Options.NAV_TEXT_RANGE, 2)
end
Options.DEBUG = "MOUNTTRAIL_DEBUG"

-- ns.db.global.settings, created when missing.
local function settings()
  local global = ns.db.global
  if type(global.settings) ~= "table" then global.settings = {} end
  return global.settings
end

-- Whether not-owned unobtainable mounts are listed (on Misc): the list's own
-- reader (UI.ShowUnobtainable, UI\List.lua) when loaded, else the saved
-- setting; false without a db.
function Options.ShowUnobtainable()
  local UI = ns.UI
  if UI and type(UI.ShowUnobtainable) == "function" then return UI.ShowUnobtainable() end
  local global = ns.db and ns.db.global
  local saved = global and global.settings
  return type(saved) == "table" and saved.showUnobtainable == true
end

-- Saves the choice and redraws the open window (UI\List.lua reads it).
local function setUnobtainable(on)
  settings().showUnobtainable = on and true or false
  ns.Refresh()
end

-- Whether pop-out names take their rarity colour (UI/Popouts.lua reads it).
function Options.RarityColors()
  local global = ns.db and ns.db.global
  local saved = global and global.settings
  return type(saved) == "table" and saved.rarityColors == true
end

-- Saves the choice and redraws the pop-outs.
local function setRarityColors(on)
  settings().rarityColors = on and true or false
  ns.Refresh()
end

-- Whether the wrong-difficulty warning is on (UI/DifficultyCheck.lua; on by
-- default: stored as settings.difficultyWarnOff).
function Options.DifficultyWarning()
  local global = ns.db and ns.db.global
  local saved = global and global.settings
  return not (type(saved) == "table" and saved.difficultyWarnOff == true)
end

local function setDifficultyWarning(on)
  settings().difficultyWarnOff = (not on) or nil
end

local function setWindowScale(pct)
  settings().windowScale = clamp(pct, Options.SCALE_RANGE, 100)
  if ns.UI and ns.UI.ApplyWindowScale then ns.UI.ApplyWindowScale() end
end

local function setNavTextSize(points)
  settings().navTextSize = clamp(points, Options.NAV_TEXT_RANGE, 2)
  if ns.UI and ns.UI.RefreshNav then ns.UI.RefreshNav() end
end

-- A slider on `category` (Settings.CreateSliderOptions / CreateSlider) with
-- `format(value)` as its label; nothing on clients without them.
local function slider(api, category, setting, range, format, tooltip)
  if type(api.CreateSlider) ~= "function" or type(api.CreateSliderOptions) ~= "function" then return end
  local options = api.CreateSliderOptions(range.min, range.max, range.step)
  local mixin = MinimalSliderWithSteppersMixin
  if options and options.SetLabelFormatter and type(mixin) == "table" and mixin.Label then
    options:SetLabelFormatter(mixin.Label.Right, format)
  end
  api.CreateSlider(category, setting, options, tooltip)
end

-- One setting by name, for the window's settings menu (UI.SettingsMenuItems):
-- windowScale, navTextSize, showUnobtainable, rarityColors, minimap (shown).
function Options.Set(name, value)
  if not ns.db then return end
  if name == "windowScale" then setWindowScale(value)
  elseif name == "navTextSize" then setNavTextSize(value)
  elseif name == "showUnobtainable" then setUnobtainable(value)
  elseif name == "rarityColors" then setRarityColors(value)
  elseif name == "difficultyWarning" then setDifficultyWarning(value)
  elseif name == "minimap" then Options.SetMinimap(value)
  elseif name == "showLists" or name == "showQuick" then
    -- Stored as "hide" flags, so a missing value (the default) shows them.
    settings()[name == "showLists" and "navHideLists" or "navHideQuick"] = (not value) or nil
    if ns.UI and ns.UI.RefreshNav then ns.UI.RefreshNav() end
  end
  for _, var in pairs({ Options.WINDOW_SCALE, Options.NAV_TEXT, Options.UNOBTAINABLE, Options.RARITY_COLORS,
    Options.MINIMAP, Options.SHOW_LISTS, Options.SHOW_QUICK, Options.DIFFICULTY_WARNING }) do
    Options.Changed(var)
  end
end

-- Every text size back to the game's (0), the navigation's to +2.
function Options.ResetTextSizes()
  if not ns.db then return end
  local s = settings()
  s.textHeader, s.textBody, s.textDetail, s.navTextSize = nil, nil, nil, nil
  if ns.UI and ns.UI.ApplyTextSizes then ns.UI.ApplyTextSizes() end
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
Options.SetMinimap = setMinimap

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

local REQUIRED = { "RegisterVerticalLayoutCategory", "RegisterProxySetting", "CreateCheckbox",
  "RegisterAddOnCategory" }

local function build(api)
  local VarType = type(api.VarType) == "table" and api.VarType or {}
  local category = api.RegisterVerticalLayoutCategory(L["MountTrail"])

  local unobtainable = api.RegisterProxySetting(category, Options.UNOBTAINABLE, VarType.Boolean or "boolean",
    L["Show unobtainable mounts"], false, Options.ShowUnobtainable, setUnobtainable)
  api.CreateCheckbox(category, unobtainable,
    L["List mounts you can no longer get on the Misc tab, under Unobtainable. Collected ones stay where they are."])

  local rarity = api.RegisterProxySetting(category, Options.RARITY_COLORS, VarType.Boolean or "boolean",
    L["Colour pop-out names by rarity"], false, Options.RarityColors, setRarityColors)
  api.CreateCheckbox(category, rarity,
    L["Colour each pop-out row by how many characters own the mount (legendary under 2 %, epic under 10 %, rare under 20 %, uncommon under 50 %). Needs Mount Journal Enhanced or the MountsRarity add-on."])

  local difficulty = api.RegisterProxySetting(category, Options.DIFFICULTY_WARNING, VarType.Boolean or "boolean",
    L["Warn about the wrong difficulty"], true, Options.DifficultyWarning, setDifficultyWarning)
  api.CreateCheckbox(category, difficulty,
    L["Entering an instance on a difficulty where a mount in your open pop-outs does not drop (Normal instead of Heroic, Heroic instead of Mythic...) shows a warning."])

  -- The sliders, on clients that have them.
  if type(api.CreateSlider) == "function" and type(api.CreateSliderOptions) == "function" then
    local scale = api.RegisterProxySetting(category, Options.WINDOW_SCALE, VarType.Number or "number",
      L["Window scale"], 100, Options.WindowScale, setWindowScale)
    slider(api, category, scale, Options.SCALE_RANGE, function(v) return string.format("%d%%", v) end,
      L["Size of the MountTrail window and everything in it, text included."])
    for _, role in ipairs({ "header", "body", "detail" }) do
      local setting = api.RegisterProxySetting(category, Options.TEXT_VARS[role], VarType.Number or "number",
        L[Options.TEXT_LABELS[role]], 0, function() return Options.TextSize(role) end,
        function(v) Options.SetTextSize(role, v) end)
      slider(api, category, setting, Options.TEXT_RANGE, function(v) return string.format("%+d", v) end,
        L[Options.TEXT_TIPS[role]])
    end
    local navText = api.RegisterProxySetting(category, Options.NAV_TEXT, VarType.Number or "number",
      L["Navigation text size"], 2, Options.NavTextSize, setNavTextSize)
    slider(api, category, navText, Options.NAV_TEXT_RANGE, function(v) return string.format("+%d", v) end,
      L["Points added to the text of the window's left column."])
  end

  -- The navigation's list sections.
  for _, s in ipairs({
    { var = Options.SHOW_LISTS, name = "showLists", hide = "navHideLists", label = "Show My lists",
      tip = "Your own lists in the window's left column." },
    { var = Options.SHOW_QUICK, name = "showQuick", hide = "navHideQuick", label = "Show Quick lists",
      tip = "The built-in lists (Daily / Weekly lockouts, Rare Spawns) in the window's left column." },
  }) do
    local setting = api.RegisterProxySetting(category, s.var, VarType.Boolean or "boolean", L[s.label], true,
      function() return settings()[s.hide] ~= true end, function(on) Options.Set(s.name, on) end)
    api.CreateCheckbox(category, setting, L[s.tip])
  end

  local minimap = api.RegisterProxySetting(category, Options.MINIMAP, VarType.Boolean or "boolean",
    L["Show minimap button"], true, getMinimap, setMinimap)
  api.CreateCheckbox(category, minimap, L["Show the MountTrail button on the minimap."])

  local debug = api.RegisterProxySetting(category, Options.DEBUG, VarType.Boolean or "boolean",
    L["Debug messages"], false, getDebug, setDebug)
  api.CreateCheckbox(category, debug,
    L["Show errors MountTrail catches around maps and waypoints (same as /mtrail debug)."])

  api.RegisterAddOnCategory(category)
  return category
end

-- Registers the page with `api` (the Settings table, default the global) ->
-- the category, or nil when the API is missing, ns.db does not exist yet, or a
-- call failed (reported with /mtrail debug). Registers once.
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
-- debug flag via /mtrail debug), so its control shows the new value.
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
