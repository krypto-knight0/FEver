param(
    [string]$Python = 'python',
    [string]$RomPath,
    [string[]]$Suites,
    [string]$Project,
    [string]$Godot,
    [string]$Output,
    [switch]$IncludeServices,
    [switch]$IncludeEnding,
    [switch]$SkipImport,
    [switch]$List
)
$ErrorActionPreference = 'Stop'
$arguments = @((Join-Path $PSScriptRoot 'run_fe7_tests.py'))
if ($RomPath) { $arguments += @('--rom', $RomPath) }
if ($Suites) { $arguments += '--suites'; $arguments += $Suites }
if ($Project) { $arguments += @('--project', $Project) }
if ($Godot) { $arguments += @('--godot', $Godot) }
if ($Output) { $arguments += @('--output', $Output) }
if ($IncludeServices) { $arguments += '--include-services' }
if ($IncludeEnding) { $arguments += '--include-ending' }
if ($SkipImport) { $arguments += '--skip-import' }
if ($List) { $arguments += '--list' }
& $Python @arguments
if ($LASTEXITCODE -ne 0) { throw 'FE7 tests failed; see the runner log paths.' }
