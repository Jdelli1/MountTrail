<#
.SYNOPSIS
  Links this repository into a WoW Retail install as an addon (dev install).

.DESCRIPTION
  Creates a directory junction
    <WowPath>\_retail_\Interface\AddOns\AzerothTrail  ->  <repo root>
  so edits in the repository show up in game after /reload.
  Creates the AddOns folder if it is missing, but exits 1 when <WowPath>\_retail_
  does not exist (e.g. the _retail_ folder itself was passed). Safe to run repeatedly: an existing
  junction is reported and left alone (exit 0). If the target exists and is not a
  junction (a real folder or file), the script refuses and exits 1.

.PARAMETER WowPath
  The World of Warcraft install folder, the one that contains _retail_.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\link_addon.ps1 -WowPath "C:\Program Files (x86)\World of Warcraft"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$WowPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$retail   = Join-Path $WowPath '_retail_'
$addOns   = Join-Path $retail 'Interface\AddOns'
$target   = Join-Path $addOns 'AzerothTrail'

if (-not (Test-Path -LiteralPath $WowPath -PathType Container)) {
    Write-Host "WowPath does not exist: $WowPath"
    exit 1
}

# Catches passing the _retail_ folder itself (or any folder that is not the
# WoW install root): the script never creates _retail_.
if (-not (Test-Path -LiteralPath $retail -PathType Container)) {
    Write-Host "No _retail_ folder in WowPath: $retail does not exist. Pass the World of Warcraft install folder that contains _retail_, not _retail_ itself."
    exit 1
}

if (-not (Test-Path -LiteralPath $addOns -PathType Container)) {
    # New-Item has no -LiteralPath (PowerShell 5.1) and treats [ ] in paths as
    # wildcards, so create the folder and the junction with literal-path calls.
    [void][IO.Directory]::CreateDirectory($addOns)
    Write-Host "Created $addOns"
}

# Test-Path -LiteralPath sees through a dangling junction, so look at the item itself.
$existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
if ($null -ne $existing) {
    $isLink = ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    if ($isLink -and $existing.LinkType -eq 'Junction') {
        Write-Host "Already linked: $target -> $($existing.Target)"
        exit 0
    }
    Write-Host "Refusing: $target already exists and is not a junction. Move or delete it yourself, then run again."
    exit 1
}

# '2>&1' is passed to cmd (not PowerShell), so mklink's errors come back as
# plain text instead of stopping the script as a NativeCommandError.
$mklink = cmd /c mklink /J "$target" "$repoRoot" '2>&1'
if ($LASTEXITCODE -ne 0) {
    Write-Host "Could not create the junction ${target}: $mklink"
    exit 1
}
Write-Host "Linked $target -> $repoRoot"
exit 0
