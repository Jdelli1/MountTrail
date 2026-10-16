#!/usr/bin/env python3
"""Runs every tests/*_spec.lua under Lua 5.1 (via lupa) and syntax-checks every
addon .lua file. Exits non-zero on any failure."""
import functools
import os
import sys

try:
    from lupa import lua51 as lupa_rt
except ImportError:
    try:
        from lupa import luajit21 as lupa_rt
    except ImportError:
        sys.exit("FATAL: lupa with lua51 or luajit21 support is required (python -m pip install lupa)")

print = functools.partial(print, flush=True)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXCLUDED_DIRS = {"tests", "tools", "Libs", ".superpowers", ".git", "docs", ".cache", "__pycache__"}


def new_runtime():
    lua = lupa_rt.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ROOT = ROOT.replace("\\", "/")
    lua.globals().print = lambda *a: print(*[str(x) for x in a])
    for name in ("harness.lua", "wow_stub.lua"):
        path = os.path.join(ROOT, "tests", name)
        with open(path, encoding="utf-8") as fh:
            lua.execute(fh.read())
    return lua


def addon_lua_files():
    found = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = sorted(d for d in dirnames if d not in EXCLUDED_DIRS)
        for fn in sorted(filenames):
            if fn.endswith(".lua"):
                found.append(os.path.join(dirpath, fn))
    return found


def syntax_check():
    """Compile (never execute) every addon Lua file. Returns failure count."""
    lua = new_runtime()
    check = lua.globals().__syntax_check
    bad = 0
    files = addon_lua_files()
    for path in files:
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        with open(path, encoding="utf-8") as fh:
            src = fh.read()
        err = check(src, "@" + rel)
        if err:
            bad += 1
            print("SYNTAX FAIL %s: %s" % (rel, err))
    print("syntax check: %d file(s), %d error(s)" % (len(files), bad))
    return bad


def run_spec(path):
    rel = os.path.relpath(path, ROOT).replace("\\", "/")
    print("== %s" % rel)
    lua = new_runtime()
    try:
        with open(path, encoding="utf-8") as fh:
            lua.execute(fh.read())
    except lupa_rt.LuaError as exc:
        print("FAIL %s: spec error: %s" % (rel, exc))
        return 0, 1
    passed, failed = lua.globals().__harness_summary()
    return int(passed), int(failed)


def main():
    tests_dir = os.path.join(ROOT, "tests")
    specs = sorted(
        os.path.join(tests_dir, f) for f in os.listdir(tests_dir) if f.endswith("_spec.lua")
    )
    total_pass = total_fail = 0
    for spec in specs:
        p, f = run_spec(spec)
        total_pass += p
        total_fail += f
    syntax_bad = syntax_check()
    print("\n%d passed, %d failed, %d syntax error(s)" % (total_pass, total_fail, syntax_bad))
    return 1 if (total_fail or syntax_bad or not specs) else 0


if __name__ == "__main__":
    sys.exit(main())
