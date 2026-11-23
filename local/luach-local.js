// לוח הקומה — שרת מקומי למחשב של המסך.
// מגיש את הלוח ואת דף הניהול ברשת המקומית, שומר את ההגדרות בקובץ,
// ומסנכרן עם Firebase בכל פעם שיש אינטרנט. אין תלויות: מספיק Node.js.
//   node luach-local.js            → http://localhost:8770  (ניהול: /#manage)
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFile } = require('child_process');

const PORT = Number(process.env.LUACH_PORT) || 8770;
const ROOT = path.resolve(__dirname, '..');
const STATE_FILE = process.env.LUACH_STATE || path.join(__dirname, 'state.json');
const SYNC_MS = 5000;
const KEYS = ['config', 'msgs', 'media'];
const MAX_BODY = 25 * 1024 * 1024; // תמונות נשמרות כ-base64 בתוך רשימת המדיה
const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.webmanifest': 'application/manifest+json', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
};

// כתובת Firebase נלקחת מ-index.html, כך שיש רק מקום אחד להגדיר אותה.
const DB_URL = process.env.LUACH_DB || (() => {
  const m = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8').match(/databaseURL:\s*"(https:[^"]+)"/);
  return m ? m[1].replace(/\/$/, '') : '';
})();

// Last-write-wins, בדיוק כמו בדף: config לפי updatedAt, msgs/media לפי u.
const stamp = (key, v) => (v && (key === 'config' ? v.updatedAt : v.u)) || 0;

let state = { config: null, msgs: null, media: null, status: null };
try { state = Object.assign(state, JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'))); } catch { /* first run */ }
const dirty = new Set(); // keys changed locally and not yet uploaded
const cloud = { online: false, lastSync: 0, error: '' };

let saveTimer = null;
function persist() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    const tmp = STATE_FILE + '.tmp';
    fs.writeFile(tmp, JSON.stringify(state), (err) => { if (!err) fs.rename(tmp, STATE_FILE, () => {}); });
  }, 300);
}

const clients = new Set();
function send(res, k, v) { res.write(`data: ${JSON.stringify({ k, v, t: Date.now() })}\n\n`); }
function broadcast(k, v) { for (const res of clients) send(res, k, v); }

/** Applies a newer value; returns false when the stored one is newer. */
function apply(key, value, fromCloud) {
  if (stamp(key, value) < stamp(key, state[key])) return false;
  state[key] = value;
  if (fromCloud) dirty.delete(key); else dirty.add(key);
  persist();
  broadcast(key, value);
  return true;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0; const chunks = [];
    req.on('data', (c) => { size += c.length; if (size > MAX_BODY) { reject(new Error('too large')); req.destroy(); } else chunks.push(c); });
    req.on('end', () => { try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))); } catch (e) { reject(e); } });
    req.on('error', reject);
  });
}

function json(res, code, body) {
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
}

function serveFile(req, res, pathname) {
  let rel;
  try { rel = decodeURIComponent(pathname); } catch { return json(res, 400, {}); }
  if (rel === '/') rel = '/index.html';
  const file = path.resolve(ROOT, '.' + rel);
  const parts = path.relative(ROOT, file).split(path.sep);
  const privateFile = parts[0] === 'local' && /^(state\.json|server\.log)/.test(parts[1] || '');
  if (!file.startsWith(ROOT + path.sep) || parts.some((p) => p.startsWith('.')) || privateFile) return json(res, 404, {});
  fs.readFile(file, (err, data) => {
    if (err) return json(res, 404, {});
    const headers = { 'Content-Type': TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream', 'Cache-Control': 'no-cache' };
    if (rel === '/index.html') {
      // מסמן לדף שהוא רץ מהמחשב המקומי, כדי שידבר עם השרת הזה ולא ישירות עם Firebase.
      data = Buffer.from(data.toString('utf8').replace('<head>', '<head><script>window.LUACH_LOCAL=1</script>'));
    }
    res.writeHead(200, headers);
    res.end(req.method === 'HEAD' ? undefined : data);
  });
}

const server = http.createServer(async (req, res) => {
  const { pathname } = new URL(req.url, 'http://local');
  try {
    if (pathname === '/api/stream' && req.method === 'GET') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive' });
      res.write('retry: 2000\n\n');
      for (const k of [...KEYS, 'status']) send(res, k, state[k]);
      send(res, 'cloud', cloud);
      clients.add(res);
      const ping = setInterval(() => res.write(': ping\n\n'), 15000);
      res.on('close', () => { clearInterval(ping); clients.delete(res); });
      return;
    }
    const m = pathname.match(/^\/api\/board\/(config|msgs|media)$/);
    if (m && req.method === 'POST') {
      const value = await readBody(req);
      if (!value || typeof value !== 'object') return json(res, 400, { error: 'bad body' });
      return json(res, 200, { applied: apply(m[1], value, false) });
    }
    if (pathname === '/api/status' && req.method === 'POST') {
      const body = await readBody(req).catch(() => ({}));
      state.status = { online: true, ts: Date.now(), fs: !!(body && body.fs) };
      dirty.add('status');
      broadcast('status', state.status);
      return json(res, 200, { ok: true });
    }
    if (pathname === '/api/fullscreen' && req.method === 'POST') {
      // רק הדף שרץ על המחשב עצמו יכול לבקש — לא אייפון/מכשיר אחר ברשת.
      if (!isLoopback(req.socket.remoteAddress)) return json(res, 403, {});
      return pressF11((result) => json(res, 200, { result }));
    }
    if (pathname === '/api/info') return json(res, 200, { cloud, addresses: lanAddresses(), port: PORT, clients: clients.size });
    if (pathname.startsWith('/api/')) return json(res, 404, {});
    if (req.method !== 'GET' && req.method !== 'HEAD') return json(res, 405, {});
    return serveFile(req, res, pathname);
  } catch (e) {
    return json(res, 400, { error: String(e.message || e) });
  }
});

