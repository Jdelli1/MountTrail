-- Logic/Lists.lua: custom checklists (pure).

describe("Lists", function()
  local function load() return load_addon({ "Core/Locale.lua", "Logic/Lists.lua" }).Lists end

  it("creates numbered lists; empty names refused; long names cut", function()
    local L = load()
    local store = {}
    eq(L.Create(store, "  WoD loop  "), 1)
    eq(L.Create(store, "Tanaan"), 2)
    eq(L.Create(store, "   "), nil)
    eq(L.Get(store, 1).name, "WoD loop")
    eq(#L.Get(store, L.Create(store, string.rep("x", 60))).name, 40)
  end)

  it("adds, removes, toggles mounts in order; no duplicates", function()
    local L = load()
    local store = {}
    local id = L.Create(store, "A")
    eq(L.Add(store, id, 614), true)
    eq(L.Add(store, id, 657), true)
    eq(L.Add(store, id, 614), false, "already there")
    eq(L.Get(store, id).mounts, { 614, 657 })
    eq(L.Toggle(store, id, 614), false)
    eq(L.Get(store, id).mounts, { 657 })
    eq(L.Toggle(store, id, 614), true)
    eq(L.Has(store, id, 614), true)
    eq(L.Remove(store, id, 1), false)
    eq(L.Add(store, 99, 1), false, "no such list")
  end)

  it("renames, deletes, sorts by name", function()
    local L = load()
    local store = {}
    local b = L.Create(store, "beta")
    local a = L.Create(store, "Alpha")
    L.Add(store, a, 1)
    eq(L.Sorted(store), { { id = a, name = "Alpha", count = 1 }, { id = b, name = "beta", count = 0 } })
    eq(L.Rename(store, b, "Aardvark"), true)
    eq(L.Rename(store, b, ""), false)
    eq(L.Sorted(store)[1].name, "Aardvark")
    L.Delete(store, a)
    eq(#L.Sorted(store), 1)
    eq(L.Get(store, a), nil)
  end)
end)
