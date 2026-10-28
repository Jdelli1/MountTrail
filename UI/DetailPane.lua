local ADDON, ns = ...

-- Mount detail pane: the right side of every mount list (UI.List). Shows the
-- selected mount: Blizzard's mount preview (the Mount Journal's own
-- WrappedAndUnwrappedModelScene: drag to rotate, wheel to zoom, the rider
-- shown or not by the Mount Journal's "mountJournalShowPlayer" setting, its
-- checkbox here too), the name and icon, the client's flavor text, then the
-- tooltip's lines (UI.TooltipLines without the click hints: source, chance,
-- attempts, lockout, achievement) and "Where to find it": each NPC behind
-- the mount (Map.Spots: the vendor, a rare) by name, its zones and how
-- many spawn points - all in a scrolling area. No buttons: the list's rows
-- do it (UI.PaneRowClick: right-click plots or opens the achievement, Shift map, Ctrl preview).
--   local pane = UI.CreateDetailPane(parent)
--   pane:SetMount(mountID[, routeBoss])   -- nil: empty
--   pane:Refresh()                        -- same mount, fresh numbers
-- The model is reloaded only when the mount changes. Clients without the
-- model scene template show the large icon instead.
-- Its width is shared by every pane and saved (ns.db.global.window.
-- paneWidth, UI.PANE_MIN..UI.PANE_MAX): drag its left edge (UI.Splitter),
-- right-click there for the default.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

UI.DETAIL_WIDTH = 300 -- the default width

local panes = {} -- every pane built, so a new width reaches them all

-- The panes' width: the saved one, else UI.DETAIL_WIDTH.
function UI.PaneWidth()
  local global = ns.db and ns.db.global
  local window = global and type(global.window) == "table" and global.window or nil
  local clamp = UI.ClampWidth or function(w) return w end
  return clamp(window and window.paneWidth, UI.PANE_MIN or 220, UI.PANE_MAX or 460, UI.DETAIL_WIDTH)
end

-- Sets every pane's width (clamped); `save`: keep it.
function UI.SetPaneWidth(w, save)
  local clamp = UI.ClampWidth or function(v) return v end
  w = clamp(w, UI.PANE_MIN or 220, UI.PANE_MAX or 460, UI.DETAIL_WIDTH)
  if save and ns.db and ns.db.global then
    if type(ns.db.global.window) ~= "table" then ns.db.global.window = {} end
    ns.db.global.window.paneWidth = w
  end
  for _, pane in ipairs(panes) do pane:SetPaneWidth(w) end
  return w
end
local MODEL_HEIGHT = 230
local PAD = 10
local LINE_GAP = 3
local SCROLL_STEP = 30
local SHOW_PLAYER_CVAR = "mountJournalShowPlayer"

local function report(err)
  if ns.Game and ns.Game.ReportError then ns.Game.ReportError(err) end
end

local function mountData(mountID)
  local mounts = ns.Data and ns.Data.Mounts
  return mounts and mounts[mountID] or nil
end

