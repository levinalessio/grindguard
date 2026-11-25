# ============================================================================
#  GrindGuard für Windows – Fokus-Wächter
#
#  Erkennt Ablenkungen (Programme, Websites, Suchbegriffe), schliesst sie
#  sofort und sperrt den Bildschirm mit einer Warnung. Nutzt nur Bordmittel
#  von Windows 10/11 (Windows PowerShell 5.1). Es wird nichts nachinstalliert
#  und nichts verlässt deinen PC.
#
#  Alle Befehle:  ~\GrindGuard\grind help
#
#  Diese Datei ist als UTF-8 mit BOM gespeichert, damit Windows PowerShell
#  die Umlaute richtig liest.
# ============================================================================
param(
    [Parameter(Position = 0)][string]$Command = 'help',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest = @()
)

$script:Version      = '1.4'
$script:Base         = $PSScriptRoot
$script:SelfPath     = $PSCommandPath
$script:ConfDir      = Join-Path $script:Base 'config'
$script:StateDir     = Join-Path $script:Base 'state'
$script:SettingsFile = Join-Path $script:ConfDir 'einstellungen.txt'
$script:SitesFile    = Join-Path $script:ConfDir 'websites.txt'
$script:AppsFile     = Join-Path $script:ConfDir 'apps.txt'
$script:QuotesFile   = Join-Path $script:ConfDir 'sprueche.txt'
$script:StrikesFile  = Join-Path $script:StateDir 'ausrutscher.log'
$script:PauseFile    = Join-Path $script:StateDir 'pause_bis'
$script:PidFile      = Join-Path $script:StateDir 'daemon.pid'
$script:StopFile     = Join-Path $script:StateDir 'stop'
$script:LogFile      = Join-Path $script:StateDir 'grindguard.log'
$script:StatusFile   = Join-Path $script:StateDir 'status.txt'
$script:FocusFile    = Join-Path $script:StateDir 'fokus_bis'
$script:FocusDir     = Join-Path $script:StateDir 'fokus'
$script:NotSatz      = 'Ich breche meine Fokus-Sitzung bewusst ab'
$script:ConfSrc      = $script:ConfDir
$script:GrindCmd     = Join-Path $script:Base 'grind.cmd'
$script:UiFile       = Join-Path $script:Base 'grindguard-ui.cs'
$script:IconFile     = Join-Path $script:Base 'grindguard.ico'
$script:OpenFlag     = Join-Path $script:StateDir 'einstellungen_oeffnen'
$script:UpdateRepo   = 'levinalessio/grindguard'
$script:UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\GrindGuard'
$script:RunKey       = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$script:RunName      = 'GrindGuard'
$script:MutexName    = 'Local\GrindGuard-Waechter'
$script:PsExe        = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:Utf8         = New-Object System.Text.UTF8Encoding($false)
$script:Inv          = [System.Globalization.CultureInfo]::InvariantCulture

# Browser (Prozessnamen ohne .exe). Bei ihnen wird die Adresse geprüft.
$script:Browsers = @('chrome', 'msedge', 'brave', 'opera', 'vivaldi', 'chromium', 'thorium',
    'arc', 'comet', 'firefox', 'librewolf', 'waterfox', 'floorp', 'zen')

# Diese Programme werden nie beendet, egal was in apps.txt steht – unter
# anderem die Terminals, damit du den Wächter immer anhalten kannst.
$script:Protected = @('explorer', 'dwm', 'csrss', 'winlogon', 'wininit', 'services', 'lsass', 'smss',
    'svchost', 'sihost', 'ctfmon', 'fontdrvhost', 'dllhost', 'runtimebroker', 'logonui', 'lockapp',
    'searchhost', 'searchapp', 'searchui', 'startmenuexperiencehost', 'shellexperiencehost',
    'textinputhost', 'applicationframehost', 'systemsettings', 'taskmgr', 'cmd', 'powershell', 'pwsh',
    'powershell_ise', 'windowsterminal', 'openconsole', 'conhost', 'mmc', 'securityhealthsystray',
    'rundll32', 'widgets', 'phoneexperiencehost', 'consent')

# Erkennung über den Fenstertitel – nur wenn die Adresse selbst nicht lesbar ist
# (z. B. Vollbild, App-Fenster von TikTok/Instagram, Firefox ohne Bedienungshilfe).
$script:TitleEnd = '(\s[-\u2013\u2014]\s|\s(und|and)\s\d+\s|$)'
$script:TitleRules = @(
    @{ P = '^(?<q>.+?)\s[-\u2013\u2014]\sGoogle[\s-]?(Suche|Search)' + $script:TitleEnd; Url = 'https://www.google.com/search?q=' },
    @{ P = '^(?<q>.+?)\s(at|bei|auf)\sDuckDuckGo' + $script:TitleEnd; Url = 'https://duckduckgo.com/?q=' },
    @{ P = '(^|\s[-\u2013\u2014|]\s)YouTube Studio' + $script:TitleEnd; Url = 'https://studio.youtube.com/' },
    @{ P = '(^|\s[-\u2013\u2014|]\s)YouTube Music' + $script:TitleEnd; Url = 'https://music.youtube.com/' },
    @{ P = '(^(\(\d+\)\s)?|\s[-\u2013\u2014|]\s)YouTube' + $script:TitleEnd; Url = 'https://www.youtube.com/' },
    @{ P = '(^(\(\d+\)\s)?Instagram' + $script:TitleEnd + ')|(\s[\u2022|]\sInstagram)|(\s(on|auf)\sInstagram\b)'; Url = 'https://www.instagram.com/' },
    @{ P = '(^(\(\d+\)\s)?TikTok' + $script:TitleEnd + ')|(\s\|\sTikTok' + $script:TitleEnd + ')'; Url = 'https://www.tiktok.com/' },
    @{ P = '(^(\(\d+\)\s)?Reddit\s[-\u2013\u2014]\s)|(\s:\sr/\w+)|(^r/\w+)'; Url = 'https://www.reddit.com/' },
    @{ P = '(^(\(\d+\)\s)?Netflix' + $script:TitleEnd + ')|(\s[-\u2013\u2014|]\sNetflix' + $script:TitleEnd + ')'; Url = 'https://www.netflix.com/' },
    @{ P = '(^|\s[-\u2013\u2014|]\s)Twitch' + $script:TitleEnd; Url = 'https://www.twitch.tv/' },
    @{ P = '(^(\(\d+\)\s)?Facebook' + $script:TitleEnd + ')|(\s\|\sFacebook' + $script:TitleEnd + ')'; Url = 'https://www.facebook.com/' },
    @{ P = '(\s/\sX' + $script:TitleEnd + ')|(\s(on|auf)\sX:\s)'; Url = 'https://x.com/' },
    @{ P = '\s[\u2022|]\slichess\.org' + $script:TitleEnd; Url = 'https://lichess.org/' },
    @{ P = '(^Ricardo\s[-\u2013\u2014]\s)|(\s[-\u2013\u2014|]\sRicardo' + $script:TitleEnd + ')|(\s\|\sRicardo\s)'; Url = 'https://www.ricardo.ch/' },
    @{ P = '\s[-\u2013\u2014|]\stutti(\.ch)?' + $script:TitleEnd; Url = 'https://www.tutti.ch/' },
    @{ P = '(download\sfree\smp3)|(mp3\sdownload)|(\bMP3\.pm\b)|(\bListen\sMP3\b)'; Url = 'https://mp3.pm/' },
    @{ P = '(\s(on|auf)\sAudiomack\b)|(\s\|\sAudiomack' + $script:TitleEnd + ')'; Url = 'https://audiomack.com/' },
    @{ P = '^Stake:\s'; Url = 'https://stake.com/' }
)

# Windows-Funktionen, die PowerShell nicht von sich aus mitbringt
$script:NativeSource = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class GGNative
{
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool AllowSetForegroundWindow(int processId);

    public static string Title(IntPtr hWnd)
    {
        StringBuilder sb = new StringBuilder(1024);
        GetWindowText(hWnd, sb, sb.Capacity);
        return sb.ToString();
    }

    public static int ProcessId(IntPtr hWnd)
    {
        uint pid;
        GetWindowThreadProcessId(hWnd, out pid);
        return (int)pid;
    }

    public static bool KeyDown(int vKey)
    {
        return (GetAsyncKeyState(vKey) & 0x8000) != 0;
    }

    // Strg+W: schliesst im Browser den sichtbaren Tab
    public static void CtrlW()
    {
        const uint KEYUP = 0x0002;
        keybd_event(0x11, 0, 0, UIntPtr.Zero);
        keybd_event(0x57, 0, 0, UIntPtr.Zero);
        keybd_event(0x57, 0, KEYUP, UIntPtr.Zero);
        keybd_event(0x11, 0, KEYUP, UIntPtr.Zero);
    }
}
'@

# Diese Fenster sind nie das Ziel der Rückkehr (Taskleiste, Startmenü, Sperrbildschirm …)
$script:NoReturn = @('explorer', 'lockapp', 'logonui', 'searchhost', 'searchapp', 'searchui',
    'startmenuexperiencehost', 'shellexperiencehost', 'textinputhost', 'consent', 'dwm')

$script:SearchParams = @('q', 'p', 'query', 'text', 'wd', 'search_query', 'search', 's')

# Welche Designs der Sperre bei "wechselnd" je nach Ton nacheinander kommen
$script:PlateSets = @{
    brutal = @('nacht', 'kobalt', 'lexikon')
    direkt = @('lexikon', 'papier', 'kobalt')
    ruhig  = @('papier', 'bordeaux')
}
$script:PlateNames = @('nacht', 'kobalt', 'papier', 'lexikon', 'bordeaux')

# Kobalt: dieser Satz wird neunmal "geschrieben", bis die Sperre vorbei ist
$script:KobaltLines = @('Ich arbeite jetzt weiter.', 'Ich entscheide, nicht mein Feed.',
    'Erst die Arbeit. Dann der Rest.', 'Ich bleibe dran.')

# Lexikon: Wörterbucheinträge statt Spruch
$script:Lexikon = @(
    @{ W = 'Prokrastination.'; K = '(Nomen)'; D = 'Das, was du gerade machst, statt das, was du dir vorgenommen hast.' },
    @{ W = 'Ausrede.'; K = '(Nomen)'; D = 'Ein guter Grund, der zufällig genau dann auftaucht, wenn es anstrengend wird.' },
    @{ W = 'Später.'; K = '(Adverb)'; D = 'Das Wort, an dem die meisten Ziele scheitern.' },
    @{ W = 'Disziplin.'; K = '(Nomen)'; D = 'Das tun, was du dir vorgenommen hast. Auch wenn niemand zuschaut.' },
    @{ W = 'Gewohnheit.'; K = '(Nomen)'; D = 'Was du heute dreimal tust, tust du morgen, ohne zu fragen.' },
    @{ W = 'Fokus.'; K = '(Nomen)'; D = 'Nein sagen zu allem, was jetzt nicht dran ist. Auch zu diesem Tab.' }
)
$script:LexikonJagd = @{ W = 'Umweg.'; K = '(Nomen)'; D = 'Der dritte Versuch in zehn Minuten, doch noch durchzukommen. Er führt nirgendwohin.' }

$script:CalmQuotes = @(
    'Kurz durchatmen. Dann den nächsten kleinen Schritt.',
    'Abgelenkt passiert jedem. Entscheidend ist, wie schnell du zurück bist.',
    'Was ist die nächste Aufgabe, die du in fünf Minuten schaffst?',
    'Leg das Handy weg, trink einen Schluck Wasser, mach weiter.'
)

# Welche Listen gelten? Normal config\, während einer Fokus-Sitzung die eingefrorene Kopie.
function Set-ConfSrc([string]$Dir) {
    $script:ConfSrc = $Dir
    $script:SettingsFile = Join-Path $Dir 'einstellungen.txt'
    $script:SitesFile = Join-Path $Dir 'websites.txt'
    $script:AppsFile = Join-Path $Dir 'apps.txt'
    $script:QuotesFile = Join-Path $Dir 'sprueche.txt'
}

# ----------------------------------------------------------------------------
# Kleine Helfer
# ----------------------------------------------------------------------------
function Get-Now {
    return [DateTimeOffset]::Now.ToUnixTimeSeconds()
}

function Write-Log([string]$Message) {
    try {
        if (-not (Test-Path -LiteralPath $script:StateDir)) {
            [void](New-Item -ItemType Directory -Path $script:StateDir -Force)
        }
        $line = '{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $script:Inv), $Message
        [System.IO.File]::AppendAllText($script:LogFile, $line + "`r`n", $script:Utf8)
    } catch { }
}

$script:LastLogMsg = ''
$script:LastLogAt = 0
function Write-LogOnce([string]$Message) {
    # dieselbe Meldung höchstens alle 10 Minuten
    $now = Get-Now
    if ($Message -eq $script:LastLogMsg -and ($now - $script:LastLogAt) -lt 600) { return }
    $script:LastLogMsg = $Message
    $script:LastLogAt = $now
    Write-Log $Message
}

