-- Minimal test harness. Globals: describe, it, eq, ok, load_addon.
-- ROOT (repo root, no trailing slash) is set by tools/run_tests.py.

local passed, failed = 0, 0
local failures = {}
local prefix = ""

local function deepeq(a, b, seen)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do
    if not deepeq(v, b[k], seen) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function repr(v, depth)
  depth = depth or 0
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  if depth > 3 then return "{...}" end
  local parts = {}
  for k, x in pairs(v) do
    parts[#parts + 1] = "[" .. repr(k, depth + 1) .. "]=" .. repr(x, depth + 1)
  end
  table.sort(parts)
  return "{" .. table.concat(parts, ", ") .. "}"
end

function eq(actual, expected, msg)
  if not deepeq(actual, expected) then
    error((msg and (msg .. ": ") or "") .. "expected " .. repr(expected) .. ", got " .. repr(actual), 2)
  end
end

function ok(cond, msg)
  if not cond then error(msg or "assertion failed", 2) end
end

function describe(name, fn)
  local old = prefix
  prefix = prefix .. name .. " > "
  local good, err = pcall(fn)
  if not good then
    failed = failed + 1
    failures[#failures + 1] = prefix .. "(describe body): " .. tostring(err)
    print("FAIL " .. prefix .. "(describe body): " .. tostring(err))
  end
  prefix = old
end

function it(name, fn)
  local good, err = pcall(fn)
  if good then
    passed = passed + 1
    print("PASS " .. prefix .. name)
  else
    failed = failed + 1
    failures[#failures + 1] = prefix .. name .. ": " .. tostring(err)
    print("FAIL " .. prefix .. name .. ": " .. tostring(err))
  end
end

-- Runs each file (path relative to repo root) with ("MountTrail", ns)
-- sharing one ns table; returns ns.
-- Files split out of a bigger one load right after it, as in the .toc, so a
-- spec that names UI/Frame.lua or UI/List.lua gets the whole of it.
COMPANIONS = {
  ["UI/Frame.lua"] = { "UI/Widgets.lua", "UI/Style.lua", "UI/Nav.lua" },
  ["UI/Popouts.lua"] = { "UI/Style.lua" },
  ["UI/List.lua"] = { "UI/SourceText.lua", "UI/Search.lua" },
}

function load_addon(files)
  local ns = {}
  local loaded = {}
  local function load(path)
    if loaded[path] then return end
    loaded[path] = true
    local chunk, err = loadfile(ROOT .. "/" .. path)
    if not chunk then error("cannot load " .. path .. ": " .. tostring(err), 3) end
    chunk("MountTrail", ns)
    for _, extra in ipairs(COMPANIONS[path] or {}) do load(extra) end
  end
  for _, path in ipairs(files) do load(path) end
  return ns
end

-- Called by the Python runner after the spec file has run.
function __harness_summary()
  return passed, failed
end

-- Lua-side compile check (no execution). Returns error string or nil.
function __syntax_check(src, chunkname)
  local fn, err = loadstring(src, chunkname)
  if not fn then return err end
  return nil
end
