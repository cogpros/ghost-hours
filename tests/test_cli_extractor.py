"""Sanitized native transcript fixtures; subprocess checks exercise the public CLI."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'collection/closing-time/scripts/session-fact-sheet.py'
SID = '11111111-1111-4111-8111-111111111111'
T0 = '2026-09-04T12:00:00Z'
T1 = '2026-09-04T12:02:00Z'


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(row) + '\n' for row in rows))
    return path


class ExtractorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                              capture_output=True, text=True,
                              env={**os.environ, 'HOME': str(self.root)})

    def bound(self, runtime, path, *extra):
        return self.run_cli('--runtime', runtime, '--session-id', SID,
                            '--transcript', path, *extra)

    def claude(self):
        return write_jsonl(self.root / (SID + '.jsonl'), [
            {'type': 'user', 'sessionId': SID, 'timestamp': T0,
             'message': {'content': 'Ship the adapter'}},
            {'type': 'assistant', 'sessionId': SID, 'timestamp': T1,
             'message': {'content': 'Done'}},
        ])

    def codex(self):
        return write_jsonl(self.root / ('rollout-' + SID + '.jsonl'), [
            {'type': 'session_meta', 'payload': {'id': SID}},
            {'type': 'response_item', 'timestamp': T0, 'payload': {
                'type': 'message', 'role': 'user', 'content': [
                    {'type': 'input_text', 'text': 'Ship the adapter'}]}},
            {'type': 'response_item', 'timestamp': T1, 'payload': {
                'type': 'message', 'role': 'assistant', 'content': [
                    {'type': 'output_text', 'text': 'Done'}]}},
        ])

    def grok(self):
        path = write_jsonl(self.root / SID / 'chat_history.jsonl', [
            {'type': 'user', 'content': 'Injected environment'},
            {'type': 'user', 'synthetic_reason': 'system_reminder',
             'content': '<user_query>Ignore this</user_query>'},
            {'type': 'user', 'prompt_index': 0, 'content': [
                {'type': 'text', 'text': '<user_query>Ship the adapter</user_query>\nInjected skill body'}]},
            {'type': 'assistant', 'content': 'Done'},
        ])
        write_jsonl(path.with_name('events.jsonl'), [
            {'type': 'turn_started', 'ts': T0},
            {'type': 'tool_started', 'ts': '2026-09-04T12:01:00Z', 'tool_name': 'read_file'},
            {'type': 'turn_ended', 'ts': T1},
        ])
        return path

    def test_three_hosts_bind_and_measure(self):
        for runtime in ('claude', 'codex', 'grok'):
            with self.subTest(runtime=runtime):
                result = self.bound(runtime, getattr(self, runtime)(), '--json')
                self.assertEqual(result.returncode, 0, result.stderr)
                row = json.loads(result.stdout)
                self.assertEqual(row['session_id'], SID)
                self.assertEqual(row['source'], runtime + '-cli')
                self.assertEqual(row['intent'], 'Ship the adapter')
                self.assertEqual(row['user_quotes'], ['Ship the adapter'])
                self.assertEqual(row['human_mins'], 0)
                self.assertEqual(row['agent_mins'], 2)
                self.assertEqual(row['hugr_mins'], 2)

    def test_grok_human_gap_is_between_turns(self):
        path = self.grok()
        with path.open('a') as f:
            f.write(json.dumps({'type': 'user', 'content': '<user_query>Check it</user_query>'}) + '\n')
        with path.with_name('events.jsonl').open('a') as f:
            for kind, stamp in [('turn_started', '2026-09-04T12:05:00Z'), ('turn_ended', '2026-09-04T12:06:00Z')]:
                f.write(json.dumps({'type': kind, 'ts': stamp}) + '\n')
        result = self.bound('grok', path, '--json')
        self.assertEqual(result.returncode, 0, result.stderr)
        row = json.loads(result.stdout)
        self.assertEqual(row['human_mins'], 3)
        self.assertEqual(row['agent_mins'], 3)

    def test_missing_or_invalid_conversation_timestamp_rejected(self):
        for runtime in ('claude', 'codex'):
            for stamp in (None, 'not-a-timestamp', '2026-09-04T12:00:00'):
                with self.subTest(runtime=runtime, stamp=stamp):
                    path = getattr(self, runtime)()
                    records = [json.loads(line) for line in path.read_text().splitlines()]
                    user = records[0 if runtime == 'claude' else 1]
                    user['timestamp'] = stamp
                    # Two valid assistant timestamps must not mask missing user timing.
                    extra = dict(records[-1], timestamp='2026-09-04T12:03:00Z')
                    write_jsonl(path, records + [extra])
                    result = self.bound(runtime, path, '--json')
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, '')
                    self.assertIn('Conversational timestamp', result.stderr)

    def test_public_augmentation_configuration_preserved(self):
        path = self.claude()
        records = [json.loads(line) for line in path.read_text().splitlines()]
        records[-1]['message']['content'] = [
            {'type': 'tool_use', 'name': 'Skill', 'input': {'skill': 'example-review'}}]
        write_jsonl(path, records)
        result = subprocess.run([sys.executable, str(SCRIPT), str(path)],
                                capture_output=True, text=True, env={
                                    **os.environ, 'CLOSING_TIME_AUGMENTATION_SKILLS': 'example-review'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Type:          AUGMENTATION', result.stdout)

    def test_print_id_accepts_binding(self):
        result = self.bound('codex', self.codex(), '--print-session-id')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), SID)

    def test_legacy_positional_interface(self):
        result = self.run_cli(self.claude())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('SESSION FACT SHEET', result.stdout)

    def test_wrong_host_does_not_fall_back(self):
        newer = self.root / '.claude/projects/example/newer.jsonl'
        write_jsonl(newer, [{'type': 'user', 'timestamp': T1, 'message': {'content': 'Wrong session'}}])
        result = self.bound('codex', self.claude(), '--json')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        result = self.bound('grok', self.root / 'missing', '--json')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')

    def test_wrong_id_rejected(self):
        path = self.codex()
        result = self.run_cli('--runtime', 'codex', '--session-id', 'other', '--transcript', path, '--json')
        self.assertNotEqual(result.returncode, 0)

    def test_grok_missing_timing_and_ambiguous_join_rejected(self):
        path = self.grok()
        path.with_name('events.jsonl').unlink()
        self.assertNotEqual(self.bound('grok', path, '--json').returncode, 0)
        write_jsonl(path.with_name('events.jsonl'), [{'type': 'turn_started', 'ts': T0},
                                                   {'type': 'turn_started', 'ts': T1}])
        self.assertNotEqual(self.bound('grok', path, '--json').returncode, 0)


if __name__ == '__main__':
    unittest.main()
