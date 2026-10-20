#!/usr/bin/env python3
"""Writes Data/Spots.lua: where to find the NPC behind each mount.

For every mount in Data/Mounts.lua: the NPCs that drop or sell it, each with
every spawn point AllTheThings lists (a rare's several spawn spots, a mount
sold by vendors in several towns), its daily-kill quest when it has one, and
its faction when only one faction can use it.

Sources:
  * AllTheThings (https://github.com/ATTWoWAddon/AllTheThings, MIT, pinned in
    tools/sources.json "allthethings"): its database lists each mount under
    the NPC that drops or sells it, with that NPC's coordinates
    (`n(npcID, {coords = {[uiMapID] = {{x, y}, ...}}, questID =, isDaily =, r =,
    g = { mnt(spellID, ...) | i(itemID, ...) }})`).
  * Blizzard's Mount.db2 source text (tools/verify_data.py cache, build pinned
    in tools/sources.json "db2build") and UiMap.db2: the NPC names and the
    zones the game itself gives. When the source names zones, only the NPCs
    standing in those zones are kept (AllTheThings also lists, say, a racial
    mount's vendor in every capital), and each is named after the source's
    "Vendor:" / "Drop:" line of its zone.

    python tools/build_spots.py              # pinned commits, cached files
    python tools/build_spots.py --offline    # cache only
"""

import argparse
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_data  # noqa: E402  (_cached, lua_string)
import verify_data  # noqa: E402  (fetch_tables, read_csv)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Data", "Spots.lua")
MOUNTS = os.path.join(ROOT, "Data", "Mounts.lua")
LICENSE_OUT = os.path.join(ROOT, "Data", "LICENSE-AllTheThings.txt")
SOURCES = os.path.join(ROOT, "tools", "sources.json")

ATT_CATEGORIES = (
    "BlackMarket", "Character", "Craftables", "Delves", "ExpansionFeatures", "GroupFinder",
    "Holidays", "Housing", "InGameShop", "Instances", "PVP", "Professions", "Promotions",
    "Secrets", "Sourceless", "TradingPost", "Unsorted", "WorldDrops", "WorldEvents", "Zones",
)  # NeverImplemented.lua is left out on purpose
MAX_NPCS = 12  # per mount (world-wide vendors of a common mount)
ZONE, CONTINENT = 3, 2
FACTIONS = {"1": "Horde", "2": "Alliance"}

# Tokens that matter while walking AllTheThings' Lua: strings and comments
# (skipped), calls `name(` and bare parentheses.
_TOKEN = re.compile(r'"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\'|--[^\n]*|([A-Za-z_][A-Za-z0-9_.]*)\(|\(|\)')
_NUMBER = re.compile(r"\s*(-?\d+)")


class Frame:
    __slots__ = ("kind", "npc", "start", "end")

    def __init__(self, kind, npc, start):
        self.kind, self.npc, self.start, self.end = kind, npc, start, None


def scan(text, spells, items, frames=None):
    """Walks one AllTheThings file -> list of (mountKey, [enclosing call frames,
    innermost first], index just past the mount entry's "("). mountKey is ("spell",
    id) for mnt(id) with id in `spells`, ("item", id) for i(id) with id in `items`.
    Frames get `end` (the index of their closing parenthesis) once closed; every NPC
    frame (n(id, ...)) is appended to `frames` when given."""
    stack, found = [], []
    for m in _TOKEN.finditer(text):
        tok = m.group(0)
        if tok[0] in "\"'-":
            continue
        name = m.group(1)
        if tok == ")":
            if stack:
                frame = stack.pop()
                if frame is not None:
                    frame.end = m.start()
            continue
        if name is None:  # a bare "("
            stack.append(None)
            continue
        num = _NUMBER.match(text, m.end())
        value = int(num.group(1)) if num else None
        frame = Frame(name, value, m.end())
        stack.append(frame)
        if name == "n" and value is not None and value > 0:
            if frames is not None:
                frames.append(frame)
            continue
        key = None
        if name == "mnt" and value in spells:
            key = ("spell", value)
        elif name == "i" and value in items:
            key = ("item", value)
        if key:
            found.append((key, [f for f in reversed(stack[:-1]) if f is not None], m.end()))
    return found


def _crs(header):
    """`crs={id,id,...}`: the creatures an entry drops from."""
    m = re.search(r"(?<![A-Za-z_])crs=\{([\d,\s]*)\}", header)
    return [int(x) for x in re.findall(r"\d+", m.group(1))] if m else []


