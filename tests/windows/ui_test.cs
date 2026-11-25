// Tests für grindguard-ui.cs: Listen bearbeiten, Einstellungen, Versionen,
// Sperrbildschirm und Logo. Läuft im CI unter Windows (Add-Type) und lokal mit
// Mono:  mcs -r:System.Drawing -r:System.Windows.Forms -out:t.exe \
//            windows/app/grindguard-ui.cs tests/windows/ui_test.cs && mono t.exe
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Text;

public static class GGUiTests
{
    static int fails;

    static void Check(bool ok, string what)
    {
        Console.WriteLine((ok ? "ok      " : "FEHLER  ") + what);
        if (!ok) fails++;
    }

    static bool Same(byte[] a, byte[] b)
    {
        if (a.Length != b.Length) return false;
        for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
        return true;
    }

    static int Count(string text, string part)
    {
        int n = 0, i = 0;
        while ((i = text.IndexOf(part, i, StringComparison.Ordinal)) >= 0) { n++; i += part.Length; }
        return n;
    }

    static GGEntry Find(GGListFile f, string text)
    {
        return f.Entries().Find(delegate (GGEntry e) { return e.Text == text; });
    }

    public static int Run(string tmp, string websites, string apps, string settings, string quotes)
    {
        fails = 0;
        Directory.CreateDirectory(tmp);

        // ---- Websites: erkennen ----
        string w = Path.Combine(tmp, "websites.txt");
        File.WriteAllText(w, File.ReadAllText(websites, Encoding.UTF8).Replace("\r\n", "\n").Replace("\n", "\r\n"), new UTF8Encoding(false));
        byte[] before = File.ReadAllBytes(w);
        GGListFile f = new GGListFile(w, false);
        List<GGEntry> es = f.Entries();
        Check(es.Exists(delegate (GGEntry e) { return e.Text == "youtube.com" && e.On && e.Category == "Videos & Streaming"; }), "youtube.com: an, Abschnitt Videos & Streaming");
        Check(es.Exists(delegate (GGEntry e) { return e.Text == "amazon.com" && !e.On && e.Category == "Shopping"; }), "amazon.com: aus, Abschnitt Shopping");
        Check(!es.Exists(delegate (GGEntry e) { return e.Text.Contains(" die ") || e.Text.StartsWith("Lernvideos"); }), "Kommentare sind keine Einträge");
        Check(es.Exists(delegate (GGEntry e) { return e.Kind == "allow" && e.Display == "music.youtube.com"; }), "Ausnahme +music.youtube.com erkannt");
        Check(es.Exists(delegate (GGEntry e) { return e.Kind == "search" && e.Display == "Suche: casino"; }), "Suchbegriff erkannt");
        Check(es.Exists(delegate (GGEntry e) { return e.Text == "*.bet/*" && e.On; }), "Muster *.bet/* erkannt");

        // ---- Umschalten: aus und wieder an ergibt exakt dieselbe Datei ----
        f.Set(Find(f, "youtube.com"), false);
        f.Save();
        Check(File.ReadAllText(w).Contains("\r\n#youtube.com\r\n"), "youtube.com mit # ausgeschaltet, CRLF bleibt");
        f = new GGListFile(w, false);
        Check(!Find(f, "youtube.com").On, "bleibt nach dem Neuladen aus");
        f.Set(Find(f, "youtube.com"), true);
        f.Save();
        Check(Same(before, File.ReadAllBytes(w)), "aus und wieder an = Datei unverändert");

        // ---- Hinzufügen ----
        string err;
        Check(GGListFile.NormalizeSite("https://www.Chess.com/", out err) == "chess.com", "Adresse wird vereinheitlicht");
        Check(GGListFile.NormalizeSite("hallo welt", out err) == null, "Unsinn wird abgelehnt");
        Check(GGListFile.NormalizeSite("suche: Memes", out err) == "suche: memes", "Suchbegriff wird angenommen");
        Check(GGListFile.NormalizeSite("+Music.YouTube.com", out err) == "+music.youtube.com", "Ausnahme wird angenommen");
        f.Add("chess.com");
        f.Save();
        string t = File.ReadAllText(w);
        Check(Count(t, "chess.com") == 1 && t.Contains("\r\nchess.com\r\n"), "vorhandener #chess.com wird eingeschaltet statt doppelt");
        f.Add("example.org");
        f.Add("example.net");
        f.Save();
        t = File.ReadAllText(w);
        Check(Count(t, "# --- Eigene ---") == 1 && t.Contains("# --- Eigene ---\r\nexample.org\r\nexample.net\r\n"), "eigene Einträge landen im Abschnitt Eigene");
        f = new GGListFile(w, false);
        Check(Find(f, "example.net").Category == "Eigene", "Abschnitt Eigene wird gelesen");

        // ---- Programme ----
        string a = Path.Combine(tmp, "apps.txt");
        File.Copy(apps, a, true);
        GGListFile af = new GGListFile(a, true);
        Check(af.Entries().Exists(delegate (GGEntry e) { return e.Text == "steam" && e.On && e.Kind == "app"; }), "steam erkannt");
        Check(af.Entries().Exists(delegate (GGEntry e) { return e.Text == "Discord" && !e.On; }), "Discord (aus) erkannt");
        Check(GGListFile.NormalizeApp("Steam.exe", new string[] { "explorer" }, out err) == "Steam", "Programmname ohne .exe");
        Check(GGListFile.NormalizeApp("Explorer", new string[] { "explorer" }, out err) == null, "Systemprogramm wird abgelehnt");
        Check(GGListFile.NormalizeApp(@"C:\x\y.exe", null, out err) == null, "Pfad wird abgelehnt");

        // ---- Einstellungen ----
        string s = Path.Combine(tmp, "einstellungen.txt");
        File.Copy(settings, s, true);
        int lines = File.ReadAllLines(s).Length;
        GGKeyFile k = new GGKeyFile(s);
        Check(k.Get("TON", "") == "brutal", "TON gelesen");
        Check(k.GetInt("SPERRZEIT_MAX", 0, 3, 300) == 60, "SPERRZEIT_MAX gelesen");
        k.Set("TON", "ruhig", null);
        k.Set("DESIGN", "papier", "Design der Sperre");
        k.Save();
        k = new GGKeyFile(s);
        Check(k.Get("TON", "") == "ruhig" && k.Get("DESIGN", "") == "papier", "Werte gespeichert und neu gelesen");
        Check(File.ReadAllLines(s).Length == lines + 3, "Kommentare bleiben, neuer Schlüssel mit Kommentar angehängt");

        // ---- Versionen ----
        Check(GGUpdate.Newer("1.10", "1.9"), "1.10 ist neuer als 1.9");
        Check(!GGUpdate.Newer("1.4", "1.4"), "1.4 ist nicht neuer als 1.4");
        Check(GGUpdate.Newer("v2", "1.9"), "v2 ist neuer als 1.9");
        Check(!GGUpdate.Newer("kaputt", "1.0"), "Unsinn ist nie neuer");

        // ---- Sperrbildschirm: jedes Design zeichnet, auch mit leeren und sehr langen Texten ----
        List<string> q = new List<string>();
        foreach (string l in File.ReadAllLines(quotes, Encoding.UTF8)) if (l.Trim().Length > 0 && !l.StartsWith("#")) q.Add(l);
        string longText = new string('x', 40) + " " + string.Join(" ", q.ToArray());
        int[][] sizes = { new int[] { 1920, 1080 }, new int[] { 1366, 768 }, new int[] { 1080, 1920 }, new int[] { 800, 600 }, new int[] { 3840, 2160 } };
        foreach (string p in GGPlates.Names)
        {
            foreach (int[] z in sizes)
            {
                using (Bitmap b = GGPlates.Render(GGPlates.Sample(p, q.ToArray()), z[0], z[1], 0.4f, 12))
                {
                    if (b.Width != z[0] || b.Height != z[1]) Check(false, p + " " + z[0] + "x" + z[1] + ": falsche Grösse");
                }
            }
            GGLockContent empty = new GGLockContent();
            empty.Plate = p;
            using (Bitmap b = GGPlates.Render(empty, 1280, 720, 1f, 3)) { }
            GGLockContent huge = GGPlates.Sample(p, q.ToArray());
            huge.Quote = longText;
            huge.Detail = longText;
            huge.Head = longText;
            huge.Word = longText;
            using (Bitmap b = GGPlates.Render(huge, 1280, 720, 0f, 0)) { }
            Check(true, "Design " + p + ": alle Grössen, leer und überlang");
        }

        // ---- Logo ----
        string ico = Path.Combine(tmp, "grindguard.ico");
        GGBrand.SaveIco(ico);
        byte[] h = File.ReadAllBytes(ico);
        Check(h.Length > 1000 && h[0] == 0 && h[2] == 1 && h[4] == 9, "grindguard.ico mit 9 Grössen");
        using (Bitmap m = GGBrand.Mark(32, "fokus")) Check(m.GetPixel(2, 16).R > 150, "Fokus-Symbol ist rot");

        Console.WriteLine(fails == 0 ? "UI-Tests: alles ok" : ("UI-Tests: " + fails + " Fehler"));
        return fails;
    }
}
