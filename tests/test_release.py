"""Exercise release guards and upload orchestration without GitHub writes/builds."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent

FAKE_TOOL = r'''#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import sys

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
scenario = os.environ['RELEASE_SCENARIO']
commit = 'a' * 40
with open('commands.log', 'a') as log:
    log.write(json.dumps([tool] + args) + '\n')
if tool == 'git':
    if args == ['rev-parse', 'HEAD'] or args == ['rev-parse', 'v0.3.10^{commit}']:
        print(commit)
    elif args == ['branch', '--show-current']:
        print('feature' if scenario == 'wrong-branch' else 'main')
    elif args[:2] == ['status', '--porcelain']:
        if scenario == 'dirty' or (scenario == 'source-changed' and Path('built').exists()):
            print(' M README.md')
    elif args[:2] == ['ls-remote', '--exit-code']:
        print(('b' * 40 if scenario == 'unpushed' or (scenario == 'remote-advanced' and Path('built').exists()) else commit) + '\trefs/heads/main')
    elif args[:2] == ['ls-remote', 'origin']:
        if scenario == 'wrong-tag':
            print('b' * 40 + '\trefs/tags/v0.3.10')
        elif scenario == 'existing-tag':
            print('c' * 40 + '\trefs/tags/v0.3.10')
            print(commit + '\trefs/tags/v0.3.10^{}')
    elif args[:2] == ['remote', 'get-url']:
        print('https://github.com/example/wrong-repository.git' if scenario == 'wrong-repository' else 'https://github.com/CubicalMarks/disk-assessment.git')
    elif args[:2] == ['show-ref', '--verify']:
        sys.exit(1)
    elif args[0] not in ('tag', 'push'):
        sys.exit('Unexpected git call: ' + repr(args))
elif tool == 'gh':
    if args[:2] == ['repo', 'view']:
        print('CubicalMarks/disk-assessment')
    elif args[:2] == ['release', 'create']:
        assert '--draft' in args and '--verify-tag' in args
        assert Path(args[3]).is_file() and Path(args[4]).is_file()
        assert ' ' not in Path(args[3]).name and ' ' not in Path(args[4]).name
        assert Path(args[3]).name in Path(args[4]).read_text()
        notes = Path(args[args.index('--notes-file') + 1]).read_text()
        assert 'not notarized' in notes
        if scenario == 'upload-fails':
            sys.exit(1)
        print('https://github.com/CubicalMarks/disk-assessment/releases/example')
    else:
        sys.exit('Unexpected gh call: ' + repr(args))
elif tool == 'make':
    if scenario == 'checks-fail':
        sys.exit(1)
    if args == ['dmg']:
        Path('dist').mkdir(exist_ok=True)
        asset = Path('dist/Disk-Assessment-0.3.10-' + os.uname().machine + '.dmg')
        asset.write_bytes(b'synthetic installer')
        Path('built').touch()
        checksum = '0' * 64 if scenario == 'bad-checksum' else hashlib.sha256(asset.read_bytes()).hexdigest()
        Path(str(asset) + '.sha256').write_text(checksum + '  ' + asset.name + '\n')
'''


class ReleaseScriptTests(unittest.TestCase):
    def run_release(self, scenario, *args):
        with tempfile.TemporaryDirectory(prefix='disk-assessment-release-test-') as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            (root / 'resources').mkdir()
            (root / 'bin').mkdir()
            shutil.copy(ROOT / 'scripts/release.sh', root / 'scripts/release.sh')
            # Keep the fixture independent of the app's next version bump.
            (root / 'resources/Info.plist').write_text(
                '<?xml version="1.0"?><plist version="1.0"><dict>'
                '<key>CFBundleShortVersionString</key><string>0.3.10</string>'
                '</dict></plist>\n'
            )
            for tool in ('git', 'gh', 'make'):
                path = root / 'bin' / tool
                path.write_text(FAKE_TOOL)
                path.chmod(0o755)
            env = dict(os.environ, RELEASE_SCENARIO=scenario,
                       PATH=str(root / 'bin') + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['bash', 'scripts/release.sh', *args], cwd=root,
                                    env=env, text=True, capture_output=True)
            import json
            log = root / 'commands.log'
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, calls

    def test_guards_stop_before_build_or_writes(self):
        for scenario in ('dirty', 'unpushed', 'wrong-tag', 'wrong-branch', 'wrong-repository'):
            with self.subTest(scenario=scenario):
                result, calls = self.run_release(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(c[0] == 'make' or c[1] in ('tag', 'push', 'release') for c in calls))

    def test_dry_run_is_read_only(self):
        result, calls = self.run_release('success', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(c[0] == 'make' or c[1] in ('tag', 'push', 'release') for c in calls))

    def test_checks_fail_before_tag(self):
        result, calls = self.run_release('checks-fail')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[1] in ('tag', 'push', 'release') for c in calls))

    def test_build_changes_and_bad_assets_stop_before_remote_writes(self):
        for scenario in ('source-changed', 'remote-advanced', 'bad-checksum'):
            with self.subTest(scenario=scenario):
                result, calls = self.run_release(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(c[1] in ('tag', 'push', 'release') for c in calls))

    def test_success_attaches_both_assets_to_draft_after_build(self):
        result, calls = self.run_release('success', '--prerelease')
        self.assertEqual(result.returncode, 0, result.stderr)
        upload = next(c for c in calls if c[:3] == ['gh', 'release', 'create'])
        self.assertIn('--prerelease', upload)
        self.assertIn('--generate-notes', upload)
        self.assertLess(calls.index(['make', 'dmg']), calls.index(upload))
        self.assertIn(['git', 'push', 'origin', 'refs/tags/v0.3.10:refs/tags/v0.3.10'], calls)

    def test_existing_matching_annotated_tag_is_reused(self):
        result, calls = self.run_release('existing-tag')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(c[1] in ('tag', 'push') for c in calls))

    def test_upload_failure_keeps_tag_and_reports_partial_draft(self):
        result, calls = self.run_release('upload-fails')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('existing/partial draft', result.stderr)
        self.assertFalse(any('--delete' in c or '--clobber' in c for c in calls))


if __name__ == '__main__':
    unittest.main()
