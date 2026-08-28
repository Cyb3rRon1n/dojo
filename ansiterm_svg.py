#!/usr/bin/env python3
"""Render a tmux ANSI capture of the whiptail menu into a crisp terminal-style SVG.

Palette tuned to dojo's on-brand dark terminal look but reproduces the *actual*
SGR colors whiptail emitted. Auto-crops the frame's content bounding box so each
SVG hugs its menu box.
"""
import re, sys, os

CHAR_W = 8.2
CHAR_H = 15.5

# SGR (base-16) -> (fg, bg, ...) resolution; we only need the six codes used.
PAL = {
    '30?': "#111318",   # fg black
    '40!': "#06070a",   # bg black
    '37?': "#d9d9d9",   # fg white
    '44!': "#3a5f9e",   # bg blue (whiptail pane)
    '43!': "#e3b341",   # bg yellow (highlight / active)
    '!':   "#06070a",   # default bg
}
FG_DEFAULT = "#d9d9d9"
BG_DEFAULT = "#06070a"

class Cell:
    __slots__ = ('ch', 'fg', 'bg', 'bold')
    def __init__(self):
        self.ch = ' '
        self.fg = FG_DEFAULT
        self.bg = BG_DEFAULT
        self.bold = False

def parse(s, W, H):
    grid = [[Cell() for _ in range(W)] for _ in range(H)]
    fg, bg, bold = FG_DEFAULT, BG_DEFAULT, False
    row, col = 0, 0
    i = 0
    n = len(s)
    def put(ch):
        nonlocal col, row
        if ch == '\n':
            col = 0; row += 1
        else:
            if row < H and col < W:
                c = grid[row][col]
                c.ch = ch; c.fg = fg; c.bg = bg; c.bold = bold
            col += 1
    while i < n:
        ch = s[i]
        if ch == '\x1b' and i+1 < n and s[i+1] == '[':
            j = s.find('m', i)
            code = s[i+2:j]
            for part in code.split(';'):
                if part == '0':
                    fg, bg, bold = FG_DEFAULT, BG_DEFAULT, False
                elif part == '1':
                    bold = True
                elif part in ('30','31','32','33','34','35','36','37'):
                    key = part + '?'
                    fg = PAL.get(key, FG_DEFAULT)
                elif part in ('40','41','42','43','44','45','46','47'):
                    key = part + '!'
                    bg = PAL.get(key, BG_DEFAULT)
                elif part in ('90','91','92','93','94','95','96','97'):
                    fg = FG_DEFAULT  # bright fg -> keep light
                elif part in ('100','101','102','103','104','105','106','107'):
                    bg = BG_DEFAULT
            i = j + 1
            continue
        put(ch)
        i += 1
    return grid

def content_bbox(grid, H, W):
    minr, maxr, minc, maxc = H, -1, W, -1
    for r in range(H):
        for c in range(W):
            if grid[r][c].ch != ' ':
                if r < minr: minr = r
                if r > maxr: maxr = r
                if c < minc: minc = c
                if c > maxc: maxc = c
    if maxr < 0:
        return (0, 0, 0, 0)
    return (minr, maxr, minc, maxc)

def render(grid, H, W):
    minr, maxr, minc, maxc = content_bbox(grid, H, W)
    # small padding
    pad = 1
    top = max(0, minr - pad); left = max(0, minc - pad)
    rows = maxr - top + 1 + pad
    cols = maxc - left + 1 + pad
    width = cols * CHAR_W
    height = rows * CHAR_H
    sw = []
    sw.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:.0f}" height="{height:.0f}" '
              f'viewBox="0 0 {width:.3f} {height:.3f}" font-family="\'IBM Plex Mono\',Menlo,Consolas,monospace" '
              f'font-size="13" shape-rendering="crispEdges">')
    sw.append(f'<rect width="100%" height="100%" fill="{BG_DEFAULT}"/>')
    # background runs per row
    for r in range(top, top + rows):
        c = left
        while c < left + cols:
            bg = grid[r][c].bg
            run = c
            while run < left + cols and grid[r][run].bg == bg:
                run += 1
            if bg != BG_DEFAULT:
                x = (c - left) * CHAR_W
                y = (r - top) * CHAR_H
                w = (run - c) * CHAR_W
                sw.append(f'<rect x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{CHAR_H:.2f}" fill="{bg}"/>')
            c = run
    # glyphs
    for r in range(top, top + rows):
        for c in range(left, left + cols):
            cell = grid[r][c]
            if cell.ch == ' ':
                continue
            ch = cell.ch
            esc = ch if ch not in '&<>' else {'&':'&amp;','<':'&lt;','>':'&gt;'}[ch]
            x = (c - left) * CHAR_W
            y = (r - top) * CHAR_H
            weight = '600' if cell.bold else '400'
            # whiptail's highlight/active-button yellow reads best with dark ink
            fg = PAL['30?'] if cell.bg == PAL['43!'] else cell.fg
            sw.append(f'<text x="{x:.2f}" y="{y + CHAR_H*0.72:.2f}" fill="{fg}" font-weight="{weight}">{esc}</text>')
    sw.append('</svg>')
    return '\n'.join(sw)

def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else '/tmp/svg'
    os.makedirs(outdir, exist_ok=True)
    W, H = 100, 30
    for name in ['main', 'install', 'login', 'services', 'workspace']:
        src = f'/tmp/shots/{name}.ansi'
        if not os.path.exists(src):
            print(f"skip {name}: missing {src}")
            continue
        s = open(src, encoding='utf-8').read()
        grid = parse(s, W, H)
        svg = render(grid, H, W)
        dst = os.path.join(outdir, f'dojo-menu-{name}.svg')
        open(dst, 'w', encoding='utf-8').write(svg + '\n')
        print(f"wrote {dst} ({len(svg)} bytes)")

if __name__ == '__main__':
    main()
