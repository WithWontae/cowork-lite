#!/bin/bash
# Guard 판정 엔진(순수 함수). 판정 결과는 한 줄: `LEVEL<TAB>쉬운 말 사유`
# LEVEL = allow | backup | ask | deny
#
# 주의: Bash 명령 판정은 완전한 셸 파서가 아니라 휴리스틱이다. python 스크립트 안의 삭제,
# 변수로 조립한 명령, 난독화된 명령은 잡지 못한다. 이 Guard는 실수를 막는 장치이며
# 보안 경계가 아니다(설계 문서 §7, §15-1).
#
# 의존: lib/common.sh, lib/space.sh. bash 3.2 호환.

GUARD_SECRET_HINT="비밀번호·키 파일은 읽거나 보낼 수 없습니다."

_guard_out() { printf '%s\t%s\n' "$1" "$2"; }

_guard_is_secret() {
  case "$1" in
    *.pem|*.pfx|*.p12|*/.ssh|*/.ssh/*|.ssh/*|*/.aws/credentials|*/.env|*/.env.*|.env|.env.*|*id_rsa*|*id_ed25519*) return 0 ;;
  esac
  return 1
}

_guard_is_system() {
  case "$1" in
    /etc|/etc/*|/private/etc|/private/etc/*|/System|/System/*|/usr|/usr/*|/Library|/Library/*|/bin|/bin/*|/sbin|/sbin/*) return 0 ;;
  esac
  return 1
}

_guard_is_tmp() {
  local t
  case "$1" in /tmp/*|/private/tmp/*|/private/var/folders/*|/var/folders/*|/dev/*) return 0 ;; esac
  # Windows: 경로를 통일하면 /tmp 가 실제 Temp 위치(/c/Users/…/Temp)로 나온다. 대소문자는 구분하지 않는다.
  if cl_is_windows; then
    _space_tmp_posix
    case "${1,,}" in "${_SPACE_TMP,,}"/*) return 0 ;; esac
  fi
  if [ -n "$TMPDIR" ]; then
    _space_resolve_r "$TMPDIR"; t="$REPLY"
    case "$1" in "$t"/*) return 0 ;; esac
  fi
  return 1
}

# 경로 토큰의 ~, $HOME, ${HOME}을 실제 HOME으로 바꿔 출력한다.
# 그 밖의 변수·명령 치환이 남아 있으면 정확한 경로를 알 수 없으므로 1을 돌려준다.
_guard_expand_path() {
  local p="$1" rest
  case "$p" in
    "~"|'$HOME'|'${HOME}') p="$HOME" ;;
    "~/"*|'$HOME/'*|'${HOME}/'*) rest="${p#*/}"; p="$HOME/$rest" ;;
  esac
  printf '%s\n' "$p"
  case "$p" in *'$'*|*'`'*) return 1 ;; esac
  return 0
}

