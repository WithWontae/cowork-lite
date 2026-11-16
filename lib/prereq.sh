#!/bin/bash
# 선행 도구(Claude Code, Node.js) 점검·설치. Homebrew 같은 개발용 패키지 관리자는 쓰지 않는다.
# 설치 방법(공식 설치기·.pkg 주소)은 packs.json에 두며 미검증이다 — 깨끗한 Mac에서 확인한다(설계 §9.1b).
# 테스트는 COWORK_LITE_RUNNER(`<러너> install <도구>`)로 실제 설치를 대체한다.
# 의존: lib/common.sh. bash 3.2 호환.

PREREQ_PACKS_FILE_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packs.json"
_prereq_packs() { printf '%s\n' "${PREREQ_PACKS_FILE:-$PREREQ_PACKS_FILE_DEFAULT}"; }
_prereq_cfg() { cl_json_get "$(_prereq_packs)" "prereq.$1.$2"; }
_prereq_name() { local n; n="$(_prereq_cfg "$1" name)" && printf '%s\n' "$n" || printf '%s\n' "$1"; }

# 새로 설치한 도구가 있을 만한 폴더를 PATH 앞에 붙인다(콜론으로 구분, 테스트는 빈 값으로 끈다).
prereq_refresh_path() {
  local list="${PREREQ_EXTRA_PATHS-$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin}" d
  local -a dirs
  # Windows: 방금 설치한 도구는 이 셸의 PATH에 없다. 레지스트리의 Machine·User PATH를 다시 읽어 뒤에 붙인다.
  # PREREQ_EXTRA_PATHS가 설정돼 있으면(테스트) 건드리지 않는다.
  if [ "$(cl_os)" = windows ] && [ -z "${PREREQ_EXTRA_PATHS+x}" ]; then
    local win p
    win="$(powershell.exe -NoProfile -Command "[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')" 2>/dev/null | tr -d '\r')"
    if [ -n "$win" ] && command -v cygpath >/dev/null 2>&1; then
      p="$(cygpath -u -p "$win" 2>/dev/null)"
      [ -n "$p" ] && PATH="$PATH:$p"
    fi
  fi
  IFS=: read -r -a dirs <<< "$list"
  for d in "${dirs[@]}"; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
  done
  export PATH
}

_prereq_version() {
  local v
  case "$1" in
    node)   v="$(node --version 2>/dev/null | head -1)" ;;
    claude) v="$(claude --version 2>/dev/null | head -1)" ;;
    gh)     v="$(gh --version 2>/dev/null | head -1)" ;;
    *)      v="" ;;
  esac
  printf '%s\n' "$v" | sed -n 's/[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*/\1/p' | head -1
}

# _prereq_ver_ge <a> <b> : a >= b (점 구분 숫자 3칸)
_prereq_ver_ge() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$1"; IFS=. read -r b1 b2 b3 <<< "$2"
  a1=${a1:-0}; a2=${a2:-0}; a3=${a3:-0}; b1=${b1:-0}; b2=${b2:-0}; b3=${b3:-0}
  [ "$a1" -gt "$b1" ] && return 0; [ "$a1" -lt "$b1" ] && return 1
  [ "$a2" -gt "$b2" ] && return 0; [ "$a2" -lt "$b2" ] && return 1
  [ "$a3" -ge "$b3" ]
}

# prereq_check <claude|node> : 0 정상 / 1 없음 / 2 버전 부족
prereq_check() {
  local tool="$1" ver min
  command -v "$tool" >/dev/null 2>&1 || return 1
  min="$(_prereq_cfg "$tool" min)" || min="0.0.0"
  ver="$(_prereq_version "$tool")"
  if [ -z "$ver" ]; then
    [ "$min" = "0.0.0" ] && return 0
    return 2
  fi
  _prereq_ver_ge "$ver" "$min" && return 0
  return 2
}

