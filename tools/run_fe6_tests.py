"""Self-contained shared FE6 test runner; no private fixtures."""
import argparse
import json
import sys
from pathlib import Path
from fe6_suites import SUITES, identity, require_suite
from test_runner import SOURCE_ROOT, add_arguments, configure, output_root, execute, passed

GROUPS = ('shared',)


def available(group):
    if group == 'shared': return tuple(SUITES)
    raise ValueError('Only shared suites belong to this runner')


def select(group, requested):
    defaults = available(group)
    names = tuple(requested) if requested else defaults
    invalid = set(names) - set(available(group))
    if invalid: raise ValueError(f'{group} does not contain: {", ".join(sorted(invalid))}')
    return tuple(dict.fromkeys(names))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--group', choices=GROUPS, default='shared')
    parser.add_argument('--rom', type=Path)
    parser.add_argument('--suites', nargs='+')
    parser.add_argument('--list', action='store_true')
    add_arguments(parser)
    args = parser.parse_args(); configure(args)
    if args.list:
        for group in GROUPS: print(f'{group}: {", ".join(available(group))}')
        return 0
    try:
        names = select(args.group, args.suites)
        if not args.rom: raise ValueError('--rom is required for shared tests')
        args.rom = args.rom.resolve()
        code, digest = identity(args.rom)
        if code not in ('AFEJ','FX6E'): raise ValueError('shared requires AFEJ or FX6E')
        for name in names: require_suite(name, code, digest)
    except (OSError, ValueError) as exc: parser.error(str(exc))
    report = output_root()/'fe6-suite-runs'/f'{args.group}-{code}-{digest[:12] or "synthetic"}'
    report.mkdir(parents=True, exist_ok=True)
    results = []
    for name in names:
        command = [SOURCE_ROOT/'tools/test_fe6_dynamic.py', args.rom, '--suite', name]
        marker = SUITES[name].completion
        print(f'[{args.group}] {name}', flush=True)
        command = [sys.executable, *command]
        status, output = execute(command, report/'profile', timeout=900)
        log = report/(name+'.log'); log.write_text(output, encoding='utf-8')
        ok = passed(output, status, marker)
        results.append(dict(suite=name, passed=ok, exit_code=status, log=str(log), command=list(map(str,command))))
        print(f'  {"PASS" if ok else "FAIL"}: {log}', flush=True)
        if not ok: print(output[-6000:], flush=True)
    unchanged = identity(args.rom)[1] == digest
    ok = unchanged and all(r['passed'] for r in results)
    (report/'summary.json').write_text(json.dumps(dict(group=args.group, code=code,
        rom_sha256=digest, source_unchanged=unchanged, passed=ok, results=results),indent=2)+'\n')
    print(f'FE6 {args.group}: {sum(r["passed"] for r in results)}/{len(results)} passed; {report / "summary.json"}')
    return int(not ok)


if __name__ == '__main__': raise SystemExit(main())
