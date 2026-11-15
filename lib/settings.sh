#!/bin/bash
# ~/.claude/settings.json 안전 편집. 잠금·백업·검증·롤백으로만 고친다. bash 3.2 호환.
# 우리 hook 항목은 command 문자열에 `cowork-lite`가 들어 있는 것으로 식별한다.
# 의존: lib/common.sh

SETTINGS_MARKER="cowork-lite"
SETTINGS_GUARD_MATCHER="Read|Write|Edit|MultiEdit|Bash|NotebookEdit"
SETTINGS_EVENTS="SessionStart PreToolUse"

settings_path() { printf '%s\n' "${CLAUDE_SETTINGS_PATH:-$HOME/.claude/settings.json}"; }

# 없음·빈 파일·`{}`뿐인 파일(plutil이 편집 못 함)은 "비어 있음"으로 본다.
_settings_is_blank() {
  local f="$1"
  [ ! -s "$f" ] && return 0
  [ "$(tr -d ' \n\t' < "$f")" = "{}" ]
}

_settings_json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

_settings_lock_acquire() {
  [ -n "$COWORK_LITE_LOCK_HELD" ] && return 0
  cl_lock_acquire
}
_settings_lock_release() {
  [ -n "$COWORK_LITE_LOCK_HELD" ] && return 0
  cl_lock_release
}

# 백업을 만들고 롤백에 쓸 정보를 전역에 둔다.
_settings_backup() {
  local f="$1" dir stamp; dir="$(cl_home)/backup"; stamp="$(cl_stamp)"
  mkdir -p "$dir" || return 1
  if [ -s "$f" ]; then
    _SETTINGS_BACKUP="$dir/settings-$stamp.json"
    cp -p "$f" "$_SETTINGS_BACKUP" || return 1
  else
    _SETTINGS_BACKUP=""
    : > "$dir/settings-$stamp.absent"
  fi
}
_settings_rollback() {
  local f="$1"
  if [ -n "$_SETTINGS_BACKUP" ] && [ -f "$_SETTINGS_BACKUP" ]; then
    cp -p "$_SETTINGS_BACKUP" "$f"
  else
    rm -f "$f"
  fi
}

# _settings_transaction <변경함수> [인자…] : 잠금→검증→백업→변경→실패 시 롤백→잠금 해제
_settings_transaction() {
  local fn="$1" f rc; shift
  f="$(settings_path)"
  _settings_lock_acquire || return 1
  if ! _settings_is_blank "$f" && ! cl_json_valid "$f"; then
    cl_warn "Claude 설정 파일이 손상되어 있어 건드리지 않았습니다. 파일 위치: $f"
    _settings_lock_release; return 1
  fi
  mkdir -p "$(dirname "$f")"
  _settings_backup "$f" || { _settings_lock_release; return 1; }
  if _settings_is_blank "$f"; then printf '{"hooks":{}}\n' > "$f"; fi
  "$fn" "$f" "$@"; rc=$?
  if [ $rc -ne 0 ] || ! cl_json_valid "$f"; then
    _settings_rollback "$f"
    cl_warn "설정을 바꾸지 못해 원래 상태로 되돌렸습니다."
    _settings_lock_release; return 1
  fi
  _settings_lock_release
}

# 이벤트 배열에서 우리 항목의 인덱스를 한 줄씩 출력
_settings_ours_indexes() {
  local f="$1" ev="$2" n m i j c
  n="$(plutil -extract "hooks.$ev" raw -o - "$f" 2>/dev/null)" || return 0
  i=0
  while [ "$i" -lt "$n" ]; do
    m="$(plutil -extract "hooks.$ev.$i.hooks" raw -o - "$f" 2>/dev/null)" || m=0
    j=0
    while [ "$j" -lt "$m" ]; do
      c="$(plutil -extract "hooks.$ev.$i.hooks.$j.command" raw -o - "$f" 2>/dev/null)"
      case "$c" in *"$SETTINGS_MARKER"*) echo "$i"; break ;; esac
      j=$((j+1))
    done
    i=$((i+1))
  done
}

