import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';

// === L2 PRAGMATIC TEST MODE ===================================================
// Active tool surface for the L2-isolated TradingView assistant workflow.
//
// KEEP — read + safe navigation/mutation tools:
//   health (tv_launch disabled in tools/health.js)
//   chart (all read + navigation tools)
//   data  (all reads)
//   batch (screenshot action blocked in core/batch.js)
//   drawing, alerts, replay, indicators, watchlist, pane, tab
//   ui    (ui_evaluate disabled in tools/ui.js)
//   pine  (read-only subset — set/compile/save/smart_compile/new/open disabled in tools/pine.js)
//
// HARD-DISABLED (entire module not registered):
//   capture (capture_screenshot — path-traversal vuln, upstream PR unmerged)
//
// HARD-DISABLED (selective inside module):
//   ui_evaluate                 — arbitrary JavaScript in TV page context
//   pine_set_source             — injects arbitrary Pine code into editor
//   pine_compile                — executes injected Pine code
//   pine_smart_compile          — executes injected Pine code
//   pine_save                   — persists scripts to user's TV account
//   pine_new                    — creates new Pine scripts in TV
//   pine_open                   — switches loaded Pine script
//   tv_launch                   — spawns external Chrome/TV (bypasses L2 dedicated profile)
//   chart_set_*  — REMAINS ENABLED (chart navigation is legitimate)
//
// Screenshot action of batch_run also throws (see src/core/batch.js).

import { registerHealthTools }     from './tools/health.js';
import { registerChartTools }      from './tools/chart.js';
import { registerDataTools }       from './tools/data.js';
import { registerBatchTools }      from './tools/batch.js';
import { registerDrawingTools }    from './tools/drawing.js';
import { registerAlertTools }      from './tools/alerts.js';
import { registerReplayTools }     from './tools/replay.js';
import { registerIndicatorTools }  from './tools/indicators.js';
import { registerWatchlistTools }  from './tools/watchlist.js';
import { registerUiTools }         from './tools/ui.js';
import { registerPineTools }       from './tools/pine.js';
import { registerPaneTools }       from './tools/pane.js';
import { registerTabTools }        from './tools/tab.js';

// HARD-DISABLED module:
// import { registerCaptureTools } from './tools/capture.js';

const server = new McpServer(
  {
    name: 'tradingview',
    version: '2.0.0-l2-pragmatic',
    description: 'TradingView MCP — L2 PRAGMATIC TEST MODE. Live chart assistant for manual trading. Arbitrary-JS + Pine-execute + capture disabled.',
  },
  {
    instructions: `TradingView MCP — L2 PRAGMATIC TEST MODE.

This server is the read+navigation tool surface for a manual-trading assistant.
Claude can read chart state, change symbols/timeframes/indicators on user request,
draw levels, manage alerts, navigate panes/tabs, and use Pine read-only validation.

Claude CANNOT:
- execute arbitrary JavaScript in the TradingView page (ui_evaluate is disabled)
- inject + run Pine Script code (pine_set_source / compile / smart_compile / save / new / open are disabled)
- capture screenshots (capture_screenshot disabled pending upstream path-traversal fix)
- spawn external TradingView/Chrome processes (tv_launch disabled — Chrome is launched via L2 ops scripts)

CORE READING (use these first):
- chart_get_state → symbol, timeframe, chart type, indicator list with entity IDs (call once at start)
- quote_get → real-time price snapshot (last, OHLC, volume)
- data_get_study_values → ALL visible indicator values (RSI, MACD, etc.) — pass study_filter if known
- data_get_ohlcv → bars (ALWAYS pass summary=true unless individual bars are needed)
- data_get_pine_lines / labels / tables / boxes → custom Pine indicator drawings (pass study_filter)

NAVIGATION (on explicit user request):
- chart_set_symbol / chart_set_timeframe / chart_set_type
- chart_manage_indicator (add/remove studies — use full names: "Relative Strength Index" not "RSI")
- chart_set_visible_range / chart_scroll_to_date
- pane_set_layout (s, 2h, 2v, 4, 6, 8) / pane_set_symbol / pane_focus
- tab_new / tab_close / tab_switch
- watchlist_add / watchlist_get
- indicator_set_inputs / indicator_toggle_visibility

DRAWINGS + ALERTS:
- draw_shape (horizontal_line, trend_line, rectangle, text) — for marking levels
- draw_list / draw_clear / draw_remove_one
- alert_create / alert_list / alert_delete

REPLAY (for learning / backtesting context):
- replay_start / replay_step / replay_stop / replay_status

PINE (READ-ONLY validation):
- pine_get_source / pine_get_errors / pine_get_console / pine_list_scripts
- pine_analyze (offline static analysis, no compile)
- pine_check (server-side syntax check, no chart inject)

UI (manual interaction layer):
- ui_click / ui_hover / ui_keyboard / ui_type_text / ui_scroll / ui_mouse_click
- ui_open_panel / ui_fullscreen / ui_find_element
- layout_list / layout_switch

WORKFLOW GUIDANCE:
- ALWAYS use summary=true on data_get_ohlcv
- ALWAYS use study_filter on data_get_pine_* tools
- Call chart_get_state ONCE at start, reuse entity IDs
- For Pine Script work, use pine_analyze + pine_check (no live compile available)
- Prefer minimal-disruption mutations: ask user before changing chart state during active trading session`,
  }
);

// === Register active tool groups ==============================================
registerHealthTools(server);
registerChartTools(server);
registerDataTools(server);
registerBatchTools(server);
registerDrawingTools(server);
registerAlertTools(server);
registerReplayTools(server);
registerIndicatorTools(server);
registerWatchlistTools(server);
registerUiTools(server);
registerPineTools(server);
registerPaneTools(server);
registerTabTools(server);

// === DISABLED module ==========================================================
// registerCaptureTools(server);

// Startup notice (stderr so it doesn't interfere with MCP stdio protocol)
process.stderr.write('⚠  tradingview-mcp  |  L2 PRAGMATIC TEST MODE active.\n');
process.stderr.write('   Hard-disabled: ui_evaluate, capture_screenshot, pine_set/compile/save/smart_compile/new/open, tv_launch\n');
process.stderr.write('   Unofficial tool. Not affiliated with TradingView Inc. or Anthropic.\n');
process.stderr.write('   Ensure your usage complies with TradingView\'s Terms of Use.\n\n');

// Start stdio transport
const transport = new StdioServerTransport();
await server.connect(transport);
