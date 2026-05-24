<#
.SYNOPSIS
    L2-Isolation Rollback: Stellt System-Zustand vor Schritt 1-4 wieder her.

.DESCRIPTION
    Macht rueckgaengig:
      - NTFS-Deny-ACL auf C:\dev\PHOENIX_REBOOT (via Backup-SDDL oder direkter Remove)
      - NTFS-Allow-ACL auf C:\dev\tradingview-mcp (via Backup-SDDL oder direkter Remove)
      - Firewall-Rules Port 9222 (Allow + Block)
      - OPTIONAL (-RemoveUser): User HAL01-TVResearch loeschen
      - OPTIONAL (-RemoveChromeProfile): User-Data-Dir des dedizierten Chrome-Profils loeschen

.PARAMETER BackupTimestamp
    Zeitstempel des ACL-Backups (Format yyyyMMdd-HHmmss). Wenn angegeben, wird ACL aus
    Backup restored. Wenn weggelassen, wird Deny-Rule explizit per Remove entfernt.

.PARAMETER RemoveUser
    Wenn gesetzt: loescht den Windows-User HAL01-TVResearch (Profil bleibt erhalten).

.PARAMETER RemoveChromeProfile
    Wenn gesetzt: loescht das Chrome-User-Data-Dir im HAL01-TVResearch-Profil.

.NOTES
    Admin-Rechte erforderlich.
    Idempotent: einzelne Schritte koennen schon rueckgaengig sein, das Skript ueberspringt.
    NIEMALS automatisch User loeschen oder Profile zerstoeren ohne -RemoveUser/-RemoveChromeProfile Flags.
#>

[CmdletBinding()]
param(
    [string]$ResearchUser   = 'HAL01-TVResearch',
    [string]$ChimeraRoot    = 'C:\dev\PHOENIX_REBOOT',
    [string]$McpRepoRoot    = 'C:\dev\tradingview-mcp',
    [string]$BackupDir      = 'C:\dev\tradingview-mcp\ops\acl-backups',
    [string]$BackupTimestamp,
    [int]$Port              = 9222,
    [switch]$RemoveUser,
    [switch]$RemoveChromeProfile,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Dieses Skript muss als Administrator ausgefuehrt werden.'
}

$mode = if ($DryRun) { '[DRY-RUN] ' } else { '' }

Write-Host "=== L2-Isolation Rollback ===" -ForegroundColor Cyan
Write-Host "  Research-User:       $ResearchUser" -ForegroundColor Gray
Write-Host "  Chimera-Root:        $ChimeraRoot" -ForegroundColor Gray
Write-Host "  MCP-Repo-Root:       $McpRepoRoot" -ForegroundColor Gray
Write-Host "  Backup-Timestamp:    $(if ($BackupTimestamp) { $BackupTimestamp } else { '(keiner -> Remove-Rule-Modus)' })" -ForegroundColor Gray
Write-Host "  RemoveUser:          $RemoveUser" -ForegroundColor Gray
Write-Host "  RemoveChromeProfile: $RemoveChromeProfile" -ForegroundColor Gray
Write-Host "  DryRun:              $DryRun" -ForegroundColor Gray
Write-Host ''

# Confirm
if (-not $DryRun) {
    Write-Host "ROLLBACK fortsetzen? Dies entfernt alle L2-Isolations-Aenderungen." -ForegroundColor Yellow
    Write-Host "Tippe 'ROLLBACK' (in Grossbuchstaben) zum Bestaetigen:" -ForegroundColor Yellow
    $confirm = Read-Host
    if ($confirm -ne 'ROLLBACK') { Write-Host "Abgebrochen." -ForegroundColor Red; exit 1 }
}

# === 1) NTFS-ACL Restore / Remove ===

Write-Host "${mode}[1/4] NTFS-ACL Rollback..." -ForegroundColor White

