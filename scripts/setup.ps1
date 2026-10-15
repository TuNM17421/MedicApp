[CmdletBinding()]
param([switch]$AcceptAndroidLicenses)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$toolRoot = Join-Path $projectRoot '.devtools'
$downloadRoot = Join-Path $projectRoot '.devcache\downloads'
$manifest = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $toolRoot, $downloadRoot | Out-Null

function Install-Archive($Spec, [string]$Name, [string]$Destination, [string]$Marker, [string]$Layout) {
    if (Test-Path -LiteralPath (Join-Path $Destination $Marker)) {
        Write-Host "$Name already installed."
        return
    }
    $archive = Join-Path $downloadRoot "$Name.zip"
    if (-not (Test-Path -LiteralPath $archive) -or
        (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $Spec.sha256) {
        Write-Host "Downloading $Name $($Spec.version)..."
        & curl.exe --fail --location --silent --show-error --retry 3 --output $archive $Spec.url
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $Name" }
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $Spec.sha256) {
        throw "SHA256 mismatch: $Name"
    }
    Write-Host "Extracting $Name..."
    if ($Layout -eq 'flutter') {
        & tar.exe -xf $archive -C $toolRoot
    } elseif ($Layout -eq 'jdk') {
        $stage = Join-Path $downloadRoot 'java-extracted'
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        & tar.exe -xf $archive -C $stage
        if ($LASTEXITCODE -ne 0) { throw 'Java extraction failed.' }
        $jdk = Get-ChildItem -LiteralPath $stage -Directory | Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName 'bin\java.exe')
        } | Select-Object -First 1
        if (-not $jdk) { throw 'Java archive has an unexpected layout.' }
        # Both paths are fixed children of this project; never move external directories.
        if (-not $jdk.FullName.StartsWith($downloadRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Invalid Java staging path.'
        }
        Move-Item -LiteralPath $jdk.FullName -Destination $Destination
    } elseif ($Layout -eq 'android') {
        $parent = Split-Path $Destination
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        & tar.exe -xf $archive -C $parent
        if ($LASTEXITCODE -ne 0) { throw 'Android tools extraction failed.' }
        $extracted = Join-Path $parent 'cmdline-tools'
        if (-not $extracted.StartsWith($toolRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Invalid Android tools staging path.'
        }
        Move-Item -LiteralPath $extracted -Destination $Destination
    } else {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        & tar.exe -xf $archive -C $Destination
    }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $Destination $Marker))) {
        throw "Installation failed: $Name"
    }
}

Install-Archive $manifest.gh 'gh' (Join-Path $toolRoot 'gh') 'bin\gh.exe' 'plain'
Install-Archive $manifest.java 'java' (Join-Path $toolRoot 'jdk') 'bin\java.exe' 'jdk'
Install-Archive $manifest.androidCommandLineTools 'android-command-line-tools' (Join-Path $toolRoot 'android-sdk\cmdline-tools\latest') 'bin\sdkmanager.bat' 'android'
Install-Archive $manifest.flutter 'flutter' (Join-Path $toolRoot 'flutter') 'bin\flutter.bat' 'flutter'

. (Join-Path $PSScriptRoot 'activate.ps1')
try {
    & flutter config --no-analytics --android-sdk $env:ANDROID_HOME --jdk-dir $env:JAVA_HOME --enable-android --no-enable-windows-desktop --no-enable-web --no-enable-linux-desktop --no-enable-macos-desktop --no-enable-ios
    if ($LASTEXITCODE -ne 0) { throw 'Flutter configuration failed.' }
    $sdkManager = Join-Path $env:ANDROID_HOME 'cmdline-tools\latest\bin\sdkmanager.bat'
    if ($AcceptAndroidLicenses) {
        $licenseLog = Join-Path $downloadRoot 'android-licenses.log'
        1..100 | ForEach-Object { 'y' } | & $sdkManager "--sdk_root=$env:ANDROID_HOME" --licenses *> $licenseLog
        Write-Host "Android license output saved to $licenseLog"
    } else {
        & $sdkManager "--sdk_root=$env:ANDROID_HOME" --licenses
    }
    if ($LASTEXITCODE -ne 0) { throw 'Android SDK license step failed.' }
    $androidPackages = @($manifest.androidPackages)
    & $sdkManager "--sdk_root=$env:ANDROID_HOME" @androidPackages
    if ($LASTEXITCODE -ne 0) { throw 'Android SDK packages installation failed.' }
    & flutter precache --android
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Android cache download failed.' }
    & gh --version
    & flutter doctor -v
} finally {
    . (Join-Path $PSScriptRoot 'deactivate.ps1')
}
