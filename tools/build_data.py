#!/usr/bin/env python3
"""Generates Data/Mounts.lua and Data/Route.lua from SimpleArmory (MIT) and Rarity (GPL-2.0).

Usage:
    python tools/build_data.py            # build from the commits pinned in tools/sources.json
    python tools/build_data.py --update   # pin the current master commits, then build

Downloads go to tools/.cache/ (gitignored) over HTTPS only (api.github.com,
raw.githubusercontent.com). Standard library only.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
SOURCES_PATH = os.path.join(TOOLS, "sources.json")
CACHE = os.path.join(TOOLS, ".cache")
DATA = os.path.join(ROOT, "Data")

SA_FILES = ("static/data/mounts.json", "static/data/planner.json", "LICENSE")
RARITY_DIR = "DB/Mounts/"
RARITY_CONSTANTS = "DB/SharedConstants.lua"

EXPANSIONS = [
    "Classic",
    "The Burning Crusade",
    "Wrath of the Lich King",
    "Cataclysm",
    "Mists of Pandaria",
    "Warlords of Draenor",
    "Legion",
    "Battle for Azeroth",
    "Shadowlands",
    "Dragonflight",
    "The War Within",
    "Midnight",
]

# --- classification ---------------------------------------------------------------

JOURNAL_SECTIONS = {
    "Dungeon Drop": "dungeon",
    "Challenge Mode": "dungeon",
    "Raid Drop": "raid",
    "Raid Renown": "raid",
    "Rare Spawn": "world",
    "World Boss": "world",
    "Zone Drop": "world",
    "Nemesis Drop": "world",
    "Prey Drop": "world",
    "Tormentors": "world",
    "Treasure": "world",
    "Reputation": "reputation",
    "Paragon Reputation": "reputation",
    "Renown": "reputation",
    "Cenarion Expedition": "reputation",
    "Kurenai/The Mag'har": "reputation",
    "Netherwing": "reputation",
    "Sha'tari Skyguard": "reputation",
    "Golden Lotus": "reputation",
    "Order of the Cloud Serpent": "reputation",
    "Shado-Pan": "reputation",
    "The Tillers": "reputation",
    "Vendor": "vendor",
    "Kun-Lai Vendor": "vendor",
}

FACTIONS = {"A": "Alliance", "H": "Horde"}

HOLIDAYS = {
    "Hallow's End": "hallowsend",
    "Brewfest": "brewfest",
    "Love is in the Air": "loveisintheair",
    "Noblegarden": "noblegarden",
    "Winter Veil": "winterveil",
    "Feast of Winter Veil": "winterveil",
    "Lunar Festival": "lunarfestival",
    "Midsummer Fire Festival": "midsummer",
    "Midsummer": "midsummer",
    "Darkmoon Faire": "darkmoon",
    "Timewalking": "timewalking",
    "Anniversary": "anniversary",
}


def classify(category, subcat):
    """Map a SimpleArmory (category, subcat) pair to (tab, section)."""
    if category in EXPANSIONS:
        if subcat == "Achievement":
            return "misc", "achievement"
        return "journal", JOURNAL_SECTIONS.get(subcat, "other")
    if category == "Professions":
        return "misc", "profession"
    if category == "Promotion" and subcat == "Blizzard Store":
        return "misc", "shop"
    if category in ("Limited Time", "Past Limited Time") and subcat.startswith("Trading Post"):
        return "misc", "tradingpost"
    if category == "World Events":
        return "holiday", HOLIDAYS.get(subcat, "other")
    return "misc", "other"


# --- loading ------------------------------------------------------------------------

def _read_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def load_sa(mounts_path, planner_path):
    """Returns {"mounts": [category, ...], "planner": {"steps": [...]}}."""
    return {"mounts": _read_json(mounts_path), "planner": _read_json(planner_path)}


def _to_int(value):
    """int for ints and digit strings, else None."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, str) and value.strip().isdigit():
        return int(value.strip())
    return None


def _number(text):
    f = float(text)
    return int(f) if f.is_integer() and "." not in text else f


# --- Rarity parsing -------------------------------------------------------------------

