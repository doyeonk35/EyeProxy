#!/usr/bin/env python3
"""릴리스 노트 마크다운을 Sparkle 업데이트 창에 넣을 HTML로 바꾼다.

사용법: python3 scripts/notes-html.py <notes.md> <version>   (HTML을 stdout으로)

지원: `#`~`###` 제목, `- ` 목록(두 칸 들여쓰면 한 단계 아래), 빈 줄로 나눈 문단,
**굵게**, `코드`, [글](주소). 그 밖의 마크다운은 글자 그대로 나온다.
ponytail: 릴리스 노트에 쓰는 문법만 다룬다 — 표·코드 블록이 필요해지면 python-markdown으로 바꾼다.
"""
import html
import re
import sys
from datetime import date

STYLE = """
:root { color-scheme: light dark; }
body { font: 13px -apple-system, sans-serif; margin: 12px 16px; line-height: 1.45; }
.release { font-size: 26px; font-weight: 700; margin: 4px 0 6px; padding-bottom: 8px; border-bottom: 1px solid #8884; }
.release .v { color: #2f7cf6; }
h2 { font-size: 17px; margin: 18px 0 6px; padding-bottom: 4px; border-bottom: 1px solid #8884; }
h3 { font-size: 14px; margin: 14px 0 4px; }
ul { margin: 4px 0; padding-left: 20px; }
li { margin: 3px 0; }
code { font: 12px ui-monospace, Menlo, monospace; background: #8882; padding: 0 3px; border-radius: 3px; }
a { color: #2f7cf6; }
"""


def inline(text: str) -> str:
    out = html.escape(text, quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", out)
    out = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', out)
    return out


def convert(markdown: str, version: str) -> str:
    body = [f'<div class="release">Release <span class="v">{html.escape(version)}</span> - {date.today().isoformat()}</div>']
    depth = 0          # 열려 있는 <ul> 수
    paragraph = []

    def flush_paragraph():
        if paragraph:
            body.append(f"<p>{inline(' '.join(paragraph))}</p>")
            paragraph.clear()

    def close_lists(to: int = 0):
        nonlocal depth
        while depth > to:
            body.append("</li></ul>")
            depth -= 1

    for raw in markdown.splitlines():
        line = raw.rstrip()
        bullet = re.match(r"^( *)[-*] (.*)$", line)
        heading = re.match(r"^(#{1,3}) (.*)$", line)
        if bullet:
            flush_paragraph()
            level = len(bullet.group(1)) // 2 + 1
            if level > depth:
                while depth < level:
                    body.append("<ul><li>")
                    depth += 1
            else:
                close_lists(level)
                body.append("</li><li>")
            body.append(inline(bullet.group(2)))
        elif heading:
            flush_paragraph()
            close_lists()
            # 문서 제목(#)과 버전이 든 제목은 버전 줄이 대신하므로 건너뛰고, ##는 h2, ###는 h3
            if len(heading.group(1)) > 1 and version not in heading.group(2):
                tag = f"h{len(heading.group(1))}"
                body.append(f"<{tag}>{inline(heading.group(2))}</{tag}>")
        elif line.strip() == "":
            flush_paragraph()
            close_lists()
        else:
            close_lists()
            paragraph.append(line.strip())
    flush_paragraph()
    close_lists()
    joined = "\n".join(body)
    return f"<!doctype html><html><head><meta charset=\"utf-8\"><style>{STYLE}</style></head><body>\n{joined}\n</body></html>"


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("사용법: notes-html.py <notes.md> <version>")
    sys.stdout.write(convert(open(sys.argv[1], encoding="utf-8").read(), sys.argv[2]))