function Get-ConfigLines([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    try {
        return [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
    } catch {
        return @()
    }
}

function Format-Clock([long]$Unix) {
    return [DateTimeOffset]::FromUnixTimeSeconds($Unix).ToLocalTime().ToString('HH:mm', $script:Inv)
}

function Format-HM([int]$Value) {
    return ('{0:00}:{1:00}' -f [math]::Floor($Value / 100), ($Value % 100))
}

function Test-Protected([string]$Name) {
    return ($script:Protected -contains $Name)
}

# ----------------------------------------------------------------------------
# Konfiguration einlesen
# ----------------------------------------------------------------------------
function Import-Settings {
    $s = @{
        SperrStart = 10; SperrPlus = 5; SperrMax = 60
        Stimme = 1; StimmenName = ''; Alarmton = 1
        IntervallMs = 1000; ZeitVon = 0; ZeitBis = 2400; Tage = '1234567'
        Ton = 'brutal'; Zurueck = 1; Jagd = 1; HartBeenden = 1; Lautstaerke = 100; Design = 'wechselnd'
    }
    foreach ($raw in (Get-ConfigLines $script:SettingsFile)) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $line.Substring(0, $eq).Trim()
        $val = $line.Substring($eq + 1)
        $hash = $val.IndexOf('#')
        if ($hash -ge 0) { $val = $val.Substring(0, $hash) }
        $val = $val.Trim()
        switch ($key) {
            'SPERRZEIT_START' { if ($val -match '^(0|[1-9][0-9]{0,3})$') { $s.SperrStart = [int]$val } }
            'SPERRZEIT_PLUS'  { if ($val -match '^(0|[1-9][0-9]{0,3})$') { $s.SperrPlus = [int]$val } }
            'SPERRZEIT_MAX'   { if ($val -match '^(0|[1-9][0-9]{0,3})$') { $s.SperrMax = [int]$val } }
            'STIMME'          { if ($val -match '^[01]$') { $s.Stimme = [int]$val } }
            'ALARMTON'        { if ($val -match '^[01]$') { $s.Alarmton = [int]$val } }
            'STIMMEN_NAME'    { $s.StimmenName = $val }
            'INTERVALL' {
                if ($val -match '^(0\.5|[1-9]|[12][0-9]|30)$') {
                    $s.IntervallMs = [int]([double]::Parse($val, $script:Inv) * 1000)
                }
            }
            'AKTIVE_TAGE'     { if ($val -match '^[1-7]+$') { $s.Tage = $val } }
            'TON'             { if ($val -match '^(brutal|direkt|ruhig)$') { $s.Ton = $val } }
            'ZURUECK'         { if ($val -match '^[01]$') { $s.Zurueck = [int]$val } }
            'JAGD'            { if ($val -match '^[01]$') { $s.Jagd = [int]$val } }
            'HART_BEENDEN'    { if ($val -match '^[01]$') { $s.HartBeenden = [int]$val } }
            'LAUTSTAERKE'     { if ($val -match '^(0|[1-9][0-9]?|100)$') { $s.Lautstaerke = [int]$val } }
            'DESIGN'          { if ($val -match '^(wechselnd|nacht|kobalt|papier|lexikon|bordeaux)$') { $s.Design = $val } }
            'AKTIVE_ZEIT' {
                if ($val -match '^([0-2][0-9]):([0-5][0-9])-([0-2][0-9]):([0-5][0-9])$') {
                    $s.ZeitVon = [int]($Matches[1] + $Matches[2])
                    $s.ZeitBis = [int]($Matches[3] + $Matches[4])
                }
            }
        }
    }
    # Sicherheitsgrenzen: Der Bildschirm wird nie länger als 5 Minuten gesperrt.
    if ($s.SperrMax -gt 300) { $s.SperrMax = 300 }
    if ($s.SperrMax -lt 3) { $s.SperrMax = 3 }
    if ($s.SperrStart -lt 3) { $s.SperrStart = 3 }
    if ($s.SperrStart -gt $s.SperrMax) { $s.SperrStart = $s.SperrMax }
    if ($s.SperrPlus -gt 300) { $s.SperrPlus = 300 }
    $script:S = $s
}

function Import-Sites {
    $block = New-Object System.Collections.Generic.List[string]
    $allow = New-Object System.Collections.Generic.List[string]
    $search = New-Object System.Collections.Generic.List[string]
    foreach ($raw in (Get-ConfigLines $script:SitesFile)) {
        $l = $raw.ToLowerInvariant()
        $hash = $l.IndexOf('#')
        if ($hash -ge 0) { $l = $l.Substring(0, $hash) }
        $l = $l.Trim()
        if ($l -eq '') { continue }
        $l = $l -replace '^\+\s+', '+'
        $l = $l -replace '^(\+?)https?://', '$1'
        $l = $l -replace '^(\+?)www\.', '$1'
        $l = $l -replace '/+$', ''
        if ($l -eq '' -or $l -eq '+') { continue }
        if ($l.StartsWith('+')) {
            $allow.Add($l.Substring(1))
        } elseif ($l.StartsWith('suche:')) {
            $k = $l.Substring(6).Trim()
            if ($k -ne '') { $search.Add($k) }
        } else {
            $block.Add($l)
        }
    }
    $script:SitesBlock = $block
    $script:SitesAllow = $allow
    $script:SearchBlock = $search
}

function Import-Apps {
    $apps = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($raw in (Get-ConfigLines $script:AppsFile)) {
        $l = $raw.ToLowerInvariant()
        $hash = $l.IndexOf('#')
        if ($hash -ge 0) { $l = $l.Substring(0, $hash) }
        $l = ($l.Trim()) -replace '\.exe$', ''
        if ($l -ne '') { [void]$apps.Add($l) }
    }
    $script:AppsBlock = $apps
}

function Import-All {
    Import-Settings
    Import-Sites
    Import-Apps
}

# ----------------------------------------------------------------------------
# Adressen prüfen
# ----------------------------------------------------------------------------
function ConvertTo-UrlParts([string]$Url) {
    # Zerlegt eine Adresse in Host und Pfad (inkl. ?Suche). $null = keine Webadresse.
    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    $u = $Url.Trim().ToLowerInvariant()
    if ($u -match '^https?://') {
        $rest = $u.Substring($u.IndexOf('://') + 3)
    } elseif ($u -match '^[a-z0-9-]+(\.[a-z0-9-]+)+(:[0-9]+)?([/?#]\S*)?$') {
        $rest = $u      # so zeigt die Adressleiste sie an: ohne https://
    } else {
        return $null
    }
    $cut = $rest.IndexOfAny([char[]]'/?#')
    if ($cut -ge 0) {
        $hp = $rest.Substring(0, $cut)
        $tail = $rest.Substring($cut)
    } else {
        $hp = $rest
        $tail = ''
    }
    $hn = $hp
    $at = $hn.LastIndexOf('@')
    if ($at -ge 0) { $hn = $hn.Substring($at + 1) }
    $colon = $hn.IndexOf(':')
    if ($colon -ge 0) { $hn = $hn.Substring(0, $colon) }
    if ($hn.StartsWith('www.')) { $hn = $hn.Substring(4) }
    if ($hn.EndsWith('.')) { $hn = $hn.Substring(0, $hn.Length - 1) }
    if ($hn.Length -gt 15 -and $hn.EndsWith('.translate.goog')) {
        # Umweg über Google Übersetzer: audio-com.translate.goog ist audio.com
        $hn = $hn.Substring(0, $hn.Length - 15).Replace('--', '_').Replace('-', '.').Replace('_', '-')
        if ($hn.StartsWith('www.')) { $hn = $hn.Substring(4) }
    }
    if ($hn -eq '') { return $null }
    if ($tail -eq '') {
        $p = '/'
    } elseif ($tail.StartsWith('/')) {
        $p = $tail
    } else {
        $p = '/' + $tail
    }
    return @{ HostName = $hn; PathPart = (ConvertTo-NormPath $p) }
}

function ConvertTo-NormPath([string]$PathPart) {
    # Damit Umwege wie //shorts oder /%73horts nicht durchrutschen: mehrfache / werden
    # zu einem, %XX wird nur für unkritische Zeichen (a-z 0-9 - . _ ~) entschlüsselt.
    # Alles ab ? oder # bleibt unverändert. (Gleiche Regel wie auf dem Mac.)
    $cut = $PathPart.IndexOfAny([char[]]'?#')
    if ($cut -ge 0) {
        $path = $PathPart.Substring(0, $cut)
        $rest = $PathPart.Substring($cut)
    } else {
        $path = $PathPart
        $rest = ''
    }
    if (-not ($path.Contains('//') -or $path.Contains('%'))) { return $PathPart }
    $path = [regex]::Replace($path, '%([0-9A-Fa-f]{2})', {
        param($m)
        $c = [Convert]::ToInt32($m.Groups[1].Value, 16)
        if (($c -ge 48 -and $c -le 57) -or ($c -ge 65 -and $c -le 90) -or ($c -ge 97 -and $c -le 122) -or
            $c -eq 45 -or $c -eq 46 -or $c -eq 95 -or $c -eq 126) {
            return ([string][char]$c).ToLowerInvariant()
        }
        return $m.Value
    })
    $path = [regex]::Replace($path, '/{2,}', '/')
    if ($path -eq '') { $path = '/' }
    return ($path + $rest)
}

function Test-SiteMatch($List, [string]$HostName, [string]$PathPart) {
    foreach ($e in $List) {
        if ($e.Contains('*')) {
            # Eintrag mit Stern: Muster über die ganze Adresse
            if (($HostName + $PathPart) -like $e) { return $true }
            continue
        }
        $slash = $e.IndexOf('/')
        if ($slash -ge 0) { $eh = $e.Substring(0, $slash) } else { $eh = $e }
        if ($eh -eq '') { continue }
        if (-not ($HostName -eq $eh -or $HostName.EndsWith('.' + $eh))) { continue }
        if ($slash -lt 0) { return $true }
        $ep = '/' + $e.Substring($slash + 1)
        if ($PathPart.StartsWith($ep, [System.StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

function ConvertTo-AsciiLower([string]$Text) {
    # nur A–Z klein schreiben – dieselbe Regel wie auf dem Mac
    $sb = New-Object System.Text.StringBuilder $Text.Length
    foreach ($ch in $Text.ToCharArray()) {
        $i = [int]$ch
        if ($i -ge 65 -and $i -le 90) { [void]$sb.Append([char]($i + 32)) } else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

function Get-SearchHit([string]$PathPart) {
    # Steckt ein Suchbegriff aus der Liste in der Suche? Geprüft werden die Parameter,
    # in denen Suchmaschinen den Text übergeben (q, p, query, text, wd, search_query, …).
    if ($script:SearchBlock.Count -eq 0) { return $null }
    $qm = $PathPart.IndexOf('?')
    if ($qm -lt 0) { return $null }
    $qs = $PathPart.Substring($qm + 1)
    $hash = $qs.IndexOf('#')
    if ($hash -ge 0) { $qs = $qs.Substring(0, $hash) }
    $qs = '&' + $qs
    foreach ($name in $script:SearchParams) {
        $i = $qs.IndexOf('&' + $name + '=')
        if ($i -lt 0) { continue }
        $v = $qs.Substring($i + $name.Length + 2)
        $amp = $v.IndexOf('&')
        if ($amp -ge 0) { $v = $v.Substring(0, $amp) }
        if ($v -eq '') { continue }
        $v = $v.Replace('+', ' ')
        try { $v = [System.Uri]::UnescapeDataString($v) } catch { }
        $v = ConvertTo-AsciiLower $v
        foreach ($k in $script:SearchBlock) {
            if ($v.Contains($k)) { return $k }
        }
    }
    return $null
}

function Get-BlockName($Parts) {
    # Anzeigename, wenn die Adresse blockiert ist – sonst $null
    $script:LastSearchHit = $null
    if (-not $Parts) { return $null }
    if (Test-SiteMatch $script:SitesAllow $Parts.HostName $Parts.PathPart) { return $null }
    # Suchbegriffe zuerst: dann nennt die Warnung „Suche nach mp3“ statt nur google.com
    $k = Get-SearchHit $Parts.PathPart
    if ($k) {
        $script:LastSearchHit = $k
        return ('Suche nach „{0}“' -f $k)
    }
    if (Test-SiteMatch $script:SitesBlock $Parts.HostName $Parts.PathPart) { return $Parts.HostName }
    return $null
}

function Get-TitleUrl([string]$Title, [switch]$SearchOnly) {
    # Leitet aus dem Fenstertitel eine Adresse ab (Ersatz, falls die Adressleiste nicht lesbar ist).
    # -SearchOnly: nur Suchmaschinen (Google, DuckDuckGo) auswerten.
    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }
    $t = $Title -replace '[\u200B-\u200F\u202A-\u202E\u2060\uFEFF]', ''
    $rules = $script:TitleRules
    if ($SearchOnly) { $rules = $script:TitleRules[0..1] }
    foreach ($rule in $rules) {
        $m = [regex]::Match($t, $rule.P)
        if ($m.Success) {
            if ($m.Groups['q'].Success) {
                return ($rule.Url + [System.Uri]::EscapeDataString($m.Groups['q'].Value.Trim()))
            }
            return $rule.Url
        }
    }
    return $null
}

# ----------------------------------------------------------------------------
# Windows-Schnittstellen laden
# ----------------------------------------------------------------------------
$script:NativeReady = $false
$script:NativeError = ''
$script:UiaReady = $false
$script:GuiReady = $false
$script:Synth = $null
$script:VoiceName = ''

function Initialize-Native {
    if ($script:NativeReady) { return $true }
    try {
        if (-not ('GGNative' -as [type])) {
            Add-Type -TypeDefinition $script:NativeSource -Language CSharp -ErrorAction Stop
        }
        $script:NativeReady = $true
    } catch {
        $script:NativeReady = $false
        $script:NativeError = $_.Exception.Message
    }
    return $script:NativeReady
}

function Initialize-Uia {
    if ($script:UiaReady) { return $true }
    try {
        Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
        Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
        $edit = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Edit)
        $hasValue = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::IsValuePatternAvailableProperty, $true)
        $script:UiaEditCond = [System.Windows.Automation.AndCondition]::new(
            [System.Windows.Automation.Condition[]]@($edit, $hasValue))
        $script:UiaReady = $true
    } catch {
        $script:UiaReady = $false
    }
    return $script:UiaReady
}

function Initialize-Gui {
    if ($script:GuiReady) { return }
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    if (Initialize-Native) {
        try { [void][GGNative]::SetProcessDPIAware() } catch { }
    }
    $script:GuiReady = $true
}

function Initialize-Speech {
    $script:Synth = $null
    $script:VoiceName = ''
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $voices = @($synth.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $_.VoiceInfo })
        $pick = $null
        if ($script:S.StimmenName) {
            $pick = $voices | Where-Object { $_.Name -eq $script:S.StimmenName } | Select-Object -First 1
        }
        if (-not $pick) {
            # Am liebsten eine deutsche Stimme. Ohne sie wird nicht gesprochen –
            # eine englische Stimme, die Deutsch vorliest, nimmt niemand ernst.
            $pick = $voices | Where-Object { $_.Culture.Name -like 'de-*' } | Select-Object -First 1
        }
        if ($pick) {
            $synth.SelectVoice($pick.Name)
            $script:VoiceName = $pick.Name
        }
        $synth.Volume = [math]::Max(0, [math]::Min(100, [int]$script:S.Lautstaerke))
        $script:Synth = $synth
    } catch {
        $script:Synth = $null
    }
}

# ----------------------------------------------------------------------------
# Welches Fenster ist vorne?
# ----------------------------------------------------------------------------
function Get-ProcName([int]$ProcId) {
    # bewusst ohne Zwischenspeicher: Windows vergibt Prozessnummern neu
    try {
        return (Get-Process -Id $ProcId -ErrorAction Stop).ProcessName.ToLowerInvariant()
    } catch {
        return ''
    }
}

function Get-FrontWindow {
    $h = [GGNative]::GetForegroundWindow()
    if ($h -eq [IntPtr]::Zero) { return $null }
    $procId = [GGNative]::ProcessId($h)
    if ($procId -le 0) { return $null }
    return @{
        Hwnd   = $h
        ProcId = $procId
        Name   = (Get-ProcName $procId)
        Title  = [GGNative]::Title($h)
    }
}

function Get-ParentInfo([int]$ProcId) {
    try {
        $p = Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId = {0}' -f $ProcId) -ErrorAction Stop
        if ($p -and $p.ParentProcessId) {
            $pp = [int]$p.ParentProcessId
            return @{ ProcId = $pp; Name = (Get-ProcName $pp) }
        }
    } catch { }
    return $null
}

function Get-AppTarget($Front, [bool]$IsBrowser) {
    # Was soll beendet werden? @{ Show = Prozess für den Namen; Procs = Liste von @{ProcId; Name} } oder $null
    if ($Front.ProcId -eq $PID -or -not $Front.Name -or (Test-Protected $Front.Name)) { return $null }
    $me = @{ ProcId = $Front.ProcId; Name = $Front.Name }
    if ($script:AppsBlock.Contains($Front.Name)) {
        return @{ Show = $me; Procs = @($me) }
    }
    if ($IsBrowser) { return $null }
    # z. B. das Steam-Fenster gehört zu "steamwebhelper", ein Spiel zu "cs2" –
    # beide gestartet von "steam". Dann gehen das Fenster und Steam selbst zu.
    $parent = Get-ParentInfo $Front.ProcId
    if ($parent -and $parent.Name -and $parent.ProcId -ne $PID -and
        $script:AppsBlock.Contains($parent.Name) -and -not (Test-Protected $parent.Name)) {
        return @{ Show = $parent; Procs = @($me, $parent) }
    }
    return $null
}

function Get-AppDisplayName($Target) {
    try {
        $p = Get-Process -Id $Target.Show.ProcId -ErrorAction Stop
        if ($p.Description) { return $p.Description }
        return $p.ProcessName
    } catch {
        return $Target.Show.Name
    }
}

function Test-TargetAlive($Target) {
    foreach ($t in $Target.Procs) {
        $p = Get-Process -Id $t.ProcId -ErrorAction SilentlyContinue
        if ($p -and $p.ProcessName.ToLowerInvariant() -eq $t.Name) { return $true }
    }
    return $false
}

function Stop-App($Target) {
    # Erst höflich (wie das X oben rechts), dann – mit HART_BEENDEN=1 – hart.
    # Vor jedem Schritt wird geprüft, ob die Prozessnummer noch zum selben Programm gehört.
    # $true = alle weg
    foreach ($t in $Target.Procs) {
        try {
            $p = Get-Process -Id $t.ProcId -ErrorAction Stop
            if ($p.ProcessName.ToLowerInvariant() -eq $t.Name -and $p.MainWindowHandle -ne [IntPtr]::Zero) {
                [void]$p.CloseMainWindow()
            }
        } catch { }
    }
    for ($i = 0; $i -lt 10; $i++) {
        if (-not (Test-TargetAlive $Target)) { return $true }
        Start-Sleep -Milliseconds 100
    }
    if ($script:S.HartBeenden -ne 1) { return (-not (Test-TargetAlive $Target)) }
    foreach ($t in $Target.Procs) {
        try {
            $p = Get-Process -Id $t.ProcId -ErrorAction Stop
            if ($p.ProcessName.ToLowerInvariant() -eq $t.Name) {
                Stop-Process -Id $t.ProcId -Force -ErrorAction Stop
            }
        } catch { }
    }
    for ($i = 0; $i -lt 20; $i++) {
        if (-not (Test-TargetAlive $Target)) { return $true }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

# ----------------------------------------------------------------------------
# Browser: Adresse lesen und Tab schliessen
# ----------------------------------------------------------------------------
$script:OmniCache = @{}

function Get-OmniboxValue($Front) {
    # liest die Adressleiste über die Windows-Bedienungshilfen (UI Automation)
    # State: 'ok' (Value gesetzt), 'focus' (du tippst gerade), 'none'
    if (-not $script:UiaReady) { return @{ State = 'none' } }
    $key = [int64]$Front.Hwnd
    $el = $null
    if ($script:OmniCache.ContainsKey($key)) {
        $entry = $script:OmniCache[$key]
        if ($entry.Element) {
            $el = $entry.Element
        } elseif ($script:Now -lt $entry.RetryAt) {
            return @{ State = 'none' }
        }
    }
    if (-not $el) {
        try {
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($Front.Hwnd)
            $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $script:UiaEditCond)
        } catch {
            $el = $null
        }
        if ($script:OmniCache.Count -gt 200) { $script:OmniCache.Clear() }
        if (-not $el) {
            $script:OmniCache[$key] = @{ Element = $null; RetryAt = $script:Now + 10 }
            return @{ State = 'none' }
        }
        $script:OmniCache[$key] = @{ Element = $el; RetryAt = 0 }
    }
    try {
        $focus = $el.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::HasKeyboardFocusProperty)
        if ($focus -eq $true) { return @{ State = 'focus' } }
        $v = $el.GetCurrentPropertyValue([System.Windows.Automation.ValuePattern]::ValueProperty)
        if ($v -is [string]) { return @{ State = 'ok'; Value = $v } }
    } catch {
        $script:OmniCache.Remove($key)
    }
    return @{ State = 'none' }
}

function Get-PageInfo($Front) {
    # Was zeigt der Browser gerade? Erst die Adressleiste, sonst der Fenstertitel.
    $o = Get-OmniboxValue $Front
    if ($o.State -eq 'focus') { return @{ State = 'focus' } }
    if ($o.State -eq 'ok' -and $o.Value) {
        $parts = ConvertTo-UrlParts $o.Value
        if ($parts) {
            return @{ State = 'ok'; Source = 'url'; Url = $o.Value; Parts = $parts; Title = $Front.Title }
        }
    }
    $tu = Get-TitleUrl $Front.Title
    if ($tu) {
        return @{ State = 'ok'; Source = 'title'; Url = $tu; Parts = (ConvertTo-UrlParts $tu); Title = $Front.Title }
    }
    return @{ State = 'none' }
}

function Test-SamePage($A, $B) {
    if ($A.State -ne 'ok' -or $B.State -ne 'ok') { return $false }
    if ($A.Source -ne $B.Source) { return $false }
    if ($A.Source -eq 'title') { return ($A.Title -ceq $B.Title) }
    return ($A.Url -ceq $B.Url)
}

function Test-ModifierDown {
    foreach ($vk in @(0x10, 0x11, 0x12, 0x5B, 0x5C)) {
        if ([GGNative]::KeyDown($vk)) { return $true }
    }
    return $false
}

function Close-BrowserTab($Front, $Page) {
    # 'closed' = Tab ist zu, 'changed' = inzwischen gewechselt, 'error' = klappt nicht
    if ([GGNative]::GetForegroundWindow() -ne $Front.Hwnd) { return 'changed' }
    $Front.Title = [GGNative]::Title($Front.Hwnd)
    if (-not (Test-SamePage (Get-PageInfo $Front) $Page)) { return 'changed' }
    # Nicht mitten in einer Tastenkombination von dir zuschlagen
    # (Strg+Umschalt+W würde das ganze Fenster schliessen).
    $waited = 0
    while (Test-ModifierDown) {
        if ($waited -ge 1500) { return 'changed' }
        Start-Sleep -Milliseconds 100
        $waited += 100
    }
    if ([GGNative]::GetForegroundWindow() -ne $Front.Hwnd) { return 'changed' }
    [GGNative]::CtrlW()
    Start-Sleep -Milliseconds 450
    if (-not [GGNative]::IsWindow($Front.Hwnd)) { return 'closed' }
    $Front.Title = [GGNative]::Title($Front.Hwnd)
    if (Test-SamePage (Get-PageInfo $Front) $Page) { return 'error' }
    return 'closed'
}

# ----------------------------------------------------------------------------
# Warnung: Vollbild + Ton + Stimme
# ----------------------------------------------------------------------------
$script:OverlayDone = $true
$script:Player = $null

function Start-AlarmSound {
    if ($script:S.Alarmton -ne 1 -or $script:S.Lautstaerke -le 0) { return }
    try {
        $wav = Join-Path $env:WINDIR 'Media\Windows Critical Stop.wav'
        if ($script:S.Lautstaerke -lt 50) {
            # Windows bietet hier keine Lautstärke pro Ton: leise = der dezentere Systemton
            [System.Media.SystemSounds]::Asterisk.Play()
        } elseif (Test-Path -LiteralPath $wav) {
            $script:Player = New-Object System.Media.SoundPlayer $wav
            $script:Player.Play()
        } else {
            [System.Media.SystemSounds]::Hand.Play()
        }
    } catch { }
}

function Start-Speech([string]$Text) {
    if ($script:S.Stimme -ne 1 -or -not $script:Synth -or -not $script:VoiceName) { return }
    try {
        $script:Synth.SpeakAsyncCancelAll()
        [void]$script:Synth.SpeakAsync($Text)
    } catch { }
}

$script:UiReady = $null
$script:UiError = ''

function Initialize-Ui {
    # lädt Sperrbildschirm, Menü und Einstellungen (grindguard-ui.cs) einmal;
    # $false = es bleibt beim einfachen Dialogfenster
    if ($null -ne $script:UiReady) { return $script:UiReady }
    try {
        Initialize-Gui
        if (-not ('GGPlates' -as [type])) {
            if (-not (Test-Path -LiteralPath $script:UiFile)) { throw ('Datei fehlt: {0}' -f $script:UiFile) }
            $src = [System.IO.File]::ReadAllText($script:UiFile, [System.Text.Encoding]::UTF8)
            Add-Type -TypeDefinition $src -Language CSharp -ReferencedAssemblies System.Windows.Forms, System.Drawing -IgnoreWarnings -ErrorAction Stop
        }
        $script:UiReady = $true
    } catch {
        $script:UiReady = $false
        $script:UiError = $_.Exception.Message
        Write-LogOnce ('HINWEIS: Oberfläche nicht verfügbar ({0}) – einfache Anzeige.' -f $script:UiError)
    }
    return $script:UiReady
}

function Show-FallbackPopup([int]$Seconds, [string]$Head, [string]$Quote, [string]$Detail) {
    try {
        $shell = New-Object -ComObject WScript.Shell
        $text = "{0}`r`n`r`n{1}`r`n`r`n{2}" -f $Head, $Quote, $Detail
        [void]$shell.Popup($text, $Seconds, 'GrindGuard', 0x10 + 0x1000)
    } catch { }
}

function Get-QuoteLines {
    $q = New-Object System.Collections.Generic.List[string]
    if ($script:S.Ton -eq 'ruhig') { foreach ($c in $script:CalmQuotes) { $q.Add($c) } }
    foreach ($l in (Get-ConfigLines $script:QuotesFile)) {
        $t = $l.Trim()
        if ($t -ne '' -and -not $t.StartsWith('#')) { $q.Add($t) }
    }
    return [string[]]$q.ToArray()
}

function Get-Plate([int]$N, [int]$Hunt) {
    # welches Design die Sperre hat: fest gewählt oder je nach Ton abwechselnd
    if ($script:S.Design -and $script:S.Design -ne 'wechselnd') { return $script:S.Design }
    if ($Hunt -ge 3) {
        if ($script:S.Ton -eq 'ruhig') { return 'papier' }
        return 'lexikon'
    }
    $set = $script:PlateSets[$script:S.Ton]
    if (-not $set) { $set = $script:PlateSets['brutal'] }
    return $set[([math]::Max(1, $N) - 1) % $set.Count]
}

function New-LockContent([string]$Plate, [string]$Head, [string]$Quote, [string]$Detail, [string]$Counter, [int]$N, [int]$Hunt) {
    $c = @{ Plate = $Plate; Head = $Head; Quote = $Quote; Detail = $Detail; Counter = $Counter; Word = ''; WordClass = ''; Line = '' }
    if ($Plate -eq 'lexikon') {
        $e = $script:Lexikon[([math]::Max(1, $N) - 1 + (Get-Date).DayOfYear) % $script:Lexikon.Count]
        if ($Hunt -ge 3) { $e = $script:LexikonJagd }
        $c.Word = $e.W
        $c.WordClass = $e.K
        $c.Quote = $e.D
    }
    if ($Plate -eq 'kobalt') {
        $c.Line = $script:KobaltLines[([math]::Max(1, $N) - 1) % $script:KobaltLines.Count]
    }
    return $c
}

function Show-Warning([int]$Seconds, $Content, [string]$Speak) {
    # Gibt 'vollbild' oder 'dialog' zurück. $Content kommt von New-LockContent.
    # Auf jedem Bildschirm ein Sperrfenster; Taskleiste nach hinten, Windows-Taste und
    # Alt+Tab sind bis zum Ende aus. Strg+Alt+Entf lässt Windows immer zu.
    if ($Seconds -lt 3) { $Seconds = 3 }
    if ($Seconds -gt 300) { $Seconds = 300 }
    if (-not $Speak) { $Speak = $Content.Head }
    $forms = New-Object System.Collections.ArrayList
    $mode = 'vollbild'
    try {
        Initialize-Gui
        if (-not (Initialize-Ui)) { throw ('Oberfläche nicht geladen: {0}' -f $script:UiError) }
        $c = New-Object GGLockContent
        $c.Plate = [string]$Content.Plate
        $c.Head = [string]$Content.Head
        $c.Quote = [string]$Content.Quote
        $c.Detail = [string]$Content.Detail
        $c.Counter = [string]$Content.Counter
        $c.Word = [string]$Content.Word
        $c.WordClass = [string]$Content.WordClass
        $c.Line = [string]$Content.Line
        $c.Page = [string[]]@(Get-QuoteLines)
        [GGLockWindow]::Done = $false
        $fade = [System.Windows.Forms.SystemInformation]::UIEffectsEnabled
        foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) {
            $f = New-Object GGLockWindow -ArgumentList $scr.Bounds, $c
            if ($fade) { $f.Opacity = 0 }
            [void]$forms.Add($f)
            $f.Show()
        }
        if ($forms.Count -eq 0) { throw 'Kein Bildschirm gefunden' }
        $handles = [IntPtr[]]@($forms | ForEach-Object { $_.Handle })
        [GGLockGuard]::Front($handles[0])
        if (-not [GGLockGuard]::Engage()) { Write-LogOnce 'HINWEIS: Tastensperre (Windows-Taste, Alt+Tab) nicht verfügbar.' }
        [System.Windows.Forms.Application]::DoEvents()
        $visible = 0
        foreach ($f in $forms) { if ($f.Visible) { $visible++ } }
        if ($visible -eq 0) { throw 'Fenster nicht sichtbar' }

        Start-AlarmSound
        $delay = 0
        if ($script:S.Alarmton -eq 1) { $delay = 1200 }
        $start = [DateTime]::UtcNow
        $total = [double]$Seconds * 1000
        $end = $start.AddSeconds($Seconds)
        $spoken = $false
        $shown = -1
        $opaque = -not $fade
        $front = 0
        while ($true) {
            $nowUtc = [DateTime]::UtcNow
            $left = [int][math]::Ceiling(($end - $nowUtc).TotalSeconds)
            if ($left -le 0) { break }
            if (Test-Path -LiteralPath $script:StopFile) { break }
            $elapsed = ($nowUtc - $start).TotalMilliseconds
            if (-not $opaque) {
                # sanft einblenden (150 ms); wer Animationen abgeschaltet hat, bekommt es sofort
                $o = [math]::Min(1.0, $elapsed / 150.0)
                foreach ($f in $forms) { $f.Opacity = $o }
                if ($o -ge 1.0) { $opaque = $true }
            }
            $progress = [single][math]::Max(0, ($end - $nowUtc).TotalMilliseconds / $total)
            foreach ($f in $forms) { $f.Poster.SetTime($progress, $left) }
            if ($left -ne $shown) {
                $shown = $left
                foreach ($f in $forms) { $f.TopMost = $true }
            }
            if ($elapsed -ge $front) {
                # vorne bleiben – auch wenn sich ein anderes Fenster dazwischendrängt
                $front = $elapsed + 400
                if (-not [GGLockGuard]::IsFront($handles)) { [GGLockGuard]::Front($handles[0]) }
            }
            if (-not $spoken -and $elapsed -ge $delay) {
                $spoken = $true
                Start-Speech ('{0} {1}' -f $Speak, $Content.Quote)
            }
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 33
        }
    } catch {
        Write-Log ('FEHLER: Vollbild-Warnung konnte nicht angezeigt werden ({0}) – nehme das Dialogfenster.' -f $_.Exception.Message)
        $mode = 'dialog'
    } finally {
        if ('GGLockGuard' -as [type]) { [GGLockGuard]::Release() }
        if ('GGLockWindow' -as [type]) { [GGLockWindow]::Done = $true }
        foreach ($f in $forms) {
            try { [GGLockGuard]::MarkFullscreen($f.Handle, $false) } catch { }
            try { $f.Close(); $f.Dispose() } catch { }
        }
    }
    if ($mode -eq 'dialog') {
        Start-AlarmSound
        Start-Speech ('{0} {1}' -f $Speak, $Content.Quote)
        Show-FallbackPopup $Seconds $Content.Head $Content.Quote $Content.Detail
    }
    return $mode
}

# ----------------------------------------------------------------------------
# Ausrutscher zählen und bestrafen
# ----------------------------------------------------------------------------
function Get-TodayCount {
    if (-not (Test-Path -LiteralPath $script:StrikesFile)) { return 0 }
    $day = (Get-Date).ToString('yyyy-MM-dd', $script:Inv)
    $n = 0
    foreach ($l in (Get-ConfigLines $script:StrikesFile)) {
        if ($l.StartsWith($day)) { $n++ }
    }
    return $n
}

function Get-LockSeconds([int]$N) {
    $s = $script:S.SperrStart + $script:S.SperrPlus * ($N - 1)
    if ($s -gt $script:S.SperrMax) { $s = $script:S.SperrMax }
    return $s
}

function Get-Quote([int]$N) {
    $d0 = (Get-Date).DayOfYear
    if ($script:S.Ton -eq 'ruhig') { return $script:CalmQuotes[($N - 1 + $d0) % $script:CalmQuotes.Count] }
    $q = New-Object System.Collections.Generic.List[string]
    foreach ($l in (Get-ConfigLines $script:QuotesFile)) {
        $t = $l.Trim()
        if ($t -ne '' -and -not $t.StartsWith('#')) { $q.Add($l.TrimEnd()) }
    }
    if ($q.Count -eq 0) { return 'Zurück an die Arbeit. Jetzt.' }
    $d = (Get-Date).DayOfYear
    return $q[($N - 1 + $d) % $q.Count]
}

function Get-WarnTexts([int]$N, [string]$Name, [bool]$Closed, [int]$Hunt = 0) {
    if ($Closed) { $what = '{0} wurde geschlossen.' -f $Name } else { $what = '{0} ist noch offen. Schliess es. Jetzt.' -f $Name }
    if ($Hunt -ge 3) {
        if ($script:S.Ton -eq 'ruhig') {
            return @{ Head = 'Du suchst gerade einen Umweg.'; Speak = 'Du suchst gerade einen Umweg.'; Detail = ('{0} Das war der {1}. Versuch in zehn Minuten. Steh kurz auf, dann zurück an die Aufgabe.' -f $what, $Hunt) }
        }
        return @{ Head = 'Jagd erkannt.'; Speak = 'Jagd erkannt.'; Detail = ('{0} Das ist der {1}. Umweg in zehn Minuten. Die Sperre steht jetzt auf dem Maximum.' -f $what, $Hunt) }
    }
    if ($script:S.Ton -eq 'ruhig') { return @{ Head = 'Kurz zurück.'; Speak = 'Kurz zurück.'; Detail = "$what Kein Drama. Zurück zur Aufgabe." } }
    if ($script:S.Ton -eq 'direkt') { return @{ Head = 'Ablenkung gesperrt.'; Speak = 'Ablenkung gesperrt.'; Detail = ('{0} Ausrutscher Nr. {1} heute.' -f $what, $N) } }
    switch ($N) {
        1 { return @{ Head = 'Stopp.'; Speak = 'Stopp.'; Detail = "$what Erster Ausrutscher heute – sorg dafür, dass es der letzte bleibt." } }
        2 { return @{ Head = 'Schon wieder.'; Speak = 'Schon wieder.'; Detail = "$what Zweiter Ausrutscher heute." } }
        { $_ -eq 3 -or $_ -eq 4 } {
            return @{ Head = ('Nr. {0} heute.' -f $N); Speak = ('Ausrutscher Nummer {0} heute.' -f $N); Detail = "$what Das wird gerade zur Gewohnheit." }
        }
        default {
            return @{ Head = ('Nr. {0} heute.' -f $N); Speak = ('Ausrutscher Nummer {0} heute.' -f $N); Detail = "$what Das ist kein Ausrutscher mehr. Das ist ein Muster – und nur du kannst es brechen." }
        }
    }
}

function Invoke-Punish([string]$Kind, [string]$Name, [bool]$Closed) {
    $clean = $Name -replace '[|\r\n]', ''
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $script:Inv)
    try {
        [System.IO.File]::AppendAllText($script:StrikesFile, ('{0}|{1}|{2}' -f $ts, $Kind, $clean) + "`r`n", $script:Utf8)
    } catch { }
    $n = Get-TodayCount
    if ($n -lt 1) { $n = 1 }
    $secs = Get-LockSeconds $n
    # Jagd-Erkennung: Ausrutscher der letzten 10 Minuten zählen
    $keep = New-Object System.Collections.Generic.List[long]
    foreach ($x in $script:RecentStrikes) { if (($script:Now - $x) -lt 600) { $keep.Add($x) } }
    $keep.Add($script:Now)
    $script:RecentStrikes = $keep
    $hunt = 0
    if ($script:S.Jagd -eq 1 -and $keep.Count -ge 3) {
        $hunt = $keep.Count
        $secs = $script:S.SperrMax
    }
    $t = Get-WarnTexts $n $clean $Closed $hunt
    $quote = Get-Quote $n
    $label = 'Ausrutscher {0:00} · {1} s' -f $n, $secs
    if ($hunt -gt 0) {
        $label += ' · Jagd'
        Write-Log ('Ausrutscher Nr. {0} heute: {1} – Jagd erkannt ({2} in 10 Minuten), Bildschirm {3} s gesperrt' -f $n, $clean, $hunt, $secs)
    } else {
        Write-Log ('Ausrutscher Nr. {0} heute: {1} – Bildschirm {2} s gesperrt' -f $n, $clean, $secs)
    }
    $content = New-LockContent (Get-Plate $n $hunt) $t.Head $quote $t.Detail $label $n $hunt
    [void](Show-Warning $secs $content $t.Speak)
    Invoke-GoBack
}

function Invoke-GoBack {
    # nach der Sperre zurück zum letzten erlaubten Fenster
    if ($script:S.Zurueck -ne 1 -or -not $script:LastGood) { return }
    $g = $script:LastGood
    if ($g.Name -eq $script:EnfName) { return }          # dieselbe App (z. B. der Browser) bleibt vorne
    try {
        if (-not [GGNative]::IsWindow($g.Hwnd)) { return }
        if ([GGNative]::IsIconic($g.Hwnd)) { [void][GGNative]::ShowWindowAsync($g.Hwnd, 9) }   # 9 = wiederherstellen
        if ([GGNative]::SetForegroundWindow($g.Hwnd)) {
            Write-Log ('Zurück zu {0}' -f $g.Name)
        }
    } catch { }
}

function Send-Notice([string]$Title, [string]$Text) {
    if (-not $script:Tray) { return }
    try {
        $script:Tray.ShowBalloonTip(8000, $Title, $Text, [System.Windows.Forms.ToolTipIcon]::Warning)
    } catch { }
}

function Invoke-Enforce([string]$Kind, [string]$Name, $Front, $Extra) {
    $target = '{0}:{1}' -f $Kind, $Name
    $script:Enforced = $true
    if ($target -eq $script:CoolTarget -and $script:Now -lt $script:CoolUntil) { return }
    $script:EnfName = $Front.Name
    $closed = $false
    if ($Kind -eq 'web') {
        $r = Close-BrowserTab $Front $Extra
        if ($r -eq 'changed') { return }
        $closed = ($r -eq 'closed')
    } else {
        $closed = Stop-App $Extra
    }
    if ($closed) {
        $script:Fails = 0
        $script:FailTarget = ''
    } else {
        if ($target -eq $script:FailTarget) {
            $script:Fails++
        } else {
            $script:FailTarget = $target
            $script:Fails = 1
        }
        if ($script:Fails -ge 3) {
            # Schutz vor einer Endlosschleife aus Warnungen, falls das Schliessen
            # technisch nicht klappt (z. B. ein Spiel, das als Administrator läuft).
            $script:CoolTarget = $target
            $script:CoolUntil = $script:Now + 300
            $script:Fails = 0
            $script:FailTarget = ''
            Write-Log ('FEHLER: {0} liess sich dreimal nicht schliessen – 5 Minuten Ruhe für dieses Ziel. Prüfen: grind doctor' -f $Name)
            Write-Status
            Send-Notice 'GrindGuard' ('{0} liess sich nicht schliessen. Prüfen: ~\GrindGuard\grind doctor' -f $Name)
            return
        }
    }
    Invoke-Punish $Kind $Name $closed
}

# ----------------------------------------------------------------------------
# Pause und aktive Zeiten
# ----------------------------------------------------------------------------
function Get-PauseEnd {
    if (-not (Test-Path -LiteralPath $script:PauseFile)) { return $null }
    try {
        $t = ([System.IO.File]::ReadAllText($script:PauseFile)).Trim()
        if ($t -match '^[0-9]{1,12}$') { return [long]$t }
    } catch { }
    return $null
}

function Test-Paused {
    if (-not (Test-Path -LiteralPath $script:PauseFile)) { return $false }
    $p = Get-PauseEnd
    if ($p -and $script:Now -lt $p) { return $true }
    Remove-Item -LiteralPath $script:PauseFile -Force -ErrorAction SilentlyContinue
    if ($p) {
        Write-Log 'Pause vorbei'
        Send-Notice 'GrindGuard' 'Pause vorbei. Zurück an die Arbeit.'
    }
    return $false
}

function Test-ActiveTime {
    $d = Get-Date
    $dow = [int]$d.DayOfWeek
    if ($dow -eq 0) { $dow = 7 }
    $von = $script:S.ZeitVon
    $bis = $script:S.ZeitBis
    if ($von -eq $bis -or ($von -eq 0 -and $bis -eq 2400)) {
        return $script:S.Tage.Contains([string]$dow)
    }
    $hm = $d.Hour * 100 + $d.Minute
    if ($von -lt $bis) {
        return ($hm -ge $von -and $hm -lt $bis -and $script:S.Tage.Contains([string]$dow))
    }
    # Zeitfenster über Mitternacht (z. B. 22:00-02:00)
    if ($hm -ge $von) { return $script:S.Tage.Contains([string]$dow) }
    if ($hm -lt $bis) {
        # gehört zum Abend davor: Mo 22:00 bis Di 02:00 ist eine Montags-Sitzung
        $prev = $dow - 1
        if ($prev -lt 1) { $prev = 7 }
        return $script:S.Tage.Contains([string]$prev)
    }
    return $false
}

# ----------------------------------------------------------------------------
# Der Wächter selbst
# ----------------------------------------------------------------------------
function Reset-GuardState {
    $script:Now = Get-Now
    $script:Loops = 0
    $script:PrevKey = ''
    $script:IsBrowser = $false
    $script:AppTarget = $null
    $script:LastUrlOk = ''
    $script:Fails = 0
    $script:FailTarget = ''
    $script:CoolTarget = ''
    $script:CoolUntil = 0
    $script:Reported = @{}
    $script:RecentStrikes = New-Object System.Collections.Generic.List[long]
    $script:LastGood = $null
    $script:EnfName = ''
    $script:Enforced = $false
    $script:FocusEnd = 0
    $script:Readable = New-Object System.Collections.Generic.List[string]
    $script:TitleOnly = New-Object System.Collections.Generic.List[string]
}

# ----------------------------------------------------------------------------
# Zustand für "status" und "doctor" (schreibt nur der Wächter)
# ----------------------------------------------------------------------------
function Write-Status {
    try {
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('pid=' + $PID)
        $lines.Add('herzschlag=' + $script:Now)
        $lines.Add('browser_lesbar=' + ($script:Readable -join ', '))
        $lines.Add('browser_nur_titel=' + ($script:TitleOnly -join ', '))
        if ($script:Now -lt $script:CoolUntil) {
            $lines.Add('ausgesetzt=' + ($script:CoolTarget -replace '^[a-z]+:', ''))
            $lines.Add('ausgesetzt_bis=' + $script:CoolUntil)
        }
        $lines.Add('fokus_bis=' + $script:FocusEnd)
        [System.IO.File]::WriteAllText($script:StatusFile, (($lines -join "`r`n") + "`r`n"), $script:Utf8)
    } catch { }
}

function Get-StatusValue([string]$Key) {
    foreach ($l in (Get-ConfigLines $script:StatusFile)) {
        if ($l.StartsWith($Key + '=')) { return $l.Substring($Key.Length + 1) }
    }
    return ''
}

function Invoke-RotateLog {
    try {
        $fi = New-Object System.IO.FileInfo $script:LogFile
        if ($fi.Exists -and $fi.Length -gt 524288) {
            Move-Item -LiteralPath $script:LogFile -Destination ($script:LogFile + '.alt') -Force
        }
    } catch { }
}

# ----------------------------------------------------------------------------
# Fokus-Sitzung: Listen eingefroren, pause/stop/uninstall gesperrt
# ----------------------------------------------------------------------------
function Get-FocusEnd {
    if (-not (Test-Path -LiteralPath $script:FocusFile)) { return $null }
    try {
        $t = ([System.IO.File]::ReadAllText($script:FocusFile)).Trim()
        if ($t -match '^[0-9]{1,12}$') { return [long]$t }
    } catch { }
    return $null
}

function Test-FocusActive {
    $f = Get-FocusEnd
    if ($f -and (Get-Now) -lt $f) {
        $script:FocusEnd = $f
        return $true
    }
    $script:FocusEnd = 0
    return $false
}

function Assert-NoFocus([string]$What) {
    $f = Get-FocusEnd
    if ($f -and (Get-Now) -lt $f) {
        Write-Output ('Fokus-Sitzung läuft bis {0} Uhr – "{1}" ist bis dahin gesperrt.' -f (Format-Clock $f), $What)
        Write-Output 'Notausstieg (10 Minuten Wartezeit): ~\GrindGuard\grind notausstieg'
        exit 1
    }
}

function Invoke-WebCheck($Front) {
    $page = Get-PageInfo $Front
    if ($page.State -ne 'ok') { return }
    $note = '{0}:{1}' -f $Front.Name, $page.Source
    if (-not $script:Reported.ContainsKey($note)) {
        $script:Reported[$note] = $true
        if ($page.Source -eq 'url') {
            Write-Log ('Browser-Adresse lesbar: {0}' -f $Front.Name)
            if (-not $script:Readable.Contains($Front.Name)) { $script:Readable.Add($Front.Name) }
            [void]$script:TitleOnly.Remove($Front.Name)
        } else {
            Write-Log ('HINWEIS: Adresse in {0} gerade nicht lesbar – erkenne Seiten am Fenstertitel.' -f $Front.Name)
            if (-not $script:Readable.Contains($Front.Name) -and -not $script:TitleOnly.Contains($Front.Name)) { $script:TitleOnly.Add($Front.Name) }
        }
        Write-Status
    }
    $sig = '{0}|{1}|{2}|{3}' -f [int64]$Front.Hwnd, $page.Source, $page.Url, $Front.Title
    if ($sig -eq $script:LastUrlOk) { return }
    $name = Get-BlockName $page.Parts
    if (-not $name -and $page.Source -eq 'url') {
        # Zeigt die Adressleiste die Suchbegriffe nicht an, stehen sie im Fenstertitel
        $ts = Get-TitleUrl $Front.Title -SearchOnly
        if ($ts) { $name = Get-BlockName (ConvertTo-UrlParts $ts) }
    }
    if ($name) {
        $script:LastUrlOk = ''
        Invoke-Enforce 'web' $name $Front $page
    } else {
        $script:LastUrlOk = $sig
    }
}

function Invoke-Check {
    $script:Now = Get-Now
    $script:Loops++
    if ($script:Loops % 15 -eq 0) {
        Import-All              # Änderungen an den Listen übernehmen
        $script:PrevKey = ''
        $script:LastUrlOk = ''
        if ($script:S.StimmenName -ne $script:VoiceSetting) {
            $script:VoiceSetting = $script:S.StimmenName
            Initialize-Speech
        }
        Invoke-RotateLog
    }
    if ($script:Loops % 10 -eq 0) { Write-Status }
    if (Test-FocusActive) {
        if ($script:ConfSrc -ne $script:FocusDir -and (Test-Path -LiteralPath $script:FocusDir)) {
            Set-ConfSrc $script:FocusDir
            Import-All
            $script:PrevKey = ''
            $script:LastUrlOk = ''
            Write-Log ('Fokus-Sitzung läuft bis {0} Uhr – Regeln eingefroren' -f (Format-Clock $script:FocusEnd))
            Write-Status
        }
    } else {
        if ($script:ConfSrc -eq $script:FocusDir) {
            Set-ConfSrc $script:ConfDir
            Import-All
            $script:PrevKey = ''
            $script:LastUrlOk = ''
            Remove-Item -LiteralPath $script:FocusFile -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $script:FocusDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log 'Fokus-Sitzung beendet'
            Send-Notice 'GrindGuard' 'Fokus-Sitzung vorbei. Stark.'
            Write-Status
        }
        if (Test-Paused) { return }
        if (-not (Test-ActiveTime)) { return }
    }
    $f = Get-FrontWindow
    if (-not $f -or $f.ProcId -eq $PID) { return }
    $key = '{0}|{1}' -f [int64]$f.Hwnd, $f.ProcId
    if ($key -ne $script:PrevKey) {
        $script:PrevKey = $key
        $script:LastUrlOk = ''
        $script:IsBrowser = ($script:Browsers -contains $f.Name)
        $script:AppTarget = Get-AppTarget $f $script:IsBrowser
    }
    $script:Enforced = $false
    if ($script:AppTarget) {
        $target = $script:AppTarget
        $script:PrevKey = ''
        Invoke-Enforce 'app' (Get-AppDisplayName $target) $f $target
        return
    }
    if ($script:IsBrowser) { Invoke-WebCheck $f }
    if (-not $script:Enforced -and -not ($script:NoReturn -contains $f.Name)) {
        # Ziel für die Rückkehr nach einer Sperre
        $script:LastGood = @{ Hwnd = $f.Hwnd; Name = $f.Name }
    }
}

$script:Tray = $null
$script:TrayText = ''
$script:TrayState = ''
$script:TrayIcons = @{}
$script:MenuHeader = $null
$script:PendingTest = $null
$script:SeenConfig = 0

function Get-GuardState {
    # 'fokus', 'pause' oder 'aktiv'
    $now = Get-Now
    $fe = Get-FocusEnd
    if ($fe -and $now -lt $fe) { return 'fokus' }
    $pe = Get-PauseEnd
    if ($pe -and $now -lt $pe) { return 'pause' }
    return 'aktiv'
}

function Open-Settings([string]$Page) {
    if (-not (Initialize-Ui)) {
        Send-Notice 'GrindGuard' 'Die Einstellungen lassen sich hier nicht öffnen – ich öffne den Ordner mit den Listen.'
        try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $script:ConfDir) } catch { }
        return
    }
    try {
        [GGSettings]::OpenAsync($script:Base, $script:Version, $script:UpdateRepo, [string[]]$script:Protected, $Page)
    } catch {
        Write-LogOnce ('FEHLER: Einstellungen: {0}' -f $_.Exception.Message)
    }
}

