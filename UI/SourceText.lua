local ADDON, ns = ...

-- Reading a mount's Mount Journal source text (Game.MountSourceText): the
-- one sanitiser for it (UI.StripMarkup), its label / value
-- pairs (UI.SourcePairs), its Zone: lines (UI.SourceZone, UI.SourceZones),
-- the achievement it names, and a list row's grey line (UI.RowDescription).
-- Split out of UI/List.lua (loads after it); the sub-groups and rows
-- (UI/ListRows.lua) read these.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

-- Plain text of a Mount Journal source string (Game.MountSourceText), the
-- one sanitiser for every reader of it: hyperlinks (|H...|h text |h keep
-- their text), named (|cnNAME:) and hex (|cAARRGGBB) colour codes, |r,
-- textures (|T...|t) and atlases (|A...|a) are removed; |n and CRLF become
-- "\n". nil for non-strings.
function UI.StripMarkup(text)
  if type(text) ~= "string" then return nil end
  text = string.gsub(text, "|H.-|h(.-)|h", "%1")
  text = string.gsub(text, "|cn[^:|]*:", "")
  text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
  text = string.gsub(text, "|r", "")
  text = string.gsub(text, "|T.-|t", "")
  text = string.gsub(text, "|A.-|a", "")
  text = string.gsub(text, "|n", "\n")
  text = string.gsub(text, "\r\n?", "\n")
  return text
end

-- Icon markup for display: a texture (|Tpath-or-fileID:h:w...|t) or atlas
-- (|Aname:h:w...|a) with its size fields rewritten to 0, which WoW scales to
-- the font height, so the icon lines up with the text around it.
local function normalizeTexture(body)
  local file = string.match(body, "^([^:]*)")
  if file == "" then return "" end
  return "|T" .. file .. ":0|t"
end

local function normalizeAtlas(body)
  local name = string.match(body, "^:?([^:]*)")
  if name == "" then return "" end
  return "|A" .. name .. ":0:0|a"
end

-- Placeholders ("\1" + a byte >= 128) stand in for icons while the text is
-- split into labels and values (UI.SourcePairs, keepIcons), so a fileID's
-- digits or an icon next to a label never confuse the label detection.
local PLACEHOLDER = "\1[\128-\255]"
local MAX_ICONS = 120