_ENTRY_START = re.compile(r'\[\s*"((?:[^"\\\n]|\\.)*)"\s*\]\s*=\s*\{')


def _skip_long_bracket(text, i):
    """If text[i:] opens a Lua long bracket ([[ or [==[), return the index after it closes, else None."""
    m = re.match(r"\[(=*)\[", text[i:i + 64])
    if not m:
        return None
    close = "]" + m.group(1) + "]"
    end = text.find(close, i + m.end())
    return len(text) if end < 0 else end + len(close)


def _skip_code_noise(text, i):
    """If a comment or string starts at text[i], return the index just after it, else None."""
    ch = text[i]
    if ch == "-" and text.startswith("--", i):
        j = _skip_long_bracket(text, i + 2)
        if j is not None:
            return j
        nl = text.find("\n", i)
        return len(text) if nl < 0 else nl + 1
    if ch in "\"'":
        j = i + 1
        while j < len(text) and text[j] != ch and text[j] != "\n":
            j += 2 if text[j] == "\\" else 1
        return j + 1
    if ch == "[":
        return _skip_long_bracket(text, i)
    return None


def _match_brace(text, start):
    """`start` is just past an opening '{'; returns the index of the matching '}' (Lua-aware)."""
    depth, i, n = 1, start, len(text)
    while i < n:
        j = _skip_code_noise(text, i)
        if j is not None:
            i = j
            continue
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return n


def _iter_blocks(text):
    """Yields (name, body) for each top-level `["Name"] = { ... }` entry; nested entries, comments
    and strings are skipped."""
    i, n = 0, len(text)
    while i < n:
        if text[i] == "[":
            m = _ENTRY_START.match(text, i)
            if m:
                end = _match_brace(text, m.end())
                yield m.group(1), text[m.end():end]
                i = end + 1
                continue
        j = _skip_code_noise(text, i)
        i = j if j is not None else i + 1


def _first_int(pattern, body):
    m = re.search(pattern, body)
    return int(m.group(1)) if m else None


def parse_map_ids(text):
    """Parses `C.UIMAPIDS = { NAME = N, ... }` from Rarity's DB/SharedConstants.lua into {NAME: N}."""
    m = re.search(r"\bUIMAPIDS\s*=\s*\{", text)
    if not m:
        return {}
    body = text[m.end():_match_brace(text, m.end())]
    body = re.sub(r"--[^\n]*", "", body)
    return {k: int(v) for k, v in re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\d+)", body)}


_MAP_CONST = "CONSTANTS.UIMAPIDS."


def _resolve_map(token, map_ids):
    """Map token (digits or CONSTANTS.UIMAPIDS.NAME) -> uiMapID, or None. 0 (Rarity's 'anywhere') is None."""
    if token.isdigit():
        value = int(token)
    elif token.startswith(_MAP_CONST):
        value = (map_ids or {}).get(token[len(_MAP_CONST):])
    else:
        value = None
    return value or None


def _first_coords(body, map_ids=None):
    """First coord entry with a resolvable map and x/y; else {"m": first resolvable map}; else None."""
    m = re.search(r"\bcoords\s*=\s*\{", body)
    if not m:
        return None
    end = _match_brace(body, m.end())
    inner = body[m.end():end]
    map_only = None
    for blk in re.finditer(r"\{([^{}]*)\}", inner):
        fields = blk.group(1)
        mm = re.search(r"\bm\s*=\s*([A-Za-z_][A-Za-z0-9_.]*|\d+)", fields)
        mapid = _resolve_map(mm.group(1), map_ids) if mm else None
        if mapid is None:
            continue
        mx = re.search(r"\bx\s*=\s*(\d+(?:\.\d+)?)", fields)
        my = re.search(r"\by\s*=\s*(\d+(?:\.\d+)?)", fields)
        if mx and my:
            return {"m": mapid, "x": float(mx.group(1)), "y": float(my.group(1))}
        if map_only is None:
            map_only = {"m": mapid}
    return map_only


