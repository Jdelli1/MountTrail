local ADDON, ns = ...

-- The mount list's row and header frames, split out of UI/List.lua (loads
-- right after it): the card look every main-window list shares (a header
-- on a card's top, two-line rows with the mount's icon and a badge on the
-- card; UI.InitListHeader, UI.InitMountRow), the header colours
-- (UI.HeaderColor), the location pins (UI.CreatePin, UI.ShowPin) and the
-- world map tab's icon rows (row.withIcon).

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local HEADER_HEIGHT = 30 -- a card's top, 6 px of gap above it
local CARD_GAP = 6
local SUB_HEADER_HEIGHT = 20
local INDICATOR_SIZE = 14
local SUB_INDENT = 22 -- sub-header indicator inset (section headers: 6); icons of rows under it
local DEPTH_STEP = 16 -- each deeper header level (the checklist's depth 3) moves in this much more
local ROW_ICON_LEFT = 9 -- icon inset of other mount rows (past the card's 3 px edge)
local ROW_HEIGHT = 38 -- two lines: the name over its source, beside the icon
local CARD_ICON = 30 -- the boxed icon of a card row
local NO_RARITY = { 0.35, 0.32, 0.26 }
local PIN_SIZE, PIN_RIGHT = 16, 8 -- the location pin on a row's right end
-- Map item icons are cropped past their baked-in edge (the pin).
local ICON_CROP = 0.08
-- The world map tab's rows (row.withIcon): the mount's icon at a bag slot's
-- size, the name across the row, no expansion tag and no source (the map
-- shows the zone already).
local ICON_SIZE = 37
local ICON_ROW_HEIGHT = 41
-- Rounded icon mask of the current action bars, when the client has it.
local ICON_MASK = "UI-HUD-ActionBar-IconFrame-Mask"

-- Header colours, the same in every list, as a pop-out's group headers: a
-- header of an expansion (depth 1 or 2 with `exp`: the Lockouts'
-- expansions, a list by expansion) in that expansion's colour; any other
-- top-level header (depth 1) in the main window's header colour (its
-- appearance, UI/Style.lua), else gold; every other group (instances,
-- zones, the Lockouts' categories) light grey.
local GOLD = { 1, 0.82, 0 }
local LIGHT = { 0.85, 0.85, 0.85 }
function UI.HeaderColor(data)
  local depth = data and data.depth or 1
  if depth <= 2 and data.exp and UI.EXPANSION_COLORS and UI.EXPANSION_COLORS[data.exp] then
    return UI.EXPANSION_COLORS[data.exp]
  end
  if depth >= 2 then return LIGHT end
  local style = UI.frame and UI.PopoutStyleOf and UI.PopoutStyleOf(UI.frame)
  return style and style.header or GOLD
end

-- Section header (depth 1) and sub-header (depth 2, indented;
-- depth 3 -- the checklist's categories -- looks the same, one DEPTH_STEP
-- further in), in the pop-outs' look: "- Name (count)" in the header's
-- colour (UI.HeaderColor) over a thin rule of it. A plain Frame (not a
-- Button) so the ScrollBox pools it apart from the mount rows; left-click
-- (OnMouseUp) calls frame.onToggle(key), a right-click
-- frame.onRightClick(data, frame) when the caller set one, and hovering
-- shows frame.hint (UI.ShowHint, beside the cursor) when set.
local function initHeader(frame, data)
  if not frame.Label then
    frame:EnableMouse(true)
    -- A top-level header is a card's top: a fill, a 1 px border on top and
    -- right, and a 3 px edge in its colour, under a small gap.
    local fill = frame:CreateTexture(nil, "BACKGROUND")
    fill:SetColorTexture(1, 1, 1, 0.035)
    frame.CardFill = fill
    local edge = frame:CreateTexture(nil, "BORDER")
    edge:SetWidth(3)
    frame.CardEdge = edge
    local top = frame:CreateTexture(nil, "BORDER")
    top:SetHeight(1)
    frame.CardTop = top
    local right = frame:CreateTexture(nil, "BORDER")
    right:SetWidth(1)
    frame.CardRight = right
    local hover = frame:CreateTexture(nil, "BORDER")
    hover:SetAllPoints(frame)
    hover:SetColorTexture(1, 1, 1, 0.05)
    hover:Hide()
    frame.Hover = hover
    local rule = frame:CreateTexture(nil, "BORDER")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 1)
    frame.Rule = rule
    local glyph = frame:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormal"))
    glyph:SetWidth(INDICATOR_SIZE)
    glyph:SetJustifyH("LEFT")
    frame.Glyph = glyph
    -- The count on the header's right, as the design's card headers.
    local count = frame:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
    count:SetJustifyH("RIGHT")
    frame.Count = count
    local label = frame:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormal"))
    label:SetPoint("LEFT", glyph, "RIGHT", 0, 0)
    label:SetPoint("RIGHT", count, "LEFT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    frame.Label = label
    frame:SetScript("OnEnter", function(self)
      self.Hover:Show()
      local title, text = UI.HeaderHint(self.hint, self.onToggle ~= nil)
      if title and UI.ShowHint then UI.ShowHint(self, title, text, "cursor") end
    end)
    frame:SetScript("OnLeave", function(self)
      self.Hover:Hide()
      if UI.HideHint then UI.HideHint(self) end
    end)
    frame:SetScript("OnMouseUp", function(self, button)
      -- Only a release over the header counts (pressing, then dragging off
      -- it cancels, as with buttons).
      if type(self.IsMouseOver) == "function" and not self:IsMouseOver() then return end
      if button == "RightButton" and self.onRightClick and self.data then
        self.onRightClick(self.data, self)
        return
      end
      if button ~= "LeftButton" then return end
      -- Shift-click: every header of the list collapses (or, on a collapsed
      -- one, expands) at once.
      if UI.ShiftDown() and self.onToggleAll and self.data then
        self.onToggleAll(self.data, self)
        return
      end
      if not (self.key and self.onToggle) then return end
      self.onToggle(self.key)
    end)
  end
  local depth = data.depth or 1
  local sub = depth >= 2
  frame.key = data.key
  frame.data = data
  -- Recycled frames: the hover band follows the mouse, not the last use.
  frame.Hover:SetShown(type(frame.IsMouseOver) == "function" and frame:IsMouseOver() == true)
  local inset = sub and (SUB_INDENT + (depth - 2) * DEPTH_STEP) or ROW_ICON_LEFT
  local c = UI.HeaderColor(data)
  -- The card's top (top-level headers): its fill and borders start under the
  -- gap; the label sits in the middle of what is left.
  -- frame.flat (the world map tab's headers): no card.
  local flat = frame.flat == true
  local gap = (not sub and not flat) and CARD_GAP or 0
  local line = UI.THEME and UI.THEME.cardEdge or { 0.2, 0.16, 0.09 }
  for _, t in ipairs({ frame.CardFill, frame.CardEdge, frame.CardTop, frame.CardRight }) do
    t:ClearAllPoints()
    t:SetShown(not sub and not flat)
  end
  if flat then
    -- Nothing more: a plain header over its rule.
  elseif sub then
    -- A sub-header sits inside its card: its fill and edge continue.
    frame.CardFill:SetAllPoints(frame)
    frame.CardFill:Show()
  else
    frame.CardFill:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -gap)
    frame.CardFill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.CardEdge:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -gap)
    frame.CardEdge:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    frame.CardEdge:SetColorTexture(c[1], c[2], c[3], 0.9)
    frame.CardTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -gap)
    frame.CardTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -gap)
    frame.CardRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -gap)
    frame.CardRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    for _, t in ipairs({ frame.CardTop, frame.CardRight }) do t:SetColorTexture(line[1], line[2], line[3], 1) end
  end
  frame.Glyph:ClearAllPoints()
  frame.Glyph:SetPoint("LEFT", frame, "LEFT", inset, -gap / 2)
  frame.Rule:ClearAllPoints()
  frame.Rule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, 1)
  frame.Rule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  frame.Rule:SetColorTexture(c[1], c[2], c[3], depth >= 3 and 0.15 or 0.35)
  -- One size for every level (the small font read too small): the colour and
  -- the indent tell them apart.
  local font = UI.Font("GameFontNormal")
  frame.Glyph:SetFontObject(font)
  frame.Glyph:SetText(UI.HeaderGlyph(data.collapsed == true))
  frame.Glyph:SetTextColor(c[1], c[2], c[3])
  frame.Label:SetFontObject(font)
  frame.Label:SetTextColor(c[1], c[2], c[3])
  frame.Label:SetText(UI.HeaderText(data, true))
  frame.Count:ClearAllPoints()
  frame.Count:SetPoint("RIGHT", frame, "RIGHT", -10, -gap / 2)
  frame.Count:SetText(UI.HeaderCount(data) or "")
