// Windows/Linux용 plutil 호환 shim. cowork-lite가 쓰는 JSON 부분집합만 구현한다.
//   plutil -convert json -o <out> <file>
//   plutil -extract <keypath> raw|json -o <out> <file|->
//   plutil <-insert|-replace> <keypath> <-string|-json|-integer|-bool|-float> <값> [-append] -o <out> <file>
//   plutil -remove <keypath> -o <out> <file>
// keypath는 점으로 구분하고, 숫자 조각은 배열 인덱스다. 오류는 종료 코드 1.
'use strict';
const fs = require('fs');
const os = require('os');

function fail(msg) { process.stderr.write('plutil: ' + msg + '\n'); process.exit(1); }

// Git Bash가 넘긴 POSIX 경로를 Windows 경로로 바꾼다(bash 쪽에서 cygpath를 부르면 프로세스가 둘 늘어 느리다).
// `/c/x`→`C:\x`, `/tmp/x`→`%TEMP%\x`, `/dev/null`→NUL. 그 밖의 경로(상대·`C:\`)는 그대로 둔다.
function toWin(p) {
  if (p === '-' || p === null || p === undefined) return p;
  if (p === '/dev/null') return os.devNull;
  if (process.platform !== 'win32') return p;
  let m = /^\/([a-zA-Z])(\/.*)?$/.exec(p);
  if (m) return m[1].toUpperCase() + ':' + (m[2] || '/');
  if (p === '/tmp' || p.startsWith('/tmp/')) return os.tmpdir() + p.slice(4);
  return p;
}
function outPath(p) { return toWin(p); }
function readInput(p) { return p === '-' ? fs.readFileSync(0, 'utf8') : fs.readFileSync(toWin(p), 'utf8'); }
function parse(text) {
  if (text.charCodeAt(0) === 0xFEFF) text = text.slice(1);
  try { return JSON.parse(text); } catch (e) { fail('JSON을 읽지 못했습니다'); }
}
function write(p, text) {
  if (p === '-') process.stdout.write(text);
  else fs.writeFileSync(outPath(p), text, 'utf8');
}

const segs = (kp) => kp.split('.');
const isIdx = (s) => /^[0-9]+$/.test(s);

// 부모 컨테이너와 마지막 조각을 돌려준다. 중간 경로가 없으면 오류.
function locate(root, kp) {
  const parts = segs(kp);
  let cur = root;
  for (let i = 0; i < parts.length - 1; i++) {
    const s = parts[i];
    if (cur === null || typeof cur !== 'object') fail('경로가 없습니다: ' + kp);
    cur = Array.isArray(cur) ? (isIdx(s) ? cur[Number(s)] : undefined) : cur[s];
    if (cur === undefined) fail('경로가 없습니다: ' + kp);
  }
  return { parent: cur, key: parts[parts.length - 1] };
}
function has(parent, key) {
  if (parent === null || typeof parent !== 'object') return false;
  return Array.isArray(parent) ? (isIdx(key) && Number(key) < parent.length) : Object.prototype.hasOwnProperty.call(parent, key);
}
function get(root, kp) {
  const { parent, key } = locate(root, kp);
  if (!has(parent, key)) fail('경로가 없습니다: ' + kp);
  return Array.isArray(parent) ? parent[Number(key)] : parent[key];
}

function typed(type, raw) {
  switch (type) {
    case '-string': return raw;
    case '-json': try { return JSON.parse(raw); } catch (e) { fail('-json 값이 올바르지 않습니다'); }
    case '-integer': return parseInt(raw, 10);
    case '-float': return parseFloat(raw);
    case '-bool': return raw === 'true' || raw === 'YES' || raw === '1';
    default: fail('지원하지 않는 값 형식: ' + type);
  }
}

const argv = process.argv.slice(2);
let out = null, file = null, op = null, kp = null, fmt = null, type = null, val = null, append = false;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '-o') out = argv[++i];
  else if (a === '-convert') { op = 'convert'; fmt = argv[++i]; }
  else if (a === '-extract') { op = 'extract'; kp = argv[++i]; fmt = argv[++i]; }
  else if (a === '-insert' || a === '-replace') { op = a.slice(1); kp = argv[++i]; type = argv[++i]; val = argv[++i]; }
  else if (a === '-remove') { op = 'remove'; kp = argv[++i]; }
  else if (a === '-append') append = true;
  else file = a;
}
if (!op || file === null) fail('사용법이 올바르지 않습니다');
if (op === 'convert' && fmt !== 'json') fail('json 변환만 지원합니다');

const root = parse(readInput(file));

if (op === 'convert') {
  write(out === null ? '-' : out, JSON.stringify(root) + '\n');
  process.exit(0);
}

if (op === 'extract') {
  const v = get(root, kp);
  let text;
  if (fmt === 'json') text = JSON.stringify(v);
  else if (fmt === 'raw') {
    if (typeof v === 'string') text = v;
    else if (Array.isArray(v)) text = String(v.length);
    else if (v !== null && typeof v === 'object') text = String(Object.keys(v).length);
    else text = String(v);
  } else fail('지원하지 않는 출력 형식: ' + fmt);
  write(out === null ? '-' : out, text + '\n');
  process.exit(0);
}

const { parent, key } = locate(root, kp);
if (parent === null || typeof parent !== 'object') fail('경로가 없습니다: ' + kp);

if (op === 'remove') {
  if (!has(parent, key)) fail('경로가 없습니다: ' + kp);
  if (Array.isArray(parent)) parent.splice(Number(key), 1); else delete parent[key];
} else {
  const v = typed(type, val);
  const exists = has(parent, key);
  if (op === 'replace') {
    if (!exists) fail('바꿀 경로가 없습니다: ' + kp);
    if (Array.isArray(parent)) parent[Number(key)] = v; else parent[key] = v;
  } else { // insert
    if (append) {
      if (!exists) fail('배열이 없습니다: ' + kp);
      const arr = Array.isArray(parent) ? parent[Number(key)] : parent[key];
      if (!Array.isArray(arr)) fail('배열이 아닙니다: ' + kp);
      arr.push(v);
    } else {
      if (exists) fail('이미 있는 경로입니다: ' + kp);
      if (Array.isArray(parent)) parent.splice(isIdx(key) ? Number(key) : parent.length, 0, v); else parent[key] = v;
    }
  }
}
write(out === null ? file : out, JSON.stringify(root, null, 2) + '\n');
