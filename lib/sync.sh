#!/bin/bash
# 작업 폴더(cowork-space)를 내 GitHub 의 비공개 저장소와 연결한다(설계 §8b, 계획서 P0b Task 3).
# 사용자에게 git 용어는 보이지 않는다. 안내는 쉬운 말로 한다. 저장소는 반드시 비공개(private)일 때만 연결한다.
# 이 파일은 연결(저장소 확인·생성, 로컬 준비, .gitignore)까지만 한다. 받기·올리기·충돌은 이후 단계에서 추가한다.
# 테스트: COWORK_LITE_SYNC_REMOTE 가 있으면 GitHub 주소 대신 그 주소(로컬 폴더 등)를 origin 으로 쓴다.
# 의존: common. bash 3.2 호환.

SYNC_REPO_DEFAULT="cowork-workspace"
SYNC_IGNORE_BEGIN="# >>> cowork-lite sync >>>"
SYNC_IGNORE_END="# <<< cowork-lite sync <<<"

# 올리지 않을 것(설계 §8b): 수정 전 사본·휴지통, 비밀값 파일 패턴. 50MB 초과 파일은 이후 단계(Task 6)에서 다룬다.
# .cowork/log.jsonl(Guard 판정 기록)은 기기마다 다른 파일이라 올리면 매번 충돌하므로 제외한다(설계에 없던 추가).
_sync_ignore_lines() {
  cat <<'EOF'
.cowork/backup/
.cowork/trash/
.cowork/log.jsonl
*.pem
*.key
*.p12
*.pfx
*.kdbx
.env
.env.*
id_rsa*
id_ed25519*
EOF
}

# 작업 폴더의 .gitignore 에 cowork-lite 블록을 넣는다. 사용자가 쓰던 내용은 그대로 두고, 이미 블록이 있으면 다시 넣지 않는다.
sync_ignore_write() {
  local root f; root="$(cl_space_root)"; f="$root/.gitignore"
  mkdir -p "$root" || return 1
  if [ -f "$f" ] && grep -qF "$SYNC_IGNORE_BEGIN" "$f"; then return 0; fi
  { [ -s "$f" ] && printf '\n'; printf '%s\n' "$SYNC_IGNORE_BEGIN"; _sync_ignore_lines; printf '%s\n' "$SYNC_IGNORE_END"; } >> "$f"
}

# sync_repo_visibility <소유자/이름> : private | public | none | error 중 하나를 출력한다.
# 확인하지 못한 경우(인터넷 문제 등)는 none 이 아니라 error 다. 없는 것으로 보고 만들어 버리면 안 되기 때문이다.
sync_repo_visibility() {
  local out rc
  out="$(gh repo view "$1" --json isPrivate --jq .isPrivate 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    case "$out" in true) echo private ;; false) echo public ;; *) echo error ;; esac
  else
    case "$out" in *"Could not resolve to a Repository"*|*"Not Found"*|*"not found"*|*"404"*) echo none ;; *) echo error ;; esac
  fi
}

