-- Fixture for tools/test_verify_data.py
local ADDON, ns = ...
ns.Data = ns.Data or {}

ns.Data.Lockouts = {
  [7]  = { instance = 100, boss = "Fyrakk", difficulties = { { 14, 15 }, 16 }, reset = "weekly" }, -- verify in game
  [8]  = { instance = 999, boss = "Anyone", difficulties = { 2 }, reset = "daily" },
  [9]  = { instance = 100, boss = "Nobody", difficulties = { 2 }, reset = "daily" },
  [10] = { instance = 100, boss = "Boss One", difficulties = { 2 }, reset = "daily" },
  [11] = { instance = 100, boss = "Hidden Thing", difficulties = { 2 }, reset = "daily" },
  [12] = { instance = 100, boss = "Fyrakk, the Blazing", difficulties = { 16 }, reset = "weekly" },
  [17] = { instance = 200, boss = "King Gear", difficulties = { 23 }, reset = "weekly" },
  [3]  = { manual = true, reset = "weekly", repeatable = true },
  [15] = { lfg = 285, reset = "daily" },
  [18] = { instance = 200, boss = "Harlan", difficulties = { 23 }, reset = "weekly" },
  [19] = { instance = 200, boss = "The Harlan", difficulties = { 23 }, reset = "weekly" },
  [20] = { instance = 200, boss = "King", difficulties = { 23 }, reset = "weekly" },
  [21] = { lfg = 286, reset = "daily" },
  [23] = { instance = 200, boss = "Gamma, The Old King", difficulties = { 23 }, reset = "weekly" },
  [24] = { instance = 200, boss = "Gamma", difficulties = { 23 }, reset = "weekly" },
  [22] = { lfg = 777, reset = "daily" },
}

ns.Data.BossLockouts = {
  ["Deios"] = { instance = 200, boss = "Chrono-Lord Deios", difficulties = { 2 }, reset = "daily" },
}
