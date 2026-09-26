<#
.SYNOPSIS
  Downloads the Kokoro speech model into models/ so the build can bundle it.

.DESCRIPTION
  The model files are too large for git, so they are fetched on demand. The
  Windows build copies whatever is in models/ into the application bundle, which
  is what lets a downloaded build speak without any extra setup.

  Already-complete files are left alone, so this is safe to re-run.

.EXAMPLE
  pwsh tool/fetch_models.ps1
  pwsh tool/fetch_models.ps1 -Force
#>
[CmdletBinding()]
param(
    # Re-download even if the file already looks complete.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root 'models'
$base = 'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0'

$files = @(
    @{ Name = 'kokoro-v1.0.onnx'; MinBytes = 300MB }
    @{ Name = 'voices-v1.0.bin';  MinBytes = 25MB  }
)

if (-not (Test-Path $dest)) {
    New-Item -ItemType Directory -Path $dest | Out-Null
}

foreach ($file in $files) {
    $path = Join-Path $dest $file.Name

    if (-not $Force -and (Test-Path $path)) {
        $size = (Get-Item $path).Length
        if ($size -ge $file.MinBytes) {
            Write-Host ("  ok       {0} ({1:N0} MB)" -f $file.Name, ($size / 1MB))
            continue
        }
        Write-Host ("  partial  {0} - re-downloading" -f $file.Name)
    }

    $url = "$base/$($file.Name)"
    $temp = "$path.download"
    Write-Host ("  fetching {0}" -f $file.Name)

    # Invoke-WebRequest's progress bar makes large downloads crawl in PS 5.1.
    $previous = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $url -OutFile $temp -UseBasicParsing
    } finally {
        $ProgressPreference = $previous
    }

    $size = (Get-Item $temp).Length
    if ($size -lt $file.MinBytes) {
        Remove-Item $temp -Force
        throw "$($file.Name) downloaded only $([math]::Round($size/1MB,1)) MB; expected at least $([math]::Round($file.MinBytes/1MB,0)) MB."
    }

    Move-Item -Path $temp -Destination $path -Force
    Write-Host ("  done     {0} ({1:N0} MB)" -f $file.Name, ($size / 1MB))
}

Write-Host ''
Write-Host "Models ready in $dest"
Write-Host 'They will be copied into the app bundle on the next Windows build.'
