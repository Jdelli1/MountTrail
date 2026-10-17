describe("data", function()
  local FILES = {"Data/Mounts.lua", "Data/Route.lua", "Data/Lockouts.lua", "Data/Holidays.lua"}

  it("every route boss has a lockout spec or a Rarity quest", function()
    local ns = load_addon({"Data/Mounts.lua","Data/Route.lua","Data/Lockouts.lua"})
    local missing = {}
    local function walk(n) for _,b in ipairs(n.bosses or {}) do
        if not ns.Data.Lockouts[b.mount] and not (ns.Data.Mounts[b.mount] or {}).quest then missing[#missing+1]=b.mount end end
      for _,c in ipairs(n.steps or {}) do walk(c) end end
    for _,n in ipairs(ns.Data.Route) do walk(n) end
    eq(missing, {})
  end)

  it("lockout specs are well-formed", function()
    local ns = load_addon(FILES)
    local bad = {}
    local function fail(id, why) bad[#bad + 1] = tostring(id) .. ": " .. why end
    for id, s in pairs(ns.Data.Lockouts) do
      if type(id) ~= "number" then fail(id, "key not a number") end
      if not ns.Data.Mounts[id] then fail(id, "unknown mount") end
      local kinds = 0
      if s.instance ~= nil then kinds = kinds + 1 end
      if s.quest ~= nil then kinds = kinds + 1 end
      if s.lfg ~= nil then kinds = kinds + 1 end
      if s.manual ~= nil then kinds = kinds + 1 end
      if kinds ~= 1 then fail(id, "has " .. kinds .. " of instance/quest/lfg/manual") end
      if s.reset ~= "daily" and s.reset ~= "weekly" then fail(id, "reset is " .. tostring(s.reset)) end
      if s.instance ~= nil then
        if type(s.instance) ~= "number" then fail(id, "instance not a number") end
        if type(s.boss) ~= "string" or s.boss == "" then fail(id, "instance spec without boss") end
        if type(s.difficulties) ~= "table" or #s.difficulties == 0 then
          fail(id, "instance spec without difficulties")
        else
          for _, d in ipairs(s.difficulties) do
            if type(d) ~= "number" then fail(id, "difficulty not a number") end
          end
        end
      else
        if s.boss ~= nil or s.difficulties ~= nil then fail(id, "boss/difficulties on a non-instance spec") end
      end
      if s.quest ~= nil and type(s.quest) ~= "number" then fail(id, "quest not a number") end
      if s.lfg ~= nil and type(s.lfg) ~= "number" then fail(id, "lfg not a number") end
      if s.manual ~= nil and s.manual ~= true then fail(id, "manual must be true") end
      if s.requires ~= nil then
        if type(s.requires) ~= "table" or type(s.requires.quest) ~= "number"
          or type(s.requires.text) ~= "string" or s.requires.text == "" then
          fail(id, "requires must be {quest=<number>, text=<string>}")
        end
      end
    end
    table.sort(bad)
    eq(bad, {})
  end)

  it("defines the three holiday-boss events with their LFG dungeons", function()
    local ns = load_addon(FILES)
    local H = ns.Data.Holidays
    eq(H.hallowsend.lfg, 285)
    eq(H.brewfest.lfg, 287)
    eq(H.loveisintheair.lfg, 288)
    eq(H.hallowsend.title, "Hallow's End")
    eq(H.brewfest.title, "Brewfest")
    eq(H.loveisintheair.title, "Love is in the Air")
  end)

  it("holiday entries are well-formed and list mounts of their own section", function()
    local ns = load_addon(FILES)
    local bad = {}
    local function fail(key, why) bad[#bad + 1] = tostring(key) .. ": " .. why end
    for key, h in pairs(ns.Data.Holidays) do
      if type(h.title) ~= "string" or h.title == "" then fail(key, "no title") end
      if h.lfg ~= nil and type(h.lfg) ~= "number" then fail(key, "lfg not a number") end
      if type(h.mounts) ~= "table" then fail(key, "no mounts table") end
      if h.coords ~= nil and type(h.coords.m) ~= "number" then fail(key, "coords without map") end
      if #(h.mounts or {}) > 0 and (type(h.stepTitle) ~= "string" or h.stepTitle == "") then
        fail(key, "mounts but no stepTitle")
      end
      for _, id in ipairs(h.mounts or {}) do
        local m = ns.Data.Mounts[id]
        if not m then fail(key, "unknown mount " .. id)
        elseif m.tab ~= "holiday" or m.section ~= key then fail(key, "mount " .. id .. " is not in section " .. key)
        elseif m.unobtainable then fail(key, "mount " .. id .. " is unobtainable") end
      end
    end
    table.sort(bad)
    eq(bad, {})
  end)

  it("every holiday-boss mount has a daily lfg spec for its event (R3)", function()
    local ns = load_addon(FILES)
    local bad = {}
    for key, h in pairs(ns.Data.Holidays) do
      if h.lfg then
        for _, id in ipairs(h.mounts) do
          local s = ns.Data.Lockouts[id]
          if not s or s.lfg ~= h.lfg or s.reset ~= "daily" then
            bad[#bad + 1] = key .. ":" .. id
          end
        end
      end
    end
    table.sort(bad)
    eq(bad, {})
  end)

  it("every obtainable LFG-boss holiday mount is listed under its event", function()
    local ns = load_addon(FILES)
    local listed = {}
    for _, h in pairs(ns.Data.Holidays) do
      for _, id in ipairs(h.mounts) do listed[id] = true end
    end
    -- the mounts dropped by the holiday dungeon bosses (Rarity lockDungeonId 285/287/288)
    local expected = {219, 2623, 202, 226, 2640, 352, 2328, 2492}
    local missing = {}
    for _, id in ipairs(expected) do
      if not listed[id] then missing[#missing + 1] = id end
    end
    eq(missing, {})
  end)
end)