def parse_rarity(lua_texts, map_ids=None):
    """Parses Rarity DB/Mounts/*.lua texts into {spell_id: {chance, quest, coords, item, rarityName}}.

    `map_ids` ({NAME: uiMapID}, see parse_map_ids) resolves CONSTANTS.UIMAPIDS.NAME map references.
    The first entry seen for a spell ID wins.
    """
    out = {}
    for text in lua_texts:
        for name, body in _iter_blocks(text):
            spell = _first_int(r"\bspellId\s*=\s*(\d+)", body)
            if spell is None or spell in out:
                continue
            rec = {"rarityName": name}
            item = _first_int(r"\bitemId\s*=\s*(\d+)", body)
            if item is not None:
                rec["item"] = item
            cm = re.search(r"\bchance\s*=\s*(\d+(?:\.\d+)?)", body)
            if cm:
                rec["chance"] = _number(cm.group(1))
            quest = _first_int(r"\bquestId\s*=\s*\{?\s*(\d+)", body)
            if quest is not None:
                rec["quest"] = quest
            coords = _first_coords(body, map_ids)
            if coords:
                rec["coords"] = coords
            out[spell] = rec
    return out


# --- building -----------------------------------------------------------------------

def _categories(sa):
    return sa["mounts"] if isinstance(sa, dict) else sa


def build_mounts(sa, rarity, stats=None):
    """Returns {mountID: mount dict}. Duplicates: a later sighting replaces an earlier one only when
    the earlier one is misc/other (or flagged `dupe`) and the later one is not; tradingNow is kept
    if any sighting is a current Trading Post entry.

    Flags merged across all sightings: `unobtainable=true` only if every sighting is notObtainable;
    `faction` only if every sighting carries the same `side` (a sighting without `side` counts as
    both factions)."""
    mounts = {}
    chosen_weak = {}
    sides = {}
    obtainable = {}
    for cat in _categories(sa):
        cname = cat.get("name") or ""
        for sub in cat.get("subcats") or []:
            sname = sub.get("name") or ""
            tab, section = classify(cname, sname)
            for item in sub.get("items") or []:
                mid = _to_int(item.get("ID"))
                if mid is None:
                    continue
                rec = {
                    "name": item.get("name"),
                    "spell": _to_int(item.get("spellid")),
                    "item": _to_int(item.get("itemId")),
                    "icon": None if item.get("icon") is None else str(item.get("icon")),
                    "exp": cname if cname in EXPANSIONS else None,
                    "tab": tab,
                    "section": section,
                    "group": sname,
                }
                trading_now = cname == "Limited Time" and section == "tradingpost"
                weak = (tab, section) == ("misc", "other") or bool(item.get("dupe"))
                side = FACTIONS.get(item.get("side"))
                sides.setdefault(mid, set()).update([side] if side else FACTIONS.values())
                obtainable[mid] = obtainable.get(mid, False) or not item.get("notObtainable")
                if mid in mounts:
                    if stats is not None:
                        stats["duplicates"] = stats.get("duplicates", 0) + 1
                    prev = mounts[mid]
                    if chosen_weak[mid] and not weak:
                        if prev.get("tradingNow"):
                            rec["tradingNow"] = True
                        if trading_now:
                            rec["tradingNow"] = True
                        mounts[mid] = rec
                        chosen_weak[mid] = weak
                    elif trading_now:
                        prev["tradingNow"] = True
                    continue
                if trading_now:
                    rec["tradingNow"] = True
                mounts[mid] = rec
                chosen_weak[mid] = weak

    for mid, rec in mounts.items():
        if not obtainable[mid]:
            rec["unobtainable"] = True
        if len(sides[mid]) == 1:
            rec["faction"] = next(iter(sides[mid]))

    joined = 0
    for rec in mounts.values():
        r = rarity.get(rec["spell"]) if rec["spell"] is not None else None
        if not r:
            continue
        joined += 1
        for key in ("chance", "quest", "coords"):
            if key in r:
                rec[key] = r[key]
    if stats is not None:
        stats["joined"] = joined
        stats["rarity_entries"] = len(rarity)
        sa_spells = {rec["spell"] for rec in mounts.values()}
        stats["rarity_unmatched"] = sum(1 for s in rarity if s not in sa_spells)
    return {k: {kk: vv for kk, vv in v.items() if vv is not None} for k, v in mounts.items()}