# prereq_node_pkg_url <index.json> : 가장 최신 LTS의 macOS .pkg 주소
prereq_node_pkg_url() {
  local idx="$1" i=0 ver lts base
  base="$(_prereq_cfg node pkg_base)" || base="https://nodejs.org/dist"
  while ver="$(cl_json_get "$idx" "$i.version")"; do
    lts="$(cl_json_get "$idx" "$i.lts")"
    if [ -n "$lts" ] && [ "$lts" != "false" ]; then
      printf '%s/%s/node-%s.pkg\n' "$base" "$ver" "$ver"; return 0
    fi
    i=$((i+1))
  done
  return 1
}

# 내려받기: 실패하면 반쯤 받은 파일을 남기지 않는다.
_prereq_download() {
  local tmp="${2}.part.$$"
  if curl -fsSL -o "$tmp" "$1" 2>/dev/null; then mv "$tmp" "$2"; else rm -f "$tmp"; return 1; fi
}

# Windows: winget으로 설치한다(관리자 권한 확인 창이 뜰 수 있다).
_prereq_winget_install() {
  local id
  id="$(_prereq_cfg "$1" winget_id)" || return 1
  command -v winget >/dev/null 2>&1 || { cl_warn "winget을 찾을 수 없습니다."; return 1; }
  winget install --id "$id" -e --source winget --accept-package-agreements --accept-source-agreements
}

_prereq_real_install() {
  local tool="$1" dir url pkg rc=0
  [ "$(cl_os)" = windows ] && { _prereq_winget_install "$tool"; return $?; }
  dir="$(mktemp -d "${TMPDIR:-/tmp}/cowork-lite-dl.XXXXXX")" || return 1
  case "$tool" in
    claude)
      url="$(_prereq_cfg claude installer_url)" || { rm -rf "$dir"; return 1; }
      _prereq_download "$url" "$dir/claude-install.sh" && bash "$dir/claude-install.sh" || rc=1 ;;
    node)
      _prereq_download "$(_prereq_cfg node index_url)" "$dir/index.json" || rc=1
      if [ $rc -eq 0 ]; then
        url="$(prereq_node_pkg_url "$dir/index.json")" || rc=1
      fi
      if [ $rc -eq 0 ]; then
        pkg="$dir/node.pkg"
        _prereq_download "$url" "$pkg" && sudo installer -pkg "$pkg" -target / >/dev/null || rc=1
      fi ;;
    *) rc=1 ;;
  esac
  rm -rf "$dir"
  return $rc
}

prereq_install() {
  local tool="$1" name; name="$(_prereq_name "$tool")"
  cl_say "$name 을(를) 설치합니다. 몇 분 걸릴 수 있습니다."
  if [ "$tool" = node ]; then
    if [ "$(cl_os)" = windows ]; then
      cl_say "권한 확인 창이 나오면 [예]를 눌러 주세요."
    else
      cl_say "암호 입력 창이 나오면 Mac 로그인 암호를 입력해 주세요. (입력해도 화면에 글자가 보이지 않는 것이 정상입니다)"
    fi
  fi
  if [ -n "$COWORK_LITE_RUNNER" ]; then "$COWORK_LITE_RUNNER" install "$tool"; else _prereq_real_install "$tool"; fi
}

prereq_it_request_text() {
  local name official; name="$(_prereq_name "$1")"; official="$(_prereq_cfg "$1" official)"
  printf 'IT 담당자에게 이렇게 요청해 주세요:\n- 설치할 프로그램: %s\n- 공식 주소: %s\n- 개인 PC에 설치하려면 관리자 권한이 필요합니다.\n' "$name" "$official"
}

