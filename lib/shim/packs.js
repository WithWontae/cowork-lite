// packs.json 의 기본팩 목록을 탭으로 나눈 줄로 출력한다. plutil 을 필드마다 부르면 Windows 에서 node 를 수십 번 띄워 매우 느리다.
// 출력: 팩마다 `P<TAB>id<TAB>title` 한 줄, 이어서 설치 단계마다 한 줄.
//   run:           `S<TAB>run<TAB>인자1<TAB>인자2…` ("optional": true 이면 run 대신 run-optional: 실패해도 경고만 하고 계속)
//   remote-script: `S<TAB>remote-script<TAB>windows_url<TAB>unix_url<TAB>provides(없으면 -)` (provides: 설치 뒤 생기는 명령 이름. 이미 있으면 건너뛴다)
// 이어서 점검 명령마다 `V` 줄(아래 참고).
// 파일을 읽을 수 없거나 형식이 틀리면 아무것도 쓰지 않고 종료 코드 1. 탭·줄바꿈이 들어 있는 값은 형식 오류로 본다.
'use strict';
const fs = require('fs');
let doc;
try {
  let text = fs.readFileSync(process.argv[2], 'utf8');
  if (text.charCodeAt(0) === 0xFEFF) text = text.slice(1);
  doc = JSON.parse(text);
} catch (e) { process.exit(1); }
if (!doc || !Array.isArray(doc.packs)) process.exit(1);
const bad = (s) => typeof s !== 'string' || /[\t\r\n]/.test(s);
let out = '';
for (const p of doc.packs) {
  if (!p || bad(p.id) || bad(p.title) || !Array.isArray(p.install)) process.exit(1);
  out += 'P\t' + p.id + '\t' + p.title + '\n';
  for (const s of p.install) {
    if (s && s.type === 'run' && Array.isArray(s.argv) && s.argv.length > 0 && !s.argv.some(bad)) {
      out += (s.optional === true ? 'S\trun-optional\t' : 'S\trun\t') + s.argv.join('\t') + '\n';
    } else if (s && s.type === 'remote-script' && !bad(s.windows_url) && !bad(s.unix_url) && (s.provides === undefined || (!bad(s.provides) && s.provides !== ''))) {
      out += 'S\tremote-script\t' + s.windows_url + '\t' + s.unix_url + '\t' + (s.provides === undefined ? '-' : s.provides) + '\n';
    } else { process.exit(1); }
  }
  // 점검 명령: `V<TAB>검증여부(1|0)<TAB>expect(없으면 -)<TAB>인자1<TAB>인자2…`
  for (const v of (Array.isArray(p.verify) ? p.verify : [])) {
    const ex = v && v.expect !== undefined ? v.expect : '-';
    if (!v || v.type !== 'run' || !Array.isArray(v.argv) || v.argv.length === 0 || v.argv.some(bad) || bad(ex) || ex === '') process.exit(1);
    out += 'V\t' + (v.verified === true ? '1' : '0') + '\t' + ex + '\t' + v.argv.join('\t') + '\n';
  }
}
process.stdout.write(out, 'utf8');
