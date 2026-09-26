import contextlib
import io
import sys
import unittest
from unittest.mock import patch
import verify_asset_compatibility as probe


class CompatibilityTest(unittest.TestCase):
    def run_probe(self, missing=False):
        def fetch(ip, path, host):
            if path.endswith('.woff2'):
                return (404 if missing and ip == '172.26.1.2' else 200), b'font'
            if path.endswith('.css'):
                return 200, b'@font-face{src:url(font-digest.woff2)}'
            return 200, b'<link rel="stylesheet" href="/assets/app-digest.css">'
        with patch.object(sys, 'argv', ['probe', '--target', 'old=172.26.1.1', '--target', 'new=172.26.1.2']), patch.object(probe, 'fetch', side_effect=fetch), contextlib.redirect_stdout(io.StringIO()):
            return probe.main()

    def test_missing_css_dependency_blocks_cutover(self):
        self.assertEqual(self.run_probe(missing=True), 1)

    def test_all_targets_have_both_versions(self):
        self.assertEqual(self.run_probe(), 0)

    def test_external_urls_are_not_requested(self):
        self.assertIsNone(probe.local_asset('https://example.com/assets/x.css', '/', 'circle-book.com'))


if __name__ == '__main__':
    unittest.main()