function Set-Pause([int]$Minutes) {
    # gibt eine Meldung zurück; wird vom Befehl "pause", vom Menü und von den Einstellungen benutzt
    $fe = Get-FocusEnd
    if ($fe -and (Get-Now) -lt $fe) { return ('Fokus-Sitzung läuft bis {0} Uhr – keine Pause.' -f (Format-Clock $fe)) }
    if ($Minutes -lt 1) { $Minutes = 1 }
    if ($Minutes -gt 120) { $Minutes = 120 }
    if (-not (Test-Path -LiteralPath $script:StateDir)) { [void](New-Item -ItemType Directory -Path $script:StateDir -Force) }
    $end = (Get-Now) + $Minutes * 60
    [System.IO.File]::WriteAllText($script:PauseFile, [string]$end, $script:Utf8)
    Write-Log ('Pause: {0} Minuten, bis {1} Uhr' -f $Minutes, (Format-Clock $end))
    return ('Pause: {0} Minuten, bis {1} Uhr. Danach ist der Wächter automatisch wieder scharf.' -f $Minutes, (Format-Clock $end))
}

function Invoke-TrayFocus([int]$Minutes) {
    # läuft schon eine Sitzung, verlängert der Klick um so viele Minuten
    $fe = Get-FocusEnd
    $now = Get-Now
    if ($fe -and $now -lt $fe) { $Minutes = [int][math]::Ceiling(($fe - $now) / 60) + $Minutes }
    Send-Notice 'GrindGuard' (Start-FocusSession $Minutes)
    Update-Tray
}