# sync_connect [저장소 이름] : GitHub 의 비공개 저장소를 만들거나 찾아 작업 폴더에 연결한다. 연결하면 0, 못 하면 1.
# 기본 이름은 cowork-workspace(COWORK_LITE_SYNC_REPO 로 바꿀 수 있다).
sync_connect() {
  local name="${1:-${COWORK_LITE_SYNC_REPO:-$SYNC_REPO_DEFAULT}}" root owner uid vis remote cur lf mode
  lf="$(cl_home)/local.json"; root="$(cl_space_root)"
  if ! command -v git >/dev/null 2>&1 || ! command -v gh >/dev/null 2>&1; then
    cl_warn "⚠ 동기화에는 Git 과 GitHub CLI(gh)가 필요합니다. 설치한 뒤 cowork-lite sync setup 을 다시 실행해 주세요."
    return 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    cl_warn "⚠ GitHub 에 로그인되어 있지 않습니다. 터미널에서 gh auth login 으로 로그인한 뒤 cowork-lite sync setup 을 실행해 주세요."
    return 1
  fi
  owner="$(gh api user --jq .login 2>/dev/null)"; uid="$(gh api user --jq .id 2>/dev/null)"
  if [ -z "$owner" ] || [ -z "$uid" ]; then
    cl_warn "✘ GitHub 계정 정보를 확인하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 실행해 주세요."
    return 1
  fi

  vis="$(sync_repo_visibility "$owner/$name")"
  case "$vis" in
    private) mode=existing; cl_say "✔ 비공개 저장소 $owner/$name 이(가) 있어 그곳에 연결합니다." ;;
    public)
      cl_warn "✘ $owner/$name 은(는) 공개 저장소입니다. 업무 파일이 누구에게나 보이게 되므로 연결하지 않습니다."
      cl_warn "   GitHub 에서 비공개로 바꾸거나, COWORK_LITE_SYNC_REPO 로 다른 이름을 지정해 주세요."
      return 1 ;;
    error)
      cl_warn "✘ 저장소 상태를 확인하지 못했습니다(인터넷 연결이나 로그인을 확인해 주세요). 안전을 위해 연결하지 않습니다."
      return 1 ;;
    none)
      mode=new
      if [ -z "$COWORK_LITE_YES" ]; then
        type _space_confirm >/dev/null 2>&1 || { cl_warn "확인을 받을 수 없어 저장소를 만들지 않았습니다."; return 1; }
        _space_confirm "내 GitHub 에 업무 파일 보관용 비공개 저장소($owner/$name)를 만들까요?" || { cl_say "저장소를 만들지 않았습니다. 나중에 cowork-lite sync setup 으로 다시 할 수 있습니다."; return 1; }
      fi
      if ! gh repo create "$owner/$name" --private --description "cowork-lite 작업 폴더 보관용" >/dev/null 2>&1; then
        cl_warn "✘ 저장소를 만들지 못했습니다. 인터넷 연결이나 GitHub 권한을 확인해 주세요."
        return 1
      fi
      # 만든 뒤에도 비공개인지 다시 확인한다. 아니면 연결하지 않는다.
      if [ "$(sync_repo_visibility "$owner/$name")" != private ]; then
        cl_warn "✘ 만든 저장소가 비공개인지 확인하지 못했습니다. 안전을 위해 연결하지 않습니다. GitHub 에서 $owner/$name 을 확인해 주세요."
        return 1
      fi
      cl_say "✔ 비공개 저장소 $owner/$name 을(를) 만들었습니다." ;;
  esac

  remote="${COWORK_LITE_SYNC_REMOTE:-https://github.com/$owner/$name.git}"
  mkdir -p "$root" || return 1
  if [ ! -d "$root/.git" ]; then
    git -C "$root" init -q 2>/dev/null || { cl_warn "✘ 작업 폴더를 동기화용으로 준비하지 못했습니다."; return 1; }
    git -C "$root" symbolic-ref HEAD refs/heads/main 2>/dev/null
  fi
  cur="$(git -C "$root" remote get-url origin 2>/dev/null)"
  if [ -n "$cur" ] && [ "$cur" != "$remote" ]; then
    cl_warn "✘ 작업 폴더가 이미 다른 저장소($cur)에 연결되어 있어 그대로 둡니다."
    return 1
  fi
  [ -n "$cur" ] || git -C "$root" remote add origin "$remote" || return 1
  # 이 폴더에서만 쓰는 설정이다. 커밋 작성자는 GitHub 의 비공개 주소(noreply)를 쓴다. 한글 파일 이름이 깨지지 않게 한다.
  git -C "$root" config user.name "$owner"
  git -C "$root" config user.email "$uid+$owner@users.noreply.github.com"
  git -C "$root" config core.quotepath off
  git -C "$root" config core.autocrlf false
  sync_ignore_write || return 1
  cl_json_set "$lf" sync.repo "$owner/$name" || return 1
  cl_json_set "$lf" sync.mode "$mode" || return 1
  cl_say "✔ 작업 폴더를 GitHub 의 $owner/$name (비공개)에 연결했습니다."
}

