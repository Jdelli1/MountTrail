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
--   "Whole window" (ns.db.global.settings.windowScale, 80-150 %: everything in
--                the main window, text included, UI.ApplyWindowScale), "Left
--                column" (settings.navTextSize, points added to the
--                navigation column's fonts, 0-6, default 2) and the text
--                sizes "Headers", "Mount names and text", "Small notes"
--                (Options.TEXT_LABELS): sliders, when the client has
--                Settings.CreateSlider,
--   "Show minimap button" (ns.db.global.minimap.hide, LibDBIcon Show / Hide),
--   "Debug messages" (ns.db.global.debug, the same flag as /mtrail debug),
--   "Reset all settings" (a button, when the client has
--                CreateSettingsButtonInitializer): after a warning
--                (Options.ConfirmReset, a StaticPopup), Options.ResetAll and a
--                reload of the interface.
-- `/mtrail options` opens it (Settings.OpenToCategory(category:GetID())). Every
-- Settings call is guarded: a client without the API simply has no page.

local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })

local Options = {}
ns.Options = Options

-- Proxy setting variable names: global to the settings system, so prefixed.
Options.UNOBTAINABLE = "MOUNTTRAIL_UNOBTAINABLE"
Options.COUNT_UNOBTAINABLE = "MOUNTTRAIL_COUNT_UNOBTAINABLE"
Options.MINIMAP = "MOUNTTRAIL_MINIMAP"
Options.RARITY_COLORS = "MOUNTTRAIL_RARITY_COLORS"
Options.RARITY_COLORS_MAIN = "MOUNTTRAIL_RARITY_COLORS_MAIN"
Options.COLORBLIND = "MOUNTTRAIL_COLORBLIND"
Options.DROP_CHIME = "MOUNTTRAIL_DROP_CHIME"
Options.DROP_SOUND = "MOUNTTRAIL_DROP_SOUND"
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
-- Named by what they size on screen (the roles are the fonts' colours:
-- header = gold, body = white, detail = grey).
Options.TEXT_LABELS = { header = "Headers", body = "Mount names and text", detail = "Small notes" }
Options.TEXT_TIPS = {
  header = "List headers (Classic, Wrath of the Lich King...), page titles and the labels in the detail pane.",
  body = "Every mount's name and where it comes from, in every list, Lockouts and Home, and the detail pane's text.",
  detail = "Counts and percentages, hints and greyed-out text.",
}
-- The order the sizes are offered in: the window's areas, left to right.
Options.TEXT_ORDER = { "header", "body", "detail" }
Options.NAV_LABEL = "Left column"
Options.NAV_TIP = "Home, Lockouts, Current Zone, Alts, Browse and your lists: the window's left column."
Options.SCALE_LABEL = "Whole window"
Options.SCALE_TIP = "Everything in the MountTrail window at once, text included. Use the sizes below for just one kind of text."

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
  Options.ApplyCounting()
  ns.Refresh()
end

-- "Count towards the total", under Show unobtainable mounts: the not-owned
-- unobtainable mounts it lists count in Home's numbers too (off by default;
-- only while they are shown).
function Options.CountUnobtainable()
  local global = ns.db and ns.db.global
  local saved = global and global.settings
  return type(saved) == "table" and saved.countUnobtainable == true
end

local function setCountUnobtainable(on)
  settings().countUnobtainable = on and true or nil
  Options.ApplyCounting()
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

-- Whether the main window's list names take their rarity colour (UI/List.lua
-- reads it: UI.ListRarityColor); apart from the pop-outs' (rarityColors).
function Options.RarityColorsMain()
  local global = ns.db and ns.db.global
  local saved = global and global.settings
  return type(saved) == "table" and saved.rarityColorsMain == true
end

local function setRarityColorsMain(on)
  settings().rarityColorsMain = on and true or nil
  ns.Refresh()
end

-- The drop alert's chime (UI/DropAlert.lua): off by default; the sound one of
-- UI.DROP_SOUNDS (settings.dropSound, the first by default).
function Options.DropChime()
  local global = ns.db and ns.db.global
  local saved = global and global.settings
  return type(saved) == "table" and saved.dropChime == true
