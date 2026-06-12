// main.js — serve the built recovery-ui (dist/) over http or https, plus a
// tiny /api/nodes endpoint that pulls live disk usage from Elasticsearch the
// same way logstash does (curl _cat/allocation with kibana creds).
//
// Zero dependencies — uses node built-ins so it runs on kibana's bundled node.
//
// Env:
//   PORT              listen port (default 8080)
//   ROOT              directory to serve (default ./dist if it exists, else .)
//   SSL_CERT          PEM cert (optional; enables https)
//   SSL_KEY           PEM key  (required if SSL_CERT set)
//
//   ELASTICSEARCH_URLS    JSON array of ES URLs (same env kibana uses)
//   ES_USER               ES user for the read-only stats call (default: elastic)
//   ES_PASSWORD           ES password (overrides ES_PASSWORD_FILE)
//   ES_PASSWORD_FILE      path to file containing ES password (default: /tmp/share/credential.txt)
//
// Settings injection (window.RecoveryConfig values) — applied once at startup
// by replacing TEMPLATE_X tokens in dist/js/settings.js with env vars:
//   RETENTION_MONTHS  (everything else is hardcoded in settings.js; cluster name
//                      is pulled from ES at runtime by /api/nodes)

const http  = require("http");
const https = require("https");
const fs    = require("fs");
const path  = require("path");
const url   = require("url");

/* ------------------------------------------------------------------------ */
/* Settings template substitution                                            */
/* ------------------------------------------------------------------------ */
const SETTINGS_DEFAULTS = {
  RETENTION_MONTHS: "3",
};

function escapeForJsString(s) {
  return String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r?\n/g, " ");
}

function injectSettings(settingsPath) {
  if (!fs.existsSync(settingsPath)) return;
  let src = fs.readFileSync(settingsPath, "utf8");
  for (const key of Object.keys(SETTINGS_DEFAULTS)) {
    const val = process.env[key] != null ? process.env[key] : SETTINGS_DEFAULTS[key];
    src = src.split("TEMPLATE_" + key).join(escapeForJsString(val));
  }
  fs.writeFileSync(settingsPath, src);
}

/* ------------------------------------------------------------------------ */
/* ES password resolution                                                    */
/* ------------------------------------------------------------------------ */
function resolveEsPassword() {
  if (process.env.ES_PASSWORD) return process.env.ES_PASSWORD;
  const f = process.env.ES_PASSWORD_FILE || "/tmp/share/credential.txt";
  try { return fs.readFileSync(f, "utf8").trim(); }
  catch (e) { return ""; }
}

function parseEsUrls() {
  const raw = process.env.ELASTICSEARCH_URLS || '["https://elasticsearch:9200"]';
  try {
    const arr = JSON.parse(raw);
    return Array.isArray(arr) ? arr : [String(arr)];
  } catch (e) {
    return [raw];
  }
}

/* ------------------------------------------------------------------------ */
/* /api/nodes — pulls disk usage from ES                                     */
/* ------------------------------------------------------------------------ */
function esGet(targetUrl, auth) {
  return new Promise((resolve, reject) => {
    const parsed = url.parse(targetUrl);
    const lib = parsed.protocol === "https:" ? https : http;
    const req = lib.request({
      method: "GET",
      hostname: parsed.hostname,
      port: parsed.port || (parsed.protocol === "https:" ? 443 : 80),
      path: parsed.path,
      headers: { Authorization: "Basic " + Buffer.from(auth).toString("base64") },
      rejectUnauthorized: false, // ES uses a self-signed CA in this stack
    }, (res) => {
      let body = "";
      res.on("data", (d) => body += d);
      res.on("end", () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try { resolve(JSON.parse(body)); }
          catch (e) { reject(new Error("invalid JSON from ES: " + e.message)); }
        } else {
          reject(new Error("ES " + res.statusCode + ": " + body.slice(0, 200)));
        }
      });
    });
    req.on("error", reject);
    req.setTimeout(8000, () => req.destroy(new Error("ES request timeout")));
    req.end();
  });
}

