#!/bin/bash
# 선행 도구(Claude Code, Node.js) 점검·설치. Homebrew 같은 개발용 패키지 관리자는 쓰지 않는다.
# 설치 방법(공식 설치기·.pkg 주소)은 packs.json에 두며 미검증이다 — 깨끗한 Mac에서 확인한다(설계 §9.1b).
# 테스트는 COWORK_LITE_RUNNER(`<러너> install <도구>`)로 실제 설치를 대체한다.
# 의존: lib/common.sh. bash 3.2 호환.

PREREQ_PACKS_FILE_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packs.json"
_prereq_packs() { printf '%s\n' "${PREREQ_PACKS_FILE:-$PREREQ_PACKS_FILE_DEFAULT}"; }
# packs.json 의 prereq.<도구>.<키> 값을 읽는다. Node 를 설치하기 전(깨끗한 Windows)에는 Node 기반 JSON 도구가 동작하지 않으므로,
# 먼저 파일의 줄 구조를 직접 읽고(awk), 못 찾을 때만 JSON 도구를 쓴다. 문자열·true/false·숫자 값을 읽는다.
_prereq_cfg_plain() {
  [ -f "$(_prereq_packs)" ] || return 1
  awk -v t="$1" -v k="$2" '
    /^[[:space:]]*"prereq"[[:space:]]*:[[:space:]]*\{/ { inpre = 1; next }
    inpre && !blk && $0 ~ ("^[[:space:]]*\"" t "\"[[:space:]]*:[[:space:]]*\\{") { blk = 1; next }
    blk && /^[[:space:]]*\},?[[:space:]]*$/ { exit }
    blk {
      pat = "^[[:space:]]*\"" k "\"[[:space:]]*:[[:space:]]*"
      if (match($0, pat)) {
        s = substr($0, RLENGTH + 1)
        if (substr(s, 1, 1) == "\"") { s = substr(s, 2); sub(/".*$/, "", s) } else { sub(/[ ,\r]*$/, "", s) }
        print s; found = 1; exit
      }
    }
    END { exit found ? 0 : 1 }' "$(_prereq_packs)"
}
_prereq_cfg() {
  local v
  v="$(_prereq_cfg_plain "$1" "$2")" && [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
  cl_json_get "$(_prereq_packs)" "prereq.$1.$2"
}
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
    git)    v="$(git --version 2>/dev/null | head -1)" ;;
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

# 실제로 쓸 수 있는 Python(min 이상)을 찾아 실행 파일 경로를 출력한다. 없으면 1.
# Windows 의 python 은 앱 스토어로 연결되는 빈 껍데기일 수 있어 이름만 보지 않고 실제로 실행해 버전을 읽는다.
# 찾으면 PREREQ_PYTHON_EXE 에 기억한다(방금 설치해 PATH 에 아직 없거나, 빈 껍데기가 PATH 앞에 있어도 진짜를 쓰기 위해).
prereq_python_find() {
  local min c out exe ver d
  min="$(_prereq_cfg python min)" || min="3.10.0"
  if [ -n "${PREREQ_PYTHON_EXE:-}" ] && [ -x "$PREREQ_PYTHON_EXE" ]; then printf '%s\n' "$PREREQ_PYTHON_EXE"; return 0; fi
  local -a cands=("python3" "python" "py -3")
  if [ "$(cl_os)" = windows ] && [ -n "${LOCALAPPDATA:-}" ] && command -v cygpath >/dev/null 2>&1; then
    d="$(cygpath -u "$LOCALAPPDATA" 2>/dev/null)/Programs/Python"
    for c in "$d"/Python3*/python.exe; do [ -x "$c" ] && cands+=("$c"); done
  fi
  for c in "${cands[@]}"; do
    out="$($c -c 'import sys;print(sys.executable);print("%d.%d.%d"%sys.version_info[:3])' 2>/dev/null | tr -d '\r')" || continue
    exe="$(printf '%s\n' "$out" | sed -n 1p)"; ver="$(printf '%s\n' "$out" | sed -n 2p)"
    [ -n "$exe" ] && [ -n "$ver" ] || continue
    [ "$(cl_os)" = windows ] && command -v cygpath >/dev/null 2>&1 && exe="$(cygpath -u "$exe" 2>/dev/null)"
    [ -x "$exe" ] || continue
    _prereq_ver_ge "$ver" "$min" || continue
    export PREREQ_PYTHON_EXE="$exe"
    printf '%s\n' "$exe"; return 0
  done
  return 1
}

# prereq_check <claude|node> : 0 정상 / 1 없음 / 2 버전 부족
prereq_check() {
  local tool="$1" ver min
  if [ "$tool" = python ]; then prereq_python_find >/dev/null; return $?; fi
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

# 내려받기: 실패하면 반쯤 받은 파일을 남기지 않고, 이유(curl 오류)를 알린다.
_prereq_download() {
  local tmp="${2}.part.$$" err
  if err="$(curl -fsSL -o "$tmp" "$1" 2>&1)"; then mv "$tmp" "$2"; else
    rm -f "$tmp"
    cl_warn "내려받지 못했습니다: $1"
    [ -n "$err" ] && cl_warn "  이유: $err"
    return 1
  fi
}

# Windows: winget으로 설치한다(권한 확인 창이 뜰 수 있다). 실패하면 이유를 알린다.
_prereq_winget_install() {
  local id rc
  id="$(_prereq_cfg "$1" winget_id)"
  if [ -z "$id" ]; then cl_warn "설치 정보(winget 이름)를 packs.json 에서 읽지 못했습니다: $1"; return 1; fi
  if ! command -v winget >/dev/null 2>&1; then
    cl_warn "winget(Windows 패키지 관리자)을 찾을 수 없습니다. Windows 10 에서는 Microsoft Store 의 '앱 설치 관리자(App Installer)'를 설치하거나 업데이트하면 생깁니다."
    return 1
  fi
  winget install --id "$id" -e --source winget --accept-package-agreements --accept-source-agreements
  rc=$?
  [ $rc -eq 0 ] || cl_warn "winget 이 오류로 끝났습니다(종료 코드 $rc, 패키지 $id)."
  return $rc
}

# Windows 에서 Claude Code 는 공식 PowerShell 설치기로도 설치할 수 있다(winget 이 없거나 실패했을 때의 대안).
_prereq_claude_ps1_install() {
  local url rc
  url="$(_prereq_cfg claude installer_ps1_url)"
  [ -n "$url" ] || return 1
  command -v powershell.exe >/dev/null 2>&1 || { cl_warn "PowerShell 을 찾을 수 없어 공식 설치기를 쓸 수 없습니다."; return 1; }
  cl_say "공식 설치기($url)로 설치합니다."
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm '$url' | iex"
  rc=$?
  [ $rc -eq 0 ] || cl_warn "공식 설치기가 오류로 끝났습니다(종료 코드 $rc)."
  return $rc
}

# Windows 에서 Python 은 python.org 공식 설치 파일로도 설치할 수 있다(winget 이 없거나 실패했을 때의 대안).
# 내 계정에만 설치하므로 관리자 권한이 필요 없다. 내려받은 파일은 서명(Python Software Foundation)을 확인한 뒤에만 실행한다.
_prereq_python_official_install() {
  local url dir exe sig rc
  url="$(_prereq_cfg python installer_url_win)"
  [ -n "$url" ] || return 1
  case "${PROCESSOR_ARCHITECTURE:-AMD64}" in
    AMD64|x86_64) ;;
    *) cl_warn "이 PC(${PROCESSOR_ARCHITECTURE})에는 자동 설치를 지원하지 않습니다. $(_prereq_cfg python official) 에서 직접 설치해 주세요."; return 1 ;;
  esac
  command -v powershell.exe >/dev/null 2>&1 || { cl_warn "PowerShell 을 찾을 수 없어 내려받은 파일의 서명을 확인할 수 없습니다."; return 1; }
  dir="$(mktemp -d "${TMPDIR:-/tmp}/cowork-lite-py.XXXXXX")" || return 1
  exe="$dir/python-installer.exe"
  cl_say "python.org 에서 Python 설치 파일을 내려받습니다(약 27MB)."
  _prereq_download "$url" "$exe" || { rm -rf "$dir"; return 1; }
  sig="$(powershell.exe -NoProfile -Command "\$s = Get-AuthenticodeSignature -LiteralPath '$(cygpath -w "$exe" 2>/dev/null || printf '%s' "$exe")'; \$s.Status.ToString() + '|' + \$s.SignerCertificate.Subject" 2>/dev/null </dev/null | tr -d '\r')"
  case "$sig" in
    "Valid|"*"Python Software Foundation"*) ;;
    *) cl_warn "내려받은 파일의 서명을 확인하지 못해 실행하지 않습니다(확인 결과: ${sig:-없음})."; rm -rf "$dir"; return 1 ;;
  esac
  cl_say "Python 을 설치합니다. 내 계정에만 설치하며 관리자 권한은 필요 없습니다. 몇 분 걸릴 수 있습니다."
  # Git Bash 는 `/quiet` 같은 인자를 경로로 바꿔 버리므로 변환을 끈다(cmd.exe /c 때와 같은 문제).
  MSYS2_ARG_CONV_EXCL='*' "$exe" /quiet InstallAllUsers=0 PrependPath=1 Include_launcher=0 Include_test=0 </dev/null
  rc=$?
  rm -rf "$dir"
  [ $rc -eq 0 ] || cl_warn "Python 설치 파일이 오류로 끝났습니다(종료 코드 $rc)."
  return $rc
}

