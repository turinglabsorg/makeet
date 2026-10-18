#!/usr/bin/env python3
"""Start the isolated Makeet service with private runtime policy configuration."""
import argparse
import json
import os
from pathlib import Path
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--service-dir', type=Path, required=True)
args = parser.parse_args()
service = args.service_dir.resolve(strict=True)
try:
    config = service / 'config.json'
    if config.is_symlink() or config.stat().st_mode & 0o077:
        raise RuntimeError('Configuration permissions must be private')
    values = json.loads(config.read_text())
    allowed = {'MAKEET_PRIVACY_CONTROLLER', 'MAKEET_HOSTING_COUNTRY', 'MAKEET_APPLE_CLIENT_IDS',
               'MAKEET_GOOGLE_CLIENT_IDS', 'MAKEET_BILLING_ENABLED', 'MAKEET_BILLING_SANDBOX', 'MAKEET_APPLE_TEAM_ID', 'MAKEET_APPLE_KEY_ID',
               'MAKEET_APNS_TEAM_ID', 'MAKEET_APNS_KEY_ID', 'MAKEET_APNS_ENVIRONMENT', 'MAKEET_APNS_TOPICS', 'MAKEET_TRUST_RELAY'}
    if set(values) - allowed or any(not isinstance(v, str) for v in values.values()):
        raise RuntimeError('Invalid runtime configuration')
    environment = os.environ.copy()
    environment.update(values)
    environment['MAKEET_LISTEN'] = '127.0.0.1:8086'
    environment['MAKEET_DATABASE'] = str(service / 'data' / 'makeet.sqlite')
    os.umask(0o077)
    binary = str(service / 'bin' / 'makeet')
    os.execve(binary, [binary], environment)
except (OSError, ValueError, RuntimeError):
    sys.exit('Makeet runtime configuration unavailable')
