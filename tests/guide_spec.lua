-- Mount guides: the text format (Logic/Guide.lua), following a guide
-- (UI/Guides.lua), its window and the editor.

local function loadLogic()
  return load_addon({ "Core/Locale.lua", "Logic/Guide.lua", "Guides/ThunderingRubyCloudSerpent.lua" })
end

describe("Guide format", function()
  it("reads the built-in guide", function()
    local ns = loadLogic()
    local g, errors = ns.Guide.Parse(ns.GuideTexts[1])
    eq(errors, {})
    eq(g.title, "Thundering Ruby Cloud Serpent")
    eq(g.mounts, { 517 })
    eq(g.author, "MountTrail")
    eq(#g.steps, 5)
    eq(#g.steps[3].gotos, 3)
    eq(g.steps[3].gotos[1], { m = 390, x = 35.6, y = 26, label = "Alani (north)" })
    eq(g.credits[1], "Alani's spawn points from AllTheThings")
    eq(g.steps[3].macro, "/tar Alani")
    ok(g.steps[1].text:find("**", 1, true) and g.steps[5].text:find("[mount:517]", 1, true),
      "it shows highlighting and links")
    eq(g.steps[1].done, { { kind = "reach", yards = 200 } })
    eq(g.steps[5].done, { { kind = "mount", id = 517 } })
    eq(g.steps[2].notes[1]:sub(1, 9), "Skyshards")
    eq(#g.steps[2].notes, 2)
  end)

  it("says what is wrong and on which line, keeping the rest", function()
    local G = loadLogic().Guide
    local g, errors = G.Parse(table.concat({
      "#guide Test",
      "step One",
      "  goto 390 35.6", -- 3: no y
      "  goto 390 120 5", -- 4: out of range
      "  fly somewhere", -- 5: unknown
      "  item 5 x", -- 6: bad count
      "step Two",
      "  reach", -- 8: no goto in this step
      "  quest 77",
    }, "\n"))
    ok(g, "still a guide")
    eq(#g.steps, 2)
    local lines = {}
    for _, e in ipairs(errors) do lines[#lines + 1] = e.line end
    eq(lines, { 3, 4, 5, 6, 7 })
    eq(errors[3].msg, "Unknown line: fly")
    local none, why = G.Parse("step lonely")
    eq(none, nil)
    eq(why[1].msg, "The first line must be: #guide <title>")
    eq(select(2, G.Parse(""))[1].msg, "The guide is empty.")
    eq(select(2, G.Parse("#guide T"))[1].msg, "A guide needs at least one step.")
  end)

  it("a step is done when every done line holds; none means Next only", function()
    local G = loadLogic().Guide
    local g = G.Parse("#guide T\nstep A\n goto 1 50 50\n quest 9\n item 4 3\n reach 10\nstep B")
    local ctx = {
      isQuestDone = function(id) return id == 9 end,
      itemCount = function() return 3 end,
      near = function(p, yards) return p.x == 50 and yards == 10 end,
    }
    eq(G.StepDone(g.steps[1], ctx), true)
    ctx.itemCount = function() return 2 end
    eq(G.StepDone(g.steps[1], ctx), false, "2 of 3 items")
    eq(G.StepDone(g.steps[2], ctx), false, "no done line: Next only")
    eq(G.Clamp(g, 9), 2)
    eq(G.Clamp(g, 0), 1)
    eq(G.Id("Thundering Ruby: Cloud Serpent!"), "thundering-ruby-cloud-serpent")
    eq(G.DoneText(g.steps[1]), { "turn in [quest:9]", "3 x [item:4]", "reach the spot" })
  end)

  it("markup: **highlight** and [kind:id] links", function()
    local G = loadLogic().Guide
    local function linkFor(kind, id) return kind == "item" and ("<item " .. id .. ">") or nil end
    eq(G.Markup("Loot **ten** [item:86547] now", linkFor), "Loot |cffffd100ten|r <item 86547> now")
    eq(G.Markup("Turn in [quest:5]", linkFor), "Turn in [quest 5]", "no link yet: plain text")
    eq(G.Markup("[npc:5] and [Item:2]", linkFor), "[npc:5] and <item 2>", "unknown kinds stay as written")
    eq(G.Markup("**a** b **c**"), "|cffffd100a|r b |cffffd100c|r")
  end)
end)

describe("Following a guide", function()
  local function loadUI()
    reset_ui_stub()
    local files = toc_lua_files()
    for _, f in ipairs({ "UI/Frame.lua", "UI/Guides.lua", "UI/GuideWindow.lua", "UI/GuideEditor.lua" }) do
      files[#files + 1] = f
    end
    local ns = load_addon(files)
    ns.addon:OnInitialize()
    local plots = {}
    ns.Map = {
      PlotPoints = function(points) plots[#plots + 1] = points return #points end,
      ClearPlot = function() plots[#plots + 1] = "clear" end,
      YardsTo = function() return nil end,
    }
    ns.Game.IsQuestDone = function() return false end
    ns.Game.ItemCount = function() return 0 end
    ns.Game.IsOwned = function() return false end
    ns.Game.MountInfo = function() return nil end
    ns.Game.MapName = function(m) return m == 390 and "Vale of Eternal Blossoms" or nil end
    local said = {}
    ns.addon.Print = function(_, msg) said[#said + 1] = msg end
    return ns, plots, said
  end

  it("Next plots the next step, Back takes it back; the step is kept per guide", function()
    local ns, plots = loadUI()
    local id = "builtin:thundering-ruby-cloud-serpent"
    ok(ns.UI.GuideById(id), "the built-in guide is listed")
    ok(ns.UI.StartGuide(id))
    eq(plots[1], { { 390, 56.2, 42.6, "Vale of Eternal Blossoms" } })
    local w = ns.UI.GuideWindow()
    ok(w:IsShown(), "the window opens")
    eq(w.Count:GetText(), "1 / 5")
    eq(w.StepText:GetText(), "Travel to the |cffffd100Vale of Eternal Blossoms|r in Pandaria")
    eq(w.Done:GetText(), "Done when: reach the spot")
    ok(w.Place:GetText():find("Vale of Eternal Blossoms: Vale of Eternal Blossoms 56.2, 42.6", 1, true), w.Place:GetText())
    ns.UI.GuideGo(1)
    eq(plots[2], "clear", "step 2 has no points")
    ok(w.Done:GetText():find("^Done when: 10 x "), "ten Skyshards finish step 2")
    ns.UI.GuideGo(1)
    eq(#plots[3], 3, "Alani's three spots")
    ns.UI.GuideGo(-1)
    eq(plots[4], "clear")
    eq(ns.db.char.guides.steps[id], 2)
    ns.UI.StopGuide()
    ok(not w:IsShown())
    eq(ns.db.char.guides.active, nil)
    ns.UI.StartGuide(id)
    eq(w.Count:GetText(), "2 / 5", "resumes where it was")
    ns.UI.ResetGuide(id)
    eq(w.Count:GetText(), "1 / 5")
    eq(w.Next.Text:GetText(), "Next")
    ns.UI.GuideJump(5)
    eq(w.Next.Text:GetText(), "Finish", "the last step finishes")
    w.Next:RunScript("OnClick", "LeftButton")
    ok(not w:IsShown(), "Finish closes the guide")
    eq(ns.db.char.guides.active, nil)
    eq(ns.UI.GuideStepOf(id), 1, "next time from the start")
  end)

  it("a done step moves on by itself, but not right after Back", function()
    local ns, plots, said = loadUI()
    local near = false
    ns.Map.YardsTo = function() return near and 5 or 500 end
    local id = "builtin:thundering-ruby-cloud-serpent"
    ns.UI.StartGuide(id)
    ns.UI.CheckGuideStep()
    eq(ns.UI.GuideStepOf(id), 1, "not there yet")
    near = true
    ns.UI.CheckGuideStep()
    eq(ns.UI.GuideStepOf(id), 2, "reached the Vale")
    eq(said[#said], "Step done: now step 2 of 5")
    ns.UI.GuideGo(-1)
    ns.UI.CheckGuideStep()
    eq(ns.UI.GuideStepOf(id), 1, "held after Back")
    ns.UI.GuideGo(1)
    eq(ns.UI.GuideStepOf(id), 2)
    -- The last step: learning the mount completes the guide.
    ns.UI.GuideJump(5)
    ns.Game.IsOwned = function(m) return m == 517 end
    ns.UI.CheckGuideStep()
    eq(said[#said], "Guide complete: Thundering Ruby Cloud Serpent")
  end)

  it("the editor: new from the template, checks as you type, saves and follows", function()
    local ns = loadUI()
    local e = ns.UI.NewGuide()
    ok(e:IsShown())
    ok(e.Status:GetText():find("My mount guide: 2 steps", 1, true), e.Status:GetText())
    e.Edit:SetText("#guide Mine\nstep Go\n  goto 390 10\n")
    e.Edit:RunScript("OnTextChanged")
    eq(e.Status:GetText(), "Line 3: goto needs a map ID, then x and y")
    e.Edit:SetText("#guide Mine\nstep Go\n  goto 390 10 20\nstep Done")
    e.Edit:RunScript("OnTextChanged")
    e.Save:RunScript("OnClick", "LeftButton")
    ok(not e:IsShown(), "saved and closed")
    eq(ns.db.global.guides.mine, "#guide Mine\nstep Go\n  goto 390 10 20\nstep Done")
    local entry = ns.UI.ActiveGuide()
    eq(entry.id, "mine", "a new guide starts right away")
    -- A built-in guide edits as a copy; the same title gets a number.
    ns.UI.EditGuide("builtin:thundering-ruby-cloud-serpent")
    e.Save:RunScript("OnClick", "LeftButton")
    ok(ns.db.global.guides["thundering-ruby-cloud-serpent"], "saved as the player's own")
    ns.UI.EditGuide("builtin:thundering-ruby-cloud-serpent")
    e.Save:RunScript("OnClick", "LeftButton")
    ok(ns.db.global.guides["thundering-ruby-cloud-serpent-2"])
    -- Export shows the text, no Save.
    ns.UI.ExportGuide("mine")
    eq(e.Edit:GetText(), ns.db.global.guides.mine)
    ok(not e.Save:IsShown())
    -- Import: pasted text, saved as a new guide.
    ns.UI.ImportGuide()
    eq(e.Edit:GetText(), "")
    e.Edit:SetText("#guide Shared\nstep One")
    e.Edit:RunScript("OnTextChanged")
    e.Save:RunScript("OnClick", "LeftButton")
    ok(ns.db.global.guides.shared)
    ok(ns.UI.DeleteGuide("shared"))
    eq(ns.db.global.guides.shared, nil)
  end)

  it("Guides in the navigation column: + to add, click to follow, the step as its badge", function()
    local ns = loadUI()
    ns.ToggleWindow()
    local nav = ns.UI.frame.Nav
    local function button(label)
      for i = 1, nav.shown do
        if nav.Buttons[i].Text:GetText() == label then return nav.Buttons[i] end
      end
    end
    local heading
    for _, h in ipairs(nav.Headings) do if h:IsShown() and h.Text:GetText() == "Guides" then heading = h end end
    ok(heading, "a Guides heading")
    ok(nav.AddGuide:IsShown(), "with its +")
    local b = button("Thundering Ruby Cloud Serpent")
    ok(b, "the built-in guide")
    eq(b.Badge:GetText(), "", "not started")
    b:RunScript("OnClick", "LeftButton")
    eq(ns.UI.ActiveGuide().id, "builtin:thundering-ruby-cloud-serpent")
    eq(button("Thundering Ruby Cloud Serpent").Badge:GetText(), "|cff40c0401/5|r", "green while followed")
    local items
    ns.UI.ShowMenu = function(_, list) items = list end
    button("Thundering Ruby Cloud Serpent"):RunScript("OnClick", "RightButton")
    local texts = {}
    for _, it in ipairs(items) do if it.text then texts[#texts + 1] = it.text end end
    eq(texts, { "by MountTrail", "Alani's spawn points from AllTheThings", "An example guide: edit a copy to improve it",
      "Close guide", "Edit a copy...", "Export...", "Back to step 1" }, "authors and credits first; built-in: no Delete")
    eq(items[2].disabled, true, "the author line is not a button")
  end)

  it("the window shows markup as links with the game's tooltip", function()
    local ns = loadUI()
    ns.Game.ItemLink = function(id) return id == 86547 and "|cff1eff00|Hitem:86547|h[Skyshard]|h|r" or nil end
    local asked = {}
    ns.Game.RequestItem = function(id) asked[#asked + 1] = id end
    ns.Game.QuestName = function() return nil end
    ns.Game.RequestQuest = function() end
    ns.Data.Mounts = { [517] = { name = "Thundering Ruby Cloud Serpent", spell = 132036 } }
    eq(ns.UI.GuideLink("item", 86547), "|cff1eff00|Hitem:86547|h[Skyshard]|h|r")
    eq(ns.UI.GuideLink("item", 5), "|cffffffff|Hitem:5|h[item 5]|h|r")
    eq(asked, { 5 }, "an unloaded item is asked for")
    eq(ns.UI.GuideLink("mount", 517), "|cffa335ee|Haddon:MountTrail:mount:517|h[Thundering Ruby Cloud Serpent]|h|r")
    local mountTip
    ns.UI.ShowMountTooltip = function(_, id) mountTip = id end
    eq(ns.UI.GuideLink("quest", 7), "|cffffff00|Hquest:7:-1|h[quest 7]|h|r")
    ns.UI.SaveGuide("#guide Links\nstep Loot **ten** [item:86547]\n  item 86547 10")
    ns.UI.StartGuide("links")
    local w = ns.UI.GuideWindow()
    eq(w.StepText:GetText(), "Loot |cffffd100ten|r |cff1eff00|Hitem:86547|h[Skyshard]|h|r")
    eq(w.Done:GetText(), "Done when: 10 x |cff1eff00|Hitem:86547|h[Skyshard]|h|r")
    local shown
    GameTooltip = {
      SetOwner = function() end, Hide = function() end,
      SetHyperlink = function(_, link) shown = link end, Show = function() end,
    }
    w.Body:GetScript("OnHyperlinkEnter")(w.Body, "item:86547")
    eq(shown, "item:86547", "hovering a link shows the game's tooltip")
    w.Body:GetScript("OnHyperlinkEnter")(w.Body, "addon:MountTrail:mount:517")
    eq(mountTip, 517, "a mount link shows the mount's own tooltip")
    GameTooltip = nil
  end)

  it("macros: Copy shows the text, Make writes the account macro; authors and credits show", function()
    local ns = loadUI()
    local text = table.concat({
      "#guide Macro test",
      "#author Adventurer",
      "#author Someone",
      "#credit Thanks to the Wowhead comments",
      "step Target her",
      "  macro /tar Alani",
      "  macro /cleartarget [dead]",
      "step Done",
    }, "\n")
    local g = ns.Guide.Parse(text)
    eq(g.steps[1].macro, "/tar Alani\n/cleartarget [dead]")
    eq(g.authors, { "Adventurer", "Someone" })
    eq(g.credits, { "Thanks to the Wowhead comments" })
    eq(ns.Guide.Byline(g), "by Adventurer, Someone")
    local _, errors = ns.Guide.Parse("#guide T\nstep A\n  macro " .. string.rep("x", 256))
    eq(errors[1].msg, "The macro is longer than the game's 255 characters.")

    ns.UI.SaveGuide(text)
    ns.UI.StartGuide("macro-test")
    local w = ns.UI.GuideWindow()
    eq(w.Byline:GetText(), "by Adventurer, Someone")
    ok(w.CopyMacro:IsShown() and w.MakeMacro:IsShown(), "macro buttons on a step with a macro")
    local copied
    ns.UI.ShowGuideCopy = function(_, _, body) copied = body end
    w.CopyMacro:RunScript("OnClick", "LeftButton")
    eq(copied, "/tar Alani\n/cleartarget [dead]")
    local made
    ns.Game.MakeMacro = function(name, body) made = { name, body } return true end
    w.MakeMacro:RunScript("OnClick", "LeftButton")
    eq(made, { "MountTrail", "/tar Alani\n/cleartarget [dead]" })
    ns.Game.MakeMacro = function() return false, "combat" end
    local said
    ns.addon.Print = function(_, msg) said = msg end
    w.MakeMacro:RunScript("OnClick", "LeftButton")
    eq(said, "Macros can't be made in combat.")
    ns.UI.GuideGo(1)
    ok(not w.CopyMacro:IsShown(), "no macro: no buttons")
    ok(ns.UI.GuideCreditsText(g):find("Thanks to the Wowhead comments", 1, true))
  end)

  it("the menu's Change appearance opens the pop-outs' appearance items, Back returns", function()
    local ns = loadUI()
    ns.UI.StartGuide("builtin:thundering-ruby-cloud-serpent")
    local w = ns.UI.GuideWindow()
    local styleOf, backTo
    ns.UI.PopoutStyleMenu = function(win, back) styleOf, backTo = win, back return function() return {} end end
    local items
    ns.UI.ShowMenu = function(_, list) items = type(list) == "function" and list() or list end
    w.Strip:RunScript("OnClick", "RightButton")
    eq(items[2].text, "Change appearance")
    ok(type(items[2].submenu) == "function", "a submenu")
    eq(styleOf, w, "for the guide window")
    eq(backTo()[2].text, "Change appearance", "Back comes home to the guide menu")
  end)

  it("stretches to any size: the width re-wraps the text, sizes are saved per view", function()
    local ns = loadUI()
    ns.UI.StartGuide("builtin:thundering-ruby-cloud-serpent")
    local w = ns.UI.GuideWindow()
    w:SetSize(480, 400)
    w.sizing = true
    w.Grip:RunScript("OnMouseUp", "LeftButton")
    eq(ns.db.global.guideWindow.width, 480)
    eq(ns.db.global.guideWindow.compactH, 400)
    eq(w.StepText.width, 480 - 20, "the text takes the new width")
    ok(w:GetHeight() >= 400, "the step view keeps the height asked for")
    w.Grip:RunScript("OnClick", "RightButton")
    eq(ns.db.global.guideWindow.width, nil, "right-click: the default size")
    eq(w:GetWidth(), 300)
  end)
end)
