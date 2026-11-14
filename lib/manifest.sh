#!/bin/bash
# 설치 항목 기록(제거용). 한 줄 = `종류<TAB>경로`. bash 3.2 호환.

_manifest_file() { printf '%s\n' "$(cl_home)/manifest.tsv"; }

# manifest_add <종류> <경로>
manifest_add() {
  mkdir -p "$(cl_home)" || return 1
  printf '%s\t%s\n' "$1" "$2" >> "$(_manifest_file)"
}

manifest_list() {
  [ -f "$(_manifest_file)" ] && cat "$(_manifest_file)"
  return 0
}

# manifest_remove_all_of <종류>
manifest_remove_all_of() {
  local f tmp; f="$(_manifest_file)"
  [ -f "$f" ] || return 0
  tmp="$(mktemp "$f.XXXXXX")" || return 1
  awk -F'\t' -v k="$1" '$1 != k' "$f" > "$tmp" && mv "$tmp" "$f"
}
