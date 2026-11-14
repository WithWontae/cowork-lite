#!/bin/bash
# cowork-lite SessionStart hook: 세션 시작 시 stdout이 Claude의 규칙(맥락)으로 주입된다.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
EOF
exit 0
