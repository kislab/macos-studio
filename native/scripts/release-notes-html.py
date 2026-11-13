#!/usr/bin/env python3
"""Turns a release notes Markdown file (docs/release-X.md) into the small HTML Sparkle shows in its update window.
Supports headings, paragraphs, "- " lists, **bold**, `code` and [links](https://...). The DMG download line is left out."""
import html, re, sys

def inline(text):
    text = html.escape(text, quote=True)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    return re.sub(r"\[([^\]]+)\]\((https://[^)\s]+)\)", r'<a href="\2">\1</a>', text)

out, items, para = [], [], []
def flush():
    if items: out.append("<ul>" + "".join(f"<li>{i}</li>" for i in items) + "</ul>"); items.clear()
    if para: out.append("<p>" + " ".join(para) + "</p>"); para.clear()
for line in open(sys.argv[1], encoding="utf-8").read().splitlines():
    line = line.strip()
    if "/releases/download/" in line: continue
    if not line: flush(); continue
    if line.startswith("#"):
        flush(); out.append("<h3>" + inline(line.lstrip("#").strip()) + "</h3>")
    elif line.startswith("- "):
        if para: flush()
        items.append(inline(line[2:]))
    else:
        if items: flush()
        para.append(inline(line))
flush()
result = "\n".join(out)
if "]]>" in result: sys.exit("release notes must not contain ]]>")
print(result)