end

-- The section / sub-header row look, shared with the route checklist
-- (UI/ChecklistView.lua): a ScrollBox "Frame" initializer; set
-- frame.onToggle(key) for clicks.
UI.InitListHeader = initHeader

-- Paints a row's location icon for UI.LocationIcon's kind: the map pin
-- (UI.PinIcon) for "spot" (true counts as "spot"), the map item icon for
-- "zone".
function UI.ApplyPin(pin, kind)
  local atlas, texture = UI.PinIcon()
  if kind ~= "zone" and atlas then
    pin:SetAtlas(atlas)
    return
  end
  pin:SetTexture(texture)
  pin:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
end

-- Shows a row's location icon for `kind` (UI.LocationIcon: "spot" / "zone";
-- true counts as "spot"), or hides it for nil / false.
function UI.ShowPin(pin, kind)
  if kind then UI.ApplyPin(pin, kind) end
  pin:SetShown(kind and true or false)
end

-- A row's location icon: a small texture on `owner`, hidden until the row
-- has a location (UI.ShowPin).
function UI.CreatePin(owner)
  local pin = owner:CreateTexture(nil, "OVERLAY")
  pin:SetSize(PIN_SIZE, PIN_SIZE)
  UI.ApplyPin(pin, "spot")
  pin:Hide()
  return pin