# Microsoft Visual C++ 런타임(msvcp140.dll 등). MarkItDown 이 쓰는 onnxruntime 이 필요로 하며, 새로 설치한 Windows 10 에는 없을 수 있다
# (없으면 python -m markitdown 이 "DLL load failed while importing onnxruntime_pybind11_state" 로 실패한다 — 실제 Windows 10 에서 겪음).
_prereq_vcredist_present() {
  local sys; sys="$(cygpath -u "${SYSTEMROOT:-C:\\Windows}" 2>/dev/null || printf '%s' "${SYSTEMROOT:-/c/Windows}")"
  [ -f "$sys/System32/msvcp140.dll" ] && [ -f "$sys/System32/vcruntime140_1.dll" ]
}

# 설치: winget → 안 되면 Microsoft 공식 주소(aka.ms)에서 받아 서명(Microsoft Corporation)을 확인한 뒤 실행. 관리자 권한 확인 창이 뜬다.
_prereq_vcredist_install() {
  local url dir exe sig rc
  if _prereq_winget_install vcredist; then return 0; fi
  url="$(_prereq_cfg vcredist installer_url_win)"; [ -n "$url" ] || return 1
  command -v powershell.exe >/dev/null 2>&1 || return 1
  dir="$(mktemp -d "${TMPDIR:-/tmp}/cowork-lite-vc.XXXXXX")" || return 1
  exe="$dir/vc_redist.x64.exe"
  cl_say "Microsoft 공식 주소에서 Visual C++ 런타임을 내려받습니다(약 25MB)."
  _prereq_download "$url" "$exe" || { rm -rf "$dir"; return 1; }
  sig="$(powershell.exe -NoProfile -Command "\$s = Get-AuthenticodeSignature -LiteralPath '$(cygpath -w "$exe" 2>/dev/null || printf '%s' "$exe")'; \$s.Status.ToString() + '|' + \$s.SignerCertificate.Subject" 2>/dev/null </dev/null | tr -d '\r')"
  case "$sig" in
    "Valid|"*"Microsoft Corporation"*) ;;
    *) cl_warn "내려받은 파일의 서명을 확인하지 못해 실행하지 않습니다(확인 결과: ${sig:-없음})."; rm -rf "$dir"; return 1 ;;
  esac
  MSYS2_ARG_CONV_EXCL='*' "$exe" /install /quiet /norestart </dev/null
  rc=$?
  rm -rf "$dir"
  # 3010 = 다시 시작 필요, 1638 = 같거나 더 새 버전이 이미 있음. bash 는 종료 코드를 256 으로 나눈 나머지(3010→194, 1638→102)로 받으므로 둘 다 성공으로 본다.
  case "$rc" in 0|3010|194|1638|102) return 0 ;; esac
  cl_warn "Visual C++ 설치 파일이 오류로 끝났습니다(종료 코드 $rc)."
  return $rc
}

