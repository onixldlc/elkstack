/* Banner.jsx — incident ribbon + always-on admin contact banner */
const { useState, useEffect } = React;

/* Live "time since incident" clock. */
function IncidentClock({ since }) {
  const [, force] = useState(0);
  useEffect(() => {
    const t = setInterval(() => force((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, []);
  const secs = Math.max(0, Math.floor((Date.now() - since) / 1000));
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  const pad = (n) => String(n).padStart(2, "0");
  return <span className="mono">{h > 0 ? pad(h) + ":" : ""}{pad(m)}:{pad(s)}</span>;
}

/* Top ribbon — reflects the live cluster level. */
function Ribbon({ level, peak, threshold, logstashRunning, clusterName, incidentStartedAt }) {
  let msg;
  if (!logstashRunning) {
    msg = <span className="ribbon-msg"><strong>Ingest halted.</strong> Cluster disk reached the {threshold}% hard limit — Logstash and Kibana were stopped to protect the nodes.</span>;
  } else if (level === "elevated") {
    msg = <span className="ribbon-msg"><strong>Recovering.</strong> Ingest resumed, but peak node usage is still elevated at {peak.toFixed(1)}%.</span>;
  } else {
    msg = <span className="ribbon-msg"><strong>Pressure relieved.</strong> Peak node usage is {peak.toFixed(1)}%. Safe to bring Kibana back online.</span>;
  }
  return (
    <div className="ribbon" data-level={level}>
      <span className="dot"></span>
      {msg}
      <span className="ribbon-meta mono">
        {clusterName} · incident +<IncidentClock since={incidentStartedAt} />
      </span>
    </div>
  );
}

/* Always-on "contact your admin" banner. Generic unless configured. */
function ContactBanner({ contact }) {
  const c = contact;
  return (
    <div className="contact" role="note">
      <span className="ic">☎</span>
      <div className="body">
        <div className="title">
          {c.configured
            ? <>Contact <b>{c.name}</b> before taking any recovery action</>
            : <>Contact your Elastic administrator before taking any recovery action</>}
        </div>
        <div className="desc">
          These controls can stop services and delete data. Always confirm with the person
          responsible for this cluster first. {!c.configured &&
            <span>(No on-call contact is configured — set <code>adminContact</code> in <code>js/config.js</code>.)</span>}
        </div>
        {c.configured && (c.phone || c.slack || c.note) && (
          <div className="chips">
            {c.phone && <span className="chip">☎ <b>{c.phone}</b></span>}
            {c.slack && <span className="chip"># <b>{c.slack}</b></span>}
            {c.note && <span className="chip">{c.note}</span>}
          </div>
        )}
      </div>
    </div>
  );
}

Object.assign(window, { Ribbon, ContactBanner, IncidentClock });
