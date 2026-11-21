#!/usr/bin/env python3
"""Search for inputs where a weakened bound of the short quotient returns a wrongly rounded value.

`bin_coeff_div_short_quotient` (library/src/internal/bin_kernel/coeff_knuth_words_nonjs.mbt) returns an
approximation `Q` of `floor(N / D)` unless `Q mod 2^m` is within `lower = 2 n` of a grid point from above
or within `upper = floor(top two limbs of the final window / top limb of D) + 2` from below. This is a
Python port of the quotient loop and of that test (written from the source), with the two bounds as
parameters: `upper_add` (the kernel has 2) and `lower_mult` (the kernel has 2, `lower = lower_mult n`).
It reports the inputs for which the returned value rounds differently from the exact quotient.

Result (divisors of 2 to 4 limbs, quotients within a few units of a multiple of 2^m, m = 32 to 40, 2.4 million
cases): with the kernel's bounds no input is wrong; with `lower = 0` about 0.3 percent of the cases are
wrong (the witnesses are rows of the `div` table of kernel_oracle.py); with `upper_add = 0` no input is wrong,
which the argument in the header of coeff_div_oracle_wbtest.mbt explains (the `+ 2` is a margin).

    python3 tools/short_quotient_bound_search.py SEED COUNT
"""
import random, sys
B = 1 << 64
M = B - 1

def limbs(x, n):
    return [(x >> (64 * i)) & M for i in range(n)]

def short_div(N, D, precision, upper_add=2, lower_mult=2):
    dl = (D.bit_length() + 63) // 64
    shift = 64 * dl - D.bit_length()
    v = D << shift
    w = N << shift
    nl = (N.bit_length() + 63) // 64
    ql = nl - dl + 1
    top = v >> (64 * (dl - 1))
    dnext = (v >> (64 * (dl - 2))) & M
    two = v >> (64 * (dl - 2))
    q = 0
    for off in range(ql - 1, -1, -1):
        window = w >> (64 * off)
        high = window >> (64 * dl)
        if high < top:
            trial = (window >> (64 * (dl - 2))) // two
        else:
            nxt = (window >> (64 * (dl - 1))) & M
            aft = (window >> (64 * (dl - 2))) & M
            trial = M
            rem = nxt + top
            while rem < B and trial * dnext > (rem << 64) + aft:
                trial -= 1
                rem += top
        skip = max(0, dl - 1 - off)
        piece = v >> (64 * skip)  # divisor limbs from skip
        sub = (trial * piece) << (64 * (off + skip))
        if sub > w:  # borrow out of the limb above the row: add back once
            trial -= 1
            sub -= piece << (64 * (off + skip))
            if sub > w:
                return "bad", None
        w -= sub
        q |= trial << (64 * off)
    wh = (w >> (64 * dl)) & M
    if wh >= top:
        return "decline", None
    wn = (w >> (64 * (dl - 1))) & M
    upper = (wh * B + wn) // top + upper_add
    lower = lower_mult * dl
    bits = q.bit_length()
    if bits == 0:
        return "decline", None
    m = bits - precision - 1
    if m < 32:
        return "decline", None
    r = q & ((1 << m) - 1)
    if not (r > lower and ((1 << m) - 1 - r) >= upper):
        return "decline", None
    return "ok", q

def rounds(q, sticky, precision):
    s = q.bit_length() - precision
    kept = q >> s
    low = q - (kept << s)
    half = 1 << (s - 1)
    near = kept + 1 if (low > half or (low == half and (sticky or kept & 1))) else kept
    up = kept + 1 if (low or sticky) else kept
    return (near, kept, up), s

def kernel_rounds(q, precision):
    s = q.bit_length() - precision
    kept = q >> s
    near = kept + 1 if (q >> (s - 1)) & 1 else kept
    return (near, kept, kept + 1), s

def main(seed, count):
    rnd = random.Random(seed)
    stats = {}
    for it in range(count):
        dl = rnd.choice([2, 3, 4])
        kind = rnd.choice(["rand", "ones", "min", "minmid", "onesmid"])
        if kind == "rand": D = rnd.getrandbits(64 * dl) | (1 << (64 * dl - 1))
        elif kind == "ones": D = (1 << (64 * dl)) - 1 - rnd.choice([0, 0, 1, rnd.getrandbits(8)])
        elif kind == "min": D = (1 << (64 * dl - 1)) + rnd.choice([0, 1, rnd.getrandbits(8)])
        elif kind == "minmid": D = (1 << (64 * dl - 1)) | rnd.getrandbits(64 * (dl - 1))
        else: D = (M << (64 * (dl - 1))) | rnd.getrandbits(64 * (dl - 1))
        if rnd.random() < 0.3:
            D >>= rnd.choice([1, 7, 31, 63])
            if D.bit_length() <= 64 * (dl - 1): continue
        qbits_extra = rnd.choice([0, 1, 2, 3])
        m = rnd.choice([32, 33, 34, 40])
        precision = 64 * dl + rnd.choice([-63, -1, 0, 1, 5])
        if precision < 4: continue
        total = precision + m + 1 + (64 * qbits_extra) % 7
        # a quotient next to a grid point (multiple of 2^m) in [2^(total-1), 2^total)
        g = (rnd.getrandbits(total - m - 1) | (1 << (total - m - 1))) << m
        t = rnd.choice([-1, 0, 1, 2, 3, -2, -3, rnd.randint(-8 * dl, 8 * dl), rnd.randint(-40, 40)])
        E = g + t
        if E.bit_length() != total or E <= 0: continue
        r = rnd.choice([0, 1, D - 1, rnd.randrange(D)])
        N = D * E + r
        if N.bit_length() < D.bit_length(): continue
        exact, sticky = divmod(N, D)[0], (N % D != 0)
        for name, (ua, lm) in {"base": (2, 2), "M14": (0, 2), "M15": (2, 0), "M14+M15": (0, 0)}.items():
            status, q = short_div(N, D, precision, ua, lm)
            key = (name, status)
            stats[key] = stats.get(key, 0) + 1
            if status == "ok":
                er, es = rounds(exact, sticky, precision)
                kr, ks = kernel_rounds(q, precision)
                if (er, es) != (kr, ks):
                    stats[(name, "WRONG")] = stats.get((name, "WRONG"), 0) + 1
                    if stats[(name, "WRONG")] <= 3:
                        print("WITNESS", name, "D=%x" % D, "N=%x" % N, "precision", precision, "dl", dl, "t", t, flush=True)
    print(sorted(stats.items()))

if __name__ == "__main__":
    main(int(sys.argv[1]), int(sys.argv[2]))
