#!/usr/bin/env node
// BNS sync server — one file, zero dependencies, three commands.
//
// Philosophy (owner's spec, July 2026):
//   - The user's data lives UNPACKED on the server: data.json + individual
//     audio files. No zip work on the hot path — .bns stays an import/export
//     travel file on the client side only.
//   - Exactly THREE network commands: hello, pull, push. Nothing else exists.
//     No signup endpoint (accounts are provisioned on the box via CLI), no
//     static files, no directory listing, no GET UI. Anything unknown → 404.
//   - Dumb server, smart client: the server never merges, never interprets
//     data beyond validation. Clients pull → merge locally → push. Nothing
//     to break server-side.
//   - Not payload-exploitable: bearer tokens (only sha256 stored at rest),
//     constant-time compare, per-IP auth-failure lockout, streaming size
//     caps, strict audio-name whitelist (no path traversal possible), JSON
//     schema sanity, atomic writes. No eval, no exec, no shell, ever.
//   - Never root: refuses to start as root unless --allow-root (for odd
//     container setups). Designed for a plain unprivileged user + systemd
//     or a reverse proxy (nginx/apache with the SSL you already manage).
//     Direct TLS also supported via --cert/--key.
//
// Usage:
//   node bns-server.mjs serve [--port 8787] [--bind 0.0.0.0] [--data-dir ./bns-data]
//                             [--cert cert.pem --key key.pem] [--allow-root]
//   node bns-server.mjs adduser <name>       # prints the token ONCE
//   node bns-server.mjs removeuser <name>
//   node bns-server.mjs listusers
//   node bns-server.mjs stats                # disk usage per account (ops)
//
// Production home: Ubuntu VPS (Germany, 100GB) — see server/deploy/ for the
// hardened systemd unit (binds 127.0.0.1 behind nginx SSL) and setup script.
//
// API (all POST, JSON, Authorization: Bearer <token>):
//   /v1/hello -> { ok, user, revision, audio:[names], serverTime, version }
//   /v1/pull  body { have:[audioNames] }
//             -> { ok, revision, data|null, audio:{ name: base64 } (only missing) }
//   /v1/push  body { data:{...}, audio:{ name: base64 } (only new) }
//             -> { ok, revision }

import http from 'node:http';
import https from 'node:https';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { promises as fs } from 'node:fs';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const VERSION = '0.12a';
const MAX_BODY_BYTES = 200 * 1024 * 1024;   // whole request hard cap
const MAX_DATA_BYTES = 20 * 1024 * 1024;    // data.json cap
const MAX_AUDIO_BYTES = 25 * 1024 * 1024;   // per voice note cap
const AUDIO_NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}\.(m4a|wav|aac|ogg)$/;
const AUTH_FAIL_LIMIT = 10;                 // failures per window per IP
const AUTH_FAIL_WINDOW_MS = 15 * 60 * 1000;

// ---------------------------------------------------------------- helpers
const sha256hex = (s) => createHash('sha256').update(s).digest('hex');

function argValue(args, flag, dflt) {
  const i = args.indexOf(flag);
  return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : dflt;
}

async function atomicWrite(file, bytes) {
  const tmp = file + '.tmp';
  await fs.writeFile(tmp, bytes);
  await fs.rename(tmp, file); // atomic on same filesystem
}

function safeEqualHex(aHex, bHex) {
  const a = Buffer.from(aHex, 'hex');
  const b = Buffer.from(bHex, 'hex');
  return a.length === b.length && timingSafeEqual(a, b);
}

// ---------------------------------------------------------------- users
class Users {
  constructor(dataDir) {
    this.file = path.join(dataDir, 'users.json');
    this.map = {}; // name -> { tokenHash, createdAt }
  }
  async load() {
    try { this.map = JSON.parse(await fs.readFile(this.file, 'utf8')); }
    catch { this.map = {}; }
  }
  async save() {
    await fs.mkdir(path.dirname(this.file), { recursive: true });
    await atomicWrite(this.file, JSON.stringify(this.map, null, 2));
  }
  /** token -> user name, or null. Constant-time against each stored hash. */
  authenticate(token) {
    if (typeof token !== 'string' || token.length < 32 || token.length > 128) return null;
    const hash = sha256hex(token);
    for (const [name, u] of Object.entries(this.map)) {
      if (u.tokenHash && safeEqualHex(u.tokenHash, hash)) return name;
    }
    return null;
  }
}

// ---------------------------------------------------------------- storage
class Storage {
  constructor(dataDir, quotaBytes = 0) {
    this.root = dataDir;
    this.quotaBytes = quotaBytes; // 0 = unlimited
  }

