<#
.SYNOPSIS
    L2-Isolation Verifikation: Prueft alle Isolations-Boundaries.

.DESCRIPTION
    Als 'HAL01-TVResearch' ausfuehren. Testet:
      - Chimera-Tree nicht lesbar
      - MCP-Repo lesbar
      - Port 9222 lauscht nur auf 127.0.0.1
      - Firewall-Rules aktiv
      - MCP-Config existiert
      - Node-Prerequisites vorhanden
#>

[CmdletBinding()]
param(
    [string]$ChimeraRoot = 'C:\dev\PHOENIX_REBOOT',
    [string]$McpRepoRoot = 'C:\dev\tradingview-mcp',
    [int]$Port = 9222
)

$ErrorActionPreference = 'Continue'

Write-Host "=== L2-Isolation Verifikation ===" -ForegroundColor Cyan
Write-Host "  Aktueller User: $env:USERNAME" -ForegroundColor Gray
Write-Host ''

$pass = 0
$fail = 0

function Test-Assertion {
    param([string]$Name, [bool]$Condition, [string]$ExpectedDesc)
    if ($Condition) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  [FAIL] $Name  (erwartet: $ExpectedDesc)" -ForegroundColor Red
        $script:fail++
    }
}

# 1. User-Identitaet
Write-Host "[1] User-Identitaet" -ForegroundColor White
Test-Assertion 'Eingeloggt als HAL01-TVResearch' ($env:USERNAME -eq 'HAL01-TVResearch') 'USERNAME = HAL01-TVResearch'

# 2. Chimera-Tree Lockdown
Write-Host ''
Write-Host "[2] Chimera-Tree Lockdown" -ForegroundColor White
$chimeraExists = Test-Path $ChimeraRoot
Test-Assertion 'Chimera-Pfad existiert' $chimeraExists "Test-Path $ChimeraRoot == True"

$chimeraReadDenied = $false
try {
    Get-ChildItem -Path $ChimeraRoot -ErrorAction Stop | Out-Null
    $chimeraReadDenied = $false
} catch {
    $chimeraReadDenied = ($_.Exception.Message -match 'denied|Zugriff verweigert|access')
}
Test-Assertion 'Get-ChildItem auf Chimera-Tree wird verweigert' $chimeraReadDenied 'Access Denied Exception'

# 3. MCP-Repo Access
Write-Host ''
Write-Host "[3] MCP-Repo Access" -ForegroundColor White
$mcpExists = Test-Path $McpRepoRoot
Test-Assertion 'MCP-Repo-Pfad existiert' $mcpExists "Test-Path $McpRepoRoot == True"

$mcpReadable = $false
try {
    $items = @(Get-ChildItem -Path $McpRepoRoot -ErrorAction Stop)
    $mcpReadable = $items.Count -gt 0
} catch { $mcpReadable = $false }
Test-Assertion 'Get-ChildItem auf MCP-Repo erfolgreich' $mcpReadable 'Inhalt lesbar'

# 4. Port-Binding
Write-Host ''
Write-Host "[4] CDP-Port-Binding (Port $Port)" -ForegroundColor White
$listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
$portListening = $null -ne $listening
Test-Assertion "Port $Port lauscht" $portListening "TCP $Port LISTENING"

if ($portListening) {
    $nonLoopback = @($listening | Where-Object {
        $_.LocalAddress -ne '127.0.0.1' -and $_.LocalAddress -ne '::1'
    })
    $loopbackOnly = $nonLoopback.Count -eq 0
    Test-Assertion 'Port lauscht NUR auf Loopback' $loopbackOnly 'Keine 0.0.0.0 / LAN-IPs'
}

# 5. Firewall-Rules
Write-Host ''
Write-Host "[5] Firewall-Rules" -ForegroundColor White
$allowRule = Get-NetFirewallRule -DisplayName 'TradingView-MCP-CDP-Allow-Loopback' -ErrorAction SilentlyContinue
Test-Assertion "Allow-Loopback-Rule existiert" ($null -ne $allowRule) 'Rule TradingView-MCP-CDP-Allow-Loopback aktiv'

$blockRule = Get-NetFirewallRule -DisplayName 'TradingView-MCP-CDP-Block-NonLoopback' -ErrorAction SilentlyContinue
Test-Assertion "Block-NonLoopback-Rule existiert" ($null -ne $blockRule) 'Rule TradingView-MCP-CDP-Block-NonLoopback aktiv'

# 6. MCP-Config
Write-Host ''
Write-Host "[6] MCP-Config im User-Profil" -ForegroundColor White
$mcpConfig = "$env:USERPROFILE\.claude\.mcp.json"
$mcpConfigExists = Test-Path $mcpConfig
Test-Assertion "MCP-Config existiert: $mcpConfig" $mcpConfigExists 'Datei vorhanden'

# 7. Node.js
Write-Host ''
Write-Host "[7] Node.js verfuegbar" -ForegroundColor White
$nodeOk = $false
try {
    $nodeVer = & node --version 2>$null
    $nodeOk = $nodeVer -match '^v(\d+)' -and [int]$Matches[1] -ge 18
} catch {}
Test-Assertion "Node >=18 verfuegbar" $nodeOk 'node --version liefert v18+'

# Zusammenfassung
Write-Host ''
Write-Host "=== Verifikations-Ergebnis ===" -ForegroundColor Cyan
Write-Host "  PASS: $pass" -ForegroundColor Green
Write-Host "  FAIL: $fail" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host ''

if ($fail -eq 0) {
    Write-Host "L2-Isolation vollstaendig verifiziert. Setup einsatzbereit." -ForegroundColor Green
    exit 0
} else {
    Write-Host "L2-Isolation NICHT vollstaendig. Failed Assertions oben pruefen." -ForegroundColor Red
    exit 1
}
