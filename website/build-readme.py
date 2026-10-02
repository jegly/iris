#!/usr/bin/env python3
"""Generate ../README.md from website/index.html (single source of truth) + website/readme-extra.md.

GitHub READMEs can't use the page's CSS, fonts or scripts, so this renders the Markdown equivalent:
the hero as readme-banner.svg (make-banner.py), downloads as a table, every change group as a ```diff block
(GitHub colours + green and - red, like the page), and the trade-offs as a list. readme-extra.md holds the
GitHub-only sections (verify, build, layout, credits) and is appended unchanged.
Usage: python3 website/build-readme.py   (from the iris folder or anywhere)
"""
import html
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
page = (HERE / "index.html").read_text()
extra = (HERE / "readme-extra.md").read_text()


def text(fragment: str) -> str:
    """Tag-free, entity-decoded, whitespace-collapsed text."""
    t = re.sub(r"<[^>]+>", "", fragment)
    return re.sub(r"\s+", " ", html.unescape(t)).strip()


def md_inline(fragment: str) -> str:
    """Keep <code> as backticks, drop other tags."""
    fragment = re.sub(r"<code>(.*?)</code>", lambda m: "`" + html.unescape(m.group(1)) + "`", fragment, flags=re.S)
    return text(fragment)


out = []
out.append('<p align="center"><img src="website/iris-banner.png" alt="Iris" width="100%"></p>\n')

lede = re.search(r'<p class="lede">(.*?)</p>', page, re.S)
if lede:
    out.append(text(lede.group(1)) + "\n")

# Downloads
out.append("## Download\n")
out.append("| Platform | Package | Install | Notes |\n|---|---|---|---|")
for card in re.finditer(r'<article class="dl"([^>]*)>(.*?)</article>', page, re.S):
    if re.search(r"\bhidden\b", card.group(1)):  # not published yet (hidden on the site too)
        continue
    c = card.group(2)
    name = text(re.search(r"<h3>(.*?)</h3>", c, re.S).group(1))
    tag = text(re.search(r'<span class="tag">(.*?)</span>', c, re.S).group(1))
    meta = md_inline(re.search(r'<p class="meta">(.*?)</p>', c, re.S).group(1))
    cmd = html.unescape(re.search(r"<pre class=\"cmd\"><code>(.*?)</code>", c, re.S).group(1)).strip()
    link = re.search(r'<a class="btn[^"]*" href="([^"]+)">(.*?)</a>', c, re.S)
    out.append(f"| **{name}** | [{tag}]({link.group(1)}) | `{cmd}` | {meta} |")
out.append("")

# What Iris technically changes
sec = re.search(r'<section id="changes".*?</section>', page, re.S).group(0)
title = text(re.search(r"<h2[^>]*>(.*?)</h2>", sec, re.S).group(1))
intro = text(re.search(r'<div class="section-head">.*?<p>(.*?)</p>', sec, re.S).group(1))
out.append(f"## {title}\n\n{intro}\n")
for hunk in re.finditer(r'<div class="hunk">\s*<h3>(.*?)</h3>\s*<ul>(.*?)</ul>', sec, re.S):
    out.append(f"### {text(hunk.group(1))}\n\n```diff")
    for li in re.finditer(r'<li class="(add|rm)"[^>]*>.*?</span><span>(.*?)</span></li>', hunk.group(2), re.S):
        body = li.group(2)
        # platform tags -> "[Ubuntu]" suffix; explanations stay in parentheses
        body = re.sub(r'<span class="plat">(.*?)</span>', r"[\1]", body)
        sign = "+" if li.group(1) == "add" else "-"
        out.append(f"{sign} {text(body)}")
    out.append("```\n")

# Trade-offs
t = re.search(r'<section id="tradeoffs".*?</section>', page, re.S).group(0)
out.append(f"## {text(re.search(r'<h2[^>]*>(.*?)</h2>', t, re.S).group(1))}\n")
head = re.search(r'<div class="section-head">.*?<p>(.*?)</p>', t, re.S)
if head:
    out.append(text(head.group(1)) + "\n")
for dt, dd in re.findall(r"<dt>(.*?)</dt><dd>(.*?)</dd>", t, re.S):
    out.append(f"- **{text(dt)}.** {md_inline(dd)}")
out.append("")

out.append(extra.rstrip() + "\n")
readme = "\n".join(out)
(HERE.parent / "README.md").write_text(readme)
print(f"README.md written: {len(readme.splitlines())} lines")
