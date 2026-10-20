#!/usr/bin/env python3
"""Extract every CatalogItem literal from the Swift catalog into JSON for the
Android parity test (android/app/src/test/resources/catalog_literals_swift.json).

The Swift source is the spec. The Kotlin catalog is a mechanical conversion of
it; CatalogParityTest checks every computed Kotlin item against these literals.
Run after editing Shared/Catalog/MaintenanceCatalog.swift.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Shared/Catalog/MaintenanceCatalog.swift"
OUT = ROOT / "android/app/src/test/resources/catalog_literals_swift.json"


def calls(text: str, opener: str):
    """Yield the argument text of every balanced `opener(...)` call, skipping strings."""
    start = 0
    while (index := text.find(opener, start)) != -1:
        i = index + len(opener)
        depth, in_string, escaped = 1, False, False
        while depth:
            ch = text[i]
            if in_string:
                if escaped:
                    escaped = False
                elif ch == "\\":
                    escaped = True
                elif ch == '"':
                    in_string = False
            elif ch == '"':
                in_string = True
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            i += 1
        yield text[index + len(opener):i - 1]
        start = i


def split_args(args: str):
    parts, depth, in_string, escaped, current = [], 0, False, False, ""
    for ch in args:
        if in_string:
            current += ch
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(current.strip())
            current = ""
        else:
            current += ch
    if current.strip():
        parts.append(current.strip())
    return parts


def literal(value: str):
    value = value.strip()
    if value.startswith('"') and value.endswith('"'):
        return json.loads(value)
    if value in ("true", "false"):
        return value == "true"
    if re.fullmatch(r"-?[\d_]+(\.\d+)?", value):
        return float(value.replace("_", ""))
    if re.fullmatch(r"\.\w+", value):
        return value[1:]
    return None  # not a literal (a variable such as `core` or `name`)


def main() -> int:
    text = SOURCE.read_text()
    items = []
    for args in calls(text, "CatalogItem("):
        fields, unresolved = {}, []
        for part in split_args(args):
            name, _, value = part.partition(":")
            name = name.strip()
            if name == "gear":
                fields["gear"] = [
                    {"title": json.loads(t), "query": json.loads(q)}
                    for t, q in re.findall(r'\.init\(title:\s*("(?:[^"\\]|\\.)*"),\s*query:\s*("(?:[^"\\]|\\.)*")\)', value)
                ]
                continue
            parsed = literal(value)
            if parsed is None:
                unresolved.append(name)
            else:
                fields[name] = parsed
        fields["unresolved"] = unresolved
        items.append(fields)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"source": str(SOURCE.relative_to(ROOT)), "items": items}, indent=1, ensure_ascii=False) + "\n")
    print(f"{len(items)} CatalogItem literals -> {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