end

-- Room a row leaves on its right for the pin (PIN_RIGHT + PIN_SIZE + a gap).
UI.PIN_RIGHT = PIN_RIGHT
UI.PIN_ROOM = PIN_RIGHT + PIN_SIZE + 8

local function setupRow(row)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  -- Modern list rows: no borders, a faint stripe on every other row and a
  -- soft hover highlight.
  local stripe = row:CreateTexture(nil, "BACKGROUND")
  stripe:SetAllPoints(row)
  stripe:SetColorTexture(1, 1, 1, 0.025)
  row.Stripe = stripe
  -- The card it sits on: a fill, a 3 px edge in its expansion's colour and
  -- a 1 px right border (the map tab's rows have none).
  local cardFill = row:CreateTexture(nil, "BACKGROUND", nil, -1)
  cardFill:SetAllPoints(row)
  cardFill:SetColorTexture(1, 1, 1, 0.035)
  row.CardFill = cardFill
  local cardEdge = row:CreateTexture(nil, "BORDER")
  cardEdge:SetWidth(3)
  cardEdge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  cardEdge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  row.CardEdge = cardEdge
  local cardRight = row:CreateTexture(nil, "BORDER")
  cardRight:SetWidth(1)
  cardRight:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
  cardRight:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  row.CardRight = cardRight
  -- The mount's icon, boxed in its rarity's colour.
  local box = CreateFrame("Frame", nil, row)
  box:SetSize(CARD_ICON, CARD_ICON)
  box.Edge = UI.FlatBorder(box, 1, 1, 1, 0.3)
  row.IconBox = box
  local cardIcon = box:CreateTexture(nil, "ARTWORK")
  cardIcon:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
  cardIcon:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
  cardIcon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
  row.CardIcon = cardIcon
  -- Owned, or the drop chance: a boxed badge left of the pin.
  row.Chip = UI.Badge(row)
  -- Owned (collected) mounts, listed with the Collected filter on: a light
  -- translucent green tint above the stripe.
  local owned = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  owned:SetAllPoints(row)
  owned:SetColorTexture(0.25, 0.85, 0.35, 0.14)
  owned:Hide()
  row.Owned = owned
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  highlight:SetColorTexture(1, 1, 1, 0.07)
  -- The row shown in the detail pane: a soft gold fill with a gold bar on
  -- its left edge.
  local selected = row:CreateTexture(nil, "BACKGROUND", nil, 2)
  selected:SetAllPoints(row)
  selected:SetColorTexture(1, 0.82, 0, 0.12)
  local bar = row:CreateTexture(nil, "ARTWORK")
  bar:SetWidth(2)
  bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  bar:SetColorTexture(1, 0.82, 0, 0.9)
  selected:Hide()
  bar:Hide()
  row.Selected = {
    SetShown = function(_, on) selected:SetShown(on); bar:SetShown(on) end,
    IsShown = function() return selected:IsShown() end,
  }

  row.Tag = UI.ExpansionBadge(row)

  -- Location pin on the right end (rows with a waypoint target only).
  local pin = UI.CreatePin(row)
  pin:SetPoint("RIGHT", row, "RIGHT", -PIN_RIGHT, 0)
  row.Pin = pin

  local name = row:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlight"))
  name:SetWordWrap(false)
  row.Name = name

  local source = row:CreateFontString(nil, "OVERLAY", UI.SourceFont())
  source:SetWordWrap(false)
  row.Source = source

  row:SetScript("OnEnter", function(self)
    if self.onSelect and self.mountID then
      -- The detail pane shows the mount: the hover just says what a click does.
      UI.ShowHint(self, UI.RowHintTitle(self), UI.PaneRowHint(self.mountID, self.routeBoss, self.eventMap), "cursor")
    elseif self.tooltip then
      self.tooltip(self)
    elseif self.mountID then
      -- A route / checklist row's boss decides the lockout line.
      UI.ShowMountTooltip(self, self.mountID, self.routeBoss)
    end
  end)
  row:SetScript("OnLeave", function(self)
    UI.HideMountTooltip()
    UI.HideHint(self)
  end)
  row:SetScript("OnClick", function(self, button)
    -- In a list with the detail pane any click selects the row, then
    -- UI.PaneRowClick (right-click plots, Shift map, Ctrl achievement). Otherwise: left-click waypoint (or the
    -- achievement), Shift+left-click world map, Ctrl+left-click preview,
    -- Shift+right-click achievement (UI.RowClickAction).
    if self.onSelect and self.mountID and (button == "LeftButton" or button == "RightButton") then
      self.onSelect(self.mountID, self)
      UI.PaneRowClick(self.mountID, self.routeBoss, self.eventMap, button)
      return
    end
    UI.HandleRowClick(self.mountID, button, self.routeBoss, self.eventMap)
  end)
end

-- A row tooltip that shows nothing (a list with the detail pane: the pane
-- shows what the tooltip would).
function UI.NoTooltip() end

-- A list name's colour when "Colour list names by rarity" is on (the main
-- window's own setting, apart from the pop-outs') and MountsRarity knows the
-- mount (ns.Owners), else nil.
function UI.ListRarityColor(mountID)
  local global = ns.db and ns.db.global
  local settings = global and global.settings
  local owners = ns.Owners
  if not (type(settings) == "table" and settings.rarityColorsMain == true and owners) then return nil end
  local pct = owners.Percent(mountID)
  return pct and owners.Color(pct) or nil
