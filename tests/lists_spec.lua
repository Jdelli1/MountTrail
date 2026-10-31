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

  it("moves a mount one place, or before another; the ends hold", function()
    local L = load()
    local store = {}
    local id = L.Create(store, "A")
    for _, m in ipairs({ 1, 2, 3, 4 }) do L.Add(store, id, m) end
    eq(L.Move(store, id, 3, -1), true)
    eq(L.Get(store, id).mounts, { 1, 3, 2, 4 })
    eq(L.Move(store, id, 1, -1), false, "already first")
    eq(L.Move(store, id, 4, 1), false, "already last")
    eq(L.Move(store, id, 99, 1), false, "not on the list")
    eq(L.MoveBefore(store, id, 4, 1), true)
    eq(L.Get(store, id).mounts, { 4, 1, 3, 2 })
    eq(L.MoveBefore(store, id, 4, nil), true, "nil: to the end")
    eq(L.Get(store, id).mounts, { 1, 3, 2, 4 })
    eq(L.MoveBefore(store, id, 2, 4), false, "already there: no change")
  end)

  it("a list's sort: in the order added by default, or by expansion", function()
    local L = load()
    local store = {}
    local id = L.Create(store, "A")
    eq(L.SortOf(store, id), "added", "the default")
    L.SetSort(store, id, "expansion")
    eq(L.SortOf(store, id), "expansion")
    L.SetSort(store, id, "added")
    eq(L.Get(store, id).sort, nil, "the default stores nothing")
    local mounts = { [1] = { exp = "Legion" }, [2] = { exp = "Classic" }, [3] = {}, [4] = { exp = "Legion" } }
    local function ids(t) local o = {} for i, e in ipairs(t) do o[i] = e.id end return o end
    eq(ids(L.Ordered({ 4, 3, 2, 1 }, mounts, "added", { "Classic", "Legion" })), { 4, 3, 2, 1 })
    eq(ids(L.Ordered({ 4, 3, 2, 1 }, mounts, "expansion", { "Classic", "Legion" })), { 2, 4, 1, 3 },
      "Classic, then Legion in the list's order, unknown last")
  end)
end)