function Invoke-TestLock([string]$Plate) {
    Import-All
    if ($script:PlateNames -notcontains $Plate) { $Plate = Get-Plate 1 0 }
    $content = New-LockContent $Plate 'Testalarm.' (Get-Quote 1) 'So sieht es aus, wenn du erwischt wirst. Das hier ist nur ein Test.' 'Test · 6 s' 1 0
    return (Show-Warning 6 $content 'Testalarm.')
}

function Invoke-UiRequest([string]$Request) {
    # Wünsche aus dem Einstellungsfenster (läuft im eigenen Thread) hier im Wächter ausführen
    $parts = $Request.Split(':')
    $arg = ''
    if ($parts.Count -gt 1) { $arg = $parts[1] }
    switch ($parts[0]) {
        'test'   { [void](Invoke-TestLock $arg) }
        'fokus'  { if ($arg -match '^[0-9]{1,3}$') { Send-Notice 'GrindGuard' (Start-FocusSession ([int]$arg)) } }
        'pause'  { if ($arg -match '^[0-9]{1,3}$') { Send-Notice 'GrindGuard' (Set-Pause ([int]$arg)) } }
        'weiter' { Remove-Item -LiteralPath $script:PauseFile -Force -ErrorAction SilentlyContinue; Write-Log 'Pause beendet' }
    }
    Update-Tray
}