# 세션이 끝날 때 올리는 hook(SessionEnd)을 Claude 설정에 등록한다. 동기화를 켜고 연결까지 끝난 경우에만 부른다. 멱등.
sync_register_hook() {
  local home; home="$(cl_home)"
  [ -f "$home/hooks/session-end.sh" ] || { cl_warn "세션 종료 때 자동으로 올리는 파일(session-end.sh)을 찾지 못했습니다. cowork-lite setup 을 다시 실행해 주세요."; return 1; }
  settings_register_sync_hook "\"$home/hooks/session-end.sh\"" || return 1
  manifest_add file "$home/hooks/session-end.sh"
  cl_say "✔ 세션이 끝날 때 자동으로 올리고, 시작할 때 자동으로 받도록 설정했습니다."
}

# 연결에 실패했을 때 동기화를 끈다. 단, 전에 연결에 성공한 적이 있으면(sync.repo 가 기록돼 있으면) 그대로 둔다:
# 잘 쓰던 사용자가 오프라인 같은 일시적인 이유로 setup 을 다시 실행했을 뿐인데 동기화가 꺼지면 안 된다.
# 끄면 0, 그대로 두면 1.
_sync_turn_off_unless_connected_before() {
  [ -n "$(cl_json_get "$(cl_home)/local.json" sync.repo 2>/dev/null)" ] && return 1
  cl_json_set "$(cl_home)/local.json" sync.enabled false
}

# 동기화를 켠다(나중에 켜는 경로와 설치 중 경로가 같다): 설정 → Git·gh 확인 → 로그인 → 저장소 연결 → 자동 실행 등록.
sync_setup() {
  cl_json_set "$(cl_home)/local.json" sync.enabled true || return 1
  prereq_git_optional
  prereq_gh_optional
  if ! sync_connect "$@"; then
    # 처음 연결하는 경우에는 연결 없이 켜진 채로 두지 않는다(세션을 시작할 때마다 실패 안내가 나오고 doctor 가 실패한다).
    if _sync_turn_off_unless_connected_before; then
      cl_warn "동기화는 켜지 않은 채로 둡니다. 위 안내대로 준비한 뒤 cowork-lite sync setup 을 다시 실행해 주세요."
    else
      cl_warn "동기화 연결을 확인하지 못했습니다. 이전 설정은 그대로 두었습니다. 문제를 해결한 뒤 다시 실행해 주세요."
    fi
    return 1
  fi
  sync_register_hook
}

# 세션을 시작할 때: 다른 노트북의 변경을 받고, 지난 세션에 못 올린 변경을 올린다. 결과를 "[동기화] ..." 줄로 출력한다(Claude 가 읽는다).
# 바뀐 것이 없으면 아무것도 출력하지 않는다. 실패해도 항상 0(세션은 계속된다).
sync_auto_start() {
  local out line
  out="$(sync_run --auto 2>&1)"
  [ -n "$out" ] || return 0
  printf '[동기화] 시작할 때 자동으로 맞춘 결과입니다. 충돌이나 실패가 있으면 사용자에게 쉬운 말로 알려 주세요.\n'
  while IFS= read -r line; do printf '[동기화] %s\n' "$line"; done <<< "$out"
  return 0
}

# 세션이 끝날 때: 변경을 올리고 결과를 기록(sync.log)에 남긴다. 기록이 300줄을 넘으면 최근 200줄만 남긴다. 항상 0.
sync_auto_end() {
  local log out; log="$(cl_home)/sync.log"
  out="$(sync_run --auto 2>&1)"
  if [ -n "$out" ]; then
    { printf '[%s] 세션 종료 동기화\n' "$(date '+%Y-%m-%d %H:%M')"; printf '%s\n' "$out"; } >> "$log"
  fi
  if [ -f "$log" ] && [ "$(wc -l < "$log" | tr -d ' ')" -gt 300 ]; then
    tail -n 200 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
  fi
  return 0
}