  async dirSize(dir) {
    let total = 0;
    let files = [];
    try { files = await fs.readdir(dir, { withFileTypes: true }); } catch { return 0; }
    for (const f of files) {
      const p = path.join(dir, f.name);
      total += f.isDirectory() ? await this.dirSize(p) : (await fs.stat(p)).size;
    }
    return total;
  }

  userDir(user) {
    // user names come from OUR users.json (CLI-provisioned), but sanitize
    // anyway — defense in depth.
    const safe = user.replace(/[^A-Za-z0-9._-]/g, '_');
    return path.join(this.root, 'users', safe);
  }

  async meta(user) {
    try { return JSON.parse(await fs.readFile(path.join(this.userDir(user), 'meta.json'), 'utf8')); }
    catch { return { revision: 0, updatedAt: null }; }
  }

  async readData(user) {
    try { return await fs.readFile(path.join(this.userDir(user), 'data.json'), 'utf8'); }
    catch { return null; }
  }

  async audioNames(user) {
    try { return (await fs.readdir(path.join(this.userDir(user), 'audio'))).filter(n => AUDIO_NAME_RE.test(n)); }
    catch { return []; }
  }

  async readAudio(user, name) {
    if (!AUDIO_NAME_RE.test(name)) return null;
    try { return await fs.readFile(path.join(this.userDir(user), 'audio', name)); }
    catch { return null; }
  }

  async writePush(user, dataJsonString, audioMap) {
    const dir = this.userDir(user);
    const audioDir = path.join(dir, 'audio');
    await fs.mkdir(audioDir, { recursive: true });
    // Fixed-disk protection (100GB VPS): one account can never eat the box.
    if (this.quotaBytes > 0) {
      const incoming = Buffer.byteLength(dataJsonString) +
        audioMap.reduce((n, [, b]) => n + b.length, 0);
      if (await this.dirSize(dir) + incoming > this.quotaBytes) {
        const err = new Error('account storage is full — old items prune on the device; sync again after');
        err.quota = true;
        throw err;
      }
    }
    // audio first, data last — a crash mid-push leaves extra audio at worst,
    // never a data.json that references missing state.
    for (const [name, bytes] of audioMap) {
      await atomicWrite(path.join(audioDir, name), bytes);
    }
    await atomicWrite(path.join(dir, 'data.json'), dataJsonString);
    const meta = await this.meta(user);
    const next = { revision: (meta.revision || 0) + 1, updatedAt: new Date().toISOString() };
    await atomicWrite(path.join(dir, 'meta.json'), JSON.stringify(next));
    return next.revision;
  }
}

// ---------------------------------------------------------------- validation
/** The only payload the server accepts: a BNS data snapshot. */
function validateDataShape(data) {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    return 'data must be a JSON object';
  }
  for (const key of ['routines', 'events', 'captures', 'completionLogs']) {
    if (key in data && !Array.isArray(data[key])) return `${key} must be an array`;
  }
  if ('settings' in data && (typeof data.settings !== 'object' || data.settings === null)) {
    return 'settings must be an object';
  }
  const hasAny = ['routines', 'events', 'captures', 'completionLogs', 'settings']
    .some(k => k in data);
  if (!hasAny) return 'not a BNS snapshot';
  return null;
}

function validateAudioEntry(name, b64) {
  if (!AUDIO_NAME_RE.test(name)) return `audio name rejected: ${name}`;
  if (typeof b64 !== 'string') return 'audio must be base64 strings';
  if (b64.length > Math.ceil(MAX_AUDIO_BYTES * 4 / 3) + 4) return `audio too large: ${name}`;
  return null;
}