# settings_our_command <이벤트> : 그 이벤트에 등록된 우리 hook의 command 문자열을 출력한다. 없으면 1.
# doctor가 등록된 명령을 Claude Code가 하는 것과 같은 방식으로 실제 실행해 볼 때 쓴다.
settings_our_command() {
  local f ev="$1" n m i j c; f="$(settings_path)"
  [ -s "$f" ] || return 1
  n="$(plutil -extract "hooks.$ev" raw -o - "$f" 2>/dev/null)" || return 1
  i=0
  while [ "$i" -lt "$n" ]; do
    m="$(plutil -extract "hooks.$ev.$i.hooks" raw -o - "$f" 2>/dev/null)" || m=0
    j=0
    while [ "$j" -lt "$m" ]; do
      c="$(plutil -extract "hooks.$ev.$i.hooks.$j.command" raw -o - "$f" 2>/dev/null)"
      case "$c" in *"$SETTINGS_MARKER"*) printf '%s\n' "$c"; return 0 ;; esac
      j=$((j+1))
    done
    i=$((i+1))
  done
  return 1
}

settings_has_hooks() {
  local f ev; f="$(settings_path)"
  [ -s "$f" ] || return 1
  for ev in $SETTINGS_EVENTS; do
    [ -n "$(_settings_ours_indexes "$f" "$ev")" ] || return 1
  done
}

_settings_apply_register() {
  local f="$1" session_cmd="$2" guard_cmd="$3" ev item
  plutil -extract hooks json -o - "$f" >/dev/null 2>&1 \
    || cl_json_edit "$f" -insert hooks -json '{}' || return 1
  for ev in $SETTINGS_EVENTS; do
    plutil -extract "hooks.$ev" json -o - "$f" >/dev/null 2>&1 \
      || cl_json_edit "$f" -insert "hooks.$ev" -json '[]' || return 1
    if [ "$ev" = "SessionStart" ]; then
      item="{\"hooks\":[{\"type\":\"command\",\"command\":\"$(_settings_json_escape "$session_cmd")\"}]}"
    else
      item="{\"matcher\":\"$SETTINGS_GUARD_MATCHER\",\"hooks\":[{\"type\":\"command\",\"command\":\"$(_settings_json_escape "$guard_cmd")\"}]}"
    fi
    cl_json_edit "$f" -insert "hooks.$ev" -json "$item" -append || return 1
  done
}

# settings_register_hooks <session_cmd> <guard_cmd> : 멱등. 이미 등록돼 있으면 아무것도 바꾸지 않는다.
settings_register_hooks() {
  settings_has_hooks && return 0
  _settings_transaction _settings_apply_register "$1" "$2"
}

_settings_apply_unregister() {
  local f="$1" ev idx
  for ev in $SETTINGS_EVENTS; do
    for idx in $(_settings_ours_indexes "$f" "$ev" | sort -rn); do
      cl_json_edit "$f" -remove "hooks.$ev.$idx" || return 1
    done
    # 우리 항목을 빼서 이벤트 배열이 비었으면 그 이벤트 키도 지운다(원래 없던 키가 빈 채로 남지 않게).
    [ "$(plutil -extract "hooks.$ev" json -o - "$f" 2>/dev/null | tr -d '[:space:]')" = "[]" ] \
      && { cl_json_edit "$f" -remove "hooks.$ev" || return 1; }
  done
  [ "$(plutil -extract hooks json -o - "$f" 2>/dev/null | tr -d '[:space:]')" = "{}" ] \
    && { cl_json_edit "$f" -remove hooks || return 1; }
  return 0
}

settings_unregister_hooks() {
  local f; f="$(settings_path)"
  [ -s "$f" ] || return 0
  _settings_transaction _settings_apply_unregister
}