local function hideIcons(text)
  local icons = {}
  local function hide(markup)
    if markup == "" or #icons >= MAX_ICONS then return "" end
    icons[#icons + 1] = markup
    return "\1" .. string.char(127 + #icons)
  end
  text = string.gsub(text, "|T(.-)|t", function(body) return hide(normalizeTexture(body)) end)
  text = string.gsub(text, "|A(.-)|a", function(body) return hide(normalizeAtlas(body)) end)
  return text, icons
end

local function showIcons(text, icons)
  return (string.gsub(text, PLACEHOLDER, function(mark) return icons[string.byte(mark, 2) - 127] or "" end))
end

local function dropIcons(text)
  return (string.gsub(text, PLACEHOLDER, ""))
end

local FULLWIDTH_COLON = "\239\188\154" -- U+FF1A, zhCN / zhTW labels
local MAX_LABEL = 40 -- bytes; longer "labels" are sentences with a colon

local function trim(s)
  return string.match(s, "^%s*(.-)%s*$")
end

-- Comparable form of a label: lower case, without the colon and spaces.
local function labelKey(label)
  if type(label) ~= "string" then return nil end
  label = dropIcons(label)
  label = string.gsub(label, FULLWIDTH_COLON, "")
  label = string.gsub(label, ":", "")
  label = trim(label)
  if label == "" then return nil end
  return string.lower(label)
end

-- Label kinds of the source text: English words plus the client's own
-- (GlobalStrings: BATTLE_PET_SOURCE_n are the Mount Journal's source names,
-- ZONE_COLON / LOCATION_COLON / COSTS_LABEL / CATEGORY) for other locales.
-- Read on each call, so a client without them still works. cost and
-- category only serve to split lines (UI.SourcePairs).
local KIND_WORDS = {
  { kind = "drop", words = { "Drop" }, globals = { "BATTLE_PET_SOURCE_1" } },
  { kind = "quest", words = { "Quest" }, globals = { "BATTLE_PET_SOURCE_2" } },
  { kind = "vendor", words = { "Vendor" }, globals = { "BATTLE_PET_SOURCE_3" } },
  { kind = "achievement", words = { "Achievement" }, globals = { "BATTLE_PET_SOURCE_6" } },
  { kind = "zone", words = { "Zone", "Location" }, globals = { "ZONE_COLON", "LOCATION_COLON" } },
  { kind = "cost", words = { "Cost" }, globals = { "COSTS_LABEL" } },
  { kind = "category", words = { "Category" }, globals = { "CATEGORY" } },
}

local function labelKinds()
  local kinds = {}
  local function add(word, kind)
    local key = labelKey(word)
    if key and not kinds[key] then kinds[key] = kind end
  end
  for _, entry in ipairs(KIND_WORDS) do
    for _, word in ipairs(entry.words) do add(word, entry.kind) end
    for _, name in ipairs(entry.globals) do add(_G[name], entry.kind) end
  end
  return kinds
end

-- Kind of a source label: "drop" | "quest" | "vendor" | "achievement" |
-- "zone" (Zone / Location) | "cost" | "category" | nil.
function UI.SourceLabelKind(label, kinds)
  local key = labelKey(label)
  return key and (kinds or labelKinds())[key] or nil
end

-- Label key -> kind for UI.SourceLabelKind's second argument, built once per
-- caller (UI.SearchFields) instead of once per label.
function UI.SourceLabelKinds()
  return labelKinds()
end

-- "<label>: <value>" -> label (with its colon), value; nil when the line has
-- no short, digit-free label before its first colon.
local function splitLabel(line)
  local label, value = string.match(line, "^([^:]-:)%s*(.*)$")
  local wide, wideValue = string.match(line, "^(.-" .. FULLWIDTH_COLON .. ")%s*(.*)$")
  if wide and (not label or #wide < #label) then label, value = wide, wideValue end
  if not label or #label > MAX_LABEL or string.find(label, "%d") then return nil end
  if not string.find(label, "[^%s:]") then return nil end
  return label, value
end

-- A value that runs into another known label ("Ultraxion Zone: Dragon
-- Soul") -> head, label, tail; nil when no known label (labelKinds) follows a
-- space. Unknown words never split ("Ahead of the Curve: Ultraxion").
local function splitKnown(value, kinds)
  local from = 1
  while true do
    local space = string.find(value, "%s", from)
    if not space then return nil end
    local rest = string.sub(value, space + 1)
    local label = string.match(rest, "^([^:%s][^:]-:)")
    if label and #label <= MAX_LABEL and kinds[labelKey(label)] then
      local head = trim(string.sub(value, 1, space - 1))
      if head ~= "" then return head, label, trim(string.sub(rest, #label + 1)) end
    end
    from = space + 1
  end
end

-- Coloured labels ("|cFFFFD200Zone:|r", "|cnNORMAL_FONT_COLOR:Zone:|r") start
-- a line of their own, even when the client put several on one line.
local function breakColouredLabels(text)
  for _, colon in ipairs({ ":", FULLWIDTH_COLON }) do
    text = string.gsub(text, "(|c%x%x%x%x%x%x%x%x[^|\n]-" .. colon .. "%s*|r)", "|n%1")
    text = string.gsub(text, "(|cn[^:|]*:[^|\n]-" .. colon .. "%s*|r)", "|n%1")
  end
  return text
end

-- The source string's lines (UI.StripMarkup) -> { { label = "Drop:", value =
-- "Ultraxion" }, { value = "<unlabelled line>" }, ... } in order. Labels are
-- the client's own (localised) text with the colon; lines and values are
-- trimmed; empty lines and labels with an empty value are left out. Several
-- labels on one line become several pairs: coloured labels always, plain
-- ones when the label is a known word (UI.SourceLabelKind). With keepIcons
-- the values keep their (normalised) icons; labels never do.
function UI.SourcePairs(text, keepIcons)
  local out = {}
  if type(text) ~= "string" then return out end
  local icons
  if keepIcons then text, icons = hideIcons(text) end
  text = UI.StripMarkup(breakColouredLabels(text))
  local kinds = labelKinds()
  for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
    line = trim(line)
    if line ~= "" then
      local label, value = splitLabel(line)
      if label then
        value = trim(value)
        while label do
          local head, nextLabel, tail = splitKnown(value, kinds)
          if head then value = head end
          if value ~= "" then
            out[#out + 1] = { label = trim(dropIcons(label)), value = icons and showIcons(value, icons) or value }
          end
          label, value = nextLabel, tail
        end
      else
        out[#out + 1] = { value = icons and showIcons(line, icons) or line }
      end
    end
  end
  return out
end

-- True for the label of the zone line: "Zone:", or ZONE_COLON (a
-- GlobalStrings entry) for other locales when the client has it. "Location:"
-- is not a sub-group source (UI.SourceLabelKind counts it as a zone).
local function isZoneLabel(label)
  local key = labelKey(label)
  return key ~= nil and (key == "zone" or key == labelKey(ZONE_COLON))
end

-- The value of the first "Zone:" line of a Mount Journal source string
-- (Game.MountSourceText; UI.SourcePairs), nil when there is none.
function UI.SourceZone(text)
  for _, pair in ipairs(UI.SourcePairs(text)) do
    if pair.label and isZoneLabel(pair.label) then return pair.value end
  end
  return nil
end

-- Every "Zone:" / "Location:" value of a Mount Journal source string, in
-- order (a drop's zone, a vendor's, ...); {} when there is none.
function UI.SourceZones(text)
  local out = {}
  local kinds = labelKinds()
  for _, pair in ipairs(UI.SourcePairs(text)) do
    if pair.label and UI.SourceLabelKind(pair.label, kinds) == "zone" then out[#out + 1] = pair.value end
  end
  return out
end

-- Name of the achievement the achievement scan mapped the mount to, or nil
-- (not an achievement mount, not known yet, or no match).
local function scannedAchievementName(mountID)
  local scan = ns.AchievementScan
  local id = scan and scan.Lookup and scan.Lookup(mountID) or nil
  if not id then return nil end
  local name = ns.Game.AchievementName and ns.Game.AchievementName(id) or nil
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

-- The same, for UI.SearchFields (UI/Search.lua).
function UI.ScannedAchievementName(mountID)
  return scannedAchievementName(mountID)
end

-- The grey line under a mount row's name: the most specific source the
-- client's source text (Game.MountSourceText, passed in) or our data gives,
-- one line:
--   "Drop: Ultraxion · Dragon Soul" (Drop, plus Zone / Location),
--   "Achievement: <name>" (source text, else the achievement scan's name),
--   "Vendor: <name> · <zone>", "Quest: <name>",
--   another labelled line, not Cost / Category ("Treasure: <name> · <zone>"),
--   the route's "<boss> (<instance>)",
--   a lone "Zone: <name>", an unlabelled line,
--   else UI.SourceLine (the category text; "" when there is none).
-- Labels are the client's own.
function UI.RowDescription(mountID, sourceText)
  local kinds = labelKinds()
  local first, zone, unlabelled, other = {}, nil, nil, nil
  for _, pair in ipairs(UI.SourcePairs(sourceText, true)) do
    if pair.label then
      local kind = UI.SourceLabelKind(pair.label, kinds)
      if kind == "zone" then
        zone = zone or pair
      elseif kind then
        first[kind] = first[kind] or pair
      else
        other = other or pair
      end
    else
      unlabelled = unlabelled or pair.value
    end
  end
  local function text(pair, withZone)
    local out = pair.label .. " " .. pair.value
    if withZone and zone then out = out .. " · " .. zone.value end
    return out
  end

  if first.drop then return text(first.drop, true) end
  if first.achievement then return text(first.achievement) end
  local achievement = scannedAchievementName(mountID)
  if achievement then return string.format(L["Achievement: %s"], achievement) end
  if first.vendor then return text(first.vendor, true) end
  if first.quest then return text(first.quest) end
  if other then return text(other, true) end
  local entry = UI.RouteEntry(mountID)
  if entry and entry.boss then
    if entry.instance then return entry.boss .. " (" .. entry.instance .. ")" end
    return entry.boss
  end
  if zone then return text(zone) end
  if unlabelled then return unlabelled end
  return UI.SourceLine(mountID)
end
