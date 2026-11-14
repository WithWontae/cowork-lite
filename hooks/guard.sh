#!/bin/bash
# cowork-lite PreToolUse hook: stdin의 도구 호출 JSON을 읽어 판정 JSON을 stdout으로 낸다.
# fail-closed: 입력이 비었거나 깨졌거나, 도구를 모르거나, 내부 오류가 나면 막는다.
# 종료 코드는 항상 0(판정은 stdout JSON으로만 전달한다).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBDIR="$HERE/../lib"
FAIL_TEXT="문제가 생겨 안전을 위해 멈췄습니다. 도움이 필요하면 cowork-lite report 를 실행해 주세요."
EMITTED=0

emit() {
  [ "$EMITTED" = 1 ] && return 0
  EMITTED=1
  local reason; reason="$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')"
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

main() {
  local tool path cmd res level reason cwd
  source "$LIBDIR/common.sh" && source "$LIBDIR/manifest.sh" && source "$LIBDIR/space.sh" \
    && source "$LIBDIR/guard.sh" || return 1
  INPUT="$(cat)"
  [ -n "$INPUT" ] || return 1
  tool="$(extract tool_name)" || return 1
  [ -n "$tool" ] || return 1
  # 상대 경로는 Claude가 작업 중인 폴더(입력의 cwd) 기준으로 푼다.
  cwd="$(extract cwd)"
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then cd "$cwd" || return 1; fi
  case "$tool" in
    Bash)
      cmd="$(extract tool_input.command)" || return 1
      res="$(guard_decide_bash "$cmd")" ;;
    Write|Edit|MultiEdit|Read)
      path="$(extract tool_input.file_path)" || return 1
      [ -n "$path" ] || return 1
      res="$(guard_decide_file "$tool" "$path")" ;;
    NotebookEdit)
      path="$(extract tool_input.notebook_path)" || return 1
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
