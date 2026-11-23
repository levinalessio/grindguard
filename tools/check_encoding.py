"""Prüft Zeilenenden und Kodierung aller Quelldateien.

Windows PowerShell 5.1 liest .ps1-Dateien ohne BOM als ANSI und verstümmelt Umlaute;
cmd.exe stolpert über LF-Zeilenenden. Auf dem Mac stören CR-Zeichen in Shell-Skripten.
Ein falsch eingestelltes Git (core.autocrlf) oder ein Editor ruiniert das schnell –
deshalb läuft diese Prüfung im CI.

    python3 tools/check_encoding.py
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
BOM = b'\xef\xbb\xbf'
SKIP_DIRS = {'.git', 'dist', 'node_modules', '__pycache__'}
SHELL_FILES = ('macos/app/grind',)
VAR_BEFORE_NON_ASCII = re.compile(r'\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7f]')
BINARY = ('.png', '.jpg', '.jpeg', '.gif', '.ico', '.icns', '.zip', '.svg')


def rules(rel):
    """(Zeilenende, BOM nötig, nur ASCII) für eine Datei relativ zum Repo."""
    if rel.startswith('windows/'):
        bom = rel.endswith('.ps1') or rel == 'windows/LIESMICH.txt'
        return 'crlf', bom, rel.endswith('.cmd')
    return 'lf', False, rel == 'macos/app/lib/overlay.js'


def main():
    problems = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
            if rel.endswith(BINARY):
                continue
            data = open(path, 'rb').read()
            eol, need_bom, ascii_only = rules(rel)
            if need_bom and not data.startswith(BOM):
                problems.append(f'{rel}: UTF-8-BOM fehlt (Windows PowerShell 5.1 liest sonst ANSI)')
            if not need_bom and data.startswith(BOM):
                problems.append(f'{rel}: unerwarteter BOM')
            body = data[3:] if data.startswith(BOM) else data
            try:
                body.decode('utf-8')
            except UnicodeDecodeError as e:
                problems.append(f'{rel}: kein gültiges UTF-8 ({e})')
                continue
            if ascii_only and any(b > 127 for b in body):
                problems.append(f'{rel}: darf nur ASCII enthalten')
            if eol == 'crlf':
                bare_lf = body.count(b'\n') - body.count(b'\r\n')
                if bare_lf:
                    problems.append(f'{rel}: {bare_lf} Zeilen mit LF statt CRLF')
            elif b'\r' in body:
                problems.append(f'{rel}: enthält CR (Windows-Zeilenenden) – hier gehört LF hin')
            if rel.startswith(('macos/', 'tests/', 'tools/')) and (rel.endswith('.sh') or rel in SHELL_FILES):
                # bash 3.2 und dash auf macOS zählen Bytes über 127 zum Variablennamen:
                # "$NAME“" wird dort zu einer leeren Variable. Immer "${NAME}“" schreiben.
                for nr, line in enumerate(body.decode('utf-8').splitlines(), 1):
                    if VAR_BEFORE_NON_ASCII.search(line):
                        problems.append(f'{rel}:{nr}: $VARIABLE direkt vor Umlaut/Sonderzeichen – ${{VARIABLE}} schreiben')
            if body and not body.endswith(b'\n'):
                problems.append(f'{rel}: letzte Zeile ohne Zeilenende')
    for p in problems:
        print(p)
    print('Kodierung: ok' if not problems else f'Kodierung: {len(problems)} Probleme')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
