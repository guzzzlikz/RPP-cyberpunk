"""Translate UI string literals in Open77 .js / .lua files with a JSON dictionary.

A literal is a candidate when it reads like prose: two or more words, or (Lua) the
value of a label / title / message / text / description / help / hint / subtitle /
placeholder / tooltip key. Event names, commands, selectors and identifiers have no
spaces and are never candidates. `apply` replaces only literals whose exact content
is in the dictionary, so anything not translated stays byte-identical.

usage:
  translate_code.py extract FILE...           print candidate literals as JSON
  translate_code.py apply DICT.json FILE...   replace translated literals
"""
import json
import re
import sys

LIT = re.compile(r'''(?P<q>["'])(?P<s>(?:\\.|(?!(?P=q))[^\\\n])*)(?P=q)|`(?P<t>[^`$\\]*)`''')
KEYED = re.compile(r'\b(label|title|message|text|description|help|hint|subtitle|placeholder|tooltip|caption|heading|body)\s*[=:]\s*$')
WORD = re.compile(r'[A-Za-z]{2,}')
CODE = re.compile(r'=>|[;{}<>]|\$\(|^\s*[.#\[]|https?:|\.(js|css|html|lua|png|jpg|rml|rcss|ttf|anims|ent)\b|^[a-z_]+[:.][a-z_.:]+$|%[sdqf]|\\[nt]')


# Lua: prose only counts when the line sends it to a player (log lines are skipped).
SINK = re.compile(r'notif|addMessage|command:result|reply\(|respond|chat\(|warn\(player|tell\(|feedback|toast|'
                  r'TriggerClientEvent|\b(label|title|message|text|description|help|hint|subtitle|reason)\s*[=:]')
LOGGY = re.compile(r'\b(print|log|logf|debugLog|error|assert|trace|info|warnLog)\s*\(|Log\w*\(|%s|%d|\.\.\s*$')


def candidates(text, lua):
    import bisect
    starts = [0] + [m.end() for m in re.finditer('\n', text)]

    def line_of(_, pos):
        i = bisect.bisect_right(starts, pos) - 1
        end = starts[i + 1] - 1 if i + 1 < len(starts) else len(text)
        return text[starts[i]:end][:400]

    for m in LIT.finditer(text):
        s = m.group('s') if m.group('s') is not None else m.group('t')
        if s is None or not WORD.search(s) or CODE.search(s):
            continue
        prose = len(WORD.findall(s)) >= 2 and ' ' in s.strip()
        keyed = lua and KEYED.search(text[max(0, m.start() - 40):m.start()])
        if lua and not keyed:
            line = line_of(text, m.start())
            if line.lstrip().startswith('--') or LOGGY.search(line) or not SINK.search(line):
                continue
        if prose or (keyed and s[:1].isupper()):
            start = m.start('s') if m.group('s') is not None else m.start('t')
            yield start, start + len(s), s


def is_lua(path):
    return path.endswith('.lua')


def extract(files):
    seen = {}
    for path in files:
        text = open(path, encoding='utf-8').read()
        for _, _, s in candidates(text, is_lua(path)):
            seen.setdefault(s, path)
    json.dump({k: '' for k in seen}, sys.stdout, ensure_ascii=False, indent=1)


def apply(dict_path, files):
    table = {k: v for k, v in json.load(open(dict_path, encoding='utf-8')).items() if v}
    for path in files:
        text = open(path, 'rb').read().decode('utf-8')
        out, last, n = [], 0, 0
        for start, end, s in candidates(text, is_lua(path)):
            if s in table:
                out += [text[last:start], table[s]]
                last, n = end, n + 1
        out.append(text[last:])
        if n:
            open(path, 'wb').write(''.join(out).encode('utf-8'))
        print(n, path, file=sys.stderr)


if __name__ == '__main__':
    if sys.argv[1] == 'extract':
        extract(sys.argv[2:])
    else:
        apply(sys.argv[2], sys.argv[3:])