function New-TrayItem($Parent, [string]$Text, [scriptblock]$Action) {
    $it = New-Object System.Windows.Forms.ToolStripMenuItem $Text
    if ($Action) { $it.Add_Click($Action) }
    if ($Parent -is [System.Windows.Forms.ToolStripMenuItem]) { [void]$Parent.DropDownItems.Add($it) } else { [void]$Parent.Items.Add($it) }
    return $it
}

function Add-TraySeparator($Parent) {
    $sep = New-Object System.Windows.Forms.ToolStripSeparator
    if ($Parent -is [System.Windows.Forms.ToolStripMenuItem]) { [void]$Parent.DropDownItems.Add($sep) } else { [void]$Parent.Items.Add($sep) }
}

function New-Tray {
    try {
        $ui = Initialize-Ui
        $t = New-Object System.Windows.Forms.NotifyIcon
        if ($ui) {
            $size = [System.Windows.Forms.SystemInformation]::SmallIconSize.Width
            foreach ($st in @('aktiv', 'pause', 'fokus')) { $script:TrayIcons[$st] = [GGBrand]::TrayIcon($size, $st) }
            $t.Icon = $script:TrayIcons['aktiv']
        } else {
            $t.Icon = [System.Drawing.SystemIcons]::Application
        }
        $t.Text = 'GrindGuard – aktiv'
        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        if ($ui) {
            $script:MenuTheme = [GGMenuTheme]::Current()
            $script:MenuHeader = New-Object GGMenuHeader -ArgumentList $script:MenuTheme
            [void]$menu.Items.Add($script:MenuHeader)
            Add-TraySeparator $menu
        }
        $script:MenuFocus = New-TrayItem $menu 'Fokus-Sitzung' $null
        foreach ($m in @(25, 50, 90)) {
            $it = New-TrayItem $script:MenuFocus ('{0} Minuten' -f $m) { param($itemSender, $clickArgs) Invoke-TrayFocus ([int]$itemSender.Tag) }
            $it.Tag = $m
        }
        $script:MenuPause = New-TrayItem $menu 'Pause' $null
        $script:MenuPauseItems = @()
        foreach ($m in @(10, 20, 30)) {
            $it = New-TrayItem $script:MenuPause ('{0} Minuten' -f $m) { param($itemSender, $clickArgs) Send-Notice 'GrindGuard' (Set-Pause ([int]$itemSender.Tag)); Update-Tray }
            $it.Tag = $m
            $script:MenuPauseItems += $it
        }
        $script:MenuBlock = New-TrayItem $menu 'Sperren' $null
        if (-not $ui) { $script:MenuBlock.Visible = $false }
        $script:MenuResume = New-TrayItem $script:MenuPause 'Pause beenden' {
            Remove-Item -LiteralPath $script:PauseFile -Force -ErrorAction SilentlyContinue
            Write-Log 'Pause beendet'
            Send-Notice 'GrindGuard' 'Pause beendet. Der Wächter ist wieder scharf.'
            Update-Tray
        }
        Add-TraySeparator $menu
        [void](New-TrayItem $menu 'Einstellungen …' { Open-Settings 'Heute' })
        [void](New-TrayItem $menu 'Was ist gesperrt?' { Open-Settings 'Sperren' })
        [void](New-TrayItem $menu 'Sperre testen' { $script:PendingTest = 'auto' })
        Add-TraySeparator $menu
        $more = New-TrayItem $menu 'Mehr' $null
        [void](New-TrayItem $more 'Nach Updates suchen …' { Open-Settings 'Update' })
        [void](New-TrayItem $more 'Ordner mit den Listen' { try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $script:ConfDir) } catch { } })
        [void](New-TrayItem $more 'Protokoll' { try { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $script:LogFile) } catch { } })
        Add-TraySeparator $more
        $script:MenuStop = New-TrayItem $more 'Wächter anhalten (bis zur nächsten Anmeldung)' {
            if ((Get-GuardState) -eq 'fokus') { Send-Notice 'GrindGuard' 'Während der Fokus-Sitzung geht das nicht.'; return }
            Write-Log 'Angehalten (über das Menü)'
            try { [System.IO.File]::WriteAllText($script:StopFile, 'stop', $script:Utf8) } catch { }
        }
        $script:MenuUninstall = New-TrayItem $more 'GrindGuard deinstallieren …' {
            if ((Get-GuardState) -eq 'fokus') { Send-Notice 'GrindGuard' 'Während der Fokus-Sitzung geht das nicht.'; return }
            Start-Process -FilePath $script:PsExe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" deinstallieren' -f $script:SelfPath) -WindowStyle Hidden -WorkingDirectory $env:TEMP
        }
        $script:MenuUninstall.Tag = 'gefahr'
        if ($ui) { [GGTray]::Style($menu, $script:MenuTheme) }
        $menu.Add_Opening({ Update-TrayMenu })
        $t.ContextMenuStrip = $menu
        # Linksklick öffnet das Menü ebenfalls
        $t.Add_MouseUp({
            param($iconSender, $mouseArgs)
            if ($mouseArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $script:UiReady) { [GGTray]::ShowMenu($iconSender) }
        })
        $t.Visible = $true
        $script:Tray = $t
        $script:TrayMenu = $menu
        $script:TrayText = $t.Text
        $script:TrayState = 'aktiv'
    } catch {
        Write-LogOnce ('FEHLER: Symbol in der Taskleiste: {0}' -f $_.Exception.Message)
        $script:Tray = $null
    }
}

function Update-BlockMenu([bool]$Focus) {
    # Untermenü "Sperren": jeder Abschnitt der Listen mit einem Schalter
    if (-not $script:UiReady -or -not $script:MenuBlock) { return }
    $dd = $script:MenuBlock.DropDown
    foreach ($old in @($dd.Items)) { if ($old.Image) { $old.Image.Dispose() } }
    $dd.Items.Clear()
    foreach ($line in [GGQuick]::Sections($script:ConfDir)) {
        $p = $line.Split('|')
        if ($p.Count -lt 4) { continue }
        $on = [int]$p[2]
        $total = [int]$p[3]
        $state = 2
        if ($on -eq 0) { $state = 0 } elseif ($on -lt $total) { $state = 1 }
        $it = [GGQuick]::Item($p[1], $state, $script:MenuTheme)
        $it.Tag = '{0}|{1}|{2}' -f $p[0], $p[1], [int]($on -lt $total)
        $it.Enabled = -not $Focus
        $it.Add_Click({
            param($itemSender, $clickArgs)
            $q = ([string]$itemSender.Tag).Split('|')
            try {
                [GGQuick]::SetSection($script:ConfDir, $q[0], $q[1], ($q[2] -eq '1'))
                if ($q[2] -eq '1') { Send-Notice 'GrindGuard' ('{0}: wird gesperrt.' -f $q[1]) } else { Send-Notice 'GrindGuard' ('{0}: bleibt offen.' -f $q[1]) }
            } catch {
                Send-Notice 'GrindGuard' ('Nicht gespeichert: {0}' -f $_.Exception.Message)
            }
        })
        [void]$dd.Items.Add($it)
    }
    [void]$dd.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $all = New-Object System.Windows.Forms.ToolStripMenuItem 'Einzeln einstellen …'
    $all.Add_Click({ Open-Settings 'Sperren' })
    [void]$dd.Items.Add($all)
    [GGTray]::Style($dd, $script:MenuTheme)
    [GGQuick]::Prepare($dd, $script:MenuTheme)
    if ($Focus) { $script:MenuBlock.Text = 'Sperren (eingefroren)' } else { $script:MenuBlock.Text = 'Sperren' }
}

function Update-TrayMenu {
    try {
        $state = Get-GuardState
        $n = Get-TodayCount
        $focus = ($state -eq 'fokus')
        if ($script:MenuHeader) {
            $script:MenuHeader.State = $state
            switch ($state) {
                'fokus' { $script:MenuHeader.Status = ('Fokus bis {0} Uhr · heute {1}× abgelenkt' -f (Format-Clock (Get-FocusEnd)), $n) }
                'pause' { $script:MenuHeader.Status = ('Pause bis {0} Uhr' -f (Format-Clock (Get-PauseEnd))) }
                default { $script:MenuHeader.Status = ('Aktiv · heute {0} Ausrutscher' -f $n) }
            }
            $script:MenuHeader.Invalidate()
        }
        foreach ($it in $script:MenuFocus.DropDownItems) {
            if ($focus) { $it.Text = ('+{0} Minuten verlängern' -f $it.Tag) } else { $it.Text = ('{0} Minuten' -f $it.Tag) }
        }
        if ($focus) { $script:MenuFocus.Text = ('Fokus-Sitzung (bis {0} Uhr)' -f (Format-Clock (Get-FocusEnd))) } else { $script:MenuFocus.Text = 'Fokus-Sitzung' }
        Update-BlockMenu $focus
        $script:MenuPause.Enabled = -not $focus
        foreach ($it in $script:MenuPauseItems) { $it.Visible = ($state -ne 'pause') }
        $script:MenuResume.Visible = ($state -eq 'pause')
        $script:MenuStop.Enabled = -not $focus
        $script:MenuUninstall.Enabled = -not $focus
    } catch { }
}

