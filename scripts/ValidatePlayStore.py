#!/usr/bin/env python3
"""Check the actual localized Play listing files against their upload constraints."""
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1] / 'PlayStore'
LANGUAGES = ['en-US', 'it-IT', 'fr-FR', 'de-DE', 'es-ES']
SCREENS = ['01-today.png', '02-calendar.png', '03-trends.png', '04-plan.png']

def png(path):
    raw = path.read_bytes()
    assert raw[:8] == b'\x89PNG\r\n\x1a\n' and raw[12:16] == b'IHDR', path
    width, height, bits, color = struct.unpack('>IIBB', raw[16:26])
    assert bits == 8 and color == 2, f'{path}: a 24-bit opaque RGB PNG is required'
    return width, height

assert png(ROOT / 'graphics/app-icon.png') == (512, 512)
for language in LANGUAGES:
    data = json.loads((ROOT / f'metadata/{language}.json').read_text())
    for field, limit in [('title', 30), ('short_description', 80), ('full_description', 4000)]:
        assert 0 < len(data[field]) <= limit, (language, field)
    for field in ['privacy_url', 'support_url', 'deletion_url']:
        assert data[field].startswith(f'https://makeet.app/{language[:2]}/'), (language, field)
    assert 0 < len(data['feature_graphic_alt']) <= 140
    assert png(ROOT / f'graphics/{language}-feature.png') == (1024, 500)
    assert set(data['screenshots_alt']) == set(SCREENS)
    for screen in SCREENS:
        assert 0 < len(data['screenshots_alt'][screen]) <= 140
        width, height = png(ROOT / f'screenshots/{language}/{screen}')
        assert (width, height) == (1080, 1920), (language, screen, width, height)
        assert max(width, height) <= 2 * min(width, height)
print('Verified 5 localized listings, 20 native phone screenshots, 5 feature graphics and the Play icon')