# ---------------------------------------------------------------------------------------------
# 동기화 실행(Task 4): 받아오기 → 내 변경 저장 → 합치기 → 올리기. 같은 파일을 양쪽에서 고쳤으면 아무것도 바꾸지 않고 멈춘다
# (충돌 사본 만들기는 Task 5). 어느 단계가 실패해도 내 파일은 그대로 둔다. git 은 항상 작업 폴더 안에서만 부른다.
# ---------------------------------------------------------------------------------------------

_sync_g() { git -C "$(cl_space_root)" "$@"; }

# 동시에 두 번 돌지 않게 한다(자동 실행과 수동 실행이 겹칠 수 있다). 죽은 프로세스의 잠금은 치운다.
_sync_lock() {
  local d pid; d="$(cl_home)/sync.lock"
  mkdir -p "$(cl_home)" || return 1
  if mkdir "$d" 2>/dev/null; then echo "$$" > "$d/pid"; return 0; fi
  pid="$(cat "$d/pid" 2>/dev/null)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then return 1; fi
  rm -rf "$d"; mkdir "$d" 2>/dev/null && echo "$$" > "$d/pid"
}
_sync_unlock() { rm -rf "$(cl_home)/sync.lock" 2>/dev/null; return 0; }

# 연결·켜짐 확인. 안 돼 있으면 쉬운 말로 알리고 1.
_sync_ready() {
  local root; root="$(cl_space_root)"
  if ! cl_sync_enabled; then
    cl_warn "동기화를 켜지 않았습니다. 켜려면 cowork-lite sync setup 을 실행해 주세요."; return 1
  fi
  if [ ! -d "$root/.git" ] || ! git -C "$root" remote get-url origin >/dev/null 2>&1; then
    cl_warn "아직 GitHub 저장소와 연결되지 않았습니다. cowork-lite sync setup 을 실행해 주세요."; return 1
  fi
  command -v git >/dev/null 2>&1 || { cl_warn "Git 이 없습니다. cowork-lite sync setup 으로 준비해 주세요."; return 1; }
}

# 표준입력의 비어 있지 않은 줄 수.
_sync_count() { grep -c . 2>/dev/null || true; }

# 올리지 않는 큰 파일의 기준(바이트). 기본 50MB(GitHub 는 파일당 100MB 한도라 여유를 둔다). 시험에서는 COWORK_LITE_SYNC_MAX_BYTES 로 줄인다.
_sync_max_bytes() { printf '%s\n' "${COWORK_LITE_SYNC_MAX_BYTES:-52428800}"; }
_sync_limit_text() {
  local b; b="$(_sync_max_bytes)"
  if [ $((b % 1048576)) -eq 0 ] && [ "$b" -ge 1048576 ]; then printf '%sMB\n' $((b / 1048576)); else printf '%s바이트\n' "$b"; fi
}
_sync_size_text() {
  local b; b="$(wc -c < "$1" 2>/dev/null | tr -d ' ')"
  if [ "${b:-0}" -ge 1048576 ]; then printf '%sMB\n' $((b / 1048576)); else printf '%s바이트\n' "${b:-0}"; fi
}

# 기준을 넘는 파일(작업 폴더 기준 경로, 정렬). 기준과 같은 크기는 올린다.
sync_large_files() {
  local root f max; root="$(cl_space_root)"; max="$(_sync_max_bytes)"
  [ -d "$root" ] || return 0
  find "$root" -type f -size +"${max}"c -not -path "$root/.git/*" 2>/dev/null | while IFS= read -r f; do printf '%s\n' "${f#"$root"/}"; done | sort
}

