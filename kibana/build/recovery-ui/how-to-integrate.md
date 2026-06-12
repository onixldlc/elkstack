# How to integrate the Cluster Recovery Console

> **Audience:** an engineer or a coding agent wiring this static front-end into a
> real Elastic stack. Read §0 first, then jump to the section you need.
> Nothing here requires npm or a build toolchain. JSX is compiled in the
> browser by Babel; serving is done by a tiny zero-dependency node server
> (`main.js`, runs on kibana's bundled node).

---

## 0. TL;DR / mental model

This project is a **static front-end only**. It is React, but compiled in the
browser by Babel at load time — there is no bundler and no `node_modules`. You
serve it as plain files.

Three things must be true for it to do real work:

1. **It must be served by something that is NOT Kibana.** The whole point is
   that it appears *when Kibana is down*, so Kibana cannot serve its own
   recovery page. Put it behind your reverse proxy as a fallback, or run it as a
   tiny independent sidecar. (See §3.)
2. **Live node data** comes from a small read endpoint that proxies
   Elasticsearch. Today `js/data.js` fakes it. (See §5.)
3. **The 3 action buttons** must POST to a small privileged backend (the
   "control plane") that talks to Elasticsearch / the host. Today they are
   simulated in `components/App.jsx`. (See §6 + §7.)

The browser must **never** hold Elasticsearch admin credentials and **cannot**
restart services or delete indices by itself. That is what the control plane is
for. Everything destructive happens server-side, behind auth.

### Where the seams live (the only files you edit)

| Concern | File | What to change |
|---|---|---|
| Cluster name, contact, limits, retention, action list | `js/config.js` | Plain data. Safe to edit freely. |
| Live node disk data | `js/data.js` + `components/App.jsx` | Replace the fake generator with a `fetch`. |
| What each button actually does | `components/App.jsx` (the `EFFECTS` map) | Replace each simulated handler with a `fetch` POST. |
| Look & feel | `css/styles.css` | Optional. |

---

## 1. Architecture

```
                         ┌─────────────────────────────────────────┐
   browser ── HTTP ──►   │  reverse proxy (nginx / Envoy / HAProxy) │
                         └───────────────┬──────────────┬──────────┘
                              Kibana up?  │              │  Kibana down (502/503)?
                                          ▼              ▼
                                   ┌────────────┐  ┌──────────────────────────┐
                                   │   Kibana   │  │  Cluster Recovery Console │ (static files)
                                   └────────────┘  └────────────┬─────────────┘
                                                                │ XHR /api/*
                                                                ▼
                                                   ┌──────────────────────────┐
                                                   │  control plane (you build)│
                                                   │  • reads ES node stats    │
                                                   │  • PUT _cluster/settings  │
                                                   │  • systemctl restart …    │
                                                   │  • delete old indices     │
                                                   └────────────┬─────────────┘
                                                                ▼
                                                   Elasticsearch  +  host (systemd)
```

**Why a separate control plane?** Browsers can't run `systemctl` and shouldn't
see cluster admin creds. The control plane is a thin authenticated service
(write it in whatever you like — Go, Python/FastAPI, Node, a Kibana custom
plugin) that exposes the small REST contract in §7 and does the privileged work.

---

## 2. Run & build (no npm)

```sh
chmod +x run.sh build.sh        # once

./run.sh                        # node dev server on http://localhost:8080
PORT=9000 ./run.sh              # different port

./build.sh                      # → dist/  (CDN-free, vendored React/Babel)
./run.sh dist                   # preview the built output (node main.js)
```

`run.sh` just launches the bundled zero-dependency node server (`main.js`),
which serves the static files and the small `/api/nodes` endpoint.

`build.sh` outputs:

- `dist/` — a folder with the app plus `dist/vendor/{react,react-dom,babel.min}.js`
  and the `<script>` tags rewritten to those local copies. Serve it with
  `./run.sh dist` (node) or point any static server / nginx at the folder.
  No internet needed at runtime.

> **Note on Babel-in-browser:** for a recovery page shown rarely this is fine.
> If you ever want true precompiled JS you'd need a Babel toolchain (npm) — out
> of scope here by design.

---

## 3. Deploy as a Kibana fallback

### Option A — nginx in front of Kibana (recommended)

```nginx
upstream kibana_upstream {
    server 127.0.0.1:5601;
}

server {
    listen 80;
    server_name kibana.example.internal;

    # The recovery console (built dist/), served as static files.
    root /opt/kibana-recovery/dist;

    location / {
        proxy_pass http://kibana_upstream;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_connect_timeout 3s;
        proxy_read_timeout    10s;

        # If Kibana is down / unhealthy, fall through to the recovery page.
        proxy_intercept_errors on;
        error_page 502 503 504 = @recovery;
    }

    # Static recovery console (independent of Kibana).
    location @recovery {
        # Serve the deployed dist/ folder (root points at it above).
        rewrite ^ /index.html break;
        # (or proxy_pass to the node sidecar from Option B)
    }

    # The control-plane API, always reachable (NOT proxied to Kibana).
    location /api/ {
        proxy_pass http://127.0.0.1:8088/;   # your control plane
    }
}
```

Deploy the whole `dist/` folder to `/opt/kibana-recovery/dist` and serve
`index.html` from `@recovery`.

### Option B — standalone sidecar (simplest)

Run it on its own port on the Kibana host so ops can always reach it, even when
nginx/Kibana are unhappy. Example `systemd` unit:

```ini
# /etc/systemd/system/kibana-recovery.service
[Unit]
Description=Cluster Recovery Console
After=network.target

[Service]
WorkingDirectory=/opt/kibana-recovery
Environment=PORT=8090
ExecStart=/opt/kibana-recovery/run.sh dist
Restart=always
User=kibana-recovery

[Install]
WantedBy=multi-user.target
```

```sh
sudo systemctl enable --now kibana-recovery
# now reachable at http://<host>:8090/ regardless of Kibana's state
```

---

## 4. Configure — `js/config.js`

Edit these (all plain data, no logic):

```js
clusterName: "prod-observability-01",
adminContact: {
  configured: true,                 // flip to true once filled
  name: "Dana Okafor (Platform SRE)",
  phone: "+1 (555) 010-4477",
  slack: "#elastic-oncall",
  note: "PagerDuty: ES-Core rotation"
},
limits: {
  hardLimitPct: 85,                 // your enforced hard cap
  tempLimitPct: 90,                 // what the "raise" button lifts to
  resetBelowPct: 75,                // auto-reset point
  warningPct: 70
},
retentionMonths: 3,                 // used by the purge action + copy
```

The "contact your administrator" warning is always shown; it only swaps in the
name/phone/slack once `configured: true`.

---

## 5. Wire live node data

### 5a. Expected shape

Every node the UI renders is this object:

```js
{ id: "node-01", name: "es-hot-01", role: "data-hot",
  diskTotalGB: 4096, usedPct: 86.4 }
```

### 5b. Where it comes from in Elasticsearch

Your control plane's `GET /api/nodes` should call one of:

```sh
# disk usage per node, in bytes
GET /_nodes/stats/fs

# or the compact form
GET /_cat/allocation?format=json&bytes=b&h=node,role,disk.used,disk.total
```

…and map each node to the shape above:

```
usedPct      = 100 * disk.used / disk.total
diskTotalGB  = round(disk.total / 1024^3)
role         = node roles (data_hot → "data-hot", etc.)
```

### 5c. Front-end change

Replace the synchronous fake generator with a fetch + poll. In
**`components/App.jsx`**, change the initial state and add a loader:

```jsx
// was: const [nodes, setNodes] = useStateApp(() => D.makeNodes(cfg.nodeCount));
const [nodes, setNodes] = useStateApp([]);

useEffectApp(() => {
  let alive = true;
  const load = () =>
    fetch("/api/nodes")
      .then(r => r.json())
      .then(d => { if (alive) setNodes(d.nodes); })
      .catch(() => {/* keep last good data; UI shows what it has */});
  load();
  const t = setInterval(load, cfg.tickMs);
  return () => { alive = false; clearInterval(t); };
}, []);
```

Then **delete the simulation tick** (the `setInterval` that calls `D.tick`) so
you don't fight the real data. `js/data.js` can keep `statusOf`/`peakUsage`
(pure helpers the UI still uses); only `makeNodes`/`tick`/`purgeOldData` become
dead once real data + real actions are wired.

---

## 6. Wire the action buttons

All three live in the **`EFFECTS`** map in `components/App.jsx`. Each entry is
keyed by the `id` from `js/config.js`. Replace the simulated bodies with POSTs:

```jsx
const EFFECTS = {
  "raise-threshold": () =>
    call("/api/actions/raise-threshold", { toPct: L.tempLimitPct }),

  "restart-kibana": () =>
    call("/api/actions/restart-kibana", {}),

  "purge-old-data": () =>
    call("/api/actions/purge-old-data", { retentionMonths: cfg.retentionMonths }),
};

function call(url, body) {
  pushToast({ kind: "primary", title: "Working…" });
  fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  })
    .then(r => r.ok ? r.json() : Promise.reject(r))
    .then(res => pushToast({ kind: "success", title: res.message || "Done" }))
    .catch(() => pushToast({ kind: "danger", title: "Action failed", desc: "Check the control-plane logs." }));
}
```

The type-to-confirm gate on the danger button is purely client-side — **re-check
it server-side too** (see §7).

**To add a 4th button later:** add an entry to `actions` in `js/config.js`
(give it `id`, `label`, `cta`, `kind`, `summary`, and a `confirm`), then add a
matching `id` handler in `EFFECTS`. Nothing else changes — there's an on-screen
hint that says exactly this.

---

## 7. The control plane (REST contract you implement)

Minimal, authenticated service. Suggested contract:

### `GET /api/nodes`
Returns `{ "nodes": [ {id,name,role,diskTotalGB,usedPct}, ... ] }` (see §5).
Source: `GET /_nodes/stats/fs`.

### `POST /api/actions/raise-threshold`  `{ "toPct": 90 }`
Raises whatever enforces your 85% cap. In stock Elasticsearch that's the disk
**watermarks**:

```sh
PUT /_cluster/settings
{
  "persistent": {
    "cluster.routing.allocation.disk.watermark.high":        "90%",
    "cluster.routing.allocation.disk.watermark.flood_stage": "92%"
  }
}
```

- `flood_stage` is the one that flips indices to read-only (i.e. stops writes /
  ingest). If your "85% hard limit" is enforced by `flood_stage`, raise that.
- If your hard limit is a *custom* guard (a Watcher, ILM, or a script), point
  this endpoint at that instead.
- Respond `{ "message": "Hard limit raised to 90%" }`.

### `POST /api/actions/restart-kibana`  `{}`
```sh
systemctl restart kibana          # host with privilege, or via a sudoers rule
```
Or hit your orchestrator (k8s: `kubectl rollout restart deploy/kibana`).
Respond when the service is back (or 202 + let the UI poll).

### `POST /api/actions/purge-old-data`  `{ "retentionMonths": 3 }`
**Destructive — guard hard.** Delete time-based indices older than the window:

```sh
# list candidate indices with their creation date
GET /_cat/indices?h=index,creation.date&format=json&s=creation.date

# delete each index whose creation.date is older than now - retentionMonths
DELETE /<index-name>
```

Prefer doing this via **ILM** or **data-stream retention** if you have it, so
deletion is policy-driven and auditable. Always:
- take/verify a snapshot first (SLM),
- never touch indices newer than the retention window,
- require an explicit server-side confirmation token (don't trust the client's
  type-to-confirm alone),
- write an audit record (who/when/what was deleted).

Respond `{ "message": "Deleted N indices older than 3 months; M.x TB freed" }`.

---

## 8. Auto-reset of the temporary threshold

The simulated UI resets 90% → 85% once peak usage drops below 75%. That logic
only runs while the page is open, so **move it server-side** for production. Two
options:

- A small cron/loop in the control plane: poll node stats; when peak `< resetBelowPct`,
  re-`PUT _cluster/settings` back to the 85% defaults and clear the temporary flag.
- An Elasticsearch **Watcher** that does the same on a schedule.

Expose the current effective limit in `GET /api/nodes` (e.g. add
`"thresholdPct": 90, "thresholdTemp": true`) and feed it into the UI's
`threshold`/`tempActive` state so the "Active disk hard limit" card reflects
reality instead of client state.

---

## 9. Security checklist

- [ ] Control plane sits behind auth (mTLS, SSO/OIDC, or at least a network ACL).
- [ ] Browser never receives Elasticsearch credentials; the control plane holds them.
- [ ] Destructive endpoints require a server-verified confirmation token, not just the client gate.
- [ ] RBAC: only on-call/admin roles can call `restart-kibana` and `purge-old-data`.
- [ ] Rate-limit and audit-log every action (actor, timestamp, payload, result).
- [ ] `purge-old-data` verifies a recent snapshot exists before deleting.
- [ ] The recovery page and `/api/*` are reachable even when Kibana is down (don't route them through Kibana).

---

## 10. File map

```
Cluster Recovery Console.html   # app shell (script/style includes)
index.html                      # tiny redirect → the console (dev convenience)
css/styles.css                  # all styling + dark/light tokens
js/config.js                    # ← EDIT: cluster name, contact, limits, actions
js/data.js                      # ← REPLACE makeNodes/tick with real fetch (§5)
components/
  App.jsx                       # ← EDIT: data loader (§5c) + EFFECTS map (§6)
  NodePanel.jsx                 # node bars/table, search/filter/sort
  ActionsPanel.jsx              # buttons + confirm modal
  Banner.jsx                    # incident ribbon + contact banner
  Toasts.jsx                    # action feedback
main.js                         # zero-dep node server (serves files + /api/nodes)
run.sh                          # launches main.js (no-npm dev/serve)
build.sh                        # no-npm build → dist/ (vendored React/Babel)
```

That's the whole surface. Configure (§4), point `GET /api/nodes` at real stats
(§5), implement the three POSTs (§7), and deploy it where Kibana's absence can't
take it down (§3).
