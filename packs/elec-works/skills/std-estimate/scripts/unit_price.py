#!/usr/bin/env python3
"""일위대가(노무비) 계산: 합계 = sum(수량 x 직종별 일당) x (1 + 할증율/100).

수량·일당·할증율은 코드에 넣지 않는다. 사용자가 공식 자료에서 확인해 data/ 의 CSV 에 넣은 값만 쓴다.
출처·기준일이 없는 행은 쓰지 않는다. 반올림은 하지 않는다(규칙을 임의로 정하지 않기 위해).
"""
import argparse
import csv
import os
import sys
from decimal import Decimal, InvalidOperation

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")


# Windows 콘솔 기본 코드 페이지(cp949)에서 한글이 깨지지 않게 출력을 UTF-8 로 고정한다.
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass


def fail(msg, code=2):
    print(msg, file=sys.stderr)
    sys.exit(code)


def read_rows(path):
    try:
        with open(path, encoding="utf-8-sig", newline="") as f:
            return list(csv.DictReader(f))
    except OSError as e:
        fail("파일을 읽지 못했습니다: %s" % e)


def need_source(row, what):
    if not (row.get("출처") or "").strip() or not (row.get("기준일") or "").strip():
        fail("%s 행에 출처 또는 기준일이 없어 쓰지 않습니다: %s" % (what, row))


def dec(value, what):
    try:
        return Decimal(str(value).strip())
    except InvalidOperation:
        fail("%s 값이 숫자가 아닙니다: %s" % (what, value))


def main(argv=None):
    p = argparse.ArgumentParser(description="일위대가 계산")
    p.add_argument("--work", required=True, help="공종(labor-norms.csv 의 공종 열과 같아야 함)")
    p.add_argument("--quantity", required=True, help="물량")
    p.add_argument("--surcharge", help="적용할 할증 조건(surcharge-rules.csv 의 조건 열과 같아야 함, 하나만)")
    p.add_argument("--data", default=DATA)
    a = p.parse_args(argv)
    qty = dec(a.quantity, "물량")
    if qty <= 0:
        fail("물량은 0보다 커야 합니다.")
    norms = [r for r in read_rows(os.path.join(a.data, "labor-norms.csv")) if r.get("공종") == a.work]
    if not norms:
        fail("'%s' 공종의 품셈 데이터가 없습니다. data/labor-norms.csv 를 채워 주세요." % a.work)
    wages = {r.get("직종"): r for r in read_rows(os.path.join(a.data, "unit-wages.csv"))}
    total = Decimal(0)
    lines = []
    for n in norms:
        need_source(n, "품셈")
        w = wages.get(n.get("직종"))
        if w is None:
            fail("'%s' 직종의 노임 단가가 없습니다. data/unit-wages.csv 를 채워 주세요." % n.get("직종"))
        need_source(w, "노임")
        amount = dec(n["수량"], "수량") * dec(w["일당"], "일당") * qty
        total += amount
        lines.append("%s: 수량 %s x 일당 %s x 물량 %s = %s  [품셈 %s %s / 노임 %s %s]" % (
            n["직종"], n["수량"], w["일당"], qty, amount, n["출처"], n["기준일"], w["출처"], w["기준일"]))
    if a.surcharge:
        rules = [r for r in read_rows(os.path.join(a.data, "surcharge-rules.csv")) if r.get("조건") == a.surcharge]
        if not rules:
            fail("'%s' 할증 조건이 데이터에 없습니다." % a.surcharge)
        if len(rules) > 1:
            fail("'%s' 할증 조건이 여러 행입니다. 하나로 정리해 주세요." % a.surcharge)
        need_source(rules[0], "할증")
        rate = dec(rules[0]["할증율_퍼센트"], "할증율")
        total = total * (1 + rate / 100)
        lines.append("할증 %s%% 적용(%s) [%s %s]" % (rate, a.surcharge, rules[0]["출처"], rules[0]["기준일"]))
    for ln in lines:
        print(ln)
    print("노무비 합계: %s" % total)
    print("참고용 초안입니다. 담당자가 최신 품셈과 단가를 확인해 최종 판단하세요.")


if __name__ == "__main__":
    main()
