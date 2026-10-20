local ADDON, ns = ...

-- Mount guides: step-by-step directions written as plain text, one keyword
-- per line, so anyone can write, read, paste and share them. Built-in guides
-- ship as files in Guides\; the player's own are saved text
-- (UI/Guides.lua). This file reads the text and decides when a step is
-- done. Pure Lua.
--
--   #guide Thundering Ruby Cloud Serpent     the title (required, first)
--   #mount 517                              the mount(s) it is for
--   #author Adventurer                            who wrote it (one line each)
--   #credit Thanks to Wowhead's commenters  anyone else to thank (optional)
--   #description One line about it          optional
--   -- a comment                            ignored
--   step Fly to the Vale of Eternal Blossoms
--     note Any flying mount works            a grey line under the step
--     goto 390 35.6 26 Alani (north)         map ID, x, y (0-100), a label
--     quest 31234                            done when the quest is turned in
--     item 86547 10                          done with 10 of the item in bags
--     mount 517                              done when the mount is known
--     reach 20                               done within 20 yards of the first goto
--     macro /tar Alani                       a macro to copy (more lines: more macro lines)
--
-- A step with no done line moves on with Next only. Indenting is optional:
-- every line after `step` belongs to it until the next `step`.
local Guide = {}
ns.Guide = Guide

local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })

Guide.HEADER = "#guide"
Guide.REACH_YARDS = 15 -- `reach` without a distance
Guide.MAX_STEPS = 500
Guide.MAX_TEXT = 60000
Guide.MACRO_MAX = 255 -- the game's limit on a macro's text

local function trim(s)
  return (string.match(s, "^%s*(.-)%s*$"))
end

-- A positive whole number, or nil.
local function id(word)
  local n = tonumber(word)
  if n and n > 0 and n == math.floor(n) then return n end
  return nil
end