function Update-Tray {
    if (-not $script:Tray) { return }
    $state = Get-GuardState
    $text = 'GrindGuard – aktiv'
    if ($state -eq 'fokus') { $text = 'GrindGuard – Fokus bis {0}' -f (Format-Clock (Get-FocusEnd)) }
    if ($state -eq 'pause') { $text = 'GrindGuard – Pause bis {0}' -f (Format-Clock (Get-PauseEnd)) }
    if ($text -ne $script:TrayText) {
        try { $script:Tray.Text = $text; $script:TrayText = $text } catch { }
    }
    if ($state -ne $script:TrayState -and $script:TrayIcons[$state]) {
        try { $script:Tray.Icon = $script:TrayIcons[$state]; $script:TrayState = $state } catch { }
    }
}

function Remove-Tray {
    if ($script:Tray) {
        try { $script:Tray.Visible = $false; $script:Tray.Dispose() } catch { }
        $script:Tray = $null
    }
}

function Invoke-UiTick {
    # kurze Aufgaben zwischen den Prüfungen: Wünsche aus dem Menü und dem Einstellungsfenster
    if ($script:PendingTest) {
        $p = $script:PendingTest
        $script:PendingTest = $null
        [void](Invoke-TestLock $p)
    }
    if ($script:UiReady) {
        $req = [GGSettings]::TakeRequest()
        if ($req) { Invoke-UiRequest $req }
        if ([GGSettings]::ConfigVersion -ne $script:SeenConfig) {
            $script:SeenConfig = [GGSettings]::ConfigVersion
            Import-All                      # Änderungen aus den Einstellungen sofort übernehmen
            $script:PrevKey = ''
            $script:LastUrlOk = ''
        }
    }
}

function Start-Daemon {
    if (-not (Initialize-Native)) {
        Write-Log ('FEHLER: Windows-Funktionen nicht verfügbar ({0}). Prüfen: grind doctor' -f $script:NativeError)
        exit 1
    }
    Initialize-Gui
    [void](Initialize-Uia)
    [void](Initialize-Ui)
    if (-not (Test-Path -LiteralPath $script:StateDir)) {
        [void](New-Item -ItemType Directory -Path $script:StateDir -Force)
    }
    $mutex = New-Object System.Threading.Mutex($false, $script:MutexName)
    $owned = $false
    try {
        $owned = $mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $owned = $true
    }
    if (-not $owned) {
        Write-Output 'GrindGuard läuft bereits.'
        $mutex.Dispose()
        return
    }
    Remove-Item -LiteralPath $script:StopFile -Force -ErrorAction SilentlyContinue
    [System.IO.File]::WriteAllText($script:PidFile, [string]$PID, $script:Utf8)
    Reset-GuardState
    Invoke-RotateLog
    Import-All
    Initialize-Speech
    $script:VoiceSetting = $script:S.StimmenName
    New-Tray
    $how = 'Fenstertitel'
    if ($script:UiaReady) { $how = 'Adressleiste + Fenstertitel' }
    Write-Log ('GrindGuard {0} gestartet (Windows, Websites über {1})' -f $script:Version, $how)
    Write-Status
    try {
        while ($true) {
            if (Test-Path -LiteralPath $script:StopFile) {
                Write-Log 'Angehalten (grind stop)'
                break
            }
            $menuOpen = ($script:TrayMenu -and $script:TrayMenu.Visible)
            if (-not $menuOpen) {
                try {
                    Invoke-Check
                } catch {
                    Write-LogOnce ('FEHLER: {0}' -f $_.Exception.Message)
                }
            }
            Update-Tray
            if (Test-Path -LiteralPath $script:OpenFlag) {
                $page = ''
                try { $page = ([System.IO.File]::ReadAllText($script:OpenFlag)).Trim() } catch { }
                Remove-Item -LiteralPath $script:OpenFlag -Force -ErrorAction SilentlyContinue
                Open-Settings $page
            }
            $slices = [math]::Max(1, [int]($script:S.IntervallMs / 50))
            for ($i = 0; $i -lt $slices; $i++) {
                [System.Windows.Forms.Application]::DoEvents()
                try { Invoke-UiTick } catch { Write-LogOnce ('FEHLER: {0}' -f $_.Exception.Message) }
                if ($script:TrayMenu -and $script:TrayMenu.Visible) {
                    # Menü offen: öfter Nachrichten abholen, damit es flüssig reagiert
                    for ($j = 0; $j -lt 4; $j++) { Start-Sleep -Milliseconds 12; [System.Windows.Forms.Application]::DoEvents() }
                } else {
                    Start-Sleep -Milliseconds 50
                }
            }
        }
    } finally {
        Remove-Tray
        try {
            $own = ([System.IO.File]::ReadAllText($script:PidFile)).Trim()
            if ($own -eq [string]$PID) { Remove-Item -LiteralPath $script:PidFile -Force -ErrorAction SilentlyContinue }
        } catch { }
        Remove-Item -LiteralPath $script:StopFile -Force -ErrorAction SilentlyContinue
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose()
    }
}

# ----------------------------------------------------------------------------
# Hintergrunddienst verwalten
# ----------------------------------------------------------------------------
function Get-DaemonArgs {
    return ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" run' -f $script:SelfPath)
}

function Get-DaemonProcess {
    if (-not (Test-Path -LiteralPath $script:PidFile)) { return $null }
    $t = ''
    try { $t = ([System.IO.File]::ReadAllText($script:PidFile)).Trim() } catch { }
    if ($t -notmatch '^[0-9]{1,10}$') { return $null }
    $p = Get-Process -Id ([int]$t) -ErrorAction SilentlyContinue
    if (-not $p) { return $null }
    if ($p.ProcessName -notmatch '^(powershell|pwsh)$') { return $null }
    try {
        $cim = Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId = {0}' -f $p.Id) -ErrorAction Stop
        if ($cim -and $cim.CommandLine -and $cim.CommandLine -notlike '*grindguard.ps1*') { return $null }
    } catch { }
    return $p
}

function Set-Autostart {
    $cmd = '"{0}" {1}' -f $script:PsExe, (Get-DaemonArgs)
    Set-ItemProperty -Path $script:RunKey -Name $script:RunName -Value $cmd -ErrorAction Stop
}

function Get-AutostartState {
    # 'aus', 'an', 'abgeschaltet' (im Task-Manager deaktiviert) oder 'anderer Pfad'
    $v = $null
    try { $v = (Get-ItemProperty -Path $script:RunKey -Name $script:RunName -ErrorAction Stop).($script:RunName) } catch { }
    if (-not $v) { return 'aus' }
    if ($v -notlike ('*' + $script:SelfPath + '*')) { return 'anderer Pfad' }
    try {
        $approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        $bytes = (Get-ItemProperty -Path $approved -Name $script:RunName -ErrorAction Stop).($script:RunName)
        if ($bytes -and $bytes.Length -gt 0 -and ($bytes[0] -band 1) -eq 1) { return 'abgeschaltet' }
    } catch { }
    return 'an'
}

function Stop-Daemon {
    $p = Get-DaemonProcess
    if ($p) {
        try { [System.IO.File]::WriteAllText($script:StopFile, 'stop', $script:Utf8) } catch { }
        if (-not $p.WaitForExit(5000)) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            [void]$p.WaitForExit(3000)
        }
    }
    Remove-Item -LiteralPath $script:StopFile -Force -ErrorAction SilentlyContinue
    if (-not (Get-DaemonProcess)) {
        Remove-Item -LiteralPath $script:PidFile -Force -ErrorAction SilentlyContinue
    }
}

function Wait-Daemon([int]$Seconds) {
    for ($i = 0; $i -lt ($Seconds * 4); $i++) {
        $p = Get-DaemonProcess
        if ($p) { return $p }
        Start-Sleep -Milliseconds 250
    }
    return (Get-DaemonProcess)
}

# ----------------------------------------------------------------------------
# Befehle
# ----------------------------------------------------------------------------
function Invoke-Start {
    if (-not (Test-Path -LiteralPath $script:StateDir)) {
        [void](New-Item -ItemType Directory -Path $script:StateDir -Force)
    }
    try {
        Set-Autostart
    } catch {
        Write-Output ('Konnte den Autostart nicht eintragen: {0}' -f $_.Exception.Message)
    }
    Stop-Daemon                 # läuft schon einer? Dann mit der aktuellen Version neu starten
    Start-Process -FilePath $script:PsExe -ArgumentList (Get-DaemonArgs) -WindowStyle Hidden
    $p = Wait-Daemon 10
    if ($p) {
        Write-Output ('GrindGuard läuft (PID {0}) und startet ab jetzt bei jeder Anmeldung automatisch.' -f $p.Id)
        if ((Get-AutostartState) -eq 'abgeschaltet') {
            Write-Output 'Achtung: Im Task-Manager (Reiter "Autostart") ist GrindGuard deaktiviert – dort wieder aktivieren.'
        }
        return
    }
    Write-Output 'Der Wächter ist nicht gestartet. Details: ~\GrindGuard\grind doctor'
    exit 1
}

function Invoke-Stop {
    Assert-NoFocus 'stop'
    Stop-Daemon
    Remove-Item -LiteralPath $script:PauseFile -Force -ErrorAction SilentlyContinue
    Write-Output 'GrindGuard ist angehalten. Er startet wieder bei der nächsten Anmeldung oder mit: ~\GrindGuard\grind start'
    Write-Output 'Dauerhaft entfernen: ~\GrindGuard\grind uninstall'
}

