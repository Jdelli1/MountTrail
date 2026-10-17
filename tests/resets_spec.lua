describe("resets", function()
  local function load() return load_addon({"Logic/Resets.lua"}) end

  it("Expiry daily adds untilDaily", function()
    eq(load().Resets.Expiry("daily", 1000, 50, 900), 1050)
  end)

  it("Expiry weekly adds untilWeekly", function()
    eq(load().Resets.Expiry("weekly", 1000, 50, 900), 1900)
  end)

  it("Expiry raises on unknown kind", function()
    local R = load().Resets
    local good, err = pcall(R.Expiry, "monthly", 1000, 50, 900)
    ok(not good, "expected error")
    ok(tostring(err):find("monthly", 1, true), "error should name the kind: " .. tostring(err))
  end)

  it("tick is active until the expiry moment", function()
    local R = load().Resets
    local store = {}
    R.Tick(store, 395, "daily", 1000, 50, 900)
    eq(R.IsTicked(store, 395, 1049), true)
    eq(R.IsTicked(store, 395, 1050), false)
    eq(R.IsTicked(store, 999, 1000), false)
  end)

  it("Untick removes", function()
    local R = load().Resets
    local store = {}
    R.Tick(store, 395, "weekly", 1000, 50, 900)
    R.Untick(store, 395)
    eq(R.IsTicked(store, 395, 1001), false)
    eq(store, {})
  end)

  it("prune drops expired ticks", function()
    local R = load().Resets
    local store = {[1]=10, [2]=100}
    R.Prune(store, 50)
    eq(store, {[2]=100})
  end)
end)
