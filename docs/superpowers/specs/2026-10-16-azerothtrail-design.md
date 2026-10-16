# AzerothTrail — design

A World of Warcraft (Retail) addon: a Dungeon-Journal-style browser for mounts, plus a per-character farming route that ticks itself off as you get locked out.

Date: 2026-10-16. Status: draft for owner approval.

## Why

The owner farms mounts across many characters. Two things hurt:

1. There is no single in-game place to see every mount an expansion offers, grouped by where it comes from.
2. Keeping track of which once-a-day / once-a-week mount kills a given character has already done is manual. The owner currently uses the SimpleArmory mount planner (a fixed ~80-step route through lockout bosses), where every step is ticked by hand and reset by hand.

AzerothTrail brings both into the game. The route is the part the owner will open most; the journal is how they decide what to farm.

## Goals

- Browse every mount by the expansion it was **released in**, grouped by source, with filters.
- A **route** for the logged-in character: the SimpleArmory-style run, in travel-efficient order, that auto-skips steps the character is saved to or already owns the mount for, and resets itself on daily/weekly reset.
- Track once-a-day farms too: daily-lockout dungeons, daily/weekly rares and world bosses, active holiday bosses.
- Show where a mount comes from on the map in one click.
- Hover a mount to see approximate drop rate, how many times it has been farmed, and lockout state. Ctrl+left-click previews the model.
- Look and feel close to the default Dungeon Journal.

## Non-goals

- Classic, Cata Classic, or any non-Retail client. Retail only.
- A cross-character overview. The route is **only for the logged-in character**.
- Computing the route at runtime (no pathfinding, no travel-time model). Order is hand-curated.
- Pets, toys, transmog.
- Live data from the web. Addons have no network access; all data ships in the addon.

## Anti-goals (would make it a failure even if it "works")

- The route says a step is done when it isn't, or not done when the character is saved. Auto-ticks must come only from real game state; if a step can't be detected, it stays manual and says so.
- Hard dependency on another addon. TomTom and Rarity are optional extras; everything works without them.
- Taint or errors in combat. Nothing in the addon should touch protected frames or combat-restricted APIs.
- Copying data without honouring its license.

## Constraints

- **Client:** WoW Retail, Midnight (12.x). Interface version taken from the current client at build time.
- **Lockouts are per character and only visible while logged in.** The game exposes saved-instance and quest-flag state for the current character only. The route therefore only ever shows the current character.
- **Midnight combat restrictions ("secret values").** Combat-log events are gone for addons. Kill counting must not rely on the combat log; see "Times farmed" below. This needs verifying in-game early.
- **License:** the addon is released as **GPL-2.0** (owner agreed), because it uses drop-rate data derived from Rarity (GPL-2.0).
- **Credit** every addon/library whose data or code is used, in: `LICENSE`, a credits block in the README, a header comment in any derived data file, and the CurseForge/Wago description.

## What the owner decided

### Window and tabs

One movable window styled like the Dungeon Journal, opened by slash command and minimap button. Tabs: **Journal**, **Holidays**, **Misc**, **Route**.

### Journal tab

