"""Tests for tools/verify_data.py. Run: python -m unittest tools/test_verify_data.py

Fixtures: tools/fixtures/verify/db2/*.csv (tiny DB2 tables) and
tools/fixtures/verify/data/*.lua (tiny Data/ files). No network.
"""
import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verify_data as v  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "verify")
DB2 = os.path.join(FIXTURES, "db2")
DATA = os.path.join(FIXTURES, "data")


class NormalisationTest(unittest.TestCase):
    def test_norm_boss(self):
        self.assertEqual(v.norm_boss("The Lich King"), "lich king")
        self.assertEqual(v.norm_boss("Kael'thas Sunstrider"), "kaelthas sunstrider")
        self.assertEqual(v.norm_boss("Kael’thas"), "kaelthas")
        self.assertEqual(v.norm_boss("Dimensius, the All-Devouring"), "dimensius the all devouring")
        self.assertEqual(v.norm_boss("  Ra-dén "), "ra den")

    def test_boss_match_kinds(self):
        self.assertEqual(v.boss_match("Lich King", "The Lich King"), "exact")
        self.assertEqual(v.boss_match("al'akir", "Al'Akir"), "exact")
        self.assertEqual(v.boss_match("Fyrakk", "Fyrakk the Blazing"), "prefix")
        self.assertEqual(v.boss_match("Fyrakk the Blazing", "Fyrakk"), "prefix")
        self.assertEqual(v.boss_match("Kael'thas", "Kael'thas Sunstrider"), "prefix")
        self.assertEqual(v.boss_match("Rivendare", "Lord Aurius Rivendare"), "contains")
        self.assertEqual(v.boss_match("Deios", "Chrono-Lord Deios"), "contains")

    def test_boss_match_rejects_partial_words_and_empty(self):
        self.assertIsNone(v.boss_match("Fyr", "Fyrakk the Blazing"))
        self.assertIsNone(v.boss_match("Boss One", "Chrono-Lord Deios"))
        self.assertIsNone(v.boss_match("", "Onyxia"))
        self.assertIsNone(v.boss_match("The", "The Nine"))

    def test_addon_match_is_case_insensitive_substring_either_way(self):
        # Logic/Lockouts.lua bossMatches (F12): plain containment, either way.
        self.assertTrue(v.addon_match("Fyrakk", "Fyrakk the Blazing"))
        self.assertTrue(v.addon_match("Fyrakk the Blazing", "Fyrakk"))
        self.assertTrue(v.addon_match("fyrakk", "Fyrakk the Blazing"))
        self.assertTrue(v.addon_match("Harlan Sweete", "Lord Harlan Sweete"))
        self.assertTrue(v.addon_match("High Tinker Mekkatorque", "Mekkatorque"))
        self.assertFalse(v.addon_match("Fyrakk, the Blazing", "Fyrakk the Blazing"), "punctuation is literal")
        self.assertFalse(v.addon_match("Archavon the Stone Watcher", "Koralon the Flame Watcher"))
        self.assertFalse(v.addon_match("", "Onyxia"))
        self.assertFalse(v.addon_match("Onyxia", ""))

    def test_norm_mount(self):
        self.assertEqual(v.norm_mount("Gamma  wyrm"), v.norm_mount("Gamma Wyrm"))
        self.assertNotEqual(v.norm_mount("Delta Ram"), v.norm_mount("Delta Mountain Ram"))

    def test_source_text(self):
        text = "|cFFFFD200Drop: |rRare Guy|n|cFFFFD200Zone: |rSomewhere|n|cFFFFD200Cost: |r1|TINTERFACE\\X.BLP:0|t"
        self.assertEqual(v.clean_source_text(text), "Drop: Rare Guy; Zone: Somewhere; Cost: 1")
        self.assertEqual(v.source_fields(text), {"drop": ["Rare Guy"], "zone": ["Somewhere"], "cost": ["1"]})


