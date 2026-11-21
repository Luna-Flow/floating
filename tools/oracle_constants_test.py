"""The numbers that the oracle programs keep as their own copy of the library's
limits are the same everywhere (the C random oracle, the Python rule module,
the range-boundary generator, the libmpdec generator) and equal the numbers
written in `tooling/src/consistency/oracle_constants_wbtest.mbt`, which asserts
them against the library. A limit that changes in one place fails here."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

import context_rules
import generate_libmpdec_random
import range_boundary_rows

REPO = Path(__file__).resolve().parent.parent

# The written numbers; the MoonBit test asserts the same numbers against the
# library, so the library and every oracle program are tied to these.
BINARY_E_MAX = 1073741823
BINARY_E_MIN = -1073741822
BINARY_PRECISION_MAX = 268435456
DECIMAL_LIMIT = 999999999
MATH_LIMIT = 999999


class OracleConstantsTest(unittest.TestCase):
    def test_c_random_oracle_range(self) -> None:
        source = (REPO / "tools" / "generate_mpfr_random_oracle.c").read_text()
        emax = re.search(r"#define IMPL_EMAX (\d+)L", source)
        self.assertIsNotNone(emax)
        self.assertEqual(int(emax.group(1)), BINARY_E_MAX)
        self.assertIn("#define IMPL_EMIN (1 - IMPL_EMAX)", source)

    def test_range_boundary_rows(self) -> None:
        self.assertEqual(range_boundary_rows.IMPL_EMAX, BINARY_E_MAX)
        self.assertEqual(range_boundary_rows.IMPL_EMIN, BINARY_E_MIN)
        self.assertEqual(range_boundary_rows.IMPL_EMIN, 1 - range_boundary_rows.IMPL_EMAX)

    def test_context_rules_limits(self) -> None:
        self.assertEqual(context_rules.BINARY_E_MAX_LIMIT, BINARY_E_MAX)
        self.assertEqual(context_rules.BINARY_PRECISION_MAX, BINARY_PRECISION_MAX)
        self.assertEqual(context_rules.DECIMAL_PRECISION_MAX, DECIMAL_LIMIT)
        self.assertEqual(context_rules.DECIMAL_E_MAX_LIMIT, DECIMAL_LIMIT)
        self.assertEqual(context_rules.GDA_PRECISION_MAX, DECIMAL_LIMIT)
        self.assertEqual(context_rules.GDA_E_LIMIT, DECIMAL_LIMIT)

    def test_libmpdec_generator_math_limit(self) -> None:
        self.assertEqual(generate_libmpdec_random.MATH_LIMIT, MATH_LIMIT)


if __name__ == "__main__":
    unittest.main()
