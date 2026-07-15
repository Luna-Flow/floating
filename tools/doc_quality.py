#!/usr/bin/env python3

import argparse
import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DOC_ROOT = REPO_ROOT / "doc"
LOCALES = ("en_US", "zh_CN", "ja_JP")
LINK_RE = re.compile(r"(?<!!)\[[^]]+\]\(([^)]+)\)")
MOONBIT_RE = re.compile(r"```moonbit(?:\s+check)?\n(.*?)```", re.DOTALL)
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$", re.MULTILINE)
API_BLOCK_RE = re.compile(
    r"<!-- generated-api-start -->\n```moonbit\n(.*?)\n```\n<!-- generated-api-end -->",
    re.DOTALL,
)
MODULE_VERSION_RE = re.compile(r'^version\s*=\s*"([^"]+)"', re.MULTILINE)
CHANGELOG_VERSION_RE = re.compile(r"^## (\d+\.\d+\.\d+)\b", re.MULTILINE)
HISTORICAL_BASELINE_RE = re.compile(
    r"<!-- historical-performance-baseline: (\d+\.\d+\.\d+) -->"
)


def package_paths() -> set[str]:
    return {
        str(path.parent.relative_to(REPO_ROOT / "src"))
        for path in (REPO_ROOT / "src").rglob("moon.pkg")
    }


def markdown_files(locale: str) -> set[str]:
    root = DOC_ROOT / locale
    return {str(path.relative_to(root)) for path in root.rglob("*.md")}


def check_locale_parity() -> list[str]:
    baseline = markdown_files("en_US")
    errors: list[str] = []
    for locale in LOCALES[1:]:
        actual = markdown_files(locale)
        missing = sorted(baseline - actual)
        extra = sorted(actual - baseline)
        if missing:
            errors.append(f"{locale}: missing files: {', '.join(missing)}")
        if extra:
            errors.append(f"{locale}: extra files: {', '.join(extra)}")
    return errors


def heading_levels(path: Path) -> tuple[int, ...]:
    return tuple(len(marker) for marker, _ in HEADING_RE.findall(path.read_text(encoding="utf-8")))


def heading_shape(path: Path) -> tuple[int, int]:
    levels = heading_levels(path)
    return levels.count(1), levels.count(2)


def check_heading_parity() -> list[str]:
    errors: list[str] = []
    for relative in sorted(markdown_files("en_US")):
        expected = heading_levels(DOC_ROOT / "en_US" / relative)
        for locale in LOCALES[1:]:
            actual = heading_levels(DOC_ROOT / locale / relative)
            if actual != expected:
                errors.append(
                    f"{locale}/{relative}: heading levels {actual} differ from en_US {expected}"
                )
    return errors


def github_anchor(text: str) -> str:
    value = re.sub(r"<[^>]+>", "", text).lower()
    value = re.sub(r"[^\w\- ]+", "", value, flags=re.UNICODE)
    return re.sub(r"\s+", "-", value.strip())


def local_target(path: Path, raw_target: str) -> tuple[Path, str | None] | None:
    target = raw_target.strip()
    if not target or "://" in target or target.startswith("mailto:"):
        return None
    target_path, _, fragment = target.partition("#")
    resolved = (path.parent / target_path).resolve() if target_path else path.resolve()
    return resolved, fragment or None


def check_links() -> list[str]:
    errors: list[str] = []
    for path in DOC_ROOT.rglob("*.md"):
        text = path.read_text(encoding="utf-8")
        for raw_target in LINK_RE.findall(text):
            resolved_info = local_target(path, raw_target)
            if resolved_info is None:
                continue
            resolved, fragment = resolved_info
            if not resolved.exists():
                errors.append(f"{path.relative_to(REPO_ROOT)}: broken link {raw_target}")
                continue
            if resolved.is_file() and fragment:
                anchors = {
                    github_anchor(heading)
                    for _, heading in HEADING_RE.findall(resolved.read_text(encoding="utf-8"))
                }
                if fragment.lower() not in anchors:
                    errors.append(f"{path.relative_to(REPO_ROOT)}: broken anchor {raw_target}")
            if resolved.is_relative_to(DOC_ROOT):
                locale = resolved.relative_to(DOC_ROOT).parts[0]
                source_locale = path.relative_to(DOC_ROOT).parts[0]
                if locale != source_locale:
                    errors.append(
                        f"{path.relative_to(REPO_ROOT)}: cross-locale link {raw_target}"
                    )
    return errors


def module_version() -> str:
    text = (REPO_ROOT / "moon.mod").read_text(encoding="utf-8")
    match = MODULE_VERSION_RE.search(text)
    if match is None:
        raise ValueError("moon.mod does not declare a version")
    return match.group(1)


def check_current_versions() -> list[str]:
    errors: list[str] = []
    current = module_version()
    changelog = (REPO_ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    historical = sorted(set(CHANGELOG_VERSION_RE.findall(changelog)) - {current})
    candidates = [REPO_ROOT / "README.md", REPO_ROOT / "CONTRIBUTING.md"]
    candidates.extend(DOC_ROOT.rglob("*.md"))
    candidates.extend(REPO_ROOT.glob("src/**/README.mbt.md"))
    for path in candidates:
        text = path.read_text(encoding="utf-8")
        allowed_historical = set(HISTORICAL_BASELINE_RE.findall(text))
        for version in historical:
            if version in text and version not in allowed_historical:
                errors.append(
                    f"{path.relative_to(REPO_ROOT)}: stale {version} baseline; current is {current}"
                )
    return errors


def check_package_doc_coverage() -> list[str]:
    errors: list[str] = []
    required = ("api.md", "tutorial.md", "design.md")
    for locale in LOCALES:
        for package in sorted(package_paths()):
            for filename in required:
                path = DOC_ROOT / locale / package / filename
                if not path.exists():
                    errors.append(f"{locale}: missing {package}/{filename}")
    return errors


def check_package_readme_coverage() -> list[str]:
    errors: list[str] = []
    for package in sorted(package_paths()):
        path = REPO_ROOT / "src" / package / "README.mbt.md"
        if not path.exists():
            errors.append(f"src/{package}: missing README.mbt.md")
    return errors


def generated_interface(package: str) -> str:
    return (REPO_ROOT / "src" / package / "pkg.generated.mbti").read_text(
        encoding="utf-8"
    ).strip()


def check_api_snapshots() -> list[str]:
    errors: list[str] = []
    for locale in LOCALES:
        for package in sorted(package_paths()):
            path = DOC_ROOT / locale / package / "api.md"
            text = path.read_text(encoding="utf-8")
            match = API_BLOCK_RE.search(text)
            if match is None:
                errors.append(f"{path.relative_to(REPO_ROOT)}: missing generated API snapshot")
                continue
            actual = match.group(1).strip()
            expected = generated_interface(package)
            if actual != expected:
                errors.append(f"{path.relative_to(REPO_ROOT)}: generated API snapshot is stale")
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
        *check_package_doc_coverage(),
        *check_package_readme_coverage(),
        *check_api_snapshots(),
        *check_gda_claims(),
        *check_tutorial_examples(),
    ]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate localized documentation")
    parser.parse_args(argv)
    errors = run_checks()
    if errors:
        for error in errors:
            print(error)
        return 1
    print("documentation quality checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
