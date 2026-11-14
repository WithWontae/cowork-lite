#!/bin/bash
# cowork-lite 한 줄 설치기: 파일을 $COWORK_LITE_HOME(기본 ~/.cowork-lite)에 배치하고 setup을 이어서 실행한다.
#   curl -fsSL <주소>/install.sh | bash
# 환경변수(테스트·개발용): COWORK_LITE_SRC=<로컬 소스 폴더>, COWORK_LITE_TARBALL_URL=<tarball 주소>
# 옵션: --no-setup  파일만 배치하고 끝낸다.
set -u
NO_SETUP=0
[ "${1:-}" = "--no-setup" ] && NO_SETUP=1

home="${COWORK_LITE_HOME:-$HOME/.cowork-lite}"
tarball="${COWORK_LITE_TARBALL_URL:-https://github.com/WithWontae/cowork-lite/archive/refs/heads/main.tar.gz}"
src="${COWORK_LITE_SRC:-}"
tmp=""
cleanup() { [ -n "$tmp" ] && rm -rf "$tmp"; }
trap cleanup EXIT

if [ -z "$src" ]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/cowork-lite-src.XXXXXX")" || { echo "임시 폴더를 만들 수 없습니다."; exit 1; }
  echo "cowork-lite를 내려받는 중입니다…"
  if ! curl -fsSL "$tarball" | tar -xz -C "$tmp" --strip-components=1; then
    echo "내려받지 못했습니다. 인터넷 연결이나 회사 보안 때문일 수 있습니다. 잠시 뒤에 다시 시도해 주세요."
    exit 1
  fi
  src="$tmp"
fi

for item in bin lib hooks packs.json VERSION; do
  [ -e "$src/$item" ] || { echo "설치 파일이 빠져 있습니다($item). 잠시 뒤에 다시 시도해 주세요."; exit 1; }
done

mkdir -p "$home" || { echo "설치 폴더를 만들 수 없습니다: $home"; exit 1; }
for item in bin lib hooks packs.json VERSION; do
  rm -rf "${home:?}/$item"
  cp -R "$src/$item" "$home/$item" || { echo "파일을 복사하지 못했습니다: $item"; exit 1; }
done
chmod +x "$home"/bin/* "$home"/hooks/*.sh

# Windows용 래퍼(cowork-lite.cmd)는 줄 끝이 CRLF여야 cmd가 제대로 읽는다. 저장소에는 LF로 저장되어 있어
# GitHub tarball로 받으면 LF만 있는 채로 들어온다(그러면 'rk-lite.'은(는) 인식되지 않습니다 같은 오류로 깨진다).
# 설치 때마다 복사하므로 여기서 매번 맞춘다. awk만 써서 macOS의 BSD sed 차이를 피한다.
# CR 유무는 grep이 아니라 tr로 센다(Windows Git Bash의 grep은 텍스트 모드라 줄 끝의 CR을 지우고 읽는다).
if [ -f "$home/bin/cowork-lite.cmd" ] && [ "$(tr -cd '\r' < "$home/bin/cowork-lite.cmd" | wc -c)" -eq 0 ]; then
  awk '{ printf "%s\r\n", $0 }' "$home/bin/cowork-lite.cmd" > "$home/bin/cowork-lite.cmd.tmp" \
    && mv "$home/bin/cowork-lite.cmd.tmp" "$home/bin/cowork-lite.cmd"
fi

if [ "$NO_SETUP" = 1 ]; then
  echo "파일을 복사했습니다: $home"
  exit 0
fi

export COWORK_LITE_HOME="$home"
"$home/bin/cowork-lite" setup
exit $?
