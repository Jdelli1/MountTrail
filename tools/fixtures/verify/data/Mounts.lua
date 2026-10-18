-- Fixture for tools/test_verify_data.py
local ADDON, ns = ...
ns.Data = ns.Data or {}

ns.Data.Expansions = { "Classic", "Dragonflight" }

ns.Data.Mounts = {
  [1] = { name = "Alpha Drake", spell = 1001, item = 501, exp = "Dragonflight", tab = "journal", coords = { m = 1, x = 2.5, y = 3 } },
  [2] = { name = "Beta Steed", spell = 1002, item = 502, exp = "Classic" },
  [3] = { name = "Gamma  wyrm", spell = 1003, item = 503 }, -- case/space differ: still equal
  [4] = { name = "Delta Ram", spell = 1004 },
  [5] = { name = "Ghost Mount", spell = 1005 },
  [6] = { name = "Epsilon Cat", spell = 1006, item = 506 },
  [7] = { name = "Zeta Hawk", spell = 1007, item = 508 },
  [8] = { name = "Eta Bear", spell = 1008 },
  [9] = { name = "Theta Bear", spell = 1009 },
  [10] = { name = "Iota Bear", spell = 1010, item = 510 },
  [11] = { name = "Kappa Bear", spell = 1011 },
  [12] = { name = "Lambda Bear", spell = 1012, item = 512 },
  [13] = { name = "Mu Raptor", spell = 1013, item = 513, exp = "Dragonflight" },
  [14] = { name = "Nu Serpent", spell = 1014, exp = "Classic" },
  [15] = { name = "Xi Mammoth", spell = 1015 },
  [16] = { name = "Omicron Serpent", spell = 1016, item = 516, quest = 123 },
  [17] = { name = "Pi Drake", spell = 1017, item = 517 },
  [18] = { name = "Rho Shark", spell = 1018, item = 518 },
  [19] = { name = "Sigma Shark", spell = 1019, item = 519 },
  [20] = { name = "Tau Gear", spell = 1020, item = 520 },
}
