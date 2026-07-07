#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

START = "<!-- extension-matrix:start -->"
END = "<!-- extension-matrix:end -->"


def render(catalog: dict) -> str:
    rows = [
        "| Extension | Package | Available | Preload required | Created by default | Notes |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for item in catalog["extensions"]:
        preload = ", ".join(f"`{name}`" for name in item["shared_preload_libraries"]) or "No"
        created = "Yes" if item["enabled_by_default"] else "No"
        available = "Yes" if item.get("bundled", True) else "No (catalog only)"
        rows.append(
            "| `{name}` | `{package}` | {available} | {preload} | {created} | {notes} |".format(
                name=item["name"],
                package=item["package"],
                available=available,
                preload=preload,
                created=created,
                notes=item["notes"],
            )
        )
    return "\n".join(
        [
            START,
            "",
            "This section is generated from `extensions.json`.",
            "",
            *rows,
            "",
            END,
        ]
    )


def update(path: Path, generated: str) -> str:
    text = path.read_text()
    if START not in text or END not in text:
        raise SystemExit(f"{path} is missing extension matrix markers")
    before, rest = text.split(START, 1)
    _, after = rest.split(END, 1)
    return before + generated + after


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--catalog", default="extensions.json")
    parser.add_argument("--readme", default="README.md")
    args = parser.parse_args()

    catalog = json.loads(Path(args.catalog).read_text())
    generated = render(catalog)
    readme = Path(args.readme)
    next_text = update(readme, generated)

    if args.check:
        if readme.read_text() != next_text:
            raise SystemExit("README extension matrix is stale; run scripts/generate-extension-docs.py")
        return

    readme.write_text(next_text)


if __name__ == "__main__":
    main()
