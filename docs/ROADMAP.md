# Roadmap

Ideas for later, roughly in order of interest. Nothing here is promised;
move an item out when it ships.

## Planned

- **Mount guides (to come back).** Step-by-step directions for a mount
  (goto points on TomTom, steps done by a quest, items in bags, the mount, or
  reaching a spot; macros; a plain-text format to write and share). Built and
  then taken out before release so the rest could ship first; the whole
  feature is in git history at commit c0fdff1 (Logic/Guide.lua,
  UI/Guides.lua, UI/GuideWindow.lua, UI/GuideEditor.lua, docs/GUIDES.md).
  Players' own guides stay in their saved variables (`global.guides`).
- **Custom route planning.** Build a farming route from a list: the order to
  visit its mounts' bosses, rares and vendors (by continent, nearest first),
  with "next" moving the TomTom waypoint along (the mount guides above would
  be its base). Routes would share like lists (`MountTrail: !MT1!...` lines,
  or a `!MR1!` route line), so guildmates can post a ready-made route. Builds on Logic/Lists.lua,
  Logic/Share.lua, Data/Route.lua (bosses and instances) and
  Integrations/Map.lua (waypoints).

## Ideas

- **Rare spawn alerts.** When a tracked rare appears on the minimap
  (the game's vignette API), play a sound, flash its row and set a waypoint.
- **Weekly reset summary.** On the first login after a reset, a small pop-out
  with the fresh mount lockouts and attempts across characters.
- **More quick lists.** Easy solo farms, vendor mounts you can afford now,
  reputation mounts you are close to, holiday mounts this month.
- **Mount drop log.** Date, character and attempt count when a mount drops
  ("Got it after 87 attempts" in the detail pane).
- **Pop-out lock / click-through.** Stop accidental drags; let clicks pass
  through while questing.
- **Keyboard navigation in lists.** Up / down to move, Enter for the waypoint.
- **"Why can't I get this?" lines.** Wrong faction, missing profession or
  class, holiday not running, shown in red in the detail pane.
- **Long lists in one chat link.** Lists over ~55 mounts don't fit a chat
  message; the ask-the-sharer link that covers them needs checking in game.