end

-- The row, a pop-out's: the mount's expansion tag at `left`, the name, and
-- the source line right-aligned in the row's right half (left of the pin),
-- all on one line (no icon: the detail pane shows the mount).
-- The mount's icon, made the first time a row shows one (row.withIcon),
-- cropped past its edge and rounded.
local function rowIcon(row)
  if row.Icon then return row.Icon end
  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
  if UI.AtlasExists(ICON_MASK) and row.CreateMaskTexture and icon.AddMaskTexture then
    local mask = row:CreateMaskTexture()
    mask:SetAtlas(ICON_MASK)
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
  end
  row.Icon = icon
  return icon
end

local function anchorRow(row, left)
  local tag, name, source = row.Tag, row.Name, row.Source
  tag:ClearAllPoints()
  if not row.withIcon then
    -- A card row: the boxed icon, the name over its source, the badge on the
    -- right before the pin.
    tag:Hide()
    local box = row.IconBox
    box:ClearAllPoints()
    box:SetPoint("LEFT", row, "LEFT", left, 0)
    name:ClearAllPoints()
    source:ClearAllPoints()
    row.Chip:ClearAllPoints()
    row.Chip:SetPoint("RIGHT", row, "RIGHT", -UI.PIN_ROOM, 0)
    local right = row.Chip:IsShown() and (UI.PIN_ROOM + row.Chip:GetWidth() + 6) or UI.PIN_ROOM
    name:SetPoint("BOTTOMLEFT", box, "RIGHT", 8, 1)
    name:SetPoint("BOTTOMRIGHT", row, "RIGHT", -right, 1)
    name:SetJustifyH("LEFT")
    source:SetPoint("TOPLEFT", box, "RIGHT", 8, -1)
    source:SetPoint("TOPRIGHT", row, "RIGHT", -right, -1)
    source:SetJustifyH("LEFT")
    return
  end
  if row.withIcon then
    local icon = rowIcon(row)
    icon:ClearAllPoints()
    icon:SetPoint("LEFT", row, "LEFT", left, 0)
    left = left + ICON_SIZE + 8
  end
  tag:SetPoint("LEFT", row, "LEFT", left, 0)
  name:ClearAllPoints()
  if tag:IsShown() then
    name:SetPoint("LEFT", tag, "RIGHT", 6, 0)
  else
    name:SetPoint("LEFT", row, "LEFT", left, 0)
  end
  name:SetJustifyH("LEFT")
  source:ClearAllPoints()
  if row.withIcon then
    -- No source: the name runs up to the pin.
    name:SetPoint("RIGHT", row, "RIGHT", -UI.PIN_ROOM, 0)
    return
  end
  name:SetPoint("RIGHT", row, "CENTER", 4, 0)
  source:SetPoint("LEFT", row, "CENTER", 12, 0)
  source:SetPoint("RIGHT", row, "RIGHT", -UI.PIN_ROOM, 0)
  source:SetJustifyH("RIGHT")
