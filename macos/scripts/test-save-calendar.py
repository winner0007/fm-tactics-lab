"""Calendar-only import must keep structural checks without requiring old scores."""
from contextlib import nullcontext
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
import sys
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'runtime'))
from SaveReader import fixture_calendar, leagues
import desktop_save_compat
desktop_save_compat.install()
from fmsave import ReaderCheckError
from fmsave._layouts.fm26_26_3_2 import GATE_BOUNDS
from fmsave._reader_stats import FixtureStats


class CalendarTests(unittest.TestCase):
    def setUp(self):
        self.stats = FixtureStats(span_records=15117, cluster_records=14955,
            clusters=2, strays_without_a_copy=0, with_stage=14955,
            stage_resolved=14955, home_team_resolved=13640,
            away_team_resolved=13640, undated=0, bad_kick_off_slots=0,
            neutral_venue_votes=827, with_stadium=14916,
            stadium_resolved=14916, stub_team_references=2581)
        self.save = Mock()
        self.save.info.build = '27.0.0+2493426'
        self.save._context.section.return_value = nullcontext()
        self.save._context.competition_names = None
        self.save._context.span_records.return_value = SimpleNamespace(span_bytes=512*1024**2)
        self.save._gate_bounds.return_value = GATE_BOUNDS

    def test_valid_calendar_without_results(self):
        fixtures = (SimpleNamespace(home_goals=None, away_goals=None),)
        with patch('fmsave._save.build_fixtures_with_offsets', return_value=(fixtures, self.stats, ())):
            self.assertEqual(fixture_calendar(self.save), fixtures)
        self.save.fixtures.assert_not_called()
        self.save.clubs.assert_called_once()
        self.save._checked_stadium_index.assert_called_once()

    def test_rejects_calendar_damage_instead_of_relaxing_all_checks(self):
        for damaged in (replace(self.stats, stage_resolved=0),
                        replace(self.stats, stadium_resolved=0),
                        replace(self.stats, home_team_resolved=0),
                        replace(self.stats, cluster_records=0)):
            with self.subTest(damaged=damaged), patch('fmsave._save.build_fixtures_with_offsets', return_value=((),damaged,())):
                with self.assertRaises(ReaderCheckError):
                    fixture_calendar(self.save)

    def test_does_not_hide_identity_or_stadium_errors(self):
        for reader in ('clubs', '_checked_stadium_index'):
            with self.subTest(reader=reader):
                method = getattr(self.save, reader)
                method.side_effect = ReaderCheckError('bad identity')
                with self.assertRaises(ReaderCheckError):
                    fixture_calendar(self.save)
                method.side_effect = None

    def test_complete_new_season_and_no_historical_scores(self):
        fixtures = [dict(home_team_slot=0, away_team_slot=0, round=None,
            competition_id=1, stage_id=2, season_start_year=2026,
            home_club_uid=a, away_club_uid=b, date='2026-08-08',
            played=True, home_goals=3, away_goals=2)
            for a in range(4) for b in range(4) if a!=b]
        result = leagues(fixtures,'2026-02-02')
        self.assertEqual(len(result),1)
        self.assertEqual(len(result[0]['fixtures']),12)
        self.assertTrue(all(f['homeGoals'] is None and f['awayGoals'] is None for f in result[0]['fixtures']))
        self.assertEqual(leagues(fixtures[:-1],'2026-02-02'),[])
        self.assertEqual(leagues(fixtures+[fixtures[0]],'2026-02-02'),[])
        self.assertEqual(leagues(fixtures,'2027-02-02'),[])


if __name__ == '__main__':
    unittest.main()