# 쓰기 대상 한 곳의 판정. Bash 안에서 부르면(_GUARD_CTX=bash) 기존 작업 파일 덮어쓰기는 확인을 묻는다
# (명령 안의 대상 파일을 hook이 미리 사본 뜰 수 없기 때문).
_guard_write_level() {
  local raw="$1" p rp cls
  if ! p="$(_guard_expand_path "$raw")"; then
    case "$raw" in
      *받은자료*) _guard_out deny "받은자료일 수 있는 경로라 바꿀 수 없습니다. 경로를 풀어서 다시 알려 주세요." ;;
      *)          _guard_out ask "경로를 정확히 알 수 없습니다. 계속할까요?" ;;
    esac
    return
  fi
  if [ "${_GUARD_CD:-0}" = 1 ]; then
    case "$p" in
      /*) ;;
      *받은자료*) _guard_out deny "받은자료일 수 있는 경로라 바꿀 수 없습니다. 전체 경로로 다시 알려 주세요."; return ;;
      *)          _guard_out ask "폴더를 옮긴 뒤의 상대 경로라 정확한 위치를 알 수 없습니다. 계속할까요?"; return ;;
    esac
  fi
  _space_resolve_r "$p"; rp="$REPLY"
  if _guard_is_system "$rp"; then _guard_out deny "시스템 폴더는 바꿀 수 없습니다."; return; fi
  space_classify_r "$p"; cls="$REPLY"
  case "$cls" in
    inbox)    _guard_out deny "받은자료의 원본은 바꿀 수 없습니다. 작업중 폴더로 복사해서 작업할까요?" ;;
    internal) _guard_out deny "내부 관리 폴더라 직접 바꿀 수 없습니다." ;;
    outside)
      if _guard_is_tmp "$rp"; then _guard_out allow ""; else _guard_out ask "작업 폴더 밖에 파일을 쓰려고 합니다. 계속할까요?"; fi ;;
    *)
      if [ "${_GUARD_CTX:-}" = bash ] && [ -f "$p" ]; then
        _guard_out ask "작업 중인 파일을 덮어쓰거나 바꾸려고 합니다. 계속할까요?"
      else
        _guard_out allow ""
      fi ;;
  esac
}

# guard_decide_file <tool_name> <file_path>
guard_decide_file() {
  local tool="$1" path="$2" out cls policy
  if [ -z "$path" ]; then _guard_out deny "대상 파일을 알 수 없어 안전을 위해 멈췄습니다."; return; fi
  case "$tool" in
    Read)
      if _guard_is_secret "$path"; then _guard_out deny "$GUARD_SECRET_HINT"; else _guard_out allow ""; fi
      return ;;
    Write|Edit|MultiEdit|NotebookEdit) ;;
    *) _guard_out deny "알 수 없는 도구라 안전을 위해 멈췄습니다."; return ;;
  esac
  out="$(_guard_write_level "$path")"
  if [ "${out%%$'\t'*}" != allow ]; then printf '%s\n' "$out"; return; fi
  space_classify_r "$path"; cls="$REPLY"
  if [ "$cls" != outside ] && [ -e "$path" ]; then
    cl_space_root_r
    policy="$(cl_json_get "$REPLY/.cowork-lite/shared.json" space.modify_policy)"
    if [ "$policy" = ask ]; then
      _guard_out ask "작업 중인 파일을 바꾸려고 합니다. 계속할까요?"
    else
      _guard_out backup "수정하기 전에 사본을 만들어 둡니다."
    fi
    return
  fi
  _guard_out allow ""
}

# ---------------------------------------------------------------- Bash

# 명령을 세그먼트(줄)로 나눈다. 예전의 sed 여러 개와 같은 순서·같은 결과이고, 프로세스를 띄우지 않는다.
_guard_split_segments() {
  local s="${1//>|/>}" nl=$'\n'
  s="${s//\$\(/$nl}"; s="${s//\`/$nl}"; s="${s//&&/$nl}"; s="${s//||/$nl}"
  s="${s//[;|()&]/$nl}"
  printf '%s\n' "$s"
}

# 따옴표를 풀어 한 줄에 토큰 하나로 나눈다. 실패하면 단순 공백 분리로 대체한다.
_guard_tokenize() {
  local seg="$1" t line
  _GT=()
  # -n1 을 쓰면 토큰마다 printf 프로세스가 따로 뜬다(Windows에서 느림). 한 번에 넘겨도 출력은 같다.
  t="$(printf '%s\n' "$seg" | xargs printf '%s\n' 2>/dev/null)" || t=""
  if [ -z "$t" ]; then t="$(set -f; printf '%s\n' $seg)"; fi
  while IFS= read -r line; do
    [ -n "$line" ] && _GT[${#_GT[@]}]="$line"
  done <<< "$t"
}

# 호출한 함수의 best 변수를 갱신한다(bash 동적 범위). deny면 출력하고 1을 돌려준다.
_guard_consider() {
  case "${1%%$'\t'*}" in
    deny) printf '%s\n' "$1"; return 1 ;;
    ask) [ -z "$best" ] && best="$1" ;;
  esac
  return 0
}

# cowork-lite space rm 의 대상을 보고 판정한다: 받은자료·밖은 거부, 그 외는 개수를 알려 주며 확인(ask).
_guard_space_rm() {
  local tok p cls total=0 c label=""
  for tok in "$@"; do
    case "$tok" in -*) continue ;; esac
    if ! p="$(_guard_expand_path "$tok")"; then _guard_out ask "경로를 정확히 알 수 없습니다. 계속할까요?"; return; fi
    cls="$(space_classify "$p")"
    case "$cls" in
      inbox)            _guard_out deny "받은자료는 지울 수 없습니다. 작업중 폴더로 복사한 뒤 지워 주세요."; return ;;
      outside|internal) _guard_out deny "작업 폴더 밖이나 내부 폴더는 지울 수 없습니다."; return ;;
    esac
    [ -n "$label" ] || case "$cls" in result) label="결과물" ;; journal) label="업무일지" ;; *) label="작업중" ;; esac
    c="$(_space_count_files "$p")"; total=$((total + c))
  done
  [ -n "$label" ] || { _guard_out ask "지울 파일을 알 수 없습니다. 계속할까요?"; return; }
  _guard_out ask "$label 폴더의 파일 ${total}개를 지우려고 합니다. 계속할까요?"
}

_guard_segment() {
  local seg="$1" depth="$2" n i idx base0 tok b r best="" last="" sedi=0 skipped=0 t j
  local -a T nonopt
  _guard_tokenize "$seg"
  T=("${_GT[@]}"); n=${#T[@]}
  [ "$n" -gt 0 ] || { _guard_out allow ""; return; }

  idx=0
  while [ "$idx" -lt "$n" ]; do
    case "${T[$idx]}" in
      [A-Za-z_]*=*|sudo|env|command|nohup|time|nice|exec|xargs) idx=$((idx+1)); continue ;;
    esac
    break
  done
  base0=""; [ "$idx" -lt "$n" ] && base0="${T[$idx]##*/}"

  # 비어 있지 않은 옵션 아닌 토큰(명령 이후)
  nonopt=()
  i=$((idx+1))
  while [ "$i" -lt "$n" ]; do
    tok="${T[$i]}"
    case "$tok" in -*) ;; *) nonopt[${#nonopt[@]}]="$tok" ;; esac
    i=$((i+1))
  done

  # cowork-lite space rm <경로…> : 휴지통으로 옮기는 명령이라 삭제 차단 대신 사용자 확인으로 보낸다.
  if [ "$base0" = cowork-lite ] && [ "${T[$((idx+1))]:-}" = space ] && [ "${T[$((idx+2))]:-}" = rm ]; then
    _guard_space_rm "${T[@]:$((idx+3))}"
    return
  fi

  # A. 삭제 명령
  for tok in "${T[@]}"; do
    b="${tok##*/}"
    case "$b" in
      rm|rmdir|unlink|shred)
        _guard_out deny "삭제는 cowork-lite space rm --yes-bulk <경로> 로 해 주세요. (확인한 뒤 휴지통으로 옮깁니다)"; return ;;
    esac
  done
  if [ "$base0" = find ]; then
    for tok in "${T[@]}"; do
      [ "$tok" = "-delete" ] && { _guard_out deny "삭제는 cowork-lite space rm --yes-bulk <경로> 로 해 주세요. (확인한 뒤 휴지통으로 옮깁니다)"; return; }
    done
  fi

  # B. sh -c "…", eval "…" 안쪽 명령
  if [ "$depth" -lt 3 ]; then
    case "$base0" in
      sh|bash|zsh|dash)
        j=$((idx+1))
        while [ "$j" -lt "$n" ]; do
          case "${T[$j]}" in
            -c|-lc|-ic|-ec|-xc)
              if [ $((j+1)) -lt "$n" ]; then
                r="$(guard_decide_bash "${T[$((j+1))]}" $((depth+1)))"
                _guard_consider "$r" || return
              fi
              break ;;
          esac
          j=$((j+1))
        done ;;
      eval)
        r="$(guard_decide_bash "${T[*]:$((idx+1))}" $((depth+1)))"
        _guard_consider "$r" || return ;;
    esac
  fi

  # C. 비밀 파일 읽기·전송
  case "$base0" in
    cat|less|more|head|tail|cp|mv|scp|curl|rsync|sftp|base64|xxd|strings|grep|awk|sed|tar|zip|open)
      i=$((idx+1))
      while [ "$i" -lt "$n" ]; do
        tok="${T[$i]}"
        if _guard_is_secret "$tok" || _guard_is_secret "${tok#*@}"; then
          _guard_out deny "$GUARD_SECRET_HINT"; return
        fi
        i=$((i+1))
      done ;;
  esac

  # D. 명령별 쓰기 대상
  case "$base0" in
    mv)
      for tok in "${nonopt[@]}"; do
        r="$(_guard_write_level "$tok")"; _guard_consider "$r" || return
        case "$tok" in *[*?[]*) _guard_consider "$(_guard_out ask "많은 파일을 한 번에 옮기거나 복사하려고 합니다. 계속할까요?")" || return ;; esac
      done ;;
    cp|install)
      if [ "${#nonopt[@]}" -gt 0 ]; then
        last="${nonopt[$((${#nonopt[@]}-1))]}"
        r="$(_guard_write_level "$last")"; _guard_consider "$r" || return
      fi
      for tok in "${nonopt[@]}"; do
        case "$tok" in *[*?[]*) _guard_consider "$(_guard_out ask "많은 파일을 한 번에 옮기거나 복사하려고 합니다. 계속할까요?")" || return ;; esac
      done ;;
    sed)
      for tok in "${T[@]}"; do
        case "$tok" in -i|-i*|--in-place*) sedi=1 ;; esac
      done
      if [ "$sedi" -eq 1 ]; then
        i=0
        for tok in "${nonopt[@]}"; do
          i=$((i+1)); [ "$i" -eq 1 ] && continue   # 첫 토큰은 sed 스크립트
          r="$(_guard_write_level "$tok")"; _guard_consider "$r" || return
        done
      fi ;;
    tee)
      for tok in "${nonopt[@]}"; do
        r="$(_guard_write_level "$tok")"; _guard_consider "$r" || return
      done ;;
    dd)
      for tok in "${T[@]}"; do
        case "$tok" in of=*) r="$(_guard_write_level "${tok#of=}")"; _guard_consider "$r" || return ;; esac
      done ;;
  esac

  # E. 리다이렉트 (모든 명령)
  i=0
  while [ "$i" -lt "$n" ]; do
    tok="${T[$i]}"; t=""
    case "$tok" in
      *'>'*)
        # `>file` `>>file` `2>file` `echo x>file` `> file` `2> file` 모두: 마지막 > 뒤가 대상, 비었으면 다음 토큰
        t="${tok##*>}"
        if [ -z "$t" ] && [ $((i+1)) -lt "$n" ]; then t="${T[$((i+1))]}"; fi
        t="${t#"${t%%[! ]*}"}" ;;
    esac
    if [ -n "$t" ] && [ "${t#&}" = "$t" ]; then
      r="$(_guard_write_level "$t")"; _guard_consider "$r" || return
    fi
    i=$((i+1))
  done

  # F. 외부 전송
  case "$base0" in
    scp|rsync|sendmail|mail|ftp|sftp|nc|ncat|telnet)
      _guard_consider "$(_guard_out ask "파일이나 정보를 밖으로 보내려는 명령입니다. 계속할까요?")" || return ;;
    curl)
      for tok in "${T[@]}"; do
        case "$tok" in
          -d*|--data*|-F|--form*|-T|--upload*|-X)
            _guard_consider "$(_guard_out ask "파일이나 정보를 밖으로 보내려는 명령입니다. 계속할까요?")" || return
            break ;;
        esac
      done ;;
  esac

  if [ -n "$best" ]; then printf '%s\n' "$best"; else _guard_out allow ""; fi
}

