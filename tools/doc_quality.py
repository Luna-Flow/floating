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
NUMERICAL_CORES = ("bin_float", "decimal", "decimal_gda", "interval")
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
# A line may name a released version when it says so: the install command of the
# latest published release (`moon add Luna-Flow/floating@0.10.2` stays correct
# until the next release is published), the file name of its stored measurement
# (`summary-0.10.2.json`), or an explicit "latest published" statement.
PUBLISHED_VERSION_CONTEXT_RE = re.compile(r"moon add \S+@|summary-\d|latest published")
HISTORICAL_BASELINE_RE = re.compile(
    r"<!-- historical-performance-baseline: (\d+\.\d+\.\d+) -->"
)
PO_STRING_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
PO_ESCAPES = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}


# MoonBit sources of the two modules: the library (`library/moon.mod`) and the tools
# module (`tooling/moon.mod`). A package keeps the name it has below its source
# root, and the manual pages are named after it.
def source_roots() -> tuple[Path, Path]:
    return (REPO_ROOT / "library" / "src", REPO_ROOT / "tooling" / "src")


def package_paths() -> set[str]:
    # `tools/check_doc_examples.py` writes throwaway packages under an
    # underscore-prefixed directory and removes them again; they are not part of
    # the documented package set even if an interrupted run leaves them behind.
    # Only the parts below a source root count: the checkout itself may live
    # under an underscore-prefixed directory.
    return {
        str(path.parent.relative_to(source_root))
        for source_root in source_roots()
        for path in source_root.rglob("moon.pkg")
        if not any(
            part.startswith("_") for part in path.parent.relative_to(source_root).parts
        )
    }


def package_directory(package: str) -> Path:
    """The directory of a documented package, in whichever module holds it."""
    for source_root in source_roots():
        if (source_root / package / "moon.pkg").exists():
            return source_root / package
    raise FileNotFoundError(f"no package {package} below {source_roots()}")


def is_executable(directory: Path) -> bool:
    text = (directory / "moon.pkg").read_text(encoding="utf-8")
    return re.search(r'pkgtype\(\s*kind:\s*"executable"', text) is not None


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
    paths = [
        path
        for path in (
            REPO_ROOT / "README.md",
            REPO_ROOT / "library" / "README.md",
            REPO_ROOT / "tooling" / "README.md",
            REPO_ROOT / "CONTRIBUTING.md",
        )
        if path.exists()
    ]
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
    text = (REPO_ROOT / "library" / "moon.mod").read_text(encoding="utf-8")
    match = MODULE_VERSION_RE.search(text)
    if match is None:
        raise ValueError("moon.mod does not declare a version")
    return match.group(1)


def historical_versions() -> list[str]:
    current = module_version()
    changelog = (REPO_ROOT / "library" / "CHANGELOG.md").read_text(encoding="utf-8")
    return sorted(set(CHANGELOG_VERSION_RE.findall(changelog)) - {current})


def names_version(line: str, version: str) -> bool:
    """Whether `line` names `version` itself, not a longer one such as `0.10.20`."""
    return re.search(rf"(?<![\w.]){re.escape(version)}(?!\w|\.\d)", line) is not None


def check_current_versions() -> list[str]:
    errors: list[str] = []
    current = module_version()
    historical = historical_versions()
    candidates = [
        path
        for path in (
            REPO_ROOT / "README.md",
            REPO_ROOT / "library" / "README.md",
            REPO_ROOT / "tooling" / "README.md",
            REPO_ROOT / "CONTRIBUTING.md",
        )
        if path.exists()
    ]
    candidates.extend(MANUAL_ROOT.rglob("*.md"))
    candidates.extend(REPO_ROOT.glob("library/src/**/README.mbt.md"))
    candidates.extend(REPO_ROOT.glob("tooling/src/**/README.mbt.md"))
    for path in candidates:
        text = path.read_text(encoding="utf-8")
        allowed_historical = set(HISTORICAL_BASELINE_RE.findall(text))
        for version in historical:
            if version in allowed_historical:
                continue
            stale = [
                line
                for line in text.splitlines()
                if names_version(line, version) and not PUBLISHED_VERSION_CONTEXT_RE.search(line)
            ]
            if stale:
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
            errors.append(f"doc/manual/{relative}: no {package}/moon.pkg package below src or tooling/src")
    return errors


def check_package_readme_coverage() -> list[str]:
    errors: list[str] = []
    for package in sorted(package_paths()):
        directory = package_directory(package)
        # A main package holds no `.mbt.md` file: the toolchain deprecates
        # blackbox test inputs in main packages, so an executable package keeps a
        # plain README.md and its behaviour lives in a library package.
        name = "README.md" if is_executable(directory) else "README.mbt.md"
        if not (directory / name).exists():
            errors.append(f"{directory.relative_to(REPO_ROOT)}: missing {name}")
        if is_executable(directory) and list(directory.glob("*.mbt.md")):
            errors.append(f"{directory.relative_to(REPO_ROOT)}: a main package must not hold .mbt.md files")
    return errors


