#!/usr/bin/env python3

import argparse
import json
import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DOC_ROOT = REPO_ROOT / "doc"
MANUAL_ROOT = DOC_ROOT / "manual"
LOCALE_ROOT = DOC_ROOT / "locale"
ATTACHMENT_ROOT = DOC_ROOT / "attachments"
RETIRED_LOCALE_DIRS = ("en_US", "zh_CN", "ja_JP")
PACKAGE_CHAPTERS = ("api", "tutorial", "design")
EVIDENCE_CHAPTERS = ("conformance", "performance")
NUMERICAL_CORES = ("bin_float", "decimal", "decimal_gda", "ball_float")
GUIDES = (
    "index.md",
    "conventions.md",
    "getting_started.md",
    "numeric_semantics.md",
    "architecture.md",
    "verification.md",
    "performance_audit.md",
)
GDA_RESULT = "64,986/64,986"
STALE_GDA_CLAIMS = ("conformance gap", "not full conformance", "完全な conformance ではなく")
LINK_RE = re.compile(r"(?<!!)\[[^]]+\]\(([^)]+)\)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$", re.MULTILINE)
API_BLOCK_RE = re.compile(
    r"<!-- generated-api-start -->\n```(?:mbti|moonbit)\n(.*?)\n```\n<!-- generated-api-end -->",
    re.DOTALL,
)
MODULE_VERSION_RE = re.compile(r'^version\s*=\s*"([^"]+)"', re.MULTILINE)
CHANGELOG_VERSION_RE = re.compile(r"^## (\d+\.\d+\.\d+)\b", re.MULTILINE)
HISTORICAL_BASELINE_RE = re.compile(
    r"<!-- historical-performance-baseline: (\d+\.\d+\.\d+) -->"
)
PO_STRING_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
PO_ESCAPES = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}


def package_paths() -> set[str]:
    # `tools/check_doc_examples.py` writes throwaway packages under an
    # underscore-prefixed directory and removes them again; they are not part of
    # the documented package set even if an interrupted run leaves them behind.
    return {
        str(path.parent.relative_to(REPO_ROOT / "src"))
        for path in (REPO_ROOT / "src").rglob("moon.pkg")
        if not any(part.startswith("_") for part in path.parent.parts)
    }


def manual_pages() -> set[str]:
    return {str(path.relative_to(MANUAL_ROOT)) for path in MANUAL_ROOT.rglob("*.md")}


def chapter_page(chapter: str, package: str) -> Path:
    return MANUAL_ROOT / chapter / f"{package}.md"


def translation_locales() -> list[str]:
    conf = json.loads((DOC_ROOT / "conf.json").read_text(encoding="utf-8"))
    return list(conf.get("locales", []))


def catalog_path(locale: str) -> Path:
    return LOCALE_ROOT / locale / "LC_MESSAGES" / "manual.po"


def po_unescape(value: str) -> str:
    return re.sub(r"\\(.)", lambda match: PO_ESCAPES.get(match.group(1), match.group(1)), value)


def read_catalog(path: Path) -> list[tuple[list[str], str, str]]:
    """Return (references, msgid, msgstr) for every active catalog entry."""
    entries: list[tuple[list[str], str, str]] = []
    references: list[str] = []
    fields: dict[str, str] = {}
    field = None

    def flush() -> None:
        if fields.get("msgid"):
            entries.append((references.copy(), fields["msgid"], fields.get("msgstr", "")))
        references.clear()
        fields.clear()

    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            flush()
            field = None
        elif line.startswith("#:"):
            references.extend(line[2:].split())
        elif line.startswith("#"):
            continue
        elif line.startswith('"') and field is not None:
            fields[field] += "".join(po_unescape(part) for part in PO_STRING_RE.findall(line))
        else:
            keyword, _, rest = line.partition(" ")
            field = keyword
            fields[field] = "".join(po_unescape(part) for part in PO_STRING_RE.findall(rest))
    flush()
    return entries


def check_retired_layout() -> list[str]:
    errors: list[str] = []
    for locale in RETIRED_LOCALE_DIRS:
        if (DOC_ROOT / locale).exists():
            errors.append(
                f"doc/{locale}: retired per-locale tree; English sources live in doc/manual "
                "and translations in doc/locale"
            )
    return errors


def check_catalogs_present() -> list[str]:
    errors: list[str] = []
    for locale in translation_locales():
        path = catalog_path(locale)
        if not path.exists():
            errors.append(f"{path.relative_to(REPO_ROOT)}: missing translation catalog")
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
    paths = [REPO_ROOT / "README.md", REPO_ROOT / "CONTRIBUTING.md"]
    paths.extend(sorted(MANUAL_ROOT.rglob("*.md")))
    for path in paths:
        text = path.read_text(encoding="utf-8")
        for raw_target in LINK_RE.findall(text):
            resolved_info = local_target(path, raw_target)
            if resolved_info is None:
                continue
            resolved, fragment = resolved_info
            if not resolved.is_relative_to(REPO_ROOT):
                errors.append(f"{path.relative_to(REPO_ROOT)}: link leaves the repository {raw_target}")
                continue
            if resolved.is_relative_to(ATTACHMENT_ROOT):
                # Attachments resolve per locale; `lunadoc check` owns them.
                continue
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
    return errors


