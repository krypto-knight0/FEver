"""Run shared FE7 regressions with a supplied stock English or Flux Echo 7 ROM.

Only Python's standard library and Godot are needed. No ROMs, decoded media,
Pillow, private authoring tools or archived importers are included or consulted.
"""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys

from fe7_suites import SUITES, DEFAULT_SUITES, identity, require_rom, select
from test_runner import (SOURCE_ROOT, add_arguments, configure, engine_path,
                         project_path, output_root, execute, passed)


@contextmanager
def isolated_environment(profile):
    """Complement test_runner's APPDATA isolation on Linux; do not change HOME."""
    if sys.platform != 'win32' and not sys.platform.startswith('linux'):
        raise ValueError('FE7 runner user-data isolation currently supports Windows and Linux; '
                         'this platform needs a safe Godot user-directory override before running')
    updates = {'XDG_DATA_HOME': str(profile / 'data'),
               'XDG_CONFIG_HOME': str(profile / 'config'),
               'XDG_CACHE_HOME': str(profile / 'cache')}
    previous = {key: os.environ.get(key) for key in updates}
    os.environ.update(updates)
    try:
        yield
    finally:
        for key, value in previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def command_for(suite, engine, project, rom):
    command = [str(engine), '--headless', '--path', str(project),
               '--script', str(SOURCE_ROOT / suite.script)]
    if suite.requires_rom:
        command.extend(['--', str(rom), *suite.arguments])
    return command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom', type=Path, help='Unmodified user-supplied English FE7 or Flux Echo 7 ROM')
    parser.add_argument('--suites', nargs='+', choices=SUITES,
                        help='Replace the default selection: ' + ', '.join(DEFAULT_SUITES))
    parser.add_argument('--include-services', action='store_true', help='Also run support, arena and galleries')
    parser.add_argument('--include-ending', action='store_true', help='Also run ending-card UI checks')
    parser.add_argument('--list', action='store_true', help='List suites without a ROM or Godot')
    parser.add_argument('--skip-import', action='store_true', help='Use an already imported Godot project')
    add_arguments(parser)
    args = parser.parse_args()
    configure(args)
    if args.list:
        for name, suite in SUITES.items():
            label = 'default' if name in DEFAULT_SUITES else 'optional'
            print(f'{name:18} {label:8} {suite.description}')
        return 0
    try:
        names = select(args.suites, args.include_services, args.include_ending)
        if not args.rom and any(SUITES[name].requires_rom for name in names):
            raise ValueError('--rom is required for the selected cartridge suites; '
                             'profile, cold-media and image-decoding can run without a ROM')
        rom = args.rom.resolve() if args.rom else None
        code, digest = identity(rom) if rom else ('synthetic', '')
        if rom:
            require_rom(code)
        engine, project = engine_path(), project_path()
        if not engine.is_file():
            raise ValueError('Godot executable does not exist: ' + str(engine))
        if not (project / 'project.godot').is_file():
            raise ValueError('Godot project.godot is missing: ' + str(project))
        for name in names:
            if not (SOURCE_ROOT / SUITES[name].script).is_file():
                raise ValueError('Required portable test is missing: ' + SUITES[name].script)
        base = output_root()
        if base.is_relative_to(project):
            raise ValueError('--output must be outside the Godot project to keep private test data separate')
        with isolated_environment(base / 'preflight'):
            pass
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    report = base / 'fe7-suite-runs' / f'{code}-{digest[:12] or "rom-free"}' / stamp
    report.mkdir(parents=True, exist_ok=True)
    results = []
    imported = True
    if not args.skip_import:
        print('Preparing Godot project imports', flush=True)
        command = [str(engine), '--headless', '--editor', '--import', '--quit', '--path', str(project)]
        with isolated_environment(report / 'import-profile'):
            status, output = execute(command, report / 'import-profile', timeout=180)
        log = report / 'import.log'
        log.write_text(output, encoding='utf-8')
        imported = passed(output, status, 'Godot Engine')
        results.append(dict(suite='project-import', passed=imported, exit_code=status,
                            log=str(log), command=command))
        if not imported:
            print(output[-6000:], flush=True)
    if imported:
        for name in names:
            suite = SUITES[name]
            command = command_for(suite, engine, project, rom)
            print(f'[fe7] {name}', flush=True)
            with isolated_environment(report / 'profiles' / name):
                status, output = execute(command, report / 'profiles' / name, timeout=suite.timeout)
            log = report / f'{name}.log'
            log.write_text(output, encoding='utf-8')
            ok = passed(output, status, suite.completion)
            results.append(dict(suite=name, passed=ok, exit_code=status, log=str(log), command=command))
            print(f'  {"PASS" if ok else "FAIL"}: {log}', flush=True)
            if not ok:
                print(output[-6000:], flush=True)
    try:
        unchanged = rom is None or identity(rom)[1] == digest
    except OSError:
        unchanged = False
    ok = imported and unchanged and all(row['passed'] for row in results)
    summary = dict(code=code, rom_sha256=digest, source_unchanged=unchanged, passed=ok,
                   suites=list(names), results=results)
    (report / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    if not unchanged:
        print('FAIL: Supplied cartridge changed or became unavailable during the tests')
    tests = [row for row in results if row['suite'] != 'project-import']
    print(f'FE7 suites: {sum(row["passed"] for row in tests)}/{len(names)} passed; {report / "summary.json"}')
    return int(not ok)


if __name__ == '__main__':
    raise SystemExit(main())
