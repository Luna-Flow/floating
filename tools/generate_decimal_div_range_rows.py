#!/usr/bin/env python3
"""Rows for `library/src/decimal/div_range_issue676_wbtest.mbt`.

The issue 676 table, then a seeded sweep of the plain operators `/`, `+`, `-`, `*`
over operand exponents at the bottom and the top of the stored range of `decimal`
(Etiny -2147483645, largest adjusted exponent 2147483646), the expected value of
every row computed by CPython `decimal` (libmpdec) in the plain working context
(precision 34, half-even, no clamp). Run: `python3 tools/generate_decimal_div_range_rows.py`
(standard output is the row table).
"""
import decimal, random, sys
from decimal import Decimal, Context, ROUND_HALF_EVEN
random.seed(676)
ETINY=-2147483645; EMAX=2147483646
ctx=Context(prec=34,rounding=ROUND_HALF_EVEN,Emax=EMAX,Emin=ETINY+33,clamp=0,traps=[])
ctx.flags  # noqa
fixed=[("123456789012345678E-2","25E+2147483645"),("123456789012345678E-2","250E+2147483644"),
("123456789012345678E-2147483645","25E+2"),("123456789012345678E-2147483645","250E+1"),
("123456789012345678E-2147483645","250E+2"),("123456789012345678E-1073741824","25E+1073741824"),
("123456789012345678E-1073741824","250E+1073741824"),("1E-1","12E+2147483644")]
exps=list(range(-2147483648,-2147483630))+list(range(2147483630,2147483648))+[-1073741824,1073741824,-2,0,2,-1073741823,1073741823,-2147483645,2147483645,-1000000000,1000000000]
def coef():
    n=random.choice([1,1,2,3,5,9,10,18,19,30,33,34])
    return random.randint(10**(n-1),10**n-1) if n>1 else random.randint(1,9)
def s(c,e,neg):
    e=max(e,ETINY); e=min(e,EMAX-(len(str(c))-1))
    return ("-" if neg else "")+f"{c}E{e}"
rows=[]
for a,b in fixed: rows.append(("/",a,b))
for op in "/+-*":
    k=0
    while k<500:
        a=s(coef(),random.choice(exps),random.random()<.2); b=s(coef(),random.choice(exps),random.random()<.2)
        rows.append((op,a,b)); k+=1
f={"/":ctx.divide,"+":ctx.add,"-":ctx.subtract,"*":ctx.multiply}
out=[]
for op,a,b in rows:
    r=f[op](Decimal(a),Decimal(b))
    out.append((op,a,b,str(r)))
print("///|\nlet sweep_676_rows : Array[(String, String, String, String)] = [")
for r in out: print("  (%s),"%", ".join('"%s"'%x for x in r))
print("]")