end

local function initRow(row, data)
  if not row.Name then setupRow(row) end
  row.mountID = data.id
  row.tooltip = data.tooltip
  row.onSelect = data.onSelect
  row.Selected:SetShown(data.selected == true)
  row.routeBoss = data.routeBoss
  row.eventMap = data.eventMap
  UI.SetExpansionBadge(row.Tag, data.m and data.m.exp)
  if row.withIcon then row.Tag:Hide() end
  row.Tag:EnableMouse(false) -- the row takes the clicks
  -- The card: its edge in the mount's expansion colour (gold without one).
  local card = not row.withIcon
  local exp = data.m and data.m.exp
  local ec = (exp and UI.EXPANSION_COLORS and UI.EXPANSION_COLORS[exp]) or GOLD
  local line = UI.THEME and UI.THEME.cardEdge or { 0.2, 0.16, 0.09 }
  row.CardFill:SetShown(card)
  row.CardEdge:SetShown(card)
  row.CardRight:SetShown(card)
  row.IconBox:SetShown(card)
  row.CardEdge:SetColorTexture(ec[1], ec[2], ec[3], 0.9)
  row.CardRight:SetColorTexture(line[1], line[2], line[3], 1)
  if card then
    local _, icon = ns.Game.MountInfo(data.id)
    row.CardIcon:SetTexture(icon or 134400) -- a question mark when unknown
    local rc = (not data.owned and UI.ListRarityColor(data.id)) or NO_RARITY
    row.IconBox.Edge:SetColor(rc[1], rc[2], rc[3], 1)
    -- The badge: Owned; else your tries (a mount you are farming); else
    -- its drop chance.
    local chance = data.m and tonumber(data.m.chance)
    local tries = (not data.owned and data.m and UI.IsTracked and UI.MountAttempts and UI.IsTracked(data.id, data.m))
      and UI.MountAttempts(data.id, data.m) or nil
    tries = type(tries) == "table" and tonumber(tries.total) or 0
    if data.owned then
      UI.SetBadge(row.Chip, UI.MARK_DONE .. " " .. L["Owned"], "green")
    elseif tries > 0 then
      UI.SetBadge(row.Chip, string.format(tries == 1 and L["%d try"] or L["%d tries"], tries), "grey")
    else
      UI.SetBadge(row.Chip, chance and chance > 1 and string.format(L["1 in %d"], chance) or nil, "grey")
    end
  else
    row.Chip:Hide()
  end
  -- Under a sub-header the icon lines up with the sub-header's glyph.
  anchorRow(row, data.left or (data.depth == 2 and SUB_INDENT or ROW_ICON_LEFT))
  if row.Icon then
    row.Icon:SetShown(row.withIcon == true)
    if row.withIcon then row.Icon:SetTexture(select(2, ns.Game.MountInfo(data.id))) end
  end
  local name = data.name or ns.Game.MountInfo(data.id) or data.m.name or tostring(data.id)
  -- Colour-blind marks: a tick on owned rows (the green says it otherwise).
  if data.owned and UI.ColorblindMarks and UI.ColorblindMarks() then name = UI.MARK_DONE .. " " .. name end
  if data.suffix then name = name .. "  " .. data.suffix end
  row.Name:SetText(name)
  row.Source:SetText(UI.RowSourceText(data))
  row.Source:SetShown(not row.withIcon)
  row.Stripe:SetShown(data.alt == true)
  UI.ShowPin(row.Pin, data.pin)
  -- Owned (collected) mounts: green tint and a light green name; others
  -- white (in their rarity's colour with the pop-outs' option on).
  -- Everything reset for a recycled frame.
  row.Owned:SetShown(data.owned == true)
  if data.owned then
    row.Name:SetFontObject(UI.OwnedFont())
  else
    row.Name:SetFontObject(UI.Font("GameFontHighlight"))
    local c = UI.ListRarityColor(data.id)
    if c then
      row.Name:SetTextColor(c[1], c[2], c[3])
      -- The colour's meaning as text too (colour-blind marks).
      if UI.RarityTag then row.Name:SetText(row.Name:GetText() .. UI.RarityTag(data.id)) end
    end
  end