def module_version() -> str:
    text = (REPO_ROOT / "moon.mod").read_text(encoding="utf-8")
    match = MODULE_VERSION_RE.search(text)
    if match is None:
        raise ValueError("moon.mod does not declare a version")
    return match.group(1)


def historical_versions() -> list[str]:
    current = module_version()
    changelog = (REPO_ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    return sorted(set(CHANGELOG_VERSION_RE.findall(changelog)) - {current})


def check_current_versions() -> list[str]:
    errors: list[str] = []
    current = module_version()
    historical = historical_versions()
    candidates = [REPO_ROOT / "README.md", REPO_ROOT / "CONTRIBUTING.md"]
    candidates.extend(MANUAL_ROOT.rglob("*.md"))
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


def check_translated_versions() -> list[str]:
    errors: list[str] = []
    historical = historical_versions()
    for locale in translation_locales():
        path = catalog_path(locale)
        if not path.exists():
            continue
        for references, msgid, msgstr in read_catalog(path):
            for version in historical:
                if version in msgstr and version not in msgid:
                    errors.append(
                        f"{path.relative_to(REPO_ROOT)}: {', '.join(references)}: "
                        f"translation adds stale {version} baseline"
                    )
    return errors


def check_package_doc_coverage() -> list[str]:
    errors: list[str] = []
    for package in sorted(package_paths()):
        for chapter in PACKAGE_CHAPTERS:
            if not chapter_page(chapter, package).exists():
                errors.append(f"doc/manual: missing {chapter}/{package}.md")
    for chapter in EVIDENCE_CHAPTERS:
        for package in NUMERICAL_CORES:
            if not chapter_page(chapter, package).exists():
                errors.append(f"doc/manual: missing {chapter}/{package}.md")
    for guide in GUIDES:
        if not (MANUAL_ROOT / guide).exists():
            errors.append(f"doc/manual: missing {guide}")
    return errors


def check_orphan_pages() -> list[str]:
    errors: list[str] = []
    packages = package_paths()
    chapters = (*PACKAGE_CHAPTERS, *EVIDENCE_CHAPTERS)
    for relative in sorted(manual_pages()):
        chapter, _, page = relative.partition("/")
        if not page:
            if relative not in GUIDES:
                errors.append(f"doc/manual/{relative}: unlisted guide")
            continue
        if chapter not in chapters:
            errors.append(f"doc/manual/{relative}: {chapter}/ is not a chapter")
            continue
        package = page.removesuffix(".md")
        if package not in packages:
            errors.append(f"doc/manual/{relative}: no src/{package}/moon.pkg package")
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
    for package in sorted(package_paths()):
        path = chapter_page("api", package)
        if not path.exists():
            continue
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


def has_stale_gda_claim(text: str) -> bool:
    lowered = text.lower()
    return any(claim in lowered for claim in STALE_GDA_CLAIMS)


def check_gda_claims() -> list[str]:
    errors: list[str] = []
    overview = MANUAL_ROOT / "index.md"
    if f"{GDA_RESULT} legal executable" not in overview.read_text(encoding="utf-8"):
        errors.append("doc/manual/index.md: missing complete GDA result")
    decimal_pages = ("api/decimal.md", "design/decimal.md")
    for relative in decimal_pages:
        path = MANUAL_ROOT / relative
        if has_stale_gda_claim(path.read_text(encoding="utf-8")):
            errors.append(f"{path.relative_to(REPO_ROOT)}: stale incomplete GDA claim")
    for locale in translation_locales():
        path = catalog_path(locale)
        if not path.exists():
            continue
        for references, msgid, msgstr in read_catalog(path):
            if not msgstr:
                continue
            pages = {reference.rpartition(":")[0] for reference in references}
            if "manual/index.md" in pages and GDA_RESULT in msgid and GDA_RESULT not in msgstr:
                errors.append(f"{path.relative_to(REPO_ROOT)}: index.md translation drops complete GDA result")
            if pages & {f"manual/{page}" for page in decimal_pages} and has_stale_gda_claim(msgstr):
                errors.append(
                    f"{path.relative_to(REPO_ROOT)}: {', '.join(references)}: stale incomplete GDA claim"
                )
    return errors


def run_checks() -> list[str]:
    return [
        *check_retired_layout(),
        *check_catalogs_present(),
        *check_links(),
        *check_current_versions(),
        *check_translated_versions(),
        *check_package_doc_coverage(),
        *check_orphan_pages(),
        *check_package_readme_coverage(),
        *check_api_snapshots(),
        *check_gda_claims(),
    ]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate the documentation manual")
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
