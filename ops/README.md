# L2-Isolation Setup — Operator-Anleitung

**Stand:** 2026-05-24  
**Pin-Branch:** `pin/2026-05-24-l2-isolation` @ `4795784a` (upstream `main` HEAD)  
**Ziel:** TradingView-MCP in OS-isoliertem Windows-User-Account, getrennt von SynapseChimera und Trading-Session.

---

## Zweck

Claude bekommt via MCP Live-View auf TradingView-Chart und Indikator-Werte (Variante A: Empfehlungs-Modus). Du klickst weiterhin manuell in TopStepX. Keine Order-Automation, kein Broker-API-Zugriff, keine Chimera-Integration.

## Was bereits automatisch gemacht wurde

| Schritt | Status | Artefakt |
|---|---|---|
| Repo Fork → `Polymatters/tradingview-mcp` | ✓ | `https://github.com/Polymatters/tradingview-mcp` |
| Clone → `C:\dev\tradingview-mcp` | ✓ | Lokal vorhanden |
| Pin-Branch `pin/2026-05-24-l2-isolation` auf `4795784a` | ✓ | Lokaler Branch |
| `npm ci` + `npm audit fix` | ✓ | 0 Vulnerabilities |
| Source-Code-Review (kein eval, keine externen URLs, child_process nur hard-coded) | ✓ | Manuell verifiziert |
| Screenshot-Tools deaktiviert (path-traversal Mitigation) | ✓ | Commit `28d3e5b` |
| Admin-Skripte + MCP-Config-Template + Verifikator | ✓ | Dieser `ops/` Ordner |

## Was du jetzt manuell tun musst — in genau dieser Reihenfolge

### 0. Vorbereitung
- Sicherstellen, dass du **physisch an der Workstation** bist (Skripte erfordern interaktiven Login)
- Quantower / TopStepX **schließen** falls aktiv
- Eine Telegram/Phone-Erinnerung setzen: "Setup-Session — kein Trading parallel"

### 1. Research-User anlegen (~5 min)
**Als HAL01 (Admin):** PowerShell als Administrator öffnen, dann:
```powershell
cd C:\dev\tradingview-mcp\ops
.\01-create-research-user.ps1
```
Du wirst nach einem Passwort für `HAL01-TVResearch` gefragt (Secure-String, nicht sichtbar).

**Verifikation:**
- `Get-LocalUser HAL01-TVResearch` → muss User zeigen
- `Get-LocalGroupMember -Group Administrators` → `HAL01-TVResearch` darf **NICHT** drin sein

### 2. NTFS-Lockdown auf Chimera-Tree (~2 min)
**Als HAL01 (Admin):** im selben Admin-PowerShell:
```powershell
.\02-lockdown-chimera-tree.ps1
```
Setzt Deny-FullControl auf `C:\dev\PHOENIX_REBOOT` für `HAL01-TVResearch` und Allow-Modify auf `C:\dev\tradingview-mcp`.

### 3. Firewall-Rules für Port 9222 (~1 min)
**Als HAL01 (Admin):** im selben Admin-PowerShell:
```powershell
.\03-firewall-port-9222.ps1
```
Allow-Loopback-Rule + Block-NonLoopback-Rule. Idempotent.

### 4. User-Wechsel zu HAL01-TVResearch
- `Win+L` (sperren) → User-Auswahl → **HAL01-TVResearch** einloggen
- Ab hier **alle weiteren Schritte als `HAL01-TVResearch`**

### 5. MCP-Config installieren (~1 min)
**Als HAL01-TVResearch:** PowerShell öffnen, dann:
```powershell
$claudeDir = "$env:USERPROFILE\.claude"
if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir | Out-Null }
Copy-Item -Path 'C:\dev\tradingview-mcp\ops\mcp-config-template.json' -Destination "$claudeDir\.mcp.json" -Force
Get-Content "$claudeDir\.mcp.json"
```

### 6. Chrome mit CDP starten (~1 min)
**Als HAL01-TVResearch:**
```powershell
cd C:\dev\tradingview-mcp\ops
.\04-launch-tv-chrome.ps1
```
Chrome öffnet sich im dedizierten Profil mit `--remote-debugging-port=9222 --remote-debugging-address=127.0.0.1` und navigiert direkt zu TradingView.

