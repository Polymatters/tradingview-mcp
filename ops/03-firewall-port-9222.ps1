<#
.SYNOPSIS
    L2-Isolation Schritt 3: Windows Firewall Rule fuer Port 9222 (CDP).

.DESCRIPTION
    Erlaubt 9222 NUR auf 127.0.0.1 (Loopback). Blockiert jede LAN-/Internet-Exposure.
    Idempotent. Schreibt zwei Regeln:
      1. ALLOW  TCP/9222 inbound von 127.0.0.1
      2. BLOCK  TCP/9222 inbound von allen anderen Adressen

.NOTES
    Admin-Rechte erforderlich. Inbound-Direction.
#>

[CmdletBinding()]
param(
    [int]$Port = 9222,
    [string]$AllowRuleName = 'TradingView-MCP-CDP-Allow-Loopback',
    [string]$BlockRuleName = 'TradingView-MCP-CDP-Block-NonLoopback',
    [string]$ResearchUser  = 'HAL01-TVResearch'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Dieses Skript muss als Administrator ausgefuehrt werden.'
}

Write-Host "=== L2-Isolation Schritt 3: Firewall Rules fuer Port $Port ===" -ForegroundColor Cyan
Write-Host ''

# Bestehende Regeln entfernen (idempotent)
foreach ($name in @($AllowRuleName, $BlockRuleName)) {
    $existing = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-NetFirewallRule -DisplayName $name
        Write-Host "[CLEANUP] Bestehende Rule '$name' entfernt." -ForegroundColor Yellow
    }
}

# 1) ALLOW von 127.0.0.1
New-NetFirewallRule `
    -DisplayName $AllowRuleName `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort $Port `
    -RemoteAddress '127.0.0.1' `
    -Action Allow `
    -Profile Any `
    -Description "L2 isolation: allow CDP debug port from loopback only." | Out-Null
Write-Host "[OK] ALLOW-Rule '$AllowRuleName' (127.0.0.1 -> :$Port TCP)" -ForegroundColor Green

# 2) BLOCK von allen anderen Adressen
New-NetFirewallRule `
    -DisplayName $BlockRuleName `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort $Port `
    -RemoteAddress 'Any' `
    -Action Block `
    -Profile Any `
    -Description "L2 isolation: block CDP debug port from any non-loopback source." | Out-Null
Write-Host "[OK] BLOCK-Rule '$BlockRuleName' (Any -> :$Port TCP)" -ForegroundColor Green

Write-Host ''
Write-Host "Hinweis: Windows Firewall verarbeitet ALLOW-Regeln vor BLOCK-Regeln" -ForegroundColor Gray
Write-Host "         bei gleicher Spezifizitaet. Loopback-Allow setzt sich gegen Any-Block durch." -ForegroundColor Gray
Write-Host ''
Write-Host "Verifikation nach Chrome-Launch mit --remote-debugging-port=$Port :" -ForegroundColor White
Write-Host "  Lokal:        Test-NetConnection 127.0.0.1 -Port $Port   --> TcpTestSucceeded: True" -ForegroundColor Gray
Write-Host "  Von anderem:  Test-NetConnection <ip> -Port $Port        --> TcpTestSucceeded: False" -ForegroundColor Gray
Write-Host "  netstat:      netstat -an | findstr :$Port" -ForegroundColor Gray
Write-Host "                  muss zeigen: TCP    127.0.0.1:$Port    LISTENING" -ForegroundColor Gray
Write-Host "                  NICHT:        TCP    0.0.0.0:$Port      LISTENING" -ForegroundColor Gray
Write-Host ''
Write-Host "=== Schritt 3 abgeschlossen ===" -ForegroundColor Cyan
Write-Host "Naechster Schritt (als '$ResearchUser' einloggen, dann): .\04-launch-tv-chrome.ps1" -ForegroundColor White
