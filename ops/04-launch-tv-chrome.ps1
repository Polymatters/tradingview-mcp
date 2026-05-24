<#
.SYNOPSIS
    L2-Isolation Schritt 4: Chrome im dedizierten Profil mit CDP starten.

.DESCRIPTION
    Startet Chrome mit:
      - Eigenes user-data-dir (isoliert von Standard-Chrome-Profil)
      - --remote-debugging-port=9222 (CDP fuer MCP)
      - --remote-debugging-address=127.0.0.1 (NUR Loopback)
    Idempotent: pruest ob Port schon belegt ist.

.NOTES
    Im 'HAL01-TVResearch' User-Profil ausfuehren (KEIN Admin noetig).
    NICHT als Standard-HAL01 starten - sonst wird Profil im falschen User-Dir angelegt.
#>

[CmdletBinding()]
param(
    [string]$ChromePath  = 'C:\Program Files\Google\Chrome\Application\chrome.exe',
    [string]$UserDataDir = "$env:LOCALAPPDATA\Chrome-TV-MCP",
    [int]$Port           = 9222,
    [string]$StartUrl    = 'https://www.tradingview.com/chart/'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "=== L2-Isolation Schritt 4: Chrome mit CDP starten ===" -ForegroundColor Cyan
Write-Host "  User:         $env:USERNAME" -ForegroundColor Gray
Write-Host "  Chrome:       $ChromePath" -ForegroundColor Gray
Write-Host "  UserDataDir:  $UserDataDir" -ForegroundColor Gray
Write-Host "  Port:         $Port" -ForegroundColor Gray
Write-Host ''

# Sanity-Check: bist du im richtigen User?
if ($env:USERNAME -ne 'HAL01-TVResearch') {
    Write-Host "[WARN] Du bist als '$env:USERNAME' eingeloggt, nicht als 'HAL01-TVResearch'." -ForegroundColor Yellow
    Write-Host "       L2-Isolation verlangt dedizierten User. Trotzdem fortfahren? (y/N)" -ForegroundColor Yellow
    $confirm = Read-Host
    if ($confirm -ne 'y') { Write-Host "Abgebrochen." -ForegroundColor Red; exit 1 }
}

# Chrome-Existenz
if (-not (Test-Path $ChromePath)) {
    # Fallback: x86 Pfad
    $alt = 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
    if (Test-Path $alt) { $ChromePath = $alt }
    else { throw "Chrome nicht gefunden. Bitte Pfad explizit angeben: -ChromePath '<path>'" }
}

# Port-Check
$portInUse = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($portInUse) {
    Write-Host "[WARN] Port $Port ist bereits belegt:" -ForegroundColor Yellow
    $portInUse | Format-Table LocalAddress,LocalPort,OwningProcess
    Write-Host "       Bestehenden Chrome-Prozess zuerst beenden, dann erneut starten." -ForegroundColor Yellow
    exit 1
}

# UserDataDir anlegen falls nicht existiert
if (-not (Test-Path $UserDataDir)) {
    New-Item -ItemType Directory -Path $UserDataDir | Out-Null
    Write-Host "[OK] UserDataDir angelegt: $UserDataDir" -ForegroundColor Green
}

# Chrome starten
$chromeArgs = @(
    "--user-data-dir=$UserDataDir"
    "--remote-debugging-port=$Port"
    "--remote-debugging-address=127.0.0.1"
    "--no-first-run"
    "--no-default-browser-check"
    $StartUrl
)

Write-Host "Starte Chrome mit Args:" -ForegroundColor White
$chromeArgs | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
Write-Host ''

Start-Process -FilePath $ChromePath -ArgumentList $chromeArgs

Start-Sleep -Seconds 2

# Bind-Verifikation
$listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listening) {
    Write-Host "[OK] Chrome lauscht auf Port ${Port}:" -ForegroundColor Green
    $listening | ForEach-Object {
        $addr = $_.LocalAddress
        $color = if ($addr -eq '127.0.0.1' -or $addr -eq '::1') { 'Green' } else { 'Red' }
        Write-Host "      $addr : $($_.LocalPort)  (PID $($_.OwningProcess))" -ForegroundColor $color
    }

    $hasNonLoopback = $listening | Where-Object { $_.LocalAddress -ne '127.0.0.1' -and $_.LocalAddress -ne '::1' }
    if ($hasNonLoopback) {
        Write-Host ''
        Write-Host "[!!! KRITISCH !!!] CDP-Port bindet auf NON-LOOPBACK!" -ForegroundColor Red
        Write-Host "                   Chrome sofort schliessen und --remote-debugging-address=127.0.0.1 verifizieren." -ForegroundColor Red
    }
} else {
    Write-Host "[WARN] Port $Port lauscht (noch) nicht. Chrome braucht evtl. 2-3 Sekunden." -ForegroundColor Yellow
    Write-Host "       Manueller Check: Get-NetTCPConnection -LocalPort $Port -State Listen" -ForegroundColor Gray
}

Write-Host ''
Write-Host "=== Schritt 4 abgeschlossen ===" -ForegroundColor Cyan
Write-Host "Naechster Schritt: TradingView einloggen, dann Claude Code starten" -ForegroundColor White
