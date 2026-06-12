/* App.jsx — state, simulation ticks, theme persistence, threshold auto-reset,
 * and the EFFECTS map that turns each config action into a real change. */
const { useState: useStateApp, useEffect: useEffectApp, useRef, useCallback } = React;

const THEME_KEY = "recovery-console-theme";

function useTheme() {
  const [theme, setTheme] = useStateApp(() => {
    try { return localStorage.getItem(THEME_KEY) || "dark"; } catch (e) { return "dark"; }
  });
  useEffectApp(() => {
    document.documentElement.setAttribute("data-theme", theme);
    try { localStorage.setItem(THEME_KEY, theme); } catch (e) {}
  }, [theme]);
  return [theme, setTheme];
}

let TOAST_SEQ = 0;

function App() {
  const cfg = window.RecoveryConfig;
  const D = window.RecoveryData;
  const L = cfg.limits;

  const [theme, setTheme] = useTheme();
  const [nodes, setNodes] = useStateApp([]);
  const [clusterName, setClusterName] = useStateApp(clusterName);
  const [threshold, setThreshold] = useStateApp(L.hardLimitPct);
  const [tempActive, setTempActive] = useStateApp(false);
  const [kibana, setKibana] = useStateApp("offline");
  const [toasts, setToasts] = useStateApp([]);

  // Measure the right column so the node list can match the tallest column.
  const rightRef = useRef(null);
  const [colHeight, setColHeight] = useStateApp(0);
  useEffectApp(() => {
    const el = rightRef.current;
    if (!el || typeof ResizeObserver === "undefined") return;
    const update = () => {
      const wide = window.matchMedia("(min-width: 941px)").matches;
      setColHeight(wide ? el.offsetHeight : 0);
    };
    const ro = new ResizeObserver(update);
    ro.observe(el);
    window.addEventListener("resize", update);
    update();
    return () => { ro.disconnect(); window.removeEventListener("resize", update); };
  }, []);

  // refs so the interval always sees fresh values without re-subscribing
  const thRef = useRef(threshold); thRef.current = threshold;

  const pushToast = useCallback((t) => {
    const id = ++TOAST_SEQ;
    setToasts((cur) => [...cur, Object.assign({ id }, t)]);
    setTimeout(() => setToasts((cur) => cur.filter((x) => x.id !== id)), t.ttl || 5200);
  }, []);
  const dismissToast = useCallback((id) => setToasts((cur) => cur.filter((x) => x.id !== id)), []);

  const peak = D.peakUsage(nodes);
  const logstashRunning = peak < threshold;
  const level = !logstashRunning ? "critical" : (peak >= L.warningPct ? "elevated" : "healthy");

  /* ---- Live data: poll /api/nodes (served by main.js, backed by ES) ---- */
  useEffectApp(() => {
    let alive = true;
    const load = () =>
      fetch("/api/nodes")
        .then((r) => r.ok ? r.json() : Promise.reject(r))
        .then((d) => {
          if (!alive) return;
          if (Array.isArray(d.nodes)) setNodes(d.nodes);
          if (d.clusterName) setClusterName(d.clusterName);
        })
        .catch(() => { /* keep last good data; the UI shows what it has */ });
    load();
    const t = setInterval(load, cfg.tickMs);
    return () => { alive = false; clearInterval(t); };
  }, []);

  /* =====================================================================
   * EFFECTS — one entry per action id in actions.js. All stubs for now;
   * wire each one to a real endpoint as we build them out.
   * ===================================================================== */
  const EFFECTS = {
    "raise-threshold":       () => alert("not implemented yet"),
    "kill-kibana-container": () => alert("not implemented yet"),
    "purge-old-data":        () => alert("not implemented yet"),
  };

  const runAction = useCallback((action) => {
    const fn = EFFECTS[action.id];
    if (fn) fn();
    else pushToast({ kind: "warn", title: "No handler", desc: "No effect mapped for “" + action.id + "”." });
  }, [tempActive]);

  const services = {
    kibana: kibana,
    logstash: logstashRunning ? "running" : "stopped"
  };

  return (
    <div className="app">
      <Ribbon
        level={level} peak={peak} threshold={threshold}
        logstashRunning={logstashRunning}
        clusterName={clusterName} incidentStartedAt={cfg.incidentStartedAt}
      />

      <header className="topbar">
        <div className="brand">
          <span className="logo">⛑</span>
          <div className="brand-text">
            <h1>Cluster Recovery Console</h1>
            <div className="sub">
              Kibana is unreachable. Use this page to relieve disk pressure and restore service on <b>{clusterName}</b>.
            </div>
          </div>
        </div>
        <div className="topbar-right">
          <span className="refresh-pill"><span className="spin"></span>live · {cfg.tickMs / 1000}s</span>
          <button className="theme-toggle" onClick={() => setTheme(theme === "dark" ? "light" : "dark")}>
            {theme === "dark" ? "☀ Light" : "☾ Dark"}
          </button>
        </div>
      </header>

      <ContactBanner contact={cfg.adminContact} />

      <div className="grid">
        <NodePanel nodes={nodes} threshold={threshold} colHeight={colHeight} />
        <div ref={rightRef}>
          <ActionsPanel
            actions={cfg.actions} services={services}
            threshold={threshold} tempActive={tempActive} limits={L}
            onRun={runAction}
          />
        </div>
      </div>

      <Toasts toasts={toasts} onDismiss={dismissToast} />
    </div>
  );
}

Object.assign(window, { App });

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
