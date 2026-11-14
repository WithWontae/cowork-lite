#!/bin/bash
# 작업 폴더(cowork-space) 규약: 구조, 경로 분류, 백업, space 명령(ls·find·rm·restore).
# 의존: lib/common.sh, lib/manifest.sh. bash 3.2 호환.

SPACE_AREAS="받은자료 작업중 결과물 업무일지"

space_init() {
  local root d entry; root="$(cl_space_root)"
  for d in $SPACE_AREAS .cowork/backup .cowork/trash; do
    mkdir -p "$root/$d" || return 1
  done
  entry="$(printf 'keep\t%s' "$root")"
  manifest_list | grep -Fqx "$entry" || manifest_add keep "$root"
  cl_say "작업 폴더를 준비했습니다: $root"
}

# _space_resolve <경로> : 심볼릭 링크·..을 풀어 실제 경로를 출력한다. 없는 경로도 처리한다.
# Windows에서 같은 위치가 여러 표기로 나온다(`C:\x`, `C:/x`, `/c/x`, MSYS의 `/tmp/x`, 8.3 짧은 이름, 대소문자).
# 문자열 비교로 폴더를 판정하므로 입력은 POSIX로 바꾸고 출력은 항상 하나의 표기로 맞춘다.
# 아래 `_r` 함수들은 결과를 REPLY 변수에 둔다($(...)로 받으면 프로세스를 새로 띄워 느리다). 외부 명령은 쓰지 않는다.
_space_to_posix_r() {
  local p="$1" d
  if cl_is_windows; then
    if [[ "$p" =~ ^([A-Za-z]):([\\/].*)?$ ]]; then
      d="${BASH_REMATCH[1]}"; p="${BASH_REMATCH[2]}"; p="${p//\\//}"; REPLY="/${d,,}${p}"; return
    fi
    p="${p//\\//}"
  fi
  REPLY="$p"
}
# MSYS의 /tmp는 사용자 %TEMP%와 같은 곳이다. 정션 대상이 /tmp/...로 풀려 나오면 /c/Users/... 표기와 문자열이 달라진다.
# Git Bash 안에서는 $TEMP도 `/tmp`로 보이므로 cygpath로 실제 위치를 한 번만 알아낸다(/tmp 경로가 나올 때만 불린다).
_space_tmp_posix() {
  [ -n "${_SPACE_TMP:-}" ] && return
  _space_to_posix_r "$(cygpath -m /tmp 2>/dev/null)"; _SPACE_TMP="${REPLY%/}"
  [ -n "$_SPACE_TMP" ] || _SPACE_TMP=/tmp
}
_space_canon_r() {
  local p="$1"
  REPLY="$p"
  cl_is_windows || return 0
  case "$p" in /dev/*) return 0 ;; esac   # /dev/null 같은 가상 경로는 그대로 둔다
  case "$p" in /tmp|/tmp/*) _space_tmp_posix; p="${_SPACE_TMP}${p#/tmp}" ;; esac
  # 8.3 짧은 이름(COWORK~1)이 있을 때만 cygpath로 푼다(드문 경우라 프로세스 비용을 감수한다).
  if [[ "$p" == *~[0-9]* ]] && command -v cygpath >/dev/null 2>&1; then
    p="$(cygpath -u "$(cygpath -ml "$p" 2>/dev/null || printf '%s' "$p")" 2>/dev/null || printf '%s' "$p")"
    case "$p" in /tmp|/tmp/*) _space_tmp_posix; p="${_SPACE_TMP}${p#/tmp}" ;; esac
  fi
  REPLY="$p"
}

_space_resolve() {
  local p="$1" depth="${2:-0}" tail="" base target comp out d dn
  local comps=() stack=() n=0 i
  [ "$depth" -gt 20 ] && { printf '%s\n' "$p"; return 0; }
  if [ "$depth" -eq 0 ]; then _space_to_posix_r "$p"; p="$REPLY"; fi
  case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
  while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done   # 끝의 / 제거
  while [ ! -e "$p" ] && [ ! -L "$p" ] && [ "$p" != "/" ]; do
    tail="${p##*/}${tail:+/$tail}"; p="${p%/*}"; [ -n "$p" ] || p=/
  done
  if [ -L "$p" ]; then
    target="$(readlink "$p")"
    case "$target" in /*) ;; *) d="${p%/*}"; [ -n "$d" ] || d=/; target="${d%/}/$target" ;; esac
    _space_resolve "${target}${tail:+/$tail}" $((depth+1)); return
  fi
  if [ -d "$p" ]; then
    base="$(cd -P "$p" && pwd -P)"
  else
    dn="${p%/*}"; [ -n "$dn" ] || dn=/
    base="$(cd -P "$dn" && pwd -P)"; base="${base%/}/${p##*/}"
  fi
  if [ -n "$tail" ]; then
    IFS=/ read -r -a comps <<< "$tail"
    for comp in "${comps[@]}"; do
      case "$comp" in
        ""|.) ;;
        ..) if [ "$n" -gt 0 ]; then n=$((n-1)); else base="${base%/*}"; [ -n "$base" ] || base=/; fi ;;
        *) stack[$n]="$comp"; n=$((n+1)) ;;
      esac
    done
  fi
  # 정규화는 실제로 있는 앞부분(base)에만 한다. 없는 뒷부분이 섞이면 짧은 이름이 풀리지 않는다.
  _space_canon_r "$base"; base="$REPLY"
  out="$base"
  i=0
  while [ "$i" -lt "$n" ]; do
    if [ "$out" = "/" ]; then out="/${stack[$i]}"; else out="$out/${stack[$i]}"; fi
    i=$((i+1))
  done
  printf '%s\n' "$out"
}

