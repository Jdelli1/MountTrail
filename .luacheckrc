-- luacheck configuration for MountTrail (https://github.com/lunarmodules/luacheck).
-- Run from the repository root: luacheck .
-- The game runs Lua 5.1; the addon's own globals are only its saved variables.

std = "lua51"
max_line_length = false
codes = true

exclude_files = {
  "Libs/",        -- bundled third-party libraries, never edited
  "tools/",       -- Python tools and their Lua fixtures (Rarity samples)
  ".claude/",
  ".superpowers/",
}

ignore = {
  "211/ADDON",    -- every file opens with `local ADDON, ns = ...`; most never use ADDON
  "212",          -- unused arguments (`self`, event payloads, WoW callback signatures)
  "213",          -- unused loop variables
  "432/self",     -- a method's `self` shadowing an outer `self`
}

-- The saved variables (MountTrail.toc ## SavedVariables): Core/Init.lua
-- migrates the old name's table into the new one.
globals = {
  "MountTrailDB",
  "AzerothTrailDB",
}

-- WoW API the addon reads (outside Libs/ and tests/). Mostly reached through
-- Game/API.lua, Integrations/ and the UI files; keep the list in step when a
-- new global is used.
read_globals = {
  -- Lua extensions the game adds
  "bit", "time", "tinsert", "geterrorhandler", "hooksecurefunc", "issecretvalue",

  -- Libraries and other add-ons
  "LibStub", "TomTom", "Rarity", "AllTheThings",

  -- C_ namespaces
  "C_AddOns", "C_AreaPoiInfo", "C_Calendar", "C_ContributionCollector",
  "C_DateAndTime", "C_EncounterJournal", "C_Item", "C_Map", "C_MountJournal",
  "C_QuestLog", "C_Spell", "C_SuperTrack", "C_Texture", "C_Timer", "C_XMLUtil",

  -- Frames, widgets and UI utilities
  "CreateFrame", "CreateFont", "CreateDataProvider", "CreateScrollBoxListLinearView",
  "CreateVector2D", "ScrollUtil", "ScrollBoxConstants", "MenuResponse",
  "MinimalSliderWithSteppersMixin", "Settings", "EventRegistry", "PlayerUtil",
  "UIParent", "UISpecialFrames", "UIErrorsFrame", "GameTooltip", "GameTooltip_Hide",
  "WorldMapFrame", "QuestMapFrame", "QuestMapFrame_ShowQuestDetails",
  "ColorPickerFrame", "AchievementFrame", "AchievementFrame_SelectAchievement",
  "AchievementFrame_ToggleAchievementFrame", "OpenAchievementFrameToAchievement",
  "ShowAchievementFrameForAchievement", "ShowUIPanel", "OpenWorldMap",
  "StaticPopupDialogs", "StaticPopup_Show", "SetPortraitToTexture",
  "DressUpMount", "DressUpMountLink", "PlaySound", "SOUNDKIT",
  "GameFontNormal", "GameFontHighlightSmall", "UiMapPoint", "Item", "Enum",

  -- Game state
  "GetAchievementCriteriaInfo", "GetAchievementInfo", "GetAchievementNumCriteria",
  "GetCategoryList", "GetCategoryNumAchievements", "GetBuildInfo", "GetCVarBool", "SetCVar",
  "GetCursorPosition", "GetExpansionDisplayInfo", "GetLFGDungeonRewards",
  "GetNormalizedRealmName", "GetRealmName", "GetNumSavedInstances",
  "GetSavedInstanceEncounterInfo", "GetSavedInstanceInfo", "GetServerTime",
  "GetSpellLink", "GetStatistic", "GetTime", "GetPlayerFacing", "EJ_GetInstanceInfo",
  "InCombatLockdown", "IsAltKeyDown", "IsControlKeyDown", "IsShiftKeyDown",
  "IsLoggedIn", "LoadAddOn", "RequestLFDPlayerLockInfo", "RequestRaidInfo",
  "SecondsToTime", "UnitClass", "UnitFactionGroup", "UnitLevel", "UnitName",

  -- Game constants and global strings
  "RAID_CLASS_COLORS", "ZONE_COLON", "OKAY", "BATTLE_PET_SOURCE_6",
  "CAMERA_MODIFICATION_TYPE_DISCARD", "CAMERA_TRANSITION_TYPE_IMMEDIATE",
  "EVALUATION_TREE_FLAG_PROGRESS_BAR",
}

-- Specs run under tools/run_tests.py with tests/harness.lua and
-- tests/wow_stub.lua loaded first: they define the harness functions and
-- replace WoW globals with stubs, at the top level and inside specs.
files["tests/"] = {
  allow_defined_top = true,
  allow_defined = true,
  globals = {
    -- harness.lua
    "describe", "it", "eq", "ok", "load_addon", "COMPANIONS",
    "__harness_summary", "__syntax_check", "ROOT",
    -- wow_stub.lua
    "toc_lua_files", "fire_event", "fire_frame_event", "run_slash", "reset_ui_stub",
    "STUB_ATLASES", "STUB_CURSOR", "STUB_TEMPLATES", "STUB_TEMPLATE_METHODS",
    "Region", "RegionMT", "Frame", "FrameMT",
    "PanelTemplates_SetNumTabs", "PanelTemplates_SetTab", "PanelTemplates_TabResize",
    "tremove", "strlower", "strupper", "strfind", "strsub", "strlen", "strrep",
    "gsub", "date",
  },
  ignore = {
    "121", "122",  -- the stubs replace read-only WoW globals and their fields
    "143",         -- specs read fields the stubs add to standard tables
  },
}
