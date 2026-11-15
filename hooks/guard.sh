#!/bin/bash
# cowork-lite PreToolUse hook: stdin의 도구 호출 JSON을 읽어 판정 JSON을 stdout으로 낸다.
# fail-closed: 입력이 비었거나 깨졌거나, 도구를 모르거나, 내부 오류가 나면 막는다.
# 종료 코드는 항상 0(판정은 stdout JSON으로만 전달한다).
# dirname·cd·pwd 서브셸 대신 문자열 치환만 쓴다(Windows에서 프로세스 하나가 40ms 안팎). 상대 경로로 불려도 절대 경로가 된다.
HERE="${BASH_SOURCE[0]%/*}"; [ "$HERE" = "${BASH_SOURCE[0]}" ] && HERE="."; [[ "$HERE" == /* || "$HERE" == [A-Za-z]:* ]] || HERE="$PWD/$HERE"
LIBDIR="$HERE/../lib"
FAIL_TEXT="문제가 생겨 안전을 위해 멈췄습니다. 도움이 필요하면 cowork-lite report 를 실행해 주세요."
EMITTED=0

emit() {
  [ "$EMITTED" = 1 ] && return 0
  EMITTED=1
  # JSON 문자열 이스케이프(\ → \\, " → \")와 줄바꿈 → 공백. sed·tr 프로세스를 띄우지 않는다(Windows에서 느리다).
  local reason="${2//\\/\\\\}"; reason="${reason//\"/\\\"}"; reason="${reason//$'\n'/ }"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$reason"
}

fail_closed() {
  emit deny "$FAIL_TEXT"
  command -v guard_log >/dev/null 2>&1 && guard_log deny hook internal_error 2>/dev/null
  exit 0
}

# 어떤 경로로 끝나든 판정이 한 번도 나가지 않았다면 차단을 내보낸다.
trap '[ "$EMITTED" = 1 ] || emit deny "$FAIL_TEXT"' EXIT

extract() { printf '%s' "$INPUT" | plutil -extract "$1" raw -o - - 2>/dev/null; }

# 빠른 길(plutil 대신 Node 호환 구현을 쓰는 Windows 등): 필요한 필드를 Node 한 번으로 모두 읽는다.
# 필드마다 Node를 띄우면 hook 한 번에 수 초가 걸린다. 결과는 F_<필드> 변수(F_X=1이면 문자열로 있음)에 둔다.
_read_fields_fast() {
  local node="${CL_NODE:-}"
  [ -n "$node" ] || node="$(command -v node)" || return 1
  {
    IFS= read -r -d '' F_tool_ok && IFS= read -r -d '' F_tool \
      && IFS= read -r -d '' F_cwd_ok && IFS= read -r -d '' F_cwd \
      && IFS= read -r -d '' F_cmd_ok && IFS= read -r -d '' F_cmd \
      && IFS= read -r -d '' F_path_ok && IFS= read -r -d '' F_path \
      && IFS= read -r -d '' F_nb_ok && IFS= read -r -d '' F_nb
  } < <(MSYS2_ARG_CONV_EXCL='*' "$node" "$CL_HOOKIN_JS")
}

main() {
  local tool path cmd res level reason cwd fast=0
  source "$LIBDIR/common.sh" && source "$LIBDIR/manifest.sh" && source "$LIBDIR/space.sh" \
    && source "$LIBDIR/guard.sh" || return 1
  if declare -F plutil >/dev/null 2>&1 && [ -n "${CL_HOOKIN_JS:-}" ]; then
    fast=1
    _read_fields_fast || return 1
    [ "$F_tool_ok" = 1 ] && [ -n "$F_tool" ] || return 1
    tool="$F_tool"; cwd="$F_cwd"
  else
    INPUT="$(cat)"
    [ -n "$INPUT" ] || return 1
    tool="$(extract tool_name)" || return 1
    [ -n "$tool" ] || return 1
    # 상대 경로는 Claude가 작업 중인 폴더(입력의 cwd) 기준으로 푼다.
    cwd="$(extract cwd)"
  fi
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then cd "$cwd" || return 1; fi
  case "$tool" in
    Bash)
      if [ "$fast" = 1 ]; then [ "$F_cmd_ok" = 1 ] || return 1; cmd="$F_cmd"
      else cmd="$(extract tool_input.command)" || return 1; fi
      res="$(guard_decide_bash "$cmd")" ;;
    Write|Edit|MultiEdit|Read)
      if [ "$fast" = 1 ]; then [ "$F_path_ok" = 1 ] || return 1; path="$F_path"
      else path="$(extract tool_input.file_path)" || return 1; fi
      [ -n "$path" ] || return 1
      res="$(guard_decide_file "$tool" "$path")" ;;
    NotebookEdit)
      if [ "$fast" = 1 ]; then [ "$F_nb_ok" = 1 ] || return 1; path="$F_nb"
      else path="$(extract tool_input.notebook_path)" || return 1; fi
      [ -n "$path" ] || return 1
      res="$(guard_decide_file "$tool" "$path")" ;;
    *) return 1 ;;
  esac
  [ -n "$res" ] || return 1
  level="${res%%$'\t'*}"; reason="${res#*$'\t'}"
  case "$level" in
    backup)
      if space_backup "$path" >/dev/null; then
        EMITTED=1   # 사본을 만든 뒤 판정은 비운다(허용을 선언하지 않고 Claude Code 기본 권한 확인에 맡김)
      else
        emit deny "수정하기 전에 사본을 만들지 못해 멈췄습니다."
        guard_log deny "$tool" backup_failed
      fi ;;
    # allow는 판정을 비운다. allow를 내면 Claude Code 자체 권한 확인을 건너뛰어,
    # 이 Guard가 모르는 명령까지 조용히 자동 승인되기 때문이다.
    allow) EMITTED=1 ;;
    ask|deny)
      emit "$level" "$reason"
      guard_log "$level" "$tool" "${level}_${tool}" ;;
    *) return 1 ;;
  esac
  return 0
}

main || fail_closed
exit 0
