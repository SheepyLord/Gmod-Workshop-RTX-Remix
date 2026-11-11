param([string]$Out = 'out/vr/d/s4/build')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
Import-Module (Join-Path $repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv
$output = [IO.Path]::GetFullPath((Join-Path $repo $Out))
$allowed = [IO.Path]::GetFullPath((Join-Path $repo 'out')) + [IO.Path]::DirectorySeparatorChar
if (-not $output.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'S4 build outputs must stay below this worktree out directory'
}
New-Item -ItemType Directory -Force $output | Out-Null
$env:TEMP = Join-Path $repo 'out/tmp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force $env:TEMP | Out-Null
$compileArguments = @('/nologo','/std:c++20','/O2','/MT','/EHsc','/W4','/WX','/LD','/utf-8',
  '/DWIN32_LEAN_AND_MEAN','/DNOMINMAX','/DUNICODE','/D_UNICODE',
  ("/I" + (Join-Path $repo 'third_party/gmod/include')),
  (Join-Path $PSScriptRoot 'module.cpp'),
  ("/Fo" + (Join-Path $output 'module.obj')),
  '/link',("/IMPLIB:" + (Join-Path $output 'module.lib')),
  ("/OUT:" + (Join-Path $output 'gmcl_nlvrs4_win64.dll')))
& cl @compileArguments
if ($LASTEXITCODE) { throw "spike build failed: $LASTEXITCODE" }
