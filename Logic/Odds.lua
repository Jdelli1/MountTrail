local ADDON, ns = ...

-- Drop-chance arithmetic for the mount tooltip ("1 in N chance", "Lucky if
-- you obtain in K or less", "Chance so far P%"), as Rarity shows it. Pure
-- Lua, no WoW API. N is the data's `chance` (a 1-in-N drop rate).

local Odds = {}
ns.Odds = Odds

local function usable(n)
  return type(n) == "number" and n > 0
end

-- Attempts by which half of all players have the mount:
-- ceil(ln 0.5 / ln (1 - 1/N)); N = 100 -> 69. N <= 1 (a sure drop) -> 1.
-- nil without a usable N.
function Odds.LuckyBy(n)
  if not usable(n) then return nil end
  if n <= 1 then return 1 end
  local k = math.log(0.5) / math.log(1 - 1 / n)
  -- Float noise must not push an exact integer (N = 2 -> 1) up a step.
  return math.max(1, math.ceil(k - 1e-9))
end

-- Chance of having seen at least one drop in A attempts at 1 in N:
-- 1 - (1 - 1/N)^A, a fraction 0..1 (N = 100, A = 30 -> 0.2603). nil without a
-- usable N or a non-negative A.
function Odds.ChanceSoFar(n, attempts)
  if not usable(n) or type(attempts) ~= "number" or attempts < 0 then return nil end
  if n <= 1 then return attempts > 0 and 1 or 0 end
  return 1 - (1 - 1 / n) ^ attempts
end

-- A fraction as a percentage with two decimals: 0.2603 -> "26.03%".
function Odds.Percent(p)
  if type(p) ~= "number" then return nil end
  return string.format("%.2f%%", p * 100)
end
