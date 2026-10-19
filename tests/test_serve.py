"""Check resource locations without starting a server or reading a real report."""
from pathlib import Path
import unittest

import serve


class AssetPathTests(unittest.TestCase):
    def test_web_asset_paths_resolve_after_source_move(self):
        web = serve.ROOT / 'resources' / 'web'
        for route, (relative, _) in serve.ASSETS.items():
            if route == '/report-data.json':
                continue
            with self.subTest(route=route):
                path = serve.ROOT / relative
                self.assertEqual(path.parent, web)
                self.assertTrue(path.is_file())
        self.assertEqual(serve.ASSETS['/'], serve.ASSETS['/index.html'])

    def test_snapshot_stays_at_repository_root(self):
        relative, mime = serve.ASSETS['/report-data.json']
        self.assertEqual(Path(relative), Path('report-data.json'))
        self.assertEqual(mime, 'application/json')
        self.assertEqual(serve.ROOT, Path(__file__).resolve().parents[1])
