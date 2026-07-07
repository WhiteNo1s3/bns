# BNS .bns File Association Registration (Windows)
# Ported from the reference wave (2026-07-05), adapted to this repo layout.
#
# Run AFTER `flutter build windows --release` (or point -ExePath at any bns.exe,
# e.g. the one in dist\windows\). Effect: double-clicking any *.bns launches
# THIS BNS app with the file path; main() imports it (strict packer validation
# + SHA-256 integrity run inside). Matches the "only the application gets the
# .bns files as payload" promise.
#
# Per-user (HKCU) by default — no admin needed. -MachineWide uses HKLM (admin).
# Only touches .bns keys; unregister by deleting them (printed at the end).

param(
    [string]$ExePath = "",
    [switch]$MachineWide
)

Write-Host "=== Register BNS for .bns files ===" -ForegroundColor Cyan

$root = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrEmpty($ExePath)) {
    $candidates = @(
        "$root\dist\windows\bns.exe",
        "$root\build\windows\x64\runner\Release\bns.exe",
        "$PSScriptRoot\bns.exe"
    )
    $ExePath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $ExePath -or -not (Test-Path $ExePath)) {
    Write-Host "Could not find bns.exe — build first, or pass -ExePath 'C:\path\to\bns.exe'" -ForegroundColor Red
    exit 1
}

$ExePath = (Resolve-Path $ExePath).Path
Write-Host "Using executable: $ExePath" -ForegroundColor Green

$progId = "BNSFile"
$desc = "BNS Private Data File (.bns) - opens only in the BNS application"
$base = if ($MachineWide) { "HKLM:\Software\Classes" } else { "HKCU:\Software\Classes" }

New-Item -Path "$base\.bns" -Force | Out-Null
Set-ItemProperty -Path "$base\.bns" -Name "(Default)" -Value $progId -Force
New-Item -Path "$base\.bns" -Name "OpenWithProgids" -Force | Out-Null
# Content type matches the identity marker inside every v2 .bns
Set-ItemProperty -Path "$base\.bns" -Name "Content Type" -Value "application/x-bns" -Force

New-Item -Path "$base\$progId" -Force | Out-Null
Set-ItemProperty -Path "$base\$progId" -Name "(Default)" -Value $desc -Force

$iconKey = "$base\$progId\DefaultIcon"
New-Item -Path $iconKey -Force | Out-Null
Set-ItemProperty -Path $iconKey -Name "(Default)" -Value "`"$ExePath`",0" -Force

$cmdKey = "$base\$progId\shell\open\command"
New-Item -Path $cmdKey -Force | Out-Null
Set-ItemProperty -Path $cmdKey -Name "(Default)" -Value "`"$ExePath`" `"%1`"" -Force

Write-Host "`n.bns files now open with: $ExePath" -ForegroundColor Green
Write-Host "Test: double-click a .bns (e.g. Documents\exports\BNS_Latest_*.bns)."
Write-Host "Unregister: remove keys $base\.bns and $base\$progId"
