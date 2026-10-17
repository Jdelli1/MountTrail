-- RarityBridge reads attempts from Rarity's saved data when Rarity is loaded.
-- The globals it reads are saved and restored around every test.
local GLOBALS = { "Rarity", "C_AddOns" }
local ORIGINAL = {}
for _, name in ipairs(GLOBALS) do ORIGINAL[name] = _G[name] end

local harnessIt = it
local function it(name, fn)
  return harnessIt(name, function()
    local saved = {}
    for _, name in ipairs(GLOBALS) do saved[name] = _G[name] end
    local good, err = pcall(fn)
    for _, name in ipairs(GLOBALS) do _G[name] = saved[name] end
    if not good then error(err, 0) end
  end)
end

local function loadBridge()
  return load_addon({ "Core/Locale.lua", "Integrations/Rarity.lua" }).RarityBridge
end

local function rarityLoaded(loaded)
  C_AddOns = { IsAddOnLoaded = function(name)
    eq(name, "Rarity")
    return loaded, loaded
  end }
end

local function rarityWith(groups)
  Rarity = { db = { profile = { groups = groups } } }
end

describe("RarityBridge.Attempts", function()
  it("returns attempts for the entry whose itemId matches", function()
    rarityLoaded(true)
    rarityWith({
      mounts = {
        name = "Mounts", collapsed = false, -- non-item fields Rarity keeps in groups
        ["Reins of the Drake"] = { itemId = 111, attempts = 7 },
        ["Reins of the Vitreous Stone Drake"] = { itemId = 63043, attempts = 42 },
      },
      pets = { ["Some Pet"] = { itemId = 222, attempts = 3 } },
    })
    eq(loadBridge().Attempts(63043), 42)
  end)

  it("returns nil when no entry matches or attempts is not a number", function()
    rarityLoaded(true)
    rarityWith({ mounts = {
      ["Counted"] = { itemId = 1, attempts = 5 },
      ["Never tried"] = { itemId = 2 },
      ["Odd"] = { itemId = 3, attempts = "lots" },
    } })
    local B = loadBridge()
    eq(B.Attempts(99), nil)
    eq(B.Attempts(2), nil)
    eq(B.Attempts(3), nil)
    eq(B.Attempts(1), 5)
  end)

  it("returns nil when the Rarity global is absent", function()
    rarityLoaded(true)
    Rarity = nil
    eq(loadBridge().Attempts(63043), nil)
  end)

  it("returns nil when Rarity is not loaded, even with data present", function()
    rarityLoaded(false)
    rarityWith({ mounts = { ["X"] = { itemId = 63043, attempts = 42 } } })
    eq(loadBridge().Attempts(63043), nil)
  end)

  it("returns nil when C_AddOns is missing", function()
    C_AddOns = nil
    rarityWith({ mounts = { ["X"] = { itemId = 63043, attempts = 42 } } })
    eq(loadBridge().Attempts(63043), nil)
  end)

  it("returns nil without error when Rarity.db is malformed", function()
    rarityLoaded(true)
    local B = loadBridge()
    local shapes = {
      { db = nil },
      { db = "broken" },
      { db = { profile = nil } },
      { db = { profile = { groups = "nope" } } },
      { db = { profile = { groups = { mounts = "not a table", other = { x = 5 } } } } },
      { db = setmetatable({}, { __index = function() error("boom") end }) },
    }
    for i, shape in ipairs(shapes) do
      Rarity = shape
      eq(B.Attempts(63043), nil, "shape " .. i)
    end
    Rarity = "a string"
    eq(B.Attempts(63043), nil, "Rarity not a table")
    C_AddOns = { IsAddOnLoaded = function() error("api broke") end }
    rarityWith({ mounts = { ["X"] = { itemId = 63043, attempts = 42 } } })
    eq(B.Attempts(63043), nil, "IsAddOnLoaded erroring")
  end)
end)

describe("rarity spec hygiene", function()
  harnessIt("globals are back to their original values", function()
    for _, name in ipairs(GLOBALS) do eq(_G[name], ORIGINAL[name], name .. " restored") end
  end)
end)
