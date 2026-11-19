#!/usr/bin/env python3
"""전압강하 계산: 전압강하(V) = 계수 x 길이(m) x 전류(A) / (1000 x 단면적(mm2)).

계수는 코드에 넣지 않는다. 사용자가 공식 원문에서 확인해 data/voltage-drop-formulas.json 에 넣은 값만 쓴다.
출처·기준일이 없는 항목은 쓰지 않는다.
"""
import argparse
import json
import os
import sys
from decimal import Decimal, InvalidOperation

DEFAULT_DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "voltage-drop-formulas.json")


# Windows 콘솔 기본 코드 페이지(cp949)에서 한글이 깨지지 않게 출력을 UTF-8 로 고정한다.
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass


def fail(msg, code=2):
    print(msg, file=sys.stderr)
    sys.exit(code)


def load_formula(path, system):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        fail("기준 데이터가 아직 없습니다. Claude 에 '온보딩'이라고 보내시면 질문으로 채워 드립니다. (찾은 위치: %s)" % path)
    except (OSError, ValueError) as e:
        fail("계산식 데이터를 읽지 못했습니다: %s" % e)
    rows = data.get("formulas") or []
    if not rows:
        fail("기준 데이터가 아직 없습니다. Claude 에 '온보딩'이라고 보내시면 KEC 원문에서 확인한 계수를 질문으로 채워 드립니다.")
    for r in rows:
        if r.get("system") == system:
            if not r.get("출처") or not r.get("기준일"):
                fail("'%s' 항목에 출처 또는 기준일이 없어 쓰지 않습니다." % system)
            try:
                return Decimal(str(r["coefficient"])), r
            except (KeyError, InvalidOperation):
                fail("'%s' 항목의 계수가 올바르지 않습니다." % system)
    fail("'%s' 계산식이 데이터에 없습니다." % system)


def main(argv=None):
    p = argparse.ArgumentParser(description="전압강하 계산")
    p.add_argument("--system", required=True, help="계산식 이름(데이터의 system 값)")
    p.add_argument("--length-m", required=True)
    p.add_argument("--current-a", required=True)
    p.add_argument("--area-mm2", required=True)
    p.add_argument("--voltage", required=True, help="공칭 전압(V). 비율 계산용")
    p.add_argument("--data", default=DEFAULT_DATA)
    a = p.parse_args(argv)
    try:
        length, cur, area, volt = (Decimal(x) for x in (a.length_m, a.current_a, a.area_mm2, a.voltage))
    except InvalidOperation:
        fail("숫자가 올바르지 않습니다.")
    if min(length, cur, area, volt) <= 0:
        fail("길이·전류·단면적·전압은 0보다 커야 합니다.")
    coef, row = load_formula(a.data, a.system)
    drop = coef * length * cur / (1000 * area)
    pct = drop / volt * 100
    print("전압강하: %s V" % drop.quantize(Decimal("0.01")))
    print("전압강하율: %s %%" % pct.quantize(Decimal("0.01")))
    print("근거: %s (기준일 %s)" % (row["출처"], row["기준일"]))
    print("참고용 초안입니다. 담당 기술자가 KEC 원문을 확인해 최종 판단하세요.")


if __name__ == "__main__":
    main()
