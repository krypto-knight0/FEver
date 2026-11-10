"""Game-independent process, path and isolation helpers for developer tests."""
import os
from pathlib import Path
import shutil
import subprocess

SOURCE_ROOT = Path(__file__).resolve().parents[1]


def project_path():
    supplied = os.environ.get('TEST_GODOT_PROJECT')
    if supplied: return Path(supplied).resolve()
    return SOURCE_ROOT/'godot'


def workspace_path():
    """Find a local toolchain beside repo/; standalone trees use their own root."""
    parent = SOURCE_ROOT.parent
    return parent if (parent/'.tools').is_dir() else SOURCE_ROOT


def engine_path():
    supplied = os.environ.get('TEST_GODOT_EXECUTABLE')
    if supplied: return Path(supplied).resolve()
    bundled = workspace_path()/'.tools/godot/Godot_v4.6.2-stable_win64_console.exe'
    if bundled.is_file(): return bundled
    found = shutil.which('godot') or shutil.which('godot4')
    if found: return Path(found)
    raise ValueError('Godot not found; supply --godot or TEST_GODOT_EXECUTABLE')


def output_root():
    supplied = os.environ.get('TEST_OUTPUT_ROOT')
    return Path(supplied).resolve() if supplied else workspace_path()/'build'


def add_arguments(parser):
    parser.add_argument('--project', type=Path, help='Godot application directory')
    parser.add_argument('--godot', type=Path, help='Godot console executable')
    parser.add_argument('--output', type=Path, help='Root for logs and isolated test profiles')


def configure(args):
    for name, key in [('project','TEST_GODOT_PROJECT'), ('godot','TEST_GODOT_EXECUTABLE'), ('output','TEST_OUTPUT_ROOT')]:
        value = getattr(args, name, None)
        if value: os.environ[key] = str(value.resolve())


def passed(output, returncode, completion):
    return returncode == 0 and completion in output and not any(
        marker in output for marker in ('SCRIPT ERROR:', 'ERROR:', 'FAIL:', 'Traceback (most recent call last)'))


def execute(command, profile, timeout=180):
    profile.mkdir(parents=True, exist_ok=True)
    try:
        result = subprocess.run(list(map(str, command)), cwd=SOURCE_ROOT,
            env=dict(os.environ, APPDATA=str(profile)), capture_output=True,
            encoding='utf-8', errors='replace', timeout=timeout,
            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        return result.returncode, result.stdout + result.stderr
    except subprocess.TimeoutExpired as exc:
        decode = lambda v: v.decode('utf-8', errors='replace') if isinstance(v, bytes) else v or ''
        return -1, decode(exc.stdout)+decode(exc.stderr)+'\nERROR: Test timed out\n'
