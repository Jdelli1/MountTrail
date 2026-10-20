local ADDON, ns = ...

-- Wrong-difficulty warning: on entering an instance (or changing its
-- difficulty), the mounts in the open pop-outs that drop in this instance
-- but not on this difficulty (Lockouts.WrongDifficulty) get a warning on
-- screen and in chat: "Wrong difficulty for Invincible: you are on 10 Player,
-- it drops on 25 Player (Heroic)". Once per instance and difficulty; owned
-- mounts are left out. Options: "Warn about the wrong difficulty" (on).

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local lastWarned -- "instance:difficulty" already warned about

local function say(msg)
  if ns.addon and ns.addon.Print then ns.addon:Print(msg) end
end

-- Whether the warning is on (ns.db.global.settings.difficultyWarnOff unset).
function UI.DifficultyWarningOn()
  local global = ns.db and ns.db.global
  local saved = global and type(global.settings) == "table" and global.settings or {}
  return saved.difficultyWarnOff ~= true
end

-- The mounts in the open pop-outs, not owned.
function UI.OpenPopoutMounts()
  local ids, seen = {}, {}
  for _, w in pairs(UI.PopoutWindows or {}) do
    if w:IsShown() then
      for _, row in ipairs(w.rows or {}) do
        if row.id and not seen[row.id] and not ns.Game.IsOwned(row.id) then
          seen[row.id] = true
          ids[#ids + 1] = row.id
        end
      end
    end
  end
  return ids
end

local function names(ids)
  local out = {}
  for _, d in ipairs(ids) do out[#out + 1] = ns.Game.DifficultyName(d) or tostring(d) end
  return table.concat(out, L[" or "])
end

local function mountName(id)
  local m = ns.Data and ns.Data.Mounts and ns.Data.Mounts[id]
  return ns.Game.MountInfo(id) or (m and m.name) or tostring(id)
end

-- Checks where the player is -> the warnings shown (empty when none).
-- force: warn again even for the instance and difficulty already warned about.
function UI.CheckDifficulty(force)
  if not UI.DifficultyWarningOn() then return {} end
  local instanceID, difficultyID = ns.Game.CurrentInstance()
  if not instanceID then
    lastWarned = nil
    return {}
  end
  local key = instanceID .. ":" .. difficultyID
  if key == lastWarned and not force then return {} end
  local wrong = ns.Lockouts.WrongDifficulty(UI.OpenPopoutMounts(), instanceID, difficultyID, function(id)
    return ns.Lockouts.SpecFor(id)
  end)
  if #wrong == 0 then return {} end
  lastWarned = key
  local here = ns.Game.DifficultyName(difficultyID) or tostring(difficultyID)
  local lines = {}
  for _, w in ipairs(wrong) do
    lines[#lines + 1] = string.format(L["Wrong difficulty for %s: you are on %s, it drops on %s."],
      mountName(w.id), here, names(w.wanted))
  end
  ns.Game.ScreenWarning(#lines == 1 and lines[1]
    or string.format(L["Wrong difficulty for %d mounts in your pop-outs: see chat."], #lines))
  for _, line in ipairs(lines) do say(line) end
  return lines
end

-- A moment after the loading screen: the instance's difficulty is known then.
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_DIFFICULTY_CHANGED", "ZONE_CHANGED_NEW_AREA" }) do
  events:RegisterEvent(event)
end
events:SetScript("OnEvent", function()
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(2, function() UI.CheckDifficulty() end)
  else
    UI.CheckDifficulty()
  end
end)
