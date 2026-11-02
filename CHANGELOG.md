# Changelog

## Unreleased

- Holiday mounts (Lunar Launcher, ...) show in Nearby, Current Zone, the
  zone panel and the map only while their holiday is on.
- **Font styles**, in the cogwheel menu and on the AddOns page: a Header
  font (titles) and a Body font (mount names and text), the game's own by
  default; Arial Narrow, Morpheus, Skurri, or a LibSharedMedia font. Korean
  and Chinese clients keep the game's font.
- The AddOns settings page is in sections: Window & text, Font styles,
  Collection, Colours, Navigation, Alerts, Accessibility, Advanced.
- Browse has a **Faction** page: each race's mounts under its own heading
  (Human, Orc, ... Dracthyr), the allied races' mounts together under
  Allied Races. They left Other and Quests & Activities; Home's By source
  has a Faction row.
- Lockouts: the "You have N lockouts left. Saddle up?" line is gone (the
  tabs already count what is left); the header is shorter.
- Pop-outs have two layouts, picked in each window's right-click menu:
  Cards (the default: each group a card, rows with the mount's icon, a grey
  second line and Open / Done or the drop chance on the right) and Compact
  (the one-line rows). Your colours, opacity, font and sizes apply to both.
- MountTrail's menus match: section titles sit on a card band with a gold
  edge, inside a gold-edged panel.
- Pop-outs in the Blend A look: a dim gold frame, what is left as a boxed
  badge beside the title, bordered cards, each mount's icon boxed in its
  rarity's colour, and boxed Open / Done / "1 in 100" badges.
- The main window has the same dim gold frame; the left column's section
  labels are in capitals, the entry you are on sits on a gold-tinted band,
  and counts sit on a small dark box.
- Home in the Blend A look, as the design sheet: the collected total in
  large gold figures over a gold bar; Expansions on the left, By source and
  Nearby on the right, on one page that scrolls; bars in each expansion's
  colour (sources in bronze), owned / total without a percent; Nearby rows
  show the mount's icon, where it comes from and its drop chance. The Today
  column is gone (Lockouts in the left column counts what is left).
- Every list in the main window (expansions, Browse, your lists, Lockouts,
  Current Zone, the zone panel) is made of cards: a header on a card top,
  two-line rows with the mount's icon boxed in its rarity's colour, the
  source under the name, and an `Owned` or `1 in 100` badge.
- The detail pane matches: its info sits on a card with a gold edge, the
  model area has a card border.
- The lists match the design more closely: a group's count sits on its
  header's right (the name alone on the left), a mount you are farming
  shows your tries ("87 tries") before its drop chance, and the search
  boxes and Filter buttons are flat (a dark field with a dim gold border)
  instead of Blizzard's rounded art.
- Every list page has the same one-line header, as the design: Back and
  the title on the left; search, what is left (`16 left`), Filter and the
  page's buttons on the right. Holidays, Achievements, Timewalking and Other
  get titles too.
- The detail pane follows the design: the name in its rarity's colour over
  "expansion · kind of source", an info card that starts with Status and
  lays the details out as label / value columns, and Waypoint, + List and
  Wowhead along the bottom.
- Tundra Icehoof, Armored Razorback and Warsong Direfang tick themselves:
  their lockout is the four Tanaan rares' own daily loot flags (done once all
  four are looted today, "2 of 4 rares looted" until then), and each rare
  you loot counts as an attempt. No hand tick.
- List rows and the detail pane carry the design's badges and rows: a
  lockout spent today shows `✓ Done`, one still open `Open`, a vendor mount
  its price (from the game's own source text). The detail pane's info card
  has the design's rows: Status, Attempts (with how many players would have
  it by now), Drop, From, Where, Cost and Lockout (gold while open, green
  once done).
- Pop-outs show a thin gold bar under the title (how much of the set is
  done) and each group's "N left" on its header's right.
- The Qiraji Battle Tanks leave Lockouts for the week once C'Thun dies in
  Ahn'Qiraj (40); the Bronze Drake's day is spent by the Culling of
  Stratholme heroic (Mal'Ganis's kill; the drake itself is a sure drop). No
  hand ticks for either.
- The tick boxes (Lockouts' hand-ticked rares, a pop-out's rare spawns) are
  flat: a dark square in a dim gold border, filled gold when ticked, as the
  menus' boxes.
- The Filter button opens MountTrail's own gold-edged menu instead of
  Blizzard's dropdown; a `Reset` button beside it replaces the red arrow.
- The left column has one **Lists** section instead of My lists and Quick
  lists: the built-in lists (Daily / Weekly lockouts, Rare Spawns) come first,
  then your own. The settings are now `Show your lists` and
  `Show built-in lists`.

## 0.9.1-beta

- The world map tab's rows show each mount's icon again, at a bag slot's
  size, and drop the expansion tag and the source column (the map already
  is the zone).
- The drop sound is picked on the AddOns settings page only; the cogwheel
  menu keeps the "Chime when a mount drops" switch.

## 0.9.0-beta (first public beta)

The first public release. Highlights:

- **One flat look**: the main window and every pop-out share a slim,
  pop-out-style design: a title strip (right-click for the appearance menu:
  opacity, colours, font, sizes), one-line rows (expansion tag, name, where
  it comes from) and headers in each expansion's colour.
- **Navigation and pages**: Home (your collection total, a bar per expansion
  and per source, today's lockouts, the mounts still to get in your zone),
  Lockouts, Current Zone, the Alts matrix, Browse by source (drops, vendors &
  reputation, quests, achievements, professions, in-game shop, Trading Post,
  PvP, Mythic+, holidays, Timewalking, other) and a detail pane with the 3D
  model, drop chance, attempts, lockout and where to find each mount.
- **Lockouts**: daily and weekly mount lockouts ticked off from the game's
  own data (old 10 / 25-player raids' shared lockouts, one lockout per
  difficulty for newer raids: "Heroic done · Normal, Mythic left"), rare
  spawns, live status of the assault and warfront rares, a chat line when a
  kill uses a lockout, and a wrong-difficulty warning on raid entry.
- **Drop alert**: when a mount you were farming drops (its item reaches your
  bags), chat says how many attempts it took and how lucky you were; an
  optional chime (off by default) with a choice of sounds.
- **Search** in every page, typo-tolerant, with short names (`tbc`, `icc`,
  `wod`) and an expansion fallback.
- **Pop-outs**: small windows for any set (dailies, weeklies, rare spawns,
  your lists, the mounts of your zone) that stay on screen, snap together and
  take your colours, font and size.
- **Your lists**: build lists from any mount, in your own order or by
  expansion (move and remove mounts in the list or its pop-out); share them as
  a chat line, whisper them, or export / import them as text.
- **Alt lockout matrix**: who is still unsaved this week, across characters.
- **Options**: what counts towards your collection (in-game shop, Trading
  Post, promotions, Black Market, unobtainable mounts), sizes named by what
  they size, rarity colours for the pop-outs and the lists apart, colour-blind
  marks (following the game's Colorblind Mode), `Reset all settings`, and
  `/mtrail hide` / `/mtrail show` for the minimap button.
- **Optional addons**: Rarity (attempt counts), Mount Journal Enhanced /
  MountsRarity (how rare a mount is), AllTheThings (how-to notes).

Requires TomTom.
