<#
.SYNOPSIS
  Builds a self-contained Python runtime in runtime/ with Kokoro installed.

.DESCRIPTION
  Lumen's speech engine is a small Python sidecar. Rather than requiring a system
  Python with kokoro-onnx installed, this assembles a private runtime from the
  official Windows embeddable distribution and bundles it with the app, so a
  downloaded build speaks on a machine with no Python at all.

  Steps: download the embeddable zip, enable site-packages (the embeddable build
  ships with it switched off), bootstrap pip, install kokoro-onnx, then drop the
  build tooling that is not needed at run time.

  The Windows build copies runtime/ into the application bundle.

.EXAMPLE
  pwsh tool/fetch_runtime.ps1
  pwsh tool/fetch_runtime.ps1 -Force
#>
[CmdletBinding()]
param(
    # Rebuild from scratch even if runtime/ already works.
    [switch]$Force,

    # Embeddable Python version to base the runtime on.
    [string]$PythonVersion = '3.11.9'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root 'runtime'
$python = Join-Path $dest 'python.exe'

# "3.11.9" -> "311", the suffix python.org uses for the ._pth file.
$tag = ($PythonVersion -split '\.')[0, 1] -join ''

function Test-Runtime {
    if (-not (Test-Path $python)) { return $false }
    # Redirect inside cmd: in Windows PowerShell, redirecting a native command's
    # stderr turns its output into an error record and trips -ErrorAction Stop,
    # which would abort the script instead of reporting a broken runtime.
    & cmd /c "`"$python`" -c `"import kokoro_onnx`" >nul 2>&1"
    return $LASTEXITCODE -eq 0
}

if (-not $Force -and (Test-Runtime)) {
    $mb = [math]::Round((Get-ChildItem $dest -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
    Write-Host "  ok       runtime already built ($mb MB)"
    Write-Host "Runtime ready in $dest"
    exit 0
}

if (Test-Path $dest) {
    Write-Host '  cleaning previous runtime'
    Remove-Item $dest -Recurse -Force
}
New-Item -ItemType Directory -Path $dest | Out-Null

$previous = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
try {
    $zip = Join-Path $env:TEMP "python-$PythonVersion-embed-amd64.zip"
    $url = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip"

    Write-Host "  fetching Python $PythonVersion (embeddable)"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $dest -Force
    Remove-Item $zip -Force

    # The embeddable build disables site-packages by default, so pip installs
    # would be invisible to the interpreter. Turn it on and add the folder.
    $pth = Join-Path $dest "python$tag._pth"
    if (-not (Test-Path $pth)) { throw "Expected $pth in the embeddable distribution." }

    # Must be written without a BOM. Windows PowerShell's -Encoding utf8 adds
    # one, which corrupts the first path entry and leaves the interpreter unable
    # to find its own stdlib ("No module named 'encodings'").
    [System.IO.File]::WriteAllLines(
        $pth,
        [string[]]@("python$tag.zip", '.', 'Lib\site-packages', '', 'import site'),
        (New-Object System.Text.UTF8Encoding $false)
    )
    New-Item -ItemType Directory -Path (Join-Path $dest 'Lib\site-packages') -Force | Out-Null

    Write-Host '  bootstrapping pip'
    $getPip = Join-Path $env:TEMP 'get-pip.py'
    Invoke-WebRequest -Uri 'https://bootstrap.pypa.io/get-pip.py' -OutFile $getPip -UseBasicParsing
    & $python $getPip --no-warn-script-location --quiet
    if ($LASTEXITCODE -ne 0) { throw 'pip bootstrap failed.' }
    Remove-Item $getPip -Force

    Write-Host '  installing kokoro-onnx (this pulls onnxruntime and numpy)'
    & $python -m pip install --no-warn-script-location --quiet kokoro-onnx
    if ($LASTEXITCODE -ne 0) { throw 'kokoro-onnx install failed.' }
} finally {
    $ProgressPreference = $previous
}

# pip, setuptools and wheel are build-time only; dropping them saves ~20 MB in
# every shipped copy.
Write-Host '  pruning build tooling'
$sitePackages = Join-Path $dest 'Lib\site-packages'
$prune = @(
    'pip', 'pip-*.dist-info'
    'setuptools', 'setuptools-*.dist-info'
    'wheel', 'wheel-*.dist-info'
    '_distutils_hack', 'distutils-precedence.pth', 'pkg_resources'
)
foreach ($pattern in $prune) {
    Get-ChildItem -Path $sitePackages -Filter $pattern -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Runtime)) {
    throw 'Runtime was assembled but cannot import kokoro_onnx. See the output above.'
}

$mb = [math]::Round((Get-ChildItem $dest -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
Write-Host ''
Write-Host "  done     self-contained runtime ($mb MB)"
Write-Host "Runtime ready in $dest"
Write-Host 'It will be copied into the app bundle on the next Windows build.'
