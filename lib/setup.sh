#!/bin/bash
# 설치(setup)·제거(uninstall) 흐름. 단계마다 완료 표식을 남겨 중간에 끊겨도 이어서 진행한다.
# 단계: prereq → identity → (미리보기 확인) → space → hooks → path → doctor
# 롤백: 설정 파일(hook)·PATH 블록·복사한 파일만 되돌린다. 작업 폴더의 사용자 파일은 절대 지우지 않는다.
# 의존: common, manifest, settings, space, guard, prereq, doctor. bash 3.2 호환.

SETUP_MARK_BEGIN="# >>> cowork-lite >>>"
SETUP_MARK_END="# <<< cowork-lite <<<"

_setup_state_dir() { printf '%s\n' "$(cl_home)/state"; }
_setup_done() { [ -f "$(_setup_state_dir)/$1.done" ]; }
_setup_mark() { mkdir -p "$(_setup_state_dir)" && : > "$(_setup_state_dir)/$1.done"; }

_setup_label() {
  case "$1" in
    prereq) echo "선행 도구" ;; identity) echo "내 정보" ;; space) echo "작업 폴더" ;;
    hooks) echo "안전장치 등록" ;; path) echo "명령 경로" ;; *) echo "$1" ;;
  esac
}

_setup_lock() { cl_lock_acquire; }
_setup_unlock() { cl_lock_release; }

# 질문. COWORK_LITE_YES가 있으면 묻지 않고 기본값을 쓴다. 답은 COWORK_LITE_TTY(기본 /dev/tty)에서 읽는다.
_setup_ask() {
  local ans=""
  if [ -n "$COWORK_LITE_YES" ]; then printf '%s\n' "$2"; return; fi
  printf '%s [%s]: ' "$1" "$2" >&2
  IFS= read -r ans 2>/dev/null < "${COWORK_LITE_TTY:-/dev/tty}" || ans=""
  printf '%s\n' "${ans:-$2}"
}

_setup_identity() {
  local name="${COWORK_LITE_NAME:-}" f; f="$(cl_home)/local.json"
  [ -n "$name" ] || name="$(_setup_ask "표시 이름을 입력해 주세요" "${USER:-사용자}")"
  cl_json_set "$f" display.name "$name" || return 1
  cl_json_set "$f" language ko || return 1
  cl_say "표시 이름은 '$name', 언어는 한국어로 설정했습니다."
}

_setup_space() {
  local root f; root="$(cl_space_root)"
  space_init >/dev/null || return 1
  cl_json_set "$(cl_home)/local.json" space.root "$root" || return 1
  cl_json_set "$(cl_home)/local.json" device.name "$(hostname -s 2>/dev/null || echo mac)" || return 1
  f="$root/.cowork-lite/shared.json"
  cl_json_get "$f" space.modify_policy >/dev/null || cl_json_set "$f" space.modify_policy backup || return 1
  cl_say "작업 폴더를 준비했습니다: $root"
}

_setup_hooks() {
  local home; home="$(cl_home)"
  settings_register_hooks "$home/hooks/session.sh" "$home/hooks/guard.sh" || return 1
  manifest_add file "$home/hooks/session.sh"
  manifest_add file "$home/hooks/guard.sh"
  cl_say "Claude에 안전장치 2개를 등록했습니다."
}

_setup_path() {
  local zshrc="$HOME/.zshrc" home; home="$(cl_home)"
  [ -f "$zshrc" ] || : > "$zshrc" || return 1
  if ! grep -qF "$SETUP_MARK_BEGIN" "$zshrc"; then
    printf '\n%s\nexport PATH="%s/bin:$PATH"\n%s\n' "$SETUP_MARK_BEGIN" "$home" "$SETUP_MARK_END" >> "$zshrc" || return 1
    manifest_add pathblock "$zshrc"
  fi
  cl_say "터미널에서 cowork-lite 명령을 쓸 수 있게 했습니다. (새 터미널부터 적용됩니다)"
}

