#!/bin/bash
# 기본팩 설치. 무엇을 설치할지는 packs.json(데이터)이 정하고, 이 파일은 그 목록을 차례로 실행만 한다.
# 기본팩은 전부 필수다: 하나라도 실패하면 1을 돌려주고, 호출하는 setup이 전체를 되돌린다.
# 팩 단위로 완료 표식(state/pack-<id>.done)을 남겨 다시 실행하면 끝난 팩은 건너뛴다.
# 테스트: COWORK_LITE_PACK_EXEC=<bash 스크립트>가 있으면 외부 명령 대신 그 스크립트로 인자를 넘긴다(외부 프로그램을 설치하지 않기 위해).
# packs.json 은 node 한 번으로 모두 읽는다(필드마다 plutil 을 부르면 Windows 에서 1분 넘게 걸린다). node 는 선행 도구라 이 단계에는 있다.
# 의존: common. setup.sh의 _setup_done/_setup_mark를 쓴다. bash 3.2 호환.

PACKS_FILE_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packs.json"
_PACKS_JS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shim/packs.js"
_packs_file() { printf '%s\n' "${COWORK_LITE_PACKS_FILE:-$PACKS_FILE_DEFAULT}"; }

# plutil 로 하나씩 읽어 node 방식(packs.js)과 같은 줄 형식을 만든다. Mac 은 plutil 이 빨라 이 방식을 쓴다.
_packs_load_plutil() {
  local f n i j k m argc id title type line a; f="$(_packs_file)"
  n="$(plutil -extract packs raw -o - "$f" 2>/dev/null)" || return 1
  PACKS_LINES=""; i=0
  while [ "$i" -lt "${n:-0}" ]; do
    id="$(plutil -extract "packs.$i.id" raw -o - "$f" 2>/dev/null)" || return 1
    title="$(plutil -extract "packs.$i.title" raw -o - "$f" 2>/dev/null)" || return 1
    PACKS_LINES="$PACKS_LINES"$'P\t'"$id"$'\t'"$title"$'\n'
    m="$(plutil -extract "packs.$i.install" raw -o - "$f" 2>/dev/null)" || return 1; j=0
    while [ "$j" -lt "${m:-0}" ]; do
      type="$(plutil -extract "packs.$i.install.$j.type" raw -o - "$f" 2>/dev/null)"
      case "$type" in
        run)
          argc="$(plutil -extract "packs.$i.install.$j.argv" raw -o - "$f" 2>/dev/null)" || return 1
          [ "${argc:-0}" -gt 0 ] || return 1
          line=$'S\trun'
          a="$(plutil -extract "packs.$i.install.$j.optional" raw -o - "$f" 2>/dev/null)"
          case "$a" in true|1) line=$'S\trun-optional' ;; esac
          k=0
          while [ "$k" -lt "$argc" ]; do
            a="$(plutil -extract "packs.$i.install.$j.argv.$k" raw -o - "$f" 2>/dev/null)" || return 1
            line="$line"$'\t'"$a"; k=$((k+1))
          done ;;
        remote-script)
          line=$'S\tremote-script\t'"$(plutil -extract "packs.$i.install.$j.windows_url" raw -o - "$f" 2>/dev/null)"$'\t'"$(plutil -extract "packs.$i.install.$j.unix_url" raw -o - "$f" 2>/dev/null)"$'\t'"$(plutil -extract "packs.$i.install.$j.provides" raw -o - "$f" 2>/dev/null || printf -)" ;;
        *) return 1 ;;
      esac
      PACKS_LINES="$PACKS_LINES$line"$'\n'
      j=$((j+1))
    done
    # 점검 명령: V<TAB>검증여부<TAB>expect(없으면 -)<TAB>인자…
    m="$(plutil -extract "packs.$i.verify" raw -o - "$f" 2>/dev/null)" || m=0; j=0
    while [ "$j" -lt "${m:-0}" ]; do
      type="$(plutil -extract "packs.$i.verify.$j.type" raw -o - "$f" 2>/dev/null)"
      [ "$type" = run ] || return 1
      argc="$(plutil -extract "packs.$i.verify.$j.argv" raw -o - "$f" 2>/dev/null)" || return 1
      [ "${argc:-0}" -gt 0 ] || return 1
      a="$(plutil -extract "packs.$i.verify.$j.verified" raw -o - "$f" 2>/dev/null)"
      case "$a" in true|1) a=1 ;; *) a=0 ;; esac
      line="$(plutil -extract "packs.$i.verify.$j.expect" raw -o - "$f" 2>/dev/null)" || line="-"
      [ -n "$line" ] || return 1
      line=$'V\t'"$a"$'\t'"$line"; k=0
      while [ "$k" -lt "$argc" ]; do
        a="$(plutil -extract "packs.$i.verify.$j.argv.$k" raw -o - "$f" 2>/dev/null)" || return 1
        line="$line"$'\t'"$a"; k=$((k+1))
      done
      PACKS_LINES="$PACKS_LINES$line"$'\n'
      j=$((j+1))
    done
    i=$((i+1))
  done
  PACKS_LINES="${PACKS_LINES%$'\n'}"
  [ -n "$PACKS_LINES" ]
}

# _packs_load : 팩 목록을 PACKS_LINES(탭으로 나뉜 줄들)에 읽는다. 읽지 못하면 1.
# node 가 확정된 곳(Windows: plutil 이 없어 node 로 흉내 내는 곳)에서는 node 한 번으로, 아니면 plutil 로 읽는다.
_packs_load() {
  local node="${CL_NODE:-}" f js
  [ -n "$node" ] || { _packs_load_plutil; return; }
  f="$(_packs_file)"; js="$_PACKS_JS"
  # (테스트가 OS를 mac 으로 덮어써도 Git Bash 의 node 는 윈도우 경로가 필요하므로 cygpath 유무로 판단한다)
  if command -v cygpath >/dev/null 2>&1; then f="$(cygpath -w "$f")"; js="$(cygpath -w "$js")"; fi
  PACKS_LINES="$(MSYS2_ARG_CONV_EXCL='*' "$node" "$js" "$f" 2>/dev/null)" || return 1
  [ -n "$PACKS_LINES" ]
}