- **Home:** grid of expansions, Classic → current. Each card shows the **official expansion logo** and "owned / total" with a progress bar.
- **Expansion view:** mounts grouped by source: **Dungeons, Raids, World drops / rares, Reputation, Vendors**.
- A mount belongs to the expansion it was **released in**, not the zone it's in (e.g. Onyxian Drake → Wrath).
- **Filters** (checkboxes): Dungeon, Raid, World drop, Reputation, Vendor, **Collected** (off by default, so you see what's missing). Plus a search box. Filters apply to every tab.
- **Mount row:** mount icon, name, source line (boss · instance · difficulty, or faction · standing, or vendor · zone), **Map** button.

### Holidays tab

- Holiday mounts grouped by event (Headless Horseman / Hallow's End, Coren Direbrew / Brewfest, Love is in the Air, etc.), with event dates and whether the event is on now.
- When an event is active, its boss is **added to the route** as a daily step.

### Misc tab

- Mounts you can't farm on a lockout, grouped: **Achievement, Profession, Shop, Trading Post**.
- Each has a one-line "how to get it" (achievement name, profession + recipe, "Trading Post — this month" when in the current rotation).
- Browsing only; never in the route.

### Route tab

- Modelled on the owner's SimpleArmory planner (SimpleArmory's mount planner (simplearmory.com)): steps are either **travel hints** ("Portal to Uldum") or **kills** (instance/boss → mount, difficulty notes like "Heroic only", "no watchers").
- **Order:** hand-curated for fastest travel, ignoring expansions, with **Horde and Alliance variants** (portals differ).
- **Source of the step list:** SimpleArmory's own planner data, `static/data/planner.json` in `kevinclement/SimpleArmory` (MIT license, compatible with GPL-2.0; credit SimpleArmory and keep its MIT notice). That file already carries boss IDs, item/spell IDs, notes and faction handling (steps flagged `capital: true` resolve to Orgrimmar/Stormwind). AzerothTrail converts it into a Lua data file at build time and may add steps (daily rares, holidays) on top.
- **Adapts live to the character:**
  - Steps whose mounts are all owned are hidden.
  - Steps the character is saved to are **auto-ticked** (labelled "auto").
  - Steps the character can't access yet (e.g. garrison not unlocked) are flagged, not hidden.
  - Steps that can't be detected (rares with no hidden tracking flag) are **manually** tickable.
- **Resets:** weekly content clears on the region's weekly reset (Tuesday in US); daily content (heroic dungeons, daily rares, holiday bosses) clears on the daily reset. Reset timers are shown in the header.
- Travel hints are never auto-ticked.

### Once-a-day tracking

Covered by the route, detected by:
- **Saved-instance lockouts** for raids and daily-lockout dungeons.
- **Hidden "quest completed" flags** for world bosses and rares that have them (the way Rarity/HandyNotes do it).
- Holiday bosses via their daily lockout.

### Map button

- Places the built-in map pin at the source location and opens the world map there.
- If **TomTom** is installed, also sets a TomTom waypoint arrow.

### Tooltip and click

- Hover: **approx. drop rate**, **times farmed**, **lockout status** for this character.
- **Ctrl+left-click:** preview the mount model (default dressing-room behaviour).

### Times farmed

- AzerothTrail counts its own attempts (see "Builder's calls").
- If **Rarity** is installed and its counts are readable, show Rarity's count instead/alongside.

### Drop rates

- Taken from **Rarity's** data (GPL-2.0), credited. Shown as "approx."

### Data sources (credited)

- **SimpleArmory** (MIT) — route steps.
- **Rarity** (GPL-2.0) — drop rates.

### Integrations (optional, credited)

- **TomTom** — waypoint arrow.
- **Rarity** (original `WowRarity/Rarity`, maintained forks Rarity: Collector's Edition and Spearity) — drop-rate data; attempt counts when installed.

### Name and theme

- Name: **AzerothTrail** (an Oregon Trail play). Light Oregon-Trail flavour text is welcome in the route (e.g. "You have 37 lockouts left. Saddle up?", "Adventurer has died of 0.5% drop rate.").
- Check the name is free on CurseForge and Wago before release.

## Builder's calls (made by Claude, not the owner — owner can override)

- **Language/structure:** plain Lua, frames created in code (XML only if a template genuinely needs it).
- **Libraries:** Ace3 (AceAddon, AceDB for saved settings, AceConsole for slash commands), LibDataBroker-1.1 + LibDBIcon-1.0 for the minimap button. All embedded and credited.
- **Saved data:** account-wide settings (filters, window position) and **attempt counts (account-wide**, because mounts are account-wide and Rarity counts the same way; the tooltip may show this character's share in grey); per-character manual ticks.
- **Rarity count vs ours:** when Rarity's count is readable, show Rarity's number labelled "Rarity" and ours beneath it; never add them.
- **Journal counts:** each expansion's "owned / total" counts only mounts shown in the Journal tab (dungeon, raid, world, reputation, vendor). Holiday and Misc mounts are counted on their own tabs.
- **Filters vs Route:** the Journal filters do **not** affect the Route. The route always hides steps whose mounts are all owned; it has its own "show completed steps" toggle like SimpleArmory's.
- **Factions:** both supported from day one via SimpleArmory's capital substitution; travel hints that differ beyond the capital get a faction-specific line where needed.
- **Release and language:** built release-ready but owner-first; English only for v1, with every user-facing string going through a locale table so translations can be added later. Licensing and credits are done in v1 regardless.
- **Times farmed without the combat log:** count +1 when a tracked boss/rare transitions from "not saved / flag not set" to "saved / flag set" while the mount is still uncollected. Verify this works under Midnight before building on it.
- **Data tables** shipped in the addon: mount → expansion, source type, instance/boss/difficulty or faction/vendor, map ID + coordinates, lockout or quest-flag ID, holiday, Misc category; route steps per faction.
- **Initial data scope:** every boss/rare on the owner's SimpleArmory route plus well-known daily rares first; fill the rest of the journal from the game's own mount list + source text, refine over time.
- **Reset times:** use the game's own daily/weekly reset timers rather than hard-coding Tuesday.
- **Active holidays:** read from the in-game calendar.
- **Trading Post rotation:** read from the game's Trading Post API.
- **Expansion logos and mount icons:** use the game's built-in art; ship no images.

## Left to the builder

- Exact frame layout, sizes, fonts, colours (within "looks like the Dungeon Journal").
- Data file layout and how route steps reference mounts.
- How Rarity's data is extracted and kept in sync.
- Slash command name(s).
- Test approach (unit tests for pure Lua logic outside the game; in-game checklist for the rest).

## Open risks to check early

1. Attempt counting via lockout/flag transitions under Midnight restrictions.
2. Whether Rarity exposes its attempt counts in a readable way (global table or API).
3. Availability of hidden tracking flags for each world boss / rare on the route.