-- "goto <map> <x> <y> [label]" (commas count as spaces) -> point or nil, why.
local function parseGoto(rest)
  local words = {}
  for w in string.gmatch((string.gsub(rest, ",", " ")), "%S+") do words[#words + 1] = w end
  local m, x, y = id(words[1]), tonumber(words[2]), tonumber(words[3])
  if not (m and x and y) then return nil, "goto needs a map ID, then x and y" end
  if x < 0 or x > 100 or y < 0 or y > 100 then return nil, "goto's x and y go from 0 to 100" end
  local label = table.concat(words, " ", 4)
  return { m = m, x = x, y = y, label = label ~= "" and label or nil }
end

-- Guide text -> guide, errors. guide = { title =, mounts = { id }, author =,
-- description =, steps = { { text =, notes = {}, gotos = { { m, x, y,
-- label } }, done = { { kind = "quest"|"item"|"mount"|"reach", id =, count =,
-- yards = } }, line = } } } or nil when there is no title or no step.
-- errors = { { line =, msg = } } (empty when all is well); a bad line is
-- skipped, the rest still reads.
function Guide.Parse(text)
  local errors = {}
  local function fail(line, msg) errors[#errors + 1] = { line = line, msg = msg } end
  if type(text) ~= "string" or text == "" then
    fail(1, "The guide is empty.")
    return nil, errors
  end
  if #text > Guide.MAX_TEXT then
    fail(1, "The guide is too long.")
    return nil, errors
  end
  local guide = { mounts = {}, steps = {}, authors = {}, credits = {} }
  local step
  local n = 0
  for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
    n = n + 1
    local line = trim((string.gsub(raw, "\r", "")))
    if line ~= "" and string.sub(line, 1, 2) ~= "--" then
      local word, rest = string.match(line, "^(%S+)%s*(.*)$")
      word = string.lower(word)
      if word == "#guide" then
        if rest == "" then fail(n, "#guide needs a title") else guide.title = rest end
      elseif word == "#mount" then
        local mountID = id(rest)
        if mountID then guide.mounts[#guide.mounts + 1] = mountID else fail(n, "#mount needs a mount ID") end
      elseif word == "#author" then
        if rest ~= "" then
          guide.authors[#guide.authors + 1] = rest
          guide.author = guide.author or rest
        end
      elseif word == "#credit" then
        if rest ~= "" then guide.credits[#guide.credits + 1] = rest end
      elseif word == "#description" then
        guide.description = rest ~= "" and rest or nil
      elseif word == "step" then
        if rest == "" then fail(n, "step needs its directions") end
        if #guide.steps >= Guide.MAX_STEPS then
          fail(n, "Too many steps.")
          break
        end
        step = { text = rest, notes = {}, gotos = {}, done = {}, line = n }
        guide.steps[#guide.steps + 1] = step
      elseif not step then
        fail(n, "Start a step with: step <directions>")
      elseif word == "macro" then
        local body = step.macro and (step.macro .. "\n" .. rest) or rest
        if rest == "" then
          fail(n, "macro needs the macro's text, e.g. macro /tar Alani")
        elseif #body > Guide.MACRO_MAX then
          fail(n, "The macro is longer than the game's 255 characters.")
        else
          step.macro = body
        end
      elseif word == "note" then
        if rest ~= "" then step.notes[#step.notes + 1] = rest end
      elseif word == "goto" then
        local point, why = parseGoto(rest)
        if point then step.gotos[#step.gotos + 1] = point else fail(n, why) end
      elseif word == "quest" then
        local questID = id(rest)
        if questID then step.done[#step.done + 1] = { kind = "quest", id = questID } else fail(n, "quest needs a quest ID") end
      elseif word == "item" then
        local a, b = string.match(rest, "^(%S+)%s*(%S*)")
        local itemID = id(a)
        local count = (b == "") and 1 or id(b)
        if itemID and count then
          step.done[#step.done + 1] = { kind = "item", id = itemID, count = count }
        else
          fail(n, "item needs an item ID, then how many (optional)")
        end
      elseif word == "mount" then
        local mountID = id(rest)
        if mountID then step.done[#step.done + 1] = { kind = "mount", id = mountID } else fail(n, "mount needs a mount ID") end
      elseif word == "reach" then
        local yards = rest == "" and Guide.REACH_YARDS or tonumber(rest)
        if yards and yards > 0 then step.done[#step.done + 1] = { kind = "reach", yards = yards } else fail(n, "reach takes a distance in yards") end
      else
        fail(n, "Unknown line: " .. word)
      end
    end
  end
  if not guide.title then fail(1, "The first line must be: #guide <title>") end
  if #guide.steps == 0 then fail(n, "A guide needs at least one step.") end
  if not guide.title or #guide.steps == 0 then return nil, errors end
  for _, s in ipairs(guide.steps) do
    for _, d in ipairs(s.done) do
      if d.kind == "reach" and #s.gotos == 0 then fail(s.line, "reach needs a goto in the same step") end
    end
  end
  return guide, errors
end

-- A guide's ID from its title: lower case, words joined by "-".
function Guide.Id(title)
  local s = string.lower(tostring(title or ""))
  s = string.gsub(s, "[^%w]+", "-")
  s = string.gsub(s, "^%-+", "")
  s = string.gsub(s, "%-+$", "")
  return s ~= "" and s or "guide"
end

-- Whether every done line of `step` holds (false for a step without any:
-- Next moves on). ctx: isQuestDone(id), itemCount(id) -> n, isOwned(id),
-- near(point, yards) -> bool (nil when the position is unknown).
function Guide.StepDone(step, ctx)
  if not (step and #step.done > 0) then return false end
  for _, d in ipairs(step.done) do
    local ok
    if d.kind == "quest" then
      ok = ctx.isQuestDone and ctx.isQuestDone(d.id)
    elseif d.kind == "item" then
      ok = ctx.itemCount and (ctx.itemCount(d.id) or 0) >= d.count
    elseif d.kind == "mount" then
      ok = ctx.isOwned and ctx.isOwned(d.id)
    elseif d.kind == "reach" then
      ok = step.gotos[1] ~= nil and ctx.near and ctx.near(step.gotos[1], d.yards)
    end
    if not ok then return false end
  end
  return true
end

-- A step number kept inside the guide: 1 .. #steps.
function Guide.Clamp(guide, n)
  local last = guide and #guide.steps or 1
  n = tonumber(n) or 1
  return math.max(1, math.min(last, math.floor(n)))
end

-- What a step's done lines ask for, as short phrases with link tokens
-- (Guide.Markup turns those into the game's links): "turn in [quest:9]".
function Guide.DoneText(step)
  local out = {}
  for _, d in ipairs(step and step.done or {}) do
    if d.kind == "quest" then
      out[#out + 1] = string.format(L["turn in %s"], "[quest:" .. d.id .. "]")
    elseif d.kind == "item" then
      local item = "[item:" .. d.id .. "]"
      out[#out + 1] = d.count > 1 and string.format(L["%d x %s"], d.count, item) or string.format(L["get %s"], item)
    elseif d.kind == "mount" then
      out[#out + 1] = string.format(L["learn %s"], "[mount:" .. d.id .. "]")
    elseif d.kind == "reach" then
      out[#out + 1] = L["reach the spot"]
    end
  end
  return out
end

-- Markup inside step, note and description text:
--   **words**          highlighted (gold): WoW text can't turn bold mid-line
--   [item:86547]       the item's link: its name, the game's tooltip on hover
--   [quest:31234]      the same for a quest, [mount:517] a mount,
--   [spell:12345], [achievement:6] a spell or an achievement
-- Guide text -> display text. linkFor(kind, id) -> the link, or nil to
-- show the token as plain "[kind id]".
Guide.HIGHLIGHT = "|cffffd100"
Guide.LINK_KINDS = { item = true, quest = true, mount = true, spell = true, achievement = true }

function Guide.Markup(text, linkFor)
  if type(text) ~= "string" then return "" end
  text = string.gsub(text, "%[(%a+):(%d+)%]", function(kind, id)
    kind = string.lower(kind)
    if not Guide.LINK_KINDS[kind] then return nil end
    local link = linkFor and linkFor(kind, tonumber(id))
    return link or ("[" .. kind .. " " .. id .. "]")
  end)
  text = string.gsub(text, "%*%*(.-)%*%*", function(inner) return Guide.HIGHLIGHT .. inner .. "|r" end)
  return text
end

-- "by A, B" for a guide's authors, or nil without any.
function Guide.Byline(guide)
  if not (guide and guide.authors and #guide.authors > 0) then return nil end
  return string.format(L["by %s"], table.concat(guide.authors, ", "))
end

-- A starting point for a new guide.
Guide.TEMPLATE = table.concat({
  "#guide My mount guide",
  "-- #mount 517   (the mount's ID, e.g. from its Wowhead page)",
  "#author You",
  "-- #credit Thanks to anyone who helped",
  "-- Lines starting with -- are comments.",
  "step Fly to the zone",
  "  goto 390 35.6 26 First spot",
  "  reach",
  "step Do the thing that drops it",
  "  note Anything helpful goes on a note line",
  "  -- mount 517   (moves on once you have the mount)",
}, "\n")