function mapAllocationRow(row) {
  const totalBytes = Number(row["disk.total"] || 0);
  const usedBytes  = Number(row["disk.used"]  || 0);
  const usedPct    = totalBytes > 0 ? Math.round((usedBytes / totalBytes) * 1000) / 10 : 0;
  const diskTotalGB = totalBytes > 0 ? Math.round(totalBytes / (1024 * 1024 * 1024)) : 0;
  const name = String(row.node || "unknown");
  return {
    id: name,
    name: name,
    role: String(row["node.role"] || row.role || "unknown"),
    diskTotalGB: diskTotalGB,
    usedPct: usedPct,
  };
}

async function fetchNodes() {
  const urls = parseEsUrls();
  const pass = resolveEsPassword();
  const user = process.env.ES_USER || "elastic";
  const auth = user + ":" + pass;
  let lastErr;
  for (const base of urls) {
    const root = base.replace(/\/$/, "");
    try {
      const rows = await esGet(
        root + "/_cat/allocation?format=json&bytes=b&h=node,node.role,disk.used,disk.total",
        auth
      );
      const nodes = rows
        .filter((r) => r.node && r.node !== "UNASSIGNED")
        .map(mapAllocationRow);

      // Cluster name comes straight from ES root — cheap, single round-trip.
      let clusterName = "";
      try {
        const root_info = await esGet(root + "/", auth);
        clusterName = String(root_info.cluster_name || "");
      } catch (e) { /* non-fatal — nodes are the important bit */ }

      return { clusterName, nodes };
    } catch (e) {
      lastErr = e;
    }
  }
  throw lastErr || new Error("no ES URLs available");
}

/* ------------------------------------------------------------------------ */
/* Static file serving                                                       */
/* ------------------------------------------------------------------------ */
const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js":   "application/javascript; charset=utf-8",
  ".jsx":  "application/javascript; charset=utf-8",
  ".mjs":  "application/javascript; charset=utf-8",
  ".css":  "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg":  "image/svg+xml",
  ".png":  "image/png",
  ".jpg":  "image/jpeg",
  ".jpeg": "image/jpeg",
  ".ico":  "image/x-icon",
  ".woff": "font/woff",
  ".woff2":"font/woff2",
  ".map":  "application/json",
};

function serveStatic(req, res, root) {
  let p = decodeURIComponent(url.parse(req.url).pathname);
  if (p.endsWith("/")) p += "index.html";
  const full = path.normalize(path.join(root, p));
  if (!full.startsWith(root)) { res.writeHead(403); return res.end("forbidden"); }
  fs.stat(full, (err, st) => {
    if (err || !st.isFile()) {
      const fb = path.join(root, "index.html");
      return fs.stat(fb, (e2, s2) => {
        if (e2 || !s2.isFile()) { res.writeHead(404); return res.end("not found"); }
        res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        fs.createReadStream(fb).pipe(res);
      });
    }
    res.writeHead(200, {
      "Content-Type": MIME[path.extname(full).toLowerCase()] || "application/octet-stream",
    });
    fs.createReadStream(full).pipe(res);
  });
}

function send(res, status, obj) {
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(obj));
}

/* ------------------------------------------------------------------------ */
/* Main                                                                      */
/* ------------------------------------------------------------------------ */
const PORT = parseInt(process.env.PORT || "8080", 10);
const here = __dirname;
const distDir = path.join(here, "dist");
const ROOT = process.env.ROOT
  ? path.resolve(process.env.ROOT)
  : (fs.existsSync(distDir) ? distDir : here);

// Inject env settings into dist/js/settings.js once at startup.
injectSettings(path.join(ROOT, "js", "settings.js"));

const SSL_CERT = process.env.SSL_CERT;
const SSL_KEY  = process.env.SSL_KEY;

function handler(req, res) {
  const p = url.parse(req.url).pathname;
  if (p === "/api/nodes") {
    fetchNodes()
      .then((payload) => send(res, 200, payload))
      .catch((err) => send(res, 502, { error: String(err.message || err), clusterName: "", nodes: [] }));
    return;
  }
  serveStatic(req, res, ROOT);
}

const server = (SSL_CERT && SSL_KEY)
  ? https.createServer({ cert: fs.readFileSync(SSL_CERT), key: fs.readFileSync(SSL_KEY) }, handler)
  : http.createServer(handler);

server.listen(PORT, "0.0.0.0", () => {
  const scheme = (SSL_CERT && SSL_KEY) ? "https" : "http";
  console.log(`recovery-ui serving ${ROOT} on ${scheme}://0.0.0.0:${PORT}/`);
});
