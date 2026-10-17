local ADDON, ns = ...

-- Reads attempt counts from Rarity (optional dependency) when it is loaded.
-- Rarity keeps its items at Rarity.db.profile.groups[<group>][<item name>] =
-- { itemId=, attempts=, ... }; groups also hold non-item fields, so every level
-- is type-checked. Any failure (Rarity absent, old/new data shape, an API
-- error) gives nil, never a Lua error.
local RarityBridge = {}
ns.RarityBridge = RarityBridge

local function isRarityLoaded()
  local addons = C_AddOns
  if type(addons) ~= "table" or type(addons.IsAddOnLoaded) ~= "function" then return false end
  return addons.IsAddOnLoaded("Rarity") and true or false
end

local function scan(itemID)
  if not isRarityLoaded() then return nil end
  local rarity = Rarity
  if type(rarity) ~= "table" then return nil end
  local db = rarity.db
  if type(db) ~= "table" or type(db.profile) ~= "table" then return nil end
  local groups = db.profile.groups
  if type(groups) ~= "table" then return nil end
  for _, group in pairs(groups) do
    if type(group) == "table" then
      for _, item in pairs(group) do
        if type(item) == "table" and item.itemId == itemID then
          if type(item.attempts) == "number" then return item.attempts end
          return nil
        end
      end
    end
  end
  return nil
end

-- -> Rarity's attempt count for itemID, or nil.
function RarityBridge.Attempts(itemID)
  if itemID == nil then return nil end
  local good, attempts = pcall(scan, itemID)
  if good then return attempts end
  return nil
end