end

function Options.DropSound()
  local global = ns.db and ns.db.global
  local saved = global and type(global.settings) == "table" and global.settings.dropSound
  local list = ns.UI and ns.UI.DROP_SOUNDS or {}
  for _, s in ipairs(list) do if s.key == saved then return saved end end
  return list[1] and list[1].key or nil
end

local function setDropChime(on)
  settings().dropChime = on and true or nil
end

-- Picking a sound plays it, so the player hears what they chose.
local function setDropSound(key)
  settings().dropSound = key
  if ns.Game and ns.Game.PlaySoundKit then ns.Game.PlaySoundKit(key) end
end

-- Accessibility: "Colour-blind marks" (settings.colorblindMarks): a tick on
-- finished lockouts and collected mounts, "open" on the left column's green
-- badges, the owners' share after rarity-coloured names. Until the player
-- sets it, it follows the game's Colorblind Mode (Game.ColorblindMode).
function Options.ColorblindMarks()
  local global = ns.db and ns.db.global
  local saved = global and type(global.settings) == "table" and global.settings.colorblindMarks
  if saved == true or saved == false then return saved end
  return ns.Game ~= nil and ns.Game.ColorblindMode ~= nil and ns.Game.ColorblindMode() == true
end

local function setColorblindMarks(on)
  settings().colorblindMarks = on and true or false
  ns.Refresh()
end

-- Counting: sections whose mounts the player can leave out of the collected
-- numbers (Journal.excluded; owned or not; still listed), each a checkbox,
-- on by default (stored as settings.excluded[section] = true when off).
Options.COUNT_SECTIONS = {
  { section = "shop", var = "MOUNTTRAIL_COUNT_SHOP", label = "Count in-game shop mounts",
    tip = "Mounts bought with real money in the in-game shop. Off: still listed, but left out of the collected numbers on Home." },
  { section = "tradingpost", var = "MOUNTTRAIL_COUNT_TRADINGPOST", label = "Count Trading Post mounts",
    tip = "Mounts from the monthly Trading Post. Off: still listed, but left out of the collected numbers on Home." },
  { section = "promotion", var = "MOUNTTRAIL_COUNT_PROMOTION", label = "Count promotional mounts",
    tip = "Trading card game, Recruit-a-Friend, collector's editions, BlizzCon and other promotions. Off: still listed, but left out of the collected numbers on Home." },
  { section = "bmah", var = "MOUNTTRAIL_COUNT_BMAH", label = "Count Black Market mounts",
    tip = "Mounts only sold on the Black Market Auction House. Off: still listed, but left out of the collected numbers on Home." },
}

local function excludedStore()
  local s = settings()
  if type(s.excluded) ~= "table" then s.excluded = {} end
  return s.excluded
end

-- Whether a section's mounts are counted (on by default).
function Options.Counted(section)
  local global = ns.db and ns.db.global
  local saved = global and type(global.settings) == "table" and global.settings.excluded
  return not (type(saved) == "table" and saved[section] == true)
end

-- Hands the saved choices to the gate (Journal.SetExcluded).
function Options.ApplyCounting()
  if not (ns.db and ns.Journal) then return end
  local set = {}
  for _, c in ipairs(Options.COUNT_SECTIONS) do
    if not Options.Counted(c.section) then set[c.section] = true end
  end
  ns.Journal.SetExcluded(set)
  ns.Journal.countUnobtainable = Options.ShowUnobtainable() and Options.CountUnobtainable()
end

