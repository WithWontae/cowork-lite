#!/bin/bash
# doctor: 설치 상태를 쉬운 말로 점검한다. 모두 통과하면 0, 아니면 1.
# 의존: common, manifest, settings, space, guard, prereq (호출하는 쪽이 source 한다).

_doc_ok()  { cl_say "✔ $1"; }
_doc_bad() { cl_say "✘ $1"; cl_say "   → 다음에 할 일: $2"; DOCTOR_FAILS=$((DOCTOR_FAILS+1)); }

doctor_run() {
  local home root f d kind path probe res
  DOCTOR_FAILS=0
  home="$(cl_home)"; root="$(cl_space_root)"
  prereq_refresh_path

  if prereq_check claude; then _doc_ok "Claude Code가 설치되어 있습니다"
  else _doc_bad "Claude Code가 없습니다" "cowork-lite setup 을 다시 실행해 주세요"; fi

  if prereq_check node; then _doc_ok "Node.js가 설치되어 있습니다"
  else _doc_bad "Node.js가 없거나 버전이 낮습니다" "cowork-lite setup 을 다시 실행해 주세요"; fi

  if cl_json_valid "$home/local.json"; then _doc_ok "설정 파일(local.json)이 정상입니다"
  else _doc_bad "설정 파일(local.json)이 없거나 손상되었습니다" "cowork-lite setup 을 다시 실행해 주세요"; fi

  if settings_has_hooks; then _doc_ok "Claude에 cowork-lite hook 2종이 등록되어 있습니다"
  else _doc_bad "Claude에 cowork-lite hook이 등록되어 있지 않습니다" "cowork-lite setup 을 다시 실행해 주세요"; fi

  for f in guard.sh session.sh; do
    if [ -x "$home/hooks/$f" ]; then _doc_ok "hook 파일($f)을 실행할 수 있습니다"
    else _doc_bad "hook 파일($f)이 없거나 실행 권한이 없습니다" "cowork-lite setup 을 다시 실행해 주세요"; fi
  done

  for d in 받은자료 작업중 결과물 업무일지 .cowork; do
    if [ -d "$root/$d" ]; then _doc_ok "작업 폴더에 '$d' 폴더가 있습니다"
    else _doc_bad "작업 폴더에 '$d' 폴더가 없습니다" "cowork-lite setup 을 다시 실행하면 다시 만들어 줍니다"; fi
  done

  while IFS=$'\t' read -r kind path; do
    [ -n "$path" ] || continue
    if [ ! -e "$path" ]; then
      _doc_bad "설치 기록에 있는 항목이 없습니다: $(basename "$path")" "cowork-lite setup 을 다시 실행해 주세요"
    fi
  done <<< "$(manifest_list)"

  probe="$root/받은자료/.doctor-probe"
  res="$(guard_decide_file Edit "$probe")"
  if [ "${res%%$'\t'*}" = deny ]; then _doc_ok "Guard가 받은자료 수정을 막고 있습니다"
  else _doc_bad "Guard가 받은자료를 지키지 못하고 있습니다" "cowork-lite setup 을 다시 실행하거나 도움을 요청해 주세요"; fi

  if [ "$DOCTOR_FAILS" -eq 0 ]; then
    cl_say "모두 초록불 ✔"; return 0
  fi
  cl_say "고쳐야 할 항목이 ${DOCTOR_FAILS}개 있습니다"; return 1
}
