-- Shared lists: the !MT1! string, chunks and links (Logic/Share.lua), and the
-- export / import / chat link / send flow (UI/Share.lua).

local function loadLogic()
  return load_addon({ "Core/Locale.lua", "Logic/Lists.lua", "Logic/Share.lua" })
end

describe("Share format", function()
  it("round-trips a list; odd names survive; unknown mounts are dropped", function()
    local S = loadLogic().Share
    local text = S.Encode("Mythic! 100% | [tbc]", { 5, 36, 1679, 5 })
    ok(text:find("^!MT1!"), text)
    ok(not text:find("|", 1, true), "no pipes in the string (chat would eat them)")
    eq(S.Decode("  " .. text .. "\n"), { name = "Mythic! 100% | [tbc]", mounts = { 5, 36, 1679 } })
    eq(S.Decode(text, { [5] = {}, [36] = {} }).mounts, { 5, 36 }, "known mounts only")
  end)

  it("says why a string is refused", function()
    local S = loadLogic().Share
    local text = S.Encode("Loop", { 1, 2, 3 })
    eq({ S.Decode("hello") }, { nil, "format" })
    eq({ S.Decode(text:sub(1, -3) .. "zz") }, { nil, "damaged" })
    eq({ S.Decode(text:gsub("!1%.", "!9.")) }, { nil, "damaged" }, "a changed id")
    eq({ S.Decode(S.Encode("Loop", { 1 }), { [2] = {} }) }, { nil, "empty" })
    eq({ S.Decode(S.Encode("   ", { 1 })) }, { nil, "format" }, "no name")
  end)

  it("FreeName adds (2), (3) to a taken name", function()
    local S = loadLogic().Share
    local store = { lists = { { name = "Loop" }, { name = "Loop (2)" } } }
    eq(S.FreeName(store, "Loop"), "Loop (3)")
    eq(S.FreeName(store, "New"), "New")
  end)

  it("chunks come back together per sender; a gap starts over", function()
    local S = loadLogic().Share
    local text = string.rep("abcdefghij", 60) -- 600 characters: 3 chunks
    local parts = S.Chunks("D", text)
    eq(#parts, 3)
    for _, p in ipairs(parts) do ok(#p <= 255, "fits an addon message") end
    local a = S.Assembler()
    eq(a:Add("Bob", parts[1]), nil)
    eq(a:Add("Eve", parts[2]), nil, "another sender's chunk does not mix in")
    eq(a:Add("Bob", parts[2]), nil)
    eq({ a:Add("Bob", parts[3]) }, { text, "D" })
    eq(a:Add("Bob", parts[3]), nil, "a stray last chunk: nothing")
    eq({ S.Parse("R12") }, { "R", 12 })
    eq(S.Parse("X1/1:hi"), nil)
  end)

  it("links carry the sharer and the list", function()
    local S = loadLogic().Share
    local link = S.Link("Bob-Realm", 3, "Loop")
    ok(link:find("|Hgarrmission:mounttrail:Bob-Realm:3|h[MountTrail: Loop]|h", 1, true), link)
    eq({ S.ParseLink("garrmission:mounttrail:Bob-Realm:3") }, { "Bob-Realm", 3 })
    eq(S.ParseLink("garrmission:12345"), nil, "the game's own mission links")
  end)
end)

describe("Share flow", function()
  local function loadUI()
    reset_ui_stub()
    local files = toc_lua_files()
    for _, f in ipairs({ "UI/Frame.lua", "UI/Share.lua" }) do files[#files + 1] = f end
    local ns = load_addon(files)
    ns.addon:OnInitialize()
    ns.db.global.lists = {}
    local store = ns.db.global.lists
    ns.UI.ListsDB = function() return store end
    ns.Data.Mounts = { [1] = { name = "A" }, [2] = { name = "B" }, [3] = { name = "C" } }
    ns.Game.CharKey = function() return "Alice-Realm" end
    ns.Refresh = function() end
    local sent = {}
    ns.Game.SendAddonWhisper = function(prefix, msg, target)
      sent[#sent + 1] = { prefix = prefix, msg = msg, target = target }
      return true
    end
    local prompts = {}
    ns.UI.AskText = function(title, default, onAccept, opts)
      prompts[#prompts + 1] = { title = title, default = default, accept = onAccept, opts = opts }
    end
    return ns, store, sent, prompts
  end

  it("a chat link: the clicker asks, the sharer answers, the clicker is asked to import", function()
    local ns, store, sent, prompts = loadUI()
    local id = ns.Lists.Create(store, "Loop")
    ns.Lists.Add(store, id, 1)
    ns.Lists.Add(store, id, 3)
    local linked
    ns.Game.InsertChatLink = function(link) linked = link return true end
    ok(ns.UI.ShareListInChat(id))
    eq(linked, ns.Share.Encode("Loop", { 1, 3 }), "a short list goes as its line")
    -- Too long for one chat message: the link that asks for it.
    for m = 1000, 1100 do ns.Lists.Add(store, id, m) end
    ok(ns.UI.ShareListInChat(id))
    ok(linked:find("mounttrail:Alice-Realm:" .. id, 1, true), linked)

    -- Bob clicked it: his request arrives; only a shared list answers.
    ns.UI.OnShareMessage("R" .. (id + 1), "Bob-Realm")
    eq(#sent, 0, "an unshared list does not answer")
    ns.UI.OnShareMessage("R" .. id, "Bob-Realm")
    ok(#sent >= 1 and sent[1].target == "Bob-Realm" and sent[1].msg:find("^D1/"), "answers Bob")

    -- On Bob's side (same code): he asked Alice, her chunks come in.
    local answer = sent
    local bob, bobStore, bobSent, bobPrompts = loadUI()
    bob.Game.CharKey = function() return "Bob-Realm" end
    bob.UI.RequestSharedList("Alice-Realm", id)
    eq(bobSent[1].msg, "R" .. id)
    for _, s in ipairs(answer) do bob.UI.OnShareMessage(s.msg, "Alice-Realm") end
    eq(#bobPrompts, 1, "asked to import")
    eq(bobPrompts[1].default, "Loop")
    bobPrompts[1].accept("Loop")
    local sorted = bob.Lists.Sorted(bobStore)
    eq(#sorted, 1)
    eq(bob.Lists.Get(bobStore, sorted[1].id).mounts, { 1, 3 })
  end)

  it("an answer nobody asked for is ignored; an offer (Send to player) asks first", function()
    local ns, store, sent, prompts = loadUI()
    local text = ns.Share.Encode("Gift", { 2 })
    for _, p in ipairs(ns.Share.Chunks("D", text)) do ns.UI.OnShareMessage(p, "Eve-Realm") end
    eq(#prompts, 0, "unasked answer: nothing")
    for _, p in ipairs(ns.Share.Chunks("O", text)) do ns.UI.OnShareMessage(p, "Bob-Realm") end
    eq(#prompts, 1)
    ok(prompts[1].title:find("Bob-Realm", 1, true))
    ns.Lists.Create(store, "Gift")
    prompts[1].accept("Gift")
    eq(ns.Lists.Get(store, 2).name, "Gift (2)", "a taken name gets a number")
  end)

  it("export shows the string; import takes a pasted one and asks for the name", function()
    local ns, store, sent, prompts = loadUI()
    local id = ns.Lists.Create(store, "Loop")
    ns.Lists.Add(store, id, 2)
    local copied
    ns.UI.ShowCopyText = function(_, text) copied = text end
    ns.UI.ExportList(id)
    eq(ns.Share.Decode(copied).mounts, { 2 })
    ns.UI.ImportListPrompt()
    ok(prompts[1].opts.long, "a paste box without the name limit")
    prompts[1].accept(copied)
    eq(#prompts, 2, "then the import question")
    prompts[2].accept("Loop copy")
    eq(ns.Lists.Get(store, 2).name, "Loop copy")
    local said
    ns.addon.Print = function(_, msg) said = msg end
    ns.UI.ImportListPrompt()
    prompts[3].accept("not a list")
    eq(said, "That is not a MountTrail list.")
  end)

  it("Send to player whispers the list in chunks", function()
    local ns, store, sent = loadUI()
    local id = ns.Lists.Create(store, "Loop")
    for i = 1, 3 do ns.Lists.Add(store, id, i) end
    ok(ns.UI.SendList(id, "Bob", "O"))
    eq(sent[1].target, "Bob")
    ok(sent[1].msg:find("^O1/1:!MT1!"), sent[1].msg)
  end)

  it("a !MT1! line in chat becomes a link; clicking it offers the import", function()
    local ns, store, sent, prompts = loadUI()
    local line = ns.Share.Encode("Mythic Mounts", { 1, 2, 99 })
    local msg = ns.UI.LinkShareStrings("try this " .. line .. " :)")
    ok(msg:find("^try this |cff3fc7eb|Haddon:MountTrail:import:%d+|h%[MountTrail: Mythic Mounts %(2%)%]|h|r :%)$"), msg)
    eq(ns.UI.LinkShareStrings("no list here"), nil)
    eq(ns.UI.LinkShareStrings("!MT1!broken!1!zz"), nil, "a damaged line stays text")
    local n = msg:match("import:(%d+)")
    ok(ns.UI.OnShareLink("addon:MountTrail:import:" .. n))
    eq(#prompts, 1)
    eq(prompts[1].default, "Mythic Mounts")
    prompts[1].accept("Mythic Mounts")
    eq(ns.Lists.Get(store, 1).mounts, { 1, 2 }, "known mounts only")
    eq(ns.UI.OnShareLink("item:123"), false, "other links are not ours")
  end)

  it("the real Mythic Mounts line from chat decodes", function()
    local ns = load_addon({ "Core/Locale.lua", "Data/Mounts.lua", "Logic/Lists.lua", "Logic/Share.lua" })
    local line = "!MT1!Mythic Mounts!ob.oj.y3.ys.rn.sw.t9.155.132.1p8.269.25x.2cy!9bhq"
    local found = ns.Share.Find("[Adventurer]: " .. line)
    eq(#found, 1)
    local decoded = ns.Share.Decode(found[1].text, ns.Data.Mounts)
    ok(decoded, "decodes")
    eq(decoded.name, "Mythic Mounts")
    eq(#decoded.mounts, 13)
  end)
end)
