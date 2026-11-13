"""Translate visible text in Open77 UI markup (.rml / .html) with a JSON dictionary.

Only text nodes and the placeholder / title / aria-label / data-tip attributes are
touched; tags, ids, classes, data bindings ({{...}}), <script> and <style> are not.

usage:
  translate_ui.py extract FILE...             print untranslated strings as JSON
  translate_ui.py apply DICT.json FILE...     replace strings found in DICT
"""
import json
import re
import sys

SKIP = re.compile(r'<(script|style)\b[^>]*>.*?</\1>|<!--.*?-->', re.S | re.I)
TEXT = re.compile(r'>([^<>]+)<')
ATTR = re.compile(r'\b(placeholder|title|aria-label|data-tip|alt)="([^"]*)"')
LATIN = re.compile(r'[A-Za-z]{2,}')


def segments(text):
    """Yields (start, end, value) of translatable pieces outside script/style."""
    pos = 0
    for block in list(SKIP.finditer(text)) + [None]:
        end = block.start() if block else len(text)
        part = text[pos:end]
        for m in TEXT.finditer(part):
            raw = m.group(1)
            # keep {{bindings}} and entities out of the key, translate around them
            stripped = raw.strip()
            if stripped and LATIN.search(re.sub(r'\{\{.*?\}\}|&\w+;', '', stripped)):
                s = pos + m.start(1) + raw.index(stripped)
                yield s, s + len(stripped), stripped
        for m in ATTR.finditer(part):
            value = m.group(2)
            if LATIN.search(value) and '{{' not in value:
                yield pos + m.start(2), pos + m.end(2), value
        if block:
            pos = block.end()


def extract(files):
    seen = {}
    for path in files:
        text = open(path, encoding='utf-8').read()
        for _, _, value in segments(text):
            seen.setdefault(value, path)
    json.dump({k: '' for k in seen}, sys.stdout, ensure_ascii=False, indent=1)


def apply(dict_path, files):
    table = {k: v for k, v in json.load(open(dict_path, encoding='utf-8')).items() if v}
    for path in files:
        data = open(path, 'rb').read()
        text = data.decode('utf-8')
        out, last, n = [], 0, 0
        # text nodes and attributes are found in two passes: splice in position order
        for start, end, value in sorted(segments(text)):
            if value in table:
                out.append(text[last:start])
                out.append(table[value])
                last = end
                n += 1
        out.append(text[last:])
        if n:
            open(path, 'wb').write(''.join(out).encode('utf-8'))
        print(n, path, file=sys.stderr)


if __name__ == '__main__':
    if sys.argv[1] == 'extract':
        extract(sys.argv[2:])
    else:
        apply(sys.argv[2], sys.argv[3:])
