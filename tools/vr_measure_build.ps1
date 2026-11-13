<## Build Q's read-only development clock helper, never a package input. ##>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'lib\VsDevEnv.psm1') -Force
$savedEnvironment = @{}
foreach ($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) { $savedEnvironment[$entry.Key] = $entry.Value }
$target = Join-Path $repo 'out\vr\v2q\inspect'
New-Item -ItemType Directory -Force -Path $target | Out-Null
Push-Location $target
try {
    Enter-VsDevEnv
    $env:TEMP = Join-Path $repo 'out\tmp'
    $env:TMP = $env:TEMP
    New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
    & cl.exe /nologo /EHsc /LD /MT /std:c++20 /O2 /W4 "/I$repo\third_party\gmod\include" "$repo\vr\native\tests\qinspect.cpp" /link user32.lib /OUT:gmcl_nlvrqinspect_win64.dll
    if ($LASTEXITCODE -ne 0) { throw "Clock helper build failed: $LASTEXITCODE" }
} finally {
    Pop-Location
    foreach ($entry in @([Environment]::GetEnvironmentVariables('Process').GetEnumerator())) {
        if (-not $savedEnvironment.ContainsKey($entry.Key)) { [Environment]::SetEnvironmentVariable($entry.Key, $null, 'Process') }
    }
    foreach ($entry in $savedEnvironment.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
}
Write-Host "Development helper: $target\gmcl_nlvrqinspect_win64.dll"
