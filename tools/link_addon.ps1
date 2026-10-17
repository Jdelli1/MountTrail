<#
.SYNOPSIS
  Links this repository into a WoW Retail install as an addon (dev install).

.DESCRIPTION
  Creates a directory junction
    <WowPath>\_retail_\Interface\AddOns\AzerothTrail  ->  <repo root>
  so edits in the repository show up in game after /reload.
  Creates the AddOns folder if it is missing. Safe to run repeatedly: an existing
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
$addOns   = Join-Path $WowPath '_retail_\Interface\AddOns'
$target   = Join-Path $addOns 'AzerothTrail'

if (-not (Test-Path -LiteralPath $WowPath -PathType Container)) {
    Write-Host "WowPath does not exist: $WowPath"
    exit 1
}

if (-not (Test-Path -LiteralPath $addOns -PathType Container)) {
    New-Item -ItemType Directory -Path $addOns -Force | Out-Null
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

New-Item -ItemType Junction -Path $target -Target $repoRoot | Out-Null
Write-Host "Linked $target -> $repoRoot"
exit 0