# 비밀값 패턴(.gitignore) 때문에 올리지 않은 파일. 앱 내부 폴더(.cowork/)는 알리지 않는다. 내용은 읽지 않는다.
sync_secret_files() {
  local root; root="$(cl_space_root)"
  [ -d "$root/.git" ] || return 0
  git -c core.quotepath=off -C "$root" ls-files -o -i --exclude-standard 2>/dev/null | grep -v '^\.cowork/' | sort
}

# 올리지 않은 파일(큰 파일·비밀값 파일)을 알린다. 없으면 아무 말도 하지 않는다.
_sync_report_skipped() {
  local root large secrets f; root="$(cl_space_root)"
  large="$(sync_large_files)"; secrets="$(sync_secret_files)"
  if [ -n "$large" ]; then
    cl_say "⚠ 크기 제한($(_sync_limit_text))을 넘는 파일은 올리지 않았습니다. 아래 파일은 이 노트북에만 있습니다:"
    while IFS= read -r f; do cl_say "   - $f ($(_sync_size_text "$root/$f"))"; done <<< "$large"
  fi
  if [ -n "$secrets" ]; then
    cl_say "ℹ 비밀값으로 보이는 파일은 올리지 않았습니다. 아래 파일은 이 노트북에만 있습니다:"
    while IFS= read -r f; do cl_say "   - $f"; done <<< "$secrets"
  fi
  return 0
}

# 충돌 사본 목록(작업 폴더 기준 경로, 정렬). 사본은 "<파일명>.충돌-<기기명>" 이다.
sync_conflict_files() {
  local root f; root="$(cl_space_root)"
  [ -d "$root" ] || return 0
  find "$root" -type f -name '*.충돌-*' -not -path "$root/.git/*" 2>/dev/null | while IFS= read -r f; do printf '%s\n' "${f#"$root"/}"; done | sort
}

# 다른 노트북의 기기 이름. 그 파일을 마지막으로 바꾼 자동 저장 커밋("자동 저장 <기기> <시각>")에서 읽는다. 모르면 "다른기기".
_sync_remote_device() {
  local msg dev
  msg="$(git -C "$(cl_space_root)" log -1 --no-merges --format=%s origin/main -- "$1" 2>/dev/null)"
  dev="$(printf '%s\n' "$msg" | sed -n 's/^자동 저장 \([^ ]*\) .*/\1/p')"
  printf '%s\n' "${dev:-다른기기}" | tr ' /\\:' '----'
}

# 충돌 사본 이름. 같은 이름이 이미 있으면(앞선 충돌의 사본) 번호를 붙여 덮어쓰지 않는다.
_sync_copy_name() {  # <경로> <기기>
  local root p="$1" dev="$2" c i=2; root="$(cl_space_root)"
  c="$p.충돌-$dev"
  while [ -e "$root/$c" ] || git -C "$root" ls-files --error-unmatch -- "$c" >/dev/null 2>&1; do c="$p.충돌-$dev-$i"; i=$((i+1)); done
  printf '%s\n' "$c"
}

