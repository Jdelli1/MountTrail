# Changelog

## Unreleased

- No mount icons on list rows or beside the detail pane's name: the pane's
  3D model shows the mount.
- Options: `Count in-game shop mounts`, `Count Trading Post mounts`, `Count
  promotional mounts`, `Count Black Market mounts` (on by default): off leaves
  those mounts out of every list and count, owned or not.
- Options: `Colour list names by rarity`, the main window's own, apart from
  `Colour pop-out names by rarity`.
- Home: By source lists every Browse source instead of Misc; the left column
  scrolls; a thicker total bar.
- Sizes named by what they size: `Whole window`, then `Left column`,
  `Headers`, `Mount names and text` and `Small notes` (were Window scale and
  Gold / White / Grey / Navigation text size). A row's source line and
  collected mounts' names now size with `Mount names and text`; the left
  column sizes with `Left column` only.
- Your lists: sort `Order added` (default) or `By expansion` from the list
  page's Filter menu or the pop-out's title menu; move mounts with `Move up`
  / `Move down` (detail pane, pop-out row) or Alt-drag in the pop-out; remove
  them from either.
- Every list uses the same one-line row (small icon, expansion tag, name,
  source on the right) and the same header colours, so My lists, Browse,
  expansions and Lockouts look alike.
- Options > AddOns > MountTrail: `Reset all settings`, after a warning, puts
  every setting (options, text sizes, window, every window's and pop-out's
  look) back to its default and reloads; lists, guides, attempts and lockouts
  are kept.
- The main window takes the pop-outs' look throughout:
  - a flat panel with a slim title strip instead of Blizzard's portrait
    frame; right-click the strip for the pop-outs' appearance menu;
  - the navigation's headings are pop-out group headers, counts read
    "48 left";
  - list headers are "- Name (count)" in the header or expansion colour over
    a thin rule; Lockouts counts what is left;
  - Lockouts rows are one line (expansion tag, mount, boss and instance)
    under flat Daily / Weekly / Rare Spawns tabs;
  - Home lists the expansions and sources as progress rows, with Today,
    Following and Nearby beside them;
  - flat Back / Pop out buttons; the detail pane folds away when it has
    nothing to show;
  - no small fonts in the new parts: headers at every level, the Lockouts
    rows' boss / instance line, tabs and Home's numbers are normal size, and
    expansion tags are 10 pt (were 8).
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
