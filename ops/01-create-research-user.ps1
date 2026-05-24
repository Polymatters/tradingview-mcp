<#
.SYNOPSIS
    L2-Isolation Schritt 1: Dedizierter Windows-User HAL01-TVResearch anlegen.

.DESCRIPTION
    Erstellt lokalen Standard-User (keine Admin-Rechte) für TradingView-MCP-Sessions.
    Idempotent: existiert User bereits, wird kein Fehler geworfen.

.NOTES
    Muss als Administrator ausgefuehrt werden.
    Setzt Passwort per Secure-String-Abfrage (kein Klartext).
#>

[CmdletBinding()]
param(
    [string]$UserName = 'HAL01-TVResearch',
    [string]$FullName = 'TradingView MCP Research User',
    [string]$Description = 'L2-isolated account for tradingview-mcp / TV / EzPz research. No broker access.'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Dieses Skript muss als Administrator ausgefuehrt werden.'
}

Write-Host "=== L2-Isolation Schritt 1: Research-User anlegen ===" -ForegroundColor Cyan
Write-Host "  Username:    $UserName" -ForegroundColor Gray
Write-Host "  Full Name:   $FullName" -ForegroundColor Gray
Write-Host ''

$existing = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[SKIP] User '$UserName' existiert bereits (SID: $($existing.SID))." -ForegroundColor Yellow
} else {
    Write-Host "Bitte Passwort fuer '$UserName' setzen:" -ForegroundColor White
    $pwd = Read-Host -AsSecureString
    if ($pwd.Length -eq 0) { throw 'Leeres Passwort nicht erlaubt.' }

    New-LocalUser `
        -Name $UserName `
        -Password $pwd `
        -FullName $FullName `
        -Description $Description `
        -PasswordNeverExpires `
        -UserMayNotChangePassword:$false `
        -AccountNeverExpires | Out-Null

    Write-Host "[OK] User '$UserName' angelegt." -ForegroundColor Green
}

# Sicherstellen: NUR in Users-Gruppe, NICHT in Administrators
$inUsers = (Get-LocalGroupMember -Group 'Users' -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$UserName" }).Count -gt 0
if (-not $inUsers) {
    Add-LocalGroupMember -Group 'Users' -Member $UserName
    Write-Host "[OK] '$UserName' zur Gruppe 'Users' hinzugefuegt." -ForegroundColor Green
} else {
    Write-Host "[SKIP] '$UserName' bereits in 'Users'." -ForegroundColor Yellow
}

$inAdmins = (Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$UserName" }).Count -gt 0
if ($inAdmins) {
    Write-Host "[WARN] '$UserName' ist in Administrators! Entferne..." -ForegroundColor Red
    Remove-LocalGroupMember -Group 'Administrators' -Member $UserName
    Write-Host "[OK] '$UserName' aus 'Administrators' entfernt." -ForegroundColor Green
} else {
    Write-Host "[OK] '$UserName' ist NICHT in 'Administrators'." -ForegroundColor Green
}

Write-Host ''
Write-Host "=== Schritt 1 abgeschlossen ===" -ForegroundColor Cyan
Write-Host "Naechster Schritt: .\02-lockdown-chimera-tree.ps1" -ForegroundColor White
