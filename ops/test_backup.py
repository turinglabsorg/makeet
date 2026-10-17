import importlib.util
from pathlib import Path
import os
import sqlite3
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('makeet_backup', Path(__file__).with_name('backup.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BackupTests(unittest.TestCase):
    def test_snapshot_restores_committed_wal_and_rotates_only_backup_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            service = Path(tmp)
            (service / 'data').mkdir()
            source = service / 'data' / 'makeet.sqlite'
            with sqlite3.connect(source) as db:
                db.execute('PRAGMA journal_mode=WAL')
                db.execute('CREATE TABLE records(id TEXT PRIMARY KEY, value TEXT)')
                db.execute("INSERT INTO records VALUES('fixture','retained')")
                db.commit()
                first = module.backup(service, now=1_800_000_000)
                with sqlite3.connect(first) as restored:
                    self.assertEqual(restored.execute('SELECT * FROM records').fetchall(), [('fixture', 'retained')])
                    self.assertEqual(restored.execute('PRAGMA integrity_check').fetchone(), ('ok',))
                keep = service / 'backups' / 'keep.txt'
                keep.write_text('unrelated')
                module.backup(service, now=1_800_000_000 + 31 * 86400)
                self.assertFalse(first.exists())
                self.assertTrue(keep.exists())
                for path in (service / 'backups').glob('*.sqlite'):
                    self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_symlink_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            service = Path(tmp); (service / 'data').mkdir()
            original = service / 'other.sqlite'; original.touch()
            (service / 'data' / 'makeet.sqlite').symlink_to(original)
            with self.assertRaises(RuntimeError):
                module.backup(service)


if __name__ == '__main__':
    unittest.main()
