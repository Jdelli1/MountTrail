"""Unit tests for tools/build_data.py. Run: python -m unittest tools/test_build_data.py -v"""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import build_data  # noqa: E402

FIX = os.path.join(HERE, "fixtures")


def fixture_text(name):
    with open(os.path.join(FIX, name), encoding="utf-8") as fh:
        return fh.read()


class BuildDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sa = build_data.load_sa(os.path.join(FIX, "sa_mounts.json"), os.path.join(FIX, "sa_planner.json"))
        cls.map_ids = build_data.parse_map_ids(fixture_text("rarity_constants.lua"))
        cls.rarity = build_data.parse_rarity([fixture_text("rarity_sample.lua")], cls.map_ids)
        cls.mounts = build_data.build_mounts(cls.sa, cls.rarity)
        cls.route = build_data.build_route(cls.sa["planner"])

    # --- required by the brief -------------------------------------------------

    def test_dungeon_drop_classified(self):
        m = self.mounts[395]
        self.assertEqual(m["tab"], "journal")
        self.assertEqual(m["section"], "dungeon")
        self.assertEqual(m["exp"], "Cataclysm")
        self.assertEqual(m["group"], "Dungeon Drop")
        self.assertEqual(m["name"], "Drake of the North Wind")
        self.assertEqual(m["spell"], 88742)
        self.assertEqual(m["item"], 63040)
        self.assertEqual(m["icon"], "inv_misc_stormdragonpale")

    def test_faction_subcat_is_reputation(self):
        m = self.mounts[186]
        self.assertEqual((m["tab"], m["section"], m["exp"]), ("journal", "reputation", "The Burning Crusade"))

    def test_world_event_is_holiday(self):
        m = self.mounts[219]
        self.assertEqual(m["tab"], "holiday")
        self.assertEqual(m["section"], "hallowsend")
        self.assertIsNone(m.get("exp"))

    def test_trading_post_now(self):
        now = self.mounts[532]
        self.assertEqual((now["tab"], now["section"]), ("misc", "tradingpost"))
        self.assertIs(now.get("tradingNow"), True)
        past = self.mounts[1577]
        self.assertEqual((past["tab"], past["section"]), ("misc", "tradingpost"))
        self.assertFalse(past.get("tradingNow"))

    def test_rarity_join(self):
        m = self.mounts[473]
        self.assertEqual(m["chance"], 100)
        self.assertEqual(m["quest"], 32099)
        self.assertEqual(m["coords"], {"m": 379, "x": 53.7, "y": 64.7})

    def test_route_tree_renamed(self):
        root = self.route[0]
        self.assertIs(root["capital"], True)
        portal = root["steps"][0]
        kill = portal["steps"][0]
        self.assertEqual(kill["bosses"][0]["mount"], 395)
        self.assertEqual(kill["bosses"][0]["boss"], "Altairus")
        self.assertEqual(kill["bosses"][0]["note"], "You can run Heroic once per day")
        self.assertEqual(kill["type"], "Dungeon")
        boat = root["steps"][1]
        self.assertIs(boat["alliance"], True)
        self.assertIs(boat["capital"], True)
        self.assertNotIn("isAlliance", boat)

    def test_lua_emit_round_trip(self):
        mounts = {
            395: {"name": "Drake of the North Wind", "spell": 88742, "tab": "journal"},
            304: {"name": "Mimiron's Head", "spell": 63796},
            1: {"name": 'Say "Hi"', "spell": 1},
        }
        text = build_data.emit_lua(mounts=mounts)
        self.assertIn("[395] = {", text)
        self.assertIn('"Mimiron\'s Head"', text)
        self.assertIn('"Say \\"Hi\\""', text)
        self.assertTrue(text.startswith("-- "))
        self.assertIn("local ADDON, ns = ...", text)
        self.assertIn("ns.Data = ns.Data or {}", text)
        self.assertIn("ns.Data.Mounts = {", text)
        self.assertIn("ns.Data.Expansions = {", text)

    # --- extra coverage ----------------------------------------------------------

    def test_classify_table(self):
        c = build_data.classify
        self.assertEqual(c("Cataclysm", "Raid Drop"), ("journal", "raid"))
        self.assertEqual(c("The War Within", "Raid Renown"), ("journal", "raid"))
        self.assertEqual(c("Mists of Pandaria", "Challenge Mode"), ("journal", "dungeon"))
        for sub in ("Rare Spawn", "World Boss", "Zone Drop", "Nemesis Drop", "Prey Drop", "Tormentors", "Treasure"):
            self.assertEqual(c("Midnight", sub), ("journal", "world"), sub)
        for sub in ("Reputation", "Paragon Reputation", "Renown", "Cenarion Expedition", "Kurenai/The Mag'har",
                    "Netherwing", "Sha'tari Skyguard", "Golden Lotus", "Order of the Cloud Serpent",
                    "Shado-Pan", "The Tillers"):
            self.assertEqual(c("Legion", sub), ("journal", "reputation"), sub)
        self.assertEqual(c("Mists of Pandaria", "Kun-Lai Vendor"), ("journal", "vendor"))
        self.assertEqual(c("Legion", "Vendor"), ("journal", "vendor"))
        self.assertEqual(c("Legion", "Achievement"), ("misc", "achievement"))
        self.assertEqual(c("Legion", "Class Hall"), ("journal", "other"))
        self.assertEqual(c("Professions", "Alchemy"), ("misc", "profession"))
        self.assertEqual(c("Promotion", "Blizzard Store"), ("misc", "shop"))
        self.assertEqual(c("Promotion", "Blizzcon"), ("misc", "other"))
        self.assertEqual(c("Limited Time", "Trading Post: November"), ("misc", "tradingpost"))
        self.assertEqual(c("Limited Time", "Midnight: Season 2"), ("misc", "other"))
        self.assertEqual(c("Past Limited Time", "Trading Post Re-Releases"), ("misc", "tradingpost"))
        self.assertEqual(c("Past Limited Time", "Plunderstorm"), ("misc", "other"))
        self.assertEqual(c("World Events", "Brewfest"), ("holiday", "brewfest"))
        self.assertEqual(c("World Events", "Love is in the Air"), ("holiday", "loveisintheair"))
        self.assertEqual(c("World Events", "Midsummer Fire Festival"), ("holiday", "midsummer"))
        self.assertEqual(c("World Events", "Darkmoon Faire"), ("holiday", "darkmoon"))
        self.assertEqual(c("World Events", "Brawler's Guild"), ("holiday", "other"))
        for top in ("Mounts", "Racial", "Mythic+", "PVP", "Other"):
            self.assertEqual(c(top, "Anything"), ("misc", "other"), top)

    def test_achievement_keeps_exp_and_misc_has_no_exp(self):
        self.assertEqual(self.mounts[415]["exp"], "Cataclysm")
        self.assertEqual((self.mounts[415]["tab"], self.mounts[415]["section"]), ("misc", "achievement"))
        self.assertIsNone(self.mounts[285].get("exp"))
        self.assertEqual(self.mounts[285]["section"], "profession")
        self.assertEqual(self.mounts[376]["section"], "shop")
        self.assertEqual(self.mounts[230]["section"], "other")

    def test_duplicates_prefer_specific_classification(self):
        # Limited Time/Vendor (misc/other) loses to Midnight/Vendor (journal/vendor).
        m = self.mounts[3137]
        self.assertEqual((m["tab"], m["section"], m["exp"]), ("journal", "vendor", "Midnight"))
        # Trading Post: October seen first keeps tradingNow; the later Re-Releases copy does not override.
        self.assertIs(self.mounts[532]["tradingNow"], True)

    def test_item_id_coerced_and_missing_item_ok(self):
        self.assertEqual(self.mounts[151]["item"], 29745)
        self.assertIsNone(self.mounts[1006].get("item"))

    def test_parse_rarity_details(self):
        r = self.rarity
        self.assertEqual(set(r), {127158, 88742, 1, 88744, 3, 4})
        north = r[88742]
        self.assertEqual(north["quest"], 52001)
        self.assertEqual(r[1]["chance"], 5)
        self.assertNotIn("coords", r[1])
        self.assertNotIn("quest", r[1])

    def test_route_drops_empty_and_keeps_flags(self):
        root = self.route[0]
        self.assertEqual(len(root["steps"]), 3)  # the empty {} node is dropped
        self.assertNotIn("startStep", root)
        ulduar = root["steps"][1]["steps"][0]
        self.assertEqual([b["mount"] for b in ulduar["bosses"]], [304, 999])
        self.assertIs(ulduar["bosses"][1]["horde"], True)
        self.assertIsNone(ulduar["bosses"][1].get("note"))
        self.assertIs(root["steps"][2]["unavailable"], True)

    def test_route_emit(self):
        text = build_data.emit_lua(route=self.route)
        self.assertIn("ns.Data.Route = {", text)
        self.assertIn("mount = 395", text)
        self.assertIn('boss = "Altairus"', text)
        self.assertIn("alliance = true", text)
        self.assertNotIn("ns.Data.Mounts", text)

    def test_header_names_sources(self):
        sources = {"simplearmory": {"repo": "kevinclement/SimpleArmory", "commit": "abc123"},
                   "rarity": {"repo": "WowRarity/Rarity", "commit": "def456"}}
        text = build_data.emit_lua(mounts={395: {"name": "x"}}, sources=sources)
        head = text.split("local ADDON", 1)[0]
        self.assertIn("GENERATED by tools/build_data.py", head)
        self.assertIn("do not edit", head)
        self.assertIn("abc123", head)
        self.assertIn("def456", head)
        self.assertIn("MIT", head)
        self.assertIn("GPL-2.0", head)

    def test_lua_floats_and_sorting(self):
        text = build_data.emit_lua(mounts={10: {"coords": {"m": 1, "x": 60.0, "y": 5.25}}, 2: {"name": "a"}})
        self.assertIn("x = 60.0", text)
        self.assertLess(text.index("[2] = {"), text.index("[10] = {"))

    # --- fix round 1: map constants, faction, unobtainable, minors ------------------

    def test_parse_map_ids(self):
        self.assertEqual(self.map_ids, {"NONE": 0, "ULDUM": 249, "SKYWALL": 325, "VASHJIR": 203})

    def test_symbolic_map_constant_resolved(self):
        # First coord entry is CONSTANTS.UIMAPIDS.ULDUM with x/y: it is now the first full triple.
        self.assertEqual(self.rarity[88742]["coords"], {"m": 249, "x": 1.0, "y": 2.0})

    def test_m_only_coords(self):
        r = self.rarity
        # NONE (0) and unknown constants are not resolvable; SKYWALL is the first resolvable map.
        self.assertEqual(r[88744]["coords"], {"m": 325})
        self.assertEqual(r[3]["coords"], {"m": 504})
        self.assertNotIn("coords", r[4])
        self.assertEqual(self.mounts[396]["coords"], {"m": 325})
        text = build_data.emit_lua(mounts={396: self.mounts[396]})
        self.assertIn("coords = { m = 325 }", text)

    def test_without_map_ids_symbolic_is_skipped(self):
        r = build_data.parse_rarity([fixture_text("rarity_sample.lua")])
        self.assertEqual(r[88742]["coords"], {"m": 325, "x": 60.0, "y": 58.0})
        self.assertEqual(r[88744]["coords"], {"m": 203})

    def test_unobtainable_only_if_every_sighting(self):
        self.assertIs(self.mounts[1006]["unobtainable"], True)
        self.assertIs(self.mounts[901]["unobtainable"], True)
        self.assertNotIn("unobtainable", self.mounts[900])
        self.assertNotIn("unobtainable", self.mounts[395])
        self.assertIn("unobtainable = true", build_data.emit_lua(mounts={1006: self.mounts[1006]}))

    def test_faction_union(self):
        self.assertEqual(self.mounts[151]["faction"], "Alliance")
        self.assertEqual(self.mounts[3002]["faction"], "Alliance")  # A in both sightings
        self.assertEqual(self.mounts[3003]["faction"], "Horde")
        self.assertNotIn("faction", self.mounts[768])  # seen as H and as A
        self.assertNotIn("faction", self.mounts[395])
        for rec in self.mounts.values():
            self.assertNotIn("side", rec)
        self.assertIn('faction = "Horde"', build_data.emit_lua(mounts={3003: self.mounts[3003]}))

    def test_faction_union_side_and_no_side(self):
        sa = {"mounts": [
            {"name": "Legion", "subcats": [{"name": "Vendor", "items": [
                {"ID": 5, "name": "x", "spellid": 5, "side": "A"},
                {"ID": 5, "name": "x", "spellid": 5}]}]}]}
        self.assertNotIn("faction", build_data.build_mounts(sa, {})[5])

    def test_lua_escaping(self):
        text = build_data.emit_lua(mounts={
            1: {"name": "Back\\slash"},
            2: {"name": "Line\nbreak"},
            3: {"name": "Ünïcode Drake ☃"},
        })
        self.assertIn('"Back\\\\slash"', text)
        self.assertIn('"Line\\nbreak"', text)
        self.assertIn('"Ünïcode Drake ☃"', text)
        self.assertNotIn("Line\nbreak", text)

    def test_header_copyright_from_license(self):
        lic = "MIT License\n\nCopyright (c) 2099 Some Author\n\nPermission is hereby granted..."
        self.assertEqual(build_data.license_copyright(lic), "Copyright (c) 2099 Some Author")
        self.assertIsNone(build_data.license_copyright("no notice here"))
        text = build_data.emit_lua(mounts={1: {"name": "a"}}, copyright="Copyright (c) 2099 Some Author")
        head = text.split("local ADDON", 1)[0]
        self.assertIn("Copyright (c) 2099 Some Author", head)
        self.assertNotIn("Kevin Clement", build_data.emit_lua(mounts={1: {"name": "a"}}))

    def test_retry_policy(self):
        self.assertTrue(build_data._should_retry(429, {}))
        self.assertTrue(build_data._should_retry(403, {"X-RateLimit-Remaining": "0"}))
        self.assertFalse(build_data._should_retry(403, {"X-RateLimit-Remaining": "12"}))
        self.assertFalse(build_data._should_retry(403, {}))
        self.assertFalse(build_data._should_retry(404, {}))

    def test_update_writes_sources_only_after_generation(self):
        import tempfile
        from unittest import mock
        original = '{"simplearmory": {"repo": "a/b", "commit": "old1"}, "rarity": {"repo": "c/d", "commit": "old2"}}\n'
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "sources.json")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(original)
            with mock.patch.object(build_data, "SOURCES_PATH", path), \
                    mock.patch.object(build_data, "resolve_master", return_value="newsha"), \
                    mock.patch.object(build_data, "generate", side_effect=RuntimeError("boom")):
                with self.assertRaises(RuntimeError):
                    build_data.main(["--update"])
            with open(path, encoding="utf-8") as fh:
                self.assertEqual(fh.read(), original)
            with mock.patch.object(build_data, "SOURCES_PATH", path), \
                    mock.patch.object(build_data, "resolve_master", return_value="newsha"), \
                    mock.patch.object(build_data, "generate", return_value=None) as gen:
                build_data.main(["--update"])
            self.assertEqual(gen.call_args[0][0]["rarity"]["commit"], "newsha")
            with open(path, encoding="utf-8") as fh:
                self.assertIn("newsha", fh.read())


if __name__ == "__main__":
    unittest.main()
