"""Tests for tools/build_zones.py: python -m unittest tools/test_build_zones.py"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_zones  # noqa: E402


def m(i, name, kind, parent, tuning=0):
    return {"ID": str(i), "Name_lang": name, "Type": str(kind), "ParentUiMapID": str(parent),
            "ContentTuningID": str(tuning)}


UIMAP = [
    m(946, "Cosmic", 0, 0),
    m(947, "Azeroth", 1, 946),
    m(13, "Eastern Kingdoms", 2, 947, tuning=900),   # tuned for the newest expansion
    m(101, "Outland", 2, 946),
    m(572, "Draenor", 2, 946),
    m(107, "Nagrand", 3, 101, tuning=40),
    m(550, "Nagrand", 3, 572, tuning=68),
    m(110, "Silvermoon City", 3, 13),
    m(2395, "Eversong Woods", 3, 2537, tuning=3085),
    m(2537, "Quel'Thalas", 2, 13, tuning=3085),
    m(2393, "Silvermoon City", 3, 2395),               # no tuning: the zone above it
    m(1269, "Silvermoon City", 3, 1208),               # a flight-map copy, not in the tree
    m(1208, "Eastern Kingdoms", 2, 0),
    m(52, "Westfall", 3, 13, tuning=6),
]
TUNING = [
    {"ID": "40", "ExpansionID": "1"},
    {"ID": "68", "ExpansionID": "5"},
    {"ID": "3085", "ExpansionID": "11"},
    {"ID": "900", "ExpansionID": "11"},
    {"ID": "6", "ExpansionID": "0"},
]


class ZoneVersionsTest(unittest.TestCase):
    def setUp(self):
        self.versions, self.names = build_zones.zone_versions(UIMAP, TUNING)

    def test_same_named_zones_in_the_tree_only(self):
        self.assertEqual(sorted(self.versions), [107, 110, 550, 2393])
        self.assertNotIn(1269, self.versions, "copy outside the world map's tree")
        self.assertNotIn(52, self.versions, "unique name")

    def test_groups_and_expansions(self):
        self.assertEqual(self.versions[107], (1, 1))
        self.assertEqual(self.versions[550], (1, 5))
        self.assertEqual(self.versions[110], (2, None), "continent tuning is not used")
        self.assertEqual(self.versions[2393], (2, 11), "from the zone above it")

    def test_emit(self):
        text = build_zones.emit_lua(self.versions, self.names, "1.2.3.4")
        self.assertIn("ns.Data.ZoneVersions = {", text)
        self.assertIn("[107] = { g = 1, e = 1 }, -- Nagrand (The Burning Crusade)", text)
        self.assertIn("[110] = { g = 2 }, -- Silvermoon City\n", text)
        self.assertIn("build 1.2.3.4", text)


if __name__ == "__main__":
    unittest.main()
