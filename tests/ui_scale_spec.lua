-- Window size: the bottom-right grip resizes the main window freely (within
-- the minimum and the screen), keeping its top-left corner; right-click
-- resets to the default size; the size is saved. (Formerly a scale grip.)

local function loadUI()
  reset_ui_stub()
  local files = toc_lua_files()
  for _, f in ipairs({ "UI/Frame.lua" }) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  return ns
end

describe("window size", function()
  it("ClampSize keeps the minimum and the screen; junk is the default", function()
    local UI = loadUI().UI
    eq({ UI.ClampSize(1000.4, 700.6) }, { 1000, 701 })
    eq({ UI.ClampSize(300, 200) }, UI.MIN_SIZE, "minimum")
    eq({ UI.ClampSize(5000, 4000, 1920, 1080) }, { 1920, 1080 }, "the screen")
    eq({ UI.ClampSize(nil, 500) }, UI.WINDOW_SIZE)
    eq({ UI.ClampSize(0 / 0, 500) }, UI.WINDOW_SIZE, "NaN")
  end)

  it("the window is resizable within the minimum and the screen, at 100%", function()
    local ns = loadUI()
    ns.db.global.window.scale = 1.3 -- an earlier version's scale is dropped
    ns.ToggleWindow()
    local frame = ns.UI.frame
    eq(frame.resizable, true)
    eq({ frame.resizeBounds[1], frame.resizeBounds[2] }, ns.UI.MIN_SIZE)
    eq(frame:GetScale(), 1)
    eq(ns.db.global.window.scale, nil)
    eq({ frame:GetSize() }, ns.UI.WINDOW_SIZE, "default size")
  end)

  it("the Window scale setting scales the window when built and when changed", function()
    local ns = loadUI()
    local pct = 120
    ns.Options = { WindowScale = function() return pct end }
    ns.ToggleWindow()
    eq(ns.UI.frame:GetScale(), 1.2)
    pct = 90
    ns.UI.ApplyWindowScale()
    eq(ns.UI.frame:GetScale(), 0.9)
  end)

  it("the saved size is applied when the window is built", function()
    local ns = loadUI()
    ns.db.global.window.width, ns.db.global.window.height = 1100, 760
    ns.ToggleWindow()
    eq({ ns.UI.frame:GetSize() }, { 1100, 760 })
  end)

  it("the grip sizes from the bottom-right, saves on release; right-click resets", function()
    local ns = loadUI()
    ns.ToggleWindow()
    local frame = ns.UI.frame
    local grip = frame.SizeGrip
    ok(grip, "grip on the window")
    eq(grip:GetPoint(1), "BOTTOMRIGHT")
    frame.left, frame.top = 200, 900
    grip:RunScript("OnMouseDown", "LeftButton")
    eq(frame.sizingFrom, "BOTTOMRIGHT")
    frame.width, frame.height = 1000, 650 -- the client resized it while dragging
    grip:RunScript("OnMouseUp", "LeftButton")
    eq(frame.sizingFrom, nil, "stopped")
    eq({ ns.db.global.window.width, ns.db.global.window.height }, { 1000, 650 })
    local point, rel, relPoint, x, y = frame:GetPoint(1)
    eq({ point, relPoint, x, y }, { "TOPLEFT", "BOTTOMLEFT", 200, 900 }, "top-left kept")
    grip:RunScript("OnClick", "RightButton")
    eq({ frame:GetSize() }, ns.UI.WINDOW_SIZE)
    eq({ ns.db.global.window.width, ns.db.global.window.height }, ns.UI.WINDOW_SIZE)
    grip:RunScript("OnMouseDown", "RightButton")
    eq(frame.sizingFrom, nil, "right button does not size")
  end)
end)
