#!/usr/bin/env python3
"""Verifies the addon's mount data against the game's own DB2 tables.

Usage:
    python tools/verify_data.py                 # latest Retail build on wago.tools
    python tools/verify_data.py --build 12.1.5.70448
    python tools/verify_data.py --offline       # newest build already in the cache
    python tools/verify_data.py --json out.json # also dump every finding as JSON

Source of truth: Blizzard DB2 tables as CSV from https://wago.tools/db2/<Table>/csv.
Downloads are cached under tools/.cache/db2/<build>/ (gitignored). Standard library only.

Checks (see docs/data-verification.md for the latest report):
  identity  Data/Mounts.lua ids, names, spells and items vs Mount.db2 / ItemEffect.
  route     Data/Route.lua kill rows: is the mount in that boss's Encounter Journal loot?
  lockout   Data/Lockouts.lua instance specs: map ID, boss name and loot.
  candidates Mounts in Encounter Journal loot with no lockout spec and no Rarity quest.

Allowlist (tools/verify_allow.json): {"route": {"<mount>@<boss>": "reason"},
"identity": {"<mount>": "reason"}, "lockout": {"<mount>" or "boss:<route boss>": "reason"}}.
An allowlisted finding is downgraded to info and keeps its reason.

Exit code 1 if any error remains after the allowlist.
"""
import argparse
import csv
import datetime
import json
import os
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
DATA = os.path.join(ROOT, "Data")
CACHE = os.path.join(TOOLS, ".cache", "db2")
ALLOW_PATH = os.path.join(TOOLS, "verify_allow.json")
REPORT_PATH = os.path.join(ROOT, "docs", "data-verification.md")

WAGO = "https://wago.tools"
PRODUCT = "wow"  # Retail
USER_AGENT = "AzerothTrail-data-verifier/1.0 (Python urllib; WoW addon data check)"
TABLES = (
    "Mount",
    "JournalEncounterItem",
    "JournalEncounter",
    "JournalInstance",
    "DungeonEncounter",
    "ItemEffect",
    "ItemXItemEffect",
)
SEVERITIES = ("error", "warn", "info")
CHECKS = ("identity", "route", "lockout")
CHECK_TITLES = {
    "identity": "1. Mount identity (Mount.db2, ItemEffect)",
    "route": "2. Route drop claims (JournalEncounterItem)",
    "lockout": "3. Lockout specs (JournalInstance, JournalEncounter, DungeonEncounter)",
}
# Mount.SourceTypeEnum (same values as the pet journal's source filter).
SOURCE_TYPES = {
    0: "Drop", 1: "Quest", 2: "Vendor", 3: "Profession", 4: "Wild pet", 5: "Achievement",
    6: "World Event", 7: "Promotion", 8: "Trading Card Game", 9: "Shop", 10: "Discovery",
    11: "Trading Post",
}


# --- download + cache -----------------------------------------------------------------

def _http_get(url, attempts=5, opener=None):
    """GET with retries and exponential backoff. Returns (body bytes, headers)."""
    opener = opener or urllib.request.urlopen
    delay = 1.0
    last = None
    for attempt in range(attempts):
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with opener(req, timeout=120) as resp:
                return resp.read(), resp.headers
        except urllib.error.HTTPError as exc:
            last = exc
            if exc.code not in (429, 500, 502, 503, 504):
                raise
        except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
            last = exc
        if attempt + 1 < attempts:
            time.sleep(delay)
            delay *= 2
    raise RuntimeError("GET %s failed after %d attempts: %s" % (url, attempts, last))


def latest_build(product=PRODUCT):
    """The newest build wago.tools knows for `product`, e.g. '12.1.5.70448'."""
    body, _ = _http_get(WAGO + "/api/builds/latest")
    info = json.loads(body.decode("utf-8"))
    return info[product]["version"]


def cached_builds(cache=CACHE):
    if not os.path.isdir(cache):
        return []
    def key(v):
        return tuple(int(p) if p.isdigit() else 0 for p in v.split("."))
    builds = [d for d in os.listdir(cache)
              if all(os.path.isfile(os.path.join(cache, d, t + ".csv")) for t in TABLES)]
    return sorted(builds, key=key)


def fetch_tables(build, cache=CACHE, offline=False):
    """Make sure every table CSV of `build` is in cache/<build>/; returns that directory."""
    folder = os.path.join(cache, build)
    os.makedirs(folder, exist_ok=True)
    for table in TABLES:
        path = os.path.join(folder, table + ".csv")
        if os.path.isfile(path) and os.path.getsize(path) > 0:
            continue
        if offline:
            raise RuntimeError("offline: %s missing from the cache" % path)
        url = "%s/db2/%s/csv?build=%s" % (WAGO, table, build)
        body, headers = _http_get(url)
        disposition = headers.get("Content-Disposition", "") if headers else ""
        if disposition and build not in disposition:
            raise RuntimeError("%s: asked for build %s, got %r" % (table, build, disposition))
        first = body.split(b"\n", 1)[0]
        if b"ID" not in first:
            raise RuntimeError("%s: response is not a DB2 CSV (first line %r)" % (table, first[:120]))
        tmp = path + ".part"
        with open(tmp, "wb") as fh:
            fh.write(body)
        os.replace(tmp, path)
        print("downloaded %s (%d bytes)" % (url, len(body)), file=sys.stderr)
    return folder


