-- Minimal stand-ins for WoW globals so addon logic can run under plain Lua 5.1.
-- Later tasks extend this file as they need more of the API.

wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = tinsert or table.insert
tremove = tremove or table.remove
strlower = strlower or string.lower
strupper = strupper or string.upper
strfind = strfind or string.find
strsub = strsub or string.sub
strlen = strlen or string.len
strrep = strrep or string.rep
format = format or string.format
gsub = gsub or string.gsub
date = date or os.date
time = time or os.time

strtrim = strtrim or function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

strsplit = strsplit or function(delim, s)
  local out, pos = {}, 1
  while true do
    local a, b = string.find(s, delim, pos, true)
    if not a then out[#out + 1] = string.sub(s, pos) break end
    out[#out + 1] = string.sub(s, pos, a - 1)
    pos = b + 1
  end
  return unpack(out)
end

GetTime = GetTime or function() return os.clock() end

-- Fake Ace3 for loading Core/Init.lua (Task 10). LibStub(name) returns a
-- stand-in library; the fake addon object records what it registers so specs
-- can fire events and slash commands by hand.
local function deepcopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepcopy(x) end
  return out
end

local fakeLibs = {}

fakeLibs["AceAddon-3.0"] = {
  NewAddon = function(self, name, ...)
    local addon = { name = name, mixins = { ... }, events = {}, commands = {}, printed = {} }
    function addon:RegisterEvent(event, method) self.events[event] = method or event end
    function addon:UnregisterEvent(event) self.events[event] = nil end
    function addon:RegisterChatCommand(cmd, method) self.commands[cmd] = method end
    function addon:Print(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
      self.printed[#self.printed + 1] = table.concat(parts, " ")
    end
    return addon
  end,
}

fakeLibs["AceDB-3.0"] = {
  New = function(self, svName, defaults)
    defaults = defaults or {}
    return { sv = svName, global = deepcopy(defaults.global) or {}, char = deepcopy(defaults.char) or {} }
  end,
}

LibStub = LibStub or function(name, silent)
  local lib = fakeLibs[name]
  if not lib and not silent then error("stub LibStub: no library " .. tostring(name), 2) end
  return lib
end

-- Calls the handler the fake addon registered for `event` (method name or function).
function fire_event(addon, event, ...)
  local handler = addon.events[event]
  if not handler then error("event not registered: " .. tostring(event), 2) end
  if type(handler) == "function" then return handler(event, ...) end
  return addon[handler](addon, event, ...)
end

-- Lua files listed in MountTrail.toc, in order, minus XML and UI/ files.
function toc_lua_files()
  local fh = assert(io.open(ROOT .. "/MountTrail.toc", "r"))
  local files = {}
  for line in fh:lines() do
    line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and not line:find("^#") and line:find("%.lua$") then
      local path = line:gsub("\\", "/")
      if not path:find("^UI/") then files[#files + 1] = path end
    end
  end
  fh:close()
  return files
end

-- Calls the handler the fake addon registered for slash command `cmd`.
function run_slash(addon, cmd, input)
  local handler = addon.commands[cmd]
  if not handler then error("slash command not registered: " .. tostring(cmd), 2) end
  if type(handler) == "function" then return handler(input) end
  return addon[handler](addon, input)
end

-- Fake widgets for loading UI/ files (Task 12). Only what UI/Frame.lua calls;
-- a missing method errors, as it would in game. Templates add nothing except
-- the PortraitFrameTemplate / PortraitFrameFlatTemplate methods Frame.lua uses
-- (SetTitle, SetPortraitToAsset), which Retail's PortraitFrameMixin provides.
-- Simplification: OnShow/OnHide fire only on the frame whose Show/Hide was
-- called, not on its children.
local Region = {}
Region.__index = Region

local function newRegion(kind, name, parent)
  local r = setmetatable({ kind = kind, name = name, parent = parent, shown = true,
    points = {}, scripts = {}, events = {}, children = {} }, Region)
  if name then _G[name] = r end
  if parent and parent.children then parent.children[#parent.children + 1] = r end
  return r
end

function Region:GetName() return self.name end
function Region:GetParent() return self.parent end
function Region:SetSize(w, h) self.width, self.height = w, h end
function Region:SetWidth(w) self.width = w end
function Region:SetHeight(h) self.height = h end
function Region:GetSize() return self.width, self.height end
function Region:GetWidth() return self.width or 0 end
function Region:GetHeight() return self.height or 0 end
function Region:ClearAllPoints() self.points = {} end
function Region:SetAllPoints(rel) self.points = { { "ALL", rel or self.parent } } end
function Region:SetPoint(point, rel, relPoint, x, y)
  if type(rel) == "number" or rel == nil then
    x, y, rel, relPoint = rel, relPoint, nil, nil
  end
  for i = #self.points, 1, -1 do
    if self.points[i][1] == point then table.remove(self.points, i) end
  end
  self.points[#self.points + 1] = { point, rel or self.parent, relPoint or point, x or 0, y or 0 }
end
function Region:GetNumPoints() return #self.points end
function Region:GetPoint(i)
  local p = self.points[i or 1]
  if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Region:IsShown() return self.shown end
function Region:IsVisible()
  if not self.shown then return false end
  return self.parent == nil or self.parent:IsVisible()
end
function Region:Show()
  if self.shown then return end
  self.shown = true
  if self:IsVisible() and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Region:Hide()
  if not self.shown then return end
  local was = self:IsVisible()
  self.shown = false
  if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Region:SetShown(show) if show then self:Show() else self:Hide() end end
function Region:SetText(text) self.text = text end
function Region:GetText() return self.text end
function Region:SetTexture(tex) self.texture = tex end
function Region:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Region:SetAtlas(atlas) self.atlas = atlas end
-- Font strings: justification, wrapping and font objects are recorded.
function Region:SetJustifyH(j) self.justifyH = j end
function Region:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
function Region:SetAlpha(a) self.alpha = a end
function Region:GetAlpha() return self.alpha or 1 end
function Region:SetWordWrap(on) self.wordWrap = on end
function Region:SetFontObject(font) self.font = font end

local Frame = setmetatable({}, { __index = Region })
Frame.__index = Frame

function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
  local old = self.scripts[name]
  self.scripts[name] = old and function(...) old(...); fn(...) end or fn
end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:EnableMouse(on) self.mouse = on end
function Frame:SetMovable(on) self.movable = on end
-- ScrollFrame: the scroll child and the vertical offset are recorded.
function Frame:SetScrollChild(child) self.scrollChild = child end
function Frame:SetVerticalScroll(v) self.vscroll = v end
function Frame:GetVerticalScroll() return self.vscroll or 0 end
function Frame:IsMovable() return self.movable end
function Frame:SetClampedToScreen(on) self.clamped = on end
function Frame:SetToplevel(on) self.toplevel = on end
function Frame:SetFrameStrata(strata) self.strata = strata end
function Frame:RegisterForDrag(...) self.dragButtons = { ... } end
function Frame:StartMoving()
  if not self.movable then error("Frame:StartMoving: frame is not movable", 2) end
  self.moving = true
end
function Frame:StopMovingOrSizing() self.moving = false; self.sizingFrom = nil end
function Frame:SetResizable(on) self.resizable = on end
function Frame:SetResizeBounds(a, b, c, d) self.resizeBounds = { a, b, c, d } end
function Frame:StartSizing(point)
  if not self.resizable then error("Frame:StartSizing: frame is not resizable", 2) end
  self.sizingFrom = point
end
function Frame:SetUserPlaced(on) self.userPlaced = on end
-- Scale: the effective scale is the product up the parent chain; GetLeft /
-- GetTop return what a spec put in .left / .top (nil: not laid out yet).
function Frame:SetScale(s) self.scale = s end
function Frame:GetScale() return self.scale or 1 end
function Frame:GetEffectiveScale()
  local parent = self.parent
  local up = (parent and parent.GetEffectiveScale) and parent:GetEffectiveScale() or 1
  return up * (self.scale or 1)
end
function Frame:GetLeft() return self.left end
function Frame:GetTop() return self.top end
function Frame:GetRight() return self.right end
function Frame:GetBottom() return self.bottom end
function Frame:SetHyperlinksEnabled(on) self.hyperlinks = on end
function Frame:SetEnabled(on) self.enabled = on end
function Frame:IsEnabled() return self.enabled ~= false end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetNormalTexture(tex) self.normalTexture = tex end
function Frame:SetHighlightTexture(tex) self.highlightTexture = tex end
function Frame:SetPushedTexture(tex) self.pushedTexture = tex end
function Frame:RegisterForClicks(...) self.clickButtons = { ... } end
STUB_CURSOR = { 0, 0 }
function GetCursorPosition() return STUB_CURSOR[1], STUB_CURSOR[2] end
function Frame:SetID(id) self.id = id end
function Frame:GetID() return self.id or 0 end
function Frame:CreateFontString(name, layer, template)
  local fs = newRegion("FontString", name, self)
  fs.layer, fs.template = layer, template
  return fs
end
function Frame:CreateTexture(name, layer, template, sublevel)
  local tex = newRegion("Texture", name, self)
  tex.layer = layer
  tex.sublevel = sublevel
  return tex
end
-- Fires a script handler as the client would (OnClick, OnDragStop, ...).
function Frame:RunScript(name, ...)
  local fn = self.scripts[name]
  if fn then return fn(self, ...) end
end

local portraitMethods = {
  SetTitle = function(self, title) self.title = title end,
  SetPortraitToAsset = function(self, asset) self.portraitAsset = asset end,
}
local TEMPLATE_METHODS = {
  PortraitFrameTemplate = portraitMethods,
  PortraitFrameFlatTemplate = portraitMethods,
}
-- Specs may add methods for other templates (copied onto each new frame).
STUB_TEMPLATE_METHODS = TEMPLATE_METHODS

-- C_XMLUtil.GetTemplateInfo knows the templates in STUB_TEMPLATES (the
-- classic ones plus the modern ones the UI prefers); specs remove entries to
-- test the fallbacks (reset_ui_stub restores them).
local MODERN_TEMPLATES = { "PortraitFrameFlatTemplate", "PanelTopTabButtonTemplate",
  "WowStyle1FilterDropdownTemplate", "MinimalCheckboxTemplate" }
local CLASSIC_TEMPLATES = { "PortraitFrameTemplate", "PanelTabButtonTemplate", "InsetFrameTemplate",
  "UIPanelButtonTemplate", "UICheckButtonTemplate", "SearchBoxTemplate", "BackdropTemplate" }
STUB_TEMPLATES = {}
local function resetTemplates()
  wipe(STUB_TEMPLATES)
  for _, name in ipairs(MODERN_TEMPLATES) do STUB_TEMPLATES[name] = true end
  for _, name in ipairs(CLASSIC_TEMPLATES) do STUB_TEMPLATES[name] = true end
end
resetTemplates()
C_XMLUtil = {
  GetTemplateInfo = function(name)
    if STUB_TEMPLATES[name] then return { type = "Frame", width = 0, height = 0 } end
    return nil
  end,
}
-- C_Texture.GetAtlasInfo knows the atlases in STUB_ATLASES.
STUB_ATLASES = {}
C_Texture = {
  GetAtlasInfo = function(name)
    if STUB_ATLASES[name] then return { width = 1, height = 1 } end
    return nil
  end,
}

UIParent = UIParent or setmetatable(newRegion("Frame", "UIParent"), Frame)
UISpecialFrames = UISpecialFrames or {}
local createdFrames = {}

function CreateFrame(frameType, name, parent, template)
  local f = setmetatable(newRegion(frameType, name, parent), Frame)
  f.template = template
  for tmpl in string.gmatch(template or "", "[^,%s]+") do
    for k, fn in pairs(TEMPLATE_METHODS[tmpl] or {}) do f[k] = fn end
  end
  createdFrames[#createdFrames + 1] = f
  return f
end

function PanelTemplates_SetNumTabs(frame, n) frame.numTabs = n end
function PanelTemplates_TabResize(tab, padding, absoluteSize, minWidth, maxWidth)
  tab.resized = { padding = padding, absoluteSize = absoluteSize, minWidth = minWidth, maxWidth = maxWidth }
end
function PanelTemplates_SetTab(frame, id)
  assert(frame.numTabs and id >= 1 and id <= frame.numTabs, "PanelTemplates_SetTab: bad tab id")
  frame.selectedTab = id
end

local loggedIn = false
function IsLoggedIn() return loggedIn end

-- Fires `event` at every fake frame that registered it, then marks the player
-- logged in when the event is PLAYER_LOGIN.
function fire_frame_event(event, ...)
  if event == "PLAYER_LOGIN" then loggedIn = true end
  for _, f in ipairs(createdFrames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

-- Fake LibDataBroker-1.1 / LibDBIcon-1.0: record what the UI registers.
fakeLibs["LibDataBroker-1.1"] = {
  objects = {},
  NewDataObject = function(self, name, obj)
    if self.objects[name] then return nil end -- like LDB: names are unique
    self.objects[name] = obj
    return obj
  end,
}
fakeLibs["LibDBIcon-1.0"] = {
  registered = {},
  Register = function(self, name, obj, db) self.registered[name] = { obj = obj, db = db } end,
}

-- Clears UI state between specs that load UI/ files more than once.
function reset_ui_stub()
  wipe(UISpecialFrames)
  wipe(createdFrames)
  wipe(fakeLibs["LibDataBroker-1.1"].objects)
  wipe(fakeLibs["LibDBIcon-1.0"].registered)
  loggedIn = false
  resetTemplates()
  wipe(STUB_ATLASES)
  MountTrailFrame = nil
  for i = 1, 8 do _G["MountTrailFrameTab" .. i] = nil end
end
