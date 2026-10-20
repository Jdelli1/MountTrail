# Beta testing MountTrail

Thanks for trying the beta. The addon is unit-tested (over 900 tests), but
some things can only be checked in the game. This list is what helps most;
report results (good or bad) on the issue tracker with the bug template.

Before testing: install **TomTom**, then MountTrail. A `/reload` is enough
after updating, except when an update adds files: then restart the game.

## Core

- [ ] `/mtrail` opens the window; it remembers its size, position and page.
- [ ] Home's expansion tiles and progress bars match your collection.
- [ ] **Lockouts** lists this character's daily and weekly mount lockouts;
      after killing a boss, its row turns done within a few seconds.
- [ ] Filter > `Show completed` keeps done lockouts listed (dimmed).
- [ ] Attempts: kill a boss that drops a mount you don't own; the tooltip's
      "Attempts" goes up by one (and only one).
- [ ] The **Alts** window shows your other characters after you log each in once.

## Finding mounts

- [ ] Browse pages and every search box find mounts by name, boss, zone or
      short names (`tbc`, `icc`, `wod`); a place with nothing on the page
      shows its expansion instead.
- [ ] **Current Zone** follows you from zone to zone.
- [ ] The world map's MountTrail tab lists the shown zone's mounts, grouped by
      source; headers collapse.
- [ ] A row's right-click plots it on TomTom (all spawn points of a rare);
      Shift-click opens the map; Ctrl-click previews; hover lists these.

## Pop-outs

- [ ] Right-click a Lockouts chip or header to pop it out; it stays after
      `/reload`.
- [ ] Right-click a pop-out's title: Show completed, Change appearance
      (colours, font, size, opacity), Apply to all.
- [ ] **Wrong difficulty**: with a pop-out listing a raid mount open, enter
      that raid on a difficulty it doesn't drop on: a warning shows once.

## Lists and sharing

- [ ] `+ List` on a mount adds it to a list; untick to remove; a list's page
      offers Remove from <list>.
- [ ] Shift-right-click a list > Share in chat: others with MountTrail see a
      `[MountTrail: ...]` link; clicking it offers the import.
- [ ] Send to player and Export / Import (`/mtrail import`) work.
- [ ] `/mtrail sharetest` reports sharing set up (addon messages on, chat
      filters > 0).

## Guides

- [ ] Guides > Thundering Ruby Cloud Serpent: Next plots the step's points on
      TomTom, Back takes them off, the last step's Finish closes it.
- [ ] A step with `reach` moves on by itself near its point (outside
      instances); one with `item` when the items are in your bags.
- [ ] Links in a guide show the game's tooltip; `Go to: [place]` sets a
      waypoint; Make macro puts a macro on the cursor.
- [ ] New guide / Import guide / Edit a copy / Export work; the editor points
      at a mistake's line.

## Reporting

Include: what you did, what you expected, what happened, your MountTrail
version (the `.toc`'s Version, or the release name), and any Lua error (a
BugSack / BugGrabber capture is ideal). `/mtrail debug` turns on extra
messages that help.
