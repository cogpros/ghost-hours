"""Local-only Buzz recording and failure boundaries; no relay requests."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'collection/closing-time-buzz-facts/scripts/record-close.py'


class BuzzRecordTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.log = self.home / 'gh/log.jsonl'
        self.env = {**os.environ, 'HOME': str(self.home), 'GHOST_HOURS_LOG': str(self.log),
                    'CLOSING_TIME_STATE': str(self.home / 'state')}
        self.env.pop('CLOSING_TIME_UPSTREAM_DIR', None)
        self.capture = self.home / 'capture.json'
        self.appraisal = self.home / 'appraisal.json'
        self.report = self.home / 'report.html'
        self.report.write_text('<html><body>Shipped work</body></html>')
        self.capture.write_text(json.dumps(dict(date='2026-09-04', complete=True,
            window_start=1788480000, window_end=1788566400, human_mins=10,
            agent_mins=20, unknown_writers=[], threads=[])))
        self.appraisal.write_text(json.dumps(dict(type='speed', gh_mins=120,
            fwc=7, fwc_eom=4, fwc_source='operator', desc='Completed the day')))
        self.marker = self.home / 'state/closing-time-buzz/buzz-stack-2026-09-04.json'

    def run_record(self):
        return subprocess.run([sys.executable, str(SCRIPT), '--capture', str(self.capture),
            '--appraisal', str(self.appraisal), '--report', str(self.report), '--seat', 'assistant'],
            env=self.env, capture_output=True, text=True)

    def change(self, path, **values):
        data = json.loads(path.read_text())
        data.update(values)
        path.write_text(json.dumps(data))

    def rows(self, path):
        return [json.loads(line) for line in path.read_text().splitlines()]

    def test_success_retry_one_row_event_and_frozen_report(self):
        for _ in range(2):
            result = self.run_record()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('fwc_eom', result.stdout)
        rows = self.rows(self.log)
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0]['session_id'], rows[0]['source'], rows[0]['seat']),
                         ('buzz-stack-2026-09-04', 'buzz-stack', 'assistant'))
        self.assertEqual((rows[0]['human_mins'], rows[0]['entry_class']), (30, 'human'))
        seal = json.loads(self.marker.read_text())
        self.assertEqual(len(seal['capture_hash']), 64)
        self.assertTrue(seal['sealed_at'].endswith('Z'))
        self.assertEqual(len(self.rows(self.home / '.closing-time/events.jsonl')), 1)
        self.report.write_text('<html>Changed</html>')
        self.assertNotEqual(self.run_record().returncode, 0)
        self.assertEqual(len(self.rows(self.log)), 1)

    def test_incomplete_and_unknown_capture_do_not_seal(self):
        for values in (dict(complete=False), dict(complete=True, unknown_writers=['unknown'])):
            self.change(self.capture, **values)
            self.assertNotEqual(self.run_record().returncode, 0)
            self.assertFalse(self.marker.exists())
            self.assertFalse(self.log.exists())

    def test_invalid_timing_and_missing_report_do_not_seal(self):
        self.change(self.capture, human_mins=-1)
        self.assertNotEqual(self.run_record().returncode, 0)
        self.change(self.capture, human_mins=10)
        self.report.unlink()
        self.assertNotEqual(self.run_record().returncode, 0)
        self.assertFalse(self.marker.exists())
        self.assertFalse(self.log.exists())

    def test_write_failure_does_not_seal_or_expose_blind(self):
        self.log.mkdir(parents=True)
        result = self.run_record()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('fwc_eom', result.stdout + result.stderr)
        self.assertFalse(self.marker.exists())

    def test_conflicting_appraisal_preserves_measurement_and_seal(self):
        self.assertEqual(self.run_record().returncode, 0)
        before = (self.log.read_bytes(), self.marker.read_bytes())
        self.change(self.appraisal, gh_mins=180)
        self.assertNotEqual(self.run_record().returncode, 0)
        self.assertEqual((self.log.read_bytes(), self.marker.read_bytes()), before)

    def test_collector_record_and_next_window_use_same_receipt(self):
        from test_buzz_facts import FAKE
        binary = self.home / 'buzz'
        binary.write_text(FAKE)
        binary.chmod(0o755)
        now = int(datetime.now(timezone.utc).timestamp())
        fixture = self.home / 'relay.json'
        fixture.write_text(json.dumps({
            'channels': [{'channel_id': 'channel', 'name': 'work'}],
            'messages': [
                {'id': 'root', 'pubkey': 'human', 'created_at': now - 180, 'content': 'Ship', 'tags': []},
                {'id': 'reply', 'pubkey': 'agent', 'created_at': now - 60, 'content': 'Done',
                 'tags': [['e', 'root', '', 'root']]}],
            'users': {'human': [{'display_name': 'operator'}], 'agent': [{'display_name': 'assistant'}]}}))
        self.env.update(PATH=str(self.home) + os.pathsep + self.env['PATH'], TZ='UTC',
                        BUZZ_RELAY_URL='wss://example.invalid', BUZZ_OPERATOR_NAME='operator',
                        FIXTURE=str(fixture), CALLS=str(self.home / 'calls.jsonl'))
        self.env.pop('BUZZ_OPERATOR_PUBKEY', None)
        collector = SCRIPT.with_name('buzz-stack-facts.sh')
        def collect():
            result = subprocess.run(['bash', str(collector), '--json'], env=self.env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout
        self.capture.write_text(collect())
        self.assertEqual(self.run_record().returncode, 0)
        captured = json.loads(self.capture.read_text())
        marker = self.marker.with_name('buzz-stack-' + captured['date'] + '.json')
        sealed_at = json.loads(marker.read_text())['sealed_at']
        next_capture = json.loads(collect())
        expected = int(datetime.strptime(sealed_at, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc).timestamp())
        self.assertEqual(next_capture['window_start'], expected)
        self.assertIn('seal-to-seal', next_capture['window_note'])

    def test_operator_and_estimated_provenance(self):
        self.assertEqual(self.run_record().returncode, 0)
        row = self.rows(self.log)[0]
        self.assertEqual(row['fwc_source'], 'operator')
        self.assertNotIn('operator-override-fill', row.get('tags', []))
        self.change(self.capture, date='2026-09-05')
        self.change(self.appraisal, fwc_source='agent-blind', note='It mattered.')
        self.assertEqual(self.run_record().returncode, 0)
        row = self.rows(self.log)[1]
        self.assertEqual((row['fwc_source'], row['fwc_eom'], row['fwc']), ('agent-blind', 4, 7))
        self.assertIn('operator-override-fill', row['tags'])
        self.assertEqual(row['note'], 'It mattered.')


if __name__ == '__main__':
    unittest.main()