function Restore-AclFromBackup {
    param([string]$Path, [string]$SddlFile)
    if (-not (Test-Path $SddlFile)) {
        Write-Host "  [WARN] Backup-Datei nicht gefunden: $SddlFile" -ForegroundColor Yellow
        return $false
    }
    $sddl = Get-Content -Path $SddlFile -Raw
    if ($DryRun) {
        Write-Host "  [DRY-RUN] Would restore ACL on '$Path' from $SddlFile" -ForegroundColor Cyan
        Write-Host "            SDDL preview: $($sddl.Substring(0, [Math]::Min(120, $sddl.Length)))..." -ForegroundColor Gray
    } else {
        $acl = Get-Acl -Path $Path
        $acl.SetSecurityDescriptorSddlForm($sddl.Trim())
        Set-Acl -Path $Path -AclObject $acl
        Write-Host "  [OK] ACL auf '$Path' restored from $SddlFile" -ForegroundColor Green
    }
    return $true
}

function Remove-DenyRule {
    param([string]$Path, [string]$Identity)
    if (-not (Test-Path $Path)) {
        Write-Host "  [SKIP] Pfad nicht vorhanden: $Path" -ForegroundColor Yellow
        return
    }
    $acl = Get-Acl -Path $Path
    $denies = $acl.Access | Where-Object {
        $_.IdentityReference.Value -like "*\$Identity" -and $_.AccessControlType -eq 'Deny'
    }
    if (-not $denies) {
        Write-Host "  [SKIP] Keine Deny-Rules fuer '$Identity' auf '$Path'." -ForegroundColor Yellow
        return
    }
    foreach ($d in $denies) {
        if ($DryRun) {
            Write-Host "  [DRY-RUN] Would remove Deny: $($d.FileSystemRights) on '$Path' for '$($d.IdentityReference)'" -ForegroundColor Cyan
        } else {
            $acl.RemoveAccessRule($d) | Out-Null
        }
    }
    if (-not $DryRun) {
        Set-Acl -Path $Path -AclObject $acl
        Write-Host "  [OK] $($denies.Count) Deny-Rule(s) fuer '$Identity' auf '$Path' entfernt." -ForegroundColor Green
    }
}

function Remove-AllowRule {
    param([string]$Path, [string]$Identity)
    if (-not (Test-Path $Path)) {
        Write-Host "  [SKIP] Pfad nicht vorhanden: $Path" -ForegroundColor Yellow
        return
    }
    $acl = Get-Acl -Path $Path
    $allows = $acl.Access | Where-Object {
        $_.IdentityReference.Value -like "*\$Identity" -and $_.AccessControlType -eq 'Allow'
    }
    if (-not $allows) {
        Write-Host "  [SKIP] Keine explicit Allow-Rules fuer '$Identity' auf '$Path'." -ForegroundColor Yellow
        return
    }
    foreach ($a in $allows) {
        if ($DryRun) {
            Write-Host "  [DRY-RUN] Would remove Allow: $($a.FileSystemRights) on '$Path' for '$($a.IdentityReference)'" -ForegroundColor Cyan
        } else {
            $acl.RemoveAccessRule($a) | Out-Null
        }
    }
    if (-not $DryRun) {
        Set-Acl -Path $Path -AclObject $acl
        Write-Host "  [OK] $($allows.Count) Allow-Rule(s) fuer '$Identity' auf '$Path' entfernt." -ForegroundColor Green
    }
}

if ($BackupTimestamp) {
    $chimeraBackup = Join-Path $BackupDir "chimera-root-acl-$BackupTimestamp.sddl"
    $mcpBackup     = Join-Path $BackupDir "mcp-repo-acl-$BackupTimestamp.sddl"
    Restore-AclFromBackup -Path $ChimeraRoot -SddlFile $chimeraBackup | Out-Null
    if (Test-Path $McpRepoRoot) {
        Restore-AclFromBackup -Path $McpRepoRoot -SddlFile $mcpBackup | Out-Null
    }
} else {
    Write-Host "  Mode: Remove-Rule (kein Backup-Timestamp angegeben)" -ForegroundColor Gray
    Remove-DenyRule -Path $ChimeraRoot -Identity $ResearchUser
    Remove-AllowRule -Path $McpRepoRoot -Identity $ResearchUser
}