**Im Chrome-Fenster:** TradingView einloggen (dein Pro-Account).

**WICHTIG — Boundaries beim Login:**
- ✅ TradingView: OK
- ✅ EzPz Trading: OK (im selben Profil)
- ✅ AiPe: OK (im selben Profil)
- ❌ TopStepX: **NICHT einloggen** in diesem Chrome-Profil
- ❌ GitHub mit Chimera-Org: **NICHT einloggen**
- ❌ Quantower-Web: **NICHT öffnen**
- ❌ Broker- oder Bank-Accounts: **NICHT öffnen**

### 7. L2-Verifikation (~30 sec)
**Als HAL01-TVResearch:** PowerShell:
```powershell
cd C:\dev\tradingview-mcp\ops
.\05-verify-l2-isolation.ps1
```
Muss "L2-Isolation vollständig verifiziert" zeigen. Wenn irgendein Test FAIL: nicht weitermachen, an Claude zurückreporten.

### 8. Claude Code starten + MCP-Verbindung testen (~2 min)
**Als HAL01-TVResearch:** Claude Code im User-Profil starten. Im Claude-Prompt:
```
Use tv_health_check to confirm TradingView is connected.
```
Erwartetes Ergebnis: `cdp_connected: true`, Target-Info zur TradingView-Seite.

Falls Verbindung scheitert:
- TradingView-Tab im Chrome aktiv?
- Port 9222 lauscht? (`Get-NetTCPConnection -LocalPort 9222 -State Listen`)
- `tv_health_check`-Output zurück an Claude

### 9. Smoke-Test
```
tv_status
tv_quote
chart_get_state
data_get_study_values
```
Output dokumentieren. Bei bekannten Bugs (z.B. `evaluate is not defined`, `getChartApi is not defined`) — diese Tools fallen aus dem produktiven Workflow.

### 10. Trading-Watchlist konfigurieren
Im TradingView-Chart (innerhalb des dedizierten Chrome-Profils): Watchlist anlegen mit folgender Multi-Asset-Korrelation für MNQ-Trading.

**Primärinstrument (Trading-Target):**
| Symbol | TradingView-Ticker | Bemerkung |
|---|---|---|
| MNQ | `CME_MINI:MNQ1!` | Continuous Front-Month (auto-rolls) |
| MNQ (spezifisch) | `CME_MINI:MNQM2026` | Juni 2026 Kontrakt (aktueller Front-Month, Roll Mitte Juni) |

**Korrelations-Layer (Read-Only Context):**
| Symbol | TradingView-Ticker | Funktion |
|---|---|---|
| NDX | `NASDAQ:NDX` | NASDAQ-100 Cash Index — direkter Underlying-Bezug zu MNQ |
| QQQ | `NASDAQ:QQQ` | NASDAQ-100 ETF — Liquidität/Options-Flow |
| ES | `CME_MINI:ES1!` | S&P 500 Futures — breite Markt-Beta |
| SPY | `AMEX:SPY` | S&P 500 ETF — Equity-Cross-Reference |
| VIX | `CBOE:VIX` oder `TVC:VIX` | Volatility Regime |
| MAG7 | `NASDAQ:AAPL`, `NASDAQ:MSFT`, `NASDAQ:GOOGL`, `NASDAQ:AMZN`, `NASDAQ:NVDA`, `NASDAQ:META`, `NASDAQ:TSLA` | Einzeln — NDX-Komponenten-Treiber |

