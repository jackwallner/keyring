#!/usr/bin/env python3
"""Extract the club and upgrade literals from the Swift catalogs into JSON for
the Android parity test (android/app/src/test/resources/explore_literals_swift.json).

`Clubs.kt` and `Upgrades.kt` are mechanical conversions of
`Shared/Catalog/Clubs.swift` and `Shared/Catalog/Upgrades.swift`;
`ExploreParityTest` fails until every Kotlin list matches these literals.
Run after editing either Swift file, then port the change.
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLUBS = ROOT / "Shared/Catalog/Clubs.swift"
UPGRADES = ROOT / "Shared/Catalog/Upgrades.swift"
OUT = ROOT / "android/app/src/test/resources/explore_literals_swift.json"

STRING = r'"((?:[^"\\]|\\.)*)"'
CLUB = re.compile(rf'(?<![\w.])Club\({STRING}, {STRING}, \.(\w+), {STRING}\)|\.subreddit\({STRING}(?:, {STRING})?\)')


def clubs(text: str):
    found = []
    for m in CLUB.finditer(text):
        if m.group(1) is not None:
            found.append({"name": m.group(1), "detail": m.group(2), "kind": m.group(3), "url": m.group(4)})
        else:
            name, detail = m.group(5), m.group(6) or ""
            found.append({"name": f"r/{name}", "detail": detail or "Owners trading tips, photos and fixes",
                          "kind": "subreddit", "url": f"https://www.reddit.com/r/{name}/"})
    return found


def dictionary(text: str, name: str):
    start = text.index(f"static let {name}: [String: [Club]] = [")
    body = text[start:text.index("\n    ]\n", start)]
    entries = {}
    for m in re.finditer(rf'\n        {STRING}: \[(.*?)\],?(?=\n        "|\s*\Z)', body + "\n", re.S):
        entries[m.group(1)] = clubs(m.group(2))
    return entries


def by_kind(text: str):
    start = text.index("static func byKind")
    body = text[start:]
    result = {}
    parts = re.split(r"\n\s*case ([^:]+):", body)
    for kinds, block in zip(parts[1::2], parts[2::2]):
        for kind in kinds.split(","):
            result[kind.strip().lstrip(".")] = clubs(block)
    return result


def upgrades(text: str):
    lists = {}
    for m in re.finditer(r"static let (\w+)(?:: \[Upgrade\])? = (\[.*?\n    \]|Upgrade\(.*?\)\n)", text, re.S):
        items = []
        for u in re.finditer(rf'Upgrade\(title: {STRING}, why: {STRING}, symbol: {STRING}, category: \.(\w+), query: {STRING}\)', m.group(2)):
            items.append({"title": u.group(1), "why": u.group(2), "symbol": u.group(3), "category": u.group(4), "query": u.group(5)})
        lists[m.group(1)] = items
    return lists


def main():
    club_text = CLUBS.read_text()
    data = {
        "models": dictionary(club_text, "models"),
        "makes": dictionary(club_text, "makes"),
        "byKind": by_kind(club_text),
        "upgrades": upgrades(UPGRADES.read_text()),
    }
    OUT.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n")
    counts = {k: (len(v) if isinstance(v, dict) else v) for k, v in data.items()}
    print(f"wrote {OUT.relative_to(ROOT)}: {counts}")


if __name__ == "__main__":
    main()