_setup_path_remove() {
  local zshrc="$HOME/.zshrc" tmp
  [ -f "$zshrc" ] || return 0
  grep -qF "$SETUP_MARK_BEGIN" "$zshrc" || { manifest_remove_all_of pathblock; return 0; }
  # 시작·끝 표식이 둘 다 있을 때만 지운다(끝 표식이 없으면 사용자 줄까지 지울 수 있다)
  if ! grep -qF "$SETUP_MARK_END" "$zshrc"; then
    cl_warn "~/.zshrc의 cowork-lite 표시가 일부 지워져 있어 건드리지 않았습니다. 직접 확인해 주세요."
    return 0
  fi
  tmp="$(mktemp "$zshrc.XXXXXX")" || return 1
  awk -v b="$SETUP_MARK_BEGIN" -v e="$SETUP_MARK_END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$zshrc" > "$tmp" \
    && cat "$tmp" > "$zshrc"
  rm -f "$tmp"
  manifest_remove_all_of pathblock
}

_setup_files_remove() {
  local home item; home="$(cl_home)"
  for item in bin lib hooks packs.json VERSION; do rm -rf "${home:?}/$item"; done
}

_setup_rollback() {
  cl_warn "설치를 끝내지 못해 바꾼 내용을 되돌립니다. (작업 폴더의 파일은 건드리지 않습니다)"
  settings_unregister_hooks >/dev/null 2>&1
  _setup_path_remove
  rm -f "$(_setup_state_dir)/hooks.done" "$(_setup_state_dir)/path.done"
  manifest_remove_all_of file
  _setup_files_remove
  cl_warn "한 줄 설치 명령을 다시 붙여넣으면 끝낸 단계는 건너뛰고 이어서 진행합니다."
}

_setup_step() {
  local name="$1" fn="$2" label; label="$(_setup_label "$1")"
  if _setup_done "$name"; then cl_say "✔ $label 단계는 이미 끝나 건너뜁니다."; return 0; fi
  if ! "$fn"; then
    cl_warn "✘ '$label' 단계에서 문제가 생겼습니다."
    _setup_rollback
    return 1
  fi
  _setup_mark "$name"
}

_setup_preview() {
  cl_say "설치하기 전에 확인해 주세요. 아래 내용이 바뀝니다."
  cl_say "- Claude에 안전장치(hook) 2개를 등록합니다. 바뀌는 파일: $(settings_path) (바꾸기 전에 자동으로 백업합니다)"
  cl_say "- 터미널 설정 파일(~/.zshrc)에 cowork-lite 명령 경로를 한 줄 추가합니다."
  cl_say "- 작업 폴더를 만듭니다: $(cl_space_root) (받은자료·작업중·결과물·업무일지)"
  cl_say "- 설치 위치: $(cl_home)"
  [ -n "$COWORK_LITE_YES" ] && return 0
  _space_confirm "이대로 설치할까요?" || { cl_say "취소했습니다. 작업 폴더와 설정 파일은 바뀌지 않았습니다."; return 1; }
}

_setup_run_inner() {
  _setup_step prereq prereq_run_all || return 1
  _setup_step identity _setup_identity || return 1
  if ! _setup_done space || ! _setup_done hooks || ! _setup_done path; then
    _setup_preview || return 1
  fi
  _setup_step space _setup_space || return 1
  _setup_step hooks _setup_hooks || return 1
  _setup_step path _setup_path || return 1
  doctor_run
}

setup_run() {
  local rc
  _setup_lock || return 1
  trap '_setup_unlock; exit 130' INT TERM HUP
  COWORK_LITE_LOCK_HELD=1 _setup_run_inner; rc=$?
  trap - INT TERM HUP
  _setup_unlock
  return $rc
}

uninstall_run() {
  local home item root; home="$(cl_home)"; root="$(cl_space_root)"
  if [ -z "$COWORK_LITE_YES" ]; then
    _space_confirm "cowork-lite를 제거할까요? 작업 폴더의 파일은 지우지 않습니다." \
      || { cl_say "취소했습니다."; return 1; }
  fi
  # hook 해제에 실패하면 파일을 지우지 않는다(설정이 없는 파일을 가리켜 Guard가 꺼지는 것을 막는다)
  settings_unregister_hooks || {
    cl_warn "Claude 설정에서 안전장치를 지우지 못해 제거를 멈췄습니다. 설정 파일을 확인한 뒤 다시 시도해 주세요."
    return 1
  }
  _setup_path_remove
  for item in bin lib hooks state packs.json VERSION manifest.tsv; do rm -rf "${home:?}/$item"; done
  cl_say "제거했습니다. 작업 폴더($root)와 설정 백업은 그대로 남겨 두었습니다."
}
