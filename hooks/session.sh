#!/bin/bash
# cowork-lite SessionStart hook: 세션 시작 시 stdout이 Claude의 규칙(맥락)으로 주입된다.
# dirname·cd·pwd 서브셸 대신 문자열 치환만 쓴다(Windows에서 프로세스 하나가 40ms 안팎). 상대 경로로 불려도 절대 경로가 된다.
HERE="${BASH_SOURCE[0]%/*}"; [ "$HERE" = "${BASH_SOURCE[0]}" ] && HERE="."; [[ "$HERE" == /* || "$HERE" == [A-Za-z]:* ]] || HERE="$PWD/$HERE"
if ! source "$HERE/../lib/common.sh" 2>/dev/null; then
  echo "[cowork-lite] 설치 파일을 찾을 수 없습니다. 사용자에게 cowork-lite setup 을 다시 실행하도록 안내하세요."
  exit 0
fi
version="$(cat "$HERE/../VERSION" 2>/dev/null || echo dev)"
root="$(cl_space_root)"

echo "[cowork-lite] 버전=$version 작업폴더=$root"
if [ ! -d "$root" ]; then
  echo "작업 폴더가 아직 없습니다. 사용자에게 터미널에서 cowork-lite setup 을 실행하도록 안내하세요."
fi
cat <<EOF
규칙:
- 응답·문서·메모는 한국어 쉬운 말로 쓴다. 개발 용어는 풀어서 설명한다.
- 만든 결과물은 항상 작업 폴더 안($root)에 저장한다.
- 원본은 받은자료에 있다. 받은자료는 수정하지 말고, 작업중 폴더로 복사해서 작업한다.
- 파일을 지울 때는 cowork-lite space rm --yes-bulk <경로> 를 쓴다. 사용자에게 확인 창이 뜨고, 승인하면 휴지통으로 옮긴다. rm 으로 직접 지우는 것은 차단된다.
- 업무는 폴더 하나다: 작업중/<번호>_<업무이름>/. 파일은 그 업무 폴더 안에서만 만들고 고치고 지운다.
- 사용자가 "업무 시작"이라고 하면 cowork-lite task list --raw 로 진행 중인 업무를 가져와 AskUserQuestion 으로 보여 주고, 선택지의 맨 아래에 "새로운 업무 시작"을 붙인다. 새 업무면 이름을 물어 cowork-lite task new "<이름>" 을 실행하고, 기존 업무를 고르면 그 폴더(cowork-lite task path <번호>)에서 이어서 일한다.
- 사용자가 "업무 완료"라고 하면 어느 업무인지 확인한 뒤 cowork-lite task done <번호> 로 업무 폴더를 통째로 결과물로 옮긴다(직접 mv 하지 않는다).
- 사용자가 완료한 업무를 다시 하자고 하면 cowork-lite task list --done --raw 로 보여 주고 고른 것을 cowork-lite task reopen <번호> 로 작업중에 다시 가져온다.
- 하루 기록은 업무일지/년-월/년-월-일.md 에 남기며, 직접 쓰지 말고 아래 "세션 정리해" 명령을 쓴다.
- 비밀번호·인증서·주민번호·계좌 같은 민감정보는 기억하거나 기록하지 않는다.
- 사용자가 "세션 정리해"라고 하면 ai-memory 의 인수인계(memory_handoff_begin)로 이번 세션의 한 일·결정·남은 일을 저장한다. 민감정보는 넣지 않고, 저장 후 무엇을 저장했는지 짧게 알린다. 이어서 cowork-lite session save "<한 일·결정·남은 일을 쉬운 말로 요약한 내용>" 을 실행한다. 업무일지에 덧붙이고, 동기화를 켰다면 바로 동기화까지 하며, 실패하면 이유를 그대로 알린다.

답변 방식:
- 핵심만 잘 정리해서 답한다. 불필요한 설명, 반복 설명, 장황한 배경 설명은 쓰지 않는다.
- 확실하지 않은 정보는 "불확실하다"고 분명히 알린다. 추측을 사실처럼 말하지 않는다.
- 요청하지 않은 범위까지 확장하지 않는다. 시킨 것만 한다.
- 답변 맨 아래에는 사용자가 답하거나 결정해야 할 것만 핵심으로 요약한다. 결정할 것이 있으면 AskUserQuestion 도구로 선택지(선택 UI)를 만들어 쉽게 고르게 한다. 이 도구를 쓸 수 없으면 번호 목록으로 대신한다. 결정할 것이 없으면 이 부분은 쓰지 않는다.
EOF
# 온보딩(내 업무 설정)을 아직 하지 않았으면 안내하게 한다. 파일 존재만 본다(가볍다). 한 번 하거나 건너뛰면(onboarding.json 이 생기면) 더 이상 말하지 않는다.
if [ -d "$root" ] && [ ! -f "$root/.cowork/onboarding.json" ]; then
  cat <<EOF

[온보딩 안내] 이 사용자는 아직 '온보딩'(내 업무에 맞게 설정하는 질문)을 하지 않았다.
- 첫 응답의 맨 앞에 한 줄로만 알린다: "처음이시네요. '온보딩'이라고 보내시면 내 업무에 맞게 설정해 드려요. (나중에 하셔도 됩니다)"
- 사용자가 '나중에', '안 할래' 등으로 거절하면 더 권하지 말고, $root/.cowork/onboarding.json 에 {"status":"skipped"} 를 저장해 다시 묻지 않게 한다.
- 사용자가 다른 일을 바로 시키면 그 일부터 하고, 온보딩 안내는 첫 응답에 한 줄만 붙인다.
EOF
fi
# 동기화를 켠 경우에만: 시작할 때 다른 노트북의 변경을 받고 못 올린 변경을 올린다(실패해도 세션은 계속).
# 켜지 않은 사용자는 아래 한 줄(파일 읽기만)만 거치고 동기화 코드는 읽지도 않는다.
# COWORK_LITE_SKIP_SYNC 가 있으면 건너뛴다(doctor 가 hook 이 실행되는지만 볼 때).
if [ -z "${COWORK_LITE_SKIP_SYNC:-}" ] && cl_sync_enabled && source "$HERE/../lib/sync.sh" 2>/dev/null; then sync_auto_start; fi
exit 0
