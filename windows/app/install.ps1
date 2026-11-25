# ============================================================================
#  GrindGuard für Windows – installieren oder aktualisieren
#
#  Wird von INSTALLIEREN.cmd aufgerufen. Kopiert alles nach
#  %USERPROFILE%\GrindGuard, richtet den Autostart ein und zeigt bei der
#  ersten Installation einmal die Test-Warnung. Erneut ausführen =
#  aktualisieren; deine eigenen Listen und Einstellungen bleiben erhalten.
#
#  Diese Datei ist als UTF-8 mit BOM gespeichert.
# ============================================================================

$ErrorActionPreference = 'Stop'
$src   = $PSScriptRoot
$pkg   = Split-Path -Parent $src
$dest  = Join-Path $env:USERPROFILE 'GrindGuard'
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$utf8  = New-Object System.Text.UTF8Encoding($false)

function Get-ScriptVersion([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $m = [regex]::Match([System.IO.File]::ReadAllText($Path), "\`$script:Version\s*=\s*'([^']+)'")
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

try {
    if (-not (Test-Path -LiteralPath (Join-Path $src 'grindguard.ps1'))) {
        throw 'Die Installationsdateien fehlen. Bitte das ZIP vollständig entpacken und es noch einmal versuchen.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $src 'config') 'websites.txt'))) {
        throw ('Das ist der Quellcode von GitHub ("Code > Download ZIP"), nicht das fertige Paket.' +
            [Environment]::NewLine + 'Lade GrindGuard-Windows.zip hier herunter: https://github.com/levinalessio/grindguard/releases/latest')
    }
    $newVersion = Get-ScriptVersion (Join-Path $src 'grindguard.ps1')
    $oldVersion = Get-ScriptVersion (Join-Path $dest 'grindguard.ps1')
    $update = ($oldVersion -ne '')
    if ($update) {
        Write-Host ('Aktualisiere GrindGuard {0} -> {1} in {2} …' -f $oldVersion, $newVersion, $dest)
    } else {
        Write-Host ('Installiere GrindGuard {0} nach {1} …' -f $newVersion, $dest)
    }

    foreach ($d in @($dest, (Join-Path $dest 'config'), (Join-Path $dest 'state'))) {
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d) }
    }
    # Erst daneben kopieren, dann austauschen: Ein laufender Wächter liest nie eine halb kopierte Datei.
    foreach ($n in @('grindguard.ps1', 'grind.cmd', 'grindguard-ui.cs', 'DEINSTALLIEREN.cmd')) {
        $from = Join-Path $src $n
        if (-not (Test-Path -LiteralPath $from)) { continue }
        $tmp = Join-Path $dest ($n + '.neu')
        Copy-Item -LiteralPath $from -Destination $tmp -Force
        Move-Item -LiteralPath $tmp -Destination (Join-Path $dest $n) -Force
    }
    $readme = Join-Path $pkg 'LIESMICH.txt'
    if (Test-Path -LiteralPath $readme) {
        Copy-Item -LiteralPath $readme -Destination (Join-Path $dest 'LIESMICH.txt') -Force
    }

    foreach ($name in @('einstellungen.txt', 'websites.txt', 'apps.txt', 'sprueche.txt')) {
        $from = Join-Path (Join-Path $src 'config') $name
        $to = Join-Path (Join-Path $dest 'config') $name
        if (-not (Test-Path -LiteralPath $to)) {
            Copy-Item -LiteralPath $from -Destination $to
            continue
        }
        if ($name -ne 'websites.txt') {
            Write-Host ('  behalte deine bestehende {0}' -f $name)
            continue
        }
        $utf8r = [System.Text.Encoding]::UTF8
        $have = [System.IO.File]::ReadAllLines($to, $utf8r)
        $template = [System.IO.File]::ReadAllLines($from, $utf8r)
        # Zeilen, die frühere Vorlagen ausgeschaltet geliefert haben: die darf das Update einschalten
        $defaultOff = @()
        $offFile = Join-Path (Join-Path $src 'update') 'standard-aus.txt'
        if (Test-Path -LiteralPath $offFile) { $defaultOff = [System.IO.File]::ReadAllLines($offFile, $utf8r) }
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($l in $have) { $lines.Add($l) }
        $added = New-Object System.Collections.Generic.List[string]
        $toSwitch = New-Object System.Collections.Generic.List[string]
        foreach ($line in $template) {
            if ($line.Trim() -eq '' -or $line.StartsWith('#')) { continue }
            if ($lines -ccontains $line) { continue }
            $off = '#' + $line
            if ($lines -ccontains $off) {
                # Hast du die Zeile selbst mit # ausgeschaltet, bleibt sie aus.
                if ($defaultOff -ccontains $off) { $toSwitch.Add($line) }
                continue
            }
            $added.Add($line)
        }
        if ($added.Count -eq 0 -and $toSwitch.Count -eq 0) {
            Write-Host '  websites.txt: schon auf dem neuesten Stand'
            continue
        }
        Write-Host '  websites.txt: Die neue Vorlage enthält Einträge, die bei dir fehlen:'
        $all = @($added) + @($toSwitch)
        $shown = 0
        foreach ($l in $all) {
            $shown++
            if ($shown -le 15) { Write-Host ('      ' + $l) }
        }
        if ($all.Count -gt 15) { Write-Host ('      … und {0} weitere' -f ($all.Count - 15)) }
        $take = $true
        if ($env:GRIND_JA -eq '0') {
            $take = $false
        } elseif ($env:GRIND_JA -ne '1' -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
            $a = Read-Host '  Übernehmen? [J/n]'
            if ($a -match '^(n|nein|no)$') { $take = $false }
        }
        if (-not $take) {
            Write-Host '  websites.txt: unverändert gelassen'
            continue
        }
        if ($toSwitch.Count -gt 0) {
            foreach ($line in $toSwitch) { $lines[$lines.IndexOf('#' + $line)] = $line }
            [System.IO.File]::WriteAllText($to, (($lines -join "`r`n") + "`r`n"), $utf8)
            Write-Host ('  websites.txt: {0} bisher ausgeschaltete Einträge eingeschaltet' -f $toSwitch.Count)
        }
        if ($added.Count -gt 0) {
            $header = '# --- Ergänzt beim Update auf {0} (zum Ausschalten # davor setzen) ---' -f $newVersion
            $text = "`r`n" + $header + "`r`n" + ($added -join "`r`n") + "`r`n"
            [System.IO.File]::AppendAllText($to, $text, $utf8)
            Write-Host ('  websites.txt: {0} neue Einträge ergänzt, deine eigenen Änderungen bleiben' -f $added.Count)
        }
    }
    # Download-Markierung entfernen, sonst fragt Windows bei jedem Start nach
    Get-ChildItem -LiteralPath $dest -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
} catch {
    Write-Host ''
    Write-Host ('FEHLER: {0}' -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = 'Continue'
$grind = Join-Path $dest 'grindguard.ps1'

# Eintrag unter "Einstellungen > Apps", Startmenü "GrindGuard", Symbol
Write-Host ''
& $psExe -NoProfile -ExecutionPolicy Bypass -File $grind __einrichten

Write-Host ''
& $psExe -NoProfile -ExecutionPolicy Bypass -File $grind start
$started = ($LASTEXITCODE -eq 0)

if (-not $update) {
    Write-Host ''
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $grind test
}

Write-Host ''
Write-Host '------------------------------------------------------------------------'
if (-not $started) {
    Write-Host 'Kopiert, aber der Wächter läuft noch nicht. Ursache herausfinden:'
    Write-Host '  ~\GrindGuard\grind doctor   (in PowerShell eingeben)'
} elseif ($update) {
    Write-Host ('Update fertig. GrindGuard {0} läuft schon mit den neuen Listen.' -f $newVersion)
} else {
    Write-Host 'Fertig. GrindGuard läuft im Hintergrund und startet bei jeder Anmeldung mit.'
    Write-Host 'Das G.-Symbol unten rechts in der Taskleiste zeigt: Er ist aktiv.'
    Write-Host '(Falls du es nicht siehst: Pfeil ^ neben der Uhr anklicken.)'
}
Write-Host ''
Write-Host 'So bedienst du GrindGuard:'
Write-Host '  Klick aufs G.-Symbol        Fokus-Sitzung, Pause, Einstellungen'
Write-Host '  Startmenü > GrindGuard      Einstellungen: was gesperrt wird, Design, Zeiten'
Write-Host '  Einstellungen > Apps        GrindGuard entfernen (oder DEINSTALLIEREN.cmd)'
Write-Host ''
Write-Host 'Für Fortgeschrittene, in PowerShell:  ~\GrindGuard\grind help'
Write-Host ('Anleitung: {0}' -f (Join-Path $dest 'LIESMICH.txt'))
