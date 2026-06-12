/* Toasts.jsx — transient feedback for actions + auto-events */

function Toasts({ toasts, onDismiss }) {
  const ICON = { primary: "ℹ", danger: "⚠", warn: "⚠", success: "✓" };
  return (
    <div className="toasts">
      {toasts.map((t) => (
        <div key={t.id} className="toast" data-kind={t.kind || "primary"}
             onClick={() => onDismiss(t.id)} title="Dismiss">
          <span className="ic">{ICON[t.kind] || "ℹ"}</span>
          <div>
            <div className="tt">{t.title}</div>
            {t.desc && <div className="td">{t.desc}</div>}
          </div>
        </div>
      ))}
    </div>
  );
}

Object.assign(window, { Toasts });
