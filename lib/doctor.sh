#!/bin/bash
# doctor: 설치 상태를 쉬운 말로 점검한다. 모두 통과하면 0, 아니면 1.
# 의존: common, manifest, settings, space, guard, prereq (호출하는 쪽이 source 한다).

_doc_ok()  { cl_say "✔ $1"; }
_doc_bad() { cl_say "✘ $1"; cl_say "   → 다음에 할 일: $2"; DOCTOR_FAILS=$((DOCTOR_FAILS+1)); }

# doctor_check_registered_hooks <작업 폴더>
doctor_check_registered_hooks() {
  local root="$1" cmd out ok=1
  # 세션 시작 hook: 첫 줄이 [cowork-lite] 머리말이어야 한다.
  # 점검하느라 hook 을 실행할 뿐이므로 동기화(받기·올리기)는 하지 않게 신호를 준다(점검이 파일을 바꾸면 안 된다).
  if cmd="$(settings_our_command SessionStart)"; then
    out="$(COWORK_LITE_SKIP_SYNC=1 bash -c "$cmd" 2>/dev/null </dev/null | head -1)"
    case "$out" in "[cowork-lite]"*) ;; *) ok=0 ;; esac
  else
    ok=0
  fi
  # Guard hook: 받은자료 수정 시도를 실제 입력 형식으로 보내 deny가 나와야 한다.
  if cmd="$(settings_our_command PreToolUse)"; then
    out="$(printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/받은자료/.doctor-probe"}}' "$root" "$root" \
      | bash -c "$cmd" 2>/dev/null)"
    case "$out" in *'"permissionDecision":"deny"'*) ;; *) ok=0 ;; esac
  else
    ok=0
  fi
  if [ "$ok" = 1 ]; then _doc_ok "Claude에 등록된 안전장치 명령이 실제로 실행됩니다"
  else _doc_bad "Claude에 등록된 안전장치 명령이 실행되지 않습니다(경로가 깨졌을 수 있습니다)" "cowork-lite setup 을 다시 실행해 주세요"; fi
}

# 동기화 점검(동기화를 켠 경우에만 부른다). 점검만 하고 아무것도 올리거나 받지 않는다.
#  ✘(고쳐야 할 항목): GitHub 로그인 안 됨, 저장소 연결 안 됨, 공개 저장소, 저장소 없음, 자동 올리기 설정·파일 없음
#  ⚠(알리기만): 인터넷 때문에 확인 못 함, 아직 동기화한 적 없음, 해결하지 않은 충돌
# 의존: sync.sh(sync_repo_visibility, sync_conflict_files), settings.sh(settings_has_sync_hook, settings_sync_command)
doctor_check_sync() {
  local lf root repo out rc logged=0 connected=0 vis cmd last n url
  lf="$(cl_home)/local.json"; root="$(cl_space_root)"

  # 1) GitHub 로그인(gh 가 없으면 위에서 이미 알렸으므로 따지지 않는다)
  if prereq_check gh; then
    out="$(gh auth status 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then logged=1; _doc_ok "GitHub 에 로그인되어 있습니다"
    else
      case "$out" in
        *"error connecting"*|*"timeout"*|*"no such host"*|*"dial tcp"*|*"network"*)
          cl_say "⚠ GitHub 에 로그인되어 있는지 확인하지 못했습니다. (인터넷 연결을 확인해 주세요. 오류로 세지 않습니다)" ;;
        *) _doc_bad "GitHub 에 로그인되어 있지 않습니다" "터미널에서 gh auth login 으로 로그인해 주세요" ;;
      esac
    fi
  fi

  # 2) 저장소 연결
  repo="$(cl_json_get "$lf" sync.repo 2>/dev/null)"
  if [ -n "$repo" ] && [ -d "$root/.git" ] && url="$(git -C "$root" remote get-url origin 2>/dev/null)" && [ -n "$url" ]; then
    case "$url" in
      *github.com*) case "$url" in *"$repo"*) connected=1 ;; *) _doc_bad "작업 폴더에 연결된 저장소 주소($url)가 기록($repo)과 다릅니다" "cowork-lite sync setup 을 다시 실행해 주세요" ;; esac ;;
      *) connected=1 ;;
    esac
  else
    _doc_bad "작업 폴더가 GitHub 저장소와 연결되어 있지 않습니다" "cowork-lite sync setup 을 실행해 주세요"
  fi

  # 3) 비공개 여부(로그인돼 있고 연결돼 있을 때만 본다)
  if [ "$logged" = 1 ] && [ "$connected" = 1 ]; then
    vis="$(sync_repo_visibility "$repo")"
    case "$vis" in
      private) _doc_ok "GitHub 저장소 $repo 에 연결되어 있고 비공개입니다" ;;
      public)  _doc_bad "GitHub 저장소 $repo 이(가) 공개 저장소입니다" "GitHub 에서 비공개로 바꿔 주세요. 그 전에는 동기화하지 않는 것이 안전합니다(업무 파일이 누구에게나 보입니다)" ;;
      none)    _doc_bad "GitHub 저장소를 찾을 수 없습니다: $repo" "저장소를 지웠다면 cowork-lite sync setup 으로 다시 만들어 주세요" ;;
      *)       cl_say "⚠ GitHub 저장소가 비공개인지 확인하지 못했습니다. (인터넷 연결을 확인해 주세요. 오류로 세지 않습니다)" ;;
    esac
  fi

  # 4) 세션이 끝날 때 자동으로 올리는 설정(등록돼 있고, 등록된 파일이 실제로 있어야 한다). 실행해 보지는 않는다(실행하면 올라가 버린다).
  if cmd="$(settings_sync_command)"; then
    cmd="${cmd#\"}"; cmd="${cmd%\"}"
    if [ -f "$cmd" ]; then _doc_ok "세션이 끝날 때 자동으로 올리는 설정이 등록되어 있습니다"
    else _doc_bad "세션이 끝날 때 올리는 파일(session-end.sh)을 찾을 수 없습니다" "cowork-lite setup 을 다시 실행해 주세요"; fi
  else
    _doc_bad "세션이 끝날 때 자동으로 올리는 설정이 없습니다" "cowork-lite sync setup 을 실행해 주세요"
  fi

  # 5) 마지막 동기화, 해결하지 않은 충돌
  last="$(cl_json_get "$lf" sync.last 2>/dev/null)"
  if [ -n "$last" ]; then _doc_ok "마지막 동기화: $last"
  else cl_say "⚠ 아직 동기화한 적이 없습니다. (cowork-lite sync 로 처음 맞춰 보세요)"; fi
  n="$(sync_conflict_files | grep -c . || true)"
  [ "${n:-0}" -gt 0 ] && cl_say "⚠ 해결하지 않은 충돌이 ${n}개 있습니다. cowork-lite sync resolve 로 어느 쪽을 쓸지 정해 주세요"
  return 0
}

