#!/usr/bin/env python3
"""Builds public/licenses.html from the app's Acknowledgements.txt.

Each section in the source starts with "### Name version"; the next line is a URL or a
license name, and the rest is the license text. The page chrome (head, header, footer)
is taken from public/privacy.html so every page stays alike.

Run: python3 site/build_licenses.py
"""
import html
import re
from pathlib import Path

SITE = Path(__file__).resolve().parent
SOURCE = SITE.parent / "app" / "DeckTerm" / "Acknowledgements.txt"
TEMPLATE = SITE / "public" / "privacy.html"
OUT = SITE / "public" / "licenses.html"

TITLE = "Open-source licenses | DeckTerm"
OG_TITLE = "DeckTerm open-source licenses"
DESC = "The open-source software and fonts DeckTerm is built on, with their full license texts."
URL = "https://deckterm.cobanov.dev/licenses"


def parse(text):
    """Returns (intro, [(name, source, body)])."""
    intro, *chunks = re.split(r"^### ", text, flags=re.M)
    sections = []
    for chunk in chunks:
        name, source, *rest = chunk.split("\n") + [""]
        sections.append((name.strip(), source.strip(), "\n".join(rest).strip("\n")))
    return intro.strip(), sections


def slug(name, used):
    base = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "section"
    s, n = base, 2
    while s in used:
        s, n = f"{base}-{n}", n + 1
    used.add(s)
    return s


def render(intro, sections):
    used, toc, parts = set(), [], []
    for name, source, body in sections:
        sid = slug(name, used)
        e = html.escape(name)
        toc.append(f'      <li><a href="#{sid}">{e}</a></li>')
        if source.startswith(("http://", "https://")):
            src = f'<a href="{html.escape(source, quote=True)}">{html.escape(source)}</a>'
        else:
            src = html.escape(source)
        parts.append(
            f'    <section class="license" aria-labelledby="{sid}">\n'
            f'      <h2 id="{sid}">{e}</h2>\n'
            f'      <p>{src}</p>\n'
            f'      <pre>{html.escape(body)}</pre>\n'
            f'    </section>'
        )
    return (
        '  <article class="prose">\n'
        '    <h1>Open-source licenses</h1>\n'
        f'    <p class="intro">{html.escape(intro)}</p>\n'
        '    <h2 id="contents">Contents</h2>\n'
        '    <ul class="toc">\n' + "\n".join(toc) + '\n    </ul>\n'
        + "\n".join(parts) + '\n'
        '  </article>\n'
    )


def sub_once(pattern, repl, s):
    s, n = re.subn(pattern, repl, s, count=1, flags=re.S)
    assert n == 1, f"template is missing {pattern!r}"
    return s


def page(article):
    s = TEMPLATE.read_text(encoding="utf-8")
    s = sub_once(r"<title>.*?</title>", f"<title>{TITLE}</title>", s)
    s = sub_once(r'(<meta name="description" content=")[^"]*', rf"\g<1>{DESC}", s)
    s = sub_once(r'(<meta property="og:description" content=")[^"]*', rf"\g<1>{DESC}", s)
    s = sub_once(r'(<meta property="og:title" content=")[^"]*', rf"\g<1>{OG_TITLE}", s)
    s = sub_once(r'(<link rel="canonical" href=")[^"]*', rf"\g<1>{URL}", s)
    s = sub_once(r'(<meta property="og:url" content=")[^"]*', rf"\g<1>{URL}", s)
    s = s.replace(' aria-current="page"', "")
    return sub_once(r'  <article class="prose">.*</article>\n', lambda _: article, s)


def main():
    text = SOURCE.read_text(encoding="utf-8")
    intro, sections = parse(text)
    out = page(render(intro, sections))
    # Self-check: one section per "### " heading, every name present, no raw markup leaked.
    assert len(sections) == len(re.findall(r"^### ", text, flags=re.M)) > 0
    assert all(html.escape(n) in out for n, _, _ in sections)
    assert out.count("<pre>") == len(sections)
    OUT.write_text(out, encoding="utf-8")
    print(f"wrote {OUT} ({len(sections)} sections, {len(out) // 1024} KB)")


if __name__ == "__main__":
    main()
