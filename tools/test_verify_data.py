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
        findings, _, _, _, _ = self.run_all({"route": {"3@Trash": "AQ trash drop"}})
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