def read_csv(path):
    with open(path, encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def _int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


# --- minimal Lua data parser -------------------------------------------------------------

class LuaError(ValueError):
    pass


_TOKEN = re.compile(r"""
    (?P<ws>\s+)
  | (?P<comment>--\[(?P<eq>=*)\[.*?\](?P=eq)\]|--[^\n]*)
  | (?P<str>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<num>-?0[xX][0-9a-fA-F]+|-?\d+(?:\.\d*)?(?:[eE][-+]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>[{}\[\]=,;])
""", re.S | re.X)

_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def _unescape(body):
    def repl(m):
        ch = m.group(1)
        if ch.isdigit():
            return chr(int(ch))
        return _ESCAPES.get(ch, ch)
    return re.sub(r"\\(\d{1,3}|.)", repl, body, flags=re.S)


def _tokens(text, pos):
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m:
            yield ("other", text[pos], pos)
            return
        pos = m.end()
        kind = m.lastgroup if m.lastgroup != "eq" else "comment"
        if m.group("ws") is not None or m.group("comment") is not None:
            continue
        for k in ("str", "num", "name", "op"):
            if m.group(k) is not None:
                yield (k, m.group(k), m.start())
                break


class _Parser:
    def __init__(self, text, pos):
        self.it = _tokens(text, pos)
        self.tok = next(self.it, ("eof", "", len(text)))

    def advance(self):
        cur = self.tok
        self.tok = next(self.it, ("eof", "", -1))
        return cur

    def expect(self, value):
        kind, val, pos = self.advance()
        if val != value:
            raise LuaError("expected %r at %d, got %r" % (value, pos, val))

    def value(self):
        kind, val, pos = self.advance()
        if kind == "str":
            return _unescape(val[1:-1])
        if kind == "num":
            if re.match(r"-?0[xX]", val):
                return int(val, 16)
            return float(val) if re.search(r"[.eE]", val) else int(val)
        if kind == "name" and val in ("true", "false", "nil"):
            return {"true": True, "false": False, "nil": None}[val]
        if val == "{":
            return self.table()
        raise LuaError("unexpected %r at %d" % (val, pos))

    def table(self):
        keyed, items = {}, []
        while self.tok[1] != "}":
            if self.tok[0] == "eof":
                raise LuaError("unterminated table")
            if self.tok[1] == "[":
                self.advance()
                key = self.value()
                self.expect("]")
                self.expect("=")
                keyed[key] = self.value()
            elif self.tok[0] == "name" and self.tok[1] not in ("true", "false", "nil"):
                key = self.advance()[1]
                self.expect("=")
                keyed[key] = self.value()
            else:
                items.append(self.value())
            if self.tok[1] in (",", ";"):
                self.advance()
            elif self.tok[1] != "}":
                raise LuaError("expected , or } at %d, got %r" % (self.tok[2], self.tok[1]))
        self.advance()
        if not keyed:
            return items
        for i, item in enumerate(items, 1):
            keyed[i] = item
        return keyed


def lua_assignment(text, target):
    """Parse the table literal assigned to `target` (e.g. 'ns.Data.Mounts') in Lua source."""
    m = re.search(r"^[ \t]*" + re.escape(target) + r"[ \t]*=[ \t]*", text, re.M)
    if not m:
        return None
    return _Parser(text, m.end()).value()


def load_our_data(data_dir=DATA):
    def read(name):
        with open(os.path.join(data_dir, name), encoding="utf-8") as fh:
            return fh.read()
    mounts_src, route_src, lock_src = read("Mounts.lua"), read("Route.lua"), read("Lockouts.lua")
    return {
        "mounts": lua_assignment(mounts_src, "ns.Data.Mounts") or {},
        "expansions": lua_assignment(mounts_src, "ns.Data.Expansions") or [],
        "route": lua_assignment(route_src, "ns.Data.Route") or [],
        "lockouts": lua_assignment(lock_src, "ns.Data.Lockouts") or {},
        "boss_lockouts": lua_assignment(lock_src, "ns.Data.BossLockouts") or {},
    }


# --- normalisation + name matching -------------------------------------------------------

def _fold(s):
    s = unicodedata.normalize("NFKD", s or "")
    return "".join(c for c in s if not unicodedata.combining(c))


def norm_boss(name):
    """Lowercase, accents folded, apostrophes dropped, other punctuation -> space,
    leading 'The' dropped: "The Lich King" -> "lich king", "Kael'thas" -> "kaelthas"."""
    s = _fold(name).lower().replace("\u2019", "'").replace("'", "")
    s = re.sub(r"[^a-z0-9]+", " ", s).strip()
    if s.startswith("the "):
        s = s[4:]
    return s


def norm_mount(name):
    """Case- and whitespace-insensitive (curly apostrophes folded)."""
    return " ".join((name or "").replace("\u2019", "'").lower().split())


def boss_match(ours, journal):
    """How a boss name in our data matches a journal name: 'exact', 'prefix' (whole
    words: "Fyrakk" ~ "Fyrakk the Blazing"), 'contains' (a whole-word run inside the
    other: "Rivendare" ~ "Lord Aurius Rivendare"), or None."""
    a, b = norm_boss(ours), norm_boss(journal)
    if not a or not b:
        return None
    if a == b:
        return "exact"
    if b.startswith(a + " ") or a.startswith(b + " "):
        return "prefix"
    if (" " + a + " ") in (" " + b + " ") or (" " + b + " ") in (" " + a + " "):
        return "contains"
    return None


def addon_match(spec_boss, game_name):
    """Logic/Lockouts.lua bossMatches: case-sensitive equality or plain prefix either way."""
    if not spec_boss or not game_name:
        return False
    return game_name.startswith(spec_boss) or spec_boss.startswith(game_name)


def mentions(text, name):
    """Does `text` contain the boss name as whole words (normalised)?"""
    a, t = norm_boss(name), norm_boss(text)
    return bool(a) and (" " + a + " ") in (" " + t + " ")


def clean_source_text(text):
    s = text or ""
    s = re.sub(r"\|T[^|]*\|t", "", s)
    s = re.sub(r"\|c[0-9A-Fa-f]{8}", "", s)
    s = re.sub(r"\|H[^|]*\|h", "", s).replace("|h", "")
    s = s.replace("|r", "").replace("|n", "; ")
    return " ".join(s.split()).strip("; ")


def source_fields(text):
    """'Drop: X; Zone: Y' -> {'drop': ['X'], 'zone': ['Y']} (labels lowercased)."""
    out = {}
    for part in clean_source_text(text).split(";"):
        if ":" in part:
            label, value = part.split(":", 1)
            label, value = label.strip().lower(), value.strip()
            if value:
                out.setdefault(label, []).append(value)
    return out


# --- game data index ---------------------------------------------------------------------

class Game:
    """Indexes over the DB2 CSVs in one build folder."""

    def __init__(self, folder):
        def rows(table):
            return read_csv(os.path.join(folder, table + ".csv"))

        self.mounts = {_int(r["ID"]): r for r in rows("Mount")}
        effects = {_int(r["ID"]): _int(r["SpellID"]) for r in rows("ItemEffect")}
        self.item_spells, self.spell_items = {}, {}
        for r in rows("ItemXItemEffect"):
            item, spell = _int(r["ItemID"]), effects.get(_int(r["ItemEffectID"]), 0)
            if not spell:
                continue
            self.item_spells.setdefault(item, set()).add(spell)
            self.spell_items.setdefault(spell, set()).add(item)
        self.instances = {_int(r["ID"]): r for r in rows("JournalInstance")}
        self.instances_by_map = {}
        for r in self.instances.values():
            self.instances_by_map.setdefault(_int(r["MapID"]), []).append(r)
        self.encounters = {_int(r["ID"]): r for r in rows("JournalEncounter")}
        self.encounters_by_instance = {}
        for r in sorted(self.encounters.values(), key=lambda e: (_int(e["OrderIndex"]), _int(e["ID"]))):
            self.encounters_by_instance.setdefault(_int(r["JournalInstanceID"]), []).append(r)
        self.loot = {}
        for r in rows("JournalEncounterItem"):
            self.loot.setdefault(_int(r["ItemID"]), []).append(r)
        self.dungeon_encounters_by_map = {}
        for r in rows("DungeonEncounter"):
            self.dungeon_encounters_by_map.setdefault(_int(r["MapID"]), []).append(r)

    def mount_spell(self, mount_id, ours=None):
        row = self.mounts.get(mount_id)
        spell = _int(row["SourceSpellID"]) if row else 0
        return spell or _int((ours or {}).get("spell"))

    def mount_items(self, mount_id, ours):
        """Our item plus every item whose ItemEffect teaches the mount's spell."""
        items = set()
        if _int(ours.get("item")):
            items.add(_int(ours["item"]))
        items |= self.spell_items.get(self.mount_spell(mount_id, ours), set())
        return items

    def loot_rows(self, items):
        """JournalEncounterItem rows for any of `items`, each with its encounter and instance."""
        out = []
        for item in sorted(items):
            for r in self.loot.get(item, []):
                enc = self.encounters.get(_int(r["JournalEncounterID"]))
                if not enc:
                    continue
                inst = self.instances.get(_int(enc["JournalInstanceID"]))
                out.append({"item": item, "row": r, "encounter": enc, "instance": inst})
        return out

    def instance_name(self, inst):
        return inst["Name_lang"] if inst else "?"


def describe_loot(hit):
    inst = hit["instance"]
    return "%s (%s, map %s, DifficultyMask %s)" % (
        hit["encounter"]["Name_lang"], inst["Name_lang"] if inst else "?",
        inst["MapID"] if inst else "?", hit["row"]["DifficultyMask"])


# --- findings ----------------------------------------------------------------------------

def finding(check, kind, severity, mount_id, name, detail, suggestion="", key=None):
    return {
        "check": check, "kind": kind, "severity": severity, "mount": mount_id,
        "name": name or "", "detail": detail, "suggestion": suggestion,
        "key": key if key is not None else str(mount_id), "allowed": None,
    }


def apply_allowlist(findings, allow):
    for f in findings:
        reason = (allow.get(f["check"]) or {}).get(f["key"])
        if reason and f["severity"] != "info":
            f["allowed"] = reason
            f["original_severity"] = f["severity"]
            f["severity"] = "info"
    return findings


def load_allowlist(path=ALLOW_PATH):
    if not os.path.isfile(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    return {k: v for k, v in data.items() if isinstance(v, dict)}


# --- check 1: identity -------------------------------------------------------------------

def check_identity(ours, game):
    out = []
    for mid in sorted(ours["mounts"]):
        m = ours["mounts"][mid]
        name = m.get("name", "")
        row = game.mounts.get(mid)
        if row is None:
            out.append(finding("identity", "missing-mount", "error", mid, name,
                               "mount ID %d is not in Mount.db2" % mid,
                               "check the ID (removed or mistyped mount)"))
            continue
        if norm_mount(name) != norm_mount(row["Name_lang"]):
            out.append(finding("identity", "name-mismatch", "warn", mid, name,
                               "ours %r, Mount.db2 %r" % (name, row["Name_lang"]),
                               "rename to %r" % row["Name_lang"]))
        spell, game_spell = _int(m.get("spell")), _int(row["SourceSpellID"])
        if spell and game_spell and spell != game_spell:
            out.append(finding("identity", "spell-mismatch", "error", mid, name,
                               "ours spell %d, Mount.db2 SourceSpellID %d" % (spell, game_spell),
                               "set spell = %d" % game_spell))
        item = _int(m.get("item"))
        if item and game_spell:
            taught = game.item_spells.get(item)
            if taught is not None and game_spell not in taught:
                teachers = sorted(game.spell_items.get(game_spell, ()))
                out.append(finding("identity", "item-mismatch", "warn", mid, name,
                                   "item %d does not teach spell %d (its spells: %s)"
                                   % (item, game_spell, ", ".join(map(str, sorted(taught)))),
                                   "items that teach it: %s" % (", ".join(map(str, teachers)) or "none")))
    return out


# --- check 2: route drop claims ----------------------------------------------------------

def route_rows(route):
    """Every kill row in the route tree: (title path, row) for bosses[] entries with a mount."""
    out = []

    def walk(node, path):
        if isinstance(node, list):
            for child in node:
                walk(child, path)
            return
        if not isinstance(node, dict):
            return
        title = node.get("title")
        here = path + [title] if isinstance(title, str) and title else path
        bosses = node.get("bosses")
        if isinstance(bosses, list):
            for row in bosses:
                if isinstance(row, dict) and row.get("mount") is not None:
                    out.append((here, row))
        for key in ("steps", "children"):
            if key in node:
                walk(node[key], here)
    walk(route, [])
    return out


def check_route(ours, game):
    out = []
    for path, row in route_rows(ours["route"]):
        mid, boss = _int(row.get("mount")), str(row.get("boss") or "")
        m = ours["mounts"].get(mid)
        where = " > ".join(path[-2:]) if path else "route"
        key = "%d@%s" % (mid, boss)
        if m is None:
            out.append(finding("route", "unknown-mount", "error", mid, "",
                               "route row %s (%s) names a mount missing from Data/Mounts.lua" % (boss, where),
                               "fix the mount ID", key))
            continue
        name = m.get("name", "")
        hits = game.loot_rows(game.mount_items(mid, m))
        matched = [h for h in hits if boss_match(boss, h["encounter"]["Name_lang"])]
        if matched:
            continue
        # An encounter whose journal text names the boss ("Salyis's Warband" rides Galleon).
        described = [h for h in hits if mentions(h["encounter"].get("Description_lang", ""), boss)]
        if described:
            out.append(finding("route", "boss-in-description", "info", mid, name,
                               "route says %r (%s); the journal lists it under %s, whose description "
                               "names %r" % (boss, where, describe_loot(described[0]), boss),
                               "optional: rename the boss to %r" % described[0]["encounter"]["Name_lang"], key))
            continue
        if hits:
            seen, names = set(), []
            for h in hits:
                d = describe_loot(h)
                if d not in seen:
                    seen.add(d)
                    names.append(d)
            out.append(finding("route", "wrong-boss", "error", mid, name,
                               "route says %r (%s); the Encounter Journal has it from: %s"
                               % (boss, where, "; ".join(names)),
                               "move the row to %s, or drop it" % hits[0]["encounter"]["Name_lang"], key))
        else:
            row_src = game.mounts.get(mid)
            src = clean_source_text(row_src["SourceText_lang"]) if row_src else ""
            drops = source_fields(row_src["SourceText_lang"]).get("drop", []) if row_src else []
            if any(boss_match(boss, d) for d in drops):
                out.append(finding("route", "source-text-only", "info", mid, name,
                                   "route says %r (%s); not in Encounter Journal loot, but Mount.db2 "
                                   "source names the boss: %s" % (boss, where, src), "", key))
                continue
            out.append(finding("route", "not-in-loot", "warn", mid, name,
                               "route says %r (%s); no Encounter Journal loot has items %s. "
                               "Mount.db2 source: %s" % (boss, where,
                                                       ", ".join(map(str, sorted(game.mount_items(mid, m)))) or "none",
                                                       src or "(none)"),
                               "legit for trash, world, holiday or timed-chest drops: allowlist with a reason", key))
    return out


# --- check 3: lockout specs --------------------------------------------------------------

def lockout_specs(ours):
    """(key, mount ids, label, spec) for every spec: Lockouts[mount] and BossLockouts[boss]."""
    out = []
    for mid in sorted(k for k in ours["lockouts"] if isinstance(k, int)):
        out.append((str(mid), [mid], str(mid), ours["lockouts"][mid]))
    rows = route_rows(ours["route"])
    for boss in sorted(ours["boss_lockouts"]):
        mids = sorted({_int(r.get("mount")) for _, r in rows if r.get("boss") == boss})
        out.append(("boss:" + boss, mids, "boss " + boss, ours["boss_lockouts"][boss]))
    return out


def check_lockouts(ours, game):
    """Returns (findings, table rows describing each instance spec's journal match)."""
    out, table = [], []
    for key, mids, label, spec in lockout_specs(ours):
        if not isinstance(spec, dict) or spec.get("instance") is None:
            continue
        mid = mids[0] if mids else 0
        name = ours["mounts"].get(mid, {}).get("name", "") if mid else ""
        if len(mids) > 1:
            name = ", ".join(ours["mounts"].get(x, {}).get("name", str(x)) for x in mids)
        map_id, boss = _int(spec.get("instance")), str(spec.get("boss") or "")
        row = {"key": key, "mounts": mids, "name": name, "map": map_id, "boss": boss,
               "instance": "", "encounter": "", "match": "", "dungeon_encounter": "", "loot": ""}
        table.append(row)
        insts = game.instances_by_map.get(map_id, [])
        if not insts:
            out.append(finding("lockout", "unknown-instance", "error", mid, name,
                               "%s: no JournalInstance has MapID %d" % (label, map_id),
                               "check spec.instance (GetSavedInstanceInfo return 14)", key))
            row["instance"] = "(none)"
            continue
        row["instance"] = " / ".join(i["Name_lang"] for i in insts)
        encs = [e for i in insts for e in game.encounters_by_instance.get(_int(i["ID"]), [])]
        scored = [(boss_match(boss, e["Name_lang"]), e) for e in encs]
        rank = {"exact": 0, "prefix": 1, "contains": 2}
        scored = sorted([s for s in scored if s[0]], key=lambda s: rank[s[0]])
        if not scored:
            hidden = sorted({d["Name_lang"] for d in game.dungeon_encounters_by_map.get(map_id, [])
                             if boss_match(boss, d["Name_lang"])})
            if hidden:
                row["match"], row["dungeon_encounter"], row["loot"] = "DungeonEncounter only", " / ".join(hidden), "n/a"
                out.append(finding("lockout", "journal-hidden-boss", "warn", mid, name,
                                   "%s: %r is a DungeonEncounter of map %d (%s) but has no Encounter Journal "
                                   "page, so its loot cannot be checked" % (label, boss, map_id, " / ".join(hidden)),
                                   "verify the drop in game", key))
                continue
            dnames = sorted({d["Name_lang"] for d in game.dungeon_encounters_by_map.get(map_id, [])})
            out.append(finding("lockout", "unknown-boss", "error", mid, name,
                               "%s: %r is neither a JournalEncounter nor a DungeonEncounter of %s (map %d)"
                               % (label, boss, row["instance"], map_id),
                               "journal encounters: %s; DungeonEncounter: %s" % (
                                   ", ".join(e["Name_lang"] for e in encs), ", ".join(dnames)), key))
            row["match"] = "none"
            continue
        kind, enc = scored[0]
        row["encounter"], row["match"] = enc["Name_lang"], kind
        # The addon compares spec.boss with GetSavedInstanceEncounterInfo names using a
        # case-sensitive prefix test; DungeonEncounter / JournalEncounter names are the
        # game's candidates for those names.
        dnames = sorted({d["Name_lang"] for d in game.dungeon_encounters_by_map.get(map_id, [])
                         if boss_match(boss, d["Name_lang"])})
        row["dungeon_encounter"] = " / ".join(dnames)
        candidates = [e["Name_lang"] for _, e in scored] + dnames
        if not any(addon_match(boss, c) for c in candidates):
            out.append(finding("lockout", "addon-name-mismatch", "warn", mid, name,
                               "%s: %r only matches %s loosely; the addon's case-sensitive prefix "
                               "test would not match it" % (label, boss, " / ".join(sorted(set(candidates)))),
                               "set boss = %r" % (dnames[0] if dnames else enc["Name_lang"]), key))
        elif dnames and not any(addon_match(boss, d) for d in dnames):
            out.append(finding("lockout", "dungeon-encounter-name-differs", "warn", mid, name,
                               "%s: %r matches journal %r, but DungeonEncounter calls it %s; if the "
                               "saved-instance list uses that name, the addon's prefix test fails"
                               % (label, boss, enc["Name_lang"], " / ".join(repr(d) for d in dnames)),
                               "check with /azt dump; consider boss = %r" % dnames[0], key))
        elif kind != "exact":
            out.append(finding("lockout", "loose-boss-match", "info", mid, name,
                               "%s: %r matched journal %r (%s)" % (label, boss, enc["Name_lang"], kind),
                               "", key))
        enc_ids = {_int(e["ID"]) for _, e in scored}
        missing = []
        for m_id in mids:
            m = ours["mounts"].get(m_id)
            if m is None:
                continue
            hits = game.loot_rows(game.mount_items(m_id, m))
            here = [h for h in hits if _int(h["encounter"]["ID"]) in enc_ids]
            if here:
                row["loot"] = "yes (DifficultyMask %s)" % ", ".join(sorted({h["row"]["DifficultyMask"] for h in here}))
            else:
                missing.append(m_id)
                src_row = game.mounts.get(m_id)
                drops = source_fields(src_row["SourceText_lang"]).get("drop", []) if src_row else []
                if any(boss_match(boss, d) for d in drops):
                    out.append(finding("lockout", "source-text-only", "info", m_id, m.get("name", ""),
                                       "%s: not in %s's journal loot, but Mount.db2 source names the boss: %s"
                                       % (label, enc["Name_lang"], clean_source_text(src_row["SourceText_lang"])),
                                       "", key))
                    continue
                elsewhere = sorted({describe_loot(h) for h in hits})
                out.append(finding("lockout", "not-in-boss-loot", "warn", m_id, m.get("name", ""),
                                   "%s: %s (%s) loot has no item of this mount%s"
                                   % (label, enc["Name_lang"], row["instance"],
                                      "; it is in: " + "; ".join(elsewhere) if elsewhere else ""),
                                   "check the boss, or allowlist (e.g. timed chest)", key))
        if missing and not row["loot"]:
            row["loot"] = "no"
    return out, table


# --- candidates: farmable lockouts we do not track --------------------------------------

def covered_mounts(ours):
    """Mount IDs with a spec: Lockouts keys plus mounts of route rows with a BossLockouts entry."""
    covered = {k for k in ours["lockouts"] if isinstance(k, int)}
    for _, mids, _, _ in lockout_specs(ours):
        covered.update(mids)
    return covered


def lockout_candidates(ours, game):
    """Mounts whose items are in Encounter Journal loot but have no lockout spec and no
    Rarity quest. Grouped by expansion: {exp: [row]}."""
    tracked_maps = {_int(s.get("instance")) for _, _, _, s in lockout_specs(ours)
                    if isinstance(s, dict) and s.get("instance") is not None}
    route_mounts = {_int(r.get("mount")) for _, r in route_rows(ours["route"])}
    covered = covered_mounts(ours)
    groups = {}
    for mid in sorted(ours["mounts"]):
        m = ours["mounts"][mid]
        if m.get("unobtainable") or mid in covered or m.get("quest"):
            continue
        hits = game.loot_rows(game.mount_items(mid, m))
        if not hits:
            continue
        evidence = []
        for h in hits:
            inst = h["instance"]
            map_id = _int(inst["MapID"]) if inst else 0
            evidence.append({
                "encounter": h["encounter"]["Name_lang"],
                "instance": inst["Name_lang"] if inst else "?",
                "map": map_id,
                "difficulty_mask": h["row"]["DifficultyMask"],
                "tracked_map": map_id in tracked_maps,
            })
        src = game.mounts.get(mid)
        groups.setdefault(m.get("exp") or "(no expansion)", []).append({
            "mount": mid, "name": m.get("name", ""), "section": m.get("section", ""),
            "in_route": mid in route_mounts,
            "source": clean_source_text(src["SourceText_lang"]) if src else "",
            "evidence": evidence,
        })
    return groups


# Drop sources that are containers, activities or zone-wide pools, not a killable boss.
_NOT_A_BOSS = re.compile(
    r"\b(supplies|cache|chest|egg|trove|bag|strongbox|footlocker|gift|spoils|expeditions?|rifts?|"
    r"rare creatures|forbidden reach|zskera|dreamsurges|archives|torghast|pile|garbage|swarms|"
    r"spreading the light|shipping|desire|world drop|war chest|layers|crate|box|stash|coffer)\b", re.I)


def source_candidates(ours, game):
    """Mounts with no lockout spec, no Rarity quest and no Encounter Journal loot whose
    Mount.db2 source text names a creature to kill ("Drop: <NPC>"): rares, world bosses,
    holiday bosses and journal-less dungeon bosses. Grouped by expansion: {exp: [row]}."""
    by_name = {}
    for inst in game.instances.values():
        by_name.setdefault(norm_boss(inst["Name_lang"]), []).append(inst)
    covered = covered_mounts(ours)
    groups = {}
    for mid in sorted(ours["mounts"]):
        m = ours["mounts"][mid]
        if m.get("unobtainable") or mid in covered or m.get("quest"):
            continue
        row = game.mounts.get(mid)
        if not row or game.loot_rows(game.mount_items(mid, m)):
            continue
        fields = source_fields(row["SourceText_lang"])
        drops = [d for d in fields.get("drop", []) if not _NOT_A_BOSS.search(d)]
        if not drops:
            continue
        places = fields.get("zone", []) + fields.get("location", [])
        insts = [i for p in places for i in by_name.get(norm_boss(p), [])]
        encounters = []
        for inst in insts:
            map_id = _int(inst["MapID"])
            for d in game.dungeon_encounters_by_map.get(map_id, []):
                if any(boss_match(x, d["Name_lang"]) for x in drops):
                    encounters.append("%s (DungeonEncounter %s)" % (d["Name_lang"], d["ID"]))
        if fields.get("holiday"):
            hint = "holiday drop (an `lfg` spec if it is the holiday dungeon boss)"
        elif insts:
            hint = "instance boss"
        else:
            hint = "world rare / boss (needs a tracking quest ID)"
        groups.setdefault(m.get("exp") or "(no expansion)", []).append({
            "mount": mid, "name": m.get("name", ""), "section": m.get("section", ""),
            "drop": ", ".join(drops), "where": ", ".join(places),
            "instance": ", ".join("%s (map %s)" % (i["Name_lang"], i["MapID"]) for i in insts),
            "encounter": ", ".join(encounters), "holiday": ", ".join(fields.get("holiday", [])),
            "hint": hint, "source": clean_source_text(row["SourceText_lang"]),
        })
    return groups


# --- report ------------------------------------------------------------------------------

def _md(s):
    return str(s).replace("|", "\\|").replace("\n", " ")


def summarise(findings):
    counts = {c: {s: 0 for s in SEVERITIES} for c in CHECKS}
    for f in findings:
        counts[f["check"]][f["severity"]] += 1
    totals = {s: sum(counts[c][s] for c in CHECKS) for s in SEVERITIES}
    return counts, totals


def render_report(build, findings, lock_table, candidates, source_cands, ours, expansions=()):
    counts, totals = summarise(findings)
    lines = [
        "# Data verification",
        "",
        "Generated by `python tools/verify_data.py`. Do not edit by hand; re-run the tool.",
        "",
        "- Verified against Retail build **%s** (wago.tools DB2 CSVs: %s)." % (build, ", ".join(TABLES)),
        "- Generated %s." % datetime.date.today().isoformat(),
        "- Our data: %d mounts, %d route kill rows, %d lockout specs (+%d per-boss)." % (
            len(ours["mounts"]), len(route_rows(ours["route"])),
            len(ours["lockouts"]), len(ours["boss_lockouts"])),
        "- Allowlist: `tools/verify_allow.json` (allowlisted findings are shown as info with their reason).",
        "- Re-run: `python tools/verify_data.py` (latest build), `--build <version>` to pin one,",
        "  `--offline` to reuse `tools/.cache/db2/`. Exit code 1 while any error is not allowlisted.",
        "- Matching: boss names are compared case-, punctuation- and leading-\"The\"-insensitively;",
        "  a whole-word prefix (\"Fyrakk\" ~ \"Fyrakk the Blazing\") or contained run (\"Deios\" ~",
        "  \"Chrono-Lord Deios\") also matches. A mount's items are its `item` plus every item whose",
        "  ItemEffect teaches the mount's spell.",
        "",
        "## Summary",
        "",
        "| Check | Errors | Warnings | Info |",
        "|---|---:|---:|---:|",
    ]
    for c in CHECKS:
        lines.append("| %s | %d | %d | %d |" % (CHECK_TITLES[c], counts[c]["error"], counts[c]["warn"], counts[c]["info"]))
    lines.append("| **Total** | **%d** | **%d** | **%d** |" % (totals["error"], totals["warn"], totals["info"]))
    lines.append("")
    for c in CHECKS:
        lines += ["## " + CHECK_TITLES[c], ""]
        mine = [f for f in findings if f["check"] == c]
        if not mine:
            lines += ["No findings.", ""]
            continue
        for sev in SEVERITIES:
            group = [f for f in mine if f["severity"] == sev]
            if not group:
                continue
            lines += ["### %s (%d)" % ({"error": "Errors", "warn": "Warnings", "info": "Info"}[sev], len(group)), "",
                      "| Kind | Mount | Detail | Suggestion |", "|---|---|---|---|"]
            for f in sorted(group, key=lambda f: (f["kind"], f["mount"], f["key"])):
                sugg = f["suggestion"]
                if f["allowed"]:
                    sugg = "allowlisted (%s): %s" % (f["original_severity"], f["allowed"])
                lines.append("| %s | %s %s | %s | %s |" % (
                    f["kind"], f["mount"], _md(f["name"]), _md(f["detail"]), _md(sugg)))
            lines.append("")
    lines += [
        "## Lockout specs resolved against the journal",
        "",
        "Each instance spec in `Data/Lockouts.lua`: the JournalInstance with that MapID, the",
        "JournalEncounter its boss name matches (exact / prefix / contains), the matching",
        "DungeonEncounter names for that map, and whether the mount is in that encounter's loot.",
        "",
        "| Spec | Mount | Map | Journal instance | Journal encounter | Match | DungeonEncounter | In loot |",
        "|---|---|---:|---|---|---|---|---|",
    ]
    for r in lock_table:
        lines.append("| %s | %s | %d | %s | %s | %s | %s | %s |" % (
            _md(r["key"]), _md(r["name"]), r["map"], _md(r["instance"]), _md(r["encounter"]),
            r["match"], _md(r["dungeon_encounter"]), r["loot"]))
    lines += [
        "",
        "## Candidate lockouts with no spec",
        "",
        "Mounts with no entry in `Data/Lockouts.lua` and no Rarity `quest` in `Data/Mounts.lua`",
        "(unobtainable mounts skipped) that look like a daily or weekly kill.",
        "",
        "### From Encounter Journal loot",
        "",
        "The mount's item is JournalEncounterItem loot. \"Tracked map\" means another spec already",
        "uses that MapID. DifficultyMask is the raw JournalEncounterItem value (-1 = every difficulty).",
        "",
    ]
    order = {e: i for i, e in enumerate(expansions)}
    if not candidates:
        lines += ["None: every obtainable mount with Encounter Journal loot has a spec or a quest.", ""]
    for exp in sorted(candidates, key=lambda e: (order.get(e, 99), e)):
        lines += ["#### %s (%d)" % (exp, len(candidates[exp])), "",
                  "| Mount | In route | Encounter (instance) | Map | DifficultyMask | Tracked map | Mount.db2 source |",
                  "|---|---|---|---:|---|---|---|"]
        for c in candidates[exp]:
            for i, ev in enumerate(c["evidence"]):
                head = "%d %s" % (c["mount"], _md(c["name"])) if i == 0 else ""
                lines.append("| %s | %s | %s (%s) | %d | %s | %s | %s |" % (
                    head, ("yes" if c["in_route"] else "no") if i == 0 else "",
                    _md(ev["encounter"]), _md(ev["instance"]), ev["map"], ev["difficulty_mask"],
                    "yes" if ev["tracked_map"] else "no", _md(c["source"]) if i == 0 else ""))
        lines.append("")
    lines += [
        "### From Mount.db2 source text",
        "",
        "Not Encounter Journal loot, but the source text names a creature to kill (`Drop: <NPC>`;",
        "containers, eggs, caches and activity pools are left out). The hint is a guess from the",
        "source text: holiday bosses fit an `lfg` spec, instance bosses an `instance` spec, world",
        "rares need the quest ID the game flags on a kill.",
        "",
    ]
    if not source_cands:
        lines += ["None.", ""]
    for exp in sorted(source_cands, key=lambda e: (order.get(e, 99), e)):
        lines += ["#### %s (%d)" % (exp, len(source_cands[exp])), "",
                  "| Mount | Drop | Where | Instance (map) | DungeonEncounter | Hint |",
                  "|---|---|---|---|---|---|"]
        for c in source_cands[exp]:
            lines.append("| %d %s | %s | %s | %s | %s | %s |" % (
                c["mount"], _md(c["name"]), _md(c["drop"]),
                _md(c["where"] or ("Holiday: " + c["holiday"] if c["holiday"] else "")),
                _md(c["instance"]), _md(c["encounter"]), c["hint"]))
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def run(ours, game, allow):
    findings = check_identity(ours, game) + check_route(ours, game)
    lock_findings, lock_table = check_lockouts(ours, game)
    findings = apply_allowlist(findings + lock_findings, allow)
    return findings, lock_table, lockout_candidates(ours, game), source_candidates(ours, game)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--build", help="DB2 build to verify against (default: latest Retail on wago.tools)")
    ap.add_argument("--offline", action="store_true", help="use the newest cached build, no network")
    ap.add_argument("--cache", default=CACHE)
    ap.add_argument("--data", default=DATA, help="addon Data/ directory")
    ap.add_argument("--allow", default=ALLOW_PATH)
    ap.add_argument("--report", default=REPORT_PATH, help="markdown report path ('-' for stdout)")
    ap.add_argument("--json", help="also write all findings as JSON to this path")
    args = ap.parse_args(argv)

    build = args.build
    if not build:
        if args.offline:
            builds = cached_builds(args.cache)
            if not builds:
                sys.exit("offline: no complete build in %s" % args.cache)
            build = builds[-1]
        else:
            build = latest_build()
    folder = fetch_tables(build, args.cache, offline=args.offline)
    ours = load_our_data(args.data)
    game = Game(folder)
    findings, lock_table, candidates, source_cands = run(ours, game, load_allowlist(args.allow))
    report = render_report(build, findings, lock_table, candidates, source_cands, ours,
                           ours.get("expansions") or ())
    if args.report == "-":
        sys.stdout.write(report)
    else:
        with open(args.report, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(report)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump({"build": build, "findings": findings, "lockouts": lock_table,
                       "candidates": candidates, "source_candidates": source_cands},
                      fh, indent=1, default=list)
    _, totals = summarise(findings)
    print("build %s: %d errors, %d warnings, %d info -> %s"
          % (build, totals["error"], totals["warn"], totals["info"], args.report), file=sys.stderr)
    return 1 if totals["error"] else 0


if __name__ == "__main__":
    sys.exit(main())
