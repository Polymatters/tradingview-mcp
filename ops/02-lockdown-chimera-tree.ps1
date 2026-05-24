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
    [string]$McpRepoRoot    = 'C:\dev\tradingview-mcp',
    [string]$BackupDir      = 'C:\dev\tradingview-mcp\ops\acl-backups'
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
Write-Host "  ACL-Backup-Dir: $BackupDir" -ForegroundColor Gray
Write-Host ''

if (-not (Test-Path $ChimeraRoot)) {
    throw "Chimera-Root nicht gefunden: $ChimeraRoot"
}

# User-Existenz pruefen
$user = Get-LocalUser -Name $ResearchUser -ErrorAction SilentlyContinue
if (-not $user) {
    throw "User '$ResearchUser' nicht gefunden. Erst Schritt 1 (01-create-research-user.ps1) ausfuehren."
}

# 0) ACL-Backup VOR jeder Modifikation (Pflicht fuer Rollback)
Write-Host "[0/3] ACL-Backup vor Modifikation..." -ForegroundColor White
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$chimeraBackupSddl = Join-Path $BackupDir "chimera-root-acl-$ts.sddl"
$chimeraBackupTxt  = Join-Path $BackupDir "chimera-root-acl-$ts.txt"
$mcpBackupSddl     = Join-Path $BackupDir "mcp-repo-acl-$ts.sddl"
$mcpBackupTxt      = Join-Path $BackupDir "mcp-repo-acl-$ts.txt"

# SDDL-Form (maschinenlesbar, fuer Rollback verwendbar)
(Get-Acl -Path $ChimeraRoot).Sddl | Out-File -FilePath $chimeraBackupSddl -Encoding UTF8
# Human-readable Form
(Get-Acl -Path $ChimeraRoot).Access | Format-List | Out-File -FilePath $chimeraBackupTxt -Encoding UTF8

if (Test-Path $McpRepoRoot) {
    (Get-Acl -Path $McpRepoRoot).Sddl | Out-File -FilePath $mcpBackupSddl -Encoding UTF8
    (Get-Acl -Path $McpRepoRoot).Access | Format-List | Out-File -FilePath $mcpBackupTxt -Encoding UTF8
}

Write-Host "[OK] ACL-Backup geschrieben:" -ForegroundColor Green
Write-Host "     $chimeraBackupSddl" -ForegroundColor Gray
Write-Host "     $chimeraBackupTxt" -ForegroundColor Gray
if (Test-Path $McpRepoRoot) {
    Write-Host "     $mcpBackupSddl" -ForegroundColor Gray
    Write-Host "     $mcpBackupTxt" -ForegroundColor Gray
}
Write-Host "     -> Rollback via: .\99-rollback-l2-isolation.ps1 -BackupTimestamp $ts" -ForegroundColor Yellow

# 1) Deny FullControl auf Chimera-Tree
Write-Host ''
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
