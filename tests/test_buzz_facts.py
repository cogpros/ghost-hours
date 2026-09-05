import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'collection/closing-time-buzz-facts/scripts/buzz-stack-facts.sh'
FAKE = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['CALLS'], 'a') as f: f.write(json.dumps(args) + '\\n')
f = json.loads(Path(os.environ['FIXTURE']).read_text())
key = ' '.join(args[:2])
if key in f.get('fail', []): sys.exit(1)
if key == 'channels list': print(json.dumps(f['channels']))
elif key == 'messages get': print(json.dumps(f['messages']))
elif key == 'canvas get': print('Example canvas')
elif key == 'users get': print(json.dumps(f.get('users', {}).get(args[-1], [])))
else: sys.exit(9)
'''


class BuzzFactsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        binary = self.root / 'buzz'
        binary.write_text(FAKE)
        binary.chmod(0o755)
        self.fixture = self.root / 'fixture.json'
        self.calls = self.root / 'calls.jsonl'
        self.env = {**os.environ, 'HOME': str(self.root), 'TZ': 'UTC',
                    'PATH': str(self.root) + os.pathsep + os.environ['PATH'],
                    'BUZZ_RELAY_URL': 'wss://example.invalid', 'BUZZ_OPERATOR_NAME': 'operator',
                    'FIXTURE': str(self.fixture), 'CALLS': str(self.calls),
                    'CLOSING_TIME_STATE': str(self.root / 'state')}
        self.env.pop('BUZZ_OPERATOR_PUBKEY', None)
        self.data = {'channels': [{'channel_id': 'channel-a', 'name': 'example'}],
                     'messages': [
                         {'id': 'root-event', 'pubkey': 'human-key', 'created_at': 1788523200, 'content': 'Root', 'tags': []},
                         {'id': 'reply-event', 'pubkey': 'agent-key', 'created_at': 1788523320, 'content': 'Reply',
                          'tags': [['e', 'wrong-parent', '', 'reply'], ['e', 'root-event', '', 'root']]}],
                     'users': {'human-key': [{'display_name': 'operator'}], 'agent-key': [{'display_name': 'agent'}]}}

    def run_capture(self, *args):
        self.fixture.write_text(json.dumps(self.data))
        return subprocess.run(['bash', str(SCRIPT), '--date', '2026-09-04', *args],
                              env=self.env, text=True, capture_output=True)

    def test_json_includes_root_and_marked_root_precedence(self):
        result = self.run_capture('--json')
        self.assertEqual(result.returncode, 0, result.stderr)
        d = json.loads(result.stdout)
        self.assertTrue(d['complete'])
        self.assertEqual(d['unknown_writers'], [])
        self.assertEqual(len(d['threads']), 1)
        self.assertEqual(d['threads'][0]['root'], 'root-event')
        self.assertEqual(d['threads'][0]['n'], 2)
        self.assertEqual(d['agent_mins'], 2)
        self.assertEqual(d['roster']['operator']['msgs'], 1)
        for line in self.calls.read_text().splitlines():
            self.assertIn(json.loads(line)[:2], [['channels','list'], ['messages','get'], ['canvas','get'], ['users','get']])

    def test_missing_identity_or_relay_fails_before_calls(self):
        self.env.pop('BUZZ_OPERATOR_NAME')
        result = self.run_capture('--json')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.calls.exists())
        self.env['BUZZ_OPERATOR_NAME'] = 'operator'
        self.env.pop('BUZZ_RELAY_URL')
        self.assertNotEqual(self.run_capture('--json').returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_unknown_writer_fails(self):
        self.data['users'].pop('agent-key')
        result = self.run_capture('--json')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertIn('unknown writers', result.stderr)

    def test_unreadable_channels_or_canvas_fails(self):
        for command in ('channels list', 'messages get', 'canvas get'):
            with self.subTest(command=command):
                self.data['fail'] = [command]
                result = self.run_capture('--json')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')

    def test_message_limit_fails_before_success(self):
        self.data['messages'] = [self.data['messages'][0]] * 500
        result = self.run_capture('--json')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('truncated', result.stderr)

    def test_explicit_pubkey_and_markdown(self):
        self.env.pop('BUZZ_OPERATOR_NAME')
        self.env['BUZZ_OPERATOR_PUBKEY'] = 'human-key'
        self.data['users'].pop('human-key')
        result = self.run_capture()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('BUZZ STACK FACT SHEET', result.stdout)
        self.assertIn('operator: 1 msgs', result.stdout)


if __name__ == '__main__':
    unittest.main()
