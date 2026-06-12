/* ActionsPanel.jsx — service status, live threshold, recovery buttons,
 * and the confirmation modal (simple OR type-to-confirm). */
const { useState: useStateAP, useEffect: useEffectAP } = React;

function StatusDot({ state, label }) {
  return (
    <div className="svc-row">
      <span className="nm">{label}</span>
      <span className={"st " + state}><span className="d"></span>{state}</span>
    </div>
  );
}

/* The confirmation modal. */
function ConfirmModal({ action, onCancel, onConfirm }) {
  const [text, setText] = useStateAP("");
  const isType = action.confirm && action.confirm.type === "type";
  const phrase = isType ? action.confirm.phrase : null;
  const matched = isType ? text.trim() === phrase : true;

  useEffectAP(() => {
    const onKey = (e) => { if (e.key === "Escape") onCancel(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  return (
    <div className="overlay" onMouseDown={(e) => { if (e.target === e.currentTarget) onCancel(); }}>
      <div className="modal" data-kind={action.kind}>
        <div className="modal-head">
          <span className="ic">{action.icon}</span>
          <h3>{action.label}</h3>
        </div>
        <div className="modal-body">
          <p>{action.summary}</p>
          {action.dangerNote && (
            <div className="danger-note">
              <span className="ic">⚠</span>
              <span>{action.dangerNote}</span>
            </div>
          )}
          {isType && (
            <div className="confirm-field">
              <label>Type <b>{phrase}</b> to confirm</label>
              <input
                autoFocus value={text}
                className={matched ? "match" : ""}
                onChange={(e) => setText(e.target.value)}
                placeholder={phrase}
                spellCheck={false}
              />
            </div>
          )}
        </div>
        <div className="modal-foot">
          <button className="btn btn-ghost" onClick={onCancel}>Cancel</button>
          <button
            className={"btn " + (action.kind === "danger" ? "btn-danger" : "btn-primary")}
            disabled={!matched}
            onClick={() => onConfirm(action)}
          >
            {action.kind === "danger" ? "Run anyway" : "Confirm"}
          </button>
        </div>
      </div>
    </div>
  );
}

function ActionsPanel({ actions, services, threshold, tempActive, limits, onRun }) {
  const [pending, setPending] = useStateAP(null);
  const busy = services.kibana === "restarting";

  return (
    <>
      <section className="panel">
        <div className="panel-head"><h2>Services</h2></div>
        <div className="svc">
          <StatusDot label="Kibana" state={services.kibana} />
          <StatusDot label="Logstash (ingest)" state={services.logstash} />
        </div>
        <div className="thresh-card">
          <div className="lbl">Active disk hard limit</div>
          <div className="val">
            {threshold}%
            {tempActive && <span className="badge">Temporary</span>}
          </div>
          <div className="note">
            {tempActive
              ? <>Raised from {limits.hardLimitPct}%. Auto-resets to {limits.hardLimitPct}% once peak usage drops below {limits.resetBelowPct}%.</>
              : <>Default cap. Ingest &amp; Kibana stop at this level to protect the nodes.</>}
          </div>
        </div>
      </section>

      <section className="panel" style={{ marginTop: "18px" }}>
        <div className="panel-head"><h2>Recovery actions</h2></div>
        <div className="actions-list">
          {actions.map((a) => (
            <button key={a.id} className="act-btn" data-kind={a.kind}
                    disabled={busy} onClick={() => setPending(a)}>
              <span className="ic">{a.icon}</span>
              <span className="txt">
                <span className="lbl">{a.label}</span>
                <span className="desc">{a.summary}</span>
              </span>
              <span className="act-cta">{a.cta || "Run"}</span>
            </button>
          ))}
        </div>
        <div className="add-hint">
          More actions can be added — append an entry to <code>actions</code> in <code>js/config.js</code>
          and a handler in <code>EFFECTS</code> (App.jsx).
        </div>
      </section>

      {pending && (
        <ConfirmModal
          action={pending}
          onCancel={() => setPending(null)}
          onConfirm={(a) => { setPending(null); onRun(a); }}
        />
      )}
    </>
  );
}

Object.assign(window, { ActionsPanel, ConfirmModal });
