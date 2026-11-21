"""The one definition of a legal context, for the generators, the runners and the tests of the corpus.

Pure functions and three frozen dataclasses, no I/O.  A context is legal when
the standard of its package can have it:

* `bin_float` (IEEE 754-2019 3.3, 3.7, 4.3, 7.5): a precision `p` and an exponent
  `e_max >= 1` with `e_min = 1 - e_max`, or a precision alone (the extendable
  format, whose range is the implementation range); one of the five rounding
  directions; tininess before or after rounding.
* `decimal` (IEEE 754-2019): a precision and `e_max >= 1` with `e_min = 1 - e_max`,
  every finite result a member of the format (`clamp` on), tininess before
  rounding (7.5), one of the five rounding-direction attributes of 4.3.
* `decimal_gda` (General Decimal Arithmetic 1.70, page 10): `e_min` is `-e_max`,
  `1 - e_max` or `-e_max - 1`, `0 <= e_max`, `e_min <= 0`; precision at least 1; any of the
  eight rounding modes; `clamp` free.

The limits are those of the library (`binary_precision_max`,
`binary_implementation_e_max`, `decimal_precision_max`, `decimal_implementation_e_max`).
`testdata/context_vectors.txt` lists boundary contexts with their verdict; this
module and the library constructors are both tested against it
(`tools/context_rules_test.py`, `tooling/src/consistency/context_vectors_wbtest.mbt`), so a
change of a limit or of a rule in one place fails a test until the other agrees.
"""

from __future__ import annotations

from dataclasses import dataclass

# ---------------------------------------------------------------------------
# Limits and vocabularies
# ---------------------------------------------------------------------------

# The limits below are the library's own limits, written here on purpose: the
# rules keep their own copy of the numbers so that they stay independent of the
# library, and `tooling/src/consistency/oracle_constants_wbtest.mbt` and
# `tools/oracle_constants_test.py` fail when a limit changes on one side only.
# Where each comes from:
# - binary: the range of IEEE 754-2019 3.3 (`emin = 1 - emax`, `emax >= 1`) and
#   3.7 (extendable formats); the maxima are decisions of the library
#   (`binary_precision_max` 2^28, `binary_implementation_e_max` 2^30 - 1: every
#   coefficient exponent stays in a 32-bit `Int`).
# - decimal and GDA: GDA 1.70 page 10 and the limits 999,999,999 of the
#   reference implementation's Context, adopted by the library
#   (`decimal_precision_max`, `decimal_implementation_e_max`).
BINARY_PRECISION_MAX = 268_435_456
BINARY_E_MAX_LIMIT = 1_073_741_823
BINARY_ROUNDINGS = ("n", "na", "z", "u", "d")  # roundTiesToEven, roundTiesToAway, toward zero, up, down
BINARY_TININESS = ("a", "b")  # after rounding, before rounding

DECIMAL_PRECISION_MAX = 999_999_999
DECIMAL_E_MAX_LIMIT = 999_999_999
DECIMAL_ROUNDINGS = ("half_even", "half_up", "down", "ceiling", "floor")
# `half_up` is roundTiesToAway, `down` roundTowardZero, `ceiling` roundTowardPositive, `floor` roundTowardNegative.

GDA_PRECISION_MAX = 999_999_999
GDA_E_LIMIT = 999_999_999
GDA_ROUNDINGS = ("half_even", "half_up", "half_down", "down", "ceiling", "floor", "up", "05up")


# ---------------------------------------------------------------------------
# The checks: raise ValueError naming the first thing that is wrong
# ---------------------------------------------------------------------------


def check_binary_context(
    precision: int, e_max: int | None = None, e_min: int | None = None, rounding: str = "n", tininess: str = "a"
) -> None:
    """Reject a `bin_float` context that no format has.

    `e_max` absent means the precision alone (the extendable format of 3.7): a
    one-sided range, an `e_min` without an `e_max`, is rejected. An `e_min` that
    is given must be `1 - e_max`.
    """
    if not 1 <= precision <= BINARY_PRECISION_MAX:
        raise ValueError(f"precision {precision} outside 1..{BINARY_PRECISION_MAX}")
    if rounding not in BINARY_ROUNDINGS:
        raise ValueError(f"rounding {rounding} is not a rounding direction of 4.3 (one of {', '.join(BINARY_ROUNDINGS)})")
    if tininess not in BINARY_TININESS:
        raise ValueError(f"tininess {tininess} is neither a nor b")
    if e_max is None:
        if e_min is not None:
            raise ValueError("a one-sided exponent range is not an IEEE 754-2019 format: give emax")
        return
    if not 1 <= e_max <= BINARY_E_MAX_LIMIT:
        raise ValueError(f"emax {e_max} outside 1..{BINARY_E_MAX_LIMIT}")
    if e_min is not None and e_min != 1 - e_max:
        raise ValueError(f"emin {e_min} is not 1 - emax ({1 - e_max}): not an IEEE 754-2019 format")


