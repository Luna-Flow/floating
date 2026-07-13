import unittest

import generate_ieee_decimal_vectors


class IeeeVectorPlanTests(unittest.TestCase):
    def test_plan_requires_hundred_thousand_cases_per_family(self) -> None:
        plan = generate_ieee_decimal_vectors.load_plan()
        self.assertGreaterEqual(plan["targetCasesPerFamily"], 100000)
        self.assertEqual(len(plan["families"]), 10)
        self.assertEqual(len(plan["dataScales"]), 9)

    def test_generator_is_deterministic_and_hits_all_formats(self) -> None:
        first = list(generate_ieee_decimal_vectors.generate("sqrt", 96, 6060001))
        second = list(generate_ieee_decimal_vectors.generate("sqrt", 96, 6060001))
        self.assertEqual(first, second)
        self.assertEqual({row["format"] for row in first}, set(generate_ieee_decimal_vectors.FORMATS))
        self.assertGreaterEqual({row["boundary"] for row in first}.__len__(), 8)
        self.assertEqual({row["dataScale"] for row in first}, set(generate_ieee_decimal_vectors.DATA_SCALES))
        self.assertEqual({row["shape"] for row in first}, set(generate_ieee_decimal_vectors.SHAPES))


if __name__ == "__main__":
    unittest.main()
