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
- 하루 기록은 업무일지/YYYY-MM-DD.md 에 남긴다.
- 비밀번호·인증서·주민번호·계좌 같은 민감정보는 기억하거나 기록하지 않는다.
- 사용자가 "세션 정리해"라고 하면 ai-memory 의 인수인계(memory_handoff_begin)로 이번 세션의 한 일·결정·남은 일을 저장한다. 민감정보는 넣지 않고, 저장 후 무엇을 저장했는지 짧게 알린다.

답변 방식:
- 핵심만 잘 정리해서 답한다. 불필요한 설명, 반복 설명, 장황한 배경 설명은 쓰지 않는다.
- 확실하지 않은 정보는 "불확실하다"고 분명히 알린다. 추측을 사실처럼 말하지 않는다.
- 요청하지 않은 범위까지 확장하지 않는다. 시킨 것만 한다.
- 답변 맨 아래에는 사용자가 답하거나 결정해야 할 것만 핵심으로 요약한다. 결정할 것이 있으면 AskUserQuestion 도구로 선택지(선택 UI)를 만들어 쉽게 고르게 한다. 이 도구를 쓸 수 없으면 번호 목록으로 대신한다. 결정할 것이 없으면 이 부분은 쓰지 않는다.
EOF
exit 0
