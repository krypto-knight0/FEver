param(
    [string]$Python = 'python',
    [ValidateSet('shared')][string]$Group = 'shared',
    [string]$RomPath,
    [string[]]$Suites,
    [string]$Project,
    [string]$Godot,
    [string]$Output,
    [switch]$List
)
$ErrorActionPreference = 'Stop'
$arguments = @((Join-Path $PSScriptRoot 'run_fe6_tests.py'), '--group', $Group.ToLowerInvariant())
if ($RomPath) { $arguments += @('--rom', $RomPath) }
if ($Suites) { $arguments += '--suites'; $arguments += $Suites }
if ($Project) { $arguments += @('--project', $Project) }
if ($Godot) { $arguments += @('--godot', $Godot) }
if ($Output) { $arguments += @('--output', $Output) }
if ($List) { $arguments += '--list' }
& $Python @arguments
if ($LASTEXITCODE -ne 0) { throw 'FE6 tests failed; see the runner log paths.' }
