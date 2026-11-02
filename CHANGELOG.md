# Changelog

## 0.9.2-beta

**A new look.** The main window, the pop-outs and the menus share one
design: a dim gold frame, cards with a header band, and two-line rows with
each mount's icon boxed in its rarity's colour.

- **Home**: the collected total in large gold figures over a bar;
  Expansions on the left, By source and Nearby on the right, on one page
  that scrolls. Bars take each expansion's colour. Nearby shows each
  mount's icon, where it comes from and its drop chance; click its heading
  for Current Zone, right-click to pop it out.
- **Lists**: every page has the same one-line header (Back and the title on
  the left; search, what is left, Filter and the page's buttons on the
  right). Rows show `Owned`, `✓ Done`, `Open`, your tries or the drop
  chance, and a vendor mount's price.
- **Detail pane**: the name in its rarity's colour, an info card with
  Status, Attempts, Drop, From, Where, Cost and Lockout, and Waypoint,
  + List and Wowhead along the bottom.
- **Pop-outs**: two layouts in each window's right-click menu, Cards (the
  default) and Compact; a thin progress bar under the title and each
  group's count on its header.
- **Left column**: one Lists section (the built-in lists, then yours),
  section headings that light up under the pointer, and a gold band on the
  page you are on.
- Flat search boxes, Filter menus, tick boxes and buttons throughout.

**New**

- Browse has a **Faction** page: each race's mounts under its own heading,
  the allied races' together.
- **Font Styles** (cogwheel and AddOns page): pick a Header font and a Body
  font (the game's by default; Arial Narrow, Morpheus, Skurri or a
  LibSharedMedia font).
- **Background opacity** for the main window in the cogwheel and on the
  AddOns page.
- The AddOns settings page is in sections (Window & Text, Font Styles,
  Collection, Colours, Navigation, Alerts, Accessibility, Advanced), and
  the settings have clearer names (Navigation text, Header text, Body text,
  Small text).

**Lockouts**

- Tundra Icehoof, Armored Razorback and Warsong Direfang tick themselves
  from the four Tanaan rares' daily loot ("2 of 4 rares looted"), and each
  rare you loot counts as an attempt.
- The Qiraji Battle Tanks are done for the week once C'Thun dies; the
  Bronze Drake is done for the day once Mal'Ganis dies in heroic Culling of
  Stratholme. No hand ticks needed.
- The "Saddle up?" line is gone; the tabs already count what is left.

**Fixes**

- Holiday mounts show in Nearby, Current Zone, the zone panel and the map
  only while their holiday is on.
- Opacity and collapsing a pop-out group apply at once.

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
