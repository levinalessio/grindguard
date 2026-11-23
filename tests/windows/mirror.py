"""Nachbau der Windows-Regel-Engine (grindguard.ps1) in Python – Zeile für Zeile übertragen.

Damit lässt sich die Windows-Logik auch ohne Windows gegen denselben Testkatalog prüfen
wie die Mac-Version. Die echte PowerShell-Version läuft im CI auf einem Windows-Runner.

    python3 mirror.py <websites.txt> <urls.txt>      # gibt "B <suchbegriff|->" oder "E -" je Zeile aus
"""
import fnmatch
import re
import sys
from urllib.parse import unquote

SEARCH_PARAMS = ['q', 'p', 'query', 'text', 'wd', 'search_query', 'search', 's']
UNRESERVED = set(range(48, 58)) | set(range(65, 91)) | set(range(97, 123)) | {45, 46, 95, 126}


def import_sites(path):
    block, allow, search = [], [], []
    for raw in open(path, encoding='utf-8-sig').read().splitlines():
        l = raw.lower()
        h = l.find('#')
        if h >= 0:
            l = l[:h]
        l = l.strip()
        if l == '':
            continue
        l = re.sub(r'^\+\s+', '+', l)
        l = re.sub(r'^(\+?)https?://', r'\1', l)
        l = re.sub(r'^(\+?)www\.', r'\1', l)
        l = re.sub(r'/+$', '', l)
        if l in ('', '+'):
            continue
        if l.startswith('+'):
            allow.append(l[1:])
        elif l.startswith('suche:'):
            k = l[6:].strip()
            if k:
                search.append(k)
        else:
            block.append(l)
    return block, allow, search


def norm_path(p):
    cut = min([i for i in (p.find('?'), p.find('#')) if i >= 0], default=-1)
    path, rest = (p[:cut], p[cut:]) if cut >= 0 else (p, '')
    if '//' not in path and '%' not in path:
        return p

    def dec(m):
        c = int(m.group(1), 16)
        return chr(c).lower() if c in UNRESERVED else m.group(0)
    path = re.sub(r'%([0-9A-Fa-f]{2})', dec, path)
    path = re.sub(r'/{2,}', '/', path)
    return (path or '/') + rest


def url_parts(url):
    if not url or not url.strip():
        return None
    u = url.strip().lower()
    if re.match(r'^https?://', u):
        rest = u[u.index('://') + 3:]
    elif re.match(r'^[a-z0-9-]+(\.[a-z0-9-]+)+(:[0-9]+)?([/?#]\S*)?$', u):
        rest = u
    else:
        return None
    cut = min([i for i in (rest.find('/'), rest.find('?'), rest.find('#')) if i >= 0], default=-1)
    hp, tail = (rest[:cut], rest[cut:]) if cut >= 0 else (rest, '')
    hn = hp
    at = hn.rfind('@')
    if at >= 0:
        hn = hn[at + 1:]
    c = hn.find(':')
    if c >= 0:
        hn = hn[:c]
    if hn.startswith('www.'):
        hn = hn[4:]
    if hn.endswith('.'):
        hn = hn[:-1]
    if len(hn) > 15 and hn.endswith('.translate.goog'):
        hn = hn[:-15].replace('--', '_').replace('-', '.').replace('_', '-')
        if hn.startswith('www.'):
            hn = hn[4:]
    if hn == '':
        return None
    p = '/' if tail == '' else (tail if tail.startswith('/') else '/' + tail)
    return hn, norm_path(p)


def site_match(lst, hn, p):
    for e in lst:
        if '*' in e:
            if fnmatch.fnmatchcase(hn + p, e):
                return True
            continue
        slash = e.find('/')
        eh = e[:slash] if slash >= 0 else e
        if eh == '':
            continue
        if not (hn == eh or hn.endswith('.' + eh)):
            continue
        if slash < 0:
            return True
        if p.startswith('/' + e[slash + 1:]):
            return True
    return False


def ascii_lower(s):
    return ''.join(chr(ord(ch) + 32) if 'A' <= ch <= 'Z' else ch for ch in s)


def search_hit(search, p):
    if not search:
        return None
    qm = p.find('?')
    if qm < 0:
        return None
    qs = p[qm + 1:]
    h = qs.find('#')
    if h >= 0:
        qs = qs[:h]
    qs = '&' + qs
    for name in SEARCH_PARAMS:
        i = qs.find('&' + name + '=')
        if i < 0:
            continue
        v = qs[i + len(name) + 2:]
        a = v.find('&')
        if a >= 0:
            v = v[:a]
        if v == '':
            continue
        v = ascii_lower(unquote(v.replace('+', ' '), errors='surrogateescape'))
        for k in search:
            if k in v:
                return k
    return None


def decide(lists, url):
    block, allow, search = lists
    parts = url_parts(url)
    if not parts:
        return 'E -'
    hn, p = parts
    if site_match(allow, hn, p):
        return 'E -'
    k = search_hit(search, p)
    if k:
        return 'B ' + k
    if site_match(block, hn, p):
        return 'B -'
    return 'E -'


def main():
    lists = import_sites(sys.argv[1])
    for raw in open(sys.argv[2], encoding='utf-8').read().splitlines():
        line = raw.strip()
        if line == '' or line.startswith('#'):
            continue
        if not re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*://', line):
            line = 'https://' + line
        print(decide(lists, line))


if __name__ == '__main__':
    main()
