#!/bin/bash
# 공통 함수: 홈 경로, 메시지, JSON(plutil), 타임스탬프. bash 3.2 호환.

# macOS가 아니라 plutil이 없으면(Windows Git Bash 등) Node 기반 호환 shim을 함수로 연결한다.
# PATH를 바꾸는 방식은 PATH를 좁히는 호출(테스트·hook)에서 사라지므로 함수로 둔다.
# 속도 주의(Windows): 프로세스 하나를 띄우는 데 약 0.1초가 든다. 경로 판정처럼 자주 도는 곳에서는
# uname·tr·basename·dirname·cygpath 같은 외부 명령 대신 bash 내장 기능만 쓴다.
_cl_d="${BASH_SOURCE[0]}"; case "$_cl_d" in */*) _cl_d="${_cl_d%/*}" ;; *) _cl_d=. ;; esac
CL_SHIM_DIR="$(cd "$_cl_d" && pwd)/shim"; unset _cl_d
_cl_plutil_path="$(type -P plutil 2>/dev/null)"

# _cl_to_win <POSIX 경로> → REPLY: node.exe가 읽을 수 있는 Windows 경로(`/c/x`→`C:/x`, `/tmp/x`→ 실제 Temp 경로).
_cl_to_win() {
  local p="$1"
  case "$p" in
    # Git Bash 안에서는 $TEMP도 `/tmp`로 보인다. /tmp 아래에 설치된 경우(테스트)에만 cygpath로 실제 경로를 얻는다.
    /tmp|/tmp/*) REPLY="$(cygpath -m "$p" 2>/dev/null || printf '%s' "$p")"; return ;;
  esac
  if [[ "$p" =~ ^/([a-zA-Z])(/.*)?$ ]]; then REPLY="${BASH_REMATCH[1]}:${BASH_REMATCH[2]:-/}"; else REPLY="$p"; fi
}

# 진짜 plutil이 없거나 PATH에 있는 것이 우리 shim 폴더의 것이면 Node 기반 호환 구현을 함수로 연결한다.
# 함수라서 PATH를 좁히는 호출(테스트·hook)에서도 사라지지 않는다.
if [ -z "$_cl_plutil_path" ] || [ "${_cl_plutil_path%/*}" = "$CL_SHIM_DIR" ]; then
  CL_NODE="${COWORK_LITE_NODE:-}"
  if [ -z "$CL_NODE" ]; then
    # 테스트가 PATH에 가짜 node를 둘 수 있어 Windows 표준 설치 위치를 먼저 본다.
    for _cl_c in "${PROGRAMFILES:-/c/Program Files}/nodejs/node.exe" "/c/Program Files/nodejs/node.exe"; do
      [ -x "$_cl_c" ] && { CL_NODE="$_cl_c"; break; }
    done
    unset _cl_c
  fi
  _cl_to_win "$CL_SHIM_DIR/plutil.js"; CL_SHIM_JS="$REPLY"
  _cl_to_win "$CL_SHIM_DIR/hookin.js"; CL_HOOKIN_JS="$REPLY"
  # PATH에 plutil(또는 테스트용 stub)이 있으면 그것을 먼저 쓴다. 없으면 node로 직접 간다(래퍼 bash·cygpath 없이).
  plutil() {
    if type -P plutil >/dev/null 2>&1; then command plutil "$@"; return; fi
    local node="${CL_NODE:-}"
    [ -n "$node" ] || { node="$(command -v node)" || return 1; }
    MSYS2_ARG_CONV_EXCL='*' "$node" "$CL_SHIM_JS" "$@"
  }
fi
unset _cl_plutil_path

# cl_is_windows : 프로세스를 띄우지 않는 OS 판별(경로 판정에서 자주 부른다). COWORK_LITE_OS로 덮어쓸 수 있다(테스트용).
cl_is_windows() {
  case "${COWORK_LITE_OS:-$OSTYPE}" in windows|msys*|cygwin*|win32*) return 0 ;; *) return 1 ;; esac
}
# cl_os : mac | windows | linux
cl_os() {
  if [ -n "${COWORK_LITE_OS:-}" ]; then printf '%s\n' "$COWORK_LITE_OS"; return; fi
  case "$OSTYPE" in
    darwin*) echo mac ;;
    msys*|cygwin*|win32*) echo windows ;;
    *) echo linux ;;
  esac
}

# 설치 위치. Windows 형식(`C:\x`)으로 지정돼 있어도 POSIX 형식(`/c/x`)으로 돌려준다.
# 이 경로는 settings.json의 hook 명령에 들어가는데, bash -c 가 역슬래시를 지워 버려(`C:Users…`) hook이 실행되지 않는다.
cl_home() {
  local h="${COWORK_LITE_HOME:-$HOME/.cowork-lite}"
  if cl_is_windows; then
    if [[ "$h" =~ ^([A-Za-z]):([\\/].*)?$ ]]; then h="/${BASH_REMATCH[1],,}${BASH_REMATCH[2]}"; fi
    h="${h//\\//}"
  fi
  printf '%s\n' "$h"
}

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

# bash 5의 printf 내장 시각 기능이 있으면 프로세스를 띄우지 않는다(macOS의 bash 3.2는 date 사용).
cl_stamp() {
  if [ "${BASH_VERSINFO[0]:-0}" -ge 5 ]; then printf '%(%Y%m%d-%H%M%S)T\n' -1; else date '+%Y%m%d-%H%M%S'; fi
}

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
  local v f c re
  f="$(cl_home)/local.json"
  # 빠른 길: 이스케이프 없는 단순한 값이면 내장 기능만으로 읽는다(Node를 띄우면 0.2~0.5초가 든다).
  if [ -f "$f" ]; then
    IFS= read -r -d '' c < "$f"
    re='"space"[[:space:]]*:[[:space:]]*\{[^}]*"root"[[:space:]]*:[[:space:]]*"([^"\\]+)"'
    if [[ "$c" =~ $re ]]; then printf '%s\n' "${BASH_REMATCH[1]}"; return; fi
  fi
  v="$(cl_json_get "$f" space.root)" && [ -n "$v" ] && { printf '%s\n' "$v"; return; }
  printf '%s\n' "$HOME/cowork-space"
}
