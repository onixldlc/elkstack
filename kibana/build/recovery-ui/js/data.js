/* =========================================================================
 * Cluster Recovery Console — DATA HELPERS
 * -------------------------------------------------------------------------
 * The fake cluster generator/tick is gone — node data now comes from
 * /api/nodes (served by main.js, which mirrors logstash's ES disk check).
 * What remains here is pure helpers the UI still uses to summarize state.
 * No DOM, no React.
 * ========================================================================= */

window.RecoveryData = (function () {
  const cfg = window.RecoveryConfig;

  function peakUsage(nodes) {
    return nodes.reduce((m, n) => Math.max(m, n.usedPct), 0);
  }

  function statusOf(pct, thresholdPct) {
    if (pct >= thresholdPct) return "critical";
    if (pct >= cfg.limits.warningPct) return "elevated";
    return "healthy";
  }

  function round1(n) { return Math.round(n * 10) / 10; }

  return { cfg, peakUsage, statusOf, round1 };
})();