function Test-InstallDir {
    # Nur den echten Installationsordner löschen – nie ein entpacktes Paket oder eine Kopie
    $instDir = Join-Path $env:USERPROFILE 'GrindGuard'
    return ([string]::Equals($script:Base.TrimEnd('\'), $instDir.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath (Join-Path $script:Base 'grindguard.ps1')))
}

function Remove-GrindGuard([bool]$DeleteFolder) {
    Stop-Daemon
    Remove-ItemProperty -Path $script:RunKey -Name $script:RunName -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:PauseFile -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $script:UninstallKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Get-StartLink) -Force -ErrorAction SilentlyContinue
    Write-Log 'GrindGuard entfernt'
    if ($DeleteFolder -and (Test-InstallDir)) {
        # Ein kleiner Helfer löscht den Ordner, sobald dieses Fenster zu ist
        $cmd = '/c ping -n 3 127.0.0.1 >nul & rd /s /q "{0}"' -f $script:Base
        Start-Process -FilePath $env:ComSpec -ArgumentList $cmd -WindowStyle Hidden -WorkingDirectory $env:TEMP
        return $true
    }
    return $false
}

function Invoke-Uninstall {
    Assert-NoFocus 'uninstall'
    [void](Remove-GrindGuard $false)
    Write-Output 'GrindGuard ist entfernt und startet nicht mehr automatisch.'
    Write-Output ('Der Ordner {0} (deine Listen und die Statistik) liegt noch da –' -f $script:Base)
    Write-Output 'wenn du ihn nicht mehr brauchst, lösch ihn.'
}

function Invoke-UninstallGui {
    # Deinstallieren mit Fenster: aus "Einstellungen > Apps", DEINSTALLIEREN.cmd und dem Menü
    try { Set-Location -LiteralPath $env:TEMP } catch { }
    $ui = Initialize-Ui
    $fe = Get-FocusEnd
    if ($fe -and (Get-Now) -lt $fe) {
        $msg = ('Deine Fokus-Sitzung läuft bis {0} Uhr. Danach kannst du GrindGuard entfernen. Notausstieg (10 Minuten Wartezeit): ~\GrindGuard\grind notausstieg' -f (Format-Clock $fe))
        if ($ui) { [GGDialog]::Info('Nicht während der Fokus-Sitzung.', $msg) } else { Show-FallbackPopup 60 'GrindGuard' $msg '' }
        exit 1
    }
    $all = $false
    if ($ui) {
        $ok = [GGDialog]::Ask('GrindGuard entfernen?',
            'Der Wächter hört sofort auf und startet nicht mehr mit Windows. Der Eintrag unter „Apps“ und im Startmenü verschwindet.',
            'Entfernen', 'Abbrechen', 'Auch meine Listen, Sprüche und Statistik löschen', $true, [ref]$all)
        if (-not $ok) { return }
    } else {
        $shell = New-Object -ComObject WScript.Shell
        if ($shell.Popup('GrindGuard entfernen?', 0, 'GrindGuard', 0x4 + 0x20 + 0x1000) -ne 6) { return }
    }
    $gone = Remove-GrindGuard $all
    if ($gone) { $text = 'Der Wächter ist aus und dein GrindGuard-Ordner wird gelöscht. Viel Erfolg – du schaffst das auch ohne.' }
    else { $text = ('Der Wächter ist aus und startet nicht mehr. Deine Listen liegen noch in {0}.' -f $script:Base) }
    if ($ui) { [GGDialog]::Info('GrindGuard ist entfernt.', $text) } else { Show-FallbackPopup 30 'GrindGuard ist entfernt.' $text '' }
}

function Get-StartLink {
    return (Join-Path ([Environment]::GetFolderPath('Programs')) 'GrindGuard.lnk')
}

function Invoke-Register {
    # Eintrag unter "Einstellungen > Apps", Startmenü und Symbol – ruft der Installer auf
    $icon = $script:PsExe + ',0'
    if (Initialize-Ui) {
        try {
            [GGBrand]::SaveIco($script:IconFile)
            $icon = $script:IconFile
        } catch {
            Write-Output ('  Symbol: {0}' -f $_.Exception.Message)
        }
    }
    try {
        $k = $script:UninstallKey
        if (-not (Test-Path -Path $k)) { [void](New-Item -Path $k -Force) }
        $kb = 0
        try { $kb = [int](((Get-ChildItem -LiteralPath $script:Base -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum) / 1024) } catch { }
        $uninstall = '"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}" deinstallieren' -f $script:PsExe, $script:SelfPath
        $values = [ordered]@{
            DisplayName = 'GrindGuard'
            DisplayVersion = $script:Version
            Publisher = 'GrindGuard'
            DisplayIcon = $icon
            InstallLocation = $script:Base
            UninstallString = $uninstall
            URLInfoAbout = ('https://github.com/{0}' -f $script:UpdateRepo)
            HelpLink = ('https://github.com/{0}' -f $script:UpdateRepo)
            InstallDate = (Get-Date).ToString('yyyyMMdd', $script:Inv)
        }
        foreach ($name in $values.Keys) { [void](New-ItemProperty -Path $k -Name $name -Value $values[$name] -PropertyType String -Force) }
        foreach ($name in @('NoModify', 'NoRepair')) { [void](New-ItemProperty -Path $k -Name $name -Value 1 -PropertyType DWord -Force) }
        [void](New-ItemProperty -Path $k -Name 'EstimatedSize' -Value $kb -PropertyType DWord -Force)
        Write-Output '  Eintrag unter Einstellungen > Apps: ok'
    } catch {
        Write-Output ('  Eintrag unter Einstellungen > Apps fehlt: {0}' -f $_.Exception.Message)
    }
    try {
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut((Get-StartLink))
        $lnk.TargetPath = $script:PsExe
        $lnk.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" einstellungen' -f $script:SelfPath)
        $lnk.WorkingDirectory = $env:USERPROFILE
        $lnk.IconLocation = $icon
        $lnk.Description = 'GrindGuard – Einstellungen'
        $lnk.WindowStyle = 7
        $lnk.Save()
        Write-Output '  Startmenü: „GrindGuard“ öffnet die Einstellungen'
    } catch {
        Write-Output ('  Startmenü-Eintrag fehlt: {0}' -f $_.Exception.Message)
    }
}

function Invoke-Settings([string]$Page) {
    $p = Get-DaemonProcess
    if ($p) {
        # Der Wächter hat die Oberfläche schon geladen und öffnet das Fenster sofort
        if (-not (Test-Path -LiteralPath $script:StateDir)) { [void](New-Item -ItemType Directory -Path $script:StateDir -Force) }
        if (Initialize-Native) { try { [void][GGNative]::AllowSetForegroundWindow($p.Id) } catch { } }
        try { [System.IO.File]::WriteAllText($script:OpenFlag, $Page, $script:Utf8) } catch { }
        Write-Output 'Die Einstellungen öffnen sich …'
        return
    }
    if (-not (Initialize-Ui)) {
        Write-Output ('Die Einstellungen lassen sich nicht öffnen ({0}). Listen bearbeiten: ~\GrindGuard\grind edit' -f $script:UiError)
        exit 1
    }
    [GGSettings]::ShowModal($script:Base, $script:Version, $script:UpdateRepo, [string[]]$script:Protected, $Page)
}

function Test-NewerVersion([string]$Candidate, [string]$Current) {
    try {
        $a = [version](($Candidate.TrimStart('v')) + $(if ($Candidate -notmatch '\.') { '.0' } else { '' }))
        $b = [version](($Current.TrimStart('v')) + $(if ($Current -notmatch '\.') { '.0' } else { '' }))
        return ($a -gt $b)
    } catch {
        return $false
    }
}

function Wait-Window([bool]$Window) {
    if ($Window) {
        Write-Output ''
        Write-Output 'Enter drücken zum Schliessen …'
        try { [void][Console]::ReadLine() } catch { }
    }
}

function Invoke-Update([string]$Mode) {
    # Neueste Version von GitHub holen, Prüfsumme kontrollieren, Installer starten.
    # Nur auf ausdrücklichen Wunsch – GrindGuard prüft nie von selbst.
    $window = ($Mode -eq 'fenster')
    Write-Output ('GrindGuard {0} – suche nach Updates …' -f $script:Version)
    $fe = Get-FocusEnd
    if ($fe -and (Get-Now) -lt $fe) {
        Write-Output ('Fokus-Sitzung läuft bis {0} Uhr – das Update gibt es danach.' -f (Format-Clock $fe))
        Wait-Window $window
        exit 1
    }
    $ProgressPreference = 'SilentlyContinue'
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $headers = @{ 'User-Agent' = 'GrindGuard'; 'Accept' = 'application/vnd.github+json' }
    try {
        $rel = Invoke-RestMethod -Uri ('https://api.github.com/repos/{0}/releases/latest' -f $script:UpdateRepo) -Headers $headers -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
    } catch {
        Write-Output ('Keine Verbindung zu GitHub: {0}' -f $_.Exception.Message)
        Wait-Window $window
        exit 1
    }
    $latest = ([string]$rel.tag_name).TrimStart('v')
    if (-not (Test-NewerVersion $latest $script:Version)) {
        Write-Output ('Du hast die neueste Version ({0}).' -f $script:Version)
        Wait-Window $window
        return
    }
    Write-Output ('Neue Version: {0}' -f $latest)
    $zip = @($rel.assets | Where-Object { $_.name -eq 'GrindGuard-Windows.zip' })[0]
    $sums = @($rel.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' })[0]
    if (-not $zip -or -not $sums) {
        Write-Output 'In diesem Release fehlt das Windows-Paket. Bitte von Hand herunterladen:'
        Write-Output ('  https://github.com/{0}/releases/latest' -f $script:UpdateRepo)
        Wait-Window $window
        exit 1
    }
    foreach ($a in @($zip, $sums)) {
        # nur echte GitHub-Release-Downloads (der Name des Repos darf sich ändern, GitHub leitet um)
        if ([string]$a.browser_download_url -notlike 'https://github.com/*/releases/download/*') {
            Write-Output ('Unerwartete Download-Adresse: {0}' -f $a.browser_download_url)
            Wait-Window $window
            exit 1
        }
    }
    $tmp = Join-Path $env:TEMP ('GrindGuard-Update-{0}-{1}' -f $latest, [guid]::NewGuid().ToString('N').Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $tmp -Force)
    $zipPath = Join-Path $tmp 'GrindGuard-Windows.zip'
    $sumPath = Join-Path $tmp 'SHA256SUMS.txt'
    try {
        Write-Output 'Lade herunter …'
        Invoke-WebRequest -Uri $zip.browser_download_url -OutFile $zipPath -Headers @{ 'User-Agent' = 'GrindGuard' } -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
        Invoke-WebRequest -Uri $sums.browser_download_url -OutFile $sumPath -Headers @{ 'User-Agent' = 'GrindGuard' } -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    } catch {
        Write-Output ('Download fehlgeschlagen: {0}' -f $_.Exception.Message)
        Wait-Window $window
        exit 1
    }
    $expected = ''
    foreach ($l in [System.IO.File]::ReadAllLines($sumPath)) {
        if ($l -match '^([0-9a-fA-F]{64})\s+\*?GrindGuard-Windows\.zip\s*$') { $expected = $Matches[1].ToLowerInvariant() }
    }
    $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not $expected -or $expected -ne $actual) {
        Write-Output 'Die Prüfsumme stimmt nicht – das Update wird NICHT installiert.'
        Wait-Window $window
        exit 1
    }
    Write-Output 'Prüfsumme stimmt.'
    $pkg = Join-Path $tmp 'paket'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $pkg -Force
    Get-ChildItem -LiteralPath $pkg -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
    $inst = Join-Path $pkg 'app\install.ps1'
    if (-not (Test-Path -LiteralPath $inst)) {
        Write-Output 'Im Paket fehlt der Installer.'
        Wait-Window $window
        exit 1
    }
    Write-Output ''
    & $script:PsExe -NoProfile -ExecutionPolicy Bypass -File $inst
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Wait-Window $window
}

function Get-Counts {
    return ('{0} Websites, {1} Apps, {2} Suchbegriffe' -f $script:SitesBlock.Count, $script:AppsBlock.Count, $script:SearchBlock.Count)
}

function Invoke-Status {
    Import-All
    Write-Output ('GrindGuard {0} (Windows)' -f $script:Version)
    $p = Get-DaemonProcess
    $now = Get-Now
    if ($p) {
        $pe = Get-PauseEnd
        $fe = Get-FocusEnd
        if ($fe -and $now -lt $fe) {
            Write-Output ('  Wächter:        FOKUS-SITZUNG bis {0} Uhr (Regeln eingefroren)' -f (Format-Clock $fe))
        } elseif ($pe -and $now -lt $pe) {
            Write-Output ('  Wächter:        pausiert bis {0} Uhr' -f (Format-Clock $pe))
        } else {
            Write-Output ('  Wächter:        läuft (PID {0})' -f $p.Id)
        }
        $hb = Get-StatusValue 'herzschlag'
        if ($hb -match '^[0-9]+$' -and ($now - [long]$hb) -gt 60) {
            Write-Output ('  Achtung:        letztes Lebenszeichen vor {0} Sekunden – hängt er?' -f ($now - [long]$hb))
        }
        $cool = Get-StatusValue 'ausgesetzt_bis'
        if ($cool -match '^[0-9]+$' -and $now -lt [long]$cool) {
            Write-Output ('  Achtung:        Schutz für {0} ausgesetzt bis {1} Uhr (liess sich nicht schliessen)' -f (Get-StatusValue 'ausgesetzt'), (Format-Clock ([long]$cool)))
        }
    } else {
        Write-Output '  Wächter:        läuft NICHT – starten mit: ~\GrindGuard\grind start'
    }
    $n = Get-TodayCount
    Write-Output ('  Heute:          {0} Ausrutscher' -f $n)
    Write-Output ('  Nächste Sperre: {0} Sekunden' -f (Get-LockSeconds ($n + 1)))
    Write-Output ('  Blockiert:      {0}' -f (Get-Counts))
    if ($script:S.ZeitVon -ne 0 -or $script:S.ZeitBis -ne 2400 -or $script:S.Tage -ne '1234567') {
        Write-Output ('  Aktiv:          {0}–{1} Uhr, Tage {2} (1 = Montag)' -f (Format-HM $script:S.ZeitVon), (Format-HM $script:S.ZeitBis), $script:S.Tage)
    } else {
        Write-Output '  Aktiv:          immer'
    }
    $problems = @(Get-ConfigLines $script:LogFile | Where-Object { $_ -match 'FEHLER' } | Select-Object -Last 3)
    if ($problems.Count -gt 0) {
        Write-Output ''
        Write-Output 'Letzte Probleme (Details: ~\GrindGuard\grind doctor):'
        foreach ($l in $problems) { Write-Output ('  ' + $l) }
    }
}

function Invoke-Pause([string]$Minutes) {
    if ([string]::IsNullOrEmpty($Minutes)) { $Minutes = '15' }
    if ($Minutes -notmatch '^[1-9][0-9]{0,3}$') {
        Write-Output 'Bitte die Minuten als Zahl angeben, z. B.: grind pause 20'
        exit 1
    }
    $min = [int]$Minutes
    Assert-NoFocus 'pause'
    if ($min -gt 120) {
        $min = 120
        Write-Output 'Maximal 120 Minuten am Stück.'
    }
    Write-Output (Set-Pause $min)
}

function Invoke-Resume {
    Remove-Item -LiteralPath $script:PauseFile -Force -ErrorAction SilentlyContinue
    Write-Output 'Pause beendet. Der Wächter ist wieder scharf.'
}

function Invoke-Test([string]$Plate) {
    Import-All
    Initialize-Speech
    Write-Output 'Test: Gleich erscheint 6 Sekunden lang die Warnung …'
    $mode = Invoke-TestLock $Plate
    if ($mode -eq 'vollbild') {
        Write-Output 'Vollbild-Warnung: funktioniert.'
    } else {
        Write-Output 'Die Vollbild-Warnung liess sich nicht anzeigen – es wurde das einfache Dialogfenster verwendet.'
        Write-Output ('Details stehen in: {0}' -f $script:LogFile)
    }
    if (-not $script:VoiceName -and $script:S.Stimme -eq 1) {
        Write-Output 'Keine deutsche Stimme gefunden – die Warnung wird nicht vorgelesen. Siehe: grind doctor'
    }
}

function Invoke-Stats {
    $lines = @(Get-ConfigLines $script:StrikesFile | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2} ' })
    if ($lines.Count -eq 0) {
        Write-Output 'Noch kein einziger Ausrutscher aufgezeichnet.'
        return
    }
    $names = @('', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So')
    Write-Output 'Ausrutscher der letzten 7 Tage'
    for ($i = 6; $i -ge 0; $i--) {
        $d = (Get-Date).Date.AddDays(-$i)
        $key = $d.ToString('yyyy-MM-dd', $script:Inv)
        $c = @($lines | Where-Object { $_.StartsWith($key) }).Count
        $dow = [int]$d.DayOfWeek
        if ($dow -eq 0) { $dow = 7 }
        $bar = '█' * [math]::Min($c, 40)
        Write-Output ('  {0} {1}  {2,2}  {3}' -f $names[$dow], $d.ToString('dd.MM.', $script:Inv), $c, $bar)
    }
    Write-Output ''
    Write-Output 'Häufigste Ablenkungen (alle Tage)'
    $lines | ForEach-Object {
        $parts = $_.Split('|')
        if ($parts.Count -ge 3) { $parts[2] }
    } | Group-Object | Sort-Object -Property Count -Descending | Select-Object -First 5 | ForEach-Object {
        Write-Output ('  {0,3}×  {1}' -f $_.Count, $_.Name)
    }
}

function Invoke-Edit {
    Write-Output ('Öffne den Ordner mit deinen Listen: {0}' -f $script:ConfDir)
    Write-Output '  websites.txt        blockierte Websites und Suchbegriffe'
    Write-Output '  apps.txt            blockierte Programme'
    Write-Output '  sprueche.txt        die Texte der Warnung'
    Write-Output '  einstellungen.txt   Sperrzeiten, Stimme, aktive Zeiten'
    Write-Output 'Änderungen wirken nach etwa 15 Sekunden von selbst.'
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $script:ConfDir) } catch { }
}

function Get-RuleLines {
    # wirksame Zeilen der Website-Liste mit Zeilennummer (wie Import-Sites vereinheitlicht)
    $out = New-Object System.Collections.Generic.List[object]
    $nr = 0
    foreach ($raw in (Get-ConfigLines $script:SitesFile)) {
        $nr++
        $l = $raw.ToLowerInvariant()
        $hash = $l.IndexOf('#')
        if ($hash -ge 0) { $l = $l.Substring(0, $hash) }
        $l = $l.Trim()
        if ($l -eq '') { continue }
        $l = $l -replace '^\+\s+', '+'
        $l = $l -replace '^(\+?)https?://', '$1'
        $l = $l -replace '^(\+?)www\.', '$1'
        $l = $l -replace '/+$', ''
        if ($l -eq '' -or $l -eq '+') { continue }
        $out.Add(@{ Nr = $nr; Text = $l })
    }
    return $out
}

function Find-Rule([string]$Kind, $Parts, [string]$Hit) {
    foreach ($r in (Get-RuleLines)) {
        $e = $r.Text
        switch ($Kind) {
            'allow' { if ($e.StartsWith('+') -and (Test-SiteMatch @($e.Substring(1)) $Parts.HostName $Parts.PathPart)) { return $r } }
            'search' { if ($e.StartsWith('suche:') -and $e.Substring(6).Trim() -eq $Hit) { return $r } }
            'block' {
                if (-not $e.StartsWith('+') -and -not $e.StartsWith('suche:') -and (Test-SiteMatch @($e) $Parts.HostName $Parts.PathPart)) { return $r }
            }
        }
    }
    return $null
}

function Invoke-CheckUrl([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) {
        Write-Output 'Aufruf: grind check youtube.com/shorts'
        exit 1
    }
    $fe = Get-FocusEnd
    if ($fe -and (Get-Now) -lt $fe -and (Test-Path -LiteralPath $script:FocusDir)) { Set-ConfSrc $script:FocusDir }
    Import-All
    $where = 'websites.txt'
    if ($script:ConfSrc -eq $script:FocusDir) { $where = 'eingefrorene Liste der Fokus-Sitzung' }
    $u = $Url.Trim()
    if ($u -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $u = 'https://' + $u }
    $parts = ConvertTo-UrlParts $u
    if (-not $parts) {
        Write-Output ('Das ist keine Webadresse: {0}' -f $Url)
        exit 1
    }
    $name = Get-BlockName $parts
    $shown = $parts.HostName + $parts.PathPart
    if ($name) {
        if ($script:LastSearchHit) {
            Write-Output ('BLOCKIERT  {0}  (Suchbegriff „{1}“)' -f $shown, $script:LastSearchHit)
            $r = Find-Rule 'search' $parts $script:LastSearchHit
        } else {
            Write-Output ('BLOCKIERT  {0}' -f $shown)
            $r = Find-Rule 'block' $parts ''
        }
        if ($r) { Write-Output ('  Regel:    {0}  ({1}, Zeile {2})' -f $r.Text, $where, $r.Nr) }
    } else {
        Write-Output ('erlaubt    {0}' -f $shown)
        $r = Find-Rule 'allow' $parts ''
        if ($r) { Write-Output ('  Ausnahme: {0}  ({1}, Zeile {2})' -f $r.Text, $where, $r.Nr) }
    }
}

function Invoke-Corpus([string]$File) {
    # für die automatischen Tests: eine Adresse pro Zeile -> "B <Suchbegriff|->" oder "E -"
    if (-not (Test-Path -LiteralPath $File)) {
        Write-Output ('Datei fehlt: {0}' -f $File)
        exit 1
    }
    Import-All
    foreach ($raw in [System.IO.File]::ReadAllLines($File, [System.Text.Encoding]::UTF8)) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $line = 'https://' + $line }
        $parts = ConvertTo-UrlParts $line
        $name = $null
        if ($parts) { $name = Get-BlockName $parts }
        if ($name) {
            $k = '-'
            if ($script:LastSearchHit) { $k = $script:LastSearchHit }
            Write-Output ('B ' + $k)
        } else {
            Write-Output 'E -'
        }
    }
}