# 선택 도구 GitHub CLI(gh). 없어도, 설치에 실패해도 항상 0을 돌려줘 설치를 막지 않는다.
# Windows 는 winget 으로 설치한다. Mac 은 자동 설치하지 않고 안내만 한다. 로그인은 사용자가 gh auth login 으로 직접 한다.
# GitHub 로그인·git 연결. 로그인은 브라우저에서 사용자가 직접 한다(암호·토큰은 이 프로그램이 받거나 저장하지 않는다).
# 이미 로그인돼 있으면 건너뛰고, 묻지 않는 실행(COWORK_LITE_YES)이거나 터미널이 없으면 안내만 한다. 항상 0.
prereq_gh_login() {
  local tty="${COWORK_LITE_TTY:-/dev/tty}"
  command -v gh >/dev/null 2>&1 || return 0
  if gh auth status >/dev/null 2>&1; then cl_say "✔ GitHub 에 이미 로그인되어 있습니다."; return 0; fi
  if [ -n "$COWORK_LITE_YES" ] || ! type _space_confirm >/dev/null 2>&1 || [ ! -r "$tty" ] || ! _space_confirm "지금 GitHub 에 로그인할까요? (브라우저가 열립니다. 나중에 gh auth login 으로 해도 됩니다)"; then
    cl_say "ℹ GitHub 로그인은 나중에 터미널에서 gh auth login 으로 할 수 있습니다."
    return 0
  fi
  if gh auth login --hostname github.com --git-protocol https --web < "$tty" && gh auth setup-git; then
    cl_say "✔ GitHub 로그인과 git 연결을 마쳤습니다."
  else
    cl_warn "⚠ GitHub 로그인을 마치지 못했습니다. 선택 사항이라 계속 진행합니다. 나중에 gh auth login 으로 다시 할 수 있습니다."
  fi
  return 0
}

prereq_gh_optional() {
  local name; name="$(_prereq_name gh)"
  prereq_refresh_path
  if prereq_check gh; then cl_say "✔ $name 이(가) 이미 설치되어 있습니다."; prereq_gh_login; return 0; fi
  if [ -z "$COWORK_LITE_RUNNER" ] && [ "$(cl_os)" != windows ]; then
    cl_say "ℹ $name 은(는) 선택 사항이라 자동으로 설치하지 않습니다. 필요하면 $(_prereq_cfg gh official) 를 보고 설치해 주세요."
    return 0
  fi
  if prereq_install gh; then
    prereq_refresh_path
    if prereq_check gh; then
      cl_say "✔ $name 설치를 마쳤습니다."
      prereq_gh_login
    else
      cl_say "ℹ $name 설치는 끝났지만 아직 이 창에서 보이지 않습니다. 터미널을 새로 열면 보입니다."
    fi
  else
    cl_warn "⚠ $name 설치에 실패했습니다. 선택 사항이라 계속 진행합니다. 나중에 winget install --id $(_prereq_cfg gh winget_id) 로 설치할 수 있습니다."
  fi
  return 0
}

# 순서: Claude Code → Node.js. 이미 있으면 건너뛴다.
prereq_run_all() {
  local tool name rc
  prereq_refresh_path
  for tool in claude node; do
    name="$(_prereq_name "$tool")"
    prereq_check "$tool"; rc=$?
    if [ $rc -eq 0 ]; then cl_say "✔ $name 이(가) 이미 설치되어 있습니다."; continue; fi
    [ $rc -eq 2 ] && cl_say "$name 버전이 낮아 새로 설치합니다."
    if ! prereq_install "$tool"; then
      cl_warn "✘ $name 설치에 실패했습니다. 인터넷 연결이나 회사 보안 때문일 수 있습니다."
      cl_warn "문제가 계속되면 같은 명령을 다시 실행해 보시고, 그래도 안 되면 아래 내용을 IT 담당자에게 전달해 주세요."
      cl_warn "$(prereq_it_request_text "$tool")"
      return 1
    fi
    prereq_refresh_path
    if ! prereq_check "$tool"; then
      cl_warn "$name 설치는 끝났지만 아직 이 창에서 보이지 않습니다. 터미널을 닫고 다시 열어 같은 명령을 한 번 더 붙여넣어 주세요."
      return 1
    fi
    cl_say "✔ $name 설치를 마쳤습니다."
  done
  return 0
}
