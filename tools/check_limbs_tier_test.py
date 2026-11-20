import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_limbs_tier as ct  # noqa: E402

OLD = "noise\nluna_limbs: cc_id=1 (1 clang) arch_id=2 (1 x86-64, 2 arm64) int128=1 cpu_features=0\nok\n"
X86 = "luna_limbs: cc_id=2 (2 gcc) arch_id=1 (1 x86-64, 2 arm64) int128=1 cpu_features=3\n"
ASM = "luna_limbs: cc_id=1 arch_id=2 int128=1 cpu_features=0 tier=asm\n"
C = "luna_limbs: cc_id=1 arch_id=2 int128=1 cpu_features=0 tier=c\n"


class ParseTests(unittest.TestCase):
    def test_a_log_without_a_tier_is_the_c_tier(self) -> None:
        self.assertEqual(ct.parse_line(OLD), (2, None))
        self.assertEqual(ct.parse_line(ASM), (2, "asm"))
        self.assertEqual(ct.parse_line(X86), (1, None))

    def test_the_last_line_counts_and_a_missing_line_is_an_error(self) -> None:
        self.assertEqual(ct.parse_line(C + ASM), (2, "asm"))
        with self.assertRaises(ValueError):
            ct.parse_line("no differential test ran\n")


class CheckTests(unittest.TestCase):
    def test_until_the_assembly_tier_lands_the_default_state_is_c(self) -> None:
        for state in ct.STATES:
            self.assertEqual(ct.check(OLD, state, "c"), [])
            self.assertEqual(ct.check(C, state, "c"), [])

    def test_the_default_state_must_report_the_expected_tier(self) -> None:
        self.assertEqual(ct.check(ASM, "default", "asm"), [])
        problems = ct.check(C, "default", "asm")
        self.assertEqual(len(problems), 1)
        self.assertIn("expected 'asm'", problems[0])
        self.assertIn("expected 'c'", ct.check(ASM, "default", "c")[0])

    def test_the_c_state_must_report_c_whatever_the_default_is(self) -> None:
        self.assertEqual(ct.check(C, "c", "asm"), [])
        self.assertIn("'c'", ct.check(ASM, "c", "asm")[0])

    def test_the_portable_state_checks_no_tier(self) -> None:
        self.assertEqual(ct.check(ASM, "portable", "c"), [])
        self.assertEqual(ct.check(C, "portable", "asm"), [])

    def test_an_x86_runner_is_a_problem_in_every_state(self) -> None:
        for state in ct.STATES:
            self.assertTrue(any("not arm64" in p for p in ct.check(X86, state, "c")))

    def test_the_command_line(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "log.txt"
            log.write_text(ASM, encoding="utf-8")
            self.assertEqual(ct.main(["--log", str(log), "--state", "default", "--expected", "asm"]), 0)
            self.assertEqual(ct.main(["--log", str(log), "--state", "default", "--expected", "c"]), 1)
            log.write_text("nothing\n", encoding="utf-8")
            self.assertEqual(ct.main(["--log", str(log), "--state", "default", "--expected", "c"]), 1)


if __name__ == "__main__":
    unittest.main()
