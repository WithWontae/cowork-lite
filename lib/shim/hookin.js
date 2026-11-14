// hook 입력(stdin의 JSON)에서 Guard에 필요한 필드를 한 번에 꺼낸다. Node를 필드마다 띄우면 Windows에서 매우 느리다.
// 출력: 필드마다 `<1|0>\0<값>\0` (1=문자열로 있음, 0=없음). 순서는 아래 FIELDS와 같다.
// 입력이 비었거나 JSON이 아니면 아무것도 쓰지 않고 종료 코드 1(Guard가 fail-closed로 막는다).
'use strict';
const fs = require('fs');

const FIELDS = [
  ['tool_name'],
  ['cwd'],
  ['tool_input', 'command'],
  ['tool_input', 'file_path'],
  ['tool_input', 'notebook_path'],
];

let doc;
try {
  let text = fs.readFileSync(0, 'utf8');
  if (text.charCodeAt(0) === 0xFEFF) text = text.slice(1);
  doc = JSON.parse(text);
} catch (e) { process.exit(1); }
if (doc === null || typeof doc !== 'object' || Array.isArray(doc)) process.exit(1);

let out = '';
for (const path of FIELDS) {
  let v = doc;
  for (const k of path) {
    v = (v !== null && typeof v === 'object' && !Array.isArray(v) && Object.prototype.hasOwnProperty.call(v, k)) ? v[k] : undefined;
  }
  // NUL이 값에 들어 있으면 구분자와 섞이므로 읽을 수 없는 입력으로 보고 막는다.
  if (typeof v === 'string') {
    if (v.indexOf('\0') !== -1) process.exit(1);
    out += '1\0' + v + '\0';
  } else if (typeof v === 'number' || typeof v === 'boolean') {
    out += '1\0' + String(v) + '\0';
  } else {
    out += '0\0\0';
  }
}
process.stdout.write(out, 'utf8');
