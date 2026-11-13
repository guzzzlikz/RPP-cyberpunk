"""Recolor Open77 UI stylesheets to the RPP yellow/black theme.

usage: recolor.py --table FILE...        print the color mapping only
       recolor.py --apply FILE...        rewrite files in place
"""
import colorsys
import re
import sys

HEX = re.compile(r'#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b')
RGB = re.compile(r'rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(,\s*[0-9.]+\s*)?\)')
YELLOW_HUE = 55 / 360   # #FCEE0A


def transform(r, g, b):
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    deg = h * 360
    chroma = s * (1 - abs(2 * l - 1))
    if 160 <= deg <= 205 and chroma >= 0.25:
        # cyan / teal accents -> cyberpunk yellow (#22d8e2 -> #fcee0a), lightness kept
        h, s = YELLOW_HUE, 0.97
    elif 160 <= deg <= 240 and chroma < 0.25:
        # navy inks, blue-grey text and hairlines -> neutral black / grey
        h, s = 48 / 360, s * 0.10
    elif 34 <= deg <= 46 and s >= 0.85 and l >= 0.35:
        # amber warnings would vanish next to the yellow accent -> orange
        h = 26 / 360
    else:
        return None
    rr, gg, bb = colorsys.hls_to_rgb(h, l, s)
    return round(rr * 255), round(gg * 255), round(bb * 255)


def recolor_hex(match, table):
    raw = match.group(1)
    if len(raw) == 3:
        raw6, alpha = ''.join(c * 2 for c in raw), ''
    else:
        raw6, alpha = raw[:6], raw[6:]
    r, g, b = (int(raw6[i:i + 2], 16) for i in (0, 2, 4))
    out = transform(r, g, b)
    if out is None:
        return match.group(0)
    new = '%02x%02x%02x' % out
    if raw6.isupper():
        new = new.upper()
    table['#' + raw6.lower()] = '#' + new.lower()
    return '#' + new + alpha


def recolor_rgb(match, table):
    r, g, b = (int(match.group(i)) for i in (1, 2, 3))
    out = transform(r, g, b)
    if out is None:
        return match.group(0)
    table['rgb(%d,%d,%d)' % (r, g, b)] = 'rgb(%d,%d,%d)' % out
    alpha = match.group(4)
    if alpha:
        return 'rgba(%d, %d, %d%s)' % (out + (alpha,))
    return 'rgb(%d, %d, %d)' % out


def process(text, table):
    text = HEX.sub(lambda m: recolor_hex(m, table), text)
    return RGB.sub(lambda m: recolor_rgb(m, table), text)


def main():
    mode, files = sys.argv[1], sys.argv[2:]
    table = {}
    changed = 0
    for path in files:
        data = open(path, 'rb').read()
        text = data.decode('utf-8')
        new = process(text, table)
        if mode == '--apply' and new != text:
            open(path, 'wb').write(new.encode('utf-8'))
            changed += 1
    for old, new in sorted(table.items()):
        print(old, '->', new)
    print('files changed:', changed, 'of', len(files), file=sys.stderr)


if __name__ == '__main__':
    main()