end

-- The mount row, every list's (the lists, Lockouts, the zone panel, the map
-- tab), a pop-out's: a ScrollBox element initializer for "Button" frames.
-- data: { id=, m=, owned=, depth= (2: indented), left= (the icon's inset,
-- overriding depth), desc= (UI.RowDescription), tag=, alt= (striped), pin=
-- (UI.HasLocation), name= (overrides the mount's name), suffix= (text after
-- the name: the Lockouts' light blue status), tooltip= (function(row)
-- shown on hover instead of the mount tooltip), onSelect=
-- (function(mountID): a plain left-click selects instead of the waypoint;
-- the detail pane's lists), selected= (the selected row's look), routeBoss=
-- (the row's route boss, passed to the click: UI.HandleRowClick, and to the
-- hover: UI.ShowMountTooltip's lockout line) }. Rows are
-- UI.MOUNT_ROW_HEIGHT tall (UI.RowHeight for the text size). A row with
-- row.withIcon set (the world map tab's) shows the mount's icon first and no
-- source, UI.ICON_ROW_HEIGHT tall.
UI.InitMountRow = initRow
UI.MOUNT_ROW_HEIGHT = ROW_HEIGHT
-- A top-level header's height in a card list (its gap included).
UI.CARD_HEADER_HEIGHT = HEADER_HEIGHT
UI.SUB_HEADER_HEIGHT = SUB_HEADER_HEIGHT
UI.ICON_ROW_HEIGHT = ICON_ROW_HEIGHT
