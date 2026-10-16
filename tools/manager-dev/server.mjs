// Mukafaah Manager - local dev server (Node built-ins only, no packages).
// Serves backend/admin straight from disk, so edits to app.js / styles.css
// show on a browser refresh, and forwards /v1/* to a running Mukafaah API.
//
//   node tools/manager-dev/server.mjs                         -> API at http://localhost:3000
//   node tools/manager-dev/server.mjs http://192.168.1.5:3000 -> API on another PC (e.g. Wissam's)
//   PORT=5174 node tools/manager-dev/server.mjs ...           -> pick the local port (default 5173)
import http from 'node:http';
import https from 'node:https';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const ADMIN = join(here, '..', '..', 'backend', 'admin');
const API = new URL(process.argv[2] || process.env.API_URL || 'http://localhost:3000');
const PORT = Number(process.env.PORT || 5173);
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon' };

function proxy(req, res) {
  const lib = API.protocol === 'https:' ? https : http;
  const headers = { ...req.headers, host: API.host };
  const up = lib.request({ protocol: API.protocol, hostname: API.hostname, port: API.port || (API.protocol === 'https:' ? 443 : 80), method: req.method, path: req.url, headers }, (r) => {
    res.writeHead(r.statusCode || 502, r.headers);
    r.pipe(res);
  });
  up.on('error', (e) => {
    res.writeHead(502, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ code: 'API_UNREACHABLE', message: `Cannot reach the API at ${API.origin} (${e.code || e.message}). Is the server running?` }));
  });
  req.pipe(up);
}

async function file(req, res) {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/' ) { res.writeHead(302, { location: '/admin/' }); return res.end(); }
  if (p === '/admin' || p === '/admin/') p = '/admin/index.html';
  const rel = normalize(p.slice('/admin/'.length)).replace(/^([.][.][\\/])+/, '');
  try {
    const body = await readFile(join(ADMIN, rel));
    res.writeHead(200, { 'content-type': TYPES[extname(rel)] || 'application/octet-stream', 'cache-control': 'no-store' });
    res.end(body);
  } catch {
    res.writeHead(404, { 'content-type': 'text/plain' }); res.end('Not found');
  }
}

http.createServer((req, res) => {
  if (req.url.startsWith('/v1/') || req.url === '/health') return proxy(req, res);
  if (req.url === '/' || req.url.startsWith('/admin')) return file(req, res);
  res.writeHead(404); res.end();
}).listen(PORT, () => {
  console.log(`\n  Mukafaah Manager (dev)   http://localhost:${PORT}/admin`);
  console.log(`  Files from               ${ADMIN}`);
  console.log(`  API forwarded to         ${API.origin}\n`);
  console.log('  Edit backend/admin/app.js or styles.css, then refresh the browser.\n');
});
