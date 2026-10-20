local ADDON, ns = ...

-- How rare a mount is: the share of characters that own it, from the
-- MountsRarity-2.0 library (sgade/MountsRarity; GPL-3.0, so not bundled).
-- It is read at run time when another add-on has loaded it (Mount Journal
-- Enhanced embeds it, or the standalone MountsRarity add-on); without it
-- every lookup is nil and nothing shows. Its tiers and colours follow Mount
-- Journal Enhanced's: under 2 % legendary, under 10 % epic, under 20 % rare,
-- under 50 % uncommon, else common. (Not to be confused with the Rarity
-- add-on, Integrations/Rarity.lua, which counts attempts.)
local Owners = {}
ns.Owners = Owners

-- The library, or nil. Owners.lib (tests) overrides the LibStub lookup.
local function library()
  if Owners.lib ~= nil then return Owners.lib or nil end
  if type(LibStub) ~= "function" then return nil end
  local good, lib = pcall(LibStub, "MountsRarity-2.0", true)
  if good and type(lib) == "table" then return lib end
  return nil
end

-- Whether the library is loaded.
function Owners.Available()
  return library() ~= nil
end

-- -> the percentage (0-100) of characters owning the mount, or nil (no
-- library, an untracked mount, or an error).
function Owners.Percent(mountID)
  local lib = library()
  if not (lib and mountID and type(lib.GetRarityByID) == "function") then return nil end
  local good, pct = pcall(lib.GetRarityByID, lib, mountID)
  if good and type(pct) == "number" then return pct end
  return nil
end

-- Item quality of a percentage (Enum.ItemQuality values: 1 common ...
-- 5 legendary).
function Owners.Quality(pct)
  if pct < 2 then return 5 end
  if pct < 10 then return 4 end
  if pct < 20 then return 3 end
  if pct < 50 then return 2 end
  return 1
end

-- The game's item quality colours, for clients without C_Item.GetItemQualityColor.
local FALLBACK = {
  [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
  [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}

-- -> { r, g, b } of a percentage's quality.
function Owners.Color(pct)
  local quality = Owners.Quality(pct)
  local item = C_Item
  if type(item) == "table" and type(item.GetItemQualityColor) == "function" then
    local good, r, g, b = pcall(item.GetItemQualityColor, quality)
    if good and type(r) == "number" then return { r, g, b } end
  end
  return FALLBACK[quality]
end

-- "0.28%" (two decimals under 10 %, one above).
function Owners.Text(pct)
  return string.format(pct < 10 and "%.2f%%" or "%.1f%%", pct)
end
