"""Portable English FE7 test requirements, not runtime recognition rules."""
from dataclasses import dataclass
import hashlib
from pathlib import Path


@dataclass(frozen=True)
class Suite:
    script: str
    completion: str
    description: str
    arguments: tuple[str, ...] = ()
    requires_rom: bool = True
    timeout: int = 900


SUITES = {
    'profile': Suite('tests/test_fe7_profile.gd', 'FE7 profile checks:',
                     'ROM-free regional header and relocated-table regressions',
                     requires_rom=False, timeout=120),
    'cards': Suite('tests/fe7/test_dynamic_cartridge_cards.gd', 'Dynamic cartridge cards:',
                   'Header labels, cartridge switching and title cards', timeout=180),
    'cold-media': Suite('tests/fe7/test_cold_rom_media.gd', 'Cold ROM media:',
                        'ROM-free cold media and decoder-isolation regressions', requires_rom=False, timeout=180),
    'image-decoding': Suite('tests/fe7/test_image_decoding.gd', 'Image decoding regressions:',
                            'ROM-free pixel-format and graphics-decoder regressions', requires_rom=False, timeout=180),
    'normal': Suite('tests/fe7/test_fe7_dynamic_us.gd', 'Dynamic FE7 US:',
                    'Normal campaign openings, native mechanics and saves', ('normal',), timeout=1800),
    'hard': Suite('tests/fe7/test_fe7_dynamic_us.gd', 'Dynamic FE7 US:',
                  'Hard campaign openings, native mechanics and saves', ('hard',), timeout=1800),
    'item-rules': Suite('tests/fe7/test_fe7_special_items.gd', 'FE7 special items:',
                        'Native item rules and altered-table regressions', timeout=180),
    'graphics': Suite('tests/fe7/test_fe7_graphics_policy.gd', 'FE7 graphics policy:',
                      'Native graphics pointers, bounds and mutated loader checks', timeout=180),
    'services': Suite('tests/fe7/test_fe7_dynamic_services.gd', 'Dynamic FE7 services:',
                      'Lazy support, arena, library and cartridge-isolation checks'),
    'ending': Suite('tests/fe7/test_fe7_ending_ui.gd', 'ENDING UI CHECKS',
                    'Ending-card UI and native ending metadata', timeout=300),
}
DEFAULT_SUITES = ('profile', 'cards', 'cold-media', 'image-decoding',
                  'normal', 'hard', 'item-rules', 'graphics')
SUPPORTED_CODES = ('AE7E', 'FX7E')


def identity(path):
    """Read the header separately from the digest; never infer identity by name."""
    with Path(path).open('rb') as stream:
        header = stream.read(0xc0)
        if len(header) < 0xc0:
            raise ValueError('Truncated cartridge header')
        stream.seek(0)
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    return header[0xac:0xb0].decode('ascii', errors='replace'), digest


def require_rom(code):
    if code not in SUPPORTED_CODES:
        raise ValueError('These English FE7 suites require an AE7E or FX7E cartridge; '
                         'the runtime validates its native layout during each test')


def select(requested=None, include_services=False, include_ending=False):
    names = list(DEFAULT_SUITES if requested is None else requested)
    if include_services:
        names.append('services')
    if include_ending:
        names.append('ending')
    invalid = set(names) - set(SUITES)
    if invalid:
        raise ValueError('Unknown FE7 suites: ' + ', '.join(sorted(invalid)))
    return tuple(dict.fromkeys(names))