# Windows 에서 Python 이 있는데 이 런타임이 없으면 설치한다. 선택 사항이라 실패해도 설치를 막지 않는다(항상 0).
prereq_vcredist_optional() {
  cl_is_windows || return 0
  _prereq_vcredist_present && return 0
  cl_say "MS 문서 변환 도구(MarkItDown)에 필요한 Microsoft Visual C++ 런타임이 없어 설치합니다. 권한 확인 창이 나오면 [예]를 눌러 주세요."
  if _prereq_vcredist_install; then
    cl_say "✔ Visual C++ 런타임 설치를 마쳤습니다."
  else
    cl_warn "⚠ Visual C++ 런타임을 설치하지 못했습니다. 선택 사항이라 계속 진행합니다. MS 문서 변환 도구는 나중에 $(_prereq_cfg vcredist official) 에서 설치한 뒤 쓸 수 있습니다."
  fi
  return 0
}

_prereq_real_install() {
  local tool="$1" dir url pkg rc=0
  if [ "$(cl_os)" = windows ]; then
    _prereq_winget_install "$tool"; rc=$?
    [ $rc -eq 0 ] && return 0
    if [ "$tool" = claude ]; then
      cl_warn "winget 으로 설치하지 못해 공식 설치기로 다시 시도합니다."
      _prereq_claude_ps1_install; return $?
    fi
    if [ "$tool" = python ]; then
      cl_warn "winget 으로 설치하지 못해 python.org 공식 설치 파일로 다시 시도합니다."
      _prereq_python_official_install; return $?
    fi
    return $rc
  fi
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

# 설치 시도의 오류 출력과 종료 코드를 $(cl_home)/install.log 에 남긴다(왜 실패했는지 나중에 볼 수 있게). 종료 코드는 PREREQ_LAST_RC 에도 둔다.
prereq_install() {
  local tool="$1" name log rc; name="$(_prereq_name "$tool")"
  log="$(cl_home)/install.log"; mkdir -p "$(cl_home)" 2>/dev/null
  cl_say "$name 을(를) 설치합니다. 몇 분 걸릴 수 있습니다."
  if [ "$tool" = node ]; then
    if [ "$(cl_os)" = windows ]; then
      cl_say "권한 확인 창이 나오면 [예]를 눌러 주세요."
    else
      cl_say "암호 입력 창이 나오면 Mac 로그인 암호를 입력해 주세요. (입력해도 화면에 글자가 보이지 않는 것이 정상입니다)"
    fi
  fi
  printf '[%s] %s 설치 시작\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$tool" >> "$log" 2>/dev/null
  if [ -n "$COWORK_LITE_RUNNER" ]; then "$COWORK_LITE_RUNNER" install "$tool" 2> >(tee -a "$log" >&2)
  else _prereq_real_install "$tool" 2> >(tee -a "$log" >&2); fi
  rc=$?
  PREREQ_LAST_RC=$rc
  printf '[%s] %s 설치 종료 코드 %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$tool" "$rc" >> "$log" 2>/dev/null
  return $rc
}

# 설치가 막혔을 때 IT 담당자에게 전달할 내용. 개인 PC에서는 보통 관리자 권한이 필요하지 않으므로, 회사 보안 정책으로 막힌 경우에만 요청하도록 한다.
prereq_it_request_text() {
  local name official; name="$(_prereq_name "$1")"; official="$(_prereq_cfg "$1" official)"
  printf 'IT 담당자에게 이렇게 요청해 주세요:\n- 설치할 프로그램: %s\n- 공식 주소: %s\n- 회사 보안 정책으로 설치가 막힌 경우에만 필요합니다. 이 프로그램을 설치할 수 있게 허용해 달라고 요청해 주세요.\n' "$name" "$official"
}

# 설치 처음에 환경을 알려 준다. 막지는 않는다(Windows 10 에서도 될 수 있다).
# Windows 11 이 아니면(빌드 22000 미만) 확인한 환경이 아니라고 알리고, winget 이 없으면 미리 알린다.
prereq_env_notice() {
  local ver build
  cl_is_windows || return 0
  # Windows 빌드 번호는 `uname -s`(예: MINGW64_NT-10.0-19045)의 끝에서 읽는다. cmd.exe 를 부르지 않는다:
  # Git Bash 는 `/c` 인자를 경로로 바꿔 버려(`cmd.exe /c ver` 가 대화형 cmd 를 띄워) 입력을 기다리며 설치가 멈춘다(실제로 겪음).
  ver="$(uname -s 2>/dev/null)"
  case "$ver" in *_NT-*) build="${ver##*-}" ;; *) build="" ;; esac
  if [ -n "$build" ] && [ "$build" -lt 22000 ] 2>/dev/null; then
    cl_say "ℹ 이 PC는 Windows 10(빌드 $build)으로 보입니다. cowork-lite 는 Windows 11 과 Mac 에서 확인했습니다. 계속 진행하지만 일부 단계가 안 될 수 있습니다."
  fi
  if ! command -v winget >/dev/null 2>&1; then
    cl_say "ℹ winget(Windows 패키지 관리자)이 없습니다. Claude Code 와 Python 은 공식 설치기로 설치하고, 그 밖의 도구(Node.js 등)는 공식 주소를 안내합니다."
  fi
  return 0
}

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

