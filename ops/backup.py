#!/usr/bin/env python3
"""Make an online SQLite snapshot and rotate this service's restricted backups."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import fcntl
import os
from pathlib import Path
import sqlite3
import time


def backup(service: Path, now: float | None = None) -> Path:
    now = time.time() if now is None else now
    service = service.resolve(strict=True)
    source = service / 'data' / 'makeet.sqlite'
    if source.is_symlink() or not source.is_file():
        raise RuntimeError('Makeet database unavailable')
    directory = service / 'backups'
    if directory.is_symlink():
        raise RuntimeError('Backup directory must not be a symlink')
    directory.mkdir(mode=0o700, exist_ok=True)
    directory.chmod(0o700)
    with (directory / '.lock').open('a') as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        stamp = datetime.fromtimestamp(now, timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        target = directory / ('makeet-' + stamp + '.sqlite')
        temporary = target.with_suffix('.partial')
        if target.exists() or temporary.exists():
            raise RuntimeError('Backup name already exists')
        try:
            with sqlite3.connect(source.as_uri() + '?mode=ro', uri=True, timeout=30) as live:
                with sqlite3.connect(temporary, timeout=30) as snapshot:
                    temporary.chmod(0o600)
                    live.backup(snapshot)
                    if snapshot.execute('PRAGMA quick_check').fetchone() != ('ok',):
                        raise RuntimeError('Backup integrity check failed')
            temporary.replace(target)
            os.utime(target, (now, now))
        finally:
            temporary.unlink(missing_ok=True)
        for path in directory.glob('*.sqlite'):
            if path.is_file() and not path.is_symlink() and path != target and path.stat().st_mtime < now - 30 * 86400:
                path.unlink()
        return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--service-dir', type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    backup(args.service_dir)
    print('Makeet backup verified; 30-day rotation complete')
