import { z } from 'zod';
import { jsonResult } from './_format.js';
import * as core from '../core/health.js';

export function registerHealthTools(server) {
  server.tool('tv_health_check', 'Check CDP connection to TradingView and return current chart state', {}, async () => {
    try { return jsonResult(await core.healthCheck()); }
    catch (err) { return jsonResult({ success: false, error: err.message, hint: 'TradingView is not running with CDP enabled. Use the tv_launch tool to start it automatically.' }, true); }
  });

  server.tool('tv_discover', 'Report which known TradingView API paths are available and their methods', {}, async () => {
    try { return jsonResult(await core.discover()); }
    catch (err) { return jsonResult({ success: false, error: err.message }, true); }
  });

  server.tool('tv_ui_state', 'Get current UI state: which panels are open, what buttons are visible/enabled/disabled', {}, async () => {
    try { return jsonResult(await core.uiState()); }
    catch (err) { return jsonResult({ success: false, error: err.message }, true); }
  });

  // === DISABLED IN L2 READ-ONLY MODE ========================================
  // tv_launch spawns external process (TradingView Desktop with --remote-debugging-port).
  // In L2 setup, Chrome is launched externally and deliberately via
  // ops/04-launch-tv-chrome.ps1 inside the HAL01-TVResearch user profile.
  // Disabling tv_launch prevents the MCP from spawning a second uncontrolled
  // TradingView/Chrome process bypassing the dedicated profile.
}