# === 2) Firewall-Rules ===

Write-Host ''
Write-Host "${mode}[2/4] Firewall-Rules entfernen..." -ForegroundColor White

foreach ($name in @('TradingView-MCP-CDP-Allow-Loopback','TradingView-MCP-CDP-Block-NonLoopback')) {
    $rule = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
    if ($rule) {
        if ($DryRun) {
            Write-Host "  [DRY-RUN] Would remove firewall rule: $name" -ForegroundColor Cyan
        } else {
            Remove-NetFirewallRule -DisplayName $name
            Write-Host "  [OK] Firewall-Rule '$name' entfernt." -ForegroundColor Green
        }
    } else {
        Write-Host "  [SKIP] Firewall-Rule '$name' nicht vorhanden." -ForegroundColor Yellow
    }
}

# === 3) Chrome User-Data-Dir (optional) ===

Write-Host ''
Write-Host "${mode}[3/4] Chrome User-Data-Dir..." -ForegroundColor White

if ($RemoveChromeProfile) {
    $userProfile = "C:\Users\$ResearchUser\AppData\Local\Chrome-TV-MCP"
    if (Test-Path $userProfile) {
        if ($DryRun) {
            Write-Host "  [DRY-RUN] Would remove: $userProfile" -ForegroundColor Cyan
        } else {
            Remove-Item -Path $userProfile -Recurse -Force
            Write-Host "  [OK] Chrome-Profil entfernt: $userProfile" -ForegroundColor Green
        }
    } else {
        Write-Host "  [SKIP] Kein Chrome-Profil unter $userProfile gefunden." -ForegroundColor Yellow
    }
} else {
    Write-Host "  [SKIP] -RemoveChromeProfile nicht gesetzt. Chrome-Profil bleibt erhalten." -ForegroundColor Gray
}

# === 4) User-Account (optional) ===

Write-Host ''
Write-Host "${mode}[4/4] Windows-User-Account..." -ForegroundColor White

if ($RemoveUser) {
    $existingUser = Get-LocalUser -Name $ResearchUser -ErrorAction SilentlyContinue
    if ($existingUser) {
        if ($DryRun) {
            Write-Host "  [DRY-RUN] Would remove user: $ResearchUser (Profil bleibt physisch erhalten)" -ForegroundColor Cyan
        } else {
            Remove-LocalUser -Name $ResearchUser
            Write-Host "  [OK] User '$ResearchUser' entfernt." -ForegroundColor Green
            Write-Host "       Hinweis: User-Profil unter C:\Users\$ResearchUser bleibt physisch erhalten." -ForegroundColor Gray
            Write-Host "       Manuelles Loeschen via: Remove-Item 'C:\Users\$ResearchUser' -Recurse -Force" -ForegroundColor Gray
        }
    } else {
        Write-Host "  [SKIP] User '$ResearchUser' nicht vorhanden." -ForegroundColor Yellow
    }
} else {
    Write-Host "  [SKIP] -RemoveUser nicht gesetzt. User bleibt bestehen." -ForegroundColor Gray
}

Write-Host ''
Write-Host "=== Rollback abgeschlossen ===" -ForegroundColor Cyan
if (-not $DryRun) {
    Write-Host "Verifikation: ACLs ueberpruefen mit:" -ForegroundColor White
    Write-Host "  Get-Acl '$ChimeraRoot' | Format-List" -ForegroundColor Gray
    Write-Host "  Get-Acl '$McpRepoRoot' | Format-List" -ForegroundColor Gray
    Write-Host "  Get-NetFirewallRule | Where-Object DisplayName -like 'TradingView-MCP*'" -ForegroundColor Gray
}
