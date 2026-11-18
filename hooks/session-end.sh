#!/bin/bash
# cowork-lite SessionEnd hook: 세션이 끝날 때 변경분을 GitHub 로 올린다(동기화를 켠 경우에만).
# Claude Code 는 종료 hook 을 오래 기다려 주지 않을 수 있으므로 동기화는 뒤에서 돌리고 바로 끝낸다.
# 올리지 못해도(네트워크 등) 다음 세션을 시작할 때 다시 올린다. 결과는 $COWORK_LITE_HOME/sync.log 에 남는다. 항상 0으로 끝난다.
# 시험에서는 COWORK_LITE_SYNC_FOREGROUND=1 로 앞에서 돌려 끝날 때까지 기다린다.
cat >/dev/null 2>&1   # Claude Code 가 넘기는 JSON 입력은 쓰지 않는다
HERE="${BASH_SOURCE[0]%/*}"; [ "$HERE" = "${BASH_SOURCE[0]}" ] && HERE="."; [[ "$HERE" == /* || "$HERE" == [A-Za-z]:* ]] || HERE="$PWD/$HERE"
source "$HERE/../lib/common.sh" 2>/dev/null || exit 0
cl_sync_enabled || exit 0
source "$HERE/../lib/sync.sh" 2>/dev/null || exit 0
if [ -n "$COWORK_LITE_SYNC_FOREGROUND" ]; then
  sync_auto_end
else
  ( sync_auto_end </dev/null >/dev/null 2>&1 & )
fi
exit 0
