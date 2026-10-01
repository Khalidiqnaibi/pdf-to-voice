<#
.SYNOPSIS
  Downloads the Kokoro speech bundle into models/ so the build can ship it.

.DESCRIPTION
  The bundle is too large for git, so it is fetched on demand. It holds the
  full-precision Kokoro v1.0 model, the 54-voice pack, the token table, the
  espeak-ng phoneme data and the lexicons — everything the engine needs to speak
  offline. The desktop build copies models/ into the application bundle; on
  mobile the same archive is downloaded on first launch.

  Already-complete downloads are left alone, so this is safe to re-run.

.EXAMPLE
  pwsh tool/fetch_models.ps1
  pwsh tool/fetch_models.ps1 -Force
#>
[CmdletBinding()]
param(
    # Re-download and re-extract even if the bundle already looks complete.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root 'models'
$url = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2'

# What the engine refuses to start without.
$required = @('model.onnx', 'voices.bin', 'tokens.txt', 'espeak-ng-data')

function Test-Bundle {
    if (-not (Test-Path $dest)) { return $false }
    foreach ($item in $required) {
        if (-not (Test-Path (Join-Path $dest $item))) { return $false }
    }
    # A truncated download leaves a plausible-looking but tiny model behind.
    return (Get-Item (Join-Path $dest 'model.onnx')).Length -gt 300MB
}

if (-not $Force -and (Test-Bundle)) {
    $mb = [math]::Round((Get-ChildItem $dest -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
    Write-Host "  ok       Kokoro bundle already present ($mb MB)"
    Write-Host "Models ready in $dest"
    exit 0
}

$archive = Join-Path $env:TEMP 'kokoro-multi-lang-v1_0.tar.bz2'
$staging = Join-Path $env:TEMP 'kokoro-extract'

Write-Host '  fetching Kokoro bundle (about 333 MB)'
$previous = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
try {
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
} finally {
    $ProgressPreference = $previous
}

if ((Get-Item $archive).Length -lt 300MB) {
    Remove-Item $archive -Force
    throw 'Download was truncated; re-run the script.'
}

Write-Host '  extracting'
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Path $staging | Out-Null

# bsdtar ships with Windows 10 1803+ and handles .tar.bz2 in one pass.
& tar -xf $archive -C $staging
if ($LASTEXITCODE -ne 0) { throw 'Extraction failed. Is tar available on PATH?' }

$extracted = Get-ChildItem $staging -Directory | Select-Object -First 1
if (-not $extracted) { throw 'Archive did not contain the expected folder.' }

if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Move-Item -Path $extracted.FullName -Destination $dest

Remove-Item $archive -Force
Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue

if (-not (Test-Bundle)) {
    throw "Bundle is incomplete after extraction; expected $($required -join ', ') in $dest."
}

$mb = [math]::Round((Get-ChildItem $dest -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
Write-Host ''
Write-Host "  done     Kokoro bundle ready ($mb MB)"
Write-Host "It will be copied into the app bundle on the next desktop build."
