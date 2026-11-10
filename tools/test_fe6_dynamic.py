"""Exercise the dynamic FE6 importer using a supplied, unchanged local cartridge.

All mutation fixtures and generated content stay in an isolated user directory.
"""
import argparse
from pathlib import Path
import json
from fe6_suites import SUITES, identity, require_suite
from test_runner import SOURCE_ROOT as ROOT, passed, add_arguments, configure, project_path, engine_path, output_root, execute



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rom", type=Path, nargs="?")
    parser.add_argument("--list", action="store_true", help="List portable shared suites")
    parser.add_argument("--suite", choices=SUITES)
    parser.add_argument("--routing", action="store_true", help="Live import smoke test for either FE6 ROM")
    parser.add_argument("--stock", action="store_true", help="Compatibility alias for --routing (also accepts FE7)")
    parser.add_argument("--campaign", action="store_true", help="Compile and exercise every dynamic FE6 chapter")
    parser.add_argument("--chapter1", action="store_true", help="Check native title, chapter 1 visits and first-turn AI")
    parser.add_argument("--coverage", action="store_true", help="Check progression, lazy supports and special unit traits")
    parser.add_argument("--presentation", action="store_true", help="Check dynamic audio, arena presentation and endings")
    parser.add_argument("--libraries", action="store_true", help="Check in-memory art libraries, staff actions and battle speed")
    parser.add_argument("--interactions", action="store_true", help="Check native room reveals, Info and cartridge browser interactions")
    parser.add_argument("--rogue", action="store_true", help="Check dynamic Rogue modes, skills, deployment and campaign saves")
    parser.add_argument("--focused", action="store_true", help="Run only the targeted mechanics portion of --rogue")
    add_arguments(parser)
    args = parser.parse_args(); configure(args)
    if args.list:
        for name, spec in SUITES.items(): print(f"{spec.group:10} {name:14} {spec.description}")
        return 0
    if args.rom is None: parser.error("rom is required unless --list is used")
    modes = [name for name in ("stock", "campaign", "chapter1", "coverage", "presentation", "libraries", "interactions", "rogue") if getattr(args, name)]
    if args.routing: modes.append("routing")
    if args.suite: modes.append(args.suite)
    if len(modes) > 1:
        parser.error("Choose one test suite")
    suite = modes[0] if modes else "mutations"
    if suite == "stock": suite = "routing"
    if args.focused and suite != "rogue":
        parser.error("--focused requires --rogue")
    try:
        code, digest = identity(args.rom)
        require_suite(suite, code, digest)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    spec = SUITES[suite]
    script = spec.script
    profile = output_root() / 'dynamic-fe6-tests' / f'{code}-{digest[:12]}' / suite
    profile.mkdir(parents=True, exist_ok=True)
    project = project_path()
    command = [str(engine_path()),
               "--headless", "--quit-after", "600", "--path", str(project), "--script",
               str(ROOT / script), "--", str(args.rom.resolve())]
    if suite == "routing":
        command.append("routing")
    if args.focused:
        command.append("focused")
    exit_code, output = execute(command, profile, timeout=spec.timeout)
    (profile / f"{suite}.log").write_text(output, encoding="utf-8")
    print(output)
    unchanged = identity(args.rom)[1] == digest
    ok = passed(output, exit_code, spec.completion) and unchanged
    (profile / 'result.json').write_text(json.dumps(dict(suite=suite, group=spec.group,
        code=code, rom_sha256=digest, source_unchanged=unchanged, passed=ok,
        exit_code=exit_code, log=str(profile / f'{suite}.log')), indent=2)+'\n')
    if not unchanged: print('FAIL: Supplied cartridge changed during the test')
    if spec.completion not in output: print('FAIL: Test ended without its completion marker')
    return int(not ok)


if __name__ == "__main__":
    raise SystemExit(main())