def generated_interface(package: str) -> str:
    return (package_directory(package) / "pkg.generated.mbti").read_text(
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


EVIDENCE_PATH_RE = re.compile(r"`((?:library|tooling|testdata|tools)/[^`\s]+)`")


def check_evidence_paths() -> list[str]:
    """Every repository path cited in an evidence page must exist.

    The clause traceability tables of the conformance pages and the
    implementation-defined choices cite tests, corpora and tools by path; a
    renamed or deleted file must not leave a claim pointing at nothing.
    """
    errors: list[str] = []
    pages = sorted((MANUAL_ROOT / "conformance").glob("*.md"))
    pages.append(MANUAL_ROOT / "verification.md")
    for path in pages:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        for match in EVIDENCE_PATH_RE.finditer(text):
            cited = match.group(1)
            if "*" in cited or "<" in cited:
                continue
            if not (REPO_ROOT / cited).exists():
                errors.append(
                    f"{path.relative_to(REPO_ROOT)}: cited path does not exist: {cited}"
                )
    return errors


def check_conformance_checklist() -> list[str]:
    """The checklist of verification.md is generated from the clause tables."""
    import conformance_checklist

    text = (MANUAL_ROOT / "verification.md").read_text(encoding="utf-8")
    if conformance_checklist.START not in text:
        return ["doc/manual/verification.md: conformance checklist markers are missing"]
    head, rest = text.split(conformance_checklist.START, 1)
    current, _ = rest.split(conformance_checklist.END, 1)
    if current.strip("\n") != conformance_checklist.build():
        return [
            "doc/manual/verification.md: conformance checklist is stale; "
            "run python3 tools/conformance_checklist.py --write"
        ]
    return []


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


# The documentation standard of the tools module (the same pages as the library, see
# doc/manual/conventions.md). Every package of `tooling/src` is checked; the library
# packages keep their own, richer structure.
TOOLING_API_HEADINGS = ("Purpose", "Importing", "Complete public interface")
TOOLING_TUTORIAL_HEADINGS = ("Quick start", "Everyday tasks", "Going further", "Common pitfalls", "Next steps")
TOOLING_DESIGN_HEADINGS = (
    "Design goal",
    "Mathematical background",
    "Design decisions",
    "Correctness and invariants",
    "Alternatives rejected",
    "Boundaries",
)
# A tutorial of a package with public items needs one example that compiles, unless
# the items cannot run inside a test (`differential/harness` is asynchronous and
# native only).
TOOLING_NO_COMPILED_EXAMPLE = frozenset({"differential/harness"})
MBTI_ITEM_RE = re.compile(
    r"^pub(?:\(\w+\))?\s+(?:async\s+)?(?:fn|struct|enum|type|trait|let|const|suberror|typealias)\s+"
    r"(?:\[.*?\]\s*)?([A-Za-z_]\w*(?:::\w+)?)",
    re.MULTILINE,
)


def has_heading(text: str, title: str) -> bool:
    return re.search(rf"^#{{2,6}}\s+{re.escape(title)}\s*$", text, re.MULTILINE) is not None


def mbti_items(mbti: str) -> list[str]:
    """Short names of the public items of an interface file (methods by their own name)."""
    return sorted({match.group(1).split("::")[-1] for match in MBTI_ITEM_RE.finditer(mbti)})


def tooling_standard_errors(
    package: str, api: str, tutorial: str, design: str, mbti: str
) -> list[str]:
    errors: list[str] = []
    errors.extend(
        f"doc/manual/api/{package}.md: missing section {title}"
        for title in TOOLING_API_HEADINGS
        if not has_heading(api, title)
    )
    headings = " ".join(heading for _, heading in HEADING_RE.findall(api))
    undocumented = [item for item in mbti_items(mbti) if item not in headings]
    if undocumented:
        errors.append(
            f"doc/manual/api/{package}.md: public items without a heading: {', '.join(undocumented[:8])}"
        )
    if re.search(r"\|\s*I want to\s*\|\s*Use\s*\|", tutorial) is None:
        errors.append(f"doc/manual/tutorial/{package}.md: missing the | I want to | Use | table")
    errors.extend(
        f"doc/manual/tutorial/{package}.md: missing section {title}"
        for title in TOOLING_TUTORIAL_HEADINGS
        if not has_heading(tutorial, title)
    )
    if (
        mbti_items(mbti)
        and package not in TOOLING_NO_COMPILED_EXAMPLE
        and re.search(r"^```moonbit\s*$", tutorial, re.MULTILINE) is None
    ):
        errors.append(f"doc/manual/tutorial/{package}.md: no example that compiles")
    errors.extend(
        f"doc/manual/design/{package}.md: missing section {title}"
        for title in TOOLING_DESIGN_HEADINGS
        if not has_heading(design, title)
    )
    return errors


def check_tooling_standard() -> list[str]:
    errors: list[str] = []
    source_root = REPO_ROOT / "tooling" / "src"
    for package in sorted(package_paths()):
        directory = source_root / package
        if not (directory / "moon.pkg").exists():
            continue
        pages = {chapter: chapter_page(chapter, package) for chapter in ("api", "tutorial", "design")}
        if not all(path.exists() for path in pages.values()):
            continue  # check_package_doc_coverage reports the missing page
        errors.extend(
            tooling_standard_errors(
                package,
                pages["api"].read_text(encoding="utf-8"),
                pages["tutorial"].read_text(encoding="utf-8"),
                pages["design"].read_text(encoding="utf-8"),
                (directory / "pkg.generated.mbti").read_text(encoding="utf-8"),
            )
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
        *check_tooling_standard(),
        *check_gda_claims(),
        *check_evidence_paths(),
        *check_conformance_checklist(),
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
