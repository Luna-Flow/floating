#!/usr/bin/env python3
"""Rows for library/src/bin_float/decimal_format_range_issue677_wbtest.mbt.

Expected digit strings of c * 2^e rounded once to d significant digits
(nearest, ties to even) from CPython decimal: the power of two is computed with
d + 60 digits, rows within 10^-29 relative of a tie are refused. Prints the
MoonBit array rows on standard output.
"""
import decimal
from decimal import Decimal, localcontext
EMIN=-(2**30)+2   # binary_implementation_e_min
EMAX=2**30-1
cases=[]
for c in (1,3,(1<<53)-1):
    bits=c.bit_length()
    es=[EMIN,EMIN+1,EMIN+100,EMIN+122,-1073741700,-2000,-1,0,5,1000]
    hi=EMAX-bits+1
    es+= [hi,hi-1,hi-122,hi-1000]
    for e in es:
        for d in (1,7,34,100):
            cases.append((c,e,d))
def fmt(c,e,d):
    with localcontext() as ctx:
        ctx.prec=d+60; ctx.Emax=decimal.MAX_EMAX; ctx.Emin=decimal.MIN_EMIN
        v=Decimal(c)*(Decimal(2)**e)
        ctx.prec=d+60
        t=v.as_tuple(); digs=''.join(map(str,t.digits))
        # tie-risk check on the digits past d
        tail=digs[d:d+30]
        assert not (tail.startswith('5'+'0'*29) or tail.startswith('4'+'9'*29)), (c,e,d)
        ctx.prec=d
        r=+v
        t=r.as_tuple(); digs=''.join(map(str,t.digits)).ljust(d,'0')
        ex=t.exponent+len(t.digits)-1
        s=digs[0]+('.'+digs[1:] if d>1 else '')
        return f"{s}e{'+' if ex>=0 else '-'}{abs(ex)}"
out=[]
for c,e,d in cases:
    out.append(f'  ({c}UL, {e}, {d}, "{fmt(c,e,d)}"),')
print("\n".join(out))
