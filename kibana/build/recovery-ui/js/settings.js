/* =========================================================================
 * Cluster Recovery Console — RUNTIME SETTINGS
 * -------------------------------------------------------------------------
 * Most values here are hardcoded by design — they are operational defaults
 * (warning thresholds, poll cadence) that don't make sense to expose as
 * deploy-time knobs. The exceptions:
 *   - retentionMonths: 3  (env: RETENTION_MONTHS)
 *   - clusterName:     filled in at runtime from /api/nodes (ES reports it)
 *
 * Actions live in js/actions.js so this file stays "settings only".
 * ========================================================================= */

window.RecoveryConfig = Object.assign(window.RecoveryConfig || {}, {
  /* Identity — populated from ES via /api/nodes; "—" until first poll lands. */
  clusterName: "—",

  /* Page load time as a stand-in for incident start (good enough — the
   * recovery page is only shown after kibana exits). */
  incidentStartedAt: Date.now(),

  /* Admin contact — placeholder copy; not env-driven on purpose. */
  adminContact: {
    configured: false,
    name:  "your Elastic administrator",
    phone: "",
    slack: "",
    note:  ""
  },

  /* Capacity limits — hardcoded; tune in code if you ever need to. */
  limits: {
    hardLimitPct:  85,
    tempLimitPct:  90,
    resetBelowPct: 75,
    warningPct:    70
  },

  /* How often /api/nodes is polled. Hardcoded so a misconfigured env can't
   * accidentally hammer ES from the recovery page. */
  tickMs: 10000,

  /* Data retention used by the purge action — env-driven. */
  retentionMonths: Number("3")
});
