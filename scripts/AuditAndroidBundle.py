#!/usr/bin/env python3
"""Validate the actual distributable bundle, including native alignment and fixture exclusion."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import xml.etree.ElementTree as ET
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("--bundle", required=True, type=Path)
parser.add_argument("--bundletool", required=True, type=Path)
parser.add_argument("--require-signed", action="store_true")
args = parser.parse_args()
subprocess.run(["java", "-jar", str(args.bundletool), "validate", "--bundle=" + str(args.bundle)], check=True, capture_output=True)
config = json.loads(subprocess.check_output(["java", "-jar", str(args.bundletool), "dump", "config", "--bundle=" + str(args.bundle)]))
alignment = config.get("optimizations", {}).get("uncompressNativeLibraries", {}).get("alignment")
assert alignment == "PAGE_ALIGNMENT_16K", "Generated APKs must request 16KB native-library alignment"
xml = subprocess.check_output(["java", "-jar", str(args.bundletool), "dump", "manifest", "--bundle=" + str(args.bundle), "--module=base"])
manifest = ET.fromstring(xml)
android = "{http://schemas.android.com/apk/res/android}"
assert manifest.attrib["package"] == "org.turinglabs.makeet"
sdk = manifest.find("uses-sdk")
assert sdk is not None and int(sdk.get(android + "targetSdkVersion")) >= 36
assert int(sdk.get(android + "minSdkVersion")) == 26
permissions = sorted(p.get(android + "name") for p in manifest.findall("uses-permission"))
assert not any(p in permissions for p in ["com.android.vending.BILLING", "com.google.android.gms.permission.AD_ID", "android.permission.READ_CONTACTS", "android.permission.READ_MEDIA_IMAGES"])
application = manifest.find("application")
assert application is not None and application.get(android + "debuggable", "false") == "false"
assert application.get(android + "allowBackup") == "false"
assert not any("ProfileTestActivity" in a.get(android + "name", "") for a in application.findall("activity"))
native = []
with zipfile.ZipFile(args.bundle) as bundle:
    names = bundle.namelist()
    signed = any(name.startswith("META-INF/") and name.endswith((".RSA", ".EC", ".DSA")) for name in names)
    if args.require_signed:
        assert signed, "The upload bundle is unsigned"
        subprocess.run(["jarsigner", "-verify", str(args.bundle)], check=True, capture_output=True)
    for name in names:
        assert not name.endswith((".p8", ".jks", ".keystore", ".p12", ".storekit")), "Private signing or test resource in bundle"
        if name.endswith(".dex"):
            content = bundle.read(name)
            for marker in [b"ProfileTestActivity", b"ProfileFixtureState", b"fixture-access", b"qa@example.invalid", b"makeet.invalid"]:
                assert marker not in content, "Debug/test fixture in release"
        if name.endswith(".so"):
            data = bundle.read(name)
            assert data[:4] == b"\x7fELF"
            if data[4] == 2:
                endian = "<" if data[5] == 1 else ">"
                offset = struct.unpack_from(endian + "Q", data, 32)[0]
                size, count = struct.unpack_from(endian + "HH", data, 54)
                alignments = []
                for i in range(count):
                    header = offset + size * i
                    if struct.unpack_from(endian + "I", data, header)[0] == 1:
                        alignment = struct.unpack_from(endian + "Q", data, header + 48)[0]
                        assert alignment >= 16384, "Native library lacks 16KB page alignment: " + name
                        alignments.append(alignment)
                native.append({"library": name, "load_alignments": alignments})
print(json.dumps({"package": manifest.attrib["package"], "version": manifest.get(android + "versionName"),
    "version_code": manifest.get(android + "versionCode"), "target_sdk": sdk.get(android + "targetSdkVersion"),
    "signed": signed, "sha256": hashlib.sha256(args.bundle.read_bytes()).hexdigest(), "permissions": permissions, "apk_alignment": alignment,
    "native_64bit": native, "fixtures_excluded": True}, indent=2))
