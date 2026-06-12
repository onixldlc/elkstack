/* NodePanel.jsx — per-node disk usage. Bars (primary) + table (detail),
 * with search, ">70% only" filter, and sort by name / usage. Scrollable. */
const { useState: useStateNP, useMemo, useRef: useRefNP, useLayoutEffect } = React;

function fmtGB(gb) {
  if (gb >= 1024) return (gb / 1024).toFixed(gb % 1024 === 0 ? 0 : 1) + " TB";
  return gb + " GB";
}

function NodeBar({ node, threshold }) {
  const D = window.RecoveryData;
  const s = D.statusOf(node.usedPct, threshold);
  const usedGB = Math.round(node.diskTotalGB * node.usedPct / 100);
  return (
    <div className="node-row">
      <div className="top">
        <span className="nm">{node.name}</span>
        <span className="role-badge">{node.role}</span>
        <span className="pct" data-s={s}>{node.usedPct.toFixed(1)}%</span>
      </div>
      <div className="bar">
        <div className="fill" data-s={s} style={{ width: Math.min(100, node.usedPct) + "%" }}></div>
        <div className="thresh" data-label={threshold + "%"} style={{ left: threshold + "%" }}></div>
      </div>
      <div className="meta">
        <span>{fmtGB(usedGB)} / {fmtGB(node.diskTotalGB)}</span>
        <span>·</span>
        <span>{node.role}</span>
      </div>
    </div>
  );
}

function NodeTable({ nodes, threshold }) {
  const D = window.RecoveryData;
  return (
    <table className="ntable">
      <thead>
        <tr><th>Node</th><th>Role</th><th>Disk used</th><th>Capacity</th><th>Status</th></tr>
      </thead>
      <tbody>
        {nodes.map((n) => {
          const s = D.statusOf(n.usedPct, threshold);
          const usedGB = Math.round(n.diskTotalGB * n.usedPct / 100);
          return (
            <tr key={n.id}>
              <td>{n.name}</td>
              <td>{n.role}</td>
              <td>
                <span className="mini"><i className={"s-" + s} style={{ width: Math.min(100, n.usedPct) + "%" }}></i></span>
                {n.usedPct.toFixed(1)}%
              </td>
              <td>{fmtGB(usedGB)} / {fmtGB(n.diskTotalGB)}</td>
              <td><span className={"pill s-" + s}><span className="d"></span>{s}</span></td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

function NodePanel({ nodes, threshold, colHeight }) {
  const D = window.RecoveryData;
  const [view, setView] = useStateNP("bars");
  const [query, setQuery] = useStateNP("");
  const [hotOnly, setHotOnly] = useStateNP(false);
  const [sort, setSort] = useStateNP("usage-desc");

  const panelRef = useRefNP(null);
  const scrollRef = useRefNP(null);
  const MIN_SCROLL = 460;

  // Match the node list to the tallest column (passed in as colHeight),
  // never shrinking below MIN_SCROLL. colHeight = 0 means "narrow / stacked".
  // chrome = everything in the panel that ISN'T the scroll area (header,
  // controls, borders) — measured as the difference so border/padding pixels
  // are accounted for exactly and the panel bottom aligns to the column.
  useLayoutEffect(() => {
    const panel = panelRef.current, scroll = scrollRef.current;
    if (!scroll) return;
    if (!colHeight || !panel) {
      scroll.style.height = "";
      scroll.style.maxHeight = MIN_SCROLL + "px";
      return;
    }
    const chrome = panel.offsetHeight - scroll.offsetHeight;
    const target = Math.max(colHeight - chrome, MIN_SCROLL);
    scroll.style.maxHeight = "none";
    scroll.style.height = target + "px";
  }, [colHeight, nodes.length, view]);

  const shown = useMemo(() => {
    let list = nodes.slice();
    const q = query.trim().toLowerCase();
    if (q) list = list.filter((n) => n.name.toLowerCase().includes(q) || n.role.toLowerCase().includes(q));
    if (hotOnly) list = list.filter((n) => n.usedPct > D.cfg.limits.warningPct);
    list.sort((a, b) => {
      switch (sort) {
        case "name-asc": return a.name.localeCompare(b.name);
        case "name-desc": return b.name.localeCompare(a.name);
        case "usage-asc": return a.usedPct - b.usedPct;
        default: return b.usedPct - a.usedPct;
      }
    });
    return list;
  }, [nodes, query, hotOnly, sort]);

  return (
    <section className="panel" ref={panelRef}>
      <div className="panel-head">
        <h2>Node disk usage</h2>
        <span className="count">{shown.length} / {nodes.length} nodes</span>
      </div>

      <div className="controls">
        <label className="search">
          <span className="ic">⌕</span>
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search node or role…" />
        </label>

        <button className={"chip-toggle" + (hotOnly ? " on" : "")} onClick={() => setHotOnly((v) => !v)}>
          <span className="box">{hotOnly ? "✓" : ""}</span>
          &gt;{D.cfg.limits.warningPct}% only
        </button>

        <select className="sortsel" value={sort} onChange={(e) => setSort(e.target.value)}>
          <option value="usage-desc">Usage ↓</option>
          <option value="usage-asc">Usage ↑</option>
          <option value="name-asc">Name A–Z</option>
          <option value="name-desc">Name Z–A</option>
        </select>

        <div className="seg">
          <button className={view === "bars" ? "on" : ""} onClick={() => setView("bars")}>Bars</button>
          <button className={view === "table" ? "on" : ""} onClick={() => setView("table")}>Table</button>
        </div>
      </div>

      <div className="node-scroll" ref={scrollRef}>
        {shown.length === 0 ? (
          <div className="empty">No nodes match your filters.</div>
        ) : view === "bars" ? (
          shown.map((n) => <NodeBar key={n.id} node={n} threshold={threshold} />)
        ) : (
          <NodeTable nodes={shown} threshold={threshold} />
        )}
      </div>
    </section>
  );
}

Object.assign(window, { NodePanel, NodeBar, NodeTable });