// ---------------------------------------------------------------- server
function makeServer(users, storage) {
  const authFails = new Map(); // ip -> { count, resetAt }
  const busy = new Set();      // per-user push lock

  function blocked(ip) {
    const f = authFails.get(ip);
    if (!f) return false;
    if (Date.now() > f.resetAt) { authFails.delete(ip); return false; }
    return f.count >= AUTH_FAIL_LIMIT;
  }
  function noteFail(ip) {
    const f = authFails.get(ip) || { count: 0, resetAt: Date.now() + AUTH_FAIL_WINDOW_MS };
    f.count++;
    authFails.set(ip, f);
  }

  function reply(res, code, obj) {
    const body = JSON.stringify(obj);
    res.writeHead(code, {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Length': Buffer.byteLength(body),
      'X-Content-Type-Options': 'nosniff',
      'Cache-Control': 'no-store',
    });
    res.end(body);
  }

  return async function handle(req, res) {
    const ip = req.socket.remoteAddress || '?';
    try {
      const url = (req.url || '').split('?')[0];
      const routes = new Set(['/v1/hello', '/v1/pull', '/v1/push']);
      if (req.method !== 'POST' || !routes.has(url)) {
        return reply(res, 404, { ok: false, error: 'nope' });
      }
      if (blocked(ip)) {
        return reply(res, 429, { ok: false, error: 'too many failed attempts, wait a bit' });
      }

      // --- auth before reading any body
      const auth = req.headers.authorization || '';
      const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
      const user = users.authenticate(token);
      if (!user) {
        noteFail(ip);
        return reply(res, 401, { ok: false, error: 'unauthorized' });
      }

      // --- read body with a streaming hard cap
      const chunks = [];
      let size = 0;
      const body = await new Promise((resolve, reject) => {
        req.on('data', (c) => {
          size += c.length;
          if (size > MAX_BODY_BYTES) { req.destroy(); reject(new Error('too large')); return; }
          chunks.push(c);
        });
        req.on('end', () => resolve(Buffer.concat(chunks)));
        req.on('error', reject);
      }).catch(() => null);
      if (body === null) return reply(res, 413, { ok: false, error: 'request too large' });

      let payload = {};
      if (body.length) {
        try { payload = JSON.parse(body.toString('utf8')); }
        catch { return reply(res, 400, { ok: false, error: 'bad json' }); }
      }
      if (typeof payload !== 'object' || payload === null) {
        return reply(res, 400, { ok: false, error: 'bad json' });
      }

      // ---------- /v1/hello
      if (url === '/v1/hello') {
        const meta = await storage.meta(user);
        return reply(res, 200, {
          ok: true, user, version: VERSION,
          revision: meta.revision, updatedAt: meta.updatedAt,
          audio: await storage.audioNames(user),
          serverTime: new Date().toISOString(),
        });
      }

      // ---------- /v1/pull
      if (url === '/v1/pull') {
        const have = new Set(Array.isArray(payload.have)
          ? payload.have.filter(n => typeof n === 'string') : []);
        const meta = await storage.meta(user);
        const dataStr = await storage.readData(user);
        const audio = {};
        for (const name of await storage.audioNames(user)) {
          if (have.has(name)) continue;
          const bytes = await storage.readAudio(user, name);
          if (bytes) audio[name] = bytes.toString('base64');
        }
        return reply(res, 200, {
          ok: true, revision: meta.revision,
          data: dataStr === null ? null : JSON.parse(dataStr),
          audio,
        });
      }

      // ---------- /v1/push
      if (url === '/v1/push') {
        if (busy.has(user)) return reply(res, 409, { ok: false, error: 'another sync is in progress' });
        busy.add(user);
        try {
          const err = validateDataShape(payload.data);
          if (err) return reply(res, 400, { ok: false, error: err });
          const dataStr = JSON.stringify(payload.data);
          if (Buffer.byteLength(dataStr) > MAX_DATA_BYTES) {
            return reply(res, 413, { ok: false, error: 'data too large' });
          }
          const audioMap = [];
          const audioObj = (typeof payload.audio === 'object' && payload.audio !== null)
            ? payload.audio : {};
          for (const [name, b64] of Object.entries(audioObj)) {
            const aerr = validateAudioEntry(name, b64);
            if (aerr) return reply(res, 400, { ok: false, error: aerr });
            const bytes = Buffer.from(b64, 'base64');
            if (bytes.length > MAX_AUDIO_BYTES) {
              return reply(res, 413, { ok: false, error: `audio too large: ${name}` });
            }
            audioMap.push([name, bytes]);
          }
          let revision;
          try {
            revision = await storage.writePush(user, dataStr, audioMap);
          } catch (e) {
            if (e.quota) return reply(res, 413, { ok: false, error: e.message });
            throw e;
          }
          console.log(`[push] ${user}: rev ${revision}, ${audioMap.length} new audio, ${Buffer.byteLength(dataStr)} bytes data`);
          return reply(res, 200, { ok: true, revision });
        } finally {
          busy.delete(user);
        }
      }
    } catch (e) {
      console.error('[error]', e.message);
      try { reply(res, 500, { ok: false, error: 'server error' }); } catch { /* closed */ }
    }
  };
}