# 합치다 충돌한 파일을 어느 쪽도 지우지 않는 방식으로 정리하고 합치기를 마무리한다. 정리한 내용을 줄마다 "종류<탭>경로<탭>사본"으로 출력한다.
#  - 양쪽이 고침/양쪽이 새로 만듦: 이 노트북의 파일은 그대로 두고, 다른 노트북의 내용을 충돌 사본으로 남긴다.
#  - 여기서 지웠는데 저쪽에서 고침: 고친 파일을 되살린다.  여기서 고쳤는데 저쪽에서 지움: 고친 파일을 남긴다.
#  - 처음 연결한 노트북의 설정 파일(.cowork-lite/shared.json): 설치가 만든 기본값이므로 저장된 설정을 불러온다.
# 합치기를 마무리하지 못하면 1.
_sync_resolve_conflicts() {
  local root="$1" p st h2 h3 dev copy first=0
  [ -z "$(cl_json_get "$(cl_home)/local.json" sync.last 2>/dev/null)" ] && first=1
  while IFS= read -r -d '' p; do
    st="|$(git -C "$root" ls-files -u -- "$p" | awk '{print $3}' | tr '\n' '|')"
    h2=0; h3=0
    case "$st" in *"|2|"*) h2=1 ;; esac
    case "$st" in *"|3|"*) h3=1 ;; esac
    if [ "$h2" = 1 ] && [ "$h3" = 1 ]; then
      if [ "$p" = ".cowork-lite/shared.json" ] && [ "$first" = 1 ]; then
        git -C "$root" checkout --theirs -- "$p" && git -C "$root" add -- "$p" || return 1
        printf 'settings\t%s\t\n' "$p"
      else
        dev="$(_sync_remote_device "$p")"; copy="$(_sync_copy_name "$p" "$dev")"
        git -C "$root" show ":3:$p" > "$root/$copy" || return 1
        git -C "$root" checkout --ours -- "$p" && git -C "$root" add -- "$p" "$copy" || return 1
        printf 'both\t%s\t%s\n' "$p" "$copy"
      fi
    elif [ "$h3" = 1 ]; then
      git -C "$root" show ":3:$p" > "$root/$p" && git -C "$root" add -- "$p" || return 1
      printf 'revived\t%s\t\n' "$p"
    else
      git -C "$root" add -- "$p" || return 1
      printf 'kept\t%s\t\n' "$p"
    fi
  done < <(git -C "$root" diff --name-only --diff-filter=U -z 2>/dev/null)
  git -C "$root" commit -q --no-edit >/dev/null 2>&1
}

# 충돌을 정리한 결과를 쉬운 말로 알린다. 입력은 _sync_resolve_conflicts 의 출력.
_sync_report_conflicts() {
  local kind p copy any=0
  while IFS=$'\t' read -r kind p copy; do
    case "$kind" in both|revived|kept) any=1 ;; esac
  done <<< "$1"
  [ "$any" = 1 ] && cl_say "⚠ 같은 파일을 양쪽에서 고쳐서, 어느 쪽도 지우지 않고 남겼습니다."
  while IFS=$'\t' read -r kind p copy; do
    case "$kind" in
      both)     cl_say "   - $p  (다른 노트북의 내용은 $copy 에 있습니다)" ;;
      revived)  cl_say "   - $p  (이 노트북에서 지웠지만 다른 노트북에서 고쳐서 되살렸습니다)" ;;
      kept)     cl_say "   - $p  (다른 노트북에서 지웠지만 이 노트북에서 고쳐서 남겼습니다)" ;;
      settings) cl_say "처음 연결이라 저장된 설정($p)을 불러왔습니다." ;;
    esac
  done <<< "$1"
  [ "$any" = 1 ] && cl_say "어느 쪽을 쓸지 정한 뒤, cowork-lite sync resolve 의 안내대로 정리해 주세요."
  return 0
}

# sync_resolve : 충돌 사본이 있으면 어느 쪽을 쓰는 방법을 안내한다.
sync_resolve() {
  local files f orig
  files="$(sync_conflict_files)"
  if [ -z "$files" ]; then cl_say "해결할 충돌이 없습니다."; return 0; fi
  cl_say "같은 파일을 양쪽에서 고친 것이 있습니다. 어느 쪽도 지우지 않고 두 벌을 남겨 두었습니다."
  while IFS= read -r f; do
    orig="${f%.충돌-*}"
    cl_say "- $orig"
    cl_say "    다른 노트북의 내용: $f"
    cl_say "    이 노트북의 내용을 쓰려면: 충돌 사본($f)을 cowork-lite space rm 으로 지웁니다."
    cl_say "    다른 노트북의 내용을 쓰려면: $orig 에 사본의 내용을 옮겨 적은 뒤, 충돌 사본을 cowork-lite space rm 으로 지웁니다."
  done <<< "$files"
  cl_say "정리한 뒤 cowork-lite sync 를 실행하면 다른 노트북에도 반영됩니다. Claude 에게 \"충돌 사본 정리해 줘\"라고 부탁해도 됩니다."
}

