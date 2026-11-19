#!/bin/bash
# 업무일지(v0.6): 세션 정리할 때마다 업무일지/<년-월>/<년-월-일>.md 에 덧붙인다. 파일이 없으면 만들고, 있으면 기존 내용을 지우지 않는다.
# 의존: common(cl_space_root, cl_say, cl_warn), task(_task_names; 없으면 진행 중 업무 줄을 생략). bash 3.2 호환.

# 시각. 시험에서는 COWORK_LITE_NOW="2026-11-20 14:05" 로 고정한다.
_journal_now() { printf '%s\n' "${COWORK_LITE_NOW:-$(date '+%Y-%m-%d %H:%M')}"; }

# journal_add [내용...] : 내용을 인자로 주거나, 인자가 없으면 표준 입력에서 읽는다.
journal_add() {
  local now day hm ym root dir file body active
  now="$(_journal_now)"; day="${now%% *}"; hm="${now##* }"; ym="${day%-*}"
  root="$(cl_space_root)"
  [ -d "$root" ] || { cl_warn "✘ 작업 폴더가 없습니다: $root (cowork-lite setup 을 먼저 실행해 주세요)"; return 1; }
  if [ $# -gt 0 ]; then body="$*"; else body="$(cat)"; fi
  if [ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ]; then cl_warn "✘ 저장할 내용이 비어 있습니다."; return 2; fi
  dir="$root/업무일지/$ym"; file="$dir/$day.md"
  mkdir -p "$dir" || { cl_warn "✘ 업무일지 폴더를 만들지 못했습니다."; return 1; }
  [ -f "$file" ] || printf '# %s 업무일지\n' "$day" > "$file" || return 1
  active=""
  if type _task_names >/dev/null 2>&1; then active="$(_task_names 작업중 | paste -sd, - | sed 's/,/, /g')"; fi
  {
    printf '\n## 세션 정리 %s\n' "$hm"
    printf '%s\n' "$body"
    if [ -n "$active" ]; then printf '\n- 진행 중 업무: %s\n' "$active"; fi
  } >> "$file" || { cl_warn "✘ 업무일지에 쓰지 못했습니다."; return 1; }
  cl_say "✔ 업무일지에 저장했습니다: 업무일지/$ym/$day.md"
}

# session_save [내용...] : "세션 정리해" 의 파일 쪽 처리. 업무일지에 덧붙인 뒤, 동기화를 켠 경우 바로 동기화한다.
# 동기화가 실패해도 업무일지 저장은 이미 끝나 있다(내 파일은 이 노트북에 남고, 다음 세션 시작·종료 때 다시 올린다).
session_save() {
  journal_add "$@" || return $?
  if ! cl_sync_enabled; then
    cl_say "ℹ 이 노트북에서만 쓰는 설정이라 동기화는 하지 않았습니다."
    return 0
  fi
  cl_say "동기화합니다(다른 노트북과 맞춥니다)…"
  if sync_run; then
    cl_say "✔ 동기화를 마쳤습니다."
  else
    cl_warn "⚠ 동기화하지 못했습니다. 업무일지는 이 노트북에 저장되어 있고, 다음에 Claude Code 를 시작하거나 끝낼 때 다시 올립니다. 바로 다시 하려면 cowork-lite sync 를 실행하세요."
  fi
  return 0
}