# guard_decide_bash <command> [depth]
guard_decide_bash() {
  # _GUARD_CTX: 쓰기 대상 판정에 Bash 문맥임을 알린다. _GUARD_CD: 앞 세그먼트에 cd가 있었는지
  # (그 뒤의 상대 경로는 정확한 위치를 알 수 없다). 둘 다 동적 범위로 하위 함수가 읽는다.
  local cmd="$1" depth="${2:-0}" segs seg r best="" _GUARD_CTX=bash _GUARD_CD="${_GUARD_CD:-0}"
  local cd_re='(^|[[:space:]])(cd|pushd)([[:space:]]|$)'
  [ -n "$cmd" ] || { _guard_out allow ""; return; }
  segs="$(_guard_split_segments "$cmd")"
  while IFS= read -r seg; do
    # 공백·탭뿐인 세그먼트는 건너뛴다(tr·grep 프로세스 대신 bash 내장 기능)
    [ -n "${seg//[ $'\t']/}" ] || continue
    r="$(_guard_segment "$seg" "$depth")"
    _guard_consider "$r" || return
    if [[ "$seg" =~ $cd_re ]]; then _GUARD_CD=1; fi
  done <<< "$segs"
  if [ -n "$best" ]; then printf '%s\n' "$best"; else _guard_out allow ""; fi
}

# guard_log <level> <tool> <note> : 경로·내용은 남기지 않는다(영문·숫자·_ 만).
guard_log() {
  local level tool note root
  # 허용 문자 밖은 지운다(tr -cd 와 같은 동작, 프로세스를 띄우지 않는다). 문자 범위가 로케일 순서를 따르지 않게 한다.
  shopt -s globasciiranges 2>/dev/null
  level="${1//[^a-z_]/}"
  tool="${2//[^A-Za-z0-9_]/}"
  note="${3//[^A-Za-z0-9_]/}"
  cl_space_root_r; root="$REPLY"
  [ -d "$root" ] || return 0
  # 폴더가 이미 있으면 mkdir 프로세스를 띄우지 않는다(판정마다 불리므로 Windows에서 80ms를 아낀다).
  [ -d "$root/.cowork" ] || mkdir -p "$root/.cowork" 2>/dev/null || return 0
  printf '{"t":"%s","level":"%s","tool":"%s","note":"%s"}\n' "$(cl_stamp)" "$level" "$tool" "$note" >> "$root/.cowork/log.jsonl"
}
