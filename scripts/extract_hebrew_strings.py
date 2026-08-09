#!/usr/bin/env python3
"""Finds every hardcoded Hebrew string literal in lib/**/*.dart and emits:
  - build/hebrew_strings_report.json  (file -> [{key, text, line}])
  - build/app_he.arb                  (draft ARB skeleton, key -> Hebrew text)

This is the extraction half of the multi-language plan's Stage 5: it does NOT
rewrite any source file. Its output is the input to (a) an AI bulk-translation
pass into app_en/ar/fr/es.arb, and (b) a later, careful wave-by-wave codemod
that replaces each literal with AppLocalizations.of(context)!.<key>.

Key scheme: <file_stem>_<8-char content hash> — stable across file reordering
(same string always gets the same key), unique across the whole app without
needing an AST parse (a plain string constant IS its own identity here).

ponytail: regex-based, not an AST parse — good enough to find Dart string
literals containing Hebrew text; skips comments and import/package strings.
Upgrade path: swap in `dart analyze`-based AST extraction if regex false
positives/negatives become a real problem during the translation waves.
"""
import json
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
OUT_DIR = ROOT / "build"

HEBREW_RE = re.compile(r"[֐-׿]")
# Single- or double-quoted Dart string literal (not triple-quoted, not raw
# with interpolation braces excluded from the "is it translatable" check —
# interpolated strings ARE captured; the codemod stage handles $var specially).
STRING_RE = re.compile(
    r"""(?P<q>['"])(?P<body>(?:\\.|(?!(?P=q)).)*)(?P=q)""",
    re.DOTALL,
)

SKIP_LINE_PREFIXES = ("import ", "export ", "part ", "part of ")


def strip_comments(line: str) -> str:
    # crude but sufficient: drop a trailing // comment that isn't inside a string.
    # (good enough for a reporting tool; not used for any source rewrite)
    in_str = None
    for i, ch in enumerate(line):
        if in_str:
            if ch == "\\":
                continue
            if ch == in_str:
                in_str = None
        elif ch in ("'", '"'):
            in_str = ch
        elif ch == "/" and line[i : i + 2] == "//":
            return line[:i]
    return line


def extract_file(path: Path):
    results = []
    text = path.read_text(encoding="utf-8", errors="replace")
    for lineno, raw_line in enumerate(text.splitlines(), start=1):
        line = strip_comments(raw_line)
        if not HEBREW_RE.search(line):
            continue
        stripped = line.strip()
        if stripped.startswith(SKIP_LINE_PREFIXES):
            continue
        for m in STRING_RE.finditer(line):
            body = m.group("body")
            if not HEBREW_RE.search(body):
                continue
            results.append({"text": body, "line": lineno})
    return results


def make_key(file_stem: str, text: str, seen: dict) -> str:
    h = hashlib.sha1(text.encode("utf-8")).hexdigest()[:8]
    key = f"{file_stem}_{h}"
    # collision guard (two different strings hashing to the same 8 chars in
    # the same file — vanishingly unlikely, but don't silently drop one)
    n = 1
    base_key = key
    while key in seen and seen[key] != text:
        n += 1
        key = f"{base_key}_{n}"
    seen[key] = text
    return key


def main():
    dart_files = sorted(LIB.rglob("*.dart"))
    report = {}
    arb = {"@@locale": "he"}
    seen_keys = {}
    total = 0

    for f in dart_files:
        hits = extract_file(f)
        if not hits:
            continue
        rel = f.relative_to(ROOT).as_posix()
        stem = f.stem
        entries = []
        for hit in hits:
            key = make_key(stem, hit["text"], seen_keys)
            entries.append({"key": key, "text": hit["text"], "line": hit["line"]})
            arb.setdefault(key, hit["text"])
        report[rel] = entries
        total += len(entries)

    OUT_DIR.mkdir(exist_ok=True)
    (OUT_DIR / "hebrew_strings_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (OUT_DIR / "app_he.arb").write_text(
        json.dumps(arb, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    files_with_hebrew = len(report)
    print(f"Scanned {len(dart_files)} Dart files.")
    print(f"Files containing hardcoded Hebrew strings: {files_with_hebrew}")
    print(f"Total extracted string occurrences: {total}")
    print(f"Unique keys (after dedup by content): {len(seen_keys)}")
    print(f"Wrote: {OUT_DIR / 'hebrew_strings_report.json'}")
    print(f"Wrote: {OUT_DIR / 'app_he.arb'}")

    # Top 15 files by string count — this is the "which files first" signal
    # for wave-ordering the actual codemod (Section 4's 4-wave plan).
    top = sorted(report.items(), key=lambda kv: -len(kv[1]))[:15]
    print("\nTop files by Hebrew-string count:")
    for rel, entries in top:
        print(f"  {len(entries):4d}  {rel}")


if __name__ == "__main__":
    sys.exit(main())