# 선택 도구(git, gh) 하나를 점검·설치한다. 설치를 막지 않는 용도라 실패해도 안내만 한다.
# 있거나 방금 설치돼 이 창에서 보이면 0, 아니면 1. Windows 는 winget 으로 설치하고, Mac 은 자동 설치하지 않고 안내만 한다.
_prereq_optional() {
  local tool="$1" name hint; name="$(_prereq_name "$tool")"
  prereq_refresh_path
  if prereq_check "$tool"; then cl_say "✔ $name 이(가) 이미 설치되어 있습니다."; return 0; fi
  if [ -z "$COWORK_LITE_RUNNER" ] && [ "$(cl_os)" != windows ]; then
    hint="$(_prereq_cfg "$tool" mac_hint)"
    cl_say "ℹ $name 은(는) 자동으로 설치하지 않습니다. $(_prereq_cfg "$tool" official) 를 보고 설치해 주세요.${hint:+ $hint}"
    return 1
  fi
  if prereq_install "$tool"; then
    prereq_refresh_path
    if prereq_check "$tool"; then cl_say "✔ $name 설치를 마쳤습니다."; return 0; fi
    cl_say "ℹ $name 설치는 끝났지만 아직 이 창에서 보이지 않습니다. 터미널을 새로 열면 보입니다."
    return 1
  fi
  cl_warn "⚠ $name 설치에 실패했습니다. 선택 사항이라 계속 진행합니다. 나중에 winget install --id $(_prereq_cfg "$tool" winget_id) 로 설치할 수 있습니다."
  return 1
}

