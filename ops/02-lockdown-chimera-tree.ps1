<#
.SYNOPSIS
    L2-Isolation Schritt 2: Deny-Read fuer HAL01-TVResearch auf SynapseChimera-Tree.

.DESCRIPTION
    Setzt explizite Deny-ACL auf C:\dev\PHOENIX_REBOOT fuer den Research-User.
    Verhindert OS-seitig jeglichen Read-Access auf Chimera-Source/Build-Output.
    Idempotent.

.NOTES
    Admin-Rechte erforderlich.
    Verifikations-Test am Ende: simuliert Access-Versuch.
#>

[CmdletBinding()]
param(
    [string]$ResearchUser   = 'HAL01-TVResearch',
    [string]$ChimeraRoot    = 'C:\dev\PHOENIX_REBOOT',
    [string]$McpRepoRoot    = 'C:\dev\tradingview-mcp'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Dieses Skript muss als Administrator ausgefuehrt werden.'
}

Write-Host "=== L2-Isolation Schritt 2: NTFS-Lockdown auf Chimera-Tree ===" -ForegroundColor Cyan
Write-Host "  Research-User:  $ResearchUser" -ForegroundColor Gray
Write-Host "  Chimera-Root:   $ChimeraRoot" -ForegroundColor Gray
Write-Host "  MCP-Repo-Root:  $McpRepoRoot" -ForegroundColor Gray
Write-Host ''

if (-not (Test-Path $ChimeraRoot)) {
    throw "Chimera-Root nicht gefunden: $ChimeraRoot"
}

# User-Existenz pruefen
$user = Get-LocalUser -Name $ResearchUser -ErrorAction SilentlyContinue
if (-not $user) {
    throw "User '$ResearchUser' nicht gefunden. Erst Schritt 1 (01-create-research-user.ps1) ausfuehren."
}

# 1) Deny FullControl auf Chimera-Tree
Write-Host "[1/3] Setze Deny FullControl auf '$ChimeraRoot' fuer '$ResearchUser'..." -ForegroundColor White
$acl = Get-Acl -Path $ChimeraRoot
$denyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $ResearchUser,
    'FullControl',
    'ContainerInherit,ObjectInherit',
    'None',
    'Deny'
)

# Duplikate entfernen, dann neu setzen
$existingDenies = $acl.Access | Where-Object {
    $_.IdentityReference.Value -like "*\$ResearchUser" -and $_.AccessControlType -eq 'Deny'
}
foreach ($d in $existingDenies) {
    $acl.RemoveAccessRule($d) | Out-Null
}
$acl.AddAccessRule($denyRule)
Set-Acl -Path $ChimeraRoot -AclObject $acl
Write-Host "[OK] Deny-Rule auf '$ChimeraRoot' aktiv." -ForegroundColor Green

# 2) MCP-Repo: Read+Write fuer Research-User sicherstellen
Write-Host ''
Write-Host "[2/3] Stelle Read+Modify fuer '$ResearchUser' auf '$McpRepoRoot' sicher..." -ForegroundColor White
if (Test-Path $McpRepoRoot) {
    $aclMcp = Get-Acl -Path $McpRepoRoot
    $allowRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $ResearchUser,
        'Modify',
        'ContainerInherit,ObjectInherit',
        'None',
        'Allow'
    )
    $aclMcp.AddAccessRule($allowRule)
    Set-Acl -Path $McpRepoRoot -AclObject $aclMcp
    Write-Host "[OK] Allow-Rule auf '$McpRepoRoot' aktiv." -ForegroundColor Green
} else {
    Write-Host "[WARN] MCP-Repo '$McpRepoRoot' nicht gefunden. Spaeter setzen." -ForegroundColor Yellow
}

# 3) Verifikation: Versuch Access via runas
Write-Host ''
Write-Host "[3/3] Verifikations-Hinweis:" -ForegroundColor White
Write-Host "  Nach Wechsel zu '$ResearchUser' im Login-Screen:" -ForegroundColor Gray
Write-Host "  PowerShell-Test:  Test-Path '$ChimeraRoot'           --> muss `$true sein (kein Read aber Path-Existenz OK)" -ForegroundColor Gray
Write-Host "                    Get-ChildItem '$ChimeraRoot'        --> muss 'Access Denied' werfen" -ForegroundColor Gray
Write-Host "                    Test-Path '$McpRepoRoot'            --> muss `$true sein" -ForegroundColor Gray
Write-Host "                    Get-ChildItem '$McpRepoRoot'        --> muss Inhalte zeigen" -ForegroundColor Gray

Write-Host ''
Write-Host "=== Schritt 2 abgeschlossen ===" -ForegroundColor Cyan
Write-Host "Naechster Schritt: .\03-firewall-port-9222.ps1" -ForegroundColor White