// ---------------------------------------------------------------- CLI
async function main() {
  const [, , cmd = 'serve', ...args] = process.argv;
  const dataDir = path.resolve(argValue(args, '--data-dir',
    argValue(process.argv, '--data-dir', './bns-data')));
  const users = new Users(dataDir);
  await users.load();

  if (cmd === 'adduser') {
    const name = args.find(a => !a.startsWith('--'));
    if (!name || !/^[A-Za-z0-9._-]{2,40}$/.test(name)) {
      console.error('usage: adduser <name>   (letters/digits/._- only)');
      process.exit(2);
    }
    if (users.map[name]) { console.error(`user "${name}" already exists`); process.exit(1); }
    const token = randomBytes(32).toString('hex');
    users.map[name] = { tokenHash: sha256hex(token), createdAt: new Date().toISOString() };
    await users.save();
    console.log(`user "${name}" created.`);
    console.log('');
    console.log(`  TOKEN (shown once, save it now): ${token}`);
    console.log('');
    console.log('The server stores only its hash — this token cannot be recovered.');
    return;
  }
  if (cmd === 'removeuser') {
    const name = args.find(a => !a.startsWith('--'));
    if (!name || !users.map[name]) { console.error('no such user'); process.exit(1); }
    delete users.map[name];
    await users.save();
    console.log(`user "${name}" removed (their data folder is kept; delete manually if wanted).`);
    return;
  }
  if (cmd === 'listusers') {
    for (const [name, u] of Object.entries(users.map)) {
      console.log(`${name}\tcreated ${u.createdAt}`);
    }
    if (!Object.keys(users.map).length) console.log('(no users yet — adduser <name>)');
    return;
  }
  if (cmd === 'stats') {
    // Ops view for the 100GB question: how much disk does each account use.
    const usersRoot = path.join(dataDir, 'users');
    let entries = [];
    try { entries = await fs.readdir(usersRoot); } catch { /* none yet */ }
    const storage = new Storage(dataDir);
    const mb = (n) => (n / 1024 / 1024).toFixed(1).padStart(9) + ' MB';
    let grand = 0;
    for (const name of entries.sort()) {
      const size = await storage.dirSize(path.join(usersRoot, name));
      grand += size;
      const meta = await storage.meta(name);
      console.log(`${mb(size)}  ${name}  (rev ${meta.revision}, updated ${meta.updatedAt ?? 'never'})`);
    }
    console.log(`${mb(grand)}  TOTAL across ${entries.length} account(s)`);
    return;
  }
  if (cmd !== 'serve') {
    console.error('commands: serve | adduser <name> | removeuser <name> | listusers');
    process.exit(2);
  }

  // ------- serve
  if (typeof process.getuid === 'function' && process.getuid() === 0 &&
      !args.includes('--allow-root')) {
    console.error('Refusing to run as root. Use a normal user (or --allow-root if you truly must).');
    process.exit(1);
  }
  const port = parseInt(argValue(args, '--port', '8787'), 10);
  // Behind nginx (the VPS pattern) bind 127.0.0.1 so ONLY the proxy can
  // reach the process; default stays 0.0.0.0 for LAN testing at home.
  const bind = argValue(args, '--bind', '0.0.0.0');
  const certPath = argValue(args, '--cert', null);
  const keyPath = argValue(args, '--key', null);
  const quotaMb = parseInt(argValue(args, '--quota-mb', '0'), 10);
  const storage = new Storage(dataDir, quotaMb > 0 ? quotaMb * 1024 * 1024 : 0);
  await fs.mkdir(dataDir, { recursive: true });

  const handler = makeServer(users, storage);
  const server = (certPath && keyPath)
    ? https.createServer({ cert: readFileSync(certPath), key: readFileSync(keyPath) }, handler)
    : http.createServer(handler);

  server.listen(port, bind, () => {
    const mode = certPath ? 'https (direct TLS)' : 'http (put nginx/apache SSL in front for the internet)';
    console.log(`BNS sync server ${VERSION} on ${bind}:${port} — ${mode}`);
    console.log(`data dir: ${dataDir}`);
    console.log('commands: POST /v1/hello /v1/pull /v1/push — everything else is a 404.');
  });

  const shutdown = () => { console.log('bye'); server.close(() => process.exit(0)); };
  process.on('SIGINT', shutdown);   // the promised Ctrl+C
  process.on('SIGTERM', shutdown);
}

// Only act as a program when executed directly — importing this file (tests,
// tooling) must never start a server or touch the disk.
import { pathToFileURL } from 'node:url';
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => { console.error(e); process.exit(1); });
}

export { makeServer, Users, Storage, validateDataShape, AUDIO_NAME_RE };