_NODE_KEYS = (
    ("title", "title"),
    ("type", "type"),
    ("capital", "capital"),
    ("startStep", "startStep"),
    ("isAlliance", "alliance"),
    ("isHorde", "horde"),
    ("notes", "notes"),
    ("unavailable", "unavailable"),
)


def _boss(b):
    out = {"mount": _to_int(b.get("ID")), "boss": b.get("name"), "note": b.get("note")}
    if b.get("isAlliance"):
        out["alliance"] = True
    if b.get("isHorde"):
        out["horde"] = True
    return {k: v for k, v in out.items() if v is not None}


def _node(n):
    if not isinstance(n, dict):
        return None
    out = {}
    for src, dst in _NODE_KEYS:
        v = n.get(src)
        if v is None or v is False or v == "":
            continue
        out[dst] = v
    bosses = [_boss(b) for b in n.get("bosses") or [] if isinstance(b, dict)]
    bosses = [b for b in bosses if "mount" in b]
    if bosses:
        out["bosses"] = bosses
    steps = [s for s in (_node(c) for c in n.get("steps") or []) if s]
    if steps:
        out["steps"] = steps
    if not out.get("title") and not bosses and not steps:
        return None
    return out


def build_route(planner):
    """SimpleArmory planner tree -> list of nodes with renamed keys."""
    steps = planner.get("steps", []) if isinstance(planner, dict) else planner
    return [s for s in (_node(n) for n in steps) if s]


# --- Lua emission ---------------------------------------------------------------------

_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}
# Field order for mount records; anything else follows alphabetically.
_MOUNT_ORDER = ["name", "spell", "item", "icon", "exp", "tab", "section", "group", "tradingNow",
                "faction", "unobtainable", "chance", "quest", "coords"]
_NODE_ORDER = ["title", "type", "capital", "startStep", "alliance", "horde", "unavailable", "notes",
               "mount", "boss", "note", "m", "x", "y", "bosses", "steps"]


def lua_string(s):
    out = ['"']
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append("\\%03d" % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def _key(k):
    if isinstance(k, str) and _IDENT.match(k) and k not in _LUA_KEYWORDS:
        return k
    if isinstance(k, str):
        return "[" + lua_string(k) + "]"
    return "[" + lua_value(k) + "]"


def _ordered(d, order):
    rank = {k: i for i, k in enumerate(order)}
    return sorted(d.items(), key=lambda kv: (rank.get(kv[0], len(order)), str(kv[0])))


def lua_value(v, indent="", order=_NODE_ORDER):
    if v is None:
        return "nil"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, str):
        return lua_string(v)
    if isinstance(v, (list, tuple)):
        if not v:
            return "{}"
        if all(not isinstance(x, (dict, list, tuple)) for x in v):
            return "{ " + ", ".join(lua_value(x) for x in v) + " }"
        inner = indent + "  "
        parts = [inner + lua_value(x, inner, order) + ",\n" for x in v]
        return "{\n" + "".join(parts) + indent + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        flat = all(not isinstance(x, (dict, list, tuple)) for x in v.values())
        items = _ordered(v, order)
        if flat:
            return "{ " + ", ".join("%s = %s" % (_key(k), lua_value(x)) for k, x in items) + " }"
        inner = indent + "  "
        parts = ["%s%s = %s,\n" % (inner, _key(k), lua_value(x, inner, order)) for k, x in items]
        return "{\n" + "".join(parts) + indent + "}"
    raise TypeError("cannot emit %r" % (v,))


def license_copyright(license_text):
    """The first 'Copyright ...' line of a license text, or None."""
    for line in license_text.splitlines():
        if line.strip().lower().startswith("copyright"):
            return line.strip()
    return None


