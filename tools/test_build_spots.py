"""Tests for tools/build_spots.py: python -m unittest tools/test_build_spots.py"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_spots as bs  # noqa: E402

ATT = '''
h(-732,{mapID=947,g={
m(525,{g={
h(-16,{g={
n(81001,{coords={
[525]={{13.1,50.4}}},g={
mnt(171851,{itemID=116794,lvl=10})}}),
n(50981,{coords={
[550]={{67.6,42.6},{72.8,53.4}}},isDaily=1,questID=37210,g={
mnt(171824,{itemID=116661})}}),
n(99999,{coords={
[525]={{1,1}}},rwp=60003,g={
mnt(171825,{itemID=116662})}}),
}}),
h(-58,{g={
n(4885,{r=2,g={
mnt(458,{b=1,itemID=5656,lvl=10,r=2}),
i(5655,{b=1})}}),
n(1460,{coords={
[56]={{9.2,56.6}}},r=2,g={
mnt(458,{b=1,itemID=5656,r=2})}}),
}}),
h(-652,{coords={
[371]={{52.56,18.85}},[379]={{75.11,67.47}}},g={
h(-19,{crs={69841},g={
mnt(138424,{b=1,itemID=94230})}}),
}}),
}}),
}})
-- n(1,{coords={[1]={{2,2}}},g={mnt(171851,{})}}) in a comment
local s = "n(2,{g={mnt(458,{})}})"
n(4885,{coords={
[70]={{65.2,51.4}}}})
'''

MOUNTS = {
    657: ("Garn Nighthowl", 171851, 116794),
    614: ("Mottled Meadowstomper", 171824, 116661),
    615: ("Removed rare's mount", 171825, 116662),
    6: ("Brown Horse", 458, 5656),
    18: ("Chestnut Mare", 6648, 5655),
    534: ("Amber Primordial Direhorn", 138424, 94230),
}
SOURCES = {
    657: "|cFFFFD200Drop:|r Nok-Karosh|n|cFFFFD200Zone:|r Frostfire Ridge",
    614: "|cFFFFD200Drop:|r Luk'hok|n|cFFFFD200Zone:|r Nagrand",
    6: "|cFFFFD200Vendor: |rUnger Statforth|n|cFFFFD200Zone: |rWetlands|n|cFFFFD200Cost: |r1",
    18: "|cFFFFD200Vendor: |rGregor MacVince|n|cFFFFD200Zone: |rDustwallow Marsh",
    534: "|cFFFFD200Drop:|r Zandalari Warbringer|n|cFFFFD200Zone:|r Dread Wastes, Kun-Lai Summit",
}
MAPS = {525: {"frostfire ridge"}, 550: {"nagrand"}, 56: {"wetlands"}, 70: {"dustwallow marsh"},
        371: {"the jade forest", "jade forest"}, 379: {"kun-lai summit"}}


class ScanTest(unittest.TestCase):
    def test_scan_skips_strings_and_comments(self):
        found = bs.scan(ATT, {171851, 458}, set())
        keys = [k for k, _, _ in found]
        self.assertEqual(keys.count(("spell", 171851)), 1)
        self.assertEqual(keys.count(("spell", 458)), 2)

    def test_coords_and_header(self):
        self.assertEqual(bs.parse_coords('coords={[525]={{13.1,50.4},{1,2}},[70]={{65.2,51.4}}}'),
                         [(525, 13.1, 50.4), (525, 1.0, 2.0), (70, 65.2, 51.4)])
        self.assertEqual(bs.parse_coords('r=2,'), [])
        self.assertTrue(bs.removed('coords={},rwp=60003,'))
        self.assertTrue(bs.removed('u=2,'))
        self.assertFalse(bs.removed('u=25,awp=1,'))

    def test_source_people(self):
        pairs = bs.source_pairs(SOURCES[534])
        self.assertEqual(bs.source_people(pairs), [("drop", "Zandalari Warbringer", ["dread wastes", "kun-lai summit"])])


class BuildTest(unittest.TestCase):
    def setUp(self):
        self.spots, self.stats = bs.build_spots(MOUNTS, [ATT], SOURCES, lambda m: MAPS.get(m, set()),
                                                {37210: "Luk'hok"})

    def test_rare_with_spawn_points_and_daily(self):
        self.assertEqual(self.spots[657], [{"npc": 81001, "pts": [(525, 13.1, 50.4)], "kind": "drop", "name": "Nok-Karosh"}])
        s = self.spots[614][0]
        self.assertEqual(s["pts"], [(550, 67.6, 42.6), (550, 72.8, 53.4)])
        self.assertEqual((s["quest"], s["daily"], s["name"]), (37210, True, "Luk'hok"))

    def test_removed_npcs_left_out(self):
        self.assertNotIn(615, self.spots)

    def test_vendor_kept_only_in_the_sources_zone(self):
        self.assertEqual([s["npc"] for s in self.spots[6]], [1460])
        self.assertEqual((self.spots[6][0]["kind"], self.spots[6][0]["name"], self.spots[6][0]["faction"]),
                         ("vendor", "Unger Statforth", "Alliance"))

    def test_coords_from_another_entry_of_the_npc(self):
        # Gregor MacVince (4885) has no coords where he sells the Chestnut Mare
        # (an i() entry), but his other entry has them.
        self.assertEqual(self.spots[18][0]["pts"], [(70, 65.2, 51.4)])
        self.assertEqual(self.spots[18][0]["name"], "Gregor MacVince")

    def test_drop_list_on_a_header_and_the_events_coords(self):
        s = self.spots[534][0]
        self.assertEqual(s["npc"], 69841)
        self.assertEqual(s["pts"], [(371, 52.56, 18.85), (379, 75.11, 67.47)])
        self.assertEqual(s["name"], "Zandalari Warbringer")

    def test_emit(self):
        text = bs.emit_lua(self.spots, MOUNTS, "abc", "1.2.3.4")
        self.assertIn("ns.Data.Spots = {", text)
        self.assertIn('{ npc = 81001, name = "Nok-Karosh", kind = "drop", pts = { 525, 13.1, 50.4 } },', text)
        self.assertIn("quest = 37210, daily = true", text)


if __name__ == "__main__":
    unittest.main()
