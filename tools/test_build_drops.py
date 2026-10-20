"""Tests for tools/build_drops.py: python -m unittest tools/test_build_drops.py"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_drops  # noqa: E402

MOUNTS = {
    363: {"name": "Invincible", "item": 50818},
    349: {"name": "Onyxian Drake", "item": 49636},
    395: {"name": "Drake of the North Wind", "item": 63040},
    1: {"name": "Vendor mount", "item": 999},
    2: {"name": "No item"},
}
ITEMS = [  # JournalEncounterItem
    {"ID": "10", "JournalEncounterID": "100", "ItemID": "50818"},
    {"ID": "11", "JournalEncounterID": "101", "ItemID": "49636"},
    {"ID": "12", "JournalEncounterID": "102", "ItemID": "63040"},
    {"ID": "13", "JournalEncounterID": "103", "ItemID": "63040"},  # a second boss, same instance
]
ENCOUNTERS = [
    {"ID": "100", "JournalInstanceID": "1000"},
    {"ID": "101", "JournalInstanceID": "1001"},
    {"ID": "102", "JournalInstanceID": "1002"},
    {"ID": "103", "JournalInstanceID": "1002"},
]
INSTANCES = [
    {"ID": "1000", "MapID": "631"},
    {"ID": "1001", "MapID": "249"},
    {"ID": "1002", "MapID": "657"},
]
DIFFS = [  # JournalItemXDifficulty
    {"DifficultyID": "6", "JournalEncounterItemID": "10"},
    {"DifficultyID": "2", "JournalEncounterItemID": "12"},
    {"DifficultyID": "1", "JournalEncounterItemID": "13"},
]


class JournalDropsTest(unittest.TestCase):
    def setUp(self):
        self.drops = build_drops.journal_drops(MOUNTS, ITEMS, ENCOUNTERS, INSTANCES, DIFFS)

    def test_difficulties_from_the_journal(self):
        self.assertEqual(self.drops[363], {"map": 631, "d": [6]})

    def test_no_rows_means_every_difficulty(self):
        self.assertEqual(self.drops[349], {"map": 249, "d": None})

    def test_several_bosses_merge(self):
        self.assertEqual(self.drops[395], {"map": 657, "d": [1, 2]})

    def test_not_boss_loot_is_left_out(self):
        self.assertNotIn(1, self.drops)
        self.assertNotIn(2, self.drops)

    def test_lua(self):
        lua = build_drops.emit_lua(self.drops, MOUNTS, "12.1.5.1")
        self.assertIn("ns.Data.JournalDrops = {", lua)
        self.assertIn("[363] = { map = 631, d = { 6 } }, -- Invincible", lua)
        self.assertIn("[349] = { map = 249 }, -- Onyxian Drake", lua)


if __name__ == "__main__":
    unittest.main()
