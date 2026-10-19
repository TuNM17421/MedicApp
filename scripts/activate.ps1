# Dot-source this script: . .\scripts\activate.ps1
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$toolRoot = Join-Path $projectRoot '.devtools'
$cacheRoot = Join-Path $projectRoot '.devcache'

# Keep the original values so activation is reversible and safe to repeat.
$environmentNames = @('Path', 'JAVA_HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT',
    'ANDROID_USER_HOME', 'ANDROID_EMULATOR_HOME', 'ANDROID_AVD_HOME', 'PUB_CACHE',
    'GRADLE_USER_HOME', 'GH_CONFIG_DIR', 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA',
    'FLUTTER_SUPPRESS_ANALYTICS', 'DART_SUPPRESS_ANALYTICS', 'CI')
if (-not (Get-Variable MedicAppOriginalEnvironment -Scope Global -ErrorAction SilentlyContinue)) {
    $global:MedicAppOriginalEnvironment = @{}
    foreach ($name in $environmentNames) {
        $global:MedicAppOriginalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
}

# Git is already provided by Codex on this machine. Also support a normal Git install.
$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
$gitBin = if ($gitCommand) { Split-Path $gitCommand.Source } else {
    $candidates = @(
        (Join-Path $global:MedicAppOriginalEnvironment['USERPROFILE'] '.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd'),
        'C:\Program Files\Git\cmd'
    )
    $candidates | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'git.exe') } | Select-Object -First 1
}
if (-not $gitBin) { throw 'Git for Windows is required. Install Git or add git.exe to PATH.' }

$env:JAVA_HOME = Join-Path $toolRoot 'jdk'
$env:ANDROID_HOME = Join-Path $toolRoot 'android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:ANDROID_USER_HOME = Join-Path $cacheRoot 'android'
$env:ANDROID_EMULATOR_HOME = Join-Path $cacheRoot 'android\emulator'
$env:ANDROID_AVD_HOME = Join-Path $cacheRoot 'android\avd'
$env:PUB_CACHE = Join-Path $cacheRoot 'pub'
$env:GRADLE_USER_HOME = Join-Path $cacheRoot 'gradle'
$env:GH_CONFIG_DIR = Join-Path $cacheRoot 'gh'
# Flutter configuration/analytics and Windows app caches stay inside the project.
$env:USERPROFILE = Join-Path $cacheRoot 'profile'
$env:APPDATA = Join-Path $env:USERPROFILE 'AppData\Roaming'
$env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:DART_SUPPRESS_ANALYTICS = 'true'
$env:CI = 'true'
foreach ($directory in @($env:ANDROID_USER_HOME, $env:PUB_CACHE, $env:GRADLE_USER_HOME,
    $env:GH_CONFIG_DIR, $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}
$toolPaths = @((Join-Path $toolRoot 'flutter\bin'), (Join-Path $toolRoot 'jdk\bin'),
    (Join-Path $toolRoot 'android-sdk\platform-tools'),
    (Join-Path $toolRoot 'android-sdk\cmdline-tools\latest\bin'),
    (Join-Path $toolRoot 'gh\bin'), $gitBin)
$env:Path = ($toolPaths + $global:MedicAppOriginalEnvironment['Path']) -join ';'
Write-Host 'MedicApp environment active in this PowerShell session.'