# 외부 명령 하나를 실행한다.
_packs_exec() {
  # 표준입력은 끊는다: 설치 명령이 팩 목록(루프의 입력)을 읽어 버리면 남은 팩이 말없이 건너뛰어진다(실제 Windows 에서 확인).
  if [ -n "${COWORK_LITE_PACK_EXEC:-}" ]; then bash "$COWORK_LITE_PACK_EXEC" "$@" </dev/null; else "$@" </dev/null; fi
}

# _packs_run_step <type> <인자…> : 설치 단계 하나를 실행한다.
_packs_run_step() {
  local type="$1" url prov rc; shift
  case "$type" in
    run|run-optional) [ "$#" -gt 0 ] && _packs_exec "$@" ;;
    remote-script)
      # 설치 스크립트를 받아서 곧바로 실행하는 방식이다(외부 출처). 주소는 https만 허용한다.
      if cl_is_windows; then url="$1"; else url="$2"; fi
      case "$url" in https://*) ;; *) return 1 ;; esac
      # 이미 설치돼 있으면(이어서 실행) 다시 받지 않는다. 먼저 PATH 를 새로 읽는다.
      prov="${3:--}"
      if [ "$prov" != - ]; then
        type prereq_refresh_path >/dev/null 2>&1 && prereq_refresh_path
        if command -v "$prov" >/dev/null 2>&1; then cl_say "  $prov 는 이미 설치돼 있어 건너뜁니다."; return 0; fi
      fi
      if cl_is_windows; then
        _packs_exec powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm '$url' | iex"; rc=$?
      else
        _packs_exec bash -c "curl -fsSL '$url' | sh"; rc=$?
      fi
      # 설치 스크립트가 PATH 를 바꿔도 이 셸에는 반영되지 않는다. 다음 단계가 방금 설치한 명령을 찾도록 다시 읽는다.
      type prereq_refresh_path >/dev/null 2>&1 && prereq_refresh_path
      return $rc ;;
    *) return 1 ;;
  esac
}

# packs_summary : 설치 전에 사용자에게 보여 줄 팩 이름을 한 줄씩 출력한다.
packs_summary() {
  local kind id title rest
  _packs_load || return 0
  while IFS=$'\t' read -r kind id title rest; do
    if [ "$kind" = P ]; then printf '%s\n' "$title"; fi
  done <<< "$PACKS_LINES"
  return 0
}

# packs_install_all : 기본팩을 차례로 설치한다. 실패하면 어느 팩의 몇 번째 단계인지 알리고 1.
packs_install_all() {
  local id="" title="" skip=0 step=0 line
  local -a f
  _packs_load || { cl_warn "설치할 팩 목록(packs.json)을 읽지 못했습니다."; return 1; }
  while IFS= read -r line; do
    IFS=$'\t' read -r -a f <<< "$line"
    case "${f[0]}" in
      P)
        # 앞 팩이 끝났으면 완료 표식을 남긴다(건너뛴 팩은 이미 표식이 있다).
        [ -n "$id" ] && [ "$skip" = 0 ] && { _setup_mark "pack-$id"; cl_say "✔ $title 설치했습니다."; }
        id="${f[1]}"; title="${f[2]}"; step=0; skip=0
        if _setup_done "pack-$id"; then skip=1; cl_say "✔ $title 은(는) 이미 설치돼 건너뜁니다."; else cl_say "… $title 설치 중입니다."; fi ;;
      S)
        [ "$skip" = 1 ] && continue
        step=$((step+1))
        if ! _packs_run_step "${f[@]:1}"; then
          if [ "${f[1]}" = run-optional ]; then
            cl_warn "⚠ '$title' 의 선택 단계(${f[*]:2})를 건너뜁니다. 필요한 프로그램(예: Python 3.10~3.14)이 없을 수 있습니다. Python을 설치한 뒤 이 명령을 직접 실행하면 됩니다. (Windows: winget install Python.Python.3.12)"
            continue
          fi
          cl_warn "✘ '$title' 설치에 실패했습니다. 인터넷 연결이나 회사 보안 때문일 수 있습니다. (단계 $step)"
          return 1
        fi ;;
    esac
  done <<< "$PACKS_LINES"
  [ -n "$id" ] && [ "$skip" = 0 ] && { _setup_mark "pack-$id"; cl_say "✔ $title 설치했습니다."; }
  _packs_write_markers
}

# 기억(ai-memory) 팩은 허용 목록 모드라 .ai-memory.toml 이 있는 폴더만 기록한다. 작업 폴더 루트에 마커를 둔다(이미 있으면 건드리지 않는다).
# 형식은 docs/marker-file.md: workspace·project 두 키. 비밀이 담길 수 있는 받은자료는 기록에서 뺀다.
_packs_write_markers() {
  local root f; _setup_done pack-memory || return 0
  root="$(cl_space_root)"; f="$root/.ai-memory.toml"
  [ -f "$f" ] && return 0
  [ -d "$root" ] || return 0
  printf '%s\n' '# cowork-lite 가 만든 ai-memory 마커. 이 폴더 아래 작업만 기억에 기록된다.' \
    'workspace = "cowork"' 'project = "cowork-space"' '' '[capture]' 'ignore_paths = ["받은자료/**"]' > "$f"
}