function Options.SetCounted(section, on)
  if not ns.db then return end
  excludedStore()[section] = (not on) or nil
  Options.ApplyCounting()
  if ns.UI and ns.UI.ForgetHomeNearby then ns.UI.ForgetHomeNearby() end
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
  elseif name == "rarityColorsMain" then setRarityColorsMain(value)
  elseif name == "countUnobtainable" then setCountUnobtainable(value)
  elseif name == "colorblindMarks" then setColorblindMarks(value)
  elseif name == "dropChime" then setDropChime(value)
  elseif name == "dropSound" then setDropSound(value)
  elseif name == "difficultyWarning" then setDifficultyWarning(value)
  elseif name == "minimap" then Options.SetMinimap(value)
  elseif name == "showLists" or name == "showQuick" then
    -- Stored as "hide" flags, so a missing value (the default) shows them.
    settings()[name == "showLists" and "navHideLists" or "navHideQuick"] = (not value) or nil
    if ns.UI and ns.UI.RefreshNav then ns.UI.RefreshNav() end
  end
  if type(name) == "string" and string.sub(name, 1, 6) == "count:" then
    Options.SetCounted(string.sub(name, 7), value)
  end
  for _, var in pairs({ Options.WINDOW_SCALE, Options.NAV_TEXT, Options.UNOBTAINABLE, Options.RARITY_COLORS,
    Options.RARITY_COLORS_MAIN, Options.COUNT_UNOBTAINABLE, Options.COLORBLIND, Options.DROP_CHIME,
    Options.DROP_SOUND, Options.MINIMAP, Options.SHOW_LISTS, Options.SHOW_QUICK,
    Options.DIFFICULTY_WARNING }) do
    Options.Changed(var)
  end
  for _, c in ipairs(Options.COUNT_SECTIONS) do Options.Changed(c.var) end
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

