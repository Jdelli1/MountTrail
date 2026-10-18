-- Fixture for tools/test_verify_data.py
local ADDON, ns = ...
ns.Data = ns.Data or {}

ns.Data.Route = {
  {
    title = "Start",
    steps = {
      {
        title = "Run Test Keep (Raid)",
        type = "Raid",
        bosses = {
          { mount = 1, boss = "Fyrakk" },
          { mount = 2, boss = "Boss One", note = "says \"wrong\"" },
          { mount = 13, boss = "Big Mount" },
        },
      },
      {
        title = "Run Old Place (Dungeon)",
        steps = {
          {
            title = "Inner",
            bosses = {
              { mount = 3, boss = "Trash" },
              { mount = 6, boss = "Lich King" },
              { alliance = true, mount = 2, boss = "Deios" },
              { mount = 10, boss = "Timed Reward" },
              { mount = 17, boss = "King Gear" },
              { mount = 99, boss = "Nobody" },
            },
          },
        },
      },
    },
  },
}