function Start-FocusSession([int]$Minutes) {
    # gibt eine Meldung zurück; wird vom Befehl "fokus" und vom Tray-Menü benutzt
    if ($Minutes -lt 5) { return 'Bitte die Minuten als Zahl angeben (5 bis 240), z. B.: grind fokus 50' }
    if ($Minutes -gt 240) { $Minutes = 240 }
    if (-not (Test-Path -LiteralPath $script:StateDir)) { [void](New-Item -ItemType Directory -Path $script:StateDir -Force) }
    $now = Get-Now
    $end = $now + $Minutes * 60
    $cur = Get-FocusEnd
    $msg = ''
    if ($cur -and $now -lt $cur) {
        if ($end -le $cur) { return ('Es läuft schon eine Fokus-Sitzung bis {0} Uhr. Verkürzen geht nicht.' -f (Format-Clock $cur)) }
        $msg = 'Fokus-Sitzung verlängert. '
    } else {
        Remove-Item -LiteralPath $script:FocusDir -Recurse -Force -ErrorAction SilentlyContinue
        [void](New-Item -ItemType Directory -Path $script:FocusDir -Force)
        foreach ($n in @('einstellungen.txt', 'websites.txt', 'apps.txt', 'sprueche.txt')) {
            $src = Join-Path $script:ConfDir $n
            if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $script:FocusDir $n) -Force }
        }
    }
    [System.IO.File]::WriteAllText($script:FocusFile, [string]$end, $script:Utf8)
    Remove-Item -LiteralPath $script:PauseFile -Force -ErrorAction SilentlyContinue
    Write-Log ('Fokus-Sitzung gestartet: {0} Minuten, bis {1} Uhr' -f $Minutes, (Format-Clock $end))
    return ('{0}Fokus-Sitzung: {1} Minuten, bis {2} Uhr.' -f $msg, $Minutes, (Format-Clock $end))
}

function Invoke-Fokus([string]$Minutes) {
    if ([string]::IsNullOrEmpty($Minutes)) { $Minutes = '50' }
    if ($Minutes -notmatch '^[1-9][0-9]{0,3}$' -or [int]$Minutes -lt 5) {
        Write-Output 'Bitte die Minuten als Zahl angeben (5 bis 240), z. B.: grind fokus 50'
        exit 1
    }
    if ([int]$Minutes -gt 240) { Write-Output 'Maximal 240 Minuten am Stück.' }
    Write-Output (Start-FocusSession ([int]$Minutes))
    Write-Output 'Deine Listen sind bis dahin eingefroren, pause, stop und uninstall sind gesperrt.'
    Write-Output 'Notausstieg (10 Minuten Wartezeit): ~\GrindGuard\grind notausstieg'
    if (-not (Get-DaemonProcess)) { Write-Output 'Achtung: Der Wächter läuft gerade nicht – starten mit: ~\GrindGuard\grind start' }
}

function Invoke-Notausstieg {
    $cur = Get-FocusEnd
    $now = Get-Now
    if (-not $cur -or $now -ge $cur) {
        Write-Output 'Es läuft keine Fokus-Sitzung.'
        return
    }
    $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if (-not $interactive -and -not $env:GRIND_TEST_TTY) {
        Write-Output 'Der Notausstieg geht nur von Hand in PowerShell.'
        exit 1
    }
    Write-Output ('Die Sitzung läuft noch bis {0} Uhr.' -f (Format-Clock $cur))
    Write-Output 'Wenn du wirklich aussteigen willst, tippe genau diesen Satz ab und drück Enter:'
    Write-Output ''
    Write-Output ('  ' + $script:NotSatz)
    Write-Output ''
    $line = [Console]::ReadLine()
    if ($line -cne $script:NotSatz) {
        Write-Output 'Nicht genau abgetippt. Die Sitzung läuft weiter.'
        exit 1
    }
    $end = $now + 600
    if ($end -lt $cur) {
        [System.IO.File]::WriteAllText($script:FocusFile, [string]$end, $script:Utf8)
    } else {
        $end = $cur
    }
    Write-Log ('Notausstieg: Fokus-Sitzung endet um {0} Uhr' -f (Format-Clock $end))
    Write-Output ('Okay. Die Sitzung endet um {0} Uhr. Bis dahin gilt sie weiter.' -f (Format-Clock $end))
    Write-Output 'Nutze die zehn Minuten: Schreib auf, warum du aussteigst.'
}

function Invoke-Voices {
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        Write-Output 'Installierte Stimmen (Name für STIMMEN_NAME in einstellungen.txt):'
        foreach ($v in $synth.GetInstalledVoices()) {
            Write-Output ('  {0}  ({1})' -f $v.VoiceInfo.Name, $v.VoiceInfo.Culture.Name)
        }
    } catch {
        Write-Output 'Die Sprachausgabe von Windows ist nicht verfügbar.'
    }
}

function Invoke-Doctor {
    $ok = $true
    Import-All
    Write-Output ('GrindGuard {0} – Selbsttest' -f $script:Version)
    Write-Output ''
    $os = ''
    try { $os = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption } catch { $os = [string][Environment]::OSVersion.Version }
    Write-Output ('Windows:             {0}' -f $os)
    Write-Output ('PowerShell:          {0}' -f $PSVersionTable.PSVersion)

    $mode = $ExecutionContext.SessionState.LanguageMode
    if ([string]$mode -ne 'FullLanguage') {
        Write-Output ('Skript-Modus:        {0} – FEHLER: Dein PC erlaubt nur eingeschränkte Skripte' -f $mode)
        Write-Output '                     (typisch für Schul- und Firmen-PCs). GrindGuard kann hier nicht laufen.'
        $ok = $false
    }
    foreach ($scope in @('MachinePolicy', 'UserPolicy')) {
        $pol = [string](Get-ExecutionPolicy -Scope $scope)
        if ($pol -in @('Restricted', 'AllSigned')) {
            Write-Output ('Skript-Richtlinie:   {0} = {1} – FEHLER: von der IT vorgegeben, GrindGuard wird blockiert.' -f $scope, $pol)
            $ok = $false
        }
    }

    if (Initialize-Native) {
        $f = Get-FrontWindow
        if ($f) {
            Write-Output ('Fenster-Erkennung:   ok – vorne ist gerade: {0}' -f $f.Name)
        } else {
            Write-Output 'Fenster-Erkennung:   ok'
        }
    } else {
        Write-Output ('Fenster-Erkennung:   FEHLER – {0}' -f $script:NativeError)
        $ok = $false
    }

    if (Initialize-Ui) {
        Write-Output 'Oberfläche:          ok (Sperrbildschirm, Menü, Einstellungen)'
    } else {
        Write-Output ('Oberfläche:          FEHLER – {0}' -f $script:UiError)
        Write-Output '                     (die Warnung erscheint dann nur als einfaches Dialogfenster)'
        $ok = $false
    }
    if (Test-Path -Path $script:UninstallKey) {
        Write-Output 'Unter Apps:          eingetragen (Deinstallieren über Einstellungen > Apps)'
    } else {
        Write-Output 'Unter Apps:          nicht eingetragen – INSTALLIEREN.cmd noch einmal starten'
    }

    if (Initialize-Uia) {
        $found = $false
        foreach ($b in $script:Browsers) {
            foreach ($bp in @(Get-Process -Name $b -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })) {
                $found = $true
                $script:Now = Get-Now
                $front = @{ Hwnd = $bp.MainWindowHandle; ProcId = $bp.Id; Name = $b; Title = $bp.MainWindowTitle }
                $o = Get-OmniboxValue $front
                if ($o.State -eq 'ok' -and (ConvertTo-UrlParts $o.Value)) {
                    Write-Output ('Browser {0,-10}  Adresse lesbar ({1})' -f ($b + ':'), $o.Value)
                } elseif ($o.State -eq 'focus') {
                    Write-Output ('Browser {0,-10}  Adressleiste hat gerade den Fokus – später noch einmal prüfen' -f ($b + ':'))
                } else {
                    Write-Output ('Browser {0,-10}  Adresse nicht lesbar – Websites werden nur am Fenstertitel erkannt' -f ($b + ':'))
                }
                break
            }
        }
        if (-not $found) {
            Write-Output 'Browser:             keiner offen – zum Prüfen Chrome oder Edge öffnen und noch einmal "grind doctor"'
        }
    } else {
        Write-Output 'Browser:             Bedienungshilfen (UI Automation) fehlen – Websites nur am Fenstertitel erkennbar'
    }

    $as = Get-AutostartState
    switch ($as) {
        'an'           { Write-Output 'Autostart:           an' }
        'aus'          { Write-Output 'Autostart:           aus – einschalten mit: ~\GrindGuard\grind start'; $ok = $false }
        'abgeschaltet' { Write-Output 'Autostart:           im Task-Manager deaktiviert – dort unter "Autostart" wieder aktivieren'; $ok = $false }
        default        { Write-Output 'Autostart:           zeigt auf einen anderen Ordner – neu eintragen mit: ~\GrindGuard\grind start'; $ok = $false }
    }
    $p = Get-DaemonProcess
    if ($p) {
        Write-Output ('Hintergrunddienst:   läuft (PID {0})' -f $p.Id)
        $lesbar = Get-StatusValue 'browser_lesbar'
        $titel = Get-StatusValue 'browser_nur_titel'
        if ($lesbar) { Write-Output ('Seit dem Start:      Adresse gelesen in {0}' -f $lesbar) }
        if ($titel) { Write-Output ('Seit dem Start:      nur Fenstertitel in {0}' -f $titel) }
    } else {
        Write-Output 'Hintergrunddienst:   läuft NICHT – starten mit: ~\GrindGuard\grind start'
        $ok = $false
    }
    $fe = Get-FocusEnd
    if ($fe -and (Get-Now) -lt $fe) { Write-Output ('Fokus-Sitzung:       läuft bis {0} Uhr (Regeln eingefroren)' -f (Format-Clock $fe)) }
    Write-Output ('Ton der Warnung:     {0}' -f $script:S.Ton)

    Initialize-Speech
    if ($script:VoiceName) {
        Write-Output ('Stimme:              {0}' -f $script:VoiceName)
    } else {
        Write-Output 'Stimme:              keine deutsche Stimme – die Warnung wird nicht vorgelesen.'
        Write-Output '                     (Nachladen: Einstellungen > Zeit und Sprache > Sprache > Deutsch > Sprachausgabe)'
    }
    Write-Output ('Listen:              {0} blockiert' -f (Get-Counts))

    $errs = @(Get-ConfigLines $script:LogFile | Where-Object { $_ -match 'FEHLER' } | Select-Object -Last 3)
    if ($errs.Count -gt 0) {
        Write-Output ''
        Write-Output ('Letzte Fehler im Protokoll ({0}):' -f $script:LogFile)
        foreach ($l in $errs) { Write-Output ('  ' + $l) }
    }
    Write-Output ''
    if ($ok) { Write-Output 'Alles in Ordnung.' } else { Write-Output 'Es gibt Punkte zu beheben (siehe oben).' }
}

function Show-Usage {
    Write-Output ('GrindGuard {0} – dein Fokus-Wächter (Windows)' -f $script:Version)
    Write-Output ''
    Write-Output '  grind einstellungen Einstellungen öffnen (auch: Startmenü > GrindGuard)'
    Write-Output '  grind status        Läuft der Wächter? Wie viele Ausrutscher heute?'
    Write-Output '  grind fokus [Min]   Fokus-Sitzung (Standard 50): Listen eingefroren, keine Pause'
    Write-Output '  grind notausstieg   Fokus-Sitzung vorzeitig beenden (mit 10 Minuten Wartezeit)'
    Write-Output '  grind pause [Min]   Bewusste Pause (Standard 15, maximal 120 Minuten)'
    Write-Output '  grind weiter        Pause sofort beenden'
    Write-Output '  grind test [Design]  Warnung zur Probe (nacht, kobalt, papier, lexikon, bordeaux)'
    Write-Output '  grind stats         Ausrutscher der letzten 7 Tage'
    Write-Output '  grind edit          Blocklisten, Sprüche und Einstellungen öffnen'
    Write-Output '  grind check ADRESSE Zeigt, ob eine Website oder Suche blockiert würde – und welche Regel'
    Write-Output '  grind stimmen       Installierte Stimmen anzeigen'
    Write-Output '  grind doctor        Prüfen, ob alles richtig eingerichtet ist'
    Write-Output '  grind start         Wächter starten (danach automatisch bei jeder Anmeldung)'
    Write-Output '  grind stop          Wächter anhalten (bis zur nächsten Anmeldung)'
    Write-Output '  grind update        Neueste Version von GitHub holen und installieren'
    Write-Output '  grind uninstall     Wächter entfernen (mit Fenster: grind deinstallieren)'
    Write-Output ''
    Write-Output 'Aufruf in PowerShell:  ~\GrindGuard\grind <Befehl>'
}

$script:Arg = ($Rest -join ' ').Trim()
switch ($Command.ToLowerInvariant()) {
    'run'       { Start-Daemon }
    'start'     { Invoke-Start }
    'stop'      { Invoke-Stop }
    'uninstall' { Invoke-Uninstall }
    'deinstallieren' { Invoke-UninstallGui }
    'einstellungen' { Invoke-Settings $script:Arg }
    'settings'  { Invoke-Settings $script:Arg }
    'update'    { Invoke-Update $script:Arg }
    '__einrichten' { Invoke-Register }
    'status'    { Invoke-Status }
    'pause'     { Invoke-Pause $script:Arg }
    'weiter'    { Invoke-Resume }
    'resume'    { Invoke-Resume }
    'test'      { Invoke-Test $script:Arg }
    'stats'     { Invoke-Stats }
    'edit'      { Invoke-Edit }
    'check'     { Invoke-CheckUrl $script:Arg }
    'explain'   { Invoke-CheckUrl $script:Arg }
    'fokus'     { Invoke-Fokus $script:Arg }
    'focus'     { Invoke-Fokus $script:Arg }
    'notausstieg' { Invoke-Notausstieg }
    '__corpus'  { Invoke-Corpus $script:Arg }
    'stimmen'   { Invoke-Voices }
    'doctor'    { Invoke-Doctor }
    'help'      { Show-Usage }
    default     { Show-Usage; exit 1 }
}