def dropped_by(text, enclosing, entry_start):
    """The NPCs behind a mount entry -> [(npcID, NPC frame or None)]: the entry's own
    crs list, else the innermost enclosing NPC, else the innermost enclosing
    entry's crs list (a header such as "Zandalari Warbringer" drops)."""
    own = text[entry_start:text.find("}", entry_start, entry_start + 400) + 1 or entry_start + 400]
    ids = _crs(own)
    if ids:
        return [(i, None) for i in ids]
    for f in enclosing:
        if f.kind == "n" and f.npc and f.npc > 0:
            return [(f.npc, f)]
        ids = _crs(frame_header(text, f))
        if ids:
            return [(i, None) for i in ids]
    return []


def _match_brace(text, i):
    """Index of the "}" closing the "{" at text[i]."""
    depth = 0
    for j in range(i, len(text)):
        c = text[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return j
    return len(text)


def frame_header(text, frame):
    """The NPC's own attributes: its table up to its child list (`g={`)."""
    end = frame.end if frame.end is not None else len(text)
    g = text.find("g={", frame.start, end)
    return text[frame.start:g if g != -1 else end]


def parse_coords(header):
    """`coords={[map]={{x,y},...},...}` -> [(map, x, y), ...] in order."""
    i = header.find("coords={")
    if i == -1:
        return []
    block = header[i + 7:_match_brace(header, i + 7) + 1]
    out = []
    for mm in re.finditer(r"\[(\d+)\]=\{", block):
        inner = block[mm.end() - 1:_match_brace(block, mm.end() - 1) + 1]
        for p in re.finditer(r"\{\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)", inner):
            out.append((int(mm.group(1)), float(p.group(1)), float(p.group(2))))
    return out


def header_int(header, key):
    m = re.search(r"(?<![A-Za-z_])%s=(\d+)" % key, header)
    return int(m.group(1)) if m else None


def removed(header):
    """AllTheThings marks NPCs removed from the game (rwp: removed with patch;
    u=2: removed)."""
    return bool(re.search(r"(?<![A-Za-z_])rwp=", header) or re.search(r"(?<![A-Za-z_])u=2\b", header))


# --- Mount.db2 source text --------------------------------------------------------------

_LABEL = re.compile(r"\|c[0-9A-Fa-f]{8}([^|:]+):\s*\|r\s*([^|]*)")


def source_pairs(text):
    """The source text's labelled lines in order -> [(label lower-case, value)]."""
    text = (text or "").replace("|n", "\n")
    return [(m.group(1).strip().lower(), re.sub(r"\s+", " ", m.group(2)).strip())
            for m in _LABEL.finditer(text)]


def name_key(name):
    name = " ".join((name or "").split()).lower()
    return name[4:] if name.startswith("the ") else name


def source_people(pairs):
    """-> [(kind "drop"|"vendor", name, [zone keys])] from the source's Drop: /
    Vendor: lines and the Zone: / Location: lines after each (comma lists
    split)."""
    people = []
    for label, value in pairs:
        if label in ("drop", "vendor"):
            people.append([label, value, []])
        elif label in ("zone", "location") and people:
            for part in value.split(","):
                if part.strip():
                    people[-1][2].append(name_key(part))
    return [(k, n, z) for k, n, z in people]


# --- maps -----------------------------------------------------------------------------

def zone_names(uimap_rows):
    """uiMapID -> set of name keys of the map and every map above it up to the
    continent (a dungeon floor counts for its zone too)."""
    maps = {int(r["ID"]): r for r in uimap_rows}
    cache = {}

    def names(i):
        if i in cache:
            return cache[i]
        out, current, steps = set(), i, 0
        while current in maps and steps < 15:
            r = maps[current]
            if int(r["Type"] or 0) <= CONTINENT:
                break
            out.add(name_key(r["Name_lang"]))
            current, steps = int(r["ParentUiMapID"] or 0), steps + 1
        cache[i] = out
        return out
    return names


# --- building -------------------------------------------------------------------------

def read_mounts(path=MOUNTS):
    """Data/Mounts.lua -> {mountID: (name, spell, item)}."""
    out = {}
    pat = re.compile(r'^\s*\[(\d+)\] = \{ name = "((?:[^"\\]|\\.)*)", spell = (\d+)(?:, item = (\d+))?')
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = pat.match(line)
            if m:
                out[int(m.group(1))] = (m.group(2), int(m.group(3)), int(m.group(4)) if m.group(4) else None)
    return out


def npc_coords(texts_frames):
    """Every NPC's coordinates over all its entries -> {npcID: [(map, x, y)]} (an NPC
    listed under a vendor header without coordinates often has them elsewhere)."""
    out = {}
    for text, frames in texts_frames:
        for frame in frames:
            header = frame_header(text, frame)
            if "coords=" not in header or removed(header):
                continue
            pts = out.setdefault(frame.npc, [])
            for p in parse_coords(header):
                if p not in pts:
                    pts.append(p)
    return out


def build_spots(mounts, att_texts, source_texts, map_names, quest_names=None):
    """-> {mountID: [spot]} with spot = {npc, name?, kind?, quest?, daily?, faction?,
    pts: [(map, x, y)]}, and stats. quest_names: {questID: name} (Rarity's names
    of the rares behind one comma-listed "Drop:" line)."""
    by_spell = {s: mid for mid, (_, s, _) in mounts.items()}
    by_item = {i: mid for mid, (_, _, i) in mounts.items() if i}
    seen = collections.defaultdict(dict)  # mountID -> npcID -> spot
    scanned = []
    for text in att_texts:
        frames = []
        found = scan(text, set(by_spell), set(by_item), frames)
        scanned.append((text, frames, found))
    coords_of = npc_coords((text, frames) for text, frames, _ in scanned)
    for text, _, found in scanned:
        for key, enclosing, entry_start in found:
            mid = by_spell[key[1]] if key[0] == "spell" else by_item[key[1]]
            around = None  # the nearest enclosing entry with coords (an event's spots)
            for npc, frame in dropped_by(text, enclosing, entry_start):
                if npc in seen[mid]:
                    continue
                header = frame_header(text, frame) if frame else ""
                if removed(header):
                    continue
                pts = parse_coords(header) or coords_of.get(npc, [])
                if not pts:
                    if around is None:
                        around = []
                        for f in enclosing:
                            if f is frame or f.kind == "n":
                                continue
                            h = frame_header(text, f)
                            if "coords=" in h:
                                around = parse_coords(h)
                                break
                    pts = around
                if not pts:
                    continue
                spot = {"npc": npc, "pts": pts}
                quest = header_int(header, "questID")
                if quest:
                    spot["quest"] = quest
                if header_int(header, "isDaily"):
                    spot["daily"] = True
                r = re.search(r"(?<![A-Za-z_])r=(\d)", header)
                if r and r.group(1) in FACTIONS:
                    spot["faction"] = FACTIONS[r.group(1)]
                seen[mid][npc] = spot

    out, stats = {}, collections.Counter()
    for mid, spots in seen.items():
        if not spots:
            continue
        people = source_people(source_pairs(source_texts.get(mid)))
        zoned = [p for p in people if p[2]]
        chosen = list(spots.values())
        if zoned:
            def person_for(spot):
                keys = set()
                for m, _, _ in spot["pts"]:
                    keys |= map_names(m)
                for p in zoned:
                    if keys & set(p[2]):
                        return p
                return None
            matched = [(s, person_for(s)) for s in chosen]
            kept = [(s, p) for s, p in matched if p]
            if kept:
                stats["zone-matched"] += 1
                chosen = []
                for s, p in kept:
                    s = dict(s, kind=p[0], name=p[1])
                    chosen.append(s)
            elif len(people) == 1 and len(chosen) == 1:
                # The source's zone is an area inside the map (Iskaara in the
                # Azure Span): one NPC, one name.
                stats["named by the only NPC"] += 1
                chosen = [dict(chosen[0], kind=people[0][0], name=people[0][1])]
            else:
                # AllTheThings lists the mount under NPCs the game's source does
                # not name (a holiday vendor's other stands, a boss drop's
                # Timewalking vendor): rather nothing than the wrong NPC.
                stats["no zone match"] += 1
                chosen = []
        elif len(people) == 1 and len(chosen) == 1:
            chosen = [dict(chosen[0], kind=people[0][0], name=people[0][1])]
        if quest_names:
            chosen = [dict(s, name=quest_names[s["quest"]]) if s.get("quest") in quest_names
                      and (not s.get("name") or "," in s["name"]) else s for s in chosen]
        chosen.sort(key=lambda s: s["npc"])
        if not chosen:
            continue
        out[mid] = chosen[:MAX_NPCS]
        stats["mounts"] += 1
        stats["spots"] += len(out[mid])
        stats["points"] += sum(len(s["pts"]) for s in out[mid])
    return out, stats


def rarity_quest_names(sources):
    """Rarity's coords entries name the rare of each daily quest
    (`{ m =, x =, y =, q = questID, n = L["Name"] }`) -> {questID: name}."""
    ra = sources.get("rarity") or {}
    out = {}
    if not (ra.get("repo") and ra.get("commit")):
        return out
    for path in build_data._rarity_paths(ra["repo"], ra["commit"]):
        with open(build_data._cached(ra["repo"], ra["commit"], path), encoding="utf-8") as fh:
            text = fh.read()
        for m in re.finditer(r"\{[^{}]*\bq\s*=\s*(\d+)[^{}]*\bn\s*=\s*L\[\"([^\"]+)\"\][^{}]*\}", text):
            out.setdefault(int(m.group(1)), m.group(2))
    return out


def _num(v):
    s = ("%.2f" % v).rstrip("0").rstrip(".")
    return s or "0"


def emit_lua(spots, mounts, att_commit, build):
    lines = [
        "-- GENERATED by tools/build_spots.py -- do not edit.",
        "-- Source: AllTheThings https://github.com/ATTWoWAddon/AllTheThings commit %s" % att_commit,
        "--   MIT License (full text: Data/LICENSE-AllTheThings.txt): NPC IDs, coordinates,",
        "--   daily quests and factions. Names and zones: Blizzard's Mount.db2 source text and",
        "--   UiMap.db2 (Retail build %s)." % build,
        "-- mountID -> { { npc =, name =, kind = \"drop\" | \"vendor\", quest =, daily =, faction =,",
        "--   pts = { uiMapID, x, y, uiMapID, x, y, ... } (x / y in percent) } }",
        "",
        "local ADDON, ns = ...",
        "ns.Data = ns.Data or {}",
        "",
        "ns.Data.Spots = {",
    ]
    for mid in sorted(spots):
        lines.append("  [%d] = { -- %s" % (mid, mounts[mid][0]))
        for s in spots[mid]:
            parts = ["npc = %d" % s["npc"]]
            if s.get("name"):
                parts.append("name = %s" % build_data.lua_string(s["name"]))
            if s.get("kind"):
                parts.append('kind = "%s"' % s["kind"])
            if s.get("quest"):
                parts.append("quest = %d" % s["quest"])
            if s.get("daily"):
                parts.append("daily = true")
            if s.get("faction"):
                parts.append('faction = "%s"' % s["faction"])
            pts = ", ".join("%d, %s, %s" % (m, _num(x), _num(y)) for m, x, y in s["pts"])
            parts.append("pts = { %s }" % pts)
            lines.append("    { %s }," % ", ".join(parts))
        lines.append("  },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--offline", action="store_true", help="use cached files only")
    args = ap.parse_args(argv)
    with open(SOURCES, encoding="utf-8") as fh:
        sources = json.load(fh)
    att = sources.get("allthethings") or {}
    if not (att.get("repo") and att.get("commit")):
        sys.exit("no allthethings repo / commit pinned in tools/sources.json")
    build = sources.get("db2build")
    if not build:
        sys.exit("no db2build pinned in tools/sources.json")

    folder = verify_data.fetch_tables(build, offline=args.offline, tables=("Mount", "UiMap"))
    source_texts = {int(r["ID"]): r["SourceText_lang"]
                    for r in verify_data.read_csv(os.path.join(folder, "Mount.csv"))}
    map_names = zone_names(verify_data.read_csv(os.path.join(folder, "UiMap.csv")))

    texts = []
    for name in ATT_CATEGORIES:
        path = build_data._cached(att["repo"], att["commit"], "db/Standard/Categories/%s.lua" % name)
        with open(path, encoding="utf-8-sig") as fh:
            texts.append(fh.read())
    license_path = build_data._cached(att["repo"], att["commit"], "LICENSE")

    mounts = read_mounts()
    spots, stats = build_spots(mounts, texts, source_texts, map_names, rarity_quest_names(sources))
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(emit_lua(spots, mounts, att["commit"], build))
    with open(license_path, encoding="utf-8") as src, open(LICENSE_OUT, "w", encoding="utf-8", newline="\n") as dst:
        dst.write(src.read())
    print("spots: %(mounts)d mounts, %(spots)d NPCs, %(points)d points; "
          "zone-matched %(zm)d, no zone match %(nz)d" % {
              "mounts": stats["mounts"], "spots": stats["spots"], "points": stats["points"],
              "zm": stats["zone-matched"], "nz": stats["no zone match"]})
    return 0


if __name__ == "__main__":
    sys.exit(main())
