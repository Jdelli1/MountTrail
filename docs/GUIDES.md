# Writing MountTrail guides

A guide walks a player through getting one mount, step by step: what to do,
where to go, and when the step is done. MountTrail shows the current step in a
small window, puts the step's points on TomTom, and moves on by itself when it
can tell a step is finished.

A guide is **plain text**. You can write one in MountTrail's editor, in any
text editor, or in a Discord message, and share it by copying and pasting.

## Contents

- [A first guide](#a-first-guide)
- [How a guide is laid out](#how-a-guide-is-laid-out)
- [Header lines](#header-lines)
- [Steps](#steps)
- [Step lines](#step-lines)
- [When a step is done](#when-a-step-is-done)
- [Highlighting (bold)](#highlighting-bold)
- [Links with tooltips](#links-with-tooltips)
- [Macros](#macros)
- [The window's look](#the-windows-look)
- [Credits](#credits)
- [Finding IDs and coordinates](#finding-ids-and-coordinates)
- [Writing, testing and sharing in game](#writing-testing-and-sharing-in-game)
- [Mistakes and what the editor says](#mistakes-and-what-the-editor-says)
- [Limits](#limits)
- [Tips for good guides](#tips-for-good-guides)
- [A complete example](#a-complete-example)
- [Adding a built-in guide (for contributors)](#adding-a-built-in-guide-for-contributors)

## A first guide

```
#guide My first guide
#mount 517
step Fly to the Vale of Eternal Blossoms
  goto 390 56.2 42.6 The Vale
  reach 200
step Collect **ten** [item:12345] from the mobs there
  note They drop from any mob in the zone
  item 12345 10
step Kill the rare and loot [mount:517]
  mount 517
```

That guide has a title, the mount it is for, and three steps. The first moves
on by itself when you are within 200 yards of the point, the second when ten of
the item are in your bags, the third when you have the mount.

The item and quest numbers in this page's examples are placeholders: look up
the real ones as described in [Finding IDs](#finding-ids-and-coordinates).

## How a guide is laid out

- **One instruction per line.** Each line starts with a keyword (`#guide`,
  `step`, `goto`, ...) followed by its values.
- **Header lines first** (`#guide`, `#mount`, `#author`, `#description`),
  then the steps.
- **Every line after a `step` belongs to that step** until the next `step`.
  Indenting those lines is optional but makes the guide easier to read.
- **Comments**: a line starting with `--` is ignored. Use them for notes to
  yourself or other writers.
- **Blank lines** are ignored.
- Keywords are not case sensitive (`Step` and `step` both work).

## Header lines

| Line | Required | Meaning |
| --- | --- | --- |
| `#guide <title>` | Yes | The guide's name, shown in the Guides list and the window. Write it first. |
| `#mount <mount ID>` | No | The mount the guide is for. That mount's detail pane gets a **Guide** button. Use one line per mount if the guide covers several. |
| `#author <name>` | No | Who wrote it. One line per author; they show as "by A, B" under the guide's title, in its menu and when hovering it in the Guides list. |
| `#credit <text>` | No | Anyone else to thank, or where information came from. One line each; shown in the guide's menu and on hover. |
| `#description <text>` | No | One line about the guide. |

The guide's ID comes from its title (`Swift Spectral Tiger hunt` becomes
`swift-spectral-tiger-hunt`). Saving a second guide with the same title adds a
number (`-2`).

## Steps

```
step <directions>
```

The words after `step` are what the player reads. Keep it to one clear action:
"Fly to Booty Bay", "Kill Alani", "Buy the Skyshard from the vendor".

A guide needs at least one step and can have up to 500.

## Step lines

These go under a `step`:

| Line | Meaning |
| --- | --- |
| `note <text>` | An extra grey line under the directions: a tip, a warning, a detail. Use as many as you like. |
| `goto <map ID> <x> <y> [label]` | A point to go to. Several `goto` lines put several points on TomTom at once (TomTom's arrow picks the closest). The label is what TomTom calls the point. |
| `quest <quest ID>` | Done when that quest is turned in. |
| `item <item ID> [count]` | Done when that many are in your bags (1 if you leave the count out). |
| `mount <mount ID>` | Done when you have the mount. |
| `reach [yards]` | Done when you are that close to the step's **first** `goto` (15 yards if you leave it out). |
| `macro <line>` | A macro for this step. More `macro` lines add more lines to the same macro (255 characters in all, the game's limit). See [Macros](#macros). |

`x` and `y` are the numbers the game's map shows, from 0 to 100, for example
`goto 390 35.6 26`. A comma between them is fine: `goto 390 35.6, 26`.

## When a step is done

A step's `quest`, `item`, `mount` and `reach` lines are its **done lines**.

- **All of them** must hold for the step to be done. A step with
  `item 86547 10` and `reach 20` needs both the items and the spot.
- When they hold, MountTrail moves to the next step by itself and says so in
  chat. If the next step is also already done (say the quest was turned in
  earlier), it keeps going.
- **A step without done lines waits for Next.** That is the right choice for
  "talk to", "kill", "use" and anything else the game can't report.
- **After Back**, MountTrail never moves on by itself until you press Next or
  jump to a step, so a player can stay on a step they went back to.
- On the last step, **Next** reads **Finish**: it closes the guide and starts
  it from step 1 next time.

The window shows what finishes a step under its directions ("Done when: 10 x
[Skyshard], reach the spot"), or "Press Next when done." when it has no done
lines.

## Highlighting (bold)

Put two asterisks on each side of words to make them stand out:

```
step Kill mobs until you have **ten Skyshards**
```

WoW can't switch to a bold font in the middle of a line, so highlighted words
show in **bright gold** instead. You can highlight a whole step
(`step **Do not skip this**`) or a few words, in `step` and `note` lines.

## Links with tooltips

Write `[kind:ID]` and the window shows the game's own link: the real name in
brackets, and the game's tooltip when you hover it. Shift-click a link to put
it in chat.

| Write | Shows |
| --- | --- |
| `[item:86547]` | The item, with its quality colour and tooltip |
| `[quest:31234]` | The quest and its tooltip |
| `[mount:517]` | The mount, with MountTrail's mount tooltip (the mount, its drop chance, your attempts); Shift-click puts the mount's real link in chat |
| `[spell:12345]` | A spell |
| `[achievement:6]` | An achievement, with your progress in its tooltip |

```
step Combine ten [item:12345] into a [item:12346]
  note Turn in [quest:23456] first if you have not yet
```

- An item or quest the game has not loaded yet shows as `[item 86547]` for a
  moment; the window fills in the name as soon as it arrives.
- Links also work inside highlighted text and in notes.
- The "Done when" line uses links too, so every item, quest and mount in a
  guide has its tooltip.

## Macros

A step can carry a macro, for example to target a rare or use an item:

```
step Find Alani and target her
  goto 390 35.6 26 Alani
  macro /tar Alani
  macro /run if UnitExists("target") then PlaySound(8959) end
```

When that step is shown, the window has two buttons:

- **Copy macro**: the macro's text, selected; press Ctrl+C, open `/macro`,
  click New and paste it in.
- **Make macro**: MountTrail writes it into one account macro called
  `MountTrail` (made the first time, rewritten after that) and puts it on your
  cursor: drop it on an action bar. This needs one free account macro slot and
  doesn't work in combat (the game's rule); Copy always works.

Every `macro` line is one line of the macro, in order. Keep them short: the
game allows 255 characters per macro.

## Credits

Give credit where it is due:

```
#guide Thundering Ruby Cloud Serpent
#author Adventurer
#author AnotherWriter
#credit Spawn points from AllTheThings
#credit Thanks to the Wowhead commenters who mapped Alani's loop
```

- `#author` lines show as **by Adventurer, AnotherWriter** under the guide's title.
- `#credit` lines show in the guide's menu (right-click it) and when hovering
  the guide in the Guides list.
- Editing a copy of someone's guide keeps their lines: add yourself as another
  `#author` rather than replacing them.

## The window's look

- **Look**: right-click the guide window's title, then `Change appearance`:
  everything the pop-outs offer (opacity, background, header and text colour,
  font size, font, `Apply to all pop-outs`, `Reset appearance`); `Back`
  returns to the guide's menu. The guide window keeps its own look, or takes
  the shared one.
- **Size**: drag the bottom-right corner to stretch it any way you like. The
  text re-wraps to the width. The current-step view and the every-step view
  each remember their size; the current-step view still grows when a step
  needs more room. Right-click the corner for the default size.

## Finding IDs and coordinates

- **Item, quest, spell and achievement IDs**: the number in a Wowhead URL.
  `wowhead.com/item=86547` is item 86547; `wowhead.com/quest=31234` is quest
  31234.
- **Mount IDs**: MountTrail's own mount ID (the Mount Journal's). Find the
  mount on Wowhead's "Mounts" listing, or ask in the MountTrail community.
  `#mount` and `mount` both use it; `[mount:ID]` too.
- **Map IDs**: each zone has a UI map ID; Vale of Eternal Blossoms is 390.
  In game, `/dump C_Map.GetBestMapForUnit("player")` prints the ID of the map
  you are on.
- **Coordinates**: the x and y the world map shows (TomTom shows them on its
  coordinate display, and `/way` uses the same numbers).

## Writing, testing and sharing in game

- **New**: `+` next to Guides, then `New guide...`. The editor opens with a
  template to fill in. Save starts following it right away.
- **Import**: `+`, then `Import guide...`, paste the text, Save.
- **Edit**: right-click a guide under Guides, `Edit...`. A built-in guide opens
  as a copy and is saved as your own.
- **Export**: right-click a guide, `Export...`. The text is selected; press
  Ctrl+C and paste it wherever you share it.
- **Test**: follow your guide and press Next / Back through it. Right-click the
  window's title for `Show every step` to see all steps at once.
- **Delete**: right-click your guide, `Delete...` (type its name to confirm).
  Built-in guides can't be deleted.

Guides are saved account-wide; each character keeps its own place in each
guide.

## Mistakes and what the editor says

The line under the editor's text box checks the guide as you type. When all is
well it says "Title: 5 steps. Looks good." Otherwise it names the first
problem and its line:

| Message | Fix |
| --- | --- |
| `The first line must be: #guide <title>` | Add a `#guide` line. |
| `A guide needs at least one step.` | Add a `step` line. |
| `Start a step with: step <directions>` | A step line (`goto`, `note`, ...) came before any `step`. |
| `goto needs a map ID, then x and y` | Write `goto <map> <x> <y>`. |
| `goto's x and y go from 0 to 100` | Use the map's percentages, not yards. |
| `reach needs a goto in the same step` | `reach` measures to the step's first `goto`. |
| `item needs an item ID, then how many (optional)` | `item 86547` or `item 86547 10`. |
| `quest needs a quest ID` / `mount needs a mount ID` | A number after the keyword. |
| `Unknown line: <word>` | A typo in a keyword; comments need `--`. |

A guide with problems on some lines still saves as long as it has a title and a
step; the bad lines are left out. Save stays greyed out until it has both.

## Limits

Midnight keeps some things away from addons, so guides work around them:

- **Kills can't be seen.** "Kill X" steps either wait for Next, or use a
  `quest` or `item` line when the kill gives one.
- **Inside dungeons and raids** your position isn't available, so `reach`
  can't finish a step there; use Next.
- **TomTom is needed** for the points (MountTrail requires it anyway).
- A guide is limited to 500 steps and 60,000 characters.

## Tips for good guides

- One action per step. Several small steps beat one long one.
- Add a `goto` whenever there is a place to be; players follow the arrow.
- Use done lines wherever the game can tell: players then barely touch Next.
- Put warnings in `note` lines and highlight the one thing not to miss.
- Link items and quests so players can hover them instead of searching.
- Write your own words: don't copy another guide site's or addon's text.

## A complete example

The built-in Thundering Ruby Cloud Serpent guide
(`Guides/ThunderingRubyCloudSerpent.lua`) uses every feature: authors and
credits, comments, highlighting, links, several points in one step, a macro,
and done lines (`reach`, `item`, `mount`) next to steps that wait for Next.

```
#guide Thundering Ruby Cloud Serpent
#mount 517
#author MountTrail
#credit Alani's spawn points from AllTheThings
#credit An example guide: edit a copy to improve it
#description Alani the Stormborn, a rare elite cloud serpent circling the Vale of Eternal Blossoms, drops [mount:517].

-- 1. Getting there: moves on by itself once you are in the Vale.
step Travel to the **Vale of Eternal Blossoms** in Pandaria
  note Any flying mount works; the Vale sits in the middle of Pandaria
  goto 390 56.2 42.6 Vale of Eternal Blossoms
  reach 200

-- 2. The shards: moves on once ten Skyshards are in your bags.
step Kill mobs in the Vale until you have **ten** [item:86547]
  note Skyshards are a **rare** drop from any mob in the Vale
  note Ten of them combine into a [item:86546]
  item 86547 10

-- 3. Finding her: three points on TomTom, the arrow picks the closest.
step Find **Alani**: she flies a loop around the Vale
  note Use the macro to check whether she is near
  goto 390 35.6 26 Alani (north)
  goto 390 38.6 64.6 Alani (south)
  goto 390 56.2 42.6 Alani (east)
  macro /tar Alani

-- 4. The fight.
step Use the [item:86546] near Alani to break her shield, then kill her
  note She is an **elite**: bring a friend or a strong character
  macro /tar Alani

-- 5. The prize: moves on (and finishes) once the mount is yours.
step Loot her: [mount:517] drops every time
  note In a group, make sure the loot goes to you (Master Looter)
  mount 517
```

## Adding a built-in guide (for contributors)

1. Write and test the guide in game, then export it.
2. Save it as `Guides/<Name>.lua`, appending the text to `ns.GuideTexts`
   (copy `Guides/ThunderingRubyCloudSerpent.lua`).
3. List the file in `MountTrail.toc` under the other `Guides\` lines.
4. Run `python3 tools/run_tests.py`; `tests/guide_spec.lua` shows how to check
   that a guide parses without errors.
