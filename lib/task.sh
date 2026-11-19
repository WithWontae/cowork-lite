#!/bin/bash
# 업무 폴더 관리(v0.6). 업무 하나 = 폴더 하나다.
#   작업중/<번호>_<업무이름>/   진행 중인 업무. 이 안에서 파일을 만들고 고치고 지운다.
#   결과물/<번호>_<업무이름>/   완료한 업무. 업무 폴더를 통째로 옮긴다.
# 번호는 작업중·결과물 전체에서 가장 큰 번호 + 1 이라, 완료했다가 다시 가져와도 같은 이름이다.
# 의존: common(cl_space_root, cl_say, cl_warn). bash 3.2 호환(연관 배열·mapfile 을 쓰지 않는다).

TASK_ACTIVE_DIR="작업중"
TASK_DONE_DIR="결과물"

_task_dir() { printf '%s\n' "$(cl_space_root)/$1"; }

# 폴더 이름이 "숫자_이름" 꼴인가(업무 폴더). 그 밖의 파일·폴더는 업무가 아니라서 건드리지 않는다.
_task_is_name() { case "$1" in [0-9][0-9]*_?*) [[ "$1" =~ ^[0-9]+_.+ ]] ;; *) return 1 ;; esac; }
_task_num_of() { local n="${1%%_*}"; printf '%s\n' "$((10#$n))"; }

# 이름에서 폴더에 쓸 수 없는 글자를 지우고 40자로 자른다. 끝의 점·공백도 지운다.
task_sanitize_name() {
  local s="$1"
  s="$(printf '%s' "$s" | tr -d '\\/:*?"<>|' | tr -d '\000-\037' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  # 40글자로 자른다. 한글 같은 여러 바이트 글자가 중간에서 잘리지 않게, 로캘과 상관없이 글자 수를 세는 UTF-32 로 바꿔 자른다.
  if command -v iconv >/dev/null 2>&1; then
    s="$(printf '%s' "$s" | iconv -f UTF-8 -t UTF-32LE 2>/dev/null | head -c 160 | iconv -f UTF-32LE -t UTF-8 2>/dev/null)" || s="${s:0:40}"
  else
    s="${s:0:40}"
  fi
  s="$(printf '%s' "$s" | sed 's/[. ]*$//')"
  printf '%s\n' "$s"
}