# 기본팩 점검. 설치 표식이 없으면 ✘(고쳐야 할 항목). 설치된 팩은 packs.json 의 점검 명령을 실행해 본다.
# 점검 명령이 아직 검증되지 않은 것(verified=false)은 실패해도 ✘ 로 세지 않고 ⚠ 로만 알린다(추정한 명령이 틀렸을 수 있어서).
# 의존: packs.sh(_packs_load, _packs_exec), setup.sh(_setup_done)
doctor_check_packs() {
  local line kind id="" title="" done=0 ver ex out rc
  local -a f argv
  if ! _packs_load; then
    _doc_bad "기본 스킬 목록(packs.json)을 읽지 못했습니다" "cowork-lite setup 을 다시 실행해 주세요"
    return
  fi
  while IFS= read -r line; do
    IFS=$'\t' read -r -a f <<< "$line"
    case "${f[0]}" in
      P)
        id="${f[1]}"; title="${f[2]}"
        if _setup_done "pack-$id"; then done=1; _doc_ok "기본 스킬 '$title' 이(가) 설치되어 있습니다"
        else done=0; _doc_bad "기본 스킬 '$title' 이(가) 설치되어 있지 않습니다" "cowork-lite setup 을 다시 실행해 주세요"; fi ;;
      V)
        [ "$done" = 1 ] || continue
        ver="${f[1]}"; ex="${f[2]}"; argv=("${f[@]:3}")
        out="$(_packs_exec "${argv[@]}" 2>&1 </dev/null)"; rc=$?
        if [ "$rc" -ne 0 ] || { [ "$ex" != "-" ] && [[ "$out" != *"$ex"* ]]; }; then
          if [ "${argv[0]}" = python ]; then
            # Python 은 선택 도구다(MarkItDown 용). 없거나 설치가 안 됐어도 문서 스킬 자체는 정상이므로 오류로 세지 않는다.
            cl_say "⚠ '$title': Python/MarkItDown 을 쓸 수 없습니다. MS 문서를 마크다운으로 바꾸는 도구만 빠지고 나머지는 정상입니다. 필요하면 Python 3.10 이상을 설치한 뒤 cowork-lite setup 을 다시 실행해 주세요."
          elif [ "$ver" = 1 ]; then
            _doc_bad "'$title' 점검 명령(${argv[0]})이 실패했습니다" "cowork-lite setup 을 다시 실행해 주세요"
          else
            cl_say "⚠ '$title' 점검 명령(${argv[0]})을 확인하지 못했습니다. (이 점검 명령은 아직 검증되지 않아 오류로 세지 않습니다)"
          fi
        fi ;;
    esac
  done <<< "$PACKS_LINES"
}

