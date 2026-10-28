# Changelog

## Unreleased

- `/mtrail zone` opens the small pop-out of your zone's mounts (as
  `/mtrail here` does) instead of the side panel; the panel stays on the
  title bar's pin button.
- Lockouts: a saved kill now prints "Lockout checked off: <mount> (attempt
  n)" in chat, and lockouts are asked for again a few seconds after a kill.
- Lockouts: old raids up to Throne of Thunder share one lockout across the
  four 10 / 25 sizes: any kill ticks the row (Onyxia, Malygos and the Vault
  of Archavon were two rows' worth before). Firelands, Ulduar and Black
  Temple, now Normal / Heroic only, tick off on those kills (Alysrazor,
  Ragnaros).
- Lockouts: a mount with one lockout per difficulty (Felblaze Infernal,
  Antoran Charhound) shows which difficulties are done and which are left.
- Current Zone: inside a raid, its drops are matched by instance ID (Antorus
  listed none).

## 0.9.0-beta (first public beta)

The first public release. Highlights:

- **Navigation and pages**: Home with expansion progress, Lockouts (daily and
  weekly mount lockouts, rare spawns), Current Zone, Browse by source (drops,
  vendors, quests, achievements, professions, shop, Trading Post, PvP,
  Mythic+, holidays, Timewalking, other) and a resizable detail pane with the
  3D model, drop chance, attempts and where to find each mount.
- **Search** in every page, typo-tolerant, with short names (`tbc`, `icc`,
  `wod`) and an expansion fallback.
- **Pop-outs**: small windows for any set (dailies, weeklies, rare spawns,
  your lists, the mounts of your zone) that stay on screen, snap together and
  take your colours, font and size.
- **Your lists**: build lists from any mount; share them as a chat line,
  whisper them, or export / import them as text.
- **Guides**: step-by-step mount guides with TomTom waypoints, auto-advance,
  item and quest tooltips, macros and credits; write your own in plain text.
- **Alt lockout matrix**: who is still unsaved this week, across characters.
- **Wrong-difficulty warning**: entering a raid on a difficulty where a mount
  in your pop-outs doesn't drop (from the Encounter Journal's loot data).
- **Optional addons**: Rarity (attempt counts), Mount Journal Enhanced /
  MountsRarity (how rare a mount is), AllTheThings (how-to notes).

Requires TomTom.