def _header(sources, copyright=None):
    sources = sources or {}
    sa = sources.get("simplearmory", {})
    ra = sources.get("rarity", {})
    mit = "MIT License, " + copyright if copyright else "MIT License"
    return (
        "-- GENERATED by tools/build_data.py — do not edit\n"
        "-- Source: SimpleArmory https://github.com/%s commit %s\n"
        "--   %s (full text: Data/LICENSE-SimpleArmory.txt)\n"
        "-- Source: Rarity https://github.com/%s commit %s\n"
        "--   GPL-2.0 (drop chances, quest IDs, coordinates from DB/Mounts/*.lua)\n"
        % (sa.get("repo", "kevinclement/SimpleArmory"), sa.get("commit", "unknown"), mit,
           ra.get("repo", "WowRarity/Rarity"), ra.get("commit", "unknown"))
    )


def _mount_line(mid, rec):
    fields = []
    for k, v in _ordered(rec, _MOUNT_ORDER):
        if v is None:
            continue
        fields.append("%s = %s" % (_key(k), lua_value(v)))
    return "  [%d] = { %s },\n" % (mid, ", ".join(fields))


def emit_lua(mounts=None, route=None, sources=None, copyright=None):
    """Full Lua file text for Data/Mounts.lua (mounts=...) or Data/Route.lua (route=...).
    `copyright` is SimpleArmory's copyright line (see license_copyright) for the header."""
    out = [_header(sources, copyright), "\n", "local ADDON, ns = ...\n", "ns.Data = ns.Data or {}\n", "\n"]
    if mounts is not None:
        out.append("ns.Data.Expansions = " + lua_value(EXPANSIONS) + "\n\n")
        out.append("ns.Data.Mounts = {\n")
        for mid in sorted(mounts):
            out.append(_mount_line(mid, mounts[mid]))
        out.append("}\n")
    if route is not None:
        out.append("ns.Data.Route = " + lua_value(list(route)) + "\n")
    return "".join(out)


# --- network / main ---------------------------------------------------------------------

def _should_retry(code, headers):
    """Retry 429, and 403 only when it is a rate limit (X-RateLimit-Remaining is "0")."""
    if code == 429:
        return True
    return code == 403 and (headers or {}).get("X-RateLimit-Remaining") == "0"


def _http_get(url, accept=None):
    headers = {"User-Agent": "AzerothTrail-build-data"}
    if accept:
        headers["Accept"] = accept
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = "Bearer " + token
    delay = 5
    for attempt in range(6):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as resp:
                return resp.read()
        except urllib.error.HTTPError as exc:
            if _should_retry(exc.code, exc.headers) and attempt < 5:
                reset = exc.headers.get("X-RateLimit-Reset")
                wait = delay
                if reset and reset.isdigit():
                    wait = max(delay, min(900, int(reset) - int(time.time()) + 1))
                print("rate limited (%d) on %s, waiting %ds" % (exc.code, url, wait))
                time.sleep(wait)
                delay *= 2
                continue
            raise
        except urllib.error.URLError:
            if attempt < 5:
                time.sleep(delay)
                delay *= 2
                continue
            raise
    raise RuntimeError("unreachable")


def _api_json(path):
    return json.loads(_http_get("https://api.github.com/" + path, "application/vnd.github+json"))


def resolve_master(repo):
    return _api_json("repos/%s/commits/master" % repo)["sha"]


def _cached(repo, commit, path):
    dest = os.path.join(CACHE, repo.replace("/", "_"), commit, *path.split("/"))
    if not os.path.exists(dest):
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        data = _http_get("https://raw.githubusercontent.com/%s/%s/%s" % (repo, commit, path))
        with open(dest + ".part", "wb") as fh:
            fh.write(data)
        os.replace(dest + ".part", dest)
    return dest