# 작업중·결과물의 업무 폴더 이름을 한 줄씩(번호 순) 출력한다. _task_names <작업중|결과물>
_task_names() {
  local d="$(_task_dir "$1")" e name
  [ -d "$d" ] || return 0
  for e in "$d"/*/; do
    [ -d "$e" ] || continue
    name="$(basename "$e")"
    _task_is_name "$name" && printf '%s\n' "$name"
  done | sort
}

_task_next_number() {
  local max=0 name n
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    n="$(_task_num_of "$name")"
    [ "$n" -gt "$max" ] && max="$n"
  done <<< "$(_task_names "$TASK_ACTIVE_DIR"; _task_names "$TASK_DONE_DIR")"
  printf '%s\n' "$((max + 1))"
}

# task_new <이름> : 작업중/<번호>_<이름>/ 폴더를 만든다.
task_new() {
  local raw="$*" name num folder
  name="$(task_sanitize_name "$raw")"
  if [ -z "$name" ]; then cl_warn "✘ 업무 이름을 입력해 주세요. 예: cowork-lite task new \"견적서 비교\""; return 2; fi
  num="$(_task_next_number)"
  folder="$(printf '%03d_%s' "$num" "$name")"
  mkdir -p "$(_task_dir "$TASK_ACTIVE_DIR")/$folder" || { cl_warn "✘ 업무 폴더를 만들지 못했습니다."; return 1; }
  cl_say "✔ 새 업무를 만들었습니다: $TASK_ACTIVE_DIR/$folder"
  cl_say "폴더: $(_task_dir "$TASK_ACTIVE_DIR")/$folder"
}

# task_list [--done] [--raw] : 진행 중(기본) 또는 완료한 업무 목록. --raw 는 폴더 이름만 한 줄씩.
task_list() {
  local area="$TASK_ACTIVE_DIR" raw=0 label="진행 중인 업무" a names name
  for a in "$@"; do
    case "$a" in --done) area="$TASK_DONE_DIR"; label="완료한 업무" ;; --raw) raw=1 ;; esac
  done
  names="$(_task_names "$area")"
  if [ "$raw" = 1 ]; then [ -n "$names" ] && printf '%s\n' "$names"; return 0; fi
  if [ -z "$names" ]; then cl_say "$label가 없습니다."; return 0; fi
  cl_say "$label:"
  while IFS= read -r name; do cl_say "- $name"; done <<< "$names"
}

# _task_resolve <작업중|결과물> <번호 또는 이름> : 업무 폴더 이름 하나를 REPLY 에 둔다. 없거나 여럿이면 이유를 알리고 1.
_task_resolve() {
  local area="$1" arg="$2" name matches="" count=0 want
  if [ -z "$arg" ]; then cl_warn "✘ 업무 번호나 이름을 알려 주세요."; return 1; fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [[ "$arg" =~ ^[0-9]+$ ]]; then
      want="$((10#$arg))"
      [ "$(_task_num_of "$name")" = "$want" ] || continue
    elif [ "$name" = "$arg" ]; then
      matches="$name"; count=1; break
    else
      case "$name" in *"$arg"*) ;; *) continue ;; esac
    fi
    matches="${matches:+$matches
}$name"; count=$((count + 1))
  done <<< "$(_task_names "$area")"
  if [ "$count" -eq 0 ]; then cl_warn "✘ '$arg' 업무를 $area 에서 찾지 못했습니다. cowork-lite task list 로 확인해 주세요."; return 1; fi
  if [ "$count" -gt 1 ]; then
    cl_warn "✘ '$arg' 에 해당하는 업무가 여러 개입니다. 번호나 전체 이름으로 다시 알려 주세요:"
    while IFS= read -r name; do cl_warn "   - $name"; done <<< "$matches"
    return 1
  fi
  REPLY="$matches"
}

# 업무 폴더를 통째로 옮긴다. _task_move <from> <to> <번호 또는 이름>
_task_move() {
  local from="$1" to="$2" arg="$3" src dst
  _task_resolve "$from" "$arg" || return 1
  src="$(_task_dir "$from")/$REPLY"; dst="$(_task_dir "$to")/$REPLY"
  if [ -e "$dst" ]; then cl_warn "✘ $to 에 같은 이름의 폴더가 이미 있어 옮기지 않았습니다: $REPLY"; return 1; fi
  mkdir -p "$(_task_dir "$to")" || return 1
  if ! mv "$src" "$dst"; then
    cl_warn "✘ 폴더를 옮기지 못했습니다. 그 폴더의 파일이 다른 프로그램에서 열려 있으면 닫고 다시 해 주세요."
    return 1
  fi
  _TASK_MOVED="$REPLY"
}

# task_done <번호 또는 이름> : 작업중의 업무 폴더를 통째로 결과물로 옮긴다.
task_done() {
  _task_move "$TASK_ACTIVE_DIR" "$TASK_DONE_DIR" "$1" || return 1
  cl_say "✔ 업무를 완료했습니다: $_TASK_MOVED  (작업중 → 결과물)"
}

# task_reopen <번호 또는 이름> : 완료한 업무 폴더를 다시 작업중으로 가져온다.
task_reopen() {
  _task_move "$TASK_DONE_DIR" "$TASK_ACTIVE_DIR" "$1" || return 1
  cl_say "✔ 업무를 다시 진행 중으로 가져왔습니다: $_TASK_MOVED  (결과물 → 작업중)"
  cl_say "폴더: $(_task_dir "$TASK_ACTIVE_DIR")/$_TASK_MOVED"
}

# task_path <번호 또는 이름> : 진행 중인 업무의 폴더 경로를 출력한다.
task_path() {
  _task_resolve "$TASK_ACTIVE_DIR" "$1" || return 1
  printf '%s\n' "$(_task_dir "$TASK_ACTIVE_DIR")/$REPLY"
}

# task_show <번호 또는 이름> : 진행 중인 업무를 3줄로 요약한다(폴더·파일 수, 최근 바뀐 것, 마지막 세션 정리의 남은 일).
task_show() {
  local name dir files recent root; root="$(cl_space_root)"
  _task_resolve "$TASK_ACTIVE_DIR" "$1" || return 1
  name="$REPLY"; dir="$root/$TASK_ACTIVE_DIR/$name"
  files="$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ')"
  recent="$(ls -1t "$dir" 2>/dev/null | head -3 | paste -sd, - | sed 's/,/, /g')"
  cl_say "업무: $name"
  cl_say "- 폴더 $TASK_ACTIVE_DIR/$name, 파일 ${files}개"
  if [ -n "$recent" ]; then cl_say "- 최근 바뀐 것: $recent"; else cl_say "- 아직 파일이 없습니다."; fi
  if type journal_last_section >/dev/null 2>&1; then
    journal_last_section "$root"
    if [ -n "$REPLY" ]; then
      cl_say "- 마지막 세션 정리:"
      printf '%s\n' "$REPLY" | sed 's/^/    /'
    fi
  fi
}

# task_resume_hint <작업 폴더> : 진행 중인 업무를 최대 3건 한 줄로 REPLY 에 둔다(없으면 빈 값). 세션을 시작할 때 쓰므로 외부 프로그램 없이 bash 만 쓴다.
task_resume_hint() {
  local root="$1" e n total=0 shown="" k=0
  REPLY=""
  for e in "$root/$TASK_ACTIVE_DIR"/*/; do
    [ -d "$e" ] || continue
    n="${e%/}"; n="${n##*/}"
    [[ "$n" =~ ^[0-9]+_.+ ]] || continue
    total=$((total + 1))
    if [ "$k" -lt 3 ]; then shown="${shown:+$shown, }$n"; k=$((k + 1)); fi
  done
  [ "$total" -gt 0 ] || return 0
  REPLY="진행 중인 업무 ${total}건: $shown"
  [ "$total" -gt 3 ] && REPLY="$REPLY 외 $((total - 3))건"
  return 0
}