# 직접 만든 스킬(manifest 의 skill 항목)이 실제로 복사되어 있는지 본다.
doctor_check_skills() {
  local kind path
  while IFS=$'\t' read -r kind path; do
    [ "$kind" = skill ] && [ -n "$path" ] || continue
    if [ -f "$path/SKILL.md" ]; then _doc_ok "직접 만든 스킬 '$(basename "$path")' 이(가) 설치되어 있습니다"
    else _doc_bad "직접 만든 스킬 '$(basename "$path")' 이(가) 없습니다" "cowork-lite setup 을 다시 실행해 주세요"; fi
  done <<< "$(manifest_list)"
}

doctor_run() {
  local home root f d kind path probe res
  DOCTOR_FAILS=0
  home="$(cl_home)"; root="$(cl_space_root)"
  prereq_refresh_path

  if prereq_check claude; then _doc_ok "Claude Code가 설치되어 있습니다"
  else _doc_bad "Claude Code가 없습니다" "cowork-lite setup 을 다시 실행해 주세요"; fi

  if prereq_check node; then _doc_ok "Node.js가 설치되어 있습니다"
  else _doc_bad "Node.js가 없거나 버전이 낮습니다" "cowork-lite setup 을 다시 실행해 주세요"; fi

  # 동기화를 켠 경우에만 Git·gh 를 본다(로컬 전용 모드는 점검하지 않는다). 없어도 오류로 세지 않고 알리기만 한다.
  if cl_sync_enabled; then
    if prereq_check git; then _doc_ok "Git이 설치되어 있습니다"
    else cl_say "⚠ Git이 없습니다. 동기화에 필요합니다. (오류로 세지 않습니다. Windows: winget install --id Git.Git)"; fi
    if prereq_check gh; then _doc_ok "GitHub CLI(gh)가 설치되어 있습니다"
    else cl_say "⚠ GitHub CLI(gh)가 없습니다. 동기화에 필요합니다. (오류로 세지 않습니다. Windows: winget install --id GitHub.cli)"; fi
    doctor_check_sync
  fi

  if cl_json_valid "$home/local.json"; then _doc_ok "설정 파일(local.json)이 정상입니다"
  else _doc_bad "설정 파일(local.json)이 없거나 손상되었습니다" "cowork-lite setup 을 다시 실행해 주세요"; fi

  if settings_has_hooks; then _doc_ok "Claude에 cowork-lite hook 2종이 등록되어 있습니다"
  else _doc_bad "Claude에 cowork-lite hook이 등록되어 있지 않습니다" "cowork-lite setup 을 다시 실행해 주세요"; fi

  for f in guard.sh session.sh; do
    if [ -x "$home/hooks/$f" ]; then _doc_ok "hook 파일($f)을 실행할 수 있습니다"
    else _doc_bad "hook 파일($f)이 없거나 실행 권한이 없습니다" "cowork-lite setup 을 다시 실행해 주세요"; fi
  done

  # 등록된 명령을 Claude Code가 하는 것과 같은 방식(bash -c)으로 실제 실행해 본다. 파일이 있고 실행 권한이 있어도
  # 등록된 명령의 경로가 깨져 있으면(역슬래시 등) Claude Code는 hook 실패를 넘기고 보호가 조용히 꺼진다.
  doctor_check_registered_hooks "$root"

  for d in 받은자료 작업중 결과물 업무일지 .cowork; do
    if [ -d "$root/$d" ]; then _doc_ok "작업 폴더에 '$d' 폴더가 있습니다"
    else _doc_bad "작업 폴더에 '$d' 폴더가 없습니다" "cowork-lite setup 을 다시 실행하면 다시 만들어 줍니다"; fi
  done

  while IFS=$'\t' read -r kind path; do
    [ -n "$path" ] || continue
    [ "$kind" = skill ] && continue   # 스킬은 doctor_check_skills 가 본다
    if [ ! -e "$path" ]; then
      _doc_bad "설치 기록에 있는 항목이 없습니다: $(basename "$path")" "cowork-lite setup 을 다시 실행해 주세요"
    fi
  done <<< "$(manifest_list)"

  probe="$root/받은자료/.doctor-probe"
  res="$(guard_decide_file Edit "$probe")"
  if [ "${res%%$'\t'*}" = deny ]; then _doc_ok "Guard가 받은자료 수정을 막고 있습니다"
  else _doc_bad "Guard가 받은자료를 지키지 못하고 있습니다" "cowork-lite setup 을 다시 실행하거나 도움을 요청해 주세요"; fi

  doctor_check_packs
  doctor_check_skills

  if [ "$DOCTOR_FAILS" -eq 0 ]; then
    cl_say "모두 초록불 ✔"; return 0
  fi
  cl_say "고쳐야 할 항목이 ${DOCTOR_FAILS}개 있습니다"; return 1
}
