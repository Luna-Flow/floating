#!/usr/bin/env python3

import argparse
import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DOC_ROOT = REPO_ROOT / "doc"
LOCALES = ("en_US", "zh_CN", "ja_JP")
LOCALE_ONLY = {
    "zh_CN": {
        "ball_float/binary_kernel_research.md",
        "ball_float/ieee1788_research.md",
        "bin_float/coefficient_kernel_baseline.md",
    },
}
LINK_RE = re.compile(r"(?<!!)\[[^]]+\]\(([^)]+)\)")
MOONBIT_RE = re.compile(r"```moonbit(?:\s+check)?\n(.*?)```", re.DOTALL)
HEADING_RE = re.compile(r"^(#{1,2})\s+", re.MULTILINE)


def markdown_files(locale: str) -> set[str]:
    root = DOC_ROOT / locale
    return {str(path.relative_to(root)) for path in root.rglob("*.md")}


def check_locale_parity() -> list[str]:
    baseline = markdown_files("en_US")
    errors: list[str] = []
    for locale in LOCALES[1:]:
        actual = markdown_files(locale) - LOCALE_ONLY.get(locale, set())
        missing = sorted(baseline - actual)
        extra = sorted(actual - baseline)
        if missing:
            errors.append(f"{locale}: missing files: {', '.join(missing)}")
        if extra:
            errors.append(f"{locale}: extra files: {', '.join(extra)}")
    return errors


def heading_shape(path: Path) -> tuple[int, int]:
    levels = [len(marker) for marker in HEADING_RE.findall(path.read_text(encoding="utf-8"))]
    return levels.count(1), levels.count(2)


def check_heading_parity() -> list[str]:
    errors: list[str] = []
    for relative in sorted(markdown_files("en_US")):
        expected = heading_shape(DOC_ROOT / "en_US" / relative)
        for locale in LOCALES[1:]:
            actual = heading_shape(DOC_ROOT / locale / relative)
            if actual != expected:
                errors.append(
                    f"{locale}/{relative}: heading shape {actual} differs from en_US {expected}"
                )
    return errors


def check_links() -> list[str]:
    errors: list[str] = []
    for path in DOC_ROOT.rglob("*.md"):
        text = path.read_text(encoding="utf-8")
        for raw_target in LINK_RE.findall(text):
            target = raw_target.strip().split("#", 1)[0]
            if not target or "://" in target or target.startswith("mailto:"):
                continue
            resolved = (path.parent / target).resolve()
            if not resolved.exists():
                errors.append(f"{path.relative_to(REPO_ROOT)}: broken link {raw_target}")
    return errors


def check_current_versions() -> list[str]:
    errors: list[str] = []
    candidates = [REPO_ROOT / "README.md", REPO_ROOT / "CONTRIBUTING.md"]
    candidates.extend(DOC_ROOT.rglob("*.md"))
    candidates.extend(REPO_ROOT.glob("src/**/README.mbt.md"))
    for path in candidates:
        if path.name == "architecture_research.md":
            continue
        text = path.read_text(encoding="utf-8")
        if re.search(r"(?:baseline|基线|基準|current).*0\.4\.[01]", text, re.IGNORECASE):
            errors.append(f"{path.relative_to(REPO_ROOT)}: stale current baseline")
    return errors


def check_gda_claims() -> list[str]:
    errors: list[str] = []
    required = {
        "en_US": "64,986/64,986 legal executable",
        "zh_CN": "64,986/64,986",
        "ja_JP": "64,986/64,986",
    }
    for locale, marker in required.items():
        text = (DOC_ROOT / locale / "README.md").read_text(encoding="utf-8")
        if marker not in text:
            errors.append(f"{locale}/README.md: missing complete GDA result")
    for path in (
        DOC_ROOT / "en_US" / "decimal" / "api.md",
        DOC_ROOT / "zh_CN" / "decimal" / "api.md",
        DOC_ROOT / "ja_JP" / "decimal" / "api.md",
        DOC_ROOT / "en_US" / "decimal" / "design.md",
        DOC_ROOT / "zh_CN" / "decimal" / "design.md",
        DOC_ROOT / "ja_JP" / "decimal" / "design.md",
    ):
        text = path.read_text(encoding="utf-8").lower()
        if "conformance gap" in text or "not full conformance" in text or "完全な conformance ではなく" in text:
            errors.append(f"{path.relative_to(REPO_ROOT)}: stale incomplete GDA claim")
    return errors


def normalized_examples(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    return ["\n".join(line.rstrip() for line in block.strip().splitlines()) for block in MOONBIT_RE.findall(text)]


def example_shapes(path: Path) -> list[str]:
    shapes: list[str] = []
    for block in normalized_examples(path):
        match = re.search(r'test\s+"([^"]+)"', block)
        if match:
            shapes.append(match.group(1))
    return shapes


def check_tutorial_examples() -> list[str]:
    errors: list[str] = []
    for relative in sorted(markdown_files("en_US")):
        if not relative.endswith("tutorial.md"):
            continue
        expected = example_shapes(DOC_ROOT / "en_US" / relative)
        for locale in LOCALES[1:]:
            actual = example_shapes(DOC_ROOT / locale / relative)
            if actual != expected:
                errors.append(f"{locale}/{relative}: MoonBit example structure differs from en_US")
    return errors


def run_checks() -> list[str]:
    return [
        *check_locale_parity(),
        *check_heading_parity(),
        *check_links(),
        *check_current_versions(),
        *check_gda_claims(),
        *check_tutorial_examples(),
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate localized documentation")
    parser.parse_args()
    errors = run_checks()
    if errors:
        for error in errors:
            print(error)
        return 1
    print("documentation quality checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