# 동기화를 고른 경우에 쓰는 선택 도구. 둘 다 항상 0을 돌려줘 설치를 막지 않는다.
prereq_git_optional() { _prereq_optional git; return 0; }
prereq_gh_optional() { _prereq_optional gh && prereq_gh_login; return 0; }
# MarkItDown(MS 문서 변환)에 필요한 Python. 없으면 Windows 는 winget 으로 설치하고 Mac 은 안내만 한다. 실패해도 설치를 막지 않는다.
prereq_python_optional() { _prereq_optional python; return 0; }

# 순서: Claude Code → Node.js. 이미 있으면 건너뛴다.
prereq_run_all() {
  local tool name rc
  prereq_refresh_path
  prereq_env_notice
  for tool in claude node; do
    name="$(_prereq_name "$tool")"
    prereq_check "$tool"; rc=$?
    if [ $rc -eq 0 ]; then cl_say "✔ $name 이(가) 이미 설치되어 있습니다."; continue; fi
    [ $rc -eq 2 ] && cl_say "$name 버전이 낮아 새로 설치합니다."
    if ! prereq_install "$tool"; then
      cl_warn "✘ $name 설치에 실패했습니다(종료 코드 ${PREREQ_LAST_RC:-?}). 위에 나온 오류 문구와 기록($(cl_home)/install.log)에서 이유를 볼 수 있습니다."
      cl_warn "인터넷 연결이나 회사 보안 때문일 수 있습니다."
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
