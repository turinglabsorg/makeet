#!/usr/bin/env python3
"""Run only through nested hush run calls for the Makeet upload credentials."""
import base64
import os
from pathlib import Path
import subprocess
import tempfile

project = Path(__file__).resolve().parents[1]
if not os.environ.get("MAKEET_UPLOAD_PASSWORD"):
    raise SystemExit("The hush upload password is required.")
payload = os.environ.pop("MAKEET_UPLOAD_KEYSTORE", "")
if not payload:
    raise SystemExit("The hush upload keystore is required.")
with tempfile.TemporaryDirectory(prefix="makeet-android-signing-") as folder:
    store = Path(folder) / "upload.p12"
    store.write_bytes(base64.b64decode(payload, validate=True))
    store.chmod(0o600)
    del payload
    env = dict(os.environ, MAKEET_UPLOAD_STORE_FILE=str(store))
    subprocess.run(["./gradlew", "--no-daemon", ":app:bundleRelease", "-PmakeetRequireSigning=true", "--console=plain"],
                   cwd=project, env=env, check=True)
