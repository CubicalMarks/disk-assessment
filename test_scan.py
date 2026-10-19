import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from scan import Scanner, classify, nonoverlap, volume_usage


class ScanTests(unittest.TestCase):
    def test_accounting_hardlinks_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / 'child'
            folder.mkdir()
            original = folder / 'payload'
            original.write_bytes(b'x' * 16384)
            os.link(original, root / 'hardlink')
            (root / 'cycle').symlink_to(root, target_is_directory=True)
            scanner = Scanner(root, minimum=1024**3)
            tree = scanner.walk(str(root))
            self.assertEqual(tree['bytes'], original.stat().st_blocks * 512)
            self.assertEqual(tree['logical_bytes'], 16384)
            self.assertEqual(tree['files'], 1)
            self.assertEqual(tree['children'], [])
            self.assertEqual(scanner.symlinks, 1)

    def test_sparse_file_uses_allocated_blocks(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory) / 'sparse'
            with p.open('wb') as f:
                f.seek(1024**2)
                f.write(b'x')
            tree = Scanner(directory).walk(directory)
            self.assertEqual(tree['bytes'], p.stat().st_blocks*512)
            self.assertEqual(tree['logical_bytes'], 1024**2+1)

    def test_permission_error_is_visible(self):
        with tempfile.TemporaryDirectory() as directory:
            scanner = Scanner(directory)
            with patch('scan.os.scandir', side_effect=PermissionError('denied')):
                tree = scanner.walk(directory)
            self.assertEqual(tree['errors'], 1)
            self.assertEqual(scanner.error_count, 1)
            self.assertEqual(scanner.errors[0]['path'], directory)

    def test_candidate_overlap_and_path_boundaries(self):
        candidates = [{'path': p, 'bytes': 100} for p in ['/a/cache', '/a/cache/sub', '/a/caches']]
        self.assertEqual({c['path'] for c in nonoverlap(candidates)}, {'/a/cache', '/a/caches'})

    def test_installed_app_libraries_are_not_project_dependencies(self):
        self.assertIsNone(classify('/Applications/Example.app/Contents/node_modules'))
        self.assertIsNone(classify(str(Path.home())+'/.local/lib/node_modules'))
        self.assertIsNone(classify(str(Path.home())+'/.cache/codex-runtimes/node_modules'))
        self.assertEqual(classify(str(Path.home())+'/src/example/node_modules')[0], 'rebuildable')

    def test_df_uses_volume_used_not_total_minus_available(self):
        response = type('Response', (), {'stdout': 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/disk 1000 700 200 78% /data\n'})()
        with patch('scan.subprocess.run', return_value=response):
            volume = volume_usage('/data')
        self.assertEqual(volume['used'], 700*1024)
        self.assertEqual(volume['other_shared_usage'], 100*1024)

    def test_symlink_root_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'alias'
            p.symlink_to(directory, target_is_directory=True)
            with self.assertRaises(ValueError):
                Scanner(p)


if __name__ == '__main__':
    unittest.main()
