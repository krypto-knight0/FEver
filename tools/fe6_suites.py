"""Test requirements, not runtime cartridge recognition rules."""
from dataclasses import dataclass
import hashlib
from pathlib import Path

from test_runner import SOURCE_ROOT as ROOT, passed
@dataclass(frozen=True)
class Suite:
    group: str
    script: str
    completion: str
    description: str
    timeout: int = 180


SUITES = {
    'routing': Suite('shared', 'tests/fe6/shared/test_fe6_dynamic.gd', 'Dynamic FE6 checks:', 'Live import and cartridge identity'),
    'mutations': Suite('shared', 'tests/fe6/shared/test_fe6_dynamic.gd', 'Dynamic FE6 checks:', 'Relocated tables, edited data, save isolation'),
    'chapter1': Suite('shared', 'tests/fe6/shared/test_fe6_dynamic_chapter1.gd', 'Dynamic FE6 chapter 1 checks:', 'Title pointers, visits, first-turn AI'),
    'coverage': Suite('shared', 'tests/fe6/shared/test_fe6_dynamic_coverage.gd', 'Dynamic FE6 coverage checks:', 'Supports, progression and native unit traits'),
    'presentation': Suite('shared', 'tests/fe6/shared/test_fe6_dynamic_presentation.gd', 'Dynamic FE6 presentation:', 'Audio routing, arena and endings'),
    'libraries': Suite('shared', 'tests/fe6/shared/test_fe6_dynamic_libraries.gd', 'Dynamic FE6 libraries/staff/speed:', 'Live galleries, staff actions and speed'),
    'interactions': Suite('shared', 'tests/fe6/shared/test_fe6_dynamic_interactions.gd', 'Dynamic FE6 interactions:', 'Room reveals, Info and browser interactions'),
    'campaign': Suite('shared', 'tests/fe6/shared/test_fe6_dynamic_campaign.gd', 'Dynamic campaign checks:', 'All native routes, objectives and save/load', 600),
    'rogue': Suite('shared', 'tests/fe6/shared/test_fe6_dynamic_rogue.gd', 'Dynamic FE6 Rogue:', 'Rogue modes using preserved FE6 mechanics', 600),
}


def identity(path):
    with Path(path).open('rb') as stream:
        header = stream.read(0xc0)
        stream.seek(0)
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if len(header) < 0xc0:
        raise ValueError('Truncated cartridge header')
    return header[0xac:0xb0].decode('ascii', errors='replace'), digest


def require_suite(name, code, digest):
    suite = SUITES[name]
    if suite.group == 'shared':
        # Routing is also the existing FE7 smoke check. The grouped FE6
        # runner restricts its shared group to AFEJ/FX6E.
        if code not in ('AFEJ', 'FX6E') and not (name == 'routing' and code.startswith('AE7')):
            raise ValueError(f'{name} requires the supported FE6 ABI (AFEJ or FX6E)')