-- The mount's spots for this character (Map.Spots, the other faction's
-- vendors left out) as the pane lists them -> { { name =, kind =, daily =,
-- maps = { { map =, name =, points = { { x, y } } } } } }, points grouped by
-- map in the spot's order.
function UI.DetailSpots(mountID)
  local map = ns.Map
  if not (map and map.Spots) then return {} end
  local faction = ns.Game.Faction and ns.Game.Faction() or nil
  local out = {}
  for _, spot in ipairs(map.Spots(mountID, faction)) do
    local maps, byMap = {}, {}
    local pts = spot.pts
    for i = 1, #pts - 2, 3 do
      local m = pts[i]
      local group = byMap[m]
      if not group then
        group = { map = m, name = ns.Game.MapName and ns.Game.MapName(m) or nil, points = {} }
        byMap[m] = group
        maps[#maps + 1] = group
      end
      group.points[#group.points + 1] = { pts[i + 1], pts[i + 2] }
    end
    out[#out + 1] = { name = spot.name, kind = spot.kind, daily = spot.daily, maps = maps }
  end
  return out
end

-- Pure: the pane's text for a mount -> { name =, flavor =, lines = UI.TooltipLines
-- without hints, achievement = achievementID or nil, location = bool, spots =
-- UI.DetailSpots, notes = ATT's description (Notes.Description) or nil }.
function UI.DetailContent(mountID, routeBoss)
  local m = mountData(mountID) or {}
  local name = ns.Game.MountInfo and ns.Game.MountInfo(mountID) or nil
  local _, achievementID = UI.AchievementLines(mountID)
  return {
    name = name or m.name or tostring(mountID),
    flavor = UI.TooltipFlavor(mountID),
    lines = UI.TooltipLines(mountID, routeBoss, { hints = false }),
    achievement = achievementID,
    location = UI.HasLocation(mountID, routeBoss) and true or false,
    spots = UI.DetailSpots(mountID),
    notes = ns.Notes and ns.Notes.Description(mountID) or nil,
  }
end

-- Blizzard's mount preview (MountJournal_UpdateMountDisplay) in `scene` for
-- `mountID`. -> true when a model was set.
function UI.ShowMountModel(scene, mountID)
  local journal = C_MountJournal
  if not (scene and journal and type(journal.GetMountInfoExtraByID) == "function") then return false end
  local good, err = pcall(function()
    local displayID, _, _, isSelfMount, _, sceneID, animID, kitID, noRider = journal.GetMountInfoExtraByID(mountID)
    if not displayID and type(journal.GetMountAllCreatureDisplayInfoByID) == "function" then
      local all = journal.GetMountAllCreatureDisplayInfoByID(mountID)
      displayID = type(all) == "table" and all[1] and all[1].creatureDisplayID or nil
    end
    if not (displayID and sceneID) then error("no model for mount " .. tostring(mountID), 0) end
    scene:TransitionToModelSceneID(sceneID, CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
    -- No "new mount" present box: the mount actor at full alpha, the
    -- wrapped one hidden (WrappedAndUnwrappedModelSceneMixin).
    if scene.PrepareForFanfare then scene:PrepareForFanfare(false) end
    local actor = scene:GetActorByTag("unwrapped")
    if not actor then error("no mount actor in scene " .. tostring(sceneID), 0) end
    if actor.SetOnModelLoadedCallback then
      actor:Hide()
      actor:SetOnModelLoadedCallback(function() actor:Show() end)
    end
    actor:SetModelByCreatureDisplayID(displayID, true)
    local blend = Enum and Enum.ModelBlendOperation
    if isSelfMount then
      if blend and actor.SetAnimationBlendOperation then actor:SetAnimationBlendOperation(blend.None) end
      actor:SetAnimation(618) -- MountSelfIdle
    else
      if blend and actor.SetAnimationBlendOperation then actor:SetAnimationBlendOperation(blend.Anim) end
      actor:SetAnimation(0)
    end
    local showPlayer = type(GetCVarBool) == "function" and GetCVarBool(SHOW_PLAYER_CVAR)
    if not showPlayer then noRider = true end
    local native = PlayerUtil and PlayerUtil.ShouldUseNativeFormInModelScene
      and PlayerUtil.ShouldUseNativeFormInModelScene() or false
    if scene.AttachPlayerToMount then
      scene:AttachPlayerToMount(actor, animID, isSelfMount, noRider, kitID, native)
    end
  end)
  if not good then
    report(err)
    return false
  end
  return true
end

-- Lines in the scrolling info area: font strings reused between mounts.
local function lineString(pane, i)
  local fs = pane.lineStrings[i]
  if not fs then
    fs = pane.Info:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlightSmall"))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    pane.lineStrings[i] = fs
    local right = pane.Info:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlightSmall"))
    right:SetJustifyH("RIGHT")
    pane.rightStrings[i] = right
  end
  return fs, pane.rightStrings[i]
end

local function layoutInfo(pane, content)
  local width = (pane.paneWidth or UI.DETAIL_WIDTH) - 2 * PAD - 12
  local y = 0
  local n = 0
  local function place(text, r, g, b, rightText, rr, rg, rb)
    n = n + 1
    local fs, right = lineString(pane, n)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", pane.Info, "TOPLEFT", 0, -y)
    fs:SetWidth(width)
    fs:SetText(text)
    fs:SetTextColor(r or 1, g or 1, b or 1)
    fs:Show()
    if rightText then
      right:ClearAllPoints()
      right:SetPoint("TOPRIGHT", pane.Info, "TOPLEFT", width, -y)
      right:SetText(rightText)
      right:SetTextColor(rr or 1, rg or 1, rb or 1)
      right:Show()
    else
      right:Hide()
    end
    local h = fs.GetStringHeight and fs:GetStringHeight() or 12
    y = y + math.max(h or 12, 12) + LINE_GAP
  end
  if content.flavor then
    place(content.flavor, 0.8, 0.8, 0.8)
    y = y + 4
  end
  for _, l in ipairs(content.lines) do
    if l.double then
      place(l.left, l.r, l.g, l.b, l.right, l.rr, l.rg, l.rb)
    else
      place(l.left, l.r, l.g, l.b)
    end
  end
  -- How to get it, in words (AllTheThings, when loaded).
  if content.notes then
    y = y + 6
    place(L["How to get it"], 1, 0.82, 0)
    place(content.notes, 0.9, 0.9, 0.9)
  end
  -- Where to find it: each NPC, its zones and how many spawn points (a
  -- right-click on the row plots them all).
  if content.spots and #content.spots > 0 then
    y = y + 6
    place(L["Where to find it"], 1, 0.82, 0)
    for _, spot in ipairs(content.spots) do
      local label = spot.name or (spot.kind == "vendor" and L["Vendor"]) or L["Spawn points"]
      if spot.kind == "vendor" and spot.name then label = label .. "  |cff9d9d9d" .. L["vendor"] .. "|r" end
      if spot.daily then label = label .. "  |cff9d9d9d" .. L["daily"] .. "|r" end
      local where, count = {}, 0
      for _, group in ipairs(spot.maps) do
        where[#where + 1] = group.name or tostring(group.map)
        count = count + #group.points
      end
      local line = table.concat(where, ", ")
      if count > 1 then line = line .. " \194\183 " .. string.format(L["%d spawn points"], count) end
      place(label, 1, 1, 1, line, 0.7, 0.7, 0.7)
    end
  end
  for i = n + 1, #pane.lineStrings do
    pane.lineStrings[i]:Hide()
    pane.rightStrings[i]:Hide()
  end
  pane.Info:SetHeight(math.max(y, 1))
  pane.infoHeight = y
  pane.Scroll:SetVerticalScroll(0)
end

local function paint(pane)
  local id = pane.mountID
  local has = id ~= nil
  pane.Name:SetShown(has)
  pane.Icon:SetShown(has)
  pane.Info:SetShown(has)
  pane.Empty:SetShown(not has)
  pane.AddList:SetShown(has)
  pane.Wowhead:SetShown(has)
  -- "+ List" while the mount is on none of your lists, else "Lists (n)".
  local store = has and UI.ListsDB and UI.ListsDB()
  local on = 0
  for _, l in ipairs(store and ns.Lists.Sorted(store) or {}) do
    if ns.Lists.Has(store, l.id, id) then on = on + 1 end
  end
  UI.FlatButtonSetText(pane.AddList, on > 0 and string.format(L["Lists (%d)"], on) or L["+ List"])
  local guides = has and UI.GuidesForMount and UI.GuidesForMount(id) or {}
  if #guides > 0 then
    UI.FlatButtonSetText(pane.Guide, L["Guide"])
    pane.Guide:Show()
  else
    pane.Guide:SetWidth(1)
    pane.Guide:Hide()
  end
  if not has then return end
  local content = UI.DetailContent(id, pane.routeBoss)
  pane.content = content
  pane.Name:SetText(content.name)
  pane.Icon:SetTexture(UI.MountIcon(id))
  pane.Owned:SetShown(ns.Game.IsOwned and ns.Game.IsOwned(id) and true or false)
  layoutInfo(pane, content)
end

local function build(parent)
  local pane = CreateFrame("Frame", nil, parent)
  pane.paneWidth = UI.PaneWidth()
  pane:SetWidth(pane.paneWidth)
  pane.lineStrings, pane.rightStrings = {}, {}

  local fill = pane:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(pane)
  fill:SetColorTexture(0, 0, 0, 0.25)
  local edge = pane:CreateTexture(nil, "BORDER")
  edge:SetWidth(1)
  edge:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
  edge:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 0)
  edge:SetColorTexture(1, 1, 1, 0.1)

  -- Model: Blizzard's mount preview when the client has the template.
  local modelArea = CreateFrame("Frame", nil, pane)
  modelArea:SetPoint("TOPLEFT", pane, "TOPLEFT", 1, 0)
  modelArea:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 0)
  modelArea:SetHeight(MODEL_HEIGHT)
  pane.ModelArea = modelArea
  local backdrop = modelArea:CreateTexture(nil, "BACKGROUND")
  backdrop:SetAllPoints(modelArea)
  backdrop:SetColorTexture(0, 0, 0, 0.35)

  local sceneTemplate = UI.Template("WrappedAndUnwrappedModelScene", nil)
  if sceneTemplate then
    local scene = CreateFrame("ModelScene", nil, modelArea, sceneTemplate)
    scene:SetAllPoints(modelArea)
    pane.Scene = scene
    if UI.Template("ModelSceneControlFrameTemplate", nil) then
      local controls = CreateFrame("Frame", nil, scene, "ModelSceneControlFrameTemplate")
      controls:SetPoint("BOTTOM", scene, "BOTTOM", 0, 8)
      if controls.SetFrameLevel then controls:SetFrameLevel(scene:GetFrameLevel() + 10) end
      pane.Controls = controls
      scene:HookScript("OnEnter", function() controls:Show() end)
      scene:HookScript("OnLeave", function()
        if not (controls.IsMouseOver and controls:IsMouseOver()) then controls:Hide() end
      end)
    end
    local rider = CreateFrame("CheckButton", nil, modelArea, "UICheckButtonTemplate")
    rider:SetSize(22, 22)
    rider:SetPoint("BOTTOMRIGHT", modelArea, "BOTTOMRIGHT", -4, 4)
    if rider.SetFrameLevel then rider:SetFrameLevel(scene:GetFrameLevel() + 10) end
    local riderText = rider:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalSmall"))
    riderText:SetPoint("RIGHT", rider, "LEFT", 0, 0)
    riderText:SetText(L["Rider"])
    rider:SetScript("OnShow", function(self)
      self:SetChecked(type(GetCVarBool) == "function" and GetCVarBool(SHOW_PLAYER_CVAR) and true or false)
    end)
    rider:SetScript("OnClick", function(self)
      if type(SetCVar) == "function" then SetCVar(SHOW_PLAYER_CVAR, self:GetChecked() and 1 or 0) end
      if pane.mountID then UI.ShowMountModel(scene, pane.mountID) end
    end)
    pane.Rider = rider
  end
  local bigIcon = modelArea:CreateTexture(nil, "ARTWORK")
  bigIcon:SetSize(96, 96)
  bigIcon:SetPoint("CENTER", modelArea, "CENTER", 0, 0)
  bigIcon:Hide()
  pane.BigIcon = bigIcon

  -- Header: icon, name, a check when owned.
  local icon = pane:CreateTexture(nil, "ARTWORK")
  icon:SetSize(32, 32)
  icon:SetPoint("TOPLEFT", modelArea, "BOTTOMLEFT", PAD, -8)
  UI.StyleIcon(pane, icon)
  pane.Icon = icon
  -- "+ List": add the mount to a custom list (a flat menu of the lists,
  -- each toggled; "New list..." asks for a name).
  local addList = UI.FlatButton(pane, L["+ List"], "gold", 18)
  addList:SetPoint("TOPRIGHT", modelArea, "BOTTOMRIGHT", -PAD, -15)
  addList:SetScript("OnClick", function(self)
    if pane.mountID then UI.ShowListMenu(self, pane.mountID) end
  end)
  addList:SetScript("OnEnter", function(self)
    UI.ShowHint(self, L["Your lists"], L["Tick a list to add this mount to it, untick to remove it."])
  end)
  addList:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  pane.AddList = addList
  -- "Wowhead": the mount's page (guides, comments) in a box to copy.
  local wowhead = UI.FlatButton(pane, L["Wowhead"], "plain", 18)
  wowhead:SetPoint("RIGHT", addList, "LEFT", -4, 0)
  wowhead:SetScript("OnClick", function()
    local url = pane.mountID and ns.Notes and ns.Notes.WowheadURL(pane.mountID)
    if url then UI.ShowCopyText(L["Wowhead"], url, L["Ctrl+C to copy, then paste it into your browser"]) end
  end)
  wowhead:SetScript("OnEnter", function(self)
    UI.ShowHint(self, L["Wowhead"], L["The mount's Wowhead page: guides and comments (a link to copy)"])
  end)
  wowhead:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  pane.Wowhead = wowhead
  -- "Guide": follow a guide written for this mount (UI/Guides.lua); only
  -- when one exists (narrowed to nothing otherwise, so the name keeps room).
  local guide = UI.FlatButton(pane, L["Guide"], "gold", 18)
  guide:SetPoint("RIGHT", wowhead, "LEFT", -4, 0)
  guide:SetScript("OnClick", function(self)
    local guides = pane.mountID and UI.GuidesForMount and UI.GuidesForMount(pane.mountID) or {}
    if #guides == 1 then
      UI.StartGuide(guides[1].id)
    elseif #guides > 1 then
      local items = { { title = L["Guides"] } }
      for _, g in ipairs(guides) do
        items[#items + 1] = { text = g.title, onClick = function() UI.StartGuide(g.id) end }
      end
      UI.ShowMenu(self, items, "cursor")
    end
  end)
  guide:SetScript("OnEnter", function(self) UI.ShowHint(self, L["Guide"], L["Follow a step-by-step guide for this mount."]) end)
  guide:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  pane.Guide = guide

  local name = pane:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalLarge"))
  name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
  name:SetPoint("RIGHT", guide, "LEFT", -22, 0)
  name:SetJustifyH("LEFT")
  name:SetWordWrap(true)
  if name.SetMaxLines then name:SetMaxLines(2) end
  pane.Name = name
  local owned = pane:CreateTexture(nil, "OVERLAY")
  owned:SetSize(16, 16)
  owned:SetPoint("LEFT", name, "RIGHT", 2, 0)
  if UI.AtlasExists("activities-icon-checkmark") then
    owned:SetAtlas("activities-icon-checkmark")
  else
    owned:SetTexture("Interface\\Scenarios\\ScenarioIcon-Check")
  end
  owned:Hide()
  pane.Owned = owned

  -- Scrolling info: flavor text and the tooltip's lines.
  local scroll = CreateFrame("ScrollFrame", nil, pane)
  scroll:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
  scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -PAD, 8)
  if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
  local info = CreateFrame("Frame", nil, scroll)
  info:SetSize(pane.paneWidth - 2 * PAD, 1)
  scroll:SetScrollChild(info)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, (pane.infoHeight or 0) - (self:GetHeight() or 0))
    local v = math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - delta * SCROLL_STEP))
    self:SetVerticalScroll(v)
  end)
  pane.Scroll, pane.Info = scroll, info

  local empty = pane:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisable"))
  empty:SetPoint("TOPLEFT", modelArea, "BOTTOMLEFT", PAD, -20)
  empty:SetPoint("TOPRIGHT", modelArea, "BOTTOMRIGHT", -PAD, -20)
  empty:SetText(L["Click a mount to see it here"])
  pane.Empty = empty

  function pane:SetMount(mountID, routeBoss)
    local changed = mountID ~= self.mountID
    self.mountID, self.routeBoss = mountID, routeBoss
    if changed then
      local shown = mountID ~= nil and self.Scene ~= nil and UI.ShowMountModel(self.Scene, mountID)
      if self.Scene then self.Scene:SetShown(mountID ~= nil and shown) end
      self.BigIcon:SetShown(mountID ~= nil and not shown)
      if mountID then self.BigIcon:SetTexture(UI.MountIcon(mountID)) end
    end
    paint(self)
  end

  function pane:Refresh()
    paint(self)
  end

  -- A new width (UI.SetPaneWidth): the pane, its buttons and its lines.
  function pane:SetPaneWidth(w)
    self.paneWidth = w
    self:SetWidth(w)
    self.Info:SetWidth(w - 2 * PAD)
    paint(self)
  end

  -- Its left edge: drag to share the width with the list.
  if UI.Splitter then
    local split = UI.Splitter(pane, function(x)
      return (pane:GetRight() or 0) - x
    end, function(w) UI.SetPaneWidth(w) end, function(w) UI.SetPaneWidth(w, true) end, function()
      UI.SetPaneWidth(UI.DETAIL_WIDTH, true)
    end)
    split:SetPoint("TOPRIGHT", pane, "TOPLEFT", 3, 0)
    split:SetPoint("BOTTOMRIGHT", pane, "BOTTOMLEFT", 3, 0)
    pane.Splitter = split
  end

  panes[#panes + 1] = pane
  pane:SetMount(nil)
  return pane
end

UI.CreateDetailPane = build

-- The "+ List" menu for a mount: each custom list ticked when the mount is
-- on it (a click toggles, the menu stays open), then "New list...".
function UI.ShowListMenu(owner, mountID)
  local store = UI.ListsDB and UI.ListsDB()
  if not store then return end
  UI.ShowMenu(owner, function()
    local items = { { title = L["Your lists"] } }
    -- On one of your list's pages: removing it from that list comes first.
    local page = UI.CurrentListPage and UI.CurrentListPage()
    local here = page and page.kind == "list" and ns.Lists.Get(store, page.list)
    if here and ns.Lists.Has(store, page.list, mountID) then
      items[#items + 1] = { text = string.format(L["Remove from %s"], here.name), onClick = function()
        ns.Lists.Remove(store, page.list, mountID)
        ns.Refresh()
      end }
      items[#items + 1] = { separator = true }
    end
    for _, l in ipairs(ns.Lists.Sorted(store)) do
      items[#items + 1] = {
        text = l.name, checked = ns.Lists.Has(store, l.id, mountID), keepOpen = true,
        onClick = function()
          ns.Lists.Toggle(store, l.id, mountID)
          ns.Refresh()
        end,
      }
    end
    if #items > 1 then items[#items + 1] = { separator = true } end
    items[#items + 1] = { text = L["New list..."], onClick = function()
      if UI.NewListPrompt then UI.NewListPrompt(mountID) end
    end }
    return items
  end)
end
