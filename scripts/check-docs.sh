#!/bin/bash
# Checks that the documents still point at things that exist. Three gates:
#
#   1. No line-numbered code citation survives anywhere in Markdown. Line
#      numbers move on every commit that changes a file's length, and nothing
#      catches them when they stop being true.
#   2. Every symbol citation — `symbolName` (`File.swift`) — names something
#      that file still declares.
#   3. Every quoted fragment on a `Spec:` line in the checks document still
#      appears verbatim in the document that owns the rule. A reworded
#      requirement is exactly when a check needs re-reading, so the anchor has
#      to break loudly.
#
#      An anchor resolves against PRODUCT_SPEC.md unless it names another
#      document, which is how a delivery check anchors to the paste engine:
#
#          Spec: Shortcuts and job lifecycle — "at least one second long"
#          Spec: PASTE_ENGINE.md, Regression baseline — "Raycast's command bar"
#
#      Straight and curly quotes both count. Gaf's prose uses curly ones, so a
#      converter copying a fragment verbatim will produce them.
#
# Gate 3 proves a fragment exists. It cannot prove it is the *right* rule — an
# anchor can resolve to a plausible neighbour. That part is read by a human.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

/usr/bin/python3 - "$REPO_ROOT" <<'PY'
import pathlib
import re
import sys
import unicodedata

root = pathlib.Path(sys.argv[1])
failures = []

markdown = sorted(
    p for p in root.rglob("*.md")
    # CLAUDE.md is a symlink to AGENTS.md; reporting both doubles every finding.
    if ".build" not in p.parts and "node_modules" not in p.parts and not p.is_symlink()
)
sources = {p.name: p for d in ("Scriber", "ScriberCore", "ScriberCoreTests")
           for p in (root / d).glob("*.swift")}

# Gate 1 — no line-numbered citations.
line_citation = re.compile(r"`((?:[A-Za-z]+/)*[A-Za-z]+\.swift):(\d+)`")
for doc in markdown:
    for number, line in enumerate(doc.read_text().splitlines(), 1):
        for match in line_citation.finditer(line):
            failures.append(
                f"{doc.relative_to(root)}:{number} cites a line number: {match.group(0)} "
                f"— cite the enclosing declaration instead"
            )
        # The bare continuation form, which inherits its file from the citation
        # before it and so cannot be checked at all.
        for match in re.finditer(r"`:\d+`", line):
            failures.append(
                f"{doc.relative_to(root)}:{number} cites a bare line number: {match.group(0)}"
            )

# Gate 2 — symbol citations resolve.
symbol_citation = re.compile(r"`([A-Za-z_][A-Za-z0-9_.]*)\(?\)?`\s*\(`([A-Za-z]+\.swift)`\)")
for doc in markdown:
    for number, line in enumerate(doc.read_text().splitlines(), 1):
        for symbol, filename in symbol_citation.findall(line):
            source = sources.get(filename)
            if source is None:
                failures.append(
                    f"{doc.relative_to(root)}:{number} cites {filename}, which does not exist"
                )
                continue
            # Whole word, so a citation to `foo` is not satisfied by `fooBar`.
            # This is a rot detector and no more: it does not check that the
            # name is *declared* there, so a symbol surviving only in a comment
            # still passes. Tightening it to a declaration would reject honest
            # citations of enum cases and computed properties.
            bare = symbol.split(".")[-1]
            if not re.search(rf"\b{re.escape(bare)}\b", source.read_text()):
                failures.append(
                    f"{doc.relative_to(root)}:{number} cites `{symbol}` in {filename}, "
                    f"which no longer contains it"
                )

# Gate 3 — spec fragments still appear in the spec.
def normalise(text):
    text = unicodedata.normalize("NFKC", text)
    for fancy, plain in (("“", '"'), ("”", '"'),
                         ("‘", "'"), ("’", "'"),
                         ("—", "-"), ("–", "-")):
        text = text.replace(fancy, plain)
    return " ".join(text.split())

checks_path = root / "docs" / "MANUAL_CHECKS.md"
owners = {}


def owning_document(name):
    if name not in owners:
        path = root / "docs" / name
        owners[name] = normalise(path.read_text()) if path.exists() else None
    return owners[name]


if checks_path.exists():
    # Both quote styles: the prose these fragments are copied from uses curly.
    fragment = re.compile(r'["“]([^"“”]{4,})["”]')
    names = re.compile(r"\b([A-Z_]+\.md)\b")
    for number, line in enumerate(checks_path.read_text().splitlines(), 1):
        stripped = line.strip()
        if not stripped.startswith("Spec:"):
            continue
        quoted = fragment.findall(stripped)
        if not quoted:
            failures.append(
                f"docs/MANUAL_CHECKS.md:{number} has a Spec: line with no quoted fragment"
            )
            continue
        named = names.findall(stripped)
        document = named[0] if named else "PRODUCT_SPEC.md"
        owner = owning_document(document)
        if owner is None:
            failures.append(
                f"docs/MANUAL_CHECKS.md:{number} anchors to {document}, which does not exist"
            )
            continue
        for piece in quoted:
            if normalise(piece) not in owner:
                failures.append(
                    f'docs/MANUAL_CHECKS.md:{number} anchors to "{piece}", '
                    f"which {document} no longer contains"
                )

if failures:
    for failure in failures:
        print(f"FAILED: {failure}", file=sys.stderr)
    print(f"\n{len(failures)} broken reference(s)", file=sys.stderr)
    sys.exit(1)

print("Documents reference nothing that has moved or gone.")
PY
