# Contributing to MountTrail

This page covers setting up a development copy, running the tests, the data
tools and the conventions the code follows. [ARCHITECTURE.md](ARCHITECTURE.md)
explains how the code is laid out.

## Setup

1. Clone the repository anywhere.
2. Link it into the game's AddOns folder, so the game loads the clone
   directly. On Windows, `tools/link_addon.ps1` creates a directory junction:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/link_addon.ps1 -WowPath "C:\Program Files (x86)\World of Warcraft"
   ```

   - The junction is `<WowPath>\_retail_\Interface\AddOns\MountTrail`, pointing
     at the repository root.
   - `-WowPath` is the install folder that contains `_retail_`, not `_retail_`
     itself; the script exits 1 when `_retail_` is missing.
   - It is safe to run again: an existing junction is left alone. It refuses
     to touch an existing folder or file that is not a junction.
   - It also handles the old name: an `AddOns\AzerothTrail` junction is
     removed, and each account's `SavedVariables\AzerothTrail.lua` is copied
     to `MountTrail.lua` when that does not exist yet.
   - To unlink, delete only the junction:
     `cmd /c rmdir "<WowPath>\_retail_\Interface\AddOns\MountTrail"`. This does
     not delete the repository.

   On other systems a symlink named `MountTrail` in the AddOns folder works the
   same way.
3. Install [TomTom](https://www.curseforge.com/wow/addons/tomtom) in the game;
   waypoints need it.

### /reload or a full restart?

- Edits to files the game already loads show up after `/reload`.
- A **new file** (a new entry in `MountTrail.toc`), a renamed file or a change
  to the `.toc` itself needs a **full game restart**. `/reload` does not
  re-read the file list.
- The `.toc` order matters for code that runs at load time: a file can only
  use what earlier files put on `ns` at the top level. Code that runs later
  (in functions, event handlers) can use anything.

## Running the tests

Requirements: Python 3 and [lupa](https://pypi.org/project/lupa/) (Lua inside
Python).

```bash
python3 -m pip install lupa
python3 tools/run_tests.py
```

`tools/run_tests.py` runs every `tests/*_spec.lua` file in a fresh Lua 5.1
runtime (LuaJIT 2.1 if lupa has no 5.1), then compiles (without running) every
addon `.lua` file outside `tests/`, `tools/`, `Libs/` and `docs/`. It exits
non-zero on any failed test or syntax error.

How the harness works:

- `tests/harness.lua` provides `describe`, `it`, `eq` (deep equality), `ok`
  and `load_addon(files)`, which runs each file with `("MountTrail", ns)` and
  one shared `ns`, as the game does.
- `tests/wow_stub.lua` stands in for the game: string aliases (`strsplit`,
  `tinsert`, ...), a fake LibStub / AceAddon / AceDB, `fire_event` and
  `run_slash` to drive the addon object, and fake widgets (`CreateFrame`,
  regions, scroll boxes, templates) that record what was set on them so UI
  specs can assert on it. `reset_ui_stub()` clears that state between specs.
- `toc_lua_files()` reads `MountTrail.toc` and returns every non-UI Lua file in
  load order. UI specs append the UI files they need.
- `COMPANIONS` in `tests/harness.lua` lists files split out of a bigger one:
  loading `UI/Frame.lua` also loads `UI/Widgets.lua` and `UI/Nav.lua`, and
  loading `UI/List.lua` also loads `UI/Search.lua`, right after it, as in the
  `.toc`. When you split a file, add it here and to the `.toc`.
- Logic specs need no stubs at all: `Logic/` takes everything as arguments.

The data tools have their own Python unit tests:

```bash
python3 -m unittest tools/test_build_data.py tools/test_build_spots.py tools/test_build_zones.py tools/test_verify_data.py
```

They use the fixtures in `tools/fixtures/` and need no network.

## Data tools

The generated `Data/` files are never edited by hand; change the tool and
regenerate. Downloads are cached in `tools/.cache/` (gitignored). The tools use
the Python standard library only.

| Tool | Writes | Notes |
| --- | --- | --- |
| `tools/build_data.py` | `Data/Mounts.lua`, `Data/Route.lua`, `Data/LICENSE-SimpleArmory.txt` | From SimpleArmory and Rarity at the commits pinned in `tools/sources.json`. `--update` pins the current master commits first. |
| `tools/build_spots.py` | `Data/Spots.lua`, `Data/LICENSE-AllTheThings.txt` | From AllTheThings (pinned commit) and the game's Mount.db2 source text / UiMap. `--offline` uses the cache only. |
| `tools/build_zones.py` | `Data/Zones.lua` | From the game's UiMap and ContentTuning tables at the pinned `db2build`. `--offline` uses the cache only. |
| `tools/verify_data.py` | `docs/data-verification.md` | Checks `Data/` against the game's DB2 tables (via wago.tools). `--build <version>`, `--offline`, `--json out.json`. |

`tools/verify_data.py` checks mount identity, route drop claims, lockout specs,
event status IDs, completeness (every collectable Mount.db2 mount is in the
data), each mount's section against the game's source, and that every
rare-spawn mount is on the checklist. It exits 1 on any error not listed in
`tools/verify_allow.json`; an allowlisted finding is shown as info with its
reason. See [docs/data-verification.md](docs/data-verification.md) for the
latest report and [docs/ingame-checklist.md](docs/ingame-checklist.md) for the
checks that can only be done in game.

Hand-written data (`Data/Lockouts.lua`, `Data/Holidays.lua`, `Data/Events.lua`,
`Data/SpotsExtra.lua`) documents its shapes in each file's header. Run
`tools/verify_data.py` after changing lockouts or events. Never copy
coordinates from sites whose terms forbid it.

## Code style

The rules below are what the existing code does; follow them in new code.

- **One namespace.** Every file starts with `local ADDON, ns = ...` and puts its
  module on `ns` (`ns.Checklist`, `ns.UI`, ...). No new globals; the only ones
  are the saved variables.
- **Header comment.** Every file opens with a comment saying what it is, what
  it owns and anything surprising about it (load order, taint, why something
  is done this way).
- **Comments say why**, in plain sentences: the reason, the case being
  handled, the game behaviour being worked around. Not a restatement of the
  code.
- **Layers stay clean.** `Logic/` never touches a WoW global; the caller
  passes data and predicates in. Game data calls go through `Game/API.lua`.
- **Strings through `L[...]`.** Every text the player sees is `L["..."]`, with
  the English text as the key, added to `Core/Locale.lua` under the heading of
  the file that uses it.
- **Guard other addons.** Calls into TomTom, Rarity, AllTheThings,
  MountsRarity-2.0 and similar go through `pcall` and type checks; a missing
  or changed addon gives `nil`, never a Lua error.
- **Guard optional APIs.** Check that a template, atlas or API exists before
  using it (`UI.Template`, `UI.AtlasExists`, `type(C_Timer) == "table"`), with
  a fallback.
- **Widgets are created once and reused.** Frames, font strings and textures
  are made when a view or row is first built and then only updated. Never
  create widgets in a refresh path (`Refresh`, `ns.Refresh` hooks, scroll box
  initialisers that run on every redraw): the game never frees frames.
- **Errors do not break the window.** Hooks and click handlers catch errors and
  report them with `Game.ReportError` (shown with `/mtrail debug`).
- **Tests come with changes.** New logic gets a spec in `tests/`; a UI change
  that can be checked under the widget stub gets one too.

`.luacheckrc` at the repository root configures
[luacheck](https://github.com/lunarmodules/luacheck) for these rules (Lua 5.1,
the WoW globals the addon reads, `Libs/` excluded). Run `luacheck .` if you have
it installed.

### Keeping the structure

Put new code in the file that already owns that job (see
[ARCHITECTURE.md](ARCHITECTURE.md), "Where to find X"). Keep files under about
1,000 lines where practical; when one grows past that, split it by job, list
the new file in `MountTrail.toc` next to its parent and, if specs load the
parent, in `COMPANIONS` (`tests/harness.lua`). Remove dead code rather than
leaving it switched off.

### Adding a built-in guide

Write the guide (README, "Guides", has the format), save it as
`Guides/<Name>.lua` appending its text to `ns.GuideTexts` (copy
`Guides/ThunderingRubyCloudSerpent.lua`), and list the file in `MountTrail.toc`
under the other `Guides\` lines. `tests/guide_spec.lua` shows how to check it
parses. Write guides yourself: don't copy another guide site's or addon's text.

## Commit messages

Conventional-commit style, as in `git log --oneline`:

```
feat(nav): reorder My lists, Quick lists and Browse; hide list sections
fix(pane): a plain click only views the mount; right-click plots
perf: share the checklist build and search cache; one refresh per event burst
chore: load split-out UI files with their parent in tests and the toc
docs: tooltip hint line
```

- Type: `feat`, `fix`, `perf`, `chore`, `docs`; `feat!` for a change that
  drops something players relied on.
- Scope: the area touched (`nav`, `pane`, `popouts`, `lists`, `search`,
  `checklist`, `map`, `ui`, `data`, `verify`, ...).
- Subject: lower case, present tense, says what the player or developer gets.
  Several related changes are joined with `;`.

## Before you push

- [ ] `python3 tools/run_tests.py` passes (specs and syntax check).
- [ ] If a data tool changed: its `python3 -m unittest tools/test_*.py` passes,
      the generated files are regenerated and committed, and
      `python3 tools/verify_data.py` has no new errors.
- [ ] New files are in `MountTrail.toc` in the right place (and in
      `COMPANIONS` if split out of another file).
- [ ] New player-facing strings are in `Core/Locale.lua`.
- [ ] No new globals (`luacheck .` if available).
- [ ] Checked in game: `/reload` for edits, a full restart for new files.
- [ ] `README.md` updated for anything players will notice;
      `ARCHITECTURE.md` for a new file, view, hook or saved variable.
