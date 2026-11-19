#!/bin/bash
# 기록 점검(쓰기 시점, 안내용): 업무일지에 비밀값이나 고객 개인정보가 들어가지 않게 한다. 업무일지는 GitHub 비공개 저장소로 올라간다.
#  - 비밀값 모양(토큰·키·"비밀번호는 …")인 줄은 **쓰지 않는다**.
#  - 개인정보 모양(휴대전화·일반전화·이메일·주민등록번호·카드번호)인 줄은 **쓰되** 경고한다(일반화해서 다시 쓰도록 안내).
# 경고에는 걸린 값이 아니라 종류와 줄 번호만 보인다. 모든 패턴은 모양만 보는 것이라 놓치거나 잘못 잡을 수 있다(보증이 아니라 안내).
# bash 3.2 호환. 외부 프로그램은 grep -E 만 쓴다.

# record_scan <텍스트> : 걸린 항목을 `S<TAB>줄번호<TAB>종류`(비밀값) · `P<TAB>줄번호<TAB>종류`(개인정보)로 한 줄씩 출력한다.
record_scan() {
  local text="$1" kind pat n
  while IFS='|' read -r kind pat; do
    [ -n "$kind" ] || continue
    printf '%s\n' "$text" | grep -n -i -E -e "${pat#*|}" 2>/dev/null | cut -d: -f1 | while IFS= read -r n; do
      printf '%s\t%s\t%s\n' "${kind%%:*}" "$n" "${kind#*:}"
    done
  done <<'PATTERNS'
S:토큰·키 형식|x|sk-[A-Za-z0-9_-]{20,}
S:토큰·키 형식|x|gh[pousr]_[A-Za-z0-9]{20,}
S:토큰·키 형식|x|github_pat_[A-Za-z0-9_]{20,}
S:토큰·키 형식|x|AKIA[0-9A-Z]{16}
S:개인 키|x|-----BEGIN [A-Z ]*KEY-----
S:비밀번호·토큰 값|x|(비밀번호|패스워드|암호|password|passwd|pwd|token|토큰|api[ _-]?key|secret)[[:space:]]*(은|는|이|:|=)[[:space:]]*[^[:space:]]{4,}
P:휴대전화 번호|x|01[016789][- .]?[0-9]{3,4}[- .]?[0-9]{4}
P:전화번호|x|0(2|[3-6][0-9])[- .][0-9]{3,4}[- .][0-9]{4}
P:이메일 주소|x|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}
P:주민등록번호 꼴|x|[0-9]{6}-[1-4][0-9]{6}
P:카드번호 꼴|x|[0-9]{4}[- ][0-9]{4}[- ][0-9]{4}[- ][0-9]{4}
PATTERNS
}

# record_drop_lines <텍스트> <줄번호,줄번호,...> : 해당 줄을 뺀 텍스트를 출력한다.
record_drop_lines() {
  printf '%s\n' "$1" | awk -v drop=",$2," 'index(drop, "," NR ",") == 0'
}

# record_summary <S|P> <scan 결과> : "토큰·키 형식 1줄(3번), 이메일 주소 2줄(5, 7번)" 처럼 종류와 줄 번호만 요약한다.
record_summary() {
  local want="$1" scan="$2" kinds kind lines count
  kinds="$(printf '%s\n' "$scan" | awk -F'\t' -v w="$want" '$1 == w { print $3 }' | sort -u)"
  while IFS= read -r kind; do
    [ -n "$kind" ] || continue
    lines="$(printf '%s\n' "$scan" | awk -F'\t' -v w="$want" -v k="$kind" '$1 == w && $3 == k { print $2 }' | sort -n -u | paste -sd, - | sed 's/,/, /g')"
    count="$(printf '%s\n' "$lines" | tr ',' '\n' | grep -c .)"
    printf '%s %s줄(%s번)\n' "$kind" "$count" "$lines"
  done <<< "$kinds" | paste -sd';' - | sed 's/;/, /g'
}
