#!/usr/bin/env python3
"""Renders PRIVACY.md into docs/privacy.html.

The policy is written once, in the repository root, because the App Store needs
a URL and anybody reading the source deserves the same text. Keeping two copies
by hand is how they end up disagreeing, and a privacy policy that disagrees with
itself is worse than not having one.

Run after editing PRIVACY.md:  python3 docs/build_privacy.py
"""

import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "PRIVACY.md"
TARGET = ROOT / "docs" / "privacy.html"

TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SplitFree privacy policy</title>
<meta name="description" content="What SplitFree stores, what it sends, and what you can do about it.">
<link rel="stylesheet" href="_style.css">
</head>
<body>
<main>
  <header><span class="mark">S</span><a href="./">SplitFree</a></header>
{body}
  <footer>
    <p><a href="./">About SplitFree</a> &middot;
       <a href="https://github.com/devesh-aggarwal/splitfree">Source</a> &middot;
       <a href="https://github.com/devesh-aggarwal/splitfree/issues">Support</a></p>
    <p class="meta">This page is generated from PRIVACY.md in the repository.</p>
  </footer>
</main>
</body>
</html>
"""


def inline(text: str) -> str:
    """Bold, code, and links. Escaped first, so the Markdown cannot inject HTML."""
    out = html.escape(text)
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"`(.+?)`", r"<code>\1</code>", out)
    out = re.sub(r"\[(.+?)\]\((.+?)\)", r'<a href="\2">\1</a>', out)
    return out


def render(markdown: str) -> str:
    lines = markdown.splitlines()
    parts: list[str] = []
    in_list = False
    paragraph: list[str] = []

    def flush_paragraph() -> None:
        if paragraph:
            parts.append(f"  <p>{inline(' '.join(paragraph))}</p>")
            paragraph.clear()

    def close_list() -> None:
        nonlocal in_list
        if in_list:
            parts.append("  </ul>")
            in_list = False

    for line in lines:
        stripped = line.strip()

        if not stripped:
            flush_paragraph()
            close_list()
            continue

        heading = re.match(r"^(#{1,3})\s+(.*)$", stripped)
        if heading:
            flush_paragraph()
            close_list()
            level = len(heading.group(1))
            parts.append(f"  <h{level}>{inline(heading.group(2))}</h{level}>")
            continue

        bullet = re.match(r"^[-*]\s+(.*)$", stripped)
        if bullet:
            flush_paragraph()
            if not in_list:
                parts.append("  <ul>")
                in_list = True
            parts.append(f"    <li>{inline(bullet.group(1))}</li>")
            continue

        numbered = re.match(r"^\d+\.\s+(.*)$", stripped)
        if numbered:
            flush_paragraph()
            if not in_list:
                parts.append("  <ul>")
                in_list = True
            parts.append(f"    <li>{inline(numbered.group(1))}</li>")
            continue

        paragraph.append(stripped)

    flush_paragraph()
    close_list()
    return "\n".join(parts)


def main() -> None:
    body = render(SOURCE.read_text())
    TARGET.write_text(TEMPLATE.format(body=body))
    print(f"wrote {TARGET.relative_to(ROOT)} ({len(body.splitlines())} lines)")


if __name__ == "__main__":
    main()