// ---------- מסך מלא: לוחץ F11 בחלון הדפדפן של הלוח (Windows בלבד) ----------
const isLoopback = (a) => a === '127.0.0.1' || a === '::1' || a === '::ffff:127.0.0.1';
const PAGE_TITLE = (() => {
  const m = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8').match(/<title>([^<]+)<\/title>/);
  return m ? m[1].trim() : '';
})();
let f11Busy = false;
function pressF11(done) {
  if (process.platform !== 'win32') return done('unsupported');
  if (f11Busy) return done('busy');
  f11Busy = true;
  const title = PAGE_TITLE.replace(/'/g, "''");
  // מוצאים את חלון Chrome/Edge שהכותרת שלו היא כותרת הלוח, מביאים אותו לקדמה,
  // ולוחצים F11 רק אם הוא באמת החלון הפעיל (כדי שהמקש לא ייפול בחלון אחר).
  const ps = `
Add-Type @'
using System; using System.Runtime.InteropServices;
public class LuachWin {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
}
'@
$p = Get-Process chrome, msedge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like '*${title}*' } | Select-Object -First 1
if (-not $p) { 'notfound'; exit }
$h = $p.MainWindowHandle
if ([LuachWin]::IsIconic($h)) { [void][LuachWin]::ShowWindow($h, 9) }
$ws = New-Object -ComObject WScript.Shell
[void]$ws.AppActivate($p.Id); [void][LuachWin]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 400
if ([LuachWin]::GetForegroundWindow() -ne $h) { 'nofocus'; exit }
$ws.SendKeys('{F11}'); 'ok'
`;
  const enc = Buffer.from(ps, 'utf16le').toString('base64');
  execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', enc],
    { timeout: 15000, windowsHide: true }, (err, stdout) => {
      f11Busy = false;
      const result = err ? 'error' : String(stdout).trim().split(/\r?\n/).pop() || 'error';
      console.log(`Fullscreen request: ${result}`);
      done(result);
    });
}

// ---------- Firebase sync (REST) ----------
async function fb(method, p, body) {
  const r = await fetch(`${DB_URL}/board/${p}.json`, {
    method, signal: AbortSignal.timeout(10000),
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!r.ok) throw new Error(`${method} ${p}: HTTP ${r.status}`);
  return r.json();
}

let syncing = false;
async function syncOnce() {
  if (syncing || !DB_URL) return;
  syncing = true;
  try {
    // Only the version stamps are downloaded each round; full values only when the cloud is newer.
    const remote = await Promise.all([fb('GET', 'config/updatedAt'), fb('GET', 'msgs/u'), fb('GET', 'media/u')]);
    for (let i = 0; i < KEYS.length; i++) {
      const key = KEYS[i], r = remote[i] || 0, l = stamp(key, state[key]);
      if (r > l) apply(key, await fb('GET', key), true);
      else if ((l > r || dirty.has(key)) && state[key]) { await fb('PUT', key, state[key]); dirty.delete(key); }
    }
    if (dirty.has('status') && state.status) { await fb('PUT', 'status/display', state.status); dirty.delete('status'); }
    setCloud(true, '');
  } catch (e) {
    setCloud(false, String(e.message || e));
  } finally {
    syncing = false;
  }
}

function setCloud(online, error) {
  const changed = cloud.online !== online;
  cloud.online = online; cloud.error = error;
  if (online) cloud.lastSync = Date.now();
  if (changed) { console.log(online ? 'Cloud: connected' : `Cloud: offline (${error})`); broadcast('cloud', cloud); }
}

function lanAddresses() {
  return Object.values(os.networkInterfaces()).flat()
    .filter((a) => a && a.family === 'IPv4' && !a.internal).map((a) => a.address);
}

server.on('error', (e) => {
  console.error(e.code === 'EADDRINUSE' ? `Port ${PORT} is already in use (is the server already running?)` : e);
  process.exit(1);
});
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Board:  http://localhost:${PORT}/`);
  for (const a of lanAddresses()) console.log(`Manage: http://${a}:${PORT}/#manage`);
  console.log(DB_URL ? `Cloud:  ${DB_URL}` : 'Cloud:  not configured (local only)');
  syncOnce();
  setInterval(syncOnce, SYNC_MS);
});
