local ADDON, ns = ...

-- Running mount guides (Logic/Guide.lua has the format): the library (the
-- built-in guides from Guides\ plus the player's own, saved as text), which
-- step each guide is on per character, and moving through it. Each step's
-- goto points go on TomTom (Map.PlotPoints); Back or Close takes them off.
-- A step whose done lines all hold moves on by itself (quest turned in,
-- items in bags, mount learned, spot reached), except right after Back, so
-- the player can stay on a step they went back to. The window lives in
-- UI/GuideWindow.lua, the editor in UI/GuideEditor.lua.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local REACH_TICK = 1 -- seconds between distance checks while a step has `reach`
local BUILTIN = "builtin:"

local parsed = {} -- guide text -> parsed guide (false: does not parse)
local held = false -- Back was pressed: no auto-advance until the step changes
local ticker

local function say(msg)
  if ns.addon and ns.addon.Print then ns.addon:Print(msg) end
end

local function parse(text)
  local hit = parsed[text]
  if hit == nil then
    hit = ns.Guide.Parse(text) or false
    parsed[text] = hit
  end
  return hit or nil
end

-- The player's own guides: ns.db.global.guides = { [id] = text }.
local function userGuides()
  local global = ns.db and ns.db.global
  if not global then return nil end
  if type(global.guides) ~= "table" then global.guides = {} end
  return global.guides
end

-- This character's guide state: ns.db.char.guides = { active =, steps = { [id] = n } }.
local function charState()
  local char = ns.db and ns.db.char
  if not char then return nil end
  if type(char.guides) ~= "table" then char.guides = {} end
  if type(char.guides.steps) ~= "table" then char.guides.steps = {} end
  return char.guides
end

-- Every guide -> { { id =, title =, text =, guide =, builtIn = } } by title.
function UI.GuideList()
  local out = {}
  for _, text in ipairs(ns.GuideTexts or {}) do
    local g = parse(text)
    if g then out[#out + 1] = { id = BUILTIN .. ns.Guide.Id(g.title), title = g.title, text = text, guide = g, builtIn = true } end
  end
  for id, text in pairs(userGuides() or {}) do
    local g = type(text) == "string" and parse(text)
    if g then out[#out + 1] = { id = id, title = g.title, text = text, guide = g } end
  end
  table.sort(out, function(a, b)
    local ta, tb = string.lower(a.title), string.lower(b.title)
    if ta ~= tb then return ta < tb end
    return a.id < b.id
  end)
  return out
end

function UI.GuideById(id)
  for _, e in ipairs(UI.GuideList()) do
    if e.id == id then return e end
  end
  return nil
end

-- Saves guide text as the player's guide `id` (nil: a new one, its ID from
-- the title) -> id, or nil and the parse errors.
function UI.SaveGuide(text, id)
  local g, errors = ns.Guide.Parse(text)
  if not g then return nil, errors end
  local store = userGuides()
  if not store then return nil, errors end
  if not id or string.sub(id, 1, #BUILTIN) == BUILTIN then
    local base = ns.Guide.Id(g.title)
    id = base
    local n = 2
    while store[id] do
      id = base .. "-" .. n
      n = n + 1
    end
  end
  store[id] = text
  ns.Refresh()
  return id, errors
end

function UI.DeleteGuide(id)
  local store = userGuides()
  if not (store and store[id]) then return false end
  store[id] = nil
  local state = charState()
  if state then
    state.steps[id] = nil
    if state.active == id then UI.StopGuide() end
  end
  ns.Refresh()
  return true
end

-- The step guide `id` is on for this character (1 when never started).
function UI.GuideStepOf(id)
  local state = charState()
  return state and tonumber(state.steps[id]) or 1
end

-- The guide being followed -> entry, step number; nil when none.
function UI.ActiveGuide()
  local state = charState()
  local entry = state and state.active and UI.GuideById(state.active)
  if not entry then return nil end
  return entry, ns.Guide.Clamp(entry.guide, state.steps[entry.id])
end

-- Puts the step's goto points on TomTom (and takes the last ones off).
local function plot(entry, n)
  local map = ns.Map
  if not map then return end
  local step = entry.guide.steps[n]
  local points = {}
  for _, p in ipairs(step and step.gotos or {}) do
    points[#points + 1] = { p.m, p.x, p.y, p.label or entry.title }
  end
  if #points == 0 then
    if map.ClearPlot then map.ClearPlot() end
  elseif map.PlotPoints then
    map.PlotPoints(points)
  end
end

local function stepHasReach(step)
  for _, d in ipairs(step and step.done or {}) do
    if d.kind == "reach" then return true end
  end
  return false
end

local function updateTicker()
  local entry, n = UI.ActiveGuide()
  local want = entry ~= nil and not held and stepHasReach(entry.guide.steps[n])
  if want and not ticker and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
    ticker = C_Timer.NewTicker(REACH_TICK, function() UI.CheckGuideStep() end)
  elseif not want and ticker then
    if ticker.Cancel then ticker:Cancel() end
    ticker = nil
  end
end

local function changed()
  updateTicker()
  if UI.RefreshGuideWindow then UI.RefreshGuideWindow() end
  if UI.RefreshNav then UI.RefreshNav() end
end

-- Moves the active guide to step `n` (kept in range), plots it.
function UI.GuideJump(n, back)
  local entry = UI.ActiveGuide()
  local state = charState()
  if not (entry and state) then return end
  n = ns.Guide.Clamp(entry.guide, n)
  state.steps[entry.id] = n
  held = back == true
  plot(entry, n)
  changed()
  if not held then UI.CheckGuideStep() end
end

-- Next (+1) / Back (-1).
function UI.GuideGo(delta)
  local entry, n = UI.ActiveGuide()
  if not entry then return end
  UI.GuideJump(n + delta, delta < 0)
end

-- Starts (or resumes) guide `id` and shows its window.
function UI.StartGuide(id)
  local state = charState()
  local entry = UI.GuideById(id)
  if not (state and entry) then return false end
  state.active = id
  state.steps[id] = ns.Guide.Clamp(entry.guide, state.steps[id])
  held = false
  plot(entry, state.steps[id])
  if UI.ShowGuideWindow then UI.ShowGuideWindow(true) end
  changed()
  UI.CheckGuideStep()
  return true
end

-- Stops following: the points come off TomTom, the window closes.
function UI.StopGuide()
  local state = charState()
  if state then state.active = nil end
  held = false
  if ns.Map and ns.Map.ClearPlot then ns.Map.ClearPlot() end
  if UI.ShowGuideWindow then UI.ShowGuideWindow(false) end
  changed()
end

-- Finish (the last step's button): closes the guide; the next time it starts
-- from step 1 again.
function UI.FinishGuide()
  local entry = UI.ActiveGuide()
  local state = charState()
  if not (entry and state) then return end
  say(string.format(L["Guide finished: %s"], entry.title))
  state.steps[entry.id] = nil
  UI.StopGuide()
end

-- Back to step 1 (and plots it when it is the active guide).
function UI.ResetGuide(id)
  local state = charState()
  if not state then return end
  state.steps[id] = nil
  if state.active == id then UI.GuideJump(1) else changed() end
end

-- What auto-advance reads.
local function doneContext()
  local Game = ns.Game
  return {
    isQuestDone = Game.IsQuestDone,
    itemCount = Game.ItemCount,
    isOwned = Game.IsOwned,
    near = function(p, yards)
      local d = ns.Map and ns.Map.YardsTo and ns.Map.YardsTo(p.m, p.x, p.y)
      return d ~= nil and d <= yards
    end,
  }
end

-- Moves on while the current step is done (not right after Back); the
-- last step done says the guide is complete.
function UI.CheckGuideStep()
  local entry, n = UI.ActiveGuide()
  if not entry or held then return end
  local ctx = doneContext()
  local steps = entry.guide.steps
  local moved = false
  while n <= #steps and ns.Guide.StepDone(steps[n], ctx) do
    if n == #steps then
      if moved then UI.GuideJump(n) end
      local state = charState()
      if state and state.complete ~= entry.id then
        state.complete = entry.id
        say(string.format(L["Guide complete: %s"], entry.title))
      end
      return
    end
    n = n + 1
    moved = true
  end
  if moved then
    local state = charState()
    if state then state.complete = nil end
    say(string.format(L["Step done: now step %d of %d"], n, #steps))
    UI.GuideJump(n)
  end
end

-- The game's link for a markup token (Guide.Markup): its name in brackets,
-- the game's tooltip on hover. A name the client has not loaded yet shows as
-- "item 86547" and is asked for (the window repaints when it arrives).
function UI.GuideLink(kind, id)
  local Game = ns.Game
  if kind == "item" then
    local link = Game.ItemLink(id)
    if link then return link end
    Game.RequestItem(id)
    return string.format("|cffffffff|Hitem:%d|h[%s %d]|h|r", id, L["item"], id)
  elseif kind == "quest" then
    local name = Game.QuestName(id)
    if not name then Game.RequestQuest(id) end
    return string.format("|cffffff00|Hquest:%d:-1|h[%s]|h|r", id, name or (L["quest"] .. " " .. id))
  elseif kind == "mount" then
    local m = ns.Data and ns.Data.Mounts and ns.Data.Mounts[id]
    local name = Game.MountInfo(id) or (m and m.name) or (L["mount"] .. " " .. id)
    if not (m and m.spell) then return "[" .. name .. "]" end
    return string.format("|cff71d5ff|Hspell:%d:0|h[%s]|h|r", m.spell, name)
  elseif kind == "spell" then
    local name = Game.SpellName(id)
    return string.format("|cff71d5ff|Hspell:%d:0|h[%s]|h|r", id, name or (L["spell"] .. " " .. id))
  elseif kind == "achievement" then
    return Game.AchievementLink(id)
  end
  return nil
end

-- Guide text with its markup applied (Guide.Markup over UI.GuideLink).
function UI.GuideText(text)
  return ns.Guide.Markup(text, UI.GuideLink)
end

-- Guides for a mount (their #mount lines) -> list of entries.
function UI.GuidesForMount(mountID)
  local out = {}
  for _, e in ipairs(UI.GuideList()) do
    for _, m in ipairs(e.guide.mounts) do
      if m == mountID then
        out[#out + 1] = e
        break
      end
    end
  end
  return out
end

-- Events: the game's changes may finish a step; after a loading screen the
-- window comes back for the guide being followed.
local events = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_TURNED_IN", "BAG_UPDATE_DELAYED", "NEW_MOUNT_ADDED", "PLAYER_ENTERING_WORLD" }) do
  events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_ENTERING_WORLD" then
    local entry, n = UI.ActiveGuide()
    if entry then
      plot(entry, n)
      if UI.ShowGuideWindow then UI.ShowGuideWindow(true) end
      changed()
    end
    return
  end
  -- Quest flags can lag the turn-in event by a moment.
  if event == "QUEST_TURNED_IN" and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(1, function() UI.CheckGuideStep() end)
    return
  end
  UI.CheckGuideStep()
end)
