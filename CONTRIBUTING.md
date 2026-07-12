# Contribution Guidelines

This guide tracks the current repository workflow and follows the current
documentation baseline: **`0.5.0`**.

## To Contributors

We welcome contributors interested in arbitrary-precision numerics, floating-point
semantics, ball arithmetic, and MoonBit library design. This repository is still
early-stage, so contributions that improve correctness, documentation clarity,
trait design, and test coverage are especially valuable.

## Table of Contents

1. [Code Style](#1-code-style)
2. [Naming Conventions](#2-naming-conventions)
3. [Comments](#3-comments)
4. [File Standards](#4-file-standards)
5. [Commit Guidelines](#5-commit-guidelines)
6. [Release Checklist](#6-release-checklist)
7. [Code Review](#7-code-review)

## 1. Code Style

- The project follows the formatting style enforced by the MoonBit toolchain:

  ```bash
  moon fmt
  ```

- Run `moon fmt` before committing to keep the repository consistent.
- Prefer `using`-imported names over repeated fully-qualified package references when the imported names are used repeatedly in a file.
- Keep public APIs explicit about numeric semantics. If a function normalizes, rounds, or widens an enclosure, document that behavior.
- Prefer small helper functions for normalization and rounding logic over repeating low-level integer manipulation inline.

## 2. Naming Conventions

### 2.1 Bindings

- Use **lowercase letters with underscores** for bindings.
- Names should reflect the mathematical role of the value when possible, for example `coefficient`, `exponent10`, `rounding_mode`.

### 2.2 Functions

- Use **lowercase letters with underscores** for package-level helper functions.
- Keep public method names aligned across `bin_float`, `decimal`, and `ball_float` when the semantics are intended to match.

### 2.3 Structs and Traits

- Use **PascalCase** for structs and traits.
- Trait names should describe a stable capability boundary, not a specific implementation detail.

### 2.4 Files and Packages

- Use **lowercase letters with underscores** for file names and package names.
- Keep files grouped by clear responsibility:
  - trait and shared semantic definitions in `def`
  - shared implementation helpers in `internal`
  - concrete numeric representations in their own packages

## 3. Comments

- Keep comments concise, accurate, and current.
- Explain non-obvious numeric invariants, normalization rules, or enclosure behavior.
- Avoid redundant comments that restate obvious syntax.

## 4. File Standards

### 4.1 Folder Naming

- Use **lowercase** folder names.
- Folder names should describe the package responsibility directly.

### 4.2 File Organization

- Each file should focus on a single coherent concern.
- Avoid vague file names such as `utils.mbt`; prefer names that reflect the domain behavior.
- Public APIs should remain easy to discover from the package layout.

## 5. Commit Guidelines

### 5.1 Commit Messages

- Run the local verification commands before committing:

  ```bash
  just fmt
  just pr
  ```

- Commit messages should be in **English**, concise, and use Conventional Commits prefixes such as `feat:`, `fix:`, `refactor:`, `docs:`, or `test:`.

### 5.2 Commit Scope

- Keep commits small and focused.
- Avoid combining unrelated documentation, trait, and numeric behavior changes in one commit unless they are tightly coupled.

## 6. Release Checklist

- Before publishing to Mooncakes, make sure `moon.mod` has already been bumped to the intended release version.
- Update `README.md` and localized docs if the package overview or release notes no longer match the implementation.
- Move superseded release notes to `CHANGELOG.md`; keep README files focused on the current baseline.
- Run the quick `just pr` gate for ordinary changes and the complete `just ci`
  gate before publishing.
- The GitHub Actions publish workflow reads the release version directly from `moon.mod`.
- If Mooncakes reports a duplicate version, bump the version before retrying.

## 7. Code Review

- All code submissions should undergo review.
- Reviews should focus first on numeric correctness, semantic clarity, and missing tests, then on style and cleanup.
- Changes that alter rounding, normalization, conversion, or enclosure behavior should include or update tests in `src/consistency`.
