/* =========================================================================
 * Cluster Recovery Console — ACTIONS
 * -------------------------------------------------------------------------
 * Static action definitions for the recovery buttons. Settings (limits,
 * contact, etc.) live in js/settings.js and are injected from env vars.
 *
 * Add a 4th, 5th, ... button later by appending an entry here and adding a
 * matching handler id in components/App.jsx (EFFECTS map).
 *   kind:    "primary" (blue) | "danger" (red)
 *   confirm: { type: "simple" } | { type: "type", phrase: "EXACT PHRASE" }
 * ========================================================================= */

window.RecoveryConfig = Object.assign(window.RecoveryConfig || {}, {
  actions: [
    {
      id: "raise-threshold",
      label: "Raise disk threshold to 90%",
      cta: "Raise limit",
      icon: "▲",
      kind: "primary",
      summary:
        "Temporarily lift the hard limit from 85% to 90% so Logstash and Kibana can resume. " +
        "This auto-resets back to 85% once peak node usage drops below 75%.",
      confirm: { type: "simple" }
    },
    {
      id: "kill-kibana-container",
      label: "Kill Kibana container",
      cta: "Kill container",
      icon: "⟳",
      kind: "primary",
      summary:
        "Terminate this container so the orchestrator restarts it. If kibana is healthy after " +
        "restart you'll be back on the dashboard; if not, this recovery page reappears.",
      confirm: { type: "simple" }
    },
    {
      id: "purge-old-data",
      label: "Delete data older than 3 months",
      cta: "Delete data",
      icon: "⚠",
      kind: "danger",
      summary:
        "PERMANENTLY deletes every index older than the 3-month retention window across all " +
        "nodes to free disk space immediately. This cannot be undone.",
      dangerNote:
        "This destroys data. Make sure snapshots / backups exist and confirm with your Elastic " +
        "administrator BEFORE running this. Everything within the last 3 months is preserved.",
      confirm: { type: "type", phrase: "DELETE OLD DATA" }
    }
  ]
});
