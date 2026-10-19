-- Window scale: the bottom-right grip scales the main window, keeping its
-- top-left corner in place; right-click resets; the scale is saved.

local function loadUI()
  reset_ui_stub()
  local files = toc_lua_files()
  for _, f in ipairs({ "UI/Frame.lua" }) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  return ns
end

local function near(a, b, msg)
  ok(math.abs(a - b) < 1e-6, (msg or "") .. ": " .. tostring(a) .. " vs " .. tostring(b))
end

describe("window scale", function()
  it("ClampScale keeps 60-150% in whole percent; junk is 100%", function()
    local UI = loadUI().UI
    eq(UI.ClampScale(1.234), 1.23)
    eq(UI.ClampScale(0.2), 0.6)
    eq(UI.ClampScale(3), 1.5)
    eq(UI.ClampScale(nil), 1)
    eq(UI.ClampScale(0 / 0), 1, "NaN")
  end)

  it("ScaleFromCursor: the corner follows the cursor along the diagonal", function()
    local UI = loadUI().UI
    -- Window 800 x 560 with its top-left at (100, 900) px, UIParent scale 1.
    eq(UI.ScaleFromCursor(900, 340, 100, 900, 800, 560, 1), 1, "cursor on the 100% corner")
    eq(UI.ScaleFromCursor(1300, 60, 100, 900, 800, 560, 1), 1.5, "1.5x corner")
    eq(UI.ScaleFromCursor(740, 452, 100, 900, 800, 560, 1), 0.8, "0.8x corner")
    eq(UI.ScaleFromCursor(1700, 340, 100, 900, 800, 560, 1) > 1, true, "dragging right alone grows")
    eq(UI.ScaleFromCursor(100, 900, 100, 900, 800, 560, 1), 0.6, "clamped")
    eq(UI.ScaleFromCursor(1000, 280, 50, 450, 800, 560, 0.5), 1.5, "UIParent scale counts")
  end)

  it("SetWindowScale keeps the top-left corner on screen and saves scale and position", function()
    local ns = loadUI()
    ns.ToggleWindow()
    local frame = ns.UI.frame
    frame.left, frame.top = 200, 700
    ns.UI.SetWindowScale(frame, 1.25)
    eq(frame:GetScale(), 1.25)
    local point, rel, relPoint, x, y = frame:GetPoint(1)
    eq({ point, relPoint }, { "TOPLEFT", "BOTTOMLEFT" })
    eq(rel, UIParent)
    near(x * 1.25, 200, "left edge stays")
    near(y * 1.25, 700, "top edge stays")
    local db = ns.db.global.window
    eq(db.scale, 1.25)
    eq(db.point, "TOPLEFT")
    near(db.x, x, "saved x")
  end)

  it("the saved scale is applied when the window is built", function()
    local ns = loadUI()
    ns.db.global.window.scale = 0.8
    ns.ToggleWindow()
    eq(ns.UI.frame:GetScale(), 0.8)
    local ns2 = loadUI()
    ns2.db.global.window.scale = "big"
    ns2.ToggleWindow()
    eq(ns2.UI.frame:GetScale(), 1, "junk -> 100%")
  end)

  it("the grip scales while dragged, stops on release, and right-click resets", function()
    local ns = loadUI()
    ns.ToggleWindow()
    local frame = ns.UI.frame
    local grip = frame.ScaleGrip
    ok(grip, "grip on the window")
    eq(grip:GetPoint(1), "BOTTOMRIGHT")
    eq(grip.clickButtons, { "RightButtonUp" })
    frame.left, frame.top = 100, 900
    grip:RunScript("OnMouseDown", "LeftButton")
    ok(grip:GetScript("OnUpdate"), "dragging")
    STUB_CURSOR[1], STUB_CURSOR[2] = 1300, 60
    grip:RunScript("OnUpdate", 0.016)
    eq(frame:GetScale(), 1.5)
    grip:RunScript("OnMouseUp", "LeftButton")
    eq(grip:GetScript("OnUpdate"), nil, "stopped")
    grip:RunScript("OnClick", "RightButton")
    eq(frame:GetScale(), 1)
    eq(ns.db.global.window.scale, 1)
    grip:RunScript("OnMouseDown", "RightButton")
    eq(grip:GetScript("OnUpdate"), nil, "right button does not drag")
    STUB_CURSOR[1], STUB_CURSOR[2] = 0, 0
  end)
end)
