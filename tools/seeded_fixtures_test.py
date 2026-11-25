"""The committed seeded fixtures and smoke files are pinned by a sha256 in a manifest.

Level A/E statement (RULES.md, "The oracle of a test must be independent of the code
under test"): these tests do not judge any value of a fixture. They make a change of a
fixture visible. A fixture that changes without its manifest entry changing fails
`test_every_pinned_file_matches_its_hash`; a new fixture file without an entry fails
`test_every_fixture_file_is_pinned`; the three seeded samples that a cheap deterministic
program produces are regenerated into a temporary directory and compared byte for byte
(`test_seeded_samples_regenerate_byte_for_byte`, MPFR C program and libmpdec, level A: the
generators call no code of this library).

Manifests, one per family (the convention of `corpus_common.load_manifest`):
- `testdata/binary/corpora.json`: `mpfrCorpora` (run by the binary gate) and `seededFixtures`;
- `testdata/binary/smoke/manifest.json`: `sha256` of every TestFloat and MPFR smoke file;
- `testdata/decimal_gda/corpora.json`: `seededFixtures`;
- `testdata/decimal/fixtures.json`: every generated or hand-selected decimal row file.

A deliberate change of a fixture is made by its generator; the commit then replaces the
`sha256` in the manifest by the new digest and says why the rows changed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

REPO_ROOT = Path(__file__).resolve().parent.parent
TESTDATA = REPO_ROOT / "testdata"
# Directories whose row files are fixtures. `testdata/decimal_gda/official*` and
# `testdata/interval/itf1788` are fetched, git-ignored and pinned by the zip archive.
FIXTURE_DIRECTORIES = ("binary", "decimal", "decimal_gda")
FIXTURE_SUFFIXES = (".txt", ".testfloat", ".decTest")
FETCHED_PREFIXES = ("decimal_gda/official",)


def load(path: str) -> dict:
    return json.loads((REPO_ROOT / path).read_text(encoding="utf-8"))


def pinned_entries() -> list[tuple[str, dict]]:
    """Every manifest entry that pins a committed file, as (label, entry)."""
    entries: list[tuple[str, dict]] = []
    binary = load("testdata/binary/corpora.json")
    for section in ("mpfrCorpora", "seededFixtures"):
        entries += [(f"binary/corpora.json {section} {name}", spec) for name, spec in binary[section].items()]
    smoke = load("testdata/binary/smoke/manifest.json")
    for section in ("testfloat", "mpfr"):
        entries += [(f"binary/smoke/manifest.json {section} {spec['path']}", spec) for spec in smoke[section]]
    gda = load("testdata/decimal_gda/corpora.json")
    entries += [(f"decimal_gda/corpora.json seededFixtures {name}", spec) for name, spec in gda["seededFixtures"].items()]
    decimal = load("testdata/decimal/fixtures.json")
    entries += [(f"decimal/fixtures.json {name}", spec) for name, spec in decimal["fixtures"].items()]
    return entries


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class PinnedFixtureTest(unittest.TestCase):
    def test_every_pinned_file_matches_its_hash(self) -> None:
        entries = pinned_entries()
        self.assertGreater(len(entries), 40)
        for label, spec in entries:
            with self.subTest(label):
                self.assertIn("sha256", spec, f"{label}: no sha256")
                path = REPO_ROOT / spec["path"]
                self.assertTrue(path.is_file(), f"{label}: {spec['path']} is missing")
                self.assertEqual(
                    digest(path),
                    spec["sha256"],
                    f"{spec['path']} changed without its manifest entry ({label}); "
                    "regenerate or review it, then replace the sha256 in the manifest",
                )

    def test_every_fixture_file_is_pinned(self) -> None:
        pinned = {spec["path"] for _, spec in pinned_entries()}
        found = {
            path.relative_to(REPO_ROOT).as_posix()
            for directory in FIXTURE_DIRECTORIES
            for path in (TESTDATA / directory).rglob("*")
            if path.is_file()
            and path.suffix in FIXTURE_SUFFIXES
            and not path.relative_to(TESTDATA).as_posix().startswith(FETCHED_PREFIXES)
        }
        self.assertEqual(sorted(found - pinned), [], "fixture files without a sha256 in a manifest")
        # a manifest entry whose file was deleted is caught by the hash test (the file is missing)

    def test_the_seeded_samples_say_how_they_are_regenerated(self) -> None:
        for label, spec in pinned_entries():
            if spec.get("regenerate"):
                with self.subTest(label):
                    self.assertIn("command", spec)
                    self.assertIn("generator", spec)
                    self.assertTrue((REPO_ROOT / spec["generator"].split()[0]).is_file())


def compatible_libmpdec_header(generated: bytes, installed: str, recorded: str) -> bytes:
    """The regenerated libmpdec fixture with the header version of the recorded one when only the patch version differs.

    The first line of the fixture names the libmpdec version that wrote it (`libmpdec=4.0.0`).
    A patch release of the same major and minor version (4.0.1 for 4.0.0) changes that token and
    nothing else; the rows are still compared byte for byte. Another major or minor version is
    left as it is, so that the comparison fails and the fixture is regenerated on purpose.
    """
    if installed == recorded or installed.split(".")[:2] != recorded.split(".")[:2]:
        return generated
    first, newline, rest = generated.partition(b"\n")
    return first.replace(f"libmpdec={installed}".encode(), f"libmpdec={recorded}".encode()) + newline + rest


class LibmpdecHeaderTest(unittest.TestCase):
    HEADER = b"-- generator=x libmpdec=4.0.1 seed=1\nrow libmpdec=4.0.1\n"

    def test_a_patch_version_is_mapped_to_the_recorded_one_in_the_first_line_only(self) -> None:
        self.assertEqual(
            compatible_libmpdec_header(self.HEADER, "4.0.1", "4.0.0"),
            b"-- generator=x libmpdec=4.0.0 seed=1\nrow libmpdec=4.0.1\n",
        )

    def test_the_same_version_is_unchanged(self) -> None:
        self.assertEqual(compatible_libmpdec_header(self.HEADER, "4.0.1", "4.0.1"), self.HEADER)

    def test_a_minor_or_major_version_is_not_tolerated(self) -> None:
        self.assertEqual(compatible_libmpdec_header(self.HEADER, "4.1.0", "4.0.0"), self.HEADER)
        self.assertEqual(compatible_libmpdec_header(self.HEADER, "5.0.1", "4.0.0"), self.HEADER)

    def test_a_row_value_that_differs_is_still_a_difference(self) -> None:
        changed = b"-- generator=x libmpdec=4.0.1 seed=1\nrox libmpdec=4.0.1\n"
        # only the header token is mapped: the changed row stays as it is, so the byte comparison fails
        self.assertEqual(
            compatible_libmpdec_header(changed, "4.0.1", "4.0.0"),
            b"-- generator=x libmpdec=4.0.0 seed=1\nrox libmpdec=4.0.1\n",
        )
        self.assertNotEqual(
            compatible_libmpdec_header(changed, "4.0.1", "4.0.0"),
            b"-- generator=x libmpdec=4.0.0 seed=1\nrow libmpdec=4.0.1\n",
        )


class RegenerationTest(unittest.TestCase):
    """`random_differential.py fixtures` into a temporary directory, compared with the committed files.

    About 5 s: two C programs (MPFR 4.2.2, GMP) are compiled into the temporary directory and
    run; the libmpdec sample needs only Python. Skipped (and reported by `run_python_tests.py`)
    when no MPFR header is installed or when the installed MPFR is not the version of the
    manifest: the rows of another MPFR version may differ and the hash test above still holds.
    """

    def test_seeded_samples_regenerate_byte_for_byte(self) -> None:
        import generate_mpfr_decimal_random as decimal_oracle
        import random_differential as rd

        specs = {
            "binary": load("testdata/binary/corpora.json")["seededFixtures"]["mpfr-4.2.2-random"],
            "decimal_gda": load("testdata/decimal_gda/corpora.json")["seededFixtures"]["libmpdec-random"],
            "decimal": load("testdata/decimal/fixtures.json")["fixtures"]["mpfr-decimal-random"],
        }
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            targets = {name: work / "out" / Path(spec["path"]).name for name, spec in specs.items()}
            (work / "out").mkdir()
            try:
                with (
                    mock.patch.object(rd, "GENERATOR_BINARY", work / "bin" / "generate_mpfr_random_oracle"),
                    mock.patch.object(decimal_oracle, "ENCLOSURE_BINARY", work / "bin" / "mpfr_decimal_enclosure"),
                    mock.patch.dict(rd.FIXTURES, targets),
                ):
                    rd.build_generator()
                    mpfr_version, _ = rd.library_versions()
                    if mpfr_version != specs["binary"]["mpfr"]:
                        self.skipTest(f"MPFR {mpfr_version} installed, the fixtures are from {specs['binary']['mpfr']}")
                    rd.cmd_fixtures(argparse.Namespace(count=rd.FIXTURE_COUNT, mpfr_prefix=None))
            except (rd.ToolError, RuntimeError) as error:
                if "mpfr.h not found" in str(error) or "cannot build" in str(error):
                    self.skipTest(f"cannot build the MPFR generators: {error}")
                raise
            import decimal

            for name, spec in specs.items():
                with self.subTest(name):
                    generated = targets[name].read_bytes()
                    if name == "decimal_gda":
                        generated = compatible_libmpdec_header(
                            generated, decimal.__libmpdec_version__, spec["libmpdec"]
                        )
                    self.assertEqual(
                        generated,
                        (REPO_ROOT / spec["path"]).read_bytes(),
                        f"{spec['path']} differs from its seeded regeneration ({spec['command']})",
                    )


if __name__ == "__main__":
    unittest.main()
