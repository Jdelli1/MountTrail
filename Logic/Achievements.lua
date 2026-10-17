local ADDON, ns = ...

-- Pure helpers for achievement mounts (no WoW API): which mounts count, the
-- "Achievement: <name>" part of a Mount Journal source text, the matcher
-- that maps mounts to the achievements rewarding them, and the tooltip lines
-- for an achievement and its criteria. The client scan that feeds the
-- matcher lives in Integrations/AchievementScan.lua.

local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })

local Achievements = {}
ns.Achievements = Achievements

-- Mounts on the Achievements tab: misc data tab, achievement section.
function Achievements.IsAchievementMount(m)
  return type(m) == "table" and m.tab == "misc" and m.section == "achievement"
end

local function trim(s)
  return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- Text without colour, texture, atlas and hyperlink codes; |n becomes a
-- newline.
function Achievements.StripCodes(text)
  if type(text) ~= "string" then return nil end
  text = string.gsub(text, "|n", "\n")
  text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
  text = string.gsub(text, "|r", "")
  text = string.gsub(text, "|T.-|t", "")
  text = string.gsub(text, "|A.-|a", "")
  text = string.gsub(text, "|H.-|h", "")
  text = string.gsub(text, "|h", "")
  return text
end

-- The achievement named in a Mount Journal source text ("Achievement:
-- <name>" on any line), or nil. labels: extra (localized) labels to accept
-- besides "Achievement".
function Achievements.SourceTitle(source, labels)
  local text = Achievements.StripCodes(source)
  if not text then return nil end
  local all = { "Achievement" }
  for _, label in ipairs(labels or {}) do
    if type(label) == "string" and label ~= "" then all[#all + 1] = label end
  end
  for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
    line = trim(line)
    for _, label in ipairs(all) do
      local prefix = label .. ":"
      if string.sub(line, 1, #prefix) == prefix then
        local name = trim(string.sub(line, #prefix + 1))
        if name ~= "" then return name end
      end
    end
  end
  return nil
end

local function isWordByte(c)
  return c ~= "" and string.find(c, "^%w$") ~= nil
end

-- True when `name` appears in `text` as a whole (plain find, no patterns;
-- the characters either side must not be letters or digits, so "Red Drake"
-- does not match "Red Drakeling").
function Achievements.ContainsName(text, name)
  if type(text) ~= "string" or type(name) ~= "string" or name == "" then return false end
  local init = 1
  while true do
    local s, e = string.find(text, name, init, true)
    if not s then return false end
    local before = s > 1 and string.sub(text, s - 1, s - 1) or ""
    local after = string.sub(text, e + 1, e + 1)
    if not isWordByte(before) and not isWordByte(after) then return true end
    init = s + 1
  end
end

local RANK_ITEM, RANK_NAME, RANK_TITLE, RANK_NONE = 1, 2, 3, 4

local function nonEmpty(list)
  local out = {}
  for _, s in ipairs(list or {}) do
    if type(s) == "string" and s ~= "" then out[#out + 1] = s end
  end
  return out
end

-- Matcher for achievement mounts. mounts: { { id = mountID, items = { item
-- names }, names = { mount names }, title = achievement name from the
-- source text or nil } }. Feed every achievement (id, name, rewardText);
-- Result() -> { [mountID] = achievementID or false }. A mount takes the
-- first achievement whose reward text names its item; else the first whose
-- reward text names the mount; else the first whose title equals the
-- source-text title.
function Achievements.NewMatcher(mounts)
  local entries, byTitle = {}, {}
  for _, mount in ipairs(mounts or {}) do
    local entry = { id = mount.id, items = nonEmpty(mount.items), names = nonEmpty(mount.names),
      rank = RANK_NONE, match = false }
    entries[#entries + 1] = entry
    if type(mount.title) == "string" and mount.title ~= "" then
      byTitle[mount.title] = byTitle[mount.title] or {}
      table.insert(byTitle[mount.title], entry)
    end
  end

  local matcher = {}

  function matcher:Feed(achievementID, name, rewardText)
    if not achievementID then return end
    if type(rewardText) == "string" and rewardText ~= "" then
      for _, entry in ipairs(entries) do
        if entry.rank > RANK_ITEM then
          for _, item in ipairs(entry.items) do
            if Achievements.ContainsName(rewardText, item) then
              entry.rank, entry.match = RANK_ITEM, achievementID
              break
            end
          end
        end
        if entry.rank > RANK_NAME then
          for _, mountName in ipairs(entry.names) do
            if Achievements.ContainsName(rewardText, mountName) then
              entry.rank, entry.match = RANK_NAME, achievementID
              break
            end
          end
        end
      end
    end
    local titled = type(name) == "string" and byTitle[name]
    if titled then
      for _, entry in ipairs(titled) do
        if entry.rank > RANK_TITLE then entry.rank, entry.match = RANK_TITLE, achievementID end
      end
    end
  end

  function matcher:Result()
    local out = {}
    for _, entry in ipairs(entries) do
      if entry.id ~= nil then out[entry.id] = entry.match end
    end
    return out
  end

  return matcher
end

-- Tooltip colours (r, g, b).
local GOLD = { 1, 0.82, 0 }
local GREEN = { 0.25, 1, 0.25 }
local GREY = { 0.6, 0.6, 0.6 }
local WHITE = { 1, 1, 1 }

local function line(text, color, wrap)
  return { text = text, r = color[1], g = color[2], b = color[3], wrap = wrap or nil }
end

local function count(n)
  n = tonumber(n)
  if not n then return 0 end
  return math.floor(n)
end

-- Tooltip lines for an achievement. info: { name=, description=,
-- completed=, numCriteria=, criteria = { { text=, completed=, quantity=,
-- required= } } } (Game.AchievementInfo). -> { { text=, r=, g=, b=, wrap= } }:
-- "Achievement: <name>" (gold; green with "(completed)" when earned), the
-- description (white, wrapped), then up to `max` (default 8) criteria,
-- completed green and others grey, with "(quantity/required)" on
-- unfinished counted ones, and "+N more" for the rest. A criterion without
-- text shows as "Progress (q/r)" when counted, else is left out.
function Achievements.TooltipLines(info, max)
  if type(info) ~= "table" or type(info.name) ~= "string" or info.name == "" then return {} end
  max = max or 8
  local lines = {}
  local title = string.format(L["Achievement: %s"], info.name)
  if info.completed then
    lines[1] = line(title .. " " .. L["(completed)"], GREEN)
  else
    lines[1] = line(title, GOLD)
  end
  if type(info.description) == "string" and info.description ~= "" then
    lines[#lines + 1] = line(info.description, WHITE, true)
  end

  local shown = {}
  local criteria = info.criteria or {}
  for i = 1, #criteria do
    local c = criteria[i]
    local text = type(c.text) == "string" and c.text or ""
    local required = count(c.required)
    local progress = (not c.completed and required > 1)
      and string.format(" (%d/%d)", count(c.quantity), required) or ""
    if text == "" then
      if required > 1 then shown[#shown + 1] = { text = L["Progress"] .. string.format(" (%d/%d)",
        count(c.quantity), required), completed = c.completed } end
    else
      shown[#shown + 1] = { text = text .. progress, completed = c.completed }
    end
  end

  local n = math.min(max, #shown)
  for i = 1, n do
    lines[#lines + 1] = line("  " .. shown[i].text, shown[i].completed and GREEN or GREY)
  end
  local more = (#shown - n) + math.max(0, count(info.numCriteria) - #criteria)
  if more > 0 then
    lines[#lines + 1] = line(string.format(L["+%d more"], more), GREY)
  end
  return lines
end
