"""Exercise delegated close against real writers with all side effects in temp HOME."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'collection/closing-time/scripts/cli-close.py'
spec = importlib.util.spec_from_file_location('close_fixtures', Path(__file__).with_name('test_cli_extractor.py'))
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)
SID = fixtures.SID


class CloseFlowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = {**os.environ, 'HOME': str(self.root),
                    'GHOST_HOURS_LOG': str(self.root / 'measurements.jsonl'),
                    'CLOSING_TIME_STATE': str(self.root / 'custom-state')}
        self.env.pop('CLOSING_TIME_UPSTREAM_DIR', None)
        self.binding = self.root / 'custom-state/closing-time-cli' / (SID + '.json')
        self.marker = self.root / 'custom-state/closing-time' / (SID + '.json')
        self.sheet = self.root / 'facts.md'
        self.sheet.write_text(f'Session {SID}\nAgent-estimated appraisal.\n')
        self.appraisal = self.root / 'appraisal.json'
        self.appraisal.write_text(json.dumps({'type': 'speed', 'gh_mins': 10, 'fwc': 7,
                                             'desc': 'Shipped adapter', 'note': 'Ship the adapter'}))

    def call(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                              env=self.env, capture_output=True, text=True)

    def prepare(self, runtime='codex', sid=SID, score=4):
        path = getattr(fixtures.ExtractorTests, runtime)(self)
        return self.call('prepare', '--runtime', runtime, '--seat',
                         {'claude': 'assistant-a', 'codex': 'assistant-b', 'grok': 'assistant-c'}[runtime],
                         '--session-id', sid, '--transcript', path, '--blind-score', score)

    def log(self):
        return self.call('log', '--binding', self.binding, '--appraisal', self.appraisal,
                         '--fact-sheet', self.sheet)

    def seal(self):
        return self.call('seal', '--binding', self.binding)

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)

    def rows(self, path):
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def events(self):
        return self.rows(self.root / '.closing-time/events.jsonl')

    def test_three_hosts_prepare_log_seal(self):
        for runtime, seat in [('claude', 'assistant-a'), ('codex', 'assistant-b'), ('grok', 'assistant-c')]:
            with self.subTest(runtime=runtime):
                self.assert_ok(self.prepare(runtime))
                self.assert_ok(self.log())
                result = self.seal()
                self.assert_ok(result)
                row = self.rows(Path(self.env['GHOST_HOURS_LOG']))[0]
                self.assertEqual((row['source'], row['seat'], row['entry_class']),
                                 (runtime + '-cli', seat, 'human'))
                self.assertEqual((row['fwc_eom'], row['fwc']), (4, 7))
                self.assertEqual(row['note'], 'Ship the adapter')
                self.assertTrue(self.marker.exists())
                completions = [e for e in self.events() if e['type'] == 'closing_time_cli_facts_emitted']
                self.assertEqual(len(completions), 1)
                self.assertEqual(json.loads(result.stdout)['session_id'], SID)
                self.binding.unlink()
                self.marker.unlink()
                Path(self.env['GHOST_HOURS_LOG']).unlink()
                (self.root / '.closing-time/events.jsonl').unlink()

    def test_wrong_session_cannot_measure_or_seal_despite_newer_claude(self):
        fixtures.write_jsonl(self.root / '.claude/projects/example/newer.jsonl', [
            {'sessionId': 'newer', 'type': 'user', 'timestamp': fixtures.T1,
             'message': {'content': 'Another session'}}])
        result = self.prepare(sid='wrong-session')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.binding.exists())
        self.assertFalse(Path(self.env['GHOST_HOURS_LOG']).exists())
        self.assertFalse(self.marker.exists())
        self.assertEqual(self.events(), [])

    def test_failed_writer_cannot_seal(self):
        self.assert_ok(self.prepare())
        self.env['GHOST_HOURS_LOG'] = str(self.root / 'blocked')
        Path(self.env['GHOST_HOURS_LOG']).mkdir()
        self.assertNotEqual(self.log().returncode, 0)
        self.assertNotEqual(self.seal().returncode, 0)
        self.assertFalse(self.marker.exists())
        self.assertEqual(self.events(), [])

    def test_retry_one_measurement_one_completion_original_blind_score(self):
        self.assert_ok(self.prepare())
        self.assert_ok(self.log())
        self.assert_ok(self.seal())
        original_marker = self.marker.read_bytes()
        self.assert_ok(self.prepare(score=9))
        self.assert_ok(self.log())
        self.assert_ok(self.seal())
        self.assertEqual(json.loads(self.binding.read_text())['blind_fwc'], 4)
        self.assertEqual(len(self.rows(Path(self.env['GHOST_HOURS_LOG']))), 1)
        events = [e for e in self.events() if e['type'] == 'closing_time_cli_facts_emitted']
        self.assertEqual(len(events), 1)
        self.assertEqual(self.marker.read_bytes(), original_marker)

    def test_changed_retry_is_rejected_without_rewriting_measurement(self):
        self.assert_ok(self.prepare())
        self.assert_ok(self.log())
        log = Path(self.env['GHOST_HOURS_LOG'])
        before = log.read_bytes()
        appraisal = json.loads(self.appraisal.read_text())
        appraisal['gh_mins'] = 11
        self.appraisal.write_text(json.dumps(appraisal))
        self.assertNotEqual(self.log().returncode, 0)
        self.assertEqual(log.read_bytes(), before)

    def test_invented_quote_rejected_before_write(self):
        self.assert_ok(self.prepare())
        appraisal = json.loads(self.appraisal.read_text())
        appraisal['note'] = 'The operator never said this'
        self.appraisal.write_text(json.dumps(appraisal))
        self.assertNotEqual(self.log().returncode, 0)
        self.assertFalse(Path(self.env['GHOST_HOURS_LOG']).exists())
        self.assertNotEqual(self.seal().returncode, 0)
        self.assertFalse(self.marker.exists())

    def test_export_preserves_local_legacy_and_strips_seat(self):
        self.assert_ok(self.prepare())
        self.assert_ok(self.log())
        log = Path(self.env['GHOST_HOURS_LOG'])
        row = self.rows(log)[0]
        row['fwc_source'] = 'eom-blind'
        log.write_text(json.dumps(row) + '\n')
        before = log.read_bytes()
        result = subprocess.run(['bash', str(ROOT / 'scripts/ghost-hours-share.sh'), '--yes'],
                                env=self.env, text=True, capture_output=True)
        self.assert_ok(result)
        exported = json.loads(next((self.root / 'share').glob('*-export.json')).read_text())
        self.assertEqual(exported['entries'][0]['fwc_source'], 'agent-blind')
        self.assertNotIn('seat', exported['entries'][0])
        self.assertNotIn('session_id', exported['entries'][0])
        self.assertEqual(log.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
