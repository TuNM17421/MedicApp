[CmdletBinding(SupportsShouldProcess = $true)]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'scripts\toolchain.json')) -or
    -not (Test-Path -LiteralPath (Join-Path $projectRoot '05-prototype\flutter_app'))) {
    throw 'This script must run from the MedicApp project.'
}

# Resolve and validate every target before starting any removal.
$relativeTargets = @('.devtools', '.devcache',
    '05-prototype\flutter_app\.dart_tool',
    '05-prototype\flutter_app\build',
    '05-prototype\flutter_app\android\.gradle',
    '05-prototype\flutter_app\android\.kotlin',
    '05-prototype\flutter_app\android\.cxx',
    '05-prototype\flutter_app\android\app\.cxx',
    '05-prototype\flutter_app\android\app\build',
    '05-prototype\flutter_app\android\local.properties',
    '05-prototype\flutter_app\.flutter-plugins-dependencies')
$targets = foreach ($relative in $relativeTargets) {
    $absolute = [IO.Path]::GetFullPath((Join-Path $projectRoot $relative))
    if (-not $absolute.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a path outside the project: $absolute"
    }
    $candidate = $absolute
    while ($candidate -and $candidate -ne $projectRoot) {
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -Force -LiteralPath $candidate
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Refusing to remove a redirected target or ancestor: $candidate"
            }
        }
        $candidate = Split-Path $candidate -Parent
    }
    $absolute
}
if ($PSCmdlet.ShouldProcess($projectRoot, 'Stop project tools and remove local SDKs, caches and generated build files')) {
    # Log out with gh first if you want to remove credentials held in Windows Credential Manager.
    $adb = Join-Path $projectRoot '.devtools\android-sdk\platform-tools\adb.exe'
    if (Test-Path -LiteralPath $adb) { & $adb kill-server }
    $gradlew = Join-Path $projectRoot '05-prototype\flutter_app\android\gradlew.bat'
    if ((Test-Path -LiteralPath $gradlew) -and
        (Test-Path -LiteralPath (Join-Path $projectRoot '.devcache\gradle\daemon')) -and
        (Test-Path -LiteralPath (Join-Path $projectRoot '.devtools\jdk\bin\java.exe'))) {
        . (Join-Path $PSScriptRoot 'activate.ps1')
        Push-Location (Split-Path $gradlew)
        try { & $gradlew --stop } finally {
            Pop-Location
            . (Join-Path $PSScriptRoot 'deactivate.ps1')
        }
    }
    . (Join-Path $PSScriptRoot 'deactivate.ps1')
    foreach ($target in $targets) {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }
    Write-Host 'Local tools and caches removed. Source and research files preserved.'
}