**Leveraged Risk-Proxies (Signal-Indikatoren, NICHT zum Halten):**
| Symbol | TradingView-Ticker | Funktion |
|---|---|---|
| UVXY | `AMEX:UVXY` | 1.5x VIX Short-Term — schneller Spike-Detector bei Vol-Expansion |
| VXX | `BATS:VXX` | VIX Short-Term ETN — Volatility-Term-Structure-Proxy |
| SQQQ | `NASDAQ:SQQQ` | -3x QQQ — verstärkt sichtbarer Bearish-Move für MNQ-Short-Signal |
| TQQQ | `NASDAQ:TQQQ` | +3x QQQ — verstärkt sichtbarer Bullish-Move für MNQ-Long-Signal |
| SOXL | `AMEX:SOXL` | 3x long Semis — NVDA/AMD-Lead-Bestätigung |
| SOXS | `AMEX:SOXS` | 3x short Semis — Tech-Risk-Off-Detector |
| SPXU / SPXL | `AMEX:SPXU` / `AMEX:SPXL` | -3x / +3x SPY — breit-Markt Direction-Confirm |

**Hinweis:** Leveraged ETFs leiden an Volatility-Drag bei Hold — nur als **Intraday-Korrelations-/Signal-Indikator** sinnvoll, niemals als Position. Ihre Bewegungen sind oft schneller sichtbar als die unterliegenden Indices, was sie zu guten Frühwarn-Indikatoren macht.

**Empfohlenes Pane-Layout (via `pane_set_layout`):**
- **4-Pane (2x2):** MNQ | ES | QQQ | VIX  → Hauptkorrelation auf einen Blick
- **6-Pane:** + NDX + ein MAG7-Schwergewicht (NVDA für Tech-Lead)
- Mehr Panes = mehr Cognitive Load, weniger Detail pro Chart

**Watchlist-Sidebar (zusätzlich zu Panes):**
- Alle 6 MAG7 + VIX + QQQ + SPY → Live %-Change-Sicht ohne Pane zu wechseln
- Watchlist erscheint als Spalte rechts im TradingView-UI

### 11. Live-Assistance-Smoke-Test (mit Claude)
Nach Watchlist-Setup:
```
chart_set_symbol("CME_MINI:MNQ1!")
chart_get_state
data_get_study_values
quote_get
```
Dann frag Claude z.B.:
- "Lies QQQ und ES Quote, sag mir wo MNQ relativ zur Korrelation steht"
- "Wie sind die VIX und QQQ Werte gerade — wie ist das Vol-Regime für MNQ?"

---

## Operations-Regeln (Daily Use)

### Niemals parallel:
- ❌ MCP-Session aktiv **AND** Quantower-Live-Trade-Session aktiv
- ❌ MCP-Session aktiv **AND** TopStepX-Order-Window offen

### Workflow während Trading-Window:
1. **HAL01-TVResearch** Session: TradingView + Claude + MCP (Live-View)
2. **HAL01** Session: TopStepX (Manual-Click)
3. Wechseln via `Win+L` → Fast-User-Switching
4. Claude gibt Befehl im Research-Session → du wechselst → klickst im Trading-Session → wechselst zurück

### Session-Ende:
- Chrome im Research-User schließen
- Optional: Research-User komplett ausloggen
- Falls Chrome-Hang: `taskkill /F /IM chrome.exe` im Research-User-PowerShell

---

## Bekannte Tool-Bugs (NICHT verwenden)

| Tool | Bug | Workaround |
|---|---|---|
| `capture_screenshot` | Path-traversal Vuln + hängt auf MSIX | **Deaktiviert** in pin-branch |
| `chart_get_visible_range` | `evaluate is not defined` | Nicht nutzen |
| `chart_scroll_to_date` | `evaluate is not defined` | Nicht nutzen |
| `symbol_info` | `evaluate is not defined` | Nutze `quote_get` stattdessen |
| `quote_get(symbol=...)` | Ignoriert Symbol-Parameter, liest current chart | Symbol vorher per `chart_set_symbol` setzen |
| `draw_list / draw_clear / draw_remove_one` | `getChartApi is not defined` | Nicht nutzen |
| `alert_create` | `price_set: false` (dom_fallback) | TradingView-Alerts manuell setzen |

## Funktionsfähige Kern-Tools für Live-Assistenz

