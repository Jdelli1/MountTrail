-- Hand-written holiday data: holiday key (Data/Mounts.lua `section` on the
-- holiday tab) -> calendar event title (enUS, matched against C_Calendar
-- HOLIDAY events), LFG dungeon of the holiday boss, map location and the
-- mounts that boss drops. Only events with `mounts` produce a route step;
-- the others exist so the Holidays tab can name the section and show
-- "Active now".
-- Coordinates follow the Rarity data already in Data/Mounts.lua (GPL-2.0).

local ADDON, ns = ...
ns.Data = ns.Data or {}

ns.Data.Holidays = {
  hallowsend = {
    title = "Hallow's End",
    lfg = 285, -- The Headless Horseman
    coords = { m = 435 }, -- Scarlet Monastery (instance map, no pin)
    mounts = { 219, 2623 },
    stepTitle = "Queue for the Headless Horseman (Hallow's End)",
  },
  brewfest = {
    title = "Brewfest",
    lfg = 287, -- Coren Direbrew
    coords = { m = 242, x = 46.6, y = 60.0 }, -- Blackrock Depths, Grim Guzzler
    mounts = { 202, 226, 2640 },
    stepTitle = "Queue for Coren Direbrew (Brewfest)",
  },
  loveisintheair = {
    title = "Love is in the Air",
    lfg = 288, -- The Crown Chemical Co.
    coords = { m = 310, x = 40.8, y = 52.6 }, -- Shadowfang Keep
    mounts = { 352, 2328, 2492 },
    stepTitle = "Queue for Apothecary Hummel (Love is in the Air)",
  },
  -- LfgDungeons 286 "The Frost Lord Ahune" (Group_ID 11 with 285/287/288; MapID 547, The Slave Pens),
  -- build 12.1.5.70448 (tools/verify_data.py). Mount.db2 3036: "Drop: Ahune; Holiday: Midsummer".
  -- No coords: the map location is not in the verified tables -- verify in game.
  midsummer = {
    title = "Midsummer Fire Festival",
    lfg = 286, -- The Frost Lord Ahune
    mounts = { 3036 },
    stepTitle = "Queue for Ahune (Midsummer Fire Festival)",
  },

  -- Calendar titles only (no holiday-boss mounts).
  noblegarden   = { title = "Noblegarden", mounts = {} },
  winterveil    = { title = "Feast of Winter Veil", mounts = {} },
  lunarfestival = { title = "Lunar Festival", mounts = {} },
  darkmoon      = { title = "Darkmoon Faire", mounts = {} },
}
