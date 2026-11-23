"""Statische Prüfung von PowerShell-Dateien ohne PowerShell:
1. Syntax über tree-sitter-powershell (ERROR/MISSING-Knoten)
2. typische Fallen von Windows PowerShell 5.1
"""
import re, sys
from tree_sitter_language_pack import get_parser

parser = get_parser('powershell')
AUTOMATIC = {'pid', 'host', 'input', 'args', 'error', 'home', 'profile', 'event', 'sender', 'this',
             'matches', 'true', 'false', 'null', 'psitem', 'ofs', 'foreach', 'switch', 'executioncontext',
             'pscmdlet', 'psboundparameters', 'myinvocation', 'lastexitcode', 'shellid', 'pshome'}
SCOPES = {'script', 'global', 'local', 'private', 'env', 'using', 'function', 'variable', 'alias'}
PS7_ONLY = [(r'\?\?', 'Operator ?? gibt es erst ab PowerShell 7'),
            (r'(?<![\w$])\?\.', 'Operator ?. gibt es erst ab PowerShell 7'),
            (r'\s&&\s|\s\|\|\s', '&& / || gibt es erst ab PowerShell 7'),
            (r'ForEach-Object\s+-Parallel', '-Parallel gibt es erst ab PowerShell 7'),
            (r'\bJoin-String\b', 'Join-String gibt es erst ab PowerShell 7'),
            (r'-AsHashtable', '-AsHashtable gibt es erst ab PowerShell 6')]

def strip_strings(line):
    # ersetzt Inhalte von '...' und "..." durch Platzhalter (einfach, zeilenweise)
    return re.sub(r"'[^']*'|\"(?:`.|[^\"`])*\"", '""', line)

def check(path):
    src = open(path, 'rb').read()
    problems = []
    if not src.startswith(b'\xef\xbb\xbf') and re.search(rb'[\x80-\xff]', src):
        problems.append((0, 'Umlaute ohne UTF-8-BOM: Windows PowerShell 5.1 liest sie falsch'))
    text = src.decode('utf-8-sig')
    tree = parser.parse(text.encode('utf-8'))
    def walk(n):
        if n.type == 'ERROR' or n.is_missing:
            problems.append((n.start_point[0] + 1, f'Syntax: {"fehlt " + n.type if n.is_missing else "Fehler"} bei Spalte {n.start_point[1] + 1}: {text.splitlines()[n.start_point[0]].strip()[:90]}'))
        for c in n.children:
            walk(c)
    walk(tree.root_node)

    lines = text.splitlines()
    in_here = False
    for i, raw in enumerate(lines, 1):
        if re.match(r".*@'\s*$", raw) or re.match(r'.*@"\s*$', raw):
            in_here = True
            continue
        if in_here:
            if raw.startswith("'@") or raw.startswith('"@'):
                in_here = False
            elif raw.lstrip().startswith(("'@", '"@')):
                problems.append((i, 'Here-String-Ende muss ganz links stehen'))
            continue
        if raw.lstrip().startswith('#'):
            continue                    # Kommentarzeile
        # 1) Zuweisung an automatische Variablen
        for m in re.finditer(r'\$([A-Za-z_][A-Za-z0-9_]*)\s*(\+\+|--|[+\-*/]?=)(?!=)', strip_strings(raw)):
            if m.group(1).lower() in AUTOMATIC:
                problems.append((i, f'Zuweisung an automatische Variable ${m.group(1)}'))
        for m in re.finditer(r'param\(([^)]*)\)', raw):
            for v in re.findall(r'\$([A-Za-z_]\w*)', m.group(1)):
                if v.lower() in AUTOMATIC:
                    problems.append((i, f'Parametername ${v} ist eine automatische Variable'))
        for m in re.finditer(r'foreach\s*\(\s*\$([A-Za-z_]\w*)\s+in\b', raw, re.I):
            if m.group(1).lower() in AUTOMATIC:
                problems.append((i, f'Schleifenvariable ${m.group(1)} ist eine automatische Variable'))
        # 2) "$name:" in doppelten Anführungszeichen (wird als Laufwerk/Bereich gelesen)
        for s in re.findall(r'"(?:`.|[^"`])*"', raw):
            for m in re.finditer(r'(?<!`)\$([A-Za-z_][A-Za-z0-9_]*):', s):
                if m.group(1).lower() not in SCOPES:
                    problems.append((i, f'"${m.group(1)}:" in doppelten Anführungszeichen wird falsch gelesen'))
        # 3) Funktionsaufruf mit Klammern und Kommas
        for m in re.finditer(r'(?<!function )\b((?:Get|Set|Test|Invoke|Show|Start|Stop|Format|Import|Initialize|ConvertTo|Add|Write|New|Update|Remove|Reset|Wait|Close|Send)-[A-Za-z]+)\(([^()]*,[^()]*)\)', strip_strings(raw)):
            if not raw.lstrip().startswith('function'):
                problems.append((i, f'Aufruf {m.group(1)}(...,...) übergibt ein Array – ohne Klammern/Kommas aufrufen'))
        # 4) > oder < als Vergleich (ist in PowerShell eine Umleitung)
        bare = strip_strings(raw)
        if re.search(r'\bif\s*\(.*[^-\w=]\s[<>]\s', bare) or re.search(r'\bwhile\s*\(.*\s[<>]\s', bare):
            problems.append((i, '< oder > in einer Bedingung ist eine Umleitung, kein Vergleich'))
        # 5) -f: Klammern im Format-String prüfen
        for m in re.finditer(r"'((?:[^']|'')*)'\s*-f\b", raw):
            fmt = m.group(1)
            rest = re.sub(r'\{\d+(,-?\d+)?(:[^{}]+)?\}', '', fmt).replace('{{', '').replace('}}', '')
            if '{' in rest or '}' in rest:
                problems.append((i, f'Format-String mit losen Klammern: {fmt[:60]}'))
        # 6) PowerShell-7-only
        for pat, msg in PS7_ONLY:
            if re.search(pat, bare):
                problems.append((i, msg))
    return problems

total = 0
for path in sys.argv[1:]:
    probs = check(path)
    total += len(probs)
    print(f'{path}: {"ok" if not probs else str(len(probs)) + " Hinweise"}')
    for ln, msg in probs:
        print(f'   Zeile {ln}: {msg}')
sys.exit(1 if total else 0)
