#!/bin/bash
# 공통 함수: 홈 경로, 메시지, JSON(plutil), 타임스탬프. bash 3.2 호환.

cl_home() { printf '%s\n' "${COWORK_LITE_HOME:-$HOME/.cowork-lite}"; }

cl_say()  { printf '%s\n' "$*"; }
cl_warn() { printf '%s\n' "$*" >&2; }

# plutil -lint은 JSON을 plist로만 읽어 실패하므로 변환 성공 여부로 검사한다.
cl_json_valid() { [ -f "$1" ] && plutil -convert json -o /dev/null "$1" >/dev/null 2>&1; }

# cl_json_get <파일> <키경로> : 문자열 값 출력, 없으면 1
cl_json_get() {
  [ -f "$1" ] || return 1
  plutil -extract "$2" raw -o - "$1" 2>/dev/null
}

# cl_json_set <파일> <키경로> <문자열값> : 파일·상위 키가 없으면 만든다
cl_json_set() {
  local file="$1" path="$2" val="$3" prefix="" part rest
  mkdir -p "$(dirname "$file")"
  # 내용이 `{}`뿐인 파일은 plutil이 OpenStep으로 오인해 편집에 실패하므로(확인됨),
  # 새 파일·빈 객체는 최상위 키를 넣은 JSON으로 시작한다. 키에는 따옴표·역슬래시가 없다고 가정.
  if [ ! -s "$file" ] || [ "$(tr -d ' \n\t' < "$file")" = "{}" ]; then
    case "$path" in
      *.*) printf '{"%s":{}}\n' "${path%%.*}" > "$file" ;;
      *)   printf '{"%s":""}\n' "$path" > "$file" ;;
    esac
  fi
  rest="$path"
  while [ "${rest#*.}" != "$rest" ]; do
    part="${rest%%.*}"; rest="${rest#*.}"
    prefix="${prefix:+$prefix.}$part"
    plutil -extract "$prefix" json -o - "$file" >/dev/null 2>&1 \
      || cl_json_edit "$file" -insert "$prefix" -json '{}' || return 1
  done
  cl_json_edit "$file" -replace "$path" -string "$val" 2>/dev/null \
    || cl_json_edit "$file" -insert "$path" -string "$val"
}

# cl_json_edit <파일> <plutil 편집 인자…> : JSON 파일은 plutil 제자리 수정이 안 되므로
# 임시 파일로 출력한 뒤 교체한다(이 macOS의 plutil 동작, 2026-11-14 확인).
cl_json_edit() {
  local file="$1" tmp; shift
  tmp="$(mktemp "${file}.XXXXXX")" || return 1
  if plutil "$@" -o "$tmp" "$file" && cl_json_valid "$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"; return 1
  fi
}

cl_stamp() { date '+%Y%m%d-%H%M%S'; }

# 설치 잠금. 잠금 폴더에 PID를 적어 두고, 이미 있을 때 그 프로세스가 죽었으면 회수한다
# (터미널 창을 닫아 잠금이 남아도 다음 실행이 막히지 않게). PID 기록이 없으면 살아 있는 것으로 본다.
cl_lock_acquire() {
  local lock pid; lock="$(cl_home)/.lock"
  mkdir -p "$(cl_home)" || return 1
  if ! mkdir "$lock" 2>/dev/null; then
    pid="$(cat "$lock/pid" 2>/dev/null)"
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      rm -rf "$lock"
      mkdir "$lock" 2>/dev/null || { cl_warn "다른 설치가 진행 중입니다. 잠시 뒤에 다시 시도해 주세요."; return 1; }
    else
      cl_warn "다른 설치가 진행 중입니다. 잠시 뒤에 다시 시도해 주세요."
      return 1
    fi
  fi
  printf '%s\n' "$$" > "$lock/pid"
}
cl_lock_release() { rm -rf "$(cl_home)/.lock" 2>/dev/null; return 0; }

cl_space_root() {
  local v
  v="$(cl_json_get "$(cl_home)/local.json" space.root)" && [ -n "$v" ] && { printf '%s\n' "$v"; return; }
  printf '%s\n' "$HOME/cowork-space"
}
