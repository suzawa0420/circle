import tempfile
from pathlib import Path
import unittest
from sync_assets import sync

NAME = 'application-' + 'a' * 64 + '.css'


class AssetSyncTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / 'source'
        self.dest = Path(self.temp.name) / 'dest'
        self.source.mkdir()
        self.dest.mkdir()
        (self.source / NAME).write_bytes(b'public css')

    def test_preview_does_not_publish(self):
        self.assertEqual(sync(self.source, self.dest)['additions'], 1)
        self.assertFalse((self.dest / NAME).exists())

    def test_publish_preserves_manifest_and_is_idempotent(self):
        (self.source / '.sprockets-manifest-new.json').write_text('new manifest')
        manifest = self.dest / '.sprockets-manifest-old.json'
        manifest.write_text('old manifest')
        sync(self.source, self.dest, True)
        self.assertEqual((self.dest / NAME).read_bytes(), b'public css')
        self.assertEqual(manifest.read_text(), 'old manifest')
        self.assertFalse((self.dest / '.sprockets-manifest-new.json').exists())
        self.assertEqual(sync(self.source, self.dest, True)['additions'], 0)

    def test_collision_aborts_before_any_write(self):
        (self.source / ('another-' + 'b' * 64 + '.js')).write_bytes(b'new')
        (self.dest / NAME).write_bytes(b'different')
        with self.assertRaises(ValueError):
            sync(self.source, self.dest, True)
        self.assertEqual(len(list(self.dest.iterdir())), 1)
        self.assertEqual((self.dest / NAME).read_bytes(), b'different')

    def test_source_symlink_refused(self):
        (self.source / ('link-' + 'b' * 64 + '.js')).symlink_to(self.source / NAME)
        with self.assertRaises(ValueError):
            sync(self.source, self.dest, True)
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_destination_parent_symlink_refused(self):
        (self.source / 'nested').mkdir()
        (self.source / 'nested' / NAME).write_bytes(b'nested')
        (self.dest / 'nested').symlink_to(self.source, target_is_directory=True)
        with self.assertRaises(ValueError):
            sync(self.source, self.dest, True)

    def test_non_digest_file_refused(self):
        (self.source / 'settings.json').write_text('not an asset')
        with self.assertRaises(ValueError):
            sync(self.source, self.dest, True)
        self.assertEqual(list(self.dest.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
