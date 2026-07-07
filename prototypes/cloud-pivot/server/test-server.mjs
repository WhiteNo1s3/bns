// Headless test for bns-server.mjs — happy path + the attacks it must shrug off.
// Run: node server/test-server.mjs
import { makeServer, Users, Storage, validateDataShape } from './bns-server.mjs';
import http from 'node:http';
import { promises as fs } from 'node:fs';
import { createHash, randomBytes } from 'node:crypto';
import os from 'node:os';
import path from 'node:path';

let failures = 0;
const check = (name, cond) => {
  console.log((cond ? 'PASS' : 'FAIL') + '  ' + name);
  if (!cond) failures++;
};

const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'bns-server-test-'));
const users = new Users(tmp);
const token = randomBytes(32).toString('hex');
users.map['ben'] = {
  tokenHash: createHash('sha256').update(token).digest('hex'),
  createdAt: new Date().toISOString(),
};
const storage = new Storage(tmp);
const server = http.createServer(makeServer(users, storage));
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

async function call(cmd, body, tok = token) {
  const res = await fetch(`http://127.0.0.1:${port}${cmd}`, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${tok}`, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, json: await res.json().catch(() => null) };
}

// --- auth surface
check('wrong token -> 401', (await call('/v1/hello', {}, 'f'.repeat(64))).status === 401);
check('no token -> 401', (await fetch(`http://127.0.0.1:${port}/v1/hello`, { method: 'POST' })).status === 401);
check('unknown route -> 404', (await call('/v1/steal', {})).status === 404);
check('GET -> 404 (POST only)', (await fetch(`http://127.0.0.1:${port}/v1/hello`)).status === 404);

// --- hello on empty account
const hello1 = await call('/v1/hello', {});
check('hello ok, revision 0, no audio', hello1.status === 200 &&
  hello1.json.revision === 0 && hello1.json.audio.length === 0);

// --- pull on empty account
const pull1 = await call('/v1/pull', { have: [] });
check('pull on empty account -> data null', pull1.status === 200 && pull1.json.data === null);

// --- push a snapshot with one voice note
const audioBytes = randomBytes(4096);
const snapshot = {
  routines: [{ id: 'r1', title: 'Meds', recurrenceType: 'daily', updatedAt: '2026-07-06T10:00:00Z' }],
  events: [], captures: [{ id: 'c1', at: '2026-07-06T10:00:00Z', text: 'hi', audioPath: 'audio/cap_1.m4a' }],
  completionLogs: [], settings: { deviceId: 'd1', deviceName: 'PC' },
};
const push1 = await call('/v1/push', { data: snapshot, audio: { 'cap_1.m4a': audioBytes.toString('base64') } });
check('push accepted -> revision 1', push1.status === 200 && push1.json.revision === 1);

// --- hello/pull reflect the push
const hello2 = await call('/v1/hello', {});
check('hello shows revision 1 + audio listed', hello2.json.revision === 1 &&
  hello2.json.audio.includes('cap_1.m4a'));
const pull2 = await call('/v1/pull', { have: [] });
check('pull returns data + audio bytes', pull2.json.data.routines[0].title === 'Meds' &&
  Buffer.from(pull2.json.audio['cap_1.m4a'], 'base64').equals(audioBytes));
const pull3 = await call('/v1/pull', { have: ['cap_1.m4a'] });
check('pull skips audio the client already has', !('cap_1.m4a' in pull3.json.audio));

// --- attacks on push
check('path traversal audio name rejected',
  (await call('/v1/push', { data: snapshot, audio: { '../../etc/passwd.m4a': 'QUJD' } })).status === 400);
check('backslash traversal rejected',
  (await call('/v1/push', { data: snapshot, audio: { '..\\boot.m4a': 'QUJD' } })).status === 400);
check('wrong extension rejected',
  (await call('/v1/push', { data: snapshot, audio: { 'evil.exe': 'QUJD' } })).status === 400);
check('non-snapshot data rejected',
  (await call('/v1/push', { data: { hack: true } })).status === 400);
check('array data rejected',
  (await call('/v1/push', { data: [1, 2, 3] })).status === 400);
check('garbage body rejected', (await (async () => {
  const res = await fetch(`http://127.0.0.1:${port}/v1/push`, {
    method: 'POST', headers: { 'Authorization': `Bearer ${token}` }, body: 'not json{{{',
  });
  return res.status;
})()) === 400);

// traversal check on disk: nothing escaped the user dir
const escaped = await fs.readdir(tmp);
check('nothing written outside users/', escaped.every(n => ['users', 'users.json'].includes(n)));

// --- revision increments, data replaced
const push2 = await call('/v1/push', { data: { ...snapshot, events: [{ id: 'e1', title: 'Doc', date: '2026-07-15' }] }, audio: {} });
check('second push -> revision 2', push2.json.revision === 2);
const pull4 = await call('/v1/pull', { have: ['cap_1.m4a'] });
check('pull sees the new event, audio persisted', pull4.json.revision === 2 &&
  pull4.json.data.events.length === 1 && hello2.json.audio.includes('cap_1.m4a'));

// --- auth lockout after repeated failures
for (let i = 0; i < 10; i++) await call('/v1/hello', {}, 'e'.repeat(64));
const locked = await call('/v1/hello', {}, 'e'.repeat(64));
check('IP locked out after repeated bad tokens -> 429', locked.status === 429);

// --- quota: an account can never exceed its cap
{
  const qTmp = await fs.mkdtemp(path.join(os.tmpdir(), 'bns-quota-test-'));
  const qStorage = new (Storage)(qTmp, 8 * 1024); // 8KB quota
  const qServer = http.createServer(makeServer(users, qStorage));
  await new Promise(r => qServer.listen(0, '127.0.0.1', r));
  const qPort = qServer.address().port;
  const qCall = (cmd, body) => fetch(`http://127.0.0.1:${qPort}${cmd}`, {
    method: 'POST', headers: { 'Authorization': `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  const small = await qCall('/v1/push', { data: { settings: {} }, audio: {} });
  check('quota: small push fits', small.status === 200);
  const big = await qCall('/v1/push', {
    data: { settings: {} },
    audio: { 'big.m4a': randomBytes(16 * 1024).toString('base64') },
  });
  check('quota: oversized account refused with 413', big.status === 413);
  qServer.close();
  await fs.rm(qTmp, { recursive: true, force: true });
}

// --- validateDataShape unit checks
check('shape: null rejected', validateDataShape(null) !== null);
check('shape: settings-only accepted', validateDataShape({ settings: {} }) === null);
check('shape: routines must be array', validateDataShape({ routines: 'x' }) !== null);

server.close();
await fs.rm(tmp, { recursive: true, force: true });
console.log(failures ? `\n${failures} FAILURES` : '\nall green');
process.exit(failures ? 1 : 0);
