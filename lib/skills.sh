#!/bin/bash
# 우리가 직접 만든 스킬(온보딩, 전기 공무 3종)을 Claude 스킬 폴더(~/.claude/skills)에 복사한다.
# 원본은 설치 폴더의 packs/ 아래에 있다(packs/onboarding, packs/elec-works/skills/*).
# 복사한 폴더에는 표식 파일(.cowork-lite)을 남겨, 사용자가 같은 이름으로 직접 만든 스킬은 덮어쓰지 않는다.
# 복사한 폴더는 manifest 에 `skill<TAB>경로` 로 기록해 제거 때 지운다. 의존: common, manifest, settings. bash 3.2 호환.

skills_dir() { printf '%s\n' "$(dirname "$(settings_path)")/skills"; }

# skills_list : `이름<TAB>원본 폴더` 를 한 줄씩 출력한다.
skills_list() {
  local home d; home="$(cl_home)"
  [ -f "$home/packs/onboarding/SKILL.md" ] && printf 'onboarding\t%s\n' "$home/packs/onboarding"
  for d in "$home"/packs/elec-works/skills/*/; do
    [ -f "${d}SKILL.md" ] || continue
    d="${d%/}"; printf '%s\t%s\n' "$(basename "$d")" "$d"
  done
  return 0
}

skills_install_all() {
  local name src dest base n=0 skipped=0; base="$(skills_dir)"
  while IFS=$'\t' read -r name src; do
    [ -n "$name" ] || continue
    dest="$base/$name"
    if [ -e "$dest" ] && [ ! -f "$dest/.cowork-lite" ]; then
      cl_warn "⚠ 같은 이름의 스킬이 이미 있어 덮어쓰지 않았습니다: $dest"
      skipped=$((skipped + 1)); continue
    fi
    rm -rf "${dest:?}"
    mkdir -p "$dest" && cp -R "$src"/. "$dest"/ || { cl_warn "✘ 스킬을 복사하지 못했습니다: $name"; return 1; }
    : > "$dest/.cowork-lite"
    manifest_list | grep -Fqx "skill	$dest" || manifest_add skill "$dest"
    n=$((n + 1))
  done <<< "$(skills_list)"
  [ "$n" -gt 0 ] || [ "$skipped" -gt 0 ] || { cl_warn "✘ 복사할 스킬을 찾지 못했습니다(설치 파일이 빠져 있을 수 있습니다)."; return 1; }
  cl_say "✔ 직접 만든 스킬 ${n}개를 설치했습니다(온보딩, 전기 공무)."
}

# 기록된 스킬 폴더 중 표식이 있는 것만 지운다.
skills_remove_all() {
  local kind path
  while IFS=$'\t' read -r kind path; do
    [ "$kind" = skill ] && [ -n "$path" ] || continue
    if [ -f "$path/.cowork-lite" ]; then rm -rf "${path:?}"; fi
  done <<< "$(manifest_list)"
  manifest_remove_all_of skill
}