-- Puts every setting back to its default: the options and text sizes, the
-- window (size, position, view, column widths), the appearance of every
-- window and pop-out (and their sizes and positions), the minimap button,
-- the list filters, the zone panel, debug, and this character's Lockouts
-- filters. Kept: lists, attempts, kill statistics, lockout ticks,
-- rare-spawn checks, the alts, collapsed headers and the navigation's order
-- and favourites (the player's own data, not settings). global / char:
-- ns.db.global / ns.db.char.
function Options.ResetAll(global, char)
  if type(global) ~= "table" then return end
  global.settings = { showUnobtainable = false, rarityColors = false }
  if ns.Journal and ns.Journal.SetExcluded then ns.Journal.SetExcluded({}) end
  if ns.Journal then ns.Journal.countUnobtainable = false end
  global.window = {}
  global.filters = {}
  for k, v in pairs(ns.Journal and ns.Journal.DefaultFilters or {}) do
    global.filters[k] = type(v) == "table" and {} or v
    if type(v) == "table" then for k2, v2 in pairs(v) do global.filters[k][k2] = v2 end end
  end
  global.minimap = { hide = false }
  global.zonePanel = { open = false }
  global.altsWindow = {}
  global.debug = false
  global.popoutStyle = nil
  for _, state in pairs(type(global.popouts) == "table" and global.popouts or {}) do
    if type(state) == "table" then
      state.style, state.width, state.height = nil, nil, nil
      state.point, state.relPoint, state.x, state.y = nil, nil, nil, nil
    end
  end
  if type(char) == "table" then
    char.checklistFilters = {}
    char.checklistShow = nil
  end
end

-- The warning before Options.ResetAll; accepting resets, then reloads the
-- interface so every window starts from the defaults.
Options.RESET_POPUP = "MOUNTTRAIL_RESET_SETTINGS"

function Options.ConfirmReset()
  if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return false end
  StaticPopupDialogs[Options.RESET_POPUP] = StaticPopupDialogs[Options.RESET_POPUP] or {
    text = L["Reset every MountTrail setting to its default?\n\nOptions, text sizes, window size and position, and the look of every window and pop-out go back to the defaults. Your lists, attempts and lockouts are kept.\n\nThe interface reloads."],
    button1 = L["Reset"],
    button2 = L["Cancel"],
    showAlert = true,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function()
      if not ns.db then return end
      Options.ResetAll(ns.db.global, ns.db.char)
      if type(ReloadUI) == "function" then ReloadUI() elseif ns.Refresh then ns.Refresh() end
    end,
  }
  StaticPopup_Show(Options.RESET_POPUP)
  return true
end

local REQUIRED = { "RegisterVerticalLayoutCategory", "RegisterProxySetting", "CreateCheckbox",
  "RegisterAddOnCategory" }

local function build(api)
  local VarType = type(api.VarType) == "table" and api.VarType or {}
  local category, layout = api.RegisterVerticalLayoutCategory(L["MountTrail"])

  local unobtainable = api.RegisterProxySetting(category, Options.UNOBTAINABLE, VarType.Boolean or "boolean",
    L["Show unobtainable mounts"], false, Options.ShowUnobtainable, setUnobtainable)
  local showInit = api.CreateCheckbox(category, unobtainable,
    L["List mounts you can no longer get on the Misc tab, under Unobtainable. Collected ones stay where they are."])
  -- Its sub-option: greyed out while Show is off (where the client can).
  local countUnobtainable = api.RegisterProxySetting(category, Options.COUNT_UNOBTAINABLE,
    VarType.Boolean or "boolean", L["Count towards the total"], false, Options.CountUnobtainable,
    setCountUnobtainable)
  local countInit = api.CreateCheckbox(category, countUnobtainable,
    L["Also count the unobtainable mounts you do not own in Home's collected numbers (total, expansions, sources). Owned ones always count."])
  if type(countInit) == "table" and type(countInit.SetParentInitializer) == "function" and showInit then
    countInit:SetParentInitializer(showInit, function() return Options.ShowUnobtainable() end)
  end

  -- What is counted: each optional section (in-game shop, ...).
  for _, c in ipairs(Options.COUNT_SECTIONS) do
    local setting = api.RegisterProxySetting(category, c.var, VarType.Boolean or "boolean", L[c.label], true,
      function() return Options.Counted(c.section) end, function(on) Options.SetCounted(c.section, on) end)
    api.CreateCheckbox(category, setting, L[c.tip])
  end

  local rarity = api.RegisterProxySetting(category, Options.RARITY_COLORS, VarType.Boolean or "boolean",
    L["Colour pop-out names by rarity"], false, Options.RarityColors, setRarityColors)
  api.CreateCheckbox(category, rarity,
    L["Colour each pop-out row by how many characters own the mount (legendary under 2 %, epic under 10 %, rare under 20 %, uncommon under 50 %). Needs Mount Journal Enhanced or the MountsRarity add-on."])

  local rarityMain = api.RegisterProxySetting(category, Options.RARITY_COLORS_MAIN, VarType.Boolean or "boolean",
    L["Colour list names by rarity"], false, Options.RarityColorsMain, setRarityColorsMain)
  api.CreateCheckbox(category, rarityMain,
    L["The same colours for the mount names in the main window's lists (Lockouts, Browse, your lists...). Needs Mount Journal Enhanced or the MountsRarity add-on."])

  local difficulty = api.RegisterProxySetting(category, Options.DIFFICULTY_WARNING, VarType.Boolean or "boolean",
    L["Warn about the wrong difficulty"], true, Options.DifficultyWarning, setDifficultyWarning)
  api.CreateCheckbox(category, difficulty,
    L["Entering an instance on a difficulty where a mount in your open pop-outs does not drop (Normal instead of Heroic, Heroic instead of Mythic...) shows a warning."])

  -- The sliders, on clients that have them.
  if type(api.CreateSlider) == "function" and type(api.CreateSliderOptions) == "function" then
    local scale = api.RegisterProxySetting(category, Options.WINDOW_SCALE, VarType.Number or "number",
      L[Options.SCALE_LABEL], 100, Options.WindowScale, setWindowScale)
    slider(api, category, scale, Options.SCALE_RANGE, function(v) return string.format("%d%%", v) end,
      L[Options.SCALE_TIP])
    local navText = api.RegisterProxySetting(category, Options.NAV_TEXT, VarType.Number or "number",
      L[Options.NAV_LABEL], 2, Options.NavTextSize, setNavTextSize)
    slider(api, category, navText, Options.NAV_TEXT_RANGE, function(v) return string.format("+%d", v) end,
      L[Options.NAV_TIP])
    for _, role in ipairs(Options.TEXT_ORDER) do
      local setting = api.RegisterProxySetting(category, Options.TEXT_VARS[role], VarType.Number or "number",
        L[Options.TEXT_LABELS[role]], 0, function() return Options.TextSize(role) end,
        function(v) Options.SetTextSize(role, v) end)
      slider(api, category, setting, Options.TEXT_RANGE, function(v) return string.format("%+d", v) end,
        L[Options.TEXT_TIPS[role]])
    end
  end

  -- The navigation's list sections.
  for _, s in ipairs({
    { var = Options.SHOW_LISTS, name = "showLists", hide = "navHideLists", label = "Show your lists",
      tip = "Your own lists, under Lists in the window's left column." },
    { var = Options.SHOW_QUICK, name = "showQuick", hide = "navHideQuick", label = "Show built-in lists",
      tip = "The built-in lists that fill themselves (Daily / Weekly lockouts, Rare Spawns), at the top of Lists." },
  }) do
    local setting = api.RegisterProxySetting(category, s.var, VarType.Boolean or "boolean", L[s.label], true,
      function() return settings()[s.hide] ~= true end, function(on) Options.Set(s.name, on) end)
    api.CreateCheckbox(category, setting, L[s.tip])
  end

  local minimap = api.RegisterProxySetting(category, Options.MINIMAP, VarType.Boolean or "boolean",
    L["Show minimap button"], true, getMinimap, setMinimap)
  api.CreateCheckbox(category, minimap, L["Show the MountTrail button on the minimap."])

  -- The drop alert's chime and its sound (a dropdown where the client has one).
  local chime = api.RegisterProxySetting(category, Options.DROP_CHIME, VarType.Boolean or "boolean",
    L["Chime when a mount drops"], false, Options.DropChime, setDropChime)
  api.CreateCheckbox(category, chime,
    L["Play a sound when you learn a mount MountTrail tracks (the chat line says how many attempts it took either way)."])
  if type(api.CreateDropdown) == "function" and type(api.CreateControlTextContainer) == "function" then
    local sound = api.RegisterProxySetting(category, Options.DROP_SOUND, VarType.String or "string",
      L["Drop sound"], ns.UI and ns.UI.DROP_SOUNDS[1] and ns.UI.DROP_SOUNDS[1].key or "", Options.DropSound, setDropSound)
    api.CreateDropdown(category, sound, function()
      local container = api.CreateControlTextContainer()
      for _, s in ipairs(ns.UI and ns.UI.DropSounds and ns.UI.DropSounds() or {}) do container:Add(s.key, L[s.label]) end
      return container:GetData()
    end, L["The chime's sound; picking one plays it."])
  end

  -- Accessibility (a section header where the client has one).
  if layout and type(layout.AddInitializer) == "function"
    and type(CreateSettingsListSectionHeaderInitializer) == "function" then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Accessibility"]))
  end
  local colorblind = api.RegisterProxySetting(category, Options.COLORBLIND, VarType.Boolean or "boolean",
    L["Colour-blind marks"], false, Options.ColorblindMarks, setColorblindMarks)
  api.CreateCheckbox(category, colorblind,
    L["Say in text or shape what a colour says: a tick on finished lockouts and collected mounts, \"open\" on your lists' green counts, the share of characters owning a mount after a rarity-coloured name. Starts as the game's Colorblind Mode (Options > Accessibility)."])

  local debug = api.RegisterProxySetting(category, Options.DEBUG, VarType.Boolean or "boolean",
    L["Debug messages"], false, getDebug, setDebug)
  api.CreateCheckbox(category, debug,
    L["Show errors MountTrail catches around maps and waypoints (same as /mtrail debug)."])

  -- Reset all settings: a button (with a warning first) on clients that have it.
  if layout and type(layout.AddInitializer) == "function" and type(CreateSettingsButtonInitializer) == "function" then
    layout:AddInitializer(CreateSettingsButtonInitializer(L["Reset all settings"], L["Reset"],
      function() Options.ConfirmReset() end,
      L["Every MountTrail setting back to its default, after a warning. Your lists, attempts and lockouts are kept."],
      true))
  end

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
  Options.ApplyCounting()
  Options.Register()
else
  local loginFrame = CreateFrame("Frame")
  loginFrame:RegisterEvent("PLAYER_LOGIN")
  loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    Options.ApplyCounting()
    Options.Register()
  end)
end
