#!/bin/bash
# 업무일지(v0.6): 세션 정리할 때마다 업무일지/<년-월>/<년-월-일>.md 에 덧붙인다. 파일이 없으면 만들고, 있으면 기존 내용을 지우지 않는다.
# 의존: common(cl_space_root, cl_say, cl_warn), task(_task_names; 없으면 진행 중 업무 줄을 생략). bash 3.2 호환.

# 시각. 시험에서는 COWORK_LITE_NOW="2026-11-20 14:05" 로 고정한다.
_journal_now() { printf '%s\n' "${COWORK_LITE_NOW:-$(date '+%Y-%m-%d %H:%M')}"; }

# journal_add [내용...] : 내용을 인자로 주거나, 인자가 없으면 표준 입력에서 읽는다.
journal_add() {
  local now day hm ym root dir file body active scan drop pers
  now="$(_journal_now)"; day="${now%% *}"; hm="${now##* }"; ym="${day%-*}"
  root="$(cl_space_root)"
  [ -d "$root" ] || { cl_warn "✘ 작업 폴더가 없습니다: $root (cowork-lite setup 을 먼저 실행해 주세요)"; return 1; }
  if [ $# -gt 0 ]; then body="$*"; else body="$(cat)"; fi
  # 기록 점검(안내): 비밀값 모양인 줄은 쓰지 않고, 개인정보 모양인 줄은 쓰되 경고한다. 값은 보여 주지 않고 종류와 줄 번호만 알린다.
  if type record_scan >/dev/null 2>&1; then
    scan="$(record_scan "$body")"
    drop="$(printf '%s\n' "$scan" | awk -F'\t' '$1 == "S" { print $2 }' | sort -n -u | paste -sd, -)"
    if [ -n "$drop" ]; then
      cl_warn "⚠ 비밀번호·토큰처럼 보여 업무일지에 쓰지 않은 줄이 있습니다: $(record_summary S "$scan"). 비밀값은 기록하지 않습니다."
      body="$(record_drop_lines "$body" "$drop")"
      scan="$(record_scan "$body")"
    fi
    pers="$(record_summary P "$scan")"
    if [ -n "$pers" ]; then
      cl_warn "⚠ 고객·개인 정보로 보이는 줄이 있습니다: $pers. 업무일지는 GitHub 비공개 저장소로 올라가니, 필요하면 \"거래처 1곳\"처럼 일반화해서 다시 써 주세요."
    fi
  fi
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

# journal_last_section <작업 폴더> : 가장 최근 업무일지의 마지막 "세션 정리" 구역을 REPLY 에 둔다(첫 줄: 파일과 시각, 이어서 최대 3줄).
# 세션을 시작할 때 쓰므로 외부 프로그램 없이 bash 만 쓴다. 없으면 빈 값.
journal_last_section() {
  local root="$1" ym lastdir="" f best="" line i idx=-1 cnt=0
  local -a lines
  REPLY=""
  for ym in "$root"/업무일지/*/; do [ -d "$ym" ] && lastdir="$ym"; done
  [ -n "$lastdir" ] || return 0
  for f in "$lastdir"*.md; do [ -f "$f" ] && best="$f"; done
  [ -n "$best" ] || return 0
  lines=()
  while IFS= read -r line || [ -n "$line" ]; do lines[${#lines[@]}]="$line"; done < "$best"
  for ((i = 0; i < ${#lines[@]}; i++)); do
    case "${lines[$i]}" in "## 세션 정리"*) idx=$i ;; esac
  done
  [ "$idx" -ge 0 ] || return 0
  REPLY="${best#"$root"/} (${lines[$idx]#\#\# 세션 정리 })"
  for ((i = idx + 1; i < ${#lines[@]} && cnt < 3; i++)); do
    line="${lines[$i]}"
    case "$line" in "## "*) break ;; "") continue ;; esac
    REPLY="$REPLY"$'\n'"$line"; cnt=$((cnt + 1))
  done
  return 0
}