class LuaParserTest(unittest.TestCase):
    def test_tables_strings_comments(self):
        src = '''
local ADDON, ns = ...
-- a comment { not a table
ns.Data.X = {
  [7] = { name = "A \\"q\\" b", n = -2.5, ok = true, none = nil, list = { 1, 2, { 3 } } }, -- trailing
  ["Key"] = { "x"; "y" },
  --[[ block
  comment ]]
}
ns.Data.Y = 1 + 2 -- not a literal table; parser never reaches it
'''
        x = v.lua_assignment(src, "ns.Data.X")
        self.assertEqual(x[7]["name"], 'A "q" b')
        self.assertEqual(x[7]["n"], -2.5)
        self.assertIs(x[7]["ok"], True)
        self.assertEqual(x[7]["list"], [1, 2, [3]])
        self.assertEqual(x["Key"], ["x", "y"])
        self.assertIsNone(v.lua_assignment(src, "ns.Data.Missing"))

    def test_fixture_data(self):
        ours = v.load_our_data(DATA)
        self.assertEqual(ours["mounts"][1]["coords"], {"m": 1, "x": 2.5, "y": 3})
        self.assertEqual(ours["lockouts"][7]["difficulties"], [[14, 15], 16])
        self.assertEqual(ours["boss_lockouts"]["Deios"]["boss"], "Chrono-Lord Deios")
        rows = v.route_rows(ours["route"])
        self.assertEqual(len(rows), 9)
        path, row = rows[3]
        self.assertEqual(path, ["Start", "Run Old Place (Dungeon)", "Inner"])
        self.assertEqual(row, {"mount": 3, "boss": "Trash"})


class ChecksTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ours = v.load_our_data(DATA)
        cls.game = v.Game(DB2)

    def run_all(self, allow=None):
        return v.run(self.ours, self.game, allow or {})

    def find(self, findings, check, key, kind=None):
        hits = [f for f in findings if f["check"] == check and f["key"] == key
                and (kind is None or f["kind"] == kind)]
        return hits

    # identity
    def test_name_mismatch_is_warn_and_case_space_insensitive(self):
        f = v.check_identity(self.ours, self.game)
        (hit,) = self.find(f, "identity", "4", "name-mismatch")
        self.assertEqual(hit["severity"], "warn")
        self.assertIn("Delta Mountain Ram", hit["detail"])
        self.assertEqual(self.find(f, "identity", "3"), [])  # "Gamma  wyrm" == "Gamma Wyrm"

    def test_missing_mount_and_spell_mismatch_are_errors(self):
        f = v.check_identity(self.ours, self.game)
        (missing,) = self.find(f, "identity", "5", "missing-mount")
        self.assertEqual(missing["severity"], "error")
        (spell,) = self.find(f, "identity", "4", "spell-mismatch")
        self.assertEqual(spell["severity"], "error")
        self.assertIn("1040", spell["suggestion"])

    def test_item_that_teaches_another_spell(self):
        f = v.check_identity(self.ours, self.game)
        (hit,) = self.find(f, "identity", "6", "item-mismatch")
        self.assertIn("507", hit["suggestion"])

    # route
    def test_route_prefix_and_contains_matches_pass(self):
        f = v.check_route(self.ours, self.game)
        self.assertEqual(self.find(f, "route", "1@Fyrakk"), [])
        self.assertEqual(self.find(f, "route", "2@Deios"), [])
        # Lich King: our item 506 is wrong, but item 507 teaches the mount's spell.
        self.assertEqual(self.find(f, "route", "6@Lich King"), [])

    def test_wrong_boss_names_the_real_encounter(self):
        f = v.check_route(self.ours, self.game)
        (hit,) = self.find(f, "route", "2@Boss One", "wrong-boss")
        self.assertEqual(hit["severity"], "error")
        self.assertIn("Chrono-Lord Deios", hit["detail"])
        self.assertIn("Old Place", hit["detail"])

    def test_not_in_loot_warns_and_allowlist_downgrades(self):
        f = v.check_route(self.ours, self.game)
        (hit,) = self.find(f, "route", "10@Timed Reward", "not-in-loot")
        self.assertEqual(hit["severity"], "warn")
        findings = self.run_all({"route": {"3@Trash": "AQ trash drop"}})[0]
        (trash,) = self.find(findings, "route", "3@Trash")
        self.assertEqual(trash["severity"], "info")
        self.assertEqual(trash["allowed"], "AQ trash drop")
        self.assertEqual(trash["original_severity"], "warn")

    def test_source_text_and_description_downgrade_to_info(self):
        f = v.check_route(self.ours, self.game)
        (gear,) = self.find(f, "route", "17@King Gear")
        self.assertEqual((gear["kind"], gear["severity"]), ("source-text-only", "info"))
        (big,) = self.find(f, "route", "13@Big Mount")
        self.assertEqual((big["kind"], big["severity"]), ("boss-in-description", "info"))

    def test_unavailable_route_row_in_journal_loot_warns(self):
        # Mount 1 (item 501) is Encounter Journal loot of Fyrakk; mount 3
        # (Trash) is in no loot. An unavailable step (or one under an
        # unavailable step, or a row flagged itself) with journal loot warns.
        route = [{"title": "Start", "steps": [
            {"title": "Run Gone Keep (Raid)", "unavailable": True, "bosses": [
                {"mount": 1, "boss": "Fyrakk"}, {"mount": 3, "boss": "Trash"}]},
            {"title": "Gone Wing", "unavailable": True, "steps": [
                {"title": "Inner", "bosses": [{"mount": 1, "boss": "Inner Fyrakk"}]}]},
            {"title": "Run Live Keep (Raid)", "bosses": [
                {"mount": 1, "boss": "Live Fyrakk"}, {"mount": 1, "boss": "Row Gone", "unavailable": True}]},
        ]}]
        ours = dict(self.ours, route=route)
        f = v.check_unavailable(ours, self.game)
        keys = sorted(h["key"] for h in f)
        self.assertEqual(keys, ["1@Fyrakk", "1@Inner Fyrakk", "1@Row Gone"])
        (hit,) = self.find(f, "unavailable", "1@Fyrakk", "unavailable-in-loot")
        self.assertEqual(hit["severity"], "warn")
        self.assertIn("marked unavailable but in Encounter Journal loot", hit["detail"])
        self.assertIn("Fyrakk", hit["detail"])
        counts, _ = v.summarise(f)
        self.assertEqual(counts["unavailable"]["warn"], 3, "a report section of its own")
        # Part of the full run.
        findings = v.run(ours, self.game, {})[0]
        self.assertEqual(len(self.find(findings, "unavailable", "1@Fyrakk")), 1)
        # The fixture route has no unavailable rows.
        self.assertEqual(v.check_unavailable(self.ours, self.game), [])

    def test_route_row_with_unknown_mount(self):
        f = v.check_route(self.ours, self.game)
        (hit,) = self.find(f, "route", "99@Nobody", "unknown-mount")
        self.assertEqual(hit["severity"], "error")

    # lockouts
    def test_instance_and_boss_errors(self):
        f, table = v.check_lockouts(self.ours, self.game)
        self.assertEqual(self.find(f, "lockout", "8")[0]["kind"], "unknown-instance")
        self.assertEqual(self.find(f, "lockout", "8")[0]["severity"], "error")
        (boss,) = self.find(f, "lockout", "9")
        self.assertEqual((boss["kind"], boss["severity"]), ("unknown-boss", "error"))
        self.assertIn("Boss One", boss["suggestion"])

    def test_loose_match_reports_journal_name(self):
        f, table = v.check_lockouts(self.ours, self.game)
        (hit,) = self.find(f, "lockout", "7")
        self.assertEqual((hit["kind"], hit["severity"]), ("loose-boss-match", "info"))
        row = next(r for r in table if r["key"] == "7")
        self.assertEqual((row["instance"], row["encounter"], row["match"]), ("Test Keep", "Fyrakk the Blazing", "prefix"))
        self.assertTrue(row["loot"].startswith("yes"))

    def test_item_not_in_boss_loot_warns(self):
        f, _ = v.check_lockouts(self.ours, self.game)
        (hit,) = self.find(f, "lockout", "10")
        self.assertEqual((hit["kind"], hit["severity"]), ("not-in-boss-loot", "warn"))
        (gear,) = self.find(f, "lockout", "17")
        self.assertEqual((gear["kind"], gear["severity"]), ("source-text-only", "info"))

    def test_dungeon_encounter_only_and_addon_case(self):
        f, _ = v.check_lockouts(self.ours, self.game)
        (hidden,) = self.find(f, "lockout", "11")
        self.assertEqual((hidden["kind"], hidden["severity"]), ("journal-hidden-boss", "warn"))
        (case,) = self.find(f, "lockout", "12")
        self.assertEqual((case["kind"], case["severity"]), ("addon-name-mismatch", "warn"))

    def test_dungeon_encounter_title_is_fine_for_the_substring_test(self):
        # "Harlan" is contained in DungeonEncounter "Lord Harlan": no finding.
        f, _ = v.check_lockouts(self.ours, self.game)
        self.assertEqual(self.find(f, "lockout", "18"), [])

    def test_dungeon_encounter_name_that_defeats_the_addon_substring_test(self):
        f, _ = v.check_lockouts(self.ours, self.game)
        (hit,) = self.find(f, "lockout", "19")
        self.assertEqual((hit["kind"], hit["severity"]), ("dungeon-encounter-name-differs", "warn"))
        self.assertIn("Lord Harlan", hit["suggestion"])

    def test_linked_dungeon_encounter_name_that_defeats_the_substring_test(self):
        # JournalEncounter "Gamma, The Old King" links (DungeonEncounterID) to
        # DungeonEncounter "King Gamma": no fuzzy name pick finds it, the link does
        # (the real case: "Dazar, The First King" vs "King Dazar", map 1762).
        f, table = v.check_lockouts(self.ours, self.game)
        (hit,) = self.find(f, "lockout", "23", kind="dungeon-encounter-name-differs")
        self.assertEqual(hit["severity"], "warn")
        self.assertIn("King Gamma", hit["detail"])
        row = next(r for r in table if r["key"] == "23")
        self.assertIn("King Gamma", row["dungeon_encounter"])
        # A name contained in both the journal and the linked name passes.
        self.assertEqual([h["kind"] for h in self.find(f, "lockout", "24")], ["loose-boss-match"],
                         "only the info that 'Gamma' is a prefix of the journal name")

    def test_addon_match_naming_two_bosses_of_the_instance_warns(self):
        f, _ = v.check_lockouts(self.ours, self.game)
        (hit,) = self.find(f, "lockout", "20", kind="addon-ambiguous-match")
        self.assertEqual(hit["severity"], "warn")
        self.assertIn("King Gear", hit["detail"])
        self.assertIn("The Lich King", hit["detail"])
        self.assertEqual(self.find(f, "lockout", "17", kind="addon-ambiguous-match"), [])

    def test_boss_lockouts_use_route_mounts(self):
        f, table = v.check_lockouts(self.ours, self.game)
        row = next(r for r in table if r["key"] == "boss:Deios")
        self.assertEqual(row["mounts"], [2])
        self.assertEqual(self.find(f, "lockout", "boss:Deios"), [])

    # LFG specs (LfgDungeons)
    def test_lfg_specs_resolve_against_lfg_dungeons(self):
        f, table = v.check_lfg(self.ours, self.game)
        byKey = {r["key"]: r for r in table}
        self.assertEqual((byKey["15"]["lfg"], byKey["15"]["dungeon"], byKey["15"]["map"]),
                         (285, "The Headless Horseman", 1004))
        self.assertEqual(byKey["21"]["dungeon"], "The Frost Lord Ahune")
        self.assertEqual(byKey["holiday:midsummer"]["mounts"], [21])
        self.assertEqual(self.find(f, "lockout", "15"), [])
        self.assertEqual(self.find(f, "lockout", "21"), [])
        self.assertEqual(self.find(f, "lockout", "holiday:midsummer"), [])
        self.assertNotIn("holiday:noblegarden", byKey, "a holiday without lfg is not an LFG spec")

    def test_unknown_lfg_dungeon_is_an_error(self):
        f, _ = v.check_lfg(self.ours, self.game)
        (spec,) = self.find(f, "lockout", "22", kind="unknown-lfg")
        self.assertEqual(spec["severity"], "error")
        (hol,) = self.find(f, "lockout", "holiday:brewfest", kind="unknown-lfg")
        self.assertEqual(hol["severity"], "error")

    def test_holiday_lfg_must_match_its_mounts_specs(self):
        f, _ = v.check_lfg(self.ours, self.game)
        (hit,) = self.find(f, "lockout", "22", kind="holiday-lfg-differs")
        self.assertEqual(hit["severity"], "warn")
        self.assertIn("287", hit["detail"])
        self.assertEqual(self.find(f, "lockout", "21", kind="holiday-lfg-differs"), [])

    def test_holidays_file_is_optional(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name in ("Mounts.lua", "Route.lua", "Lockouts.lua"):
                with open(os.path.join(DATA, name), encoding="utf-8") as src,                         open(os.path.join(tmp, name), "w", encoding="utf-8") as dst:
                    dst.write(src.read())
            self.assertEqual(v.load_our_data(tmp)["holidays"], {})
        self.assertEqual(self.ours["holidays"]["midsummer"]["lfg"], 286)

    # events (F17): Data/Events.lua IDs against AreaPOI / Contribution / UiMap
    def test_event_groups_load(self):
        ev = self.ours["events"]
        self.assertEqual(ev["Assault: Uldum"]["pois"], {6487: "Amathet", 6488: "Aqir"})
        self.assertEqual(ev["Warfront: Arathi"]["contributions"], [11, 116, 555])

    def test_events_file_is_optional(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name in ("Mounts.lua", "Route.lua", "Lockouts.lua"):
                with open(os.path.join(DATA, name), encoding="utf-8") as src,                         open(os.path.join(tmp, name), "w", encoding="utf-8") as dst:
                    dst.write(src.read())
            self.assertEqual(v.load_our_data(tmp)["events"], {})

    def test_event_ids_resolve(self):
        f, table = v.check_events(self.ours, self.game)
        self.assertEqual(self.find(f, "events", "Assault: Uldum"), [])
        self.assertEqual(self.find(f, "events", "Warfront: Arathi", "unknown-group"), [])
        rows = {(r["group"], r["table"], r["id"]): r for r in table}
        self.assertEqual(rows[("Assault: Uldum", "AreaPOI", 6488)]["name"], "Assault: Aqir")
        self.assertEqual(rows[("Assault: Uldum", "UiMap", 249)]["name"], "Uldum")
        self.assertEqual(rows[("Warfront: Arathi", "Contribution", 116)]["name"], "Battle for Stromgarde")

    def test_event_id_errors(self):
        f, _ = v.check_events(self.ours, self.game)
        kinds = sorted((x["kind"], x["severity"]) for x in self.find(f, "events", "Assault: Bad"))
        self.assertEqual(kinds, [("map-name-differs", "error"), ("poi-name-differs", "error"),
                                 ("unknown-group", "warn"), ("unknown-map", "error"), ("unknown-poi", "error")])
        (wrong,) = self.find(f, "events", "Assault: Bad", "poi-name-differs")
        self.assertIn("Assault: Mogu", wrong["detail"])
        (missing,) = self.find(f, "events", "Warfront: Arathi", "unknown-contribution")
        self.assertIn("555", missing["detail"])
        self.assertEqual(missing["severity"], "error")

    # completeness
    def test_not_collectable_flags(self):
        self.assertEqual(v.not_collectable({"Flags": "0"}), [])
        self.assertEqual(v.not_collectable({"Flags": "64"}), ["ExcludeFromJournalIfNotLearned"])
        self.assertEqual(v.not_collectable({"Flags": "264"}), ["ShowInSpellbook"])
        self.assertEqual(v.not_collectable({"Flags": "1"}), ["ServerOnly"])
        self.assertEqual(v.not_collectable({"Flags": "4"}), [], "faction-only journal rows count")

    def test_completeness_lists_journal_mounts_missing_from_data(self):
        findings, skipped = v.check_completeness(self.ours, self.game)
        (hit,) = [f for f in findings if f["check"] == "completeness"]
        self.assertEqual((hit["mount"], hit["kind"], hit["severity"]), (30, "missing-from-data", "error"))
        self.assertIn("Vendor", hit["detail"])
        self.assertEqual(skipped, {"ExcludeFromJournalIfNotLearned": [31], "ShowInSpellbook": [32],
                                   "ServerOnly": [33]})

    # source correctness
    def test_source_kinds_from_type_and_labels(self):
        self.assertEqual(v.source_kinds({"SourceTypeEnum": "2", "SourceText_lang": "Vendor: Bob"}), {"vendor"})
        self.assertEqual(v.source_kinds({"SourceTypeEnum": "11", "SourceText_lang": "Achievement: X"}),
                         {"tradingpost", "achievement"})
        self.assertEqual(v.source_kinds({"SourceTypeEnum": "0", "SourceText_lang": "World Quest: Y; Zone: Z"}),
                         {"drop", "quest"})
        self.assertEqual(v.source_kinds({"SourceTypeEnum": "-1", "SourceText_lang": "In-Game Shop"}), {"shop"})

    def test_source_mismatch_warns_and_skips_agreeing_mounts(self):
        f = v.check_sources(self.ours, self.game)
        (hit,) = self.find(f, "source", "25")
        self.assertEqual((hit["kind"], hit["severity"]), ("section-differs", "warn"))
        self.assertIn("journal/raid", hit["detail"])
        self.assertIn("Vendor: Bob", hit["detail"])
        for ok_mount in ("26", "28", "29"):
            self.assertEqual(self.find(f, "source", ok_mount), [], ok_mount)

    # rare-spawn coverage
    def test_rare_drop_without_flag_or_spec_is_an_error(self):
        f = v.check_rares(self.ours, self.game)
        (hit,) = self.find(f, "rares", "14", "rare-not-on-checklist")
        self.assertEqual(hit["severity"], "error")
        self.assertIn("Rare Guy", hit["detail"])
        self.assertEqual(self.find(f, "rares", "16"), [], "a Rarity quest flag covers it")
        self.assertEqual(self.find(f, "rares", "26"), [], "camp spec in the source text's zone")
        self.assertEqual(self.find(f, "rares", "2"), [], "a journal boss is not a rare")

    def test_rare_with_a_quest_outside_a_rare_group_warns(self):
        # Lockouts.QuestReset gives a quest flag "daily" only for a rare-spawn group;
        # a rare filed under another group would reset weekly on the checklist.
        f = v.check_rares(self.ours, self.game)
        (hit,) = self.find(f, "rares", "34", "rare-quest-not-daily")
        self.assertEqual(hit["severity"], "warn")
        self.assertIn("Venthyr Vendor", hit["detail"])
        self.assertEqual(self.find(f, "rares", "35"), [], "a treasure is not a creature")
        self.assertEqual(self.find(f, "rares", "16"), [], "rare group: daily already")

    def test_camp_zone_must_be_a_source_zone(self):
        f = v.check_rares(self.ours, self.game)
        (hit,) = self.find(f, "rares", "27", "camp-zone-differs")
        self.assertEqual(hit["severity"], "error")
        self.assertIn("Hills", hit["detail"])

    def test_camp_spec_is_not_a_lockout_spec(self):
        _, table = v.check_lockouts(self.ours, self.game)
        self.assertNotIn("26", {r["key"] for r in table})
        self.assertIn(26, v.covered_mounts(self.ours), "a camp spec puts it on the checklist")

    # candidates
    def test_journal_candidates_skip_specs_quests_and_boss_lockouts(self):
        groups = v.lockout_candidates(self.ours, self.game)
        mids = {c["mount"] for rows in groups.values() for c in rows}
        self.assertIn(13, mids)
        self.assertNotIn(16, mids)  # Rarity quest
        self.assertNotIn(7, mids)   # has a spec
        self.assertNotIn(2, mids)   # covered by BossLockouts["Deios"]
        mu = next(c for c in groups["Dragonflight"] if c["mount"] == 13)
        self.assertEqual(mu["evidence"][0]["map"], 100)
        self.assertEqual(mu["evidence"][0]["difficulty_mask"], "2")

    def test_source_candidates(self):
        groups = v.source_candidates(self.ours, self.game)
        mids = {c["mount"] for rows in groups.values() for c in rows}
        self.assertEqual(mids, {14})  # 15 is a "Supply Cache", others have loot or specs
        self.assertEqual(groups["Classic"][0]["drop"], "Rare Guy")

    # report + exit code
    def test_report_and_exit_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = os.path.join(tmp, "db2")
            os.makedirs(os.path.join(cache, "1.2.3.4"))
            for t in v.TABLES:
                with open(os.path.join(DB2, t + ".csv"), "rb") as src, \
                        open(os.path.join(cache, "1.2.3.4", t + ".csv"), "wb") as dst:
                    dst.write(src.read())
            allow = os.path.join(tmp, "allow.json")
            with open(allow, "w") as fh:
                json.dump({"route": {"3@Trash": "trash"}}, fh)
            report, out_json = os.path.join(tmp, "r.md"), os.path.join(tmp, "r.json")
            stderr, sys.stderr = sys.stderr, io.StringIO()
            try:
                code = v.main(["--offline", "--cache", cache, "--data", DATA, "--allow", allow,
                               "--report", report, "--json", out_json])
            finally:
                sys.stderr = stderr
            self.assertEqual(code, 1)
            with open(report, encoding="utf-8") as fh:
                text = fh.read()
            self.assertIn("build **1.2.3.4**", text)
            self.assertLess(text.index("### Errors"), text.index("### Warnings"))
            self.assertIn("allowlisted (warn): trash", text)
            self.assertIn("| Mount | Drop | Where", text)
            self.assertIn("## LFG specs resolved against LfgDungeons", text)
            self.assertIn("The Frost Lord Ahune", text)
            self.assertIn("## Event status IDs resolved against the game", text)
            self.assertIn("| Assault: Uldum | AreaPOI | 6488 | Assault: Aqir |", text)
            self.assertIn("## Mount.db2 rows that are not collectable", text)
            self.assertIn("| ExcludeFromJournalIfNotLearned | 1 | 31 |", text)
            self.assertIn("## 7. Rare-spawn mounts on the checklist", text)
            with open(out_json, encoding="utf-8") as fh:
                dumped = json.load(fh)
            self.assertEqual(dumped["build"], "1.2.3.4")

    def test_clean_run_exits_zero(self):
        counts, totals = v.summarise([v.finding("route", "x", "warn", 1, "a", "d")])
        self.assertEqual(totals, {"error": 0, "warn": 1, "info": 0})
        self.assertEqual(counts["route"]["warn"], 1)


class DownloadTest(unittest.TestCase):
    def test_retries_then_succeeds(self):
        calls = []

        class Resp(io.BytesIO):
            headers = {}
            def __enter__(self):
                return self
            def __exit__(self, *a):
                return False

        def opener(req, timeout):
            calls.append(req.get_header("User-agent"))
            if len(calls) < 3:
                raise urllib.error.URLError("flaky")
            return Resp(b"ID,Name\n1,x\n")

        sleeps = []
        orig = v.time.sleep
        v.time.sleep = sleeps.append
        try:
            body, _ = v._http_get("https://example.invalid/x", attempts=4, opener=opener)
        finally:
            v.time.sleep = orig
        self.assertEqual(body, b"ID,Name\n1,x\n")
        self.assertEqual(sleeps, [1.0, 2.0])
        self.assertTrue(calls[0].startswith("AzerothTrail"))

    def test_offline_needs_cached_tables(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(RuntimeError):
                v.fetch_tables("9.9.9.9", cache=tmp, offline=True)
            self.assertEqual(v.cached_builds(tmp), [])


if __name__ == "__main__":
    unittest.main()