# sync_status : 연결된 저장소, 올리지 않은 변경 수, 마지막 동기화 시각.
sync_status() {
  local lf repo last pending conflicts; lf="$(cl_home)/local.json"
  _sync_ready || return 1
  repo="$(cl_json_get "$lf" sync.repo)"; last="$(cl_json_get "$lf" sync.last)"
  pending="$(_sync_g status --porcelain 2>/dev/null | _sync_count)"
  conflicts="$(sync_conflict_files | _sync_count)"
  cl_say "연결된 저장소: ${repo:-알 수 없음} (비공개)"
  cl_say "아직 올리지 않은 파일: ${pending:-0}개"
  cl_say "해결하지 않은 충돌: ${conflicts:-0}개"
  cl_say "이 노트북에만 있는 큰 파일: $(sync_large_files | _sync_count)개 (크기 제한 $(_sync_limit_text) 초과)"
  cl_say "마지막 동기화: ${last:-아직 없음}"
}

# sync_run [--dry-run] : 0 성공(또는 이미 최신), 1 실패·중단.
sync_run() {
  local dry=0 auto=0 root before after n out conflicts has_remote has_head pend incoming resolved="" large f a
  # --auto: 자동 실행(세션 시작·종료). 받은 것·충돌·실패만 알리고, 바뀐 것이 없거나 안 올린 큰 파일·비밀값 파일 안내는 반복하지 않는다.
  for a in "$@"; do case "$a" in --dry-run) dry=1 ;; --auto) auto=1 ;; esac; done
  # hook 에는 입력할 터미널이 없다. 자격 증명을 묻다가 멈추지 않게 하고, 네트워크가 멈추면 20초 뒤에 포기한다.
  export GIT_TERMINAL_PROMPT=0 GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=20
  _sync_ready || return 1
  root="$(cl_space_root)"
  if ! _sync_lock; then cl_warn "다른 동기화가 진행 중입니다. 잠시 뒤에 다시 실행해 주세요."; return 1; fi

  # 1) 받아오기(가져오기만 한다. 내 파일은 아직 건드리지 않는다)
  if ! out="$(git -C "$root" fetch -q origin 2>&1)"; then
    cl_warn "✘ GitHub 에서 받아오지 못했습니다. 인터넷 연결이나 로그인을 확인해 주세요. 내 파일은 그대로입니다."
    _sync_unlock; return 1
  fi
  has_remote=0; git -C "$root" rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1 && has_remote=1
  has_head=0; git -C "$root" rev-parse -q --verify HEAD >/dev/null 2>&1 && has_head=1

  if [ "$dry" = 1 ]; then
    pend="$(git -C "$root" status --porcelain 2>/dev/null | _sync_count)"
    incoming=0
    if [ "$has_remote" = 1 ]; then
      if [ "$has_head" = 1 ] && git -C "$root" merge-base HEAD origin/main >/dev/null 2>&1; then
        incoming="$(git -C "$root" diff --name-only HEAD...origin/main 2>/dev/null | _sync_count)"
      else
        incoming="$(git -C "$root" ls-tree -r --name-only origin/main 2>/dev/null | _sync_count)"
      fi
    fi
    cl_say "미리보기(바뀌는 것은 없습니다): 올릴 변경 ${pend:-0}개, 받을 파일 ${incoming:-0}개, 올리지 않는 큰 파일 $(sync_large_files | _sync_count)개"
    _sync_unlock; return 0
  fi

  # 2) 내 변경 저장(합치기 전에 먼저 기록해 두면 어떤 경우에도 내 내용이 남는다)
  # 크기 제한을 넘는 파일은 저장 대상에서 뺀다(내용을 읽기 전에 경로로 제외하므로 큰 파일을 다루느라 오래 걸리지 않는다).
  local -a addargs; addargs=(add -A -- .)
  large="$(sync_large_files)"
  if [ -n "$large" ]; then
    while IFS= read -r f; do addargs+=(":(exclude,literal)$f"); done <<< "$large"
  fi
  git -C "$root" "${addargs[@]}" >/dev/null 2>&1
  if ! git -C "$root" diff --cached --quiet 2>/dev/null; then
    git -C "$root" commit -q -m "자동 저장 $(cl_json_get "$(cl_home)/local.json" device.name 2>/dev/null) $(date '+%Y-%m-%d %H:%M')" >/dev/null 2>&1 \
      || { cl_warn "✘ 내 변경을 저장하지 못했습니다."; _sync_unlock; return 1; }
    has_head=1
  fi

  # 3) 합치기
  if [ "$has_remote" = 1 ]; then
    if [ "$has_head" = 0 ] || ! git -C "$root" merge-base --is-ancestor origin/main HEAD 2>/dev/null; then
      before="$(git -C "$root" rev-parse -q --verify HEAD 2>/dev/null)"
      if out="$(git -C "$root" merge -q --no-edit --allow-unrelated-histories origin/main 2>&1)"; then
        after="$(git -C "$root" rev-parse HEAD)"
        if [ -n "$before" ]; then n="$(git -C "$root" diff --name-only "$before" "$after" | _sync_count)"
        else n="$(git -C "$root" ls-files | _sync_count)"; fi
        cl_say "✔ 다른 노트북의 변경 ${n:-0}개 파일을 받았습니다."
      else
        conflicts="$(git -C "$root" diff --name-only --diff-filter=U 2>/dev/null)"
        # 충돌한 파일이 없는데 합치기가 실패했거나, 정리를 마치지 못하면 합치던 것을 취소하고 멈춘다(내 파일은 그대로).
        if [ -z "$conflicts" ] || ! resolved="$(_sync_resolve_conflicts "$root")"; then
          git -C "$root" merge --abort >/dev/null 2>&1
          cl_warn "✘ 다른 노트북의 변경을 합치지 못해 아무것도 바꾸지 않고 멈췄습니다(내 파일은 그대로입니다)."
          _sync_unlock; return 1
        fi
        cl_say "✔ 다른 노트북의 변경을 받았습니다."
      fi
    fi
  fi

  # 4) 올리기
  if [ "$has_remote" = 1 ]; then n="$(git -C "$root" diff --name-only origin/main HEAD 2>/dev/null | _sync_count)"
  else n="$(git -C "$root" ls-files 2>/dev/null | _sync_count)"; fi
  if [ "$has_head" = 1 ] && { [ "$has_remote" = 0 ] || [ "$(git -C "$root" rev-list --count origin/main..HEAD 2>/dev/null)" != 0 ]; }; then
    cl_say "${n:-0}개 파일을 올립니다."
    if ! out="$(git -C "$root" push -q -u origin HEAD:main 2>&1)"; then
      cl_warn "✘ GitHub 로 올리지 못했습니다. 인터넷 연결이나 로그인을 확인해 주세요. 내 파일은 그대로이고, 다음에 다시 올립니다."
      _sync_unlock; return 1
    fi
    cl_say "✔ ${n:-0}개 파일을 올렸습니다."
  else
    [ "$auto" = 1 ] || cl_say "✔ 이미 최신입니다."
  fi
  cl_json_set "$(cl_home)/local.json" sync.last "$(date '+%Y-%m-%d %H:%M')" >/dev/null 2>&1
  [ -z "$resolved" ] || _sync_report_conflicts "$resolved"
  [ "$auto" = 1 ] || _sync_report_skipped
  _sync_unlock
  return 0
}