| Tool | Zweck |
|---|---|
| `tv_health_check` | Verbindungs-Check |
| `tv_status` | TradingView-Status |
| `quote_get` | Live-Preis (current symbol) |
| `chart_get_state` | Symbol, Timeframe, Indikator-Liste mit IDs |
| `data_get_study_values` | Alle sichtbaren Indikator-Werte (RSI, MACD, etc.) |
| `data_get_ohlcv` (mit `summary=true`) | Bar-Daten |
| `data_get_pine_lines/labels/tables/boxes` | Custom-Indikator-Outputs |
| `chart_set_symbol`, `chart_set_timeframe` | Chart-Navigation |
| `pine_set_source`, `pine_smart_compile`, `pine_get_errors` | Pine-Dev-Loop |

---

## Notfall: Komplettes Teardown / Rollback

**Dediziertes Rollback-Skript:** `ops\99-rollback-l2-isolation.ps1`

### Standard-Rollback (ACL + Firewall, User + Profil bleiben)
```powershell
# Als Admin:
cd C:\dev\tradingview-mcp\ops
.\99-rollback-l2-isolation.ps1
# Bestätigung 'ROLLBACK' eingeben
```

### Rollback mit präzisem ACL-Restore aus Backup
Wenn 02-Skript ausgeführt wurde, liegt ACL-Backup unter `ops\acl-backups\chimera-root-acl-<timestamp>.sddl`. Restore:
```powershell
.\99-rollback-l2-isolation.ps1 -BackupTimestamp 20260524-143012
```

### Komplett-Teardown (inkl. User + Chrome-Profil)
```powershell
.\99-rollback-l2-isolation.ps1 -RemoveUser -RemoveChromeProfile
# Bestätigung 'ROLLBACK' eingeben
# Hinweis: User-Profil unter C:\Users\HAL01-TVResearch\ bleibt physisch erhalten (manuell löschen)
```

### Dry-Run (zeigt was passieren würde, ohne Änderung)
```powershell
.\99-rollback-l2-isolation.ps1 -DryRun
.\99-rollback-l2-isolation.ps1 -DryRun -BackupTimestamp 20260524-143012 -RemoveUser -RemoveChromeProfile
```

**Was Rollback macht:**
1. NTFS-ACL auf `C:\dev\PHOENIX_REBOOT` und `C:\dev\tradingview-mcp` restored (aus Backup) oder Deny/Allow-Rules entfernt
2. Firewall-Rules `TradingView-MCP-CDP-Allow-Loopback` + `TradingView-MCP-CDP-Block-NonLoopback` entfernt
3. (Optional) Chrome User-Data-Dir entfernt
4. (Optional) Windows-User-Account entfernt

---

## SynapseChimera-Schutz — was diese Isolation garantiert

- **Pfad:** `C:\dev\tradingview-mcp` ist außerhalb `C:\dev\PHOENIX_REBOOT\SynapseChimera`
- **NTFS:** Deny-Read auf Chimera-Tree für `HAL01-TVResearch`
- **OS-User-Grenze:** MCP-Prozess läuft mit User-Berechtigungen von `HAL01-TVResearch`, nicht `HAL01`
- **Network:** CDP-Port nur auf 127.0.0.1, Firewall blockt LAN/Internet
- **Chrome-Profil:** Isoliertes user-data-dir, keine Vermischung mit Standard-Browsing
- **MCP-Config:** Nur im `HAL01-TVResearch` User-Profil, lädt nicht in `HAL01`-Claude-Sessions
- **Stack-Disjunkt:** Node.js (MCP) vs. .NET 8 (Chimera), keine Build-Dependency möglich

---

## Pin-Maintenance

Bei späteren Upstream-Updates (nach erfolgreichem Testen):
```powershell
cd C:\dev\tradingview-mcp
git fetch upstream
git log --oneline upstream/main ^pin/2026-05-24-l2-isolation
# Sichten welche Commits dazu kamen — niemals blind mergen
# Insbesondere: path-traversal-fix-PR im upstream merged? Wenn ja, neuer Pin sinnvoll.
```

---

## Kontakt-Reset

Wenn Setup hängt oder Verifikation scheitert:
1. Output von `.\05-verify-l2-isolation.ps1` zurück an Claude
2. Output von `tv_health_check` zurück an Claude
3. Keine eigenen Workarounds ohne Rücksprache
