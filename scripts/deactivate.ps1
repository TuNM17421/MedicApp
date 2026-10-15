if (Get-Variable MedicAppOriginalEnvironment -Scope Global -ErrorAction SilentlyContinue) {
    foreach ($entry in $global:MedicAppOriginalEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
    Remove-Variable MedicAppOriginalEnvironment -Scope Global
    Write-Host 'Original process environment restored.'
}
