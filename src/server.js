import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';

// === L2 READ-ONLY MODE — KEEP (read-only tool categories) =====================
import { registerHealthTools } from './tools/health.js';   // tv_launch wird intern disabled
import { registerChartTools }  from './tools/chart.js';    // mutating tools intern disabled
import { registerDataTools }   from './tools/data.js';     // alle reads
import { registerBatchTools }  from './tools/batch.js';    // screenshot-action bereits geblockt

// === L2 READ-ONLY MODE — DISABLED (mutating / arbitrary-execution) ============
// Capture: Path-traversal Vuln im Upstream-PR (#2026-05-22) unmerged
// import { registerCaptureTools }    from './tools/capture.js';
// UI:      enthält ui_evaluate (beliebiges JavaScript in TV-Page) + alle ui_click/keyboard/mouse
// import { registerUiTools }         from './tools/ui.js';
// Pine:    Pine-Editing/Compile/Execute mutiert Chart-Pine-State
// import { registerPineTools }       from './tools/pine.js';
// Drawing: draw_shape/clear/remove mutieren Chart-Drawings
// import { registerDrawingTools }    from './tools/drawing.js';
// Alerts:  alert_create/delete mutieren TradingView-Alert-Konfig
// import { registerAlertTools }      from './tools/alerts.js';
// Replay:  replay_start/step/trade/stop mutieren Chart-Replay-State
// import { registerReplayTools }     from './tools/replay.js';
// Indicators: indicator_set_inputs / toggle_visibility mutieren Chart-Studies
// import { registerIndicatorTools }  from './tools/indicators.js';
// Watchlist: watchlist_add mutiert TV-Watchlist
// import { registerWatchlistTools }  from './tools/watchlist.js';
// Pane:    pane_set_layout/focus/symbol mutieren Layout
// import { registerPaneTools }       from './tools/pane.js';
// Tab:     tab_new/close/switch mutieren Tab-State
// import { registerTabTools }        from './tools/tab.js';

const server = new McpServer(
  {
    name: 'tradingview',
    version: '2.0.0-l2-readonly',
    description: 'TradingView MCP in L2 READ-ONLY MODE — chart analysis only. No mutation, no Pine execution, no arbitrary JS.',
  },
  {
    instructions: `TradingView MCP — L2 READ-ONLY MODE.

Only read-only tools are exposed. Mutation, Pine execution, arbitrary JavaScript (ui_evaluate),
drawings, alerts, replay, pane/tab/watchlist mutation, and screenshot capture are all DISABLED.

AVAILABLE TOOLS:

Health / connection:
- tv_health_check → confirm CDP connection
- tv_discover → list available TradingView API paths
- tv_ui_state → read which panels/buttons are visible (no interaction)

Chart state (read-only):
- chart_get_state → symbol, timeframe, chart type, indicator list with entity IDs
- chart_get_visible_range → current date range and bar range
- symbol_info → current symbol metadata
- symbol_search → search symbols by query

Live data (read-only):
- quote_get → real-time price snapshot (last, OHLC, volume)
- depth_get → order book depth snapshot
- data_get_ohlcv → price bars (ALWAYS use summary=true unless explicit bar-detail need)
- data_get_study_values → current numeric values of ALL visible indicators
- data_get_indicator → single indicator current value
- data_get_strategy_results / data_get_trades / data_get_equity → strategy tester reads
- data_get_pine_lines / labels / tables / boxes → custom Pine indicator drawings (read-only)

Batch reads:
- batch_run → multi-symbol read loop (screenshot action is blocked, get_ohlcv works)

DISABLED IN L2 (will not appear in tool list):
- ui_*  (incl. ui_evaluate — arbitrary JS in TV page)
- pine_* (Pine editing, compile, execute)
- draw_* (chart drawing mutations)
- alert_* (alert creation/deletion)
- replay_* (chart replay state mutations)
- indicator_set_inputs / indicator_toggle_visibility (study mutations)
- chart_set_* (symbol/timeframe/type changes)
- chart_manage_indicator / chart_scroll_to_date / chart_set_visible_range
- watchlist_add (only watchlist_get would be read-only but watchlist module disabled)
- pane_set_* / pane_focus
- tab_new / tab_close / tab_switch
- tv_launch (Chrome is launched externally via L2 ops scripts)
- capture_screenshot (path-traversal mitigation)

WORKFLOW: navigate symbols / change timeframes / add indicators MANUALLY in the TradingView UI.
Claude reads the resulting state via the tools above. Claude never mutates the chart.

CONTEXT MANAGEMENT:
- ALWAYS use summary=true on data_get_ohlcv
- ALWAYS use study_filter on data_get_pine_* tools
- Call chart_get_state ONCE at start, reuse entity IDs`,
  }
);

// === L2 READ-ONLY MODE — register only read-only tool groups ==================
registerHealthTools(server);   // mutating tv_launch internally disabled in tools/health.js
registerChartTools(server);    // mutating chart_set_* internally disabled in tools/chart.js
registerDataTools(server);     // all data reads
registerBatchTools(server);    // batch_run, screenshot action throws

// === DISABLED (see import comments above) =====================================
// registerCaptureTools(server);
// registerUiTools(server);
// registerPineTools(server);
// registerDrawingTools(server);
// registerAlertTools(server);
// registerReplayTools(server);
// registerIndicatorTools(server);
// registerWatchlistTools(server);
// registerPaneTools(server);
// registerTabTools(server);

// Startup notice (stderr so it doesn't interfere with MCP stdio protocol)
process.stderr.write('⚠  tradingview-mcp  |  L2 READ-ONLY MODE active.\n');
process.stderr.write('   Mutating tools disabled: ui, pine, drawing, alerts, replay, indicators, watchlist, pane, tab, capture, tv_launch, chart_set_*\n');
process.stderr.write('   Unofficial tool. Not affiliated with TradingView Inc. or Anthropic.\n');
process.stderr.write('   Ensure your usage complies with TradingView\'s Terms of Use.\n\n');

// Start stdio transport
const transport = new StdioServerTransport();
await server.connect(transport);
