#!/usr/bin/env python3
"""Minimal Markdown -> HTML for the BNS spec (headings, paragraphs, lists,
tables, fenced code, blockquotes, hr, inline bold/italic/code/links).
Self-contained on purpose: no packages to install on the owner's Mac."""
import html, re, sys

src = open(sys.argv[1], encoding='utf-8').read().split('\n')
out = []

def inline(s):
    s = html.escape(s, quote=False)
    # inline code first (protect)
    codes = []
    def keep(m):
        codes.append(m.group(1)); return f'\x00{len(codes)-1}\x00'
    s = re.sub(r'`([^`]+)`', keep, s)
    s = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', s)
    s = re.sub(r'(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])', r'<em>\1</em>', s)
    s = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', s)
    s = re.sub(r'\x00(\d+)\x00', lambda m: f'<code>{codes[int(m.group(1))]}</code>', s)
    return s

i = 0
n = len(src)
para = []
def flush_para():
    global para
    if para:
        out.append('<p>' + inline(' '.join(x.strip() for x in para)) + '</p>')
        para = []

while i < n:
    line = src[i]
    st = line.strip()
    # fenced code
    if st.startswith('```'):
        flush_para()
        buf = []; i += 1
        while i < n and not src[i].strip().startswith('```'):
            buf.append(src[i]); i += 1
        out.append('<pre><code>' + html.escape('\n'.join(buf)) + '</code></pre>')
        i += 1; continue
    # table
    if st.startswith('|') and i + 1 < n and re.match(r'^\|?\s*:?-{2,}', src[i+1].strip()):
        flush_para()
        header = [c.strip() for c in st.strip('|').split('|')]
        i += 2
        rows = []
        while i < n and src[i].strip().startswith('|'):
            rows.append([c.strip() for c in src[i].strip().strip('|').split('|')]); i += 1
        t = ['<table><thead><tr>' + ''.join(f'<th>{inline(c)}</th>' for c in header) + '</tr></thead><tbody>']
        for r in rows:
            t.append('<tr>' + ''.join(f'<td>{inline(c)}</td>' for c in r) + '</tr>')
        t.append('</tbody></table>')
        out.append(''.join(t)); continue
    # headings
    m = re.match(r'^(#{1,6})\s+(.*)$', st)
    if m:
        flush_para()
        lvl = len(m.group(1)); txt = m.group(2)
        anchor = re.sub(r'[^a-z0-9א-ת]+', '-', txt.lower()).strip('-')
        out.append(f'<h{lvl} id="{anchor}">{inline(txt)}</h{lvl}>'); i += 1; continue
    # hr
    if re.match(r'^-{3,}$', st):
        flush_para(); out.append('<hr>'); i += 1; continue
    # blockquote
    if st.startswith('>'):
        flush_para(); buf = []
        while i < n and src[i].strip().startswith('>'):
            buf.append(src[i].strip()[1:].strip()); i += 1
        out.append('<blockquote><p>' + inline(' '.join(buf)) + '</p></blockquote>'); continue
    # lists (ul/ol, one nesting level by 2+ spaces)
    lm = re.match(r'^(\s*)([-*]|\d+\.)\s+(.*)$', line)
    if lm:
        flush_para()
        items = []  # (indent, ordered, text)
        while i < n:
            lm = re.match(r'^(\s*)([-*]|\d+\.)\s+(.*)$', src[i])
            if lm:
                items.append((len(lm.group(1)), lm.group(2) not in '-*', [lm.group(3)])); i += 1
            elif src[i].strip() and src[i].startswith(' ') and items:
                items[-1][2].append(src[i].strip()); i += 1  # continuation line
            else:
                break
        # render
        stack = []  # open list types with indent
        def close_to(ind):
            while stack and stack[-1][0] > ind:
                out.append('</li></' + stack.pop()[1] + '>')
        for ind, ordered, txt in items:
            tag = 'ol' if ordered else 'ul'
            if not stack or ind > stack[-1][0]:
                stack.append((ind, tag)); out.append(f'<{tag}><li>' + inline(' '.join(txt)))
            else:
                close_to(ind)
                out.append('</li><li>' + inline(' '.join(txt)))
        while stack:
            out.append('</li></' + stack.pop()[1] + '>')
        continue
    # blank
    if not st:
        flush_para(); i += 1; continue
    para.append(line); i += 1
flush_para()

body = '\n'.join(out)
css = """
@page { size: A4; margin: 18mm 16mm 20mm 16mm; }
html { font-size: 10.6pt; }
body { font-family: -apple-system, "Helvetica Neue", Arial, "Noto Sans Hebrew", sans-serif; color: #1c1b1a; line-height: 1.45; max-width: 100%; }
h1 { font-size: 24pt; margin: 0 0 4pt; letter-spacing: -0.01em; }
h2 { font-size: 15pt; margin: 22pt 0 6pt; padding-bottom: 3pt; border-bottom: 1.5px solid #c9b9a6; break-after: avoid; }
h3 { font-size: 12pt; margin: 14pt 0 4pt; break-after: avoid; }
p { margin: 4pt 0 6pt; orphans: 3; widows: 3; }
ul, ol { margin: 2pt 0 6pt; padding-inline-start: 1.3em; }
li { margin: 2pt 0; }
li > ul, li > ol { margin-top: 2pt; }
table { border-collapse: collapse; width: 100%; margin: 6pt 0 10pt; font-size: 9.3pt; break-inside: auto; }
th, td { border: 1px solid #cfc6ba; padding: 4pt 6pt; vertical-align: top; text-align: start; }
th { background: #f1ebe2; }
tr { break-inside: avoid; }
code { font-family: "SF Mono", Menlo, Consolas, monospace; font-size: 0.9em; background: #f4f1ec; padding: 0 3px; border-radius: 3px; }
pre { background: #f4f1ec; padding: 8pt 10pt; border-radius: 6px; overflow-x: auto; font-size: 8.8pt; line-height: 1.35; break-inside: avoid; }
pre code { background: none; padding: 0; }
blockquote { margin: 6pt 0; padding: 2pt 10pt; border-inline-start: 3px solid #c9b9a6; color: #3c3935; }
hr { border: 0; border-top: 1px solid #d9d0c4; margin: 14pt 0; }
a { color: #7a4f21; text-decoration: none; }
strong { font-weight: 650; }
h1 + p { font-size: 11.5pt; color: #3c3935; }
"""
doc = f'<!doctype html><html lang="en"><head><meta charset="utf-8"><title>BNS — The Specification</title><style>{css}</style></head><body>{body}</body></html>'
open(sys.argv[2], 'w', encoding='utf-8').write(doc)
print('html written:', sys.argv[2], 'blocks:', len(out))
