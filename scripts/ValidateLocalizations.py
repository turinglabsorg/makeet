#!/usr/bin/env python3
"""Validate catalog coverage and interpolation types, optionally against compiler extraction."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re


def placeholders(value):
    return Counter(re.findall(r"%(?:\d+\$)?(@|lld|ld|d|f)", value.replace("%%", "")))


def units(localization):
    if "stringUnit" in localization:
        yield localization["stringUnit"]
    for variation in localization.get("variations", {}).values():
        for item in variation.values():
            yield from units(item)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--extracted-root", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    catalogs = {}
    languages = {"it", "en", "fr", "de", "es"}
    for path in (root / "Resources").glob("*.xcstrings"):
        catalog = json.loads(path.read_text())
        assert catalog["sourceLanguage"] == "it", path
        catalogs[path.stem] = catalog["strings"]
        for key, entry in catalog["strings"].items():
            assert languages <= entry["localizations"].keys(), (path, key, "missing language")
            for language in languages:
                translations = list(units(entry["localizations"][language]))
                assert translations, (key, language, "missing value")
                for unit in translations:
                    assert unit["state"] == "translated", (key, language, "unfinished")
                    assert placeholders(key) == placeholders(unit["value"]), (key, language, "interpolation mismatch")
    if args.extracted_root:
        extracted = set()
        for path in args.extracted_root.rglob("*.stringsdata"):
            data = json.loads(path.read_text())
            if not any(f"/{folder}/" in data.get("source", "") for folder in ["App", "Shared", "Widget"]):
                continue
            for table, entries in data.get("tables", {}).items():
                for entry in entries:
                    key = entry["key"]
                    assert key in catalogs.get(table, {}), (data["source"], key, "missing catalog entry")
                    extracted.add((table, key))
        assert extracted, "No compiler-extracted app/widget strings found"
        print(f"Compiler coverage: {len(extracted)} keys")
    print(f"Validated {sum(map(len, catalogs.values()))} keys in five languages")


if __name__ == "__main__":
    main()
