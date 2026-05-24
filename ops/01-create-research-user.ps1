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
    [string]$Description = 'L2 isolated TV/MCP research, no broker access'
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
# Cross-language: Built-in Gruppen via Well-Known-SID auflösen
#   S-1-5-32-545 = Users / Benutzer / Utilisateurs / ...
#   S-1-5-32-544 = Administrators / Administratoren / ...

try {
    $usersGroup  = Get-LocalGroup -SID 'S-1-5-32-545' -ErrorAction Stop
    $adminsGroup = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop
    Write-Host "[INFO] Lokale Gruppen aufgeloest: Users='$($usersGroup.Name)' / Administrators='$($adminsGroup.Name)'" -ForegroundColor Gray
} catch {
    throw "Konnte built-in Gruppen ueber SID nicht aufloesen: $($_.Exception.Message)"
}

# Note: @(...) wrapper makes .Count work even when Where-Object returns nothing under StrictMode
$usersMatches = @(Get-LocalGroupMember -Group $usersGroup.Name -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$UserName" })
if ($usersMatches.Count -eq 0) {
    try {
        Add-LocalGroupMember -Group $usersGroup.Name -Member $UserName -ErrorAction Stop
        Write-Host "[OK] '$UserName' zur Gruppe '$($usersGroup.Name)' hinzugefuegt." -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Konnte '$UserName' nicht zu '$($usersGroup.Name)' hinzufuegen: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "[SKIP] '$UserName' bereits in '$($usersGroup.Name)'." -ForegroundColor Yellow
}

$adminsMatches = @(Get-LocalGroupMember -Group $adminsGroup.Name -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$UserName" })
if ($adminsMatches.Count -gt 0) {
    Write-Host "[WARN] '$UserName' ist in '$($adminsGroup.Name)'! Entferne..." -ForegroundColor Red
    Remove-LocalGroupMember -Group $adminsGroup.Name -Member $UserName
    Write-Host "[OK] '$UserName' aus '$($adminsGroup.Name)' entfernt." -ForegroundColor Green
} else {
    Write-Host "[OK] '$UserName' ist NICHT in '$($adminsGroup.Name)'." -ForegroundColor Green
}

Write-Host ''
Write-Host "=== Schritt 1 abgeschlossen ===" -ForegroundColor Cyan
Write-Host "Naechster Schritt: .\02-lockdown-chimera-tree.ps1" -ForegroundColor White
