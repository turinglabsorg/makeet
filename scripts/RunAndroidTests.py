#!/usr/bin/env python3
"""Run and retain native evidence only on an explicitly selected emulator."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--serial", required=True)
parser.add_argument("--output", type=Path, default=ROOT / "artifacts/android/runtime")
args = parser.parse_args()
if not re.fullmatch(r"emulator-\d+", args.serial):
    raise SystemExit("This suite is restricted to an explicitly selected emulator.")
adb = shutil.which("adb")
if not adb:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or str(Path.home() / "Library/Android/sdk")
    adb = str(Path(sdk) / "platform-tools/adb")
command = [adb, "-s", args.serial]
if subprocess.check_output(command + ["shell", "getprop", "ro.kernel.qemu"], text=True).strip() != "1":
    raise SystemExit("The selected device is not an emulator.")
args.output.mkdir(parents=True, exist_ok=True)
for file in ["app/build/outputs/apk/debug/app-debug.apk", "app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"]:
    subprocess.run(command + ["install", "-r", str(ROOT / "android" / file)], check=True)
result = subprocess.run(command + ["shell", "am", "instrument", "-w", "-r", "-e", "notClass", "org.turinglabs.makeet.StoreScreenshotsTest", "org.turinglabs.makeet.test/androidx.test.runner.AndroidJUnitRunner"],
                        text=True, capture_output=True, timeout=600)
(args.output / "instrumentation.txt").write_text(result.stdout + result.stderr)
screenshots = Path(tempfile.mkdtemp(prefix="screenshots-", dir=args.output))
subprocess.run(command + ["pull", "/sdcard/Android/data/org.turinglabs.makeet/files/", str(screenshots)], check=False)
match = re.search(r"\bOK \((\d+) tests?\)", result.stdout)
passed = result.returncode == 0 and match is not None and "FAILURES!!!" not in result.stdout and "Process crashed" not in result.stdout
summary = {"serial": args.serial, "passed": passed, "tests": int(match.group(1)) if match else None, "screenshots": screenshots.name}
(args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary))
if not passed:
    print((result.stdout + result.stderr)[-10000:])
    raise SystemExit(1)