def _rarity_paths(repo, commit):
    listing = os.path.join(CACHE, repo.replace("/", "_"), commit, "tree.json")
    if not os.path.exists(listing):
        os.makedirs(os.path.dirname(listing), exist_ok=True)
        tree = _api_json("repos/%s/git/trees/%s?recursive=1" % (repo, commit))
        if tree.get("truncated"):
            raise RuntimeError("GitHub tree listing truncated for %s@%s" % (repo, commit))
        with open(listing, "w", encoding="utf-8") as fh:
            json.dump(tree, fh)
    with open(listing, encoding="utf-8") as fh:
        tree = json.load(fh)
    return sorted(e["path"] for e in tree["tree"]
                  if e.get("type") == "blob" and e["path"].startswith(RARITY_DIR) and e["path"].endswith(".lua"))


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--update", action="store_true", help="pin current master commits in tools/sources.json")
    args = ap.parse_args(argv)

    sources = _read_json(SOURCES_PATH) if os.path.exists(SOURCES_PATH) else {
        "simplearmory": {"repo": "kevinclement/SimpleArmory", "commit": None},
        "rarity": {"repo": "WowRarity/Rarity", "commit": None},
    }
    if args.update:
        for key in ("simplearmory", "rarity"):
            sources[key]["commit"] = resolve_master(sources[key]["repo"])
    for key in ("simplearmory", "rarity"):
        if not sources.get(key, {}).get("commit"):
            sys.exit("no commit pinned for %s; run with --update" % key)

    generate(sources)

    if args.update:
        # Only pin the new commits once the data built from them was written successfully.
        with open(SOURCES_PATH, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(sources, fh, indent=2)
            fh.write("\n")
        print("pinned %s" % ", ".join("%s@%s" % (v["repo"], v["commit"]) for v in sources.values()))
    return 0


def generate(sources):
    """Downloads (cached) the pinned sources and writes Data/Mounts.lua, Data/Route.lua and
    Data/LICENSE-SimpleArmory.txt."""
    sa_repo, sa_commit = sources["simplearmory"]["repo"], sources["simplearmory"]["commit"]
    ra_repo, ra_commit = sources["rarity"]["repo"], sources["rarity"]["commit"]
    mounts_path, planner_path, license_path = (_cached(sa_repo, sa_commit, p) for p in SA_FILES)
    sa = load_sa(mounts_path, planner_path)
    with open(license_path, encoding="utf-8") as fh:
        license_text = fh.read()
    copyright = license_copyright(license_text)
    if not copyright:
        raise RuntimeError("no copyright line in SimpleArmory LICENSE at %s" % sa_commit)

    with open(_cached(ra_repo, ra_commit, RARITY_CONSTANTS), encoding="utf-8") as fh:
        map_ids = parse_map_ids(fh.read())
    if not map_ids:
        raise RuntimeError("no UIMAPIDS found in %s at %s" % (RARITY_CONSTANTS, ra_commit))
    texts = []
    rarity_files = _rarity_paths(ra_repo, ra_commit)
    for p in rarity_files:
        with open(_cached(ra_repo, ra_commit, p), encoding="utf-8") as fh:
            texts.append(fh.read())
    rarity = parse_rarity(texts, map_ids)

    stats = {}
    mounts = build_mounts(sa, rarity, stats)
    route = build_route(sa["planner"])

    _write(os.path.join(DATA, "Mounts.lua"), emit_lua(mounts=mounts, sources=sources, copyright=copyright))
    _write(os.path.join(DATA, "Route.lua"), emit_lua(route=route, sources=sources, copyright=copyright))
    _write(os.path.join(DATA, "LICENSE-SimpleArmory.txt"), license_text)

    counts = {}
    for rec in mounts.values():
        k = (rec["tab"], rec["section"])
        counts[k] = counts.get(k, 0) + 1
    print("mounts: %d (duplicate sightings merged: %d)" % (len(mounts), stats.get("duplicates", 0)))
    for (tab, section), c in sorted(counts.items()):
        print("  %-8s %-14s %d" % (tab, section, c))
    coords = [r["coords"] for r in mounts.values() if "coords" in r]
    print("rarity: %d files, %d map constants, %d entries, %d joined, %d unmatched"
          % (len(rarity_files), len(map_ids), stats["rarity_entries"], stats["joined"], stats["rarity_unmatched"]))
    print("coords: %d full, %d map-only" % (sum("x" in c for c in coords), sum("x" not in c for c in coords)))
    print("unobtainable: %d; faction: %d Alliance, %d Horde" % (
        sum(1 for r in mounts.values() if r.get("unobtainable")),
        sum(1 for r in mounts.values() if r.get("faction") == "Alliance"),
        sum(1 for r in mounts.values() if r.get("faction") == "Horde")))


if __name__ == "__main__":
    sys.exit(main())
