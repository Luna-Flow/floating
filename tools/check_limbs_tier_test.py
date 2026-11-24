"""Tests of `check_limbs_tier.py`.

Oracle (level A): every log line below is written by hand in the format of the line printed by
`coeff_limbs_native_wbtest.mbt` (the three `REAL_*` lines are copied from the nightly run 45176216134),
and every expected verdict is written by hand from the rules in the docstring of the checker
(arch_id=2; tier portable, c, expected; override 1, 1, 0). Nothing is computed by the checker.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_limbs_tier as ct  # noqa: E402

HEAD = "luna_limbs: cc_id=1 (1 clang, 2 gcc, 3 msvc, 4 tcc) arch_id=2 (1 x86-64, 2 arm64) int128=1 cpu_features=0 (bit 0 BMI2, bit 1 ADX) "
REAL_PORTABLE = "noise\n" + HEAD + "tier=portable (mode 0) asm_compiled_in=1 override=1\nok\n"
REAL_C = HEAD + "tier=c (mode 1) asm_compiled_in=1 override=1\n"
REAL_DEFAULT = HEAD + "tier=asm (mode 2) asm_compiled_in=1 override=0\n"
DEFAULT_C = HEAD + "tier=c (mode 1) asm_compiled_in=0 override=0\n"
X86 = "luna_limbs: cc_id=2 (2 gcc) arch_id=1 (1 x86-64, 2 arm64) int128=1 cpu_features=3 tier=asm (mode 2) asm_compiled_in=1 override=0\n"
NO_OVERRIDE = "luna_limbs: cc_id=1 arch_id=2 int128=1 cpu_features=0 tier=c (mode 1)\n"
C_ONLY_BUILD = "luna_limbs: cc_id=1 arch_id=2 int128=1 cpu_features=0 override=0\n"


class ParseTests(unittest.TestCase):
    def test_the_fields_of_the_line(self) -> None:
        self.assertEqual(ct.parse_line(REAL_PORTABLE), (2, "portable", True))
        self.assertEqual(ct.parse_line(REAL_C), (2, "c", True))
        self.assertEqual(ct.parse_line(REAL_DEFAULT), (2, "asm", False))
        self.assertEqual(ct.parse_line(X86), (1, "asm", False))
        self.assertEqual(ct.parse_line(NO_OVERRIDE), (2, "c", None))
        self.assertEqual(ct.parse_line(C_ONLY_BUILD), (2, None, False))

    def test_the_last_line_counts_and_a_missing_line_is_an_error(self) -> None:
        self.assertEqual(ct.parse_line(REAL_C + REAL_DEFAULT), (2, "asm", False))
        with self.assertRaises(ValueError):
            ct.parse_line("no differential test ran\n")


class CheckTests(unittest.TestCase):
    def test_the_three_real_states_pass(self) -> None:
        self.assertEqual(ct.check(REAL_PORTABLE, "portable", "asm"), [])
        self.assertEqual(ct.check(REAL_C, "c", "asm"), [])
        self.assertEqual(ct.check(REAL_DEFAULT, "default", "asm"), [])

    def test_a_c_only_build_is_the_c_tier(self) -> None:
        self.assertEqual(ct.check(C_ONLY_BUILD, "default", "c"), [])
        self.assertEqual(len(ct.check(C_ONLY_BUILD, "default", "asm")), 1)

    def test_portable_state_with_a_c_line_fails(self) -> None:
        problems = ct.check(REAL_C, "portable", "asm")
        self.assertEqual(len(problems), 1)
        self.assertIn("expected 'portable'", problems[0])

    def test_c_state_with_an_asm_line_fails(self) -> None:
        problems = ct.check(REAL_DEFAULT, "c", "asm")
        self.assertEqual(len(problems), 2)  # the tier and override=0
        self.assertTrue(any("expected 'c'" in p for p in problems))

    def test_c_state_with_a_portable_line_fails(self) -> None:
        self.assertIn("expected 'c'", ct.check(REAL_PORTABLE, "c", "asm")[0])

    def test_default_state_with_override_fails(self) -> None:
        line = HEAD + "tier=asm (mode 2) asm_compiled_in=1 override=1\n"
        problems = ct.check(line, "default", "asm")
        self.assertEqual(len(problems), 1)
        self.assertIn("expected override=0", problems[0])

    def test_default_state_with_the_wrong_tier_fails(self) -> None:
        problems = ct.check(DEFAULT_C, "default", "asm")
        self.assertEqual(len(problems), 1)
        self.assertIn("expected 'asm'", problems[0])

    def test_portable_and_c_states_without_override_fail(self) -> None:
        self.assertIn("expected override=1", ct.check(REAL_DEFAULT.replace("asm", "c"), "c", "asm")[0])
        self.assertIn("expected override=1", ct.check(HEAD + "tier=portable (mode 0) asm_compiled_in=1 override=0\n", "portable", "asm")[0])

    def test_a_line_without_override_is_a_problem_in_every_state(self) -> None:
        for state in ct.STATES:
            self.assertTrue(any("no `override=`" in p for p in ct.check(NO_OVERRIDE, state, "c")))

    def test_an_x86_runner_is_a_problem_in_every_state(self) -> None:
        for state in ct.STATES:
            self.assertTrue(any("not arm64" in p for p in ct.check(X86, state, "asm")))

    def test_the_command_line(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "log.txt"
            log.write_text(REAL_DEFAULT, encoding="utf-8")
            self.assertEqual(ct.main(["--log", str(log), "--state", "default", "--expected", "asm"]), 0)
            self.assertEqual(ct.main(["--log", str(log), "--state", "default", "--expected", "c"]), 1)
            self.assertEqual(ct.main(["--log", str(log), "--state", "c", "--expected", "asm"]), 1)
            log.write_text("nothing\n", encoding="utf-8")
            self.assertEqual(ct.main(["--log", str(log), "--state", "default", "--expected", "c"]), 1)


if __name__ == "__main__":
    unittest.main()