def check_ieee_decimal_context(
    precision: int, rounding: str, emin: int, emax: int, clamp: int, tininess: str
) -> None:
    """Reject a `decimal` context that no IEEE 754-2019 decimal format has (3.3, 4.3, 7.5)."""
    if not 1 <= precision <= DECIMAL_PRECISION_MAX:
        raise ValueError(f"precision {precision} outside 1..{DECIMAL_PRECISION_MAX}")
    if not 1 <= emax <= DECIMAL_E_MAX_LIMIT:
        raise ValueError(f"emax {emax} outside 1..{DECIMAL_E_MAX_LIMIT}")
    if emin != 1 - emax:
        raise ValueError(f"emin {emin} is not 1 - emax ({1 - emax}): not an IEEE 754-2019 format")
    if not clamp:
        raise ValueError("clamp must be 1: every result of an IEEE format is a member of the format")
    if tininess != "b":
        raise ValueError("tininess must be b: decimal formats detect tininess before rounding (7.5)")
    if rounding not in DECIMAL_ROUNDINGS:
        raise ValueError(f"rounding {rounding} is not a rounding-direction attribute of 4.3")


def gda_exponent_range_is_legal(e_min: int, e_max: int) -> bool:
    """GDA 1.70 page 10: Emin and Emax differ in magnitude by at most one, so Emin is -Emax, 1-Emax or -Emax-1."""
    return (
        0 <= e_max <= GDA_E_LIMIT
        and -GDA_E_LIMIT <= e_min <= 0
        and e_min in (-e_max - 1, -e_max, 1 - e_max)
    )


def check_gda_context(precision: int, e_min: int, e_max: int, rounding: str = "half_even", clamp: int = 0) -> None:
    """Reject a `decimal_gda` context that GDA 1.70 cannot have (and `GdaContext::try_new` rejects)."""
    if not 1 <= precision <= GDA_PRECISION_MAX:
        raise ValueError(f"precision {precision} outside 1..{GDA_PRECISION_MAX}")
    if not gda_exponent_range_is_legal(e_min, e_max):
        raise ValueError(f"Emin {e_min} and Emax {e_max} are not a GDA 1.70 exponent range")
    if rounding not in GDA_ROUNDINGS:
        raise ValueError(f"rounding {rounding} is not one of the eight GDA rounding modes")
    if clamp not in (0, 1):
        raise ValueError(f"clamp {clamp} is neither 0 nor 1")


# ---------------------------------------------------------------------------
# One frozen dataclass per standard: a generator builds a context only through it
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class BinaryFormat:
    """A `bin_float` context: `precision` and `e_max` (absent: the precision alone), `e_min = 1 - e_max`."""

    precision: int
    e_max: int | None = None
    rounding: str = "n"
    tininess: str = "a"

    def __post_init__(self) -> None:
        check_binary_context(self.precision, self.e_max, None, self.rounding, self.tininess)

    @property
    def e_min(self) -> int | None:
        return None if self.e_max is None else 1 - self.e_max


@dataclass(frozen=True)
class DecimalFormat:
    """An IEEE 754-2019 `decimal` context: `precision` and `e_max`, `e_min = 1 - e_max`, clamp on, tininess before rounding."""

    precision: int
    e_max: int
    rounding: str = "half_even"

    def __post_init__(self) -> None:
        check_ieee_decimal_context(self.precision, self.rounding, 1 - self.e_max, self.e_max, 1, "b")

    @property
    def e_min(self) -> int:
        return 1 - self.e_max

    clamp = 1
    tininess = "b"


@dataclass(frozen=True)
class GdaContextSpec:
    """A `decimal_gda` context of GDA 1.70 (page 10 for the exponent range)."""

    precision: int
    e_min: int
    e_max: int
    rounding: str = "half_even"
    clamp: int = 0

    def __post_init__(self) -> None:
        check_gda_context(self.precision, self.e_min, self.e_max, self.rounding, self.clamp)


# ---------------------------------------------------------------------------
# The vectors file
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Vector:
    """One line of `testdata/context_vectors.txt`: a context and its verdict.

    Columns: `standard precision e_min e_max rounding clamp tininess verdict`, with
    `-` for a field the standard does not have or the context leaves out.
    """

    standard: str
    precision: int
    e_min: int | None
    e_max: int | None
    rounding: str
    clamp: int | None
    tininess: str
    legal: bool
    line: str

    def check(self) -> None:
        """Raise `ValueError` when the context is not legal under the rules of this module."""
        if self.standard == "binary":
            check_binary_context(self.precision, self.e_max, self.e_min, self.rounding, self.tininess)
        elif self.standard == "decimal":
            assert self.e_min is not None and self.e_max is not None and self.clamp is not None
            check_ieee_decimal_context(self.precision, self.rounding, self.e_min, self.e_max, self.clamp, self.tininess)
        elif self.standard == "gda":
            assert self.e_min is not None and self.e_max is not None
            check_gda_context(self.precision, self.e_min, self.e_max, self.rounding, self.clamp or 0)
        else:
            raise ValueError(f"unknown standard {self.standard}")

    def is_legal(self) -> bool:
        try:
            self.check()
        except ValueError:
            return False
        return True


def _optional_int(text: str) -> int | None:
    return None if text == "-" else int(text)


def parse_vectors(text: str) -> list[Vector]:
    """The vectors of a file: blank lines and lines starting with `#` are comments, `#` after the columns too."""
    vectors = []
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        fields = line.split()
        if len(fields) != 8:
            raise ValueError(f"a vector has 8 columns: {raw!r}")
        standard, precision, e_min, e_max, rounding, clamp, tininess, verdict = fields
        if verdict not in ("legal", "illegal"):
            raise ValueError(f"verdict {verdict!r} is neither legal nor illegal: {raw!r}")
        vectors.append(
            Vector(standard, int(precision), _optional_int(e_min), _optional_int(e_max), rounding, _optional_int(clamp), tininess, verdict == "legal", line)
        )
    return vectors
