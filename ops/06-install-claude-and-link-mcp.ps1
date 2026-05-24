<#
.SYNOPSIS
    L2-Isolation Schritt 6 (im HAL01-TVResearch User): Claude Code installieren + MCP-Config verlinken.

.DESCRIPTION
    Im neuen User-Profil (nach User-Wechsel via Win+L) ausfuehren — KEIN Admin noetig.
    Macht:
      1. Verifiziert Node.js >= 18 (Per-Machine installation, sollte vorhanden sein)
      2. Installiert Claude Code via npm global (im User-Profil)
      3. Legt .claude/ Verzeichnis an
      4. Kopiert mcp-config-template.json nach .claude/.mcp.json
      5. Zeigt Verifikations-Hinweis

.NOTES
    Idempotent: schon installierte Komponenten werden uebersprungen.
    Erster Claude-Start danach: claude  (Anthropic-Login-Prompt erscheint)
#>

[CmdletBinding()]
param(
    [string]$McpRepoRoot   = 'C:\dev\tradingview-mcp',
    [string]$McpConfigSrc  = 'C:\dev\tradingview-mcp\ops\mcp-config-template.json'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "=== L2 Schritt 6: Claude Code Install + MCP-Link (User: $env:USERNAME) ===" -ForegroundColor Cyan
Write-Host ''

# Sanity-Check: bist du im richtigen User?
if ($env:USERNAME -ne 'HAL01-TVResearch') {
    Write-Host "[WARN] Du bist als '$env:USERNAME' eingeloggt, nicht als 'HAL01-TVResearch'." -ForegroundColor Yellow
    Write-Host "       L2-Isolation verlangt dedizierten User. Trotzdem fortfahren? (y/N)" -ForegroundColor Yellow
    $confirm = Read-Host
    if ($confirm -ne 'y') { Write-Host "Abgebrochen." -ForegroundColor Red; exit 1 }
}

# === 1) Node.js Check ========================================================
Write-Host "[1/4] Node.js Verfuegbarkeit..." -ForegroundColor White
try {
    $nodeVer = & node --version 2>$null
    if ($nodeVer -match '^v(\d+)' -and [int]$Matches[1] -ge 18) {
        Write-Host "  [OK] Node $nodeVer verfuegbar" -ForegroundColor Green
    } else {
        throw "Node Version zu alt: $nodeVer (brauche v18+)"
    }
} catch {
    Write-Host "  [FAIL] Node.js nicht gefunden oder zu alt: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "         Bitte Node.js >=18 systemweit (Per-Machine) installieren." -ForegroundColor Yellow
    exit 1
}

# === 2) Claude Code installieren =============================================
Write-Host ''
Write-Host "[2/4] Claude Code Installation..." -ForegroundColor White

$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) {
    Write-Host "  [SKIP] Claude Code bereits installiert: $($claudeCmd.Source)" -ForegroundColor Yellow
} else {
    Write-Host "  Installiere via 'npm install -g @anthropic-ai/claude-code'..." -ForegroundColor Gray
    try {
        & npm install -g '@anthropic-ai/claude-code' 2>&1 | Tee-Object -Variable npmOut | Out-Null
        $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
        if (-not $claudeCmd) {
            Write-Host "  [FAIL] npm-Install erfolgreich, aber 'claude' nicht im PATH." -ForegroundColor Red
            Write-Host "         npm prefix: $(npm config get prefix)" -ForegroundColor Gray
            Write-Host "         PATH:       $env:PATH" -ForegroundColor Gray
            Write-Host "  Workaround: neue PowerShell-Session oeffnen (PATH-Update wird nach Install nicht in laufender Session gesehen)" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "  [OK] Claude Code installiert: $($claudeCmd.Source)" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] npm-Install fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Alternative: irm https://claude.ai/install.ps1 | iex" -ForegroundColor Yellow
        exit 1
    }
}

# === 3) .claude Verzeichnis anlegen + MCP-Config kopieren ====================
Write-Host ''
Write-Host "[3/4] MCP-Config installieren..." -ForegroundColor White

$claudeDir = "$env:USERPROFILE\.claude"
if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir | Out-Null
    Write-Host "  [OK] Verzeichnis angelegt: $claudeDir" -ForegroundColor Green
}

$mcpConfigDst = "$claudeDir\.mcp.json"
if (-not (Test-Path $McpConfigSrc)) {
    throw "MCP-Config-Quelle nicht gefunden: $McpConfigSrc"
}

if (Test-Path $mcpConfigDst) {
    Write-Host "  [WARN] Bestehende .mcp.json gefunden: $mcpConfigDst" -ForegroundColor Yellow
    Write-Host "  Backup wird erstellt vor Ueberschreiben..." -ForegroundColor Gray
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$mcpConfigDst.bak-$ts"
    Copy-Item -Path $mcpConfigDst -Destination $backup
    Write-Host "  [OK] Backup: $backup" -ForegroundColor Green
}

Copy-Item -Path $McpConfigSrc -Destination $mcpConfigDst -Force
Write-Host "  [OK] MCP-Config installiert: $mcpConfigDst" -ForegroundColor Green
Write-Host ''
Write-Host "  Inhalt:" -ForegroundColor Gray
Get-Content $mcpConfigDst | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

# === 4) Verifikations-Hinweis =================================================
Write-Host ''
Write-Host "[4/4] Naechste Schritte..." -ForegroundColor White
Write-Host ''
Write-Host "  4.1  Chrome starten (separates Fenster):" -ForegroundColor White
Write-Host "       cd $McpRepoRoot\ops" -ForegroundColor Gray
Write-Host "       .\04-launch-tv-chrome.ps1" -ForegroundColor Gray
Write-Host '       (Chrome oeffnet, TradingView einloggen mit deinem TV-Account)' -ForegroundColor Gray
Write-Host ''
Write-Host "  4.2  Verifikation:" -ForegroundColor White
Write-Host "       .\05-verify-l2-isolation.ps1" -ForegroundColor Gray
Write-Host ''
Write-Host "  4.3  Claude Code starten (NEUE PowerShell oeffnen damit PATH frisch ist):" -ForegroundColor White
Write-Host "       claude" -ForegroundColor Gray
Write-Host '       (Login-Prompt -> Anthropic-Account eingeben)' -ForegroundColor Gray
Write-Host ''
Write-Host "  4.4  Im Claude Code Prompt:" -ForegroundColor White
Write-Host '       Use tv_health_check to confirm TradingView is connected.' -ForegroundColor Gray
Write-Host ''

Write-Host "=== Schritt 6 abgeschlossen ===" -ForegroundColor Cyan