# _space_rel_r <루트> <경로> : 경로가 루트 아래면 루트 이후 부분을 REPLY에 두고 0, 아니면 1. 루트 자신이면 REPLY가 비어 있다.
# Windows(NTFS)는 대소문자를 구분하지 않으므로 비교만 소문자로 맞춰서 한다(`${x,,}`는 bash 4+, Windows Git Bash는 5).
_space_rel_r() {
  local rl="$1" pl="$2"
  if cl_is_windows; then rl="${rl,,}"; pl="${pl,,}"; fi
  case "$pl" in
    "$rl") REPLY=""; return 0 ;;
    "$rl"/*) REPLY="${2:$((${#1}+1))}"; return 0 ;;
  esac
  return 1
}

# space_classify <경로> → inbox|work|result|journal|internal|outside
space_classify() {
  local root rp rel top
  root="$(_space_resolve "$(cl_space_root)")"
  rp="$(_space_resolve "$1")"
  _space_rel_r "$root" "$rp" || { echo outside; return; }
  rel="$REPLY"
  [ -n "$rel" ] || { echo work; return; }
  top="${rel%%/*}"
  # 자모 분리(NFD) 한글 이름으로 폴더 판정을 피하지 못하게 NFC로 맞춘다. NFD는 macOS 파일시스템 특성이라
  # Windows에서는 건너뛴다(iconv 프로세스를 띄우는 비용만 든다).
  cl_is_windows || top="$(printf '%s' "$top" | iconv -f UTF-8-MAC -t UTF-8 2>/dev/null || printf '%s' "$top")"
  case "$top" in
    받은자료) echo inbox ;;
    작업중) echo work ;;
    결과물) echo result ;;
    업무일지) echo journal ;;
    .cowork|.cowork-lite) echo internal ;;
    *) echo work ;;
  esac
}

# space_backup <파일> → 사본 경로 출력. 이전 사본은 덮어쓰지 않는다.
space_backup() {
  local root rp rel base dest n=1
  if [ "$(space_classify "$1")" = outside ]; then
    cl_warn "작업 폴더 밖의 파일은 사본을 만들지 않습니다."; return 1
  fi
  root="$(_space_resolve "$(cl_space_root)")"
  rp="$(_space_resolve "$1")"
  _space_rel_r "$root" "$rp"; rel="$REPLY"
  base="$root/.cowork/backup/$(cl_stamp)"; dest="$base/$rel"
  while [ -e "$dest" ]; do n=$((n+1)); dest="$base-$n/$rel"; done
  mkdir -p "${dest%/*}" && cp -p "$rp" "$dest" && printf '%s\n' "$dest"
}

# 확인 질문. 답은 COWORK_LITE_TTY(기본 /dev/tty)에서 읽고, 읽지 못하면 "아니오"로 본다.
_space_confirm() {
  local ans tty="${COWORK_LITE_TTY:-/dev/tty}"
  printf '%s [예/아니오] ' "$1" >&2
  IFS= read -r ans 2>/dev/null < "$tty" || { echo >&2; return 1; }
  case "$ans" in 예|y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

_space_count_files() {
  local p="$1"
  if [ -d "$p" ] && [ ! -L "$p" ]; then find "$p" -type f | wc -l | tr -d ' '; else echo 1; fi
}

# space_rm [--yes|--yes-bulk] <경로…> : 확인 후 .cowork/trash 로 이동(영구 삭제 아님)
space_rm() {
  local yes=0 bulk=0 p cls total=0 c label root stamp seq=0 dir rp first=1
  while [ $# -gt 0 ]; do
    case "$1" in --yes) yes=1 ;; --yes-bulk) yes=1; bulk=1 ;; *) break ;; esac
    shift
  done
  [ $# -gt 0 ] || { cl_warn "지울 파일을 알려 주세요."; return 1; }
  for p in "$@"; do
    cls="$(space_classify "$p")"
    case "$cls" in
      inbox)    cl_warn "받은자료는 지울 수 없습니다. 작업중 폴더로 복사한 뒤 지워 주세요."; return 1 ;;
      outside)  cl_warn "작업 폴더 밖의 파일은 지울 수 없습니다."; return 1 ;;
      internal) cl_warn "내부 폴더는 지울 수 없습니다."; return 1 ;;
    esac
    { [ -e "$p" ] || [ -L "$p" ]; } || { cl_warn "찾을 수 없습니다: $p"; return 1; }
    if [ $first -eq 1 ]; then
      case "$cls" in result) label="결과물" ;; journal) label="업무일지" ;; *) label="작업중" ;; esac
      first=0
    fi
    c="$(_space_count_files "$p")"; total=$((total + c))
  done
  # --yes-bulk: 호출한 쪽(Guard의 사용자 확인 창)이 이미 확인했다는 뜻이라 질문 없이 진행한다.
  if [ $bulk -eq 0 ] && { [ $yes -eq 0 ] || [ "$total" -ge 10 ]; }; then
    _space_confirm "$label 폴더의 파일 ${total}개를 지우려고 합니다. 계속할까요?" \
      || { cl_say "취소했습니다. 파일은 그대로입니다."; return 1; }
  fi
  root="$(_space_resolve "$(cl_space_root)")"; stamp="$(cl_stamp)"
  for p in "$@"; do
    seq=$((seq+1)); dir="$root/.cowork/trash/$stamp-$seq"
    while [ -e "$dir" ]; do seq=$((seq+1)); dir="$root/.cowork/trash/$stamp-$seq"; done
    mkdir -p "$dir" || return 1
    rp="$(_space_resolve "$p")"
    printf '%s\n' "$rp" > "$dir/origin.txt"
    mv "$p" "$dir/" || return 1
  done
  cl_say "휴지통으로 옮겼습니다. 되돌리려면 cowork-lite space restore 를 쓰세요."
}

# space_restore <원래 경로> : 가장 최근에 지운 항목을 되돌린다. 기존 파일은 덮어쓰지 않는다.
space_restore() {
  local root rp d latest="" item dest b stem ext n=1
  root="$(_space_resolve "$(cl_space_root)")"
  rp="$(_space_resolve "$1")"
  for d in "$root/.cowork/trash"/*/; do
    [ -f "$d/origin.txt" ] || continue
    [ "$(cat "$d/origin.txt")" = "$rp" ] && latest="${d%/}"
  done
  [ -n "$latest" ] || { cl_warn "휴지통에서 찾을 수 없습니다: $1"; return 1; }
  b="$(basename "$rp")"; item="$latest/$b"
  dest="$rp"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    case "$b" in
      .*|*.*) if [ "${b#.}" != "$b" ] && [ "${b#.*.}" = "${b#.}" ]; then stem="$b"; ext=""; else stem="${b%.*}"; ext=".${b##*.}"; fi ;;
      *) stem="$b"; ext="" ;;
    esac
    dest="$(dirname "$rp")/$stem (복구)$ext"
    while [ -e "$dest" ]; do n=$((n+1)); dest="$(dirname "$rp")/$stem (복구 $n)$ext"; done
  fi
  mkdir -p "$(dirname "$dest")" && mv "$item" "$dest" || return 1
  rm -f "$latest/origin.txt"; rmdir "$latest" 2>/dev/null
  cl_say "되돌렸습니다: $dest"
}

space_ls() {
  local root dir; root="$(_space_resolve "$(cl_space_root)")"
  dir="$root${1:+/$1}"
  if [ "$(space_classify "$dir")" = outside ]; then cl_warn "작업 폴더 밖은 볼 수 없습니다."; return 1; fi
  ls -1 "$dir"
}

space_find() {
  local root f; root="$(_space_resolve "$(cl_space_root)")"
  find "$root" -mindepth 1 \( -name .cowork -o -name .cowork-lite \) -prune -o -iname "*$1*" -print |
    while IFS= read -r f; do printf '%s\n' "${f#"$root"/}"; done
}
