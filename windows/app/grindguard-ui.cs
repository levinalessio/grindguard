// ============================================================================
//  GrindGuard für Windows – Oberfläche
//
//  Sperrbildschirm (fünf Designs), Logo und Taskleisten-Symbol, Menü,
//  Einstellungsfenster, Dialoge und die Tastensperre während der Sperre.
//  grindguard.ps1 kompiliert diese Datei beim Start mit Add-Type; sie braucht
//  nur Bordmittel von Windows (.NET Framework 4, C# 5).
//
//  Diese Datei ist als UTF-8 mit BOM gespeichert.
// ============================================================================
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Globalization;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
// ===================== Stil, Schriften, Text =====================
public static class GGStyle
{
    public static readonly Color Ink = Color.FromArgb(17, 17, 17);
    public static readonly Color Paper = Color.FromArgb(244, 241, 234);
    public static readonly Color Red = Color.FromArgb(226, 35, 42);
    public static readonly Color Cobalt = Color.FromArgb(44, 102, 214);
    public static readonly Color Oxblood = Color.FromArgb(122, 27, 34);
    public static readonly Color Marker = Color.FromArgb(222, 236, 46);
    public static readonly Color Cream = Color.FromArgb(242, 235, 221);

    static Dictionary<string, bool> installed;
    static readonly object gate = new object();

    public static bool Has(string family)
    {
        lock (gate)
        {
            if (installed == null)
            {
                installed = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
                try
                {
                    using (InstalledFontCollection fc = new InstalledFontCollection())
                    {
                        foreach (FontFamily f in fc.Families) installed[f.Name] = true;
                    }
                }
                catch { }
            }
            return installed.ContainsKey(family);
        }
    }

    public static string Pick(params string[] names)
    {
        foreach (string n in names) if (Has(n)) return n;
        return names[names.Length - 1];
    }

    public static string Serif { get { return Pick("Times New Roman", "Liberation Serif", "Georgia", "DejaVu Serif"); } }
    public static string Sans { get { return Pick("Arial", "Helvetica", "Liberation Sans", "DejaVu Sans"); } }
    public static string Narrow { get { return Pick("Arial Narrow", "Liberation Sans Narrow", "Arial", "Liberation Sans", "DejaVu Sans"); } }
    public static string Ui { get { return Pick("Segoe UI", "Liberation Sans", "DejaVu Sans"); } }
    public static string UiBold { get { return Pick("Segoe UI Semibold", "Segoe UI", "Liberation Sans", "DejaVu Sans"); } }

    public static Font Px(string family, float px, FontStyle style)
    {
        return new Font(family, Math.Max(1f, px), style, GraphicsUnit.Pixel);
    }

    public static Color A(Color c, int alpha)
    {
        return Color.FromArgb(Math.Max(0, Math.Min(255, alpha)), c.R, c.G, c.B);
    }

    public static void Quality(Graphics g)
    {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.AntiAlias;
        g.InterpolationMode = InterpolationMode.HighQualityBilinear;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g.CompositingQuality = CompositingQuality.HighQuality;
    }

    [ThreadStatic] static Dictionary<string, Bitmap> grains;

    // Filmkorn: helle und dunkle Punkte mit wenig Deckkraft, einmal erzeugt und gekachelt
    public static Bitmap Grain(int alphaMax, bool darkOnly)
    {
        string key = alphaMax + (darkOnly ? "d" : "m");
        if (grains == null) grains = new Dictionary<string, Bitmap>();
        {
            Bitmap b;
            if (grains.TryGetValue(key, out b)) return b;
            const int size = 192;
            b = new Bitmap(size, size, PixelFormat.Format32bppArgb);
            BitmapData d = b.LockBits(new Rectangle(0, 0, size, size), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            byte[] row = new byte[size * 4];
            Random rnd = new Random(20261125 + alphaMax);
            for (int y = 0; y < size; y++)
            {
                for (int x = 0; x < size; x++)
                {
                    byte c = (byte)((darkOnly || rnd.Next(2) == 0) ? 0 : 255);
                    int a = rnd.Next(alphaMax + 1);
                    if (rnd.Next(3) == 0) a = a / 3;
                    row[x * 4] = c; row[x * 4 + 1] = c; row[x * 4 + 2] = c; row[x * 4 + 3] = (byte)a;
                }
                Marshal.Copy(row, 0, new IntPtr(d.Scan0.ToInt64() + (long)y * d.Stride), row.Length);
            }
            b.UnlockBits(d);
            grains[key] = b;
            return b;
        }
    }

    public static void FillGrain(Graphics g, Rectangle r, int alphaMax, bool darkOnly)
    {
        if (alphaMax <= 0) return;
        using (TextureBrush t = new TextureBrush(Grain(alphaMax, darkOnly), WrapMode.Tile))
        {
            g.FillRectangle(t, r);
        }
    }
}

public static class GGText
{
    [ThreadStatic] static StringFormat typo;

    // GDI+-Objekte dürfen nicht von zwei Threads gleichzeitig benutzt werden: eines pro Thread
    public static StringFormat Typo
    {
        get
        {
            if (typo == null)
            {
                typo = (StringFormat)StringFormat.GenericTypographic.Clone();
                typo.FormatFlags |= StringFormatFlags.NoWrap | StringFormatFlags.NoClip | StringFormatFlags.MeasureTrailingSpaces;
                typo.Trimming = StringTrimming.None;
            }
            return typo;
        }
    }

    public static float Width(Graphics g, string s, Font f)
    {
        if (string.IsNullOrEmpty(s)) return 0f;
        return g.MeasureString(s, f, new PointF(0, 0), Typo).Width;
    }

    public static float Ascent(Font f)
    {
        FontFamily ff = f.FontFamily;
        return f.Size * ff.GetCellAscent(f.Style) / ff.GetEmHeight(f.Style);
    }

    // Höhe der Grossbuchstaben im Verhältnis zur Schriftgrösse (für sauberes Zentrieren)
    public static float CapRatio(Font f)
    {
        string n = f.FontFamily.Name.ToLowerInvariant();
        if (n.Contains("times") || n.Contains("serif") || n.Contains("georgia")) return 0.662f;
        return 0.716f;
    }

    public static List<string> Wrap(Graphics g, string text, Font f, float maxW)
    {
        List<string> lines = new List<string>();
        foreach (string para in (text ?? "").Replace("\r", "").Split('\n'))
        {
            string[] words = para.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            string cur = "";
            foreach (string w in words)
            {
                string t = cur.Length == 0 ? w : cur + " " + w;
                if (cur.Length > 0 && Width(g, t, f) > maxW)
                {
                    lines.Add(cur);
                    cur = w;
                }
                else cur = t;
            }
            if (cur.Length > 0) lines.Add(cur);
        }
        return lines;
    }

    public static float Widest(Graphics g, List<string> lines, Font f)
    {
        float m = 0f;
        foreach (string l in lines) m = Math.Max(m, Width(g, l, f));
        return m;
    }

    public static string Ellipsize(Graphics g, string s, Font f, float maxW)
    {
        if (Width(g, s, f) <= maxW) return s;
        string t = s.TrimEnd(' ', '.', ',', '…');
        while (t.Length > 1 && Width(g, t + "…", f) > maxW) t = t.Substring(0, t.Length - 1).TrimEnd();
        return t + "…";
    }

    // Grösste Schrift (bis startPx), bei der der Text in den Kasten passt.
    public static List<string> Fit(Graphics g, string text, string family, FontStyle st, float startPx, float minPx,
        float maxW, float maxH, float lead, int maxLines, out Font font)
    {
        text = (text ?? "").Trim();
        float px = Math.Max(minPx, startPx);
        while (true)
        {
            Font f = GGStyle.Px(family, px, st);
            List<string> lines = Wrap(g, text, f, maxW);
            bool fits = (maxLines <= 0 || lines.Count <= maxLines)
                && lines.Count * px * lead <= maxH + 0.5f
                && Widest(g, lines, f) <= maxW + 0.5f;
            if (fits)
            {
                font = f;
                return lines;
            }
            if (px <= minPx + 0.01f)
            {
                int keep = Math.Max(1, (int)Math.Floor((maxH + 0.5f) / (px * lead)));
                if (maxLines > 0) keep = Math.Min(keep, maxLines);
                if (lines.Count > keep)
                {
                    lines = lines.GetRange(0, keep);
                    lines[keep - 1] = lines[keep - 1] + " …";
                }
                for (int i = 0; i < lines.Count; i++) lines[i] = Ellipsize(g, lines[i], f, maxW);
                font = f;
                return lines;
            }
            f.Dispose();
            px = Math.Max(minPx, px * 0.93f);
        }
    }

    // align: 0 = links, 1 = Mitte, 2 = rechts (x ist dann die Mitte bzw. der rechte Rand)
    public static float Lines(Graphics g, List<string> lines, Font f, Color c, float x, float y, float lead, int align)
    {
        using (SolidBrush b = new SolidBrush(c))
        {
            for (int i = 0; i < lines.Count; i++)
            {
                float w = Width(g, lines[i], f);
                float lx = align == 0 ? x : (align == 1 ? x - w / 2f : x - w);
                g.DrawString(lines[i], f, b, lx, y + i * f.Size * lead, Typo);
            }
        }
        return y + lines.Count * f.Size * lead;
    }

    public static float TrackedWidth(Graphics g, string s, Font f, float track)
    {
        float w = 0f;
        foreach (char ch in s ?? "") w += Width(g, ch.ToString(), f) + track;
        return Math.Max(0f, w - track);
    }

    public static void Tracked(Graphics g, string s, Font f, Color c, float x, float y, float track, int align)
    {
        if (string.IsNullOrEmpty(s)) return;
        float w = TrackedWidth(g, s, f, track);
        float cx = align == 0 ? x : (align == 1 ? x - w / 2f : x - w);
        using (SolidBrush b = new SolidBrush(c))
        {
            foreach (char ch in s)
            {
                string t = ch.ToString();
                g.DrawString(t, f, b, cx, y, Typo);
                cx += Width(g, t, f) + track;
            }
        }
    }
}

// ===================== Sperrbildschirm =====================
public class GGLockContent
{
    public string Plate = "nacht";
    public string Head = "";
    public string Quote = "";
    public string Detail = "";
    public string Counter = "";
    public string Word = "";
    public string WordClass = "";
    public string Line = "";
    public string[] Page = new string[0];
    public string Brand = "grindguard";
}

public class GGPlateLayout
{
    public RectangleF Ring;
    public Color Track, Fore, Number;
    public string NumFamily = "Arial";
    public FontStyle NumStyle = FontStyle.Regular;
    public float NumScale = 0.36f;
    public float Stroke = 4f;
    public List<PointF> LinePos = new List<PointF>();
    public string LineText = "";
    public string LineFamily = "Arial";
    public float LinePx = 10f;
    public Color LineOn;
    public RectangleF LinesRect;
}

public static class GGPlates
{
    public static readonly string[] Names = { "nacht", "kobalt", "papier", "lexikon", "bordeaux" };

    public static GGPlateLayout DrawStatic(Graphics g, GGLockContent c, int W, int H)
    {
        GGStyle.Quality(g);
        string p = (c.Plate ?? "").ToLowerInvariant();
        if (p == "kobalt") return Kobalt(g, c, W, H);
        if (p == "papier") return Papier(g, c, W, H);
        if (p == "lexikon") return Lexikon(g, c, W, H);
        if (p == "bordeaux") return Bordeaux(g, c, W, H);
        return Nacht(g, c, W, H);
    }

    // Kobalt: wie viele der Zeilen schon "geschrieben" sind
    public static int Filled(GGPlateLayout L, float progress)
    {
        int n = L.LinePos.Count;
        int k = (int)Math.Ceiling((1f - Math.Max(0f, Math.Min(1f, progress))) * n - 0.0001f);
        return Math.Max(0, Math.Min(n, k));
    }

    public static void DrawDynamic(Graphics g, GGPlateLayout L, float progress, int seconds)
    {
        DrawDynamic(g, L, progress, seconds, Rectangle.Empty);
    }

    public static void DrawDynamic(Graphics g, GGPlateLayout L, float progress, int seconds, Rectangle clip)
    {
        GGStyle.Quality(g);
        if (L.LinePos.Count > 0 && (clip.IsEmpty || clip.IntersectsWith(Rectangle.Ceiling(L.LinesRect))))
        {
            int k = Filled(L, progress);
            using (Font f = GGStyle.Px(L.LineFamily, L.LinePx, FontStyle.Regular))
            using (SolidBrush b = new SolidBrush(L.LineOn))
            {
                for (int i = 0; i < k; i++) g.DrawString(L.LineText, f, b, L.LinePos[i].X, L.LinePos[i].Y, GGText.Typo);
            }
        }
        RectangleF r = L.Ring;
        if (r.Width < 4) return;
        if (!clip.IsEmpty && !clip.IntersectsWith(Rectangle.Ceiling(RectangleF.Inflate(r, 4, 4)))) return;
        float sw = L.Stroke;
        RectangleF a = new RectangleF(r.X + sw / 2f, r.Y + sw / 2f, r.Width - sw, r.Height - sw);
        using (Pen t = new Pen(L.Track, sw)) g.DrawEllipse(t, a);
        float pr = Math.Max(0f, Math.Min(1f, progress));
        if (pr > 0.002f)
        {
            using (Pen pen = new Pen(L.Fore, sw))
            {
                g.DrawArc(pen, a, -90f, 360f * pr);
            }
        }
        string s = seconds.ToString(CultureInfo.InvariantCulture);
        using (Font f = GGStyle.Px(L.NumFamily, r.Height * L.NumScale, L.NumStyle))
        using (SolidBrush b = new SolidBrush(L.Number))
        {
            float w = GGText.Width(g, s, f);
            float cap = f.Size * GGText.CapRatio(f);
            float y = r.Y + r.Height / 2f - GGText.Ascent(f) + cap / 2f;
            g.DrawString(s, f, b, r.X + (r.Width - w) / 2f, y, GGText.Typo);
        }
    }

    static float RingBase(int W, int H)
    {
        return Math.Min(H, W * 0.75f);
    }

    static float Unit(int W, int H)
    {
        return Math.Max(0.35f, Math.Min(W / 1920f, H / 1080f));
    }

    static void Radial(Graphics g, RectangleF ellipse, Color center, Color edge)
    {
        using (GraphicsPath gp = new GraphicsPath())
        {
            gp.AddEllipse(ellipse);
            using (PathGradientBrush pb = new PathGradientBrush(gp))
            {
                pb.CenterColor = center;
                pb.SurroundColors = new Color[] { edge };
                g.FillPath(pb, gp);
            }
        }
    }

    // ---- NACHT: Nachtblau, weisse Grotesk oben links, roter Spruch unten rechts ----
    static GGPlateLayout Nacht(Graphics g, GGLockContent c, int W, int H)
    {
        float u = Unit(W, H);
        Rectangle all = new Rectangle(0, 0, W, H);
        using (LinearGradientBrush bg = new LinearGradientBrush(all, Color.FromArgb(7, 11, 21), Color.FromArgb(22, 34, 56), 90f))
        {
            g.FillRectangle(bg, all);
        }
        Radial(g, new RectangleF(-0.45f * H, 0.42f * H, 1.25f * H, 1.1f * H), Color.FromArgb(62, 255, 168, 84), Color.FromArgb(0, 255, 168, 84));
        GGStyle.FillGrain(g, all, 22, false);

        float m = Math.Max(24f, W * 0.065f);
        Color white = Color.FromArgb(246, 244, 238);
        using (Font f = GGStyle.Px(GGStyle.Serif, 24f * u, FontStyle.Italic))
        {
            GGText.Lines(g, new List<string> { c.Brand }, f, GGStyle.A(white, 150), W / 2f, H * 0.045f, 1f, 1);
        }
        using (Font f = GGStyle.Px(GGStyle.Sans, 14f * u, FontStyle.Bold))
        {
            GGText.Tracked(g, (c.Counter ?? "").ToUpperInvariant(), f, GGStyle.A(white, 150), W - m, H * 0.05f, 2.6f * u, 2);
        }

        Font hf;
        List<string> head = GGText.Fit(g, c.Head, GGStyle.Sans, FontStyle.Bold, 170f * u, 64f * u, W * 0.6f, H * 0.38f, 0.95f, 3, out hf);
        float y = H * 0.15f;
        float hb = GGText.Lines(g, head, hf, white, m - hf.Size * 0.06f, y, 0.95f, 0) + hf.Size * 0.08f;
        hf.Dispose();

        Font df;
        List<string> det = GGText.Fit(g, c.Detail, GGStyle.Sans, FontStyle.Regular, 25f * u, 16f * u, W * 0.4f, H * 0.12f, 1.35f, 3, out df);
        GGText.Lines(g, det, df, GGStyle.A(white, 185), m, hb + H * 0.035f, 1.35f, 0);
        df.Dispose();

        float bottom = H * 0.88f;
        Font qf;
        List<string> q = GGText.Fit(g, c.Quote, GGStyle.Sans, FontStyle.Bold, 66f * u, 30f * u, W * 0.5f, H * 0.3f, 1.04f, 5, out qf);
        float qh = q.Count * qf.Size * 1.04f;
        GGText.Lines(g, q, qf, GGStyle.Red, W - m, bottom - qh, 1.04f, 2);
        qf.Dispose();

        GGPlateLayout L = new GGPlateLayout();
        float d = RingBase(W, H) * 0.17f;
        L.Ring = new RectangleF(m, bottom - d, d, d);
        L.Track = GGStyle.A(white, 40);
        L.Fore = white;
        L.Number = white;
        L.NumFamily = GGStyle.Sans;
        L.NumStyle = FontStyle.Bold;
        L.NumScale = 0.34f;
        L.Stroke = Math.Max(3f, d * 0.028f);
        return L;
    }

    // ---- KOBALT: Strafarbeit – derselbe Satz neunmal, er "schreibt" sich mit der Zeit ----
    static GGPlateLayout Kobalt(Graphics g, GGLockContent c, int W, int H)
    {
        float u = Unit(W, H);
        Rectangle all = new Rectangle(0, 0, W, H);
        using (SolidBrush bg = new SolidBrush(GGStyle.Cobalt)) g.FillRectangle(bg, all);
        GGStyle.FillGrain(g, all, 6, false);
        float m = Math.Max(24f, W * 0.065f);
        Color ink = Color.FromArgb(10, 12, 18);

        using (Font f = GGStyle.Px(GGStyle.Narrow, 34f * u, FontStyle.Bold))
        {
            GGText.Lines(g, new List<string> { c.Head }, f, ink, m, H * 0.065f, 1f, 0);
        }
        Font df;
        List<string> det = GGText.Fit(g, c.Detail, GGStyle.Narrow, FontStyle.Regular, 22f * u, 15f * u, W * 0.42f, H * 0.08f, 1.3f, 2, out df);
        GGText.Lines(g, det, df, GGStyle.A(ink, 190), m, H * 0.065f + 46f * u, 1.3f, 0);
        df.Dispose();
        using (Font f = GGStyle.Px(GGStyle.Narrow, 15f * u, FontStyle.Bold))
        {
            GGText.Tracked(g, (c.Counter ?? "").ToUpperInvariant(), f, GGStyle.A(ink, 170), W - m, H * 0.072f, 2.2f * u, 2);
        }

        GGPlateLayout L = new GGPlateLayout();
        string line = string.IsNullOrEmpty(c.Line) ? c.Head : c.Line;
        const int n = 9;
        const float lead = 1.1f;
        float top = H * 0.21f, blockH = H * 0.54f;
        float px = Math.Min(blockH / (n * lead), 96f * u);
        Font lf = GGStyle.Px(GGStyle.Narrow, px, FontStyle.Regular);
        while (GGText.Width(g, line, lf) > W * 0.8f && px > 12f)
        {
            lf.Dispose();
            px *= 0.95f;
            lf = GGStyle.Px(GGStyle.Narrow, px, FontStyle.Regular);
        }
        float lw = GGText.Width(g, line, lf);
        float x = (W - lw) / 2f;
        float y0 = top + (blockH - n * px * lead) / 2f;
        using (SolidBrush faint = new SolidBrush(GGStyle.A(ink, 48)))
        {
            for (int i = 0; i < n; i++)
            {
                PointF pt = new PointF(x, y0 + i * px * lead);
                L.LinePos.Add(pt);
                g.DrawString(line, lf, faint, pt.X, pt.Y, GGText.Typo);
            }
        }
        L.LineText = line;
        L.LineFamily = GGStyle.Narrow;
        L.LinePx = px;
        L.LineOn = ink;
        L.LinesRect = new RectangleF(x - px * 0.2f, y0 - px * 0.2f, lw + px * 0.4f, n * px * lead + px * 0.6f);
        lf.Dispose();

        float bottom = H * 0.92f;
        float d = RingBase(W, H) * 0.12f;
        Font qf;
        List<string> q = GGText.Fit(g, c.Quote, GGStyle.Narrow, FontStyle.Regular, 30f * u, 18f * u, W * 0.55f, d * 1.05f, 1.22f, 3, out qf);
        float qh = q.Count * qf.Size * 1.22f;
        GGText.Lines(g, q, qf, ink, m, bottom - qh, 1.22f, 0);
        qf.Dispose();

        L.Ring = new RectangleF(W - m - d, bottom - d, d, d);
        L.Track = GGStyle.A(ink, 46);
        L.Fore = ink;
        L.Number = ink;
        L.NumFamily = GGStyle.Narrow;
        L.NumStyle = FontStyle.Bold;
        L.NumScale = 0.36f;
        L.Stroke = Math.Max(3f, d * 0.03f);
        return L;
    }

    // ---- PAPIER: Buchseite, ein Satz mit Textmarker ----
    static GGPlateLayout Papier(Graphics g, GGLockContent c, int W, int H)
    {
        float u = Unit(W, H);
        Rectangle all = new Rectangle(0, 0, W, H);
        using (SolidBrush bg = new SolidBrush(Color.FromArgb(220, 218, 212))) g.FillRectangle(bg, all);
        Ghost(g, c, W, H, u);
        Radial(g, new RectangleF(-0.25f * W, -0.35f * H, 1.5f * W, 1.7f * H), Color.FromArgb(0, 0, 0, 0), Color.FromArgb(70, 0, 0, 0));
        GGStyle.FillGrain(g, all, 20, false);

        Color ink = Color.FromArgb(22, 22, 22);
        float m = Math.Max(24f, W * 0.065f);
        using (Font f = GGStyle.Px(GGStyle.Serif, 21f * u, FontStyle.Italic))
        {
            GGText.Lines(g, new List<string> { c.Brand }, f, GGStyle.A(ink, 150), m, H * 0.05f, 1f, 0);
        }
        using (Font f = GGStyle.Px(GGStyle.Serif, 15f * u, FontStyle.Regular))
        {
            GGText.Tracked(g, (c.Counter ?? "").ToUpperInvariant(), f, GGStyle.A(ink, 150), W - m, H * 0.055f, 2.4f * u, 2);
        }

        Font qf;
        const float lead = 1.5f;
        List<string> q = GGText.Fit(g, c.Quote, GGStyle.Serif, FontStyle.Regular, 50f * u, 26f * u, W * 0.58f, H * 0.36f, lead, 5, out qf);
        float qh = q.Count * qf.Size * lead;
        float top = H * 0.47f - qh / 2f;

        using (Font f = GGStyle.Px(GGStyle.Serif, 17f * u, FontStyle.Regular))
        {
            GGText.Tracked(g, (c.Head ?? "").ToUpperInvariant(), f, GGStyle.A(ink, 175), W / 2f, top - H * 0.075f, 3.2f * u, 1);
        }
        using (SolidBrush mark = new SolidBrush(GGStyle.A(GGStyle.Marker, 236)))
        {
            for (int i = 0; i < q.Count; i++)
            {
                float w = GGText.Width(g, q[i], qf);
                float ly = top + i * qf.Size * lead;
                float pad = qf.Size * 0.22f;
                g.FillRectangle(mark, W / 2f - w / 2f - pad, ly + qf.Size * 0.08f, w + 2 * pad, qf.Size * 1.08f);
            }
        }
        GGText.Lines(g, q, qf, ink, W / 2f, top, lead, 1);
        qf.Dispose();

        Font df;
        List<string> det = GGText.Fit(g, c.Detail, GGStyle.Serif, FontStyle.Italic, 23f * u, 16f * u, W * 0.5f, H * 0.08f, 1.35f, 2, out df);
        GGText.Lines(g, det, df, GGStyle.A(ink, 190), W / 2f, top + qh + H * 0.045f, 1.35f, 1);
        df.Dispose();

        GGPlateLayout L = new GGPlateLayout();
        float d = RingBase(W, H) * 0.095f;
        L.Ring = new RectangleF(W / 2f - d / 2f, H * 0.9f - d, d, d);
        L.Track = GGStyle.A(ink, 34);
        L.Fore = ink;
        L.Number = ink;
        L.NumFamily = GGStyle.Serif;
        L.NumStyle = FontStyle.Regular;
        L.NumScale = 0.42f;
        L.Stroke = Math.Max(2f, d * 0.022f);
        return L;
    }

    // unscharfe Buchseite im Hintergrund: klein gezeichnet, gross gezogen
    static void Ghost(Graphics g, GGLockContent c, int W, int H, float u)
    {
        StringBuilder sb = new StringBuilder();
        string[] page = (c.Page != null && c.Page.Length > 0) ? c.Page : new string[] { c.Quote };
        int guard = 0;
        while (sb.Length < 6000 && guard++ < 400)
        {
            foreach (string s in page) { if (!string.IsNullOrEmpty(s)) sb.Append(s.Trim()).Append(' '); }
            if (sb.Length == 0) break;
        }
        if (sb.Length == 0) return;
        const int k = 7;
        int sw = Math.Max(16, W / k), sh = Math.Max(16, H / k);
        using (Bitmap small = new Bitmap(sw, sh, PixelFormat.Format32bppArgb))
        {
            using (Graphics sg = Graphics.FromImage(small))
            {
                GGStyle.Quality(sg);
                sg.Clear(Color.Transparent);
                using (Font f = GGStyle.Px(GGStyle.Serif, 31f * u / k, FontStyle.Regular))
                {
                    float x0 = sw * 0.17f, w = sw * 0.66f;
                    List<string> lines = GGText.Wrap(sg, sb.ToString(), f, w);
                    float lh = f.Size * 1.62f;
                    int count = (int)((sh * 0.86f) / lh);
                    using (SolidBrush b = new SolidBrush(Color.FromArgb(150, 25, 25, 25)))
                    {
                        for (int i = 0; i < count && i < lines.Count; i++)
                            sg.DrawString(lines[i], f, b, x0, sh * 0.07f + i * lh, GGText.Typo);
                    }
                }
            }
            InterpolationMode im = g.InterpolationMode;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            using (ImageAttributes ia = new ImageAttributes())
            {
                ColorMatrix cm = new ColorMatrix();
                cm.Matrix33 = 0.3f;
                ia.SetColorMatrix(cm);
                g.DrawImage(small, new Rectangle(0, 0, W, H), 0, 0, sw, sh, GraphicsUnit.Pixel, ia);
            }
            g.InterpolationMode = im;
        }
    }

    // ---- LEXIKON: Wörterbucheintrag auf weissem Papier ----
    static GGPlateLayout Lexikon(Graphics g, GGLockContent c, int W, int H)
    {
        float u = Unit(W, H);
        Rectangle all = new Rectangle(0, 0, W, H);
        using (SolidBrush bg = new SolidBrush(Color.FromArgb(251, 250, 246))) g.FillRectangle(bg, all);
        GGStyle.FillGrain(g, all, 10, true);
        Color ink = Color.FromArgb(16, 16, 16);
        Color gray = Color.FromArgb(120, 120, 116);
        float m = Math.Max(24f, W * 0.065f);
        float x = Math.Max(m, W * 0.11f);

        using (Font f = GGStyle.Px(GGStyle.Serif, 21f * u, FontStyle.Italic))
        {
            GGText.Lines(g, new List<string> { c.Brand }, f, gray, m, H * 0.05f, 1f, 0);
        }
        using (Font f = GGStyle.Px(GGStyle.Sans, 13f * u, FontStyle.Regular))
        {
            GGText.Tracked(g, (c.Counter ?? "").ToUpperInvariant(), f, gray, W - m, H * 0.055f, 2.4f * u, 2);
        }

        string word = string.IsNullOrEmpty(c.Word) ? c.Head : c.Word;
        Font wf;
        List<string> w = GGText.Fit(g, word, GGStyle.Serif, FontStyle.Regular, 156f * u, 64f * u, W * 0.78f, H * 0.2f, 1f, 1, out wf);
        float y = H * 0.2f;
        GGText.Lines(g, w, wf, ink, x - wf.Size * 0.04f, y, 1f, 0);
        float y2 = y + wf.Size * 1.08f;
        wf.Dispose();
        using (Font f = GGStyle.Px(GGStyle.Serif, 30f * u, FontStyle.Regular))
        {
            GGText.Lines(g, new List<string> { c.WordClass ?? "" }, f, ink, x + 6f * u, y2 + H * 0.015f, 1f, 0);
        }
        Font df;
        List<string> def = GGText.Fit(g, c.Quote, GGStyle.Serif, FontStyle.Regular, 40f * u, 24f * u, W * 0.6f, H * 0.3f, 1.42f, 6, out df);
        GGText.Lines(g, def, df, ink, x + 6f * u, y2 + H * 0.12f, 1.42f, 0);
        df.Dispose();

        float bottom = H * 0.9f;
        Font tf;
        List<string> det = GGText.Fit(g, c.Detail, GGStyle.Serif, FontStyle.Italic, 22f * u, 15f * u, W * 0.5f, H * 0.08f, 1.35f, 2, out tf);
        GGText.Lines(g, det, tf, gray, x + 6f * u, bottom - det.Count * tf.Size * 1.35f, 1.35f, 0);
        tf.Dispose();

        GGPlateLayout L = new GGPlateLayout();
        float d = RingBase(W, H) * 0.11f;
        L.Ring = new RectangleF(W - m - d, bottom - d, d, d);
        L.Track = GGStyle.A(ink, 28);
        L.Fore = ink;
        L.Number = ink;
        L.NumFamily = GGStyle.Serif;
        L.NumScale = 0.42f;
        L.Stroke = Math.Max(2f, d * 0.022f);
        return L;
    }

    // ---- BORDEAUX: ruhig, cremefarbene Serifen auf Ochsenblut ----
    static GGPlateLayout Bordeaux(Graphics g, GGLockContent c, int W, int H)
    {
        float u = Unit(W, H);
        Rectangle all = new Rectangle(0, 0, W, H);
        using (SolidBrush bg = new SolidBrush(GGStyle.Oxblood)) g.FillRectangle(bg, all);
        Radial(g, new RectangleF(-0.1f * W, -0.2f * H, 1.2f * W, 1.4f * H), Color.FromArgb(60, 160, 48, 56), Color.FromArgb(0, 160, 48, 56));
        GGStyle.FillGrain(g, all, 18, false);
        Color cream = GGStyle.Cream;
        float m = Math.Max(24f, W * 0.065f);

        using (Font f = GGStyle.Px(GGStyle.Serif, 22f * u, FontStyle.Italic))
        {
            GGText.Lines(g, new List<string> { c.Brand }, f, GGStyle.A(cream, 160), W / 2f, H * 0.05f, 1f, 1);
        }
        using (Font f = GGStyle.Px(GGStyle.Sans, 13f * u, FontStyle.Regular))
        {
            GGText.Tracked(g, (c.Counter ?? "").ToUpperInvariant(), f, GGStyle.A(cream, 150), W - m, H * 0.055f, 2.4f * u, 2);
        }
        Font qf;
        const float lead = 1.3f;
        List<string> q = GGText.Fit(g, c.Quote, GGStyle.Serif, FontStyle.Regular, 60f * u, 28f * u, W * 0.62f, H * 0.36f, lead, 5, out qf);
        float qh = q.Count * qf.Size * lead;
        float top = H * 0.45f - qh / 2f;
        using (Font f = GGStyle.Px(GGStyle.Sans, 15f * u, FontStyle.Bold))
        {
            GGText.Tracked(g, (c.Head ?? "").ToUpperInvariant(), f, GGStyle.A(cream, 200), W / 2f, top - H * 0.08f, 3.4f * u, 1);
        }
        GGText.Lines(g, q, qf, cream, W / 2f, top, lead, 1);
        qf.Dispose();
        Font df;
        List<string> det = GGText.Fit(g, c.Detail, GGStyle.Serif, FontStyle.Italic, 23f * u, 16f * u, W * 0.5f, H * 0.08f, 1.35f, 2, out df);
        GGText.Lines(g, det, df, GGStyle.A(cream, 185), W / 2f, top + qh + H * 0.04f, 1.35f, 1);
        df.Dispose();

        GGPlateLayout L = new GGPlateLayout();
        float d = RingBase(W, H) * 0.11f;
        L.Ring = new RectangleF(W / 2f - d / 2f, H * 0.9f - d, d, d);
        L.Track = GGStyle.A(cream, 46);
        L.Fore = cream;
        L.Number = cream;
        L.NumFamily = GGStyle.Serif;
        L.NumScale = 0.42f;
        L.Stroke = Math.Max(2f, d * 0.022f);
        return L;
    }

    // Beispielinhalt für Vorschaubilder und das CI
    public static GGLockContent Sample(string plate, string[] quotes)
    {
        GGLockContent c = new GGLockContent();
        c.Plate = plate;
        c.Page = quotes ?? new string[0];
        c.Counter = "Ausrutscher 02 · 15 s";
        c.Detail = "youtube.com wurde geschlossen. Zweiter Ausrutscher heute.";
        c.Quote = (quotes != null && quotes.Length > 0) ? quotes[0] : "Fokus ist kein Gefühl. Fokus ist eine Entscheidung. Triff sie.";
        c.Head = "Schon wieder.";
        if (plate == "kobalt") { c.Head = "Ablenkung gesperrt."; c.Line = "Ich arbeite jetzt weiter."; }
        if (plate == "papier" || plate == "bordeaux") c.Head = "Kurz zurück.";
        if (plate == "lexikon")
        {
            c.Word = "Prokrastination.";
            c.WordClass = "(Nomen)";
            c.Quote = "Das, was du gerade machst, statt das, was du dir vorgenommen hast.";
        }
        return c;
    }

    // Für Vorschau, Einstellungen und CI: komplettes Bild in einem Rutsch
    public static Bitmap Render(GGLockContent c, int W, int H, float progress, int seconds)
    {
        Bitmap b = new Bitmap(W, H, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(b))
        {
            GGPlateLayout L = DrawStatic(g, c, W, H);
            DrawDynamic(g, L, progress, seconds);
        }
        return b;
    }
}

// Ein Bildschirm der Sperre: zeichnet den Hintergrund einmal, danach nur noch Ring und Zeilen
public class GGPoster : Control
{
    readonly GGLockContent content;
    Bitmap cache;
    GGPlateLayout layout;
    float progress = 1f;
    int seconds;
    int filled = -1;

    public GGPoster(GGLockContent c)
    {
        content = c;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.UserPaint | ControlStyles.Opaque, true);
    }

    void Build()
    {
        if (Width < 8 || Height < 8) return;
        if (cache != null) cache.Dispose();
        cache = new Bitmap(Width, Height, PixelFormat.Format32bppPArgb);
        using (Graphics g = Graphics.FromImage(cache)) layout = GGPlates.DrawStatic(g, content, Width, Height);
    }

    protected override void OnSizeChanged(EventArgs e)
    {
        base.OnSizeChanged(e);
        Build();
        Invalidate();
    }

    public void SetTime(float p, int s)
    {
        if (layout == null) Build();
        if (layout == null) return;
        bool ring = s != seconds || Math.Abs(p - progress) > 0.0015f;
        progress = p;
        seconds = s;
        if (ring) Invalidate(Rectangle.Inflate(Rectangle.Ceiling(layout.Ring), 6, 6));
        if (layout.LinePos.Count > 0)
        {
            int k = GGPlates.Filled(layout, p);
            if (k != filled)
            {
                filled = k;
                Invalidate(Rectangle.Inflate(Rectangle.Ceiling(layout.LinesRect), 6, 6));
            }
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        if (cache == null) Build();
        if (cache == null) return;
        Rectangle clip = e.ClipRectangle;
        e.Graphics.DrawImage(cache, clip, clip, GraphicsUnit.Pixel);
        GGPlates.DrawDynamic(e.Graphics, layout, progress, seconds, clip);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing && cache != null)
        {
            cache.Dispose();
            cache = null;
        }
        base.Dispose(disposing);
    }
}

// Das Sperrfenster für einen Bildschirm
public class GGLockWindow : Form
{
    public static bool Done = true;     // erst wenn die Zeit um ist, darf das Fenster zu
    public readonly GGPoster Poster;

    public GGLockWindow(Rectangle bounds, GGLockContent c)
    {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Bounds = bounds;
        TopMost = true;
        ShowInTaskbar = false;
        Text = "GrindGuard";
        BackColor = Color.Black;
        Poster = new GGPoster(c);
        Poster.Dock = DockStyle.Fill;
        Controls.Add(Poster);
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!Done) e.Cancel = true;
        base.OnFormClosing(e);
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        GGLockGuard.MarkFullscreen(Handle, true);
    }
}

// Während der Sperre: Taskleiste nach hinten, Windows-Taste, Alt+Tab & Co. aus
public static class GGLockGuard
{
    delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [ComImport, Guid("602D4995-B13A-429b-A66E-1935E44F4317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ITaskbarList2
    {
        [PreserveSig] int HrInit();
        [PreserveSig] int AddTab(IntPtr hwnd);
        [PreserveSig] int DeleteTab(IntPtr hwnd);
        [PreserveSig] int ActivateTab(IntPtr hwnd);
        [PreserveSig] int SetActiveAlt(IntPtr hwnd);
        [PreserveSig] int MarkFullscreenWindow(IntPtr hwnd, [MarshalAs(UnmanagedType.Bool)] bool fullscreen);
    }

    [ComImport, Guid("56FDF344-FD6D-11d0-958A-006097C9A090"), ClassInterface(ClassInterfaceType.None)]
    class TaskbarList { }

    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll")]
    static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")]
    static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll")]
    static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")]
    static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr processId);
    [DllImport("kernel32.dll")]
    static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")]
    static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")]
    static extern bool IsHungAppWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    static HookProc proc;
    static IntPtr hook = IntPtr.Zero;
    static bool lwin, rwin;
    public static int Blocked;

    public static bool Engage()
    {
        if (hook != IntPtr.Zero) return true;
        lwin = rwin = false;
        Blocked = 0;
        try
        {
            proc = Callback;
            hook = SetWindowsHookEx(13, proc, GetModuleHandle("user32.dll"), 0);   // 13 = WH_KEYBOARD_LL
        }
        catch { hook = IntPtr.Zero; }
        return hook != IntPtr.Zero;
    }

    public static void Release()
    {
        if (hook != IntPtr.Zero)
        {
            try { UnhookWindowsHookEx(hook); } catch { }
            hook = IntPtr.Zero;
        }
        lwin = rwin = false;
    }

    static bool Down(int vk)
    {
        return (GetAsyncKeyState(vk) & 0x8000) != 0;
    }

    static IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        try
        {
            if (nCode >= 0)
            {
                KBDLLHOOKSTRUCT k = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
                int msg = wParam.ToInt32();
                bool down = msg == 0x100 || msg == 0x104;
                bool injected = (k.flags & 0x10) != 0;
                if (!injected && Swallow(k.vkCode, down, (k.flags & 0x20) != 0))
                {
                    Blocked++;
                    return new IntPtr(1);
                }
            }
        }
        catch { }
        return CallNextHookEx(hook, nCode, wParam, lParam);
    }

    // Tasten-Aufheben nur schlucken, wenn wir auch das Drücken geschluckt haben –
    // sonst bleibt nach der Sperre eine Taste "hängen".
    static bool Swallow(uint vk, bool down, bool alt)
    {
        if (vk == 0x5B) { if (down) { lwin = true; return true; } if (lwin) { lwin = false; return true; } return false; }
        if (vk == 0x5C) { if (down) { rwin = true; return true; } if (rwin) { rwin = false; return true; } return false; }
        if (!down) return false;
        if (Down(0x5B) || Down(0x5C)) return true;       // Windows-Taste schon vor der Sperre gedrückt
        bool ctrl = Down(0x11);
        if (vk == 0x09 && alt) return true;               // Alt+Tab
        if (vk == 0x1B && (alt || ctrl)) return true;     // Alt+Esc, Strg+Esc, Strg+Umschalt+Esc
        if (vk == 0x73 && alt) return true;               // Alt+F4
        if (vk == 0x5D) return true;                      // Kontextmenü-Taste
        return false;
    }

    public static void MarkFullscreen(IntPtr hwnd, bool on)
    {
        try
        {
            ITaskbarList2 t = (ITaskbarList2)new TaskbarList();
            t.HrInit();
            t.MarkFullscreenWindow(hwnd, on);
            Marshal.ReleaseComObject(t);
        }
        catch { }
    }

    public static bool IsFront(IntPtr[] mine)
    {
        IntPtr f = GetForegroundWindow();
        foreach (IntPtr h in mine) if (h == f) return true;
        return false;
    }

    // Vorne bleiben, auch wenn Windows das Fokus-Stehlen sonst unterbindet
    public static void Front(IntPtr hwnd)
    {
        try
        {
            IntPtr fg = GetForegroundWindow();
            if (fg == hwnd) return;
            uint me = GetCurrentThreadId();
            uint other = fg == IntPtr.Zero ? 0 : GetWindowThreadProcessId(fg, IntPtr.Zero);
            // nie an ein hängendes Programm koppeln – sonst hinge die Sperre mit
            bool hung = false;
            try { hung = fg != IntPtr.Zero && IsHungAppWindow(fg); } catch { }
            bool attached = !hung && other != 0 && other != me && AttachThreadInput(me, other, true);
            BringWindowToTop(hwnd);
            SetForegroundWindow(hwnd);
            if (attached) AttachThreadInput(me, other, false);
            if (GetForegroundWindow() != hwnd)
            {
                keybd_event(0x12, 0, 0, UIntPtr.Zero);          // kurzes Alt erlaubt den Wechsel
                SetForegroundWindow(hwnd);
                keybd_event(0x12, 0, 2, UIntPtr.Zero);
            }
        }
        catch { }
    }
}
// ===================== Logo und Symbole =====================
public static class GGBrand
{
    public static Color Back(string state)
    {
        if (state == "fokus") return Color.FromArgb(196, 24, 32);
        if (state == "pause") return Color.FromArgb(128, 128, 124);
        return GGStyle.Ink;
    }

    public static Color Dot(string state)
    {
        if (state == "fokus") return GGStyle.Paper;
        if (state == "pause") return Color.FromArgb(220, 220, 214);
        return GGStyle.Red;
    }

    internal static GraphicsPath Rounded(RectangleF r, float rad)
    {
        GraphicsPath p = new GraphicsPath();
        float d = Math.Min(rad * 2f, Math.Min(r.Width, r.Height));
        if (d < 0.5f) { p.AddRectangle(r); return p; }
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    // Das Zeichen: ein Serifen-G mit rotem Punkt – "G." – auf dunklem Quadrat
    public static void DrawMark(Graphics g, RectangleF r, string state)
    {
        GGStyle.Quality(g);
        float s = r.Width;
        using (GraphicsPath bg = Rounded(r, s * 0.2f))
        using (SolidBrush b = new SolidBrush(Back(state)))
        {
            g.FillPath(b, bg);
        }
        string fam = GGStyle.Pick("Georgia", "Times New Roman", "Liberation Serif", "DejaVu Serif");
        using (FontFamily ff = new FontFamily(fam))
        using (GraphicsPath gp = new GraphicsPath())
        {
            gp.AddString("G", ff, (int)FontStyle.Bold, 100f, new PointF(0, 0), StringFormat.GenericTypographic);
            RectangleF gb = gp.GetBounds();
            float targetH = s * (s < 24 ? 0.70f : 0.62f);
            float k = targetH / gb.Height;
            float dot = Math.Max(2f, s * 0.15f);
            float gap = Math.Max(0.6f, s * 0.035f);
            float totalW = gb.Width * k + gap + dot;
            float x0 = r.X + (s - totalW) / 2f;
            float y0 = r.Y + (s - targetH) / 2f;
            using (Matrix mx = new Matrix())
            {
                mx.Translate(x0, y0);
                mx.Scale(k, k);
                mx.Translate(-gb.X, -gb.Y);
                gp.Transform(mx);
            }
            using (SolidBrush b = new SolidBrush(GGStyle.Paper)) g.FillPath(b, gp);
            float dx = x0 + gb.Width * k + gap;
            float dy = y0 + targetH - dot;
            if (s < 24)
            {
                dx = (float)Math.Round(dx);
                dy = (float)Math.Round(dy);
            }
            using (SolidBrush b = new SolidBrush(Dot(state))) g.FillEllipse(b, dx, dy, dot, dot);
        }
    }

    public static Bitmap Mark(int size, string state)
    {
        Bitmap b = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(b))
        {
            g.Clear(Color.Transparent);
            DrawMark(g, new RectangleF(0, 0, size, size), state);
        }
        return b;
    }

    [DllImport("user32.dll")]
    static extern bool DestroyIcon(IntPtr handle);

    // Symbol für die Taskleiste; das Icon besitzt eine eigene Kopie, der Handle wird freigegeben.
    public static Icon TrayIcon(int size, string state)
    {
        using (Bitmap b = Mark(size, state))
        {
            IntPtr h = b.GetHicon();
            try
            {
                using (Icon tmp = Icon.FromHandle(h)) return (Icon)tmp.Clone();
            }
            finally
            {
                try { DestroyIcon(h); } catch { }
            }
        }
    }

    // .ico mit PNG-Einträgen (Windows Vista und neuer), für Startmenü und "Apps"
    public static void SaveIco(string path)
    {
        int[] sizes = { 16, 20, 24, 32, 40, 48, 64, 128, 256 };
        List<byte[]> pngs = new List<byte[]>();
        foreach (int s in sizes)
        {
            using (Bitmap b = Mark(s, "aktiv"))
            using (MemoryStream ms = new MemoryStream())
            {
                b.Save(ms, ImageFormat.Png);
                pngs.Add(ms.ToArray());
            }
        }
        using (MemoryStream o = new MemoryStream())
        using (BinaryWriter w = new BinaryWriter(o))
        {
            w.Write((short)0); w.Write((short)1); w.Write((short)sizes.Length);
            int offset = 6 + 16 * sizes.Length;
            for (int i = 0; i < sizes.Length; i++)
            {
                int s = sizes[i];
                w.Write((byte)(s >= 256 ? 0 : s)); w.Write((byte)(s >= 256 ? 0 : s));
                w.Write((byte)0); w.Write((byte)0);
                w.Write((short)1); w.Write((short)32);
                w.Write(pngs[i].Length); w.Write(offset);
                offset += pngs[i].Length;
            }
            foreach (byte[] p in pngs) w.Write(p);
            w.Flush();
            string tmp = path + ".neu";
            File.WriteAllBytes(tmp, o.ToArray());
            if (File.Exists(path)) File.Delete(path);
            File.Move(tmp, path);
        }
    }
}
// ===================== Menü in der Taskleiste =====================
public class GGMenuTheme
{
    public bool Dark;
    public Color Back, Text, Sub, Hover, Line, Accent;
    public float Scale = 1f;

    public static GGMenuTheme Current()
    {
        GGMenuTheme t = new GGMenuTheme();
        t.Dark = GGTray.DarkMode();
        t.Scale = GGTray.DpiScale();
        GGUi.S = t.Scale;
        if (t.Dark)
        {
            t.Back = Color.FromArgb(32, 32, 31); t.Text = Color.FromArgb(244, 242, 236); t.Sub = Color.FromArgb(158, 156, 150);
            t.Hover = Color.FromArgb(54, 54, 52); t.Line = Color.FromArgb(66, 66, 63);
        }
        else
        {
            t.Back = Color.FromArgb(251, 250, 247); t.Text = GGStyle.Ink; t.Sub = Color.FromArgb(118, 116, 110);
            t.Hover = Color.FromArgb(237, 234, 226); t.Line = Color.FromArgb(225, 221, 212);
        }
        t.Accent = GGStyle.Red;
        return t;
    }

    public int P(float v) { return (int)Math.Round(v * Scale); }
}

public class GGMenuRenderer : ToolStripRenderer
{
    readonly GGMenuTheme t;
    public GGMenuRenderer(GGMenuTheme theme) { t = theme; }

    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
    {
        using (SolidBrush b = new SolidBrush(t.Back)) e.Graphics.FillRectangle(b, e.AffectedBounds);
    }

    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
    {
        Rectangle r = new Rectangle(0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
        using (Pen p = new Pen(t.Line)) e.Graphics.DrawRectangle(p, r);
    }

    protected override void OnRenderImageMargin(ToolStripRenderEventArgs e)
    {
        using (SolidBrush b = new SolidBrush(t.Back)) e.Graphics.FillRectangle(b, e.AffectedBounds);
    }

    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
    {
        Rectangle r = new Rectangle(t.P(4), 1, e.Item.Width - t.P(8), e.Item.Height - 2);
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        bool hot = e.Item.Enabled && (e.Item.Selected || (e.Item is ToolStripMenuItem && ((ToolStripMenuItem)e.Item).DropDown.Visible));
        if (hot)
        {
            using (GraphicsPath gp = GGBrand.Rounded(r, t.P(5)))
            using (SolidBrush b = new SolidBrush(t.Hover))
            {
                g.FillPath(b, gp);
            }
        }
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        e.TextColor = e.Item.Enabled ? (e.Item.Tag as string == "gefahr" ? t.Accent : t.Text) : t.Sub;
        base.OnRenderItemText(e);
    }

    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
    {
        int y = e.Item.Height / 2;
        using (Pen p = new Pen(t.Line)) e.Graphics.DrawLine(p, t.P(12), y, e.Item.Width - t.P(12), y);
    }

    protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle r = e.ArrowRectangle;
        float cx = r.X + r.Width / 2f, cy = r.Y + r.Height / 2f, s = t.P(3.5f);
        using (Pen p = new Pen(e.Item.Enabled ? t.Sub : GGStyle.A(t.Sub, 110), Math.Max(1.2f, t.Scale * 1.3f)))
        {
            g.DrawLines(p, new PointF[] { new PointF(cx - s / 2f, cy - s), new PointF(cx + s / 2f, cy), new PointF(cx - s / 2f, cy + s) });
        }
    }
}

// Kopfzeile des Menüs: Logo, Name, Zustand
public class GGMenuHeader : ToolStripItem
{
    public string Status = "";
    public string State = "aktiv";
    readonly GGMenuTheme t;

    public GGMenuHeader(GGMenuTheme theme)
    {
        t = theme;
        Enabled = false;
        AutoSize = false;
        Size = new Size(t.P(272), t.P(60));
    }

    public override Size GetPreferredSize(Size constrainingSize)
    {
        return new Size(t.P(272), t.P(60));
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        GGStyle.Quality(g);
        float m = t.P(28);
        float x = t.P(14), y = (Height - m) / 2f;
        GGBrand.DrawMark(g, new RectangleF(x, y, m, m), State);
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        using (Font f = new Font(GGStyle.UiBold, 10.5f))
        using (SolidBrush b = new SolidBrush(t.Text))
        {
            g.DrawString("GrindGuard", f, b, x + m + t.P(12), y - t.P(3));
        }
        using (Font f = new Font(GGStyle.Ui, 8.75f))
        using (SolidBrush b = new SolidBrush(State == "fokus" ? GGStyle.Red : t.Sub))
        {
            g.DrawString(Status ?? "", f, b, x + m + t.P(12), y + t.P(15));
        }
    }
}

// Schnellschalter im Menü: ganze Abschnitte der Listen an und aus
public static class GGQuick
{
    public static string[] Sections(string confDir)
    {
        List<string> r = new List<string>();
        try
        {
            Add(r, new GGListFile(Path.Combine(confDir, "websites.txt"), false), "websites");
            Add(r, new GGListFile(Path.Combine(confDir, "apps.txt"), true), "apps");
        }
        catch { }
        return r.ToArray();
    }

    static void Add(List<string> r, GGListFile f, string tag)
    {
        Dictionary<string, int[]> d = new Dictionary<string, int[]>();
        List<string> order = new List<string>();
        foreach (GGEntry e in f.Entries())
        {
            if (e.Kind == "allow") continue;
            int[] c;
            if (!d.TryGetValue(e.Category, out c)) { c = new int[2]; d[e.Category] = c; order.Add(e.Category); }
            c[1]++;
            if (e.On) c[0]++;
        }
        foreach (string k in order) r.Add(tag + "|" + k + "|" + d[k][0] + "|" + d[k][1]);
    }

    public static void SetSection(string confDir, string tag, string section, bool on)
    {
        bool apps = tag == "apps";
        GGListFile f = new GGListFile(Path.Combine(confDir, apps ? "apps.txt" : "websites.txt"), apps);
        foreach (GGEntry e in f.Entries()) if (e.Category == section && e.Kind != "allow") f.Set(e, on);
        f.Save();
        GGSettings.ConfigVersion++;
    }

    // state: 0 aus, 1 teilweise, 2 an
    public static ToolStripMenuItem Item(string text, int state, GGMenuTheme t)
    {
        ToolStripMenuItem it = new ToolStripMenuItem((text ?? "").Replace("&", "&&"));   // & wäre sonst ein Tastenkürzel
        it.ImageScaling = ToolStripItemImageScaling.None;
        int w = t.P(30), h = t.P(17);
        Bitmap b = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(b))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            Color track = state == 2 ? (t.Dark ? Color.FromArgb(244, 242, 236) : GGStyle.Ink)
                : (state == 1 ? Color.FromArgb(128, 126, 120) : (t.Dark ? Color.FromArgb(86, 86, 82) : GGUi.Off));
            Color knob = state == 2 && t.Dark ? Color.FromArgb(32, 32, 31) : Color.White;
            using (GraphicsPath p = GGBrand.Rounded(new RectangleF(0.5f, 0.5f, w - 1, h - 1), (h - 1) / 2f))
            using (SolidBrush br = new SolidBrush(track))
            {
                g.FillPath(br, p);
            }
            float k = h - t.P(5);
            float kx = state == 2 ? w - t.P(2.5f) - k : (state == 1 ? (w - k) / 2f : t.P(2.5f));
            using (SolidBrush br = new SolidBrush(knob)) g.FillEllipse(br, kx, (h - k) / 2f, k, k);
        }
        it.Image = b;
        return it;
    }

    public static void Prepare(ToolStripDropDown dropDown, GGMenuTheme t)
    {
        ToolStripDropDownMenu dd = dropDown as ToolStripDropDownMenu;
        if (dd != null) dd.ShowImageMargin = true;
        dropDown.ImageScalingSize = new Size(t.P(30), t.P(17));
    }
}

public static class GGTray
{
    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    public static bool DarkMode()
    {
        try
        {
            object v = Microsoft.Win32.Registry.GetValue(
                @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme", 1);
            return v is int && (int)v == 0;
        }
        catch { return false; }
    }

    public static float DpiScale()
    {
        try
        {
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) return Math.Max(1f, g.DpiX / 96f);
        }
        catch { return 1f; }
    }

    // Windows 11: abgerundete Ecken wie bei den Menüs des Systems
    public static void Round(Control c)
    {
        try
        {
            int pref = 3;   // DWMWCP_ROUNDSMALL
            DwmSetWindowAttribute(c.Handle, 33, ref pref, 4);
        }
        catch { }
    }

    public static void Style(ToolStripDropDown menu, GGMenuTheme t)
    {
        menu.Renderer = new GGMenuRenderer(t);
        menu.Font = new Font(GGStyle.Ui, 9.75f);
        menu.Padding = new Padding(0, t.P(4), 0, t.P(4));
        ToolStripDropDownMenu dm = menu as ToolStripDropDownMenu;
        if (dm != null)
        {
            dm.ShowImageMargin = false;
            dm.ShowCheckMargin = false;
        }
        menu.Opened -= RoundOnOpen;
        menu.Opened += RoundOnOpen;
        foreach (ToolStripItem it in menu.Items)
        {
            if (it is ToolStripSeparator)
            {
                it.AutoSize = false;
                it.Height = t.P(9);
                continue;
            }
            if (it is GGMenuHeader) continue;
            it.Padding = new Padding(t.P(8), t.P(6), t.P(10), t.P(6));
            ToolStripMenuItem mi = it as ToolStripMenuItem;
            if (mi != null && mi.HasDropDownItems) Style(mi.DropDown, t);
        }
    }

    static void RoundOnOpen(object sender, EventArgs e)
    {
        Control c = sender as Control;
        if (c != null) Round(c);
    }

    // Linksklick auf das Symbol öffnet ebenfalls das Menü (wie beim Rechtsklick)
    public static void ShowMenu(NotifyIcon icon)
    {
        try
        {
            System.Reflection.MethodInfo mi = typeof(NotifyIcon).GetMethod("ShowContextMenu",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
            if (mi != null) mi.Invoke(icon, null);
        }
        catch { }
    }
}
// ===================== Listen und Einstellungen lesen/schreiben =====================
public class GGEntry
{
    public int Line;          // Zeilennummer in der Datei (0-basiert)
    public string Text;       // Eintrag ohne führendes #
    public bool On;
    public string Category;
    public string Kind;       // site | search | allow | app

    public string Display
    {
        get
        {
            string t = Text;
            int hash = t.IndexOf('#');
            if (hash > 0) t = t.Substring(0, hash);
            t = t.Trim();
            if (Kind == "allow") return t.TrimStart('+').Trim();
            if (Kind == "search") return "Suche: " + t.Substring(6).Trim();
            return t;
        }
    }
}

public static class GGFiles
{
    public static void WriteLines(string path, IList<string> lines, bool bom)
    {
        StringBuilder sb = new StringBuilder();
        foreach (string l in lines) sb.Append(l).Append("\r\n");
        string tmp = path + ".neu";
        File.WriteAllText(tmp, sb.ToString(), new UTF8Encoding(bom));
        Exception last = null;
        for (int i = 0; i < 20; i++)
        {
            try
            {
                if (File.Exists(path)) File.Replace(tmp, path, null);
                else File.Move(tmp, path);
                return;
            }
            catch (IOException ex) { last = ex; Thread.Sleep(50); }
            catch (UnauthorizedAccessException ex) { last = ex; Thread.Sleep(50); }
        }
        try { File.Delete(tmp); } catch { }
        throw new IOException("Konnte " + Path.GetFileName(path) + " nicht speichern: " + (last == null ? "" : last.Message));
    }

    public static List<string> ReadLines(string path, out bool bom)
    {
        bom = false;
        List<string> lines = new List<string>();
        if (!File.Exists(path)) return lines;
        byte[] data = File.ReadAllBytes(path);
        bom = data.Length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF;
        string text = new UTF8Encoding(false).GetString(data, bom ? 3 : 0, data.Length - (bom ? 3 : 0));
        text = text.Replace("\r\n", "\n").Replace('\r', '\n');
        if (text.EndsWith("\n")) text = text.Substring(0, text.Length - 1);
        if (text.Length > 0) lines.AddRange(text.Split('\n'));
        return lines;
    }
}

public class GGListFile
{
    public readonly string Path;
    public readonly bool Apps;
    public List<string> Lines;
    bool bom;
    static readonly Regex Header = new Regex(@"^#\s*-{2,}\s*(.+?)\s*-{2,}\s*$");

    public GGListFile(string path, bool apps)
    {
        Path = path;
        Apps = apps;
        Lines = GGFiles.ReadLines(path, out bom);
    }

    public static string CleanCategory(string c)
    {
        c = Regex.Replace(c ?? "", @"\s*\([^)]*\)\s*", " ").Trim();
        c = c.TrimEnd(':').Trim();
        return c.Length == 0 ? "Weitere" : c;
    }

    // Ein Eintrag beginnt direkt mit einem Zeichen; "# Text" mit Leerzeichen ist ein Kommentar.
    static bool LooksLikeEntry(string s)
    {
        if (s.Length == 0) return false;
        char c = s[0];
        return !(char.IsWhiteSpace(c) || c == '#' || c == '-' || c == '=');
    }

    public List<GGEntry> Entries()
    {
        List<GGEntry> list = new List<GGEntry>();
        string cat = Apps ? "Programme" : "Websites";
        for (int i = 0; i < Lines.Count; i++)
        {
            string l = Lines[i].Trim();
            if (l.Length == 0) continue;
            Match m = Header.Match(l);
            if (m.Success) { cat = CleanCategory(m.Groups[1].Value); continue; }
            bool on = true;
            string text = l;
            if (l.StartsWith("#"))
            {
                text = l.Substring(1);
                if (!LooksLikeEntry(text)) continue;
                on = false;
            }
            GGEntry e = new GGEntry();
            e.Line = i;
            e.Text = text.Trim();
            e.On = on;
            e.Category = cat;
            string low = e.Text.ToLowerInvariant();
            if (Apps) e.Kind = "app";
            else if (low.StartsWith("+")) e.Kind = "allow";
            else if (low.StartsWith("suche:")) e.Kind = "search";
            else e.Kind = "site";
            list.Add(e);
        }
        return list;
    }

    public void Set(GGEntry e, bool on)
    {
        if (e.Line < 0 || e.Line >= Lines.Count) return;
        Lines[e.Line] = on ? e.Text : "#" + e.Text;
        e.On = on;
    }

    static string Key(string entry)
    {
        string t = entry;
        int hash = t.IndexOf('#');
        if (hash > 0) t = t.Substring(0, hash);
        return t.Trim().ToLowerInvariant();
    }

    // Neuer Eintrag in den Abschnitt "Eigene". Gibt es ihn schon, wird er nur eingeschaltet.
    public GGEntry Add(string entry)
    {
        foreach (GGEntry e in Entries())
        {
            if (Key(e.Text) == Key(entry))
            {
                Set(e, true);
                return e;
            }
        }
        int header = -1;
        for (int i = 0; i < Lines.Count; i++)
        {
            Match m = Header.Match(Lines[i].Trim());
            if (m.Success && CleanCategory(m.Groups[1].Value) == "Eigene") { header = i; break; }
        }
        if (header < 0)
        {
            while (Lines.Count > 0 && Lines[Lines.Count - 1].Trim().Length == 0) Lines.RemoveAt(Lines.Count - 1);
            Lines.Add("");
            Lines.Add("# --- Eigene ---");
            Lines.Add(entry);
        }
        else
        {
            int at = header + 1;
            while (at < Lines.Count && Lines[at].Trim().Length > 0 && !Header.IsMatch(Lines[at].Trim())) at++;
            Lines.Insert(at, entry);
        }
        foreach (GGEntry e in Entries()) if (Key(e.Text) == Key(entry)) return e;
        return null;
    }

    public void Save()
    {
        GGFiles.WriteLines(Path, Lines, bom);
    }

    // Prüft und vereinheitlicht eine neue Website-Zeile; null = ungültig
    public static string NormalizeSite(string raw, out string error)
    {
        error = "";
        string s = (raw ?? "").Trim();
        if (s.Length == 0) { error = "Bitte eine Adresse eingeben, z. B. youtube.com"; return null; }
        string low = s.ToLowerInvariant();
        if (low.StartsWith("suche:"))
        {
            string k = low.Substring(6).Trim();
            if (k.Length < 2) { error = "Der Suchbegriff ist zu kurz."; return null; }
            return "suche: " + k;
        }
        bool allow = low.StartsWith("+");
        if (allow) low = low.Substring(1).Trim();
        low = Regex.Replace(low, @"^[a-z][a-z0-9+.-]*://", "");
        if (low.StartsWith("www.")) low = low.Substring(4);
        low = low.TrimEnd('/');
        if (low.IndexOfAny(new char[] { ' ', '\t', '#' }) >= 0) { error = "Eine Adresse enthält keine Leerzeichen."; return null; }
        if (low.IndexOf('.') < 0 && low.IndexOf('*') < 0) { error = "Das sieht nicht nach einer Adresse aus (z. B. youtube.com)."; return null; }
        return (allow ? "+" : "") + low;
    }

    public static string NormalizeApp(string raw, string[] protectedNames, out string error)
    {
        error = "";
        string s = (raw ?? "").Trim();
        if (s.ToLowerInvariant().EndsWith(".exe")) s = s.Substring(0, s.Length - 4);
        if (s.Length == 0) { error = "Bitte den Programmnamen eingeben, z. B. steam"; return null; }
        if (s.IndexOfAny(new char[] { '\\', '/', ':', '#', '"' }) >= 0) { error = "Nur der Name, ohne Pfad (z. B. steam)."; return null; }
        if (protectedNames != null)
        {
            foreach (string p in protectedNames)
            {
                if (string.Equals(p, s, StringComparison.OrdinalIgnoreCase))
                {
                    error = s + " ist ein Teil von Windows und wird nie beendet.";
                    return null;
                }
            }
        }
        return s;
    }
}

public class GGKeyFile
{
    public readonly string Path;
    public List<string> Lines;
    bool bom;

    public GGKeyFile(string path)
    {
        Path = path;
        Lines = GGFiles.ReadLines(path, out bom);
    }

    int Find(string key)
    {
        for (int i = 0; i < Lines.Count; i++)
        {
            string l = Lines[i].Trim();
            if (l.StartsWith("#")) continue;
            int eq = l.IndexOf('=');
            if (eq > 0 && l.Substring(0, eq).Trim() == key) return i;
        }
        return -1;
    }

    public string Get(string key, string fallback)
    {
        int i = Find(key);
        if (i < 0) return fallback;
        string v = Lines[i].Substring(Lines[i].IndexOf('=') + 1);
        int hash = v.IndexOf('#');
        if (hash >= 0) v = v.Substring(0, hash);
        v = v.Trim();
        return v;
    }

    public int GetInt(string key, int fallback, int min, int max)
    {
        int v;
        if (!int.TryParse(Get(key, ""), NumberStyles.Integer, CultureInfo.InvariantCulture, out v)) return fallback;
        return Math.Max(min, Math.Min(max, v));
    }

    public void Set(string key, string value, string comment)
    {
        int i = Find(key);
        if (i >= 0) { Lines[i] = key + "=" + value; return; }
        while (Lines.Count > 0 && Lines[Lines.Count - 1].Trim().Length == 0) Lines.RemoveAt(Lines.Count - 1);
        Lines.Add("");
        if (!string.IsNullOrEmpty(comment)) Lines.Add("# " + comment);
        Lines.Add(key + "=" + value);
    }

    public void Save()
    {
        GGFiles.WriteLines(Path, Lines, bom);
    }
}

// Zustand aus dem state-Ordner: Fokus, Pause, Ausrutscher
public class GGState
{
    public readonly string Dir;
    public GGState(string stateDir) { Dir = stateDir; }

    long ReadUnix(string name)
    {
        try
        {
            string p = System.IO.Path.Combine(Dir, name);
            if (!File.Exists(p)) return 0;
            long v;
            if (long.TryParse(File.ReadAllText(p).Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out v)) return v;
        }
        catch { }
        return 0;
    }

    public static long Now() { return (long)(DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds; }

    public static string Clock(long unix)
    {
        return new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(unix).ToLocalTime().ToString("HH:mm", CultureInfo.InvariantCulture);
    }

    public long FocusEnd { get { long v = ReadUnix("fokus_bis"); return v > Now() ? v : 0; } }
    public long PauseEnd { get { long v = ReadUnix("pause_bis"); return v > Now() ? v : 0; } }

    public List<string[]> Strikes()
    {
        List<string[]> list = new List<string[]>();
        try
        {
            string p = System.IO.Path.Combine(Dir, "ausrutscher.log");
            if (!File.Exists(p)) return list;
            foreach (string l in File.ReadAllLines(p, Encoding.UTF8))
            {
                string[] parts = l.Split('|');
                if (parts.Length >= 3 && parts[0].Length >= 10) list.Add(parts);
            }
        }
        catch { }
        return list;
    }

    public int CountOn(List<string[]> strikes, DateTime day)
    {
        string key = day.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        int n = 0;
        foreach (string[] s in strikes) if (s[0].StartsWith(key)) n++;
        return n;
    }
}

public static class GGUpdate
{
    public static string Latest(string repo, out string error)
    {
        error = "";
        try
        {
            ServicePointManager.SecurityProtocol = ServicePointManager.SecurityProtocol | (SecurityProtocolType)3072;  // TLS 1.2
            HttpWebRequest r = (HttpWebRequest)WebRequest.Create("https://api.github.com/repos/" + repo + "/releases/latest");
            r.UserAgent = "GrindGuard";
            r.Accept = "application/vnd.github+json";
            r.Timeout = 12000;
            using (WebResponse resp = r.GetResponse())
            using (StreamReader sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
            {
                Match m = Regex.Match(sr.ReadToEnd(), "\"tag_name\"\\s*:\\s*\"v?([0-9]+(\\.[0-9]+)*)\"");
                if (m.Success) return m.Groups[1].Value;
                error = "GitHub hat keine Versionsnummer geliefert.";
            }
        }
        catch (Exception ex)
        {
            error = ex.Message;
        }
        return null;
    }

    public static bool Newer(string candidate, string current)
    {
        try { return new Version(Pad(candidate)) > new Version(Pad(current)); }
        catch { return false; }
    }

    static string Pad(string v)
    {
        v = (v ?? "0").Trim().TrimStart('v');
        if (v.IndexOf('.') < 0) v += ".0";
        return v;
    }
}
// ===================== Bausteine für Fenster =====================
public static class GGUi
{
    public static float S = 1f;
    public static int P(float v) { return (int)Math.Round(v * S); }
    public static readonly Color Back = Color.FromArgb(247, 245, 240);
    public static readonly Color Card = Color.FromArgb(255, 255, 253);
    public static readonly Color Line = Color.FromArgb(223, 219, 210);
    public static readonly Color Sub = Color.FromArgb(110, 108, 102);
    public static readonly Color Hover = Color.FromArgb(237, 234, 226);
    public static readonly Color Off = Color.FromArgb(196, 192, 184);
    public static Font F(float pt) { return new Font(GGStyle.Ui, pt); }
    public static Font B(float pt) { return new Font(GGStyle.UiBold, pt); }
    public static Font Serif(float pt) { return new Font(GGStyle.Serif, pt); }
    public static Font SerifItalic(float pt) { return new Font(GGStyle.Serif, pt, FontStyle.Italic); }

    public static Label Text(Control parent, string text, Font f, Color c, int x, int y, int w)
    {
        Label l = new Label();
        l.Text = text;
        l.Font = f;
        l.ForeColor = c;
        l.BackColor = Color.Transparent;
        l.UseMnemonic = false;
        l.Location = new Point(x, y);
        if (w > 0)
        {
            l.AutoSize = false;
            l.Width = w;
            using (Graphics g = l.CreateGraphics())
            {
                Size sz = TextRenderer.MeasureText(g, text, f, new Size(w, 2000), TextFormatFlags.WordBreak);
                l.Height = sz.Height + 2;
            }
        }
        else l.AutoSize = true;
        parent.Controls.Add(l);
        return l;
    }

    public static Label Caption(Control parent, string text, int x, int y)
    {
        return Text(parent, text.ToUpperInvariant(), B(8f), Sub, x, y, 0);
    }

    public static void DrawToggle(Graphics g, Rectangle r, bool on, bool partial, bool enabled, bool focus)
    {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Color track = on ? (partial ? Color.FromArgb(120, 118, 112) : GGStyle.Ink) : Off;
        if (!enabled) track = GGStyle.A(track, 90);
        float h = r.Height, w = r.Width;
        using (GraphicsPath p = GGBrand.Rounded(new RectangleF(r.X, r.Y, w, h), h / 2f))
        using (SolidBrush b = new SolidBrush(track))
        {
            g.FillPath(b, p);
        }
        float k = h - P(6);
        float kx = on ? r.Right - P(3) - k : r.X + P(3);
        using (SolidBrush b = new SolidBrush(enabled ? Color.White : Color.FromArgb(235, 235, 235)))
        {
            g.FillEllipse(b, kx, r.Y + P(3), k, k);
        }
        if (focus)
        {
            using (Pen p = new Pen(GGStyle.Red, Math.Max(1.5f, S * 1.5f)))
            using (GraphicsPath gp = GGBrand.Rounded(new RectangleF(r.X - P(3), r.Y - P(3), w + P(6), h + P(6)), (h + P(6)) / 2f))
            {
                g.DrawPath(p, gp);
            }
        }
    }
}

public class GGToggle : Control
{
    bool on;
    public event EventHandler Changed;

    public GGToggle()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.SupportsTransparentBackColor | ControlStyles.Selectable, true);
        BackColor = Color.Transparent;
        Size = new Size(GGUi.P(42), GGUi.P(24));
        Cursor = Cursors.Hand;
        TabStop = true;
    }

    public bool On
    {
        get { return on; }
        set { if (on != value) { on = value; Invalidate(); } }
    }

    public void Flip()
    {
        if (!Enabled) return;
        Focus();
        On = !On;
        if (Changed != null) Changed(this, EventArgs.Empty);
    }

    protected override void OnClick(EventArgs e)
    {
        Flip();
        base.OnClick(e);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) { Flip(); e.Handled = true; }
        base.OnKeyDown(e);
    }

    protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
    protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }
    protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }

    protected override void OnPaint(PaintEventArgs e)
    {
        Rectangle r = new Rectangle(GGUi.P(3), GGUi.P(3), Width - GGUi.P(6), Height - GGUi.P(6));
        GGUi.DrawToggle(e.Graphics, r, on, false, Enabled, Focused && ShowFocusCues);
    }
}

public class GGButton : Control
{
    public string Kind;      // primary | secondary | link | danger
    bool hover;

    public GGButton(string text, string kind)
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.SupportsTransparentBackColor | ControlStyles.Selectable, true);
        BackColor = Color.Transparent;
        Kind = kind;
        Text = text;
        Font = GGUi.F(9.75f);
        Cursor = Cursors.Hand;
        TabStop = true;
        Fit();
    }

    public void Fit()
    {
        Size sz = TextRenderer.MeasureText(Text, Font);
        bool link = Kind == "link" || Kind == "danger";
        Width = sz.Width + (link ? GGUi.P(4) : GGUi.P(34));
        Height = link ? sz.Height + GGUi.P(6) : GGUi.P(36);
    }

    protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Fit(); Invalidate(); }
    protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); hover = true; Invalidate(); }
    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hover = false; Invalidate(); }
    protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
    protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }
    protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) { OnClick(EventArgs.Empty); e.Handled = true; }
        base.OnKeyDown(e);
    }

    protected override void OnClick(EventArgs e)
    {
        if (!Enabled) return;
        base.OnClick(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
        Color text = GGStyle.Ink;
        if (Kind == "primary")
        {
            using (GraphicsPath p = GGBrand.Rounded(r, GGUi.P(3)))
            using (SolidBrush b = new SolidBrush(hover ? Color.FromArgb(52, 52, 50) : GGStyle.Ink))
            {
                g.FillPath(b, p);
            }
            text = GGStyle.Paper;
        }
        else if (Kind == "secondary")
        {
            using (GraphicsPath p = GGBrand.Rounded(r, GGUi.P(3)))
            {
                using (SolidBrush b = new SolidBrush(hover ? GGUi.Hover : GGUi.Card)) g.FillPath(b, p);
                using (Pen pen = new Pen(hover ? GGUi.Sub : GGUi.Line)) g.DrawPath(pen, p);
            }
        }
        else if (Kind == "danger") text = GGStyle.Red;
        if (Kind == "link" && hover) text = GGStyle.Red;
        if (!Enabled) text = GGStyle.A(text, 110);
        bool link = Kind == "link" || Kind == "danger";
        using (Font f = link ? new Font(Font, FontStyle.Underline) : (Font)Font.Clone())
        {
            TextFormatFlags fl = TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix |
                                 (link ? TextFormatFlags.Left : TextFormatFlags.HorizontalCenter);
            TextRenderer.DrawText(g, Text, f, new Rectangle(link ? 0 : 0, 0, Width, Height), text, fl);
        }
        if (Focused && ShowFocusCues)
        {
            using (Pen p = new Pen(GGStyle.Red, Math.Max(1.5f, GGUi.S * 1.5f)))
            using (GraphicsPath gp = GGBrand.Rounded(new RectangleF(1, 1, Width - 3, Height - 3), GGUi.P(3)))
            {
                g.DrawPath(p, gp);
            }
        }
    }
}

// Auswahlkarte (z. B. Ton der Warnung)
public class GGChoice : Control
{
    public string Title, Desc;
    bool selected, hover;
    public GGChoice(string title, string desc, int w, int h)
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.SupportsTransparentBackColor | ControlStyles.Selectable, true);
        BackColor = Color.Transparent;
        Title = title; Desc = desc;
        Size = new Size(w, h);
        Cursor = Cursors.Hand;
        TabStop = true;
    }
    public bool Selected { get { return selected; } set { selected = value; Invalidate(); } }
    protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); hover = true; Invalidate(); }
    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hover = false; Invalidate(); }
    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) { OnClick(EventArgs.Empty); e.Handled = true; }
        base.OnKeyDown(e);
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        float bw = selected ? Math.Max(2f, GGUi.S * 2f) : 1f;
        RectangleF r = new RectangleF(bw / 2f, bw / 2f, Width - bw - 1, Height - bw - 1);
        using (GraphicsPath p = GGBrand.Rounded(r, GGUi.P(4)))
        {
            using (SolidBrush b = new SolidBrush(hover && !selected ? GGUi.Hover : GGUi.Card)) g.FillPath(b, p);
            using (Pen pen = new Pen(selected ? GGStyle.Ink : GGUi.Line, bw)) g.DrawPath(pen, p);
        }
        int pad = GGUi.P(14);
        using (Font f = GGUi.Serif(15f))
            TextRenderer.DrawText(g, Title, f, new Point(pad - GGUi.P(2), pad - GGUi.P(4)), GGStyle.Ink, TextFormatFlags.NoPrefix);
        using (Font f = GGUi.F(8.75f))
            TextRenderer.DrawText(g, Desc, f, new Rectangle(pad, pad + GGUi.P(28), Width - 2 * pad, Height - pad - GGUi.P(30)), GGUi.Sub,
                TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
        if (selected)
        {
            float d = GGUi.P(9);
            using (SolidBrush b = new SolidBrush(GGStyle.Red)) g.FillEllipse(b, Width - pad - d, pad, d, d);
        }
        if (Focused && ShowFocusCues)
        {
            using (Pen pen = new Pen(GGStyle.Red, Math.Max(1.5f, GGUi.S * 1.5f)))
            using (GraphicsPath p = GGBrand.Rounded(new RectangleF(3, 3, Width - 7, Height - 7), GGUi.P(3)))
                g.DrawPath(pen, p);
        }
    }
}

// Vorschaubild eines Sperrbildschirms
public class GGThumb : Control
{
    public Bitmap Image;
    public string Title;
    bool selected, hover;
    public GGThumb(string title, int w, int h)
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.SupportsTransparentBackColor | ControlStyles.Selectable, true);
        BackColor = Color.Transparent;
        Title = title;
        Size = new Size(w, h);
        Cursor = Cursors.Hand;
        TabStop = true;
    }
    public bool Selected { get { return selected; } set { selected = value; Invalidate(); } }
    protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); hover = true; Invalidate(); }
    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hover = false; Invalidate(); }
    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) { OnClick(EventArgs.Empty); e.Handled = true; }
        base.OnKeyDown(e);
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        int lab = GGUi.P(26);
        Rectangle img = new Rectangle(GGUi.P(4), GGUi.P(4), Width - GGUi.P(8), Height - lab - GGUi.P(8));
        if (selected || hover)
        {
            using (Pen p = new Pen(selected ? GGStyle.Ink : GGUi.Sub, Math.Max(2f, GGUi.S * 2f)))
                g.DrawRectangle(p, Rectangle.Inflate(img, GGUi.P(2), GGUi.P(2)));
        }
        if (Image != null) g.DrawImage(Image, img);
        else using (SolidBrush b = new SolidBrush(GGUi.Line)) g.FillRectangle(b, img);
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        using (Font f = selected ? GGUi.B(9f) : GGUi.F(9f))
            TextRenderer.DrawText(g, Title, f, new Rectangle(img.X, img.Bottom + GGUi.P(4), img.Width, lab), selected ? GGStyle.Ink : GGUi.Sub,
                TextFormatFlags.Left | TextFormatFlags.NoPrefix);
        if (selected)
        {
            float d = GGUi.P(8);
            using (SolidBrush b = new SolidBrush(GGStyle.Red)) g.FillEllipse(b, img.Right - d, img.Bottom + GGUi.P(8), d, d);
        }
        if (Focused && ShowFocusCues)
        {
            using (Pen p = new Pen(GGStyle.Red, Math.Max(1.5f, GGUi.S * 1.5f))) g.DrawRectangle(p, Rectangle.Inflate(img, GGUi.P(5), GGUi.P(5)));
        }
    }
}

// Zahlenfeld mit – und +
public class GGStepper : Control
{
    int value;
    public int Min, Max, Step;
    public Func<int, string> Format;
    public event EventHandler Changed;
    int hot = 0;

    public GGStepper(int min, int max, int step, int val)
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.SupportsTransparentBackColor | ControlStyles.Selectable, true);
        BackColor = Color.Transparent;
        Min = min; Max = max; Step = step; value = Math.Max(min, Math.Min(max, val));
        Size = new Size(GGUi.P(148), GGUi.P(36));
        TabStop = true;
        Format = delegate (int v) { return v.ToString(CultureInfo.InvariantCulture); };
    }

    public int Value
    {
        get { return value; }
        set { int v = Math.Max(Min, Math.Min(Max, value)); if (v != this.value) { this.value = v; Invalidate(); } }
    }

    void Bump(int dir)
    {
        if (!Enabled) return;
        int old = value;
        Value = value + dir * Step;
        if (value != old && Changed != null) Changed(this, EventArgs.Empty);
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        Focus();
        int third = Height;
        if (e.X < third) Bump(-1);
        else if (e.X > Width - third) Bump(1);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        int h = e.X < Height ? -1 : (e.X > Width - Height ? 1 : 0);
        Cursor = h == 0 ? Cursors.Default : Cursors.Hand;
        if (h != hot) { hot = h; Invalidate(); }
    }

    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hot = 0; Invalidate(); }
    protected override void OnMouseWheel(MouseEventArgs e) { base.OnMouseWheel(e); Bump(e.Delta > 0 ? 1 : -1); }
    protected override bool IsInputKey(Keys k) { return k == Keys.Up || k == Keys.Down || k == Keys.Left || k == Keys.Right || base.IsInputKey(k); }
    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Up || e.KeyCode == Keys.Right) { Bump(1); e.Handled = true; }
        if (e.KeyCode == Keys.Down || e.KeyCode == Keys.Left) { Bump(-1); e.Handled = true; }
        base.OnKeyDown(e);
    }
    protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
    protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
        using (GraphicsPath p = GGBrand.Rounded(r, GGUi.P(3)))
        {
            using (SolidBrush b = new SolidBrush(GGUi.Card)) g.FillPath(b, p);
            using (Pen pen = new Pen(Focused && ShowFocusCues ? GGStyle.Red : GGUi.Line)) g.DrawPath(pen, p);
        }
        int s = Height;
        if (hot != 0)
        {
            Rectangle hr = hot < 0 ? new Rectangle(1, 1, s - 1, Height - 2) : new Rectangle(Width - s, 1, s - 2, Height - 2);
            using (SolidBrush b = new SolidBrush(GGUi.Hover)) g.FillRectangle(b, hr);
        }
        float cy = Height / 2f, a = GGUi.P(5);
        using (Pen pen = new Pen(Enabled && value > Min ? GGStyle.Ink : GGUi.Off, Math.Max(1.5f, GGUi.S * 1.5f)))
            g.DrawLine(pen, s / 2f - a, cy, s / 2f + a, cy);
        using (Pen pen = new Pen(Enabled && value < Max ? GGStyle.Ink : GGUi.Off, Math.Max(1.5f, GGUi.S * 1.5f)))
        {
            float cx = Width - s / 2f;
            g.DrawLine(pen, cx - a, cy, cx + a, cy);
            g.DrawLine(pen, cx, cy - a, cx, cy + a);
        }
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        using (Font f = GGUi.B(9.75f))
            TextRenderer.DrawText(g, Format(value), f, new Rectangle(s, 0, Width - 2 * s, Height), Enabled ? GGStyle.Ink : GGUi.Sub,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
    }
}

// Ein Schalter mit Titel und Beschreibung, über die ganze Breite
public class GGSwitchRow : Control
{
    public readonly GGToggle Toggle;
    public GGSwitchRow(string title, string desc, int width)
    {
        SetStyle(ControlStyles.SupportsTransparentBackColor | ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer, true);
        BackColor = Color.Transparent;
        Width = width;
        Toggle = new GGToggle();
        Controls.Add(Toggle);
        Label t = GGUi.Text(this, title, GGUi.F(10f), GGStyle.Ink, 0, GGUi.P(2), width - GGUi.P(70));
        int y = t.Bottom;
        if (!string.IsNullOrEmpty(desc))
        {
            Label d = GGUi.Text(this, desc, GGUi.F(8.75f), GGUi.Sub, 0, y, width - GGUi.P(70));
            y = d.Bottom;
        }
        Height = Math.Max(y + GGUi.P(6), Toggle.Height + GGUi.P(4));
        Toggle.Location = new Point(width - Toggle.Width, GGUi.P(2));
        foreach (Control c in Controls) if (c is Label) { c.Cursor = Cursors.Hand; c.Click += delegate { Toggle.Flip(); }; }
    }
}

// Tages-Auswahl (Mo … So)
public class GGChip : Control
{
    bool on;
    public event EventHandler Changed;
    public GGChip(string text)
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.SupportsTransparentBackColor | ControlStyles.Selectable, true);
        BackColor = Color.Transparent;
        Text = text;
        Size = new Size(GGUi.P(44), GGUi.P(36));
        Cursor = Cursors.Hand;
        TabStop = true;
    }
    public bool On { get { return on; } set { on = value; Invalidate(); } }
    protected override void OnClick(EventArgs e)
    {
        if (!Enabled) return;
        Focus();
        On = !On;
        if (Changed != null) Changed(this, EventArgs.Empty);
        base.OnClick(e);
    }
    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) { OnClick(EventArgs.Empty); e.Handled = true; }
        base.OnKeyDown(e);
    }
    protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
    protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }
    protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
        using (GraphicsPath p = GGBrand.Rounded(r, GGUi.P(3)))
        {
            Color fill = on ? GGStyle.Ink : GGUi.Card;
            if (!Enabled) fill = GGStyle.A(fill, 120);
            using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
            using (Pen pen = new Pen(Focused && ShowFocusCues ? GGStyle.Red : (on ? GGStyle.Ink : GGUi.Line))) g.DrawPath(pen, p);
        }
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        using (Font f = GGUi.B(9f))
            TextRenderer.DrawText(g, Text, f, new Rectangle(0, 0, Width, Height), on ? GGStyle.Paper : GGStyle.Ink,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
    }
}

// Eingabefeld mit Rahmen und Platzhalter
public class GGInput : Panel
{
    public readonly TextBox Box;
    readonly Label hint;
    public GGInput(string placeholder, int width)
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        BackColor = GGUi.Card;
        Size = new Size(width, GGUi.P(36));
        Box = new TextBox();
        Box.BorderStyle = BorderStyle.None;
        Box.Font = GGUi.F(10f);
        Box.BackColor = GGUi.Card;
        Box.ForeColor = GGStyle.Ink;
        Box.Location = new Point(GGUi.P(10), (Height - Box.PreferredHeight) / 2 + 1);
        Box.Width = width - GGUi.P(20);
        Box.Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top;
        hint = new Label();
        hint.Text = placeholder;
        hint.Font = GGUi.F(10f);
        hint.ForeColor = GGUi.Off;
        hint.BackColor = GGUi.Card;
        hint.AutoSize = true;
        hint.Location = new Point(GGUi.P(10), Box.Top);
        hint.Cursor = Cursors.IBeam;
        hint.Click += delegate { Box.Focus(); };
        Controls.Add(Box);
        Controls.Add(hint);
        hint.BringToFront();
        Box.TextChanged += delegate { hint.Visible = Box.Text.Length == 0; };
        Box.GotFocus += delegate { Invalidate(); };
        Box.LostFocus += delegate { Invalidate(); };
        Click += delegate { Box.Focus(); };
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        using (Pen p = new Pen(Box.Focused ? GGStyle.Ink : GGUi.Line)) e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
    }
}
// Liste aller Sperr-Einträge mit Schaltern, gruppiert nach Abschnitten
public class GGList : Panel
{
    class Row
    {
        public int Type;              // 0 Überschrift, 1 Kategorie, 2 Eintrag
        public string Text = "", Hint = "";
        public GGEntry Entry;
        public GGListFile File;
        public List<Row> Children = new List<Row>();
        public int Y, H;
    }

    readonly List<Row> rows = new List<Row>();
    GGListFile sites, apps;
    string filter = "";
    int hover = -1;
    public event Action<GGListFile, List<GGEntry>, bool> Toggled;

    public GGList()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        AutoScroll = true;
        BackColor = GGUi.Card;
        TabStop = true;
    }

    public void Load(GGListFile siteFile, GGListFile appFile)
    {
        sites = siteFile;
        apps = appFile;
        Rebuild();
    }

    public string Filter
    {
        get { return filter; }
        set { filter = (value ?? "").Trim().ToLowerInvariant(); Rebuild(); }
    }

    bool Match(GGEntry e)
    {
        if (filter.Length == 0) return true;
        return e.Display.ToLowerInvariant().Contains(filter) || e.Category.ToLowerInvariant().Contains(filter);
    }

    void AddGroup(string section, GGListFile file, List<GGEntry> entries)
    {
        List<GGEntry> shown = entries.FindAll(Match);
        if (shown.Count == 0) return;
        Row head = new Row();
        head.Type = 0; head.Text = section; head.H = GGUi.P(44);
        rows.Add(head);
        Dictionary<string, Row> cats = new Dictionary<string, Row>();
        foreach (GGEntry e in shown)
        {
            Row cat;
            if (!cats.TryGetValue(e.Category, out cat))
            {
                cat = new Row();
                cat.Type = 1; cat.Text = e.Category; cat.File = file; cat.H = GGUi.P(42);
                cats[e.Category] = cat;
                rows.Add(cat);
            }
            Row r = new Row();
            r.Type = 2; r.Entry = e; r.File = file; r.Text = e.Display; r.H = GGUi.P(34);
            if (e.Kind == "search") r.Hint = "Suchbegriff";
            else if (e.Kind == "allow") r.Hint = "bleibt offen";
            else if (e.Text.IndexOf('*') >= 0) r.Hint = "Muster";
            else if (e.Text.IndexOf('/') >= 0) r.Hint = "nur dieser Bereich";
            cat.Children.Add(r);
            rows.Add(r);
        }
    }

    public void Rebuild()
    {
        int keep = -AutoScrollPosition.Y;
        rows.Clear();
        if (sites != null)
        {
            List<GGEntry> all = sites.Entries();
            AddGroup("Websites und Suchbegriffe", sites, all.FindAll(delegate (GGEntry e) { return e.Kind != "allow"; }));
            AddGroup("Programme", apps, apps == null ? new List<GGEntry>() : apps.Entries());
            AddGroup("Ausnahmen – bleiben immer offen", sites, all.FindAll(delegate (GGEntry e) { return e.Kind == "allow"; }));
        }
        else if (apps != null) AddGroup("Programme", apps, apps.Entries());
        int y = GGUi.P(4);
        foreach (Row r in rows) { r.Y = y; y += r.H; }
        AutoScrollMinSize = new Size(0, y + GGUi.P(12));
        AutoScrollPosition = new Point(0, keep);
        hover = -1;
        Invalidate();
    }

    public List<GGEntry> VisibleEntries(bool includeAllow)
    {
        List<GGEntry> list = new List<GGEntry>();
        foreach (Row r in rows) if (r.Type == 2 && (includeAllow || r.Entry.Kind != "allow")) list.Add(r.Entry);
        return list;
    }

    public GGListFile FileOf(GGEntry e)
    {
        foreach (Row r in rows) if (r.Type == 2 && r.Entry == e) return r.File;
        return null;
    }

    int Hit(int y)
    {
        int yy = y - AutoScrollPosition.Y;
        for (int i = 0; i < rows.Count; i++) if (yy >= rows[i].Y && yy < rows[i].Y + rows[i].H) return i;
        return -1;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        int h = Hit(e.Y);
        if (h >= 0 && rows[h].Type == 0) h = -1;
        Cursor = h >= 0 && Enabled ? Cursors.Hand : Cursors.Default;
        if (h != hover) { hover = h; Invalidate(); }
    }

    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hover = -1; Invalidate(); }
    protected override void OnScroll(ScrollEventArgs se) { base.OnScroll(se); Invalidate(); }
    protected override void OnMouseWheel(MouseEventArgs e) { base.OnMouseWheel(e); Invalidate(); }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        base.OnMouseClick(e);
        Focus();
        if (!Enabled || e.Button != MouseButtons.Left) return;
        int h = Hit(e.Y);
        if (h < 0 || Toggled == null) return;
        Row r = rows[h];
        if (r.Type == 2)
        {
            Toggled(r.File, new List<GGEntry> { r.Entry }, !r.Entry.On);
        }
        else if (r.Type == 1)
        {
            bool allOn = r.Children.TrueForAll(delegate (Row c) { return c.Entry.On; });
            List<GGEntry> list = new List<GGEntry>();
            foreach (Row c in r.Children) list.Add(c.Entry);
            Toggled(r.File, list, !allOn);
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.Clear(BackColor);
        g.TranslateTransform(0, AutoScrollPosition.Y);
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        int w = ClientSize.Width;
        int pad = GGUi.P(18);
        int tw = GGUi.P(36), th = GGUi.P(20);
        using (Font fSec = GGUi.B(8f))
        using (Font fCat = GGUi.B(10f))
        using (Font fItem = GGUi.F(10f))
        using (Font fHint = GGUi.F(8.5f))
        using (Pen line = new Pen(GGUi.Line))
        using (SolidBrush hov = new SolidBrush(GGUi.Hover))
        {
            for (int i = 0; i < rows.Count; i++)
            {
                Row r = rows[i];
                int top = r.Y;
                if (top + r.H + AutoScrollPosition.Y < 0 || top + AutoScrollPosition.Y > Height) continue;
                if (i == hover) g.FillRectangle(hov, 0, top, w, r.H);
                if (r.Type == 0)
                {
                    Color c = GGUi.Sub;
                    TextRenderer.DrawText(g, r.Text.ToUpperInvariant(), fSec, new Rectangle(pad, top + GGUi.P(18), w - 2 * pad, GGUi.P(20)), c, TextFormatFlags.NoPrefix);
                    continue;
                }
                if (r.Type == 1)
                {
                    g.DrawLine(line, pad, top, w - pad, top);
                    int on = 0;
                    foreach (Row c in r.Children) if (c.Entry.On) on++;
                    TextRenderer.DrawText(g, r.Text, fCat, new Rectangle(pad, top, w - 2 * pad - tw, r.H), GGStyle.Ink,
                        TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
                    Size ts = TextRenderer.MeasureText(g, r.Text, fCat);
                    string cnt = on + " von " + r.Children.Count + " an";
                    TextRenderer.DrawText(g, cnt, fHint, new Rectangle(pad + ts.Width + GGUi.P(6), top, GGUi.P(140), r.H), GGUi.Sub,
                        TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
                    GGUi.DrawToggle(g, new Rectangle(w - pad - tw, top + (r.H - th) / 2, tw, th), on > 0, on > 0 && on < r.Children.Count, Enabled, false);
                    continue;
                }
                Color tc = r.Entry.On ? GGStyle.Ink : GGUi.Sub;
                TextRenderer.DrawText(g, r.Text, fItem, new Rectangle(pad + GGUi.P(14), top, w - 2 * pad - tw - GGUi.P(120), r.H), tc,
                    TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
                if (r.Hint.Length > 0)
                {
                    Size ts = TextRenderer.MeasureText(g, r.Text, fItem);
                    TextRenderer.DrawText(g, r.Hint, fHint, new Rectangle(pad + GGUi.P(14) + ts.Width + GGUi.P(4), top, GGUi.P(160), r.H), GGUi.Sub,
                        TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
                }
                GGUi.DrawToggle(g, new Rectangle(w - pad - tw, top + (r.H - th) / 2, tw, th), r.Entry.On, false, Enabled, false);
            }
            if (rows.Count == 0)
            {
                TextRenderer.DrawText(g, filter.Length > 0 ? "Nichts gefunden für „" + filter + "“." : "Die Listen sind leer.",
                    fItem, new Rectangle(pad, GGUi.P(20), w - 2 * pad, GGUi.P(40)), GGUi.Sub, TextFormatFlags.NoPrefix);
            }
        }
        g.ResetTransform();
        using (Pen p = new Pen(GGUi.Line)) g.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
    }
}

// Wochenbalken für "Heute"
public class GGWeek : Control
{
    public int[] Counts = new int[7];
    public string[] Labels = new string[7];
    public GGWeek()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        int max = 1;
        foreach (int c in Counts) max = Math.Max(max, c);
        int lab = GGUi.P(22), top = GGUi.P(22);
        float colW = Width / 7f;
        float barW = Math.Min(GGUi.P(34), colW * 0.55f);
        int baseY = Height - lab;
        using (Pen p = new Pen(GGUi.Line)) g.DrawLine(p, 0, baseY, Width, baseY);
        using (Font f = GGUi.F(8.5f))
        using (Font fb = GGUi.B(8.5f))
        {
            for (int i = 0; i < 7; i++)
            {
                float h = (baseY - top) * Counts[i] / (float)max;
                float x = i * colW + (colW - barW) / 2f;
                Color c = i == 6 ? GGStyle.Red : GGStyle.Ink;
                if (Counts[i] > 0)
                {
                    using (SolidBrush b = new SolidBrush(c)) g.FillRectangle(b, x, baseY - h, barW, h);
                }
                TextRenderer.DrawText(g, Counts[i].ToString(CultureInfo.InvariantCulture), fb,
                    new Rectangle((int)(i * colW), (int)(baseY - h - GGUi.P(20)), (int)colW, GGUi.P(18)), Counts[i] > 0 ? c : GGUi.Off,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPrefix);
                TextRenderer.DrawText(g, Labels[i] ?? "", i == 6 ? fb : f, new Rectangle((int)(i * colW), baseY + GGUi.P(4), (int)colW, lab),
                    i == 6 ? GGStyle.Ink : GGUi.Sub, TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPrefix);
            }
        }
    }
}
// Seitenleiste des Einstellungsfensters
public class GGSidebar : Control
{
    public readonly string[] Pages = { "Heute", "Sperren", "Warnung", "Zeiten", "Über" };
    public int Selected;
    public string Version = "";
    public string Status = "";
    public string State = "aktiv";
    int hover = -1;
    public event Action<int> Picked;

    public GGSidebar()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        BackColor = GGStyle.Ink;
        TabStop = true;
    }

    int ItemTop(int i) { return GGUi.P(132) + i * GGUi.P(44); }

    int Hit(Point p)
    {
        for (int i = 0; i < Pages.Length; i++)
            if (p.Y >= ItemTop(i) && p.Y < ItemTop(i) + GGUi.P(44)) return i;
        return -1;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        int h = Hit(e.Location);
        Cursor = h >= 0 ? Cursors.Hand : Cursors.Default;
        if (h != hover) { hover = h; Invalidate(); }
    }

    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hover = -1; Invalidate(); }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        base.OnMouseClick(e);
        int h = Hit(e.Location);
        if (h >= 0 && Picked != null) Picked(h);
    }

    protected override bool IsInputKey(Keys k) { return k == Keys.Up || k == Keys.Down || base.IsInputKey(k); }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (Picked == null) return;
        if (e.KeyCode == Keys.Down) Picked(Math.Min(Pages.Length - 1, Selected + 1));
        if (e.KeyCode == Keys.Up) Picked(Math.Max(0, Selected - 1));
    }

    protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
    protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        GGStyle.Quality(g);
        int pad = GGUi.P(26);
        GGBrand.DrawMark(g, new RectangleF(pad, GGUi.P(30), GGUi.P(34), GGUi.P(34)), State);
        g.TextRenderingHint = TextRenderingHint.AntiAlias;
        using (Font f = GGUi.Serif(17f))
        using (SolidBrush b = new SolidBrush(GGStyle.Paper))
        {
            g.DrawString("GrindGuard.", f, b, pad - GGUi.P(2), GGUi.P(74));
        }
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        using (Font f = GGUi.F(10.5f))
        using (Font fb = GGUi.B(10.5f))
        {
            for (int i = 0; i < Pages.Length; i++)
            {
                int y = ItemTop(i);
                bool sel = i == Selected;
                if (i == hover && !sel)
                {
                    using (SolidBrush b = new SolidBrush(Color.FromArgb(34, 34, 33))) g.FillRectangle(b, 0, y, Width, GGUi.P(44));
                }
                if (sel)
                {
                    float d = GGUi.P(7);
                    using (SolidBrush b = new SolidBrush(GGStyle.Red)) g.FillEllipse(b, pad - GGUi.P(14), y + GGUi.P(22) - d / 2f, d, d);
                }
                TextRenderer.DrawText(g, Pages[i], sel ? fb : f, new Rectangle(pad, y, Width - pad, GGUi.P(44)),
                    sel ? GGStyle.Paper : Color.FromArgb(160, 158, 150), TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
                if (sel && Focused && ShowFocusCues)
                {
                    using (Pen p = new Pen(GGStyle.Red)) g.DrawRectangle(p, GGUi.P(6), y + 2, Width - GGUi.P(12), GGUi.P(40));
                }
            }
        }
        using (Font f = GGUi.F(8.75f))
        {
            int y = Height - GGUi.P(70);
            Color sc = State == "fokus" ? Color.FromArgb(255, 110, 110) : Color.FromArgb(200, 198, 190);
            TextRenderer.DrawText(g, Status, f, new Rectangle(pad, y, Width - pad - GGUi.P(10), GGUi.P(40)), sc,
                TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
            TextRenderer.DrawText(g, "Version " + Version, f, new Rectangle(pad, Height - GGUi.P(32), Width - pad, GGUi.P(20)),
                Color.FromArgb(120, 118, 112), TextFormatFlags.NoPrefix);
        }
    }
}

// Kleine Dialoge im selben Stil
public class GGDialog : Form
{
    public bool Checked;
    GGToggle check;

    GGDialog(string title, string text, string ok, string cancel, string checkText, bool danger)
    {
        GGUi.S = GGTray.DpiScale();
        Text = "GrindGuard";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = true;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = GGUi.Back;
        Font = GGUi.F(9.75f);
        AutoScaleMode = AutoScaleMode.None;
        try { Icon = GGBrand.TrayIcon(32, "aktiv"); } catch { }
        int w = GGUi.P(480), pad = GGUi.P(30);
        ClientSize = new Size(w, GGUi.P(200));
        PictureBox mark = new PictureBox();
        mark.Image = GGBrand.Mark(GGUi.P(36), "aktiv");
        mark.SizeMode = PictureBoxSizeMode.AutoSize;
        mark.Location = new Point(pad, pad);
        mark.BackColor = Color.Transparent;
        Controls.Add(mark);
        Label t = GGUi.Text(this, title, GGUi.Serif(17f), GGStyle.Ink, pad, pad + GGUi.P(48), w - 2 * pad);
        Label b = GGUi.Text(this, text, GGUi.F(10f), Color.FromArgb(60, 60, 58), pad, t.Bottom + GGUi.P(8), w - 2 * pad);
        int y = b.Bottom + GGUi.P(18);
        if (!string.IsNullOrEmpty(checkText))
        {
            check = new GGToggle();
            check.Location = new Point(pad - GGUi.P(3), y);
            Controls.Add(check);
            Label cl = GGUi.Text(this, checkText, GGUi.F(9.75f), GGStyle.Ink, pad + check.Width + GGUi.P(6), y + GGUi.P(3), w - 2 * pad - check.Width - GGUi.P(6));
            cl.Cursor = Cursors.Hand;
            cl.Click += delegate { check.Flip(); };
            y = Math.Max(check.Bottom, cl.Bottom) + GGUi.P(18);
        }
        GGButton okb = new GGButton(ok, "primary");
        if (danger) okb.BackColor = Color.Transparent;
        int x = w - pad - okb.Width;
        okb.Location = new Point(x, y);
        okb.Click += delegate { Checked = check != null && check.On; DialogResult = DialogResult.OK; Close(); };
        Controls.Add(okb);
        if (!string.IsNullOrEmpty(cancel))
        {
            GGButton cb = new GGButton(cancel, "secondary");
            cb.Location = new Point(x - GGUi.P(10) - cb.Width, y);
            cb.Click += delegate { DialogResult = DialogResult.Cancel; Close(); };
            Controls.Add(cb);
            AcceptButton = null;
            cb.TabIndex = 0;
            okb.TabIndex = 1;
        }
        ClientSize = new Size(w, y + okb.Height + pad);
        KeyPreview = true;
        KeyDown += delegate (object s, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) { DialogResult = DialogResult.Cancel; Close(); } };
    }

    public static bool Ask(string title, string text, string ok, string cancel, string checkText, bool danger, out bool isChecked)
    {
        using (GGDialog d = new GGDialog(title, text, ok, cancel, checkText, danger))
        {
            d.TopMost = true;
            bool r = d.ShowDialog() == DialogResult.OK;
            isChecked = d.Checked;
            return r;
        }
    }

    public static void Info(string title, string text)
    {
        bool dummy;
        Ask(title, text, "OK", null, null, false, out dummy);
    }
}

// Laufende Programme zur Auswahl
public class GGAppPicker : Form
{
    public string Picked;
    readonly ListBox list = new ListBox();
    readonly GGInput manual;
    readonly Label error;
    readonly string[] prot;

    public GGAppPicker(string[] protectedNames)
    {
        prot = protectedNames;
        Text = "Programm sperren";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false; MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;
        BackColor = GGUi.Back;
        Font = GGUi.F(9.75f);
        AutoScaleMode = AutoScaleMode.None;
        int w = GGUi.P(460), pad = GGUi.P(26);
        Label t = GGUi.Text(this, "Programm sperren.", GGUi.Serif(17f), GGStyle.Ink, pad, pad, w - 2 * pad);
        Label s = GGUi.Text(this, "Wähle ein Programm, das gerade läuft – oder tippe den Namen aus dem Task-Manager (Reiter „Details“, ohne .exe).",
            GGUi.F(9.25f), GGUi.Sub, pad, t.Bottom + GGUi.P(4), w - 2 * pad);
        list.Location = new Point(pad, s.Bottom + GGUi.P(14));
        list.Size = new Size(w - 2 * pad, GGUi.P(240));
        list.BorderStyle = BorderStyle.FixedSingle;
        list.DrawMode = DrawMode.OwnerDrawFixed;
        list.ItemHeight = GGUi.P(30);
        list.IntegralHeight = false;
        list.Font = GGUi.F(9.75f);
        list.DrawItem += DrawItem;
        list.DoubleClick += delegate { Accept(); };
        Controls.Add(list);
        manual = new GGInput("oder Name eingeben, z. B. steam", w - 2 * pad);
        manual.Location = new Point(pad, list.Bottom + GGUi.P(12));
        manual.Box.KeyDown += delegate (object o, KeyEventArgs e) { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; Accept(); } };
        Controls.Add(manual);
        error = GGUi.Text(this, " ", GGUi.F(9f), GGStyle.Red, pad, manual.Bottom + GGUi.P(6), w - 2 * pad);
        GGButton ok = new GGButton("Sperren", "primary");
        GGButton cancel = new GGButton("Abbrechen", "secondary");
        int y = error.Bottom + GGUi.P(8);
        ok.Location = new Point(w - pad - ok.Width, y);
        cancel.Location = new Point(ok.Left - GGUi.P(10) - cancel.Width, y);
        ok.Click += delegate { Accept(); };
        cancel.Click += delegate { DialogResult = DialogResult.Cancel; Close(); };
        Controls.Add(ok);
        Controls.Add(cancel);
        ClientSize = new Size(w, ok.Bottom + pad);
        Fill();
    }

    class Item
    {
        public string Name, Title;
        public override string ToString() { return Name; }
    }

    void Fill()
    {
        Dictionary<string, Item> seen = new Dictionary<string, Item>(StringComparer.OrdinalIgnoreCase);
        try
        {
            int me = Process.GetCurrentProcess().Id;
            foreach (Process p in Process.GetProcesses())
            {
                try
                {
                    if (p.Id == me || p.MainWindowHandle == IntPtr.Zero) continue;
                    string title = p.MainWindowTitle;
                    if (string.IsNullOrEmpty(title)) continue;
                    string err;
                    if (GGListFile.NormalizeApp(p.ProcessName, prot, out err) == null) continue;
                    if (!seen.ContainsKey(p.ProcessName))
                    {
                        Item it = new Item();
                        it.Name = p.ProcessName;
                        it.Title = title;
                        seen[p.ProcessName] = it;
                    }
                }
                catch { }
                finally { p.Dispose(); }
            }
        }
        catch { }
        List<Item> items = new List<Item>(seen.Values);
        items.Sort(delegate (Item a, Item b) { return string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase); });
        foreach (Item it in items) list.Items.Add(it);
    }

    void DrawItem(object sender, DrawItemEventArgs e)
    {
        if (e.Index < 0) return;
        Item it = (Item)list.Items[e.Index];
        bool sel = (e.State & DrawItemState.Selected) != 0;
        using (SolidBrush b = new SolidBrush(sel ? GGStyle.Ink : GGUi.Card)) e.Graphics.FillRectangle(b, e.Bounds);
        Rectangle r = e.Bounds;
        r.X += GGUi.P(10);
        using (Font fb = GGUi.B(9.75f))
            TextRenderer.DrawText(e.Graphics, it.Name, fb, r, sel ? GGStyle.Paper : GGStyle.Ink, TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        Size sz = TextRenderer.MeasureText(it.Name, list.Font);
        Rectangle r2 = new Rectangle(r.X + sz.Width + GGUi.P(10), r.Y, r.Width - sz.Width - GGUi.P(24), r.Height);
        TextRenderer.DrawText(e.Graphics, it.Title, list.Font, r2, sel ? Color.FromArgb(200, 198, 190) : GGUi.Sub,
            TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
    }

    void Accept()
    {
        string raw = manual.Box.Text.Trim();
        if (raw.Length == 0 && list.SelectedItem != null) raw = ((Item)list.SelectedItem).Name;
        string err;
        string name = GGListFile.NormalizeApp(raw, prot, out err);
        if (name == null)
        {
            error.Text = err;
            return;
        }
        Picked = name;
        DialogResult = DialogResult.OK;
        Close();
    }
}
// ===================== Einstellungsfenster =====================
public class GGSettings : Form
{
    // ---- Verbindung zum Wächter ----
    public static volatile GGSettings Current;
    public static volatile int ConfigVersion;
    public static volatile bool HostedInDaemon;
    public static string LastError = "";
    static readonly object qlock = new object();
    static readonly Queue<string> requests = new Queue<string>();

    public static string TakeRequest()
    {
        lock (qlock) return requests.Count > 0 ? requests.Dequeue() : null;
    }

    // Im Wächter: eigenes Fenster in einem eigenen Thread, damit beides flüssig bleibt
    public static void OpenAsync(string baseDir, string version, string repo, string[] prot, string page)
    {
        GGSettings cur = Current;
        if (cur != null && !cur.IsDisposed)
        {
            try { cur.BeginInvoke((MethodInvoker)delegate { cur.ShowPage(page); cur.BringUp(); }); } catch { }
            return;
        }
        HostedInDaemon = true;
        Thread th = new Thread(delegate ()
        {
            // Ein Fehler im Fenster darf nie den Wächter mitreissen
            Application.ThreadException += delegate (object sender, ThreadExceptionEventArgs e)
            {
                LastError = e.Exception.ToString();
            };
            try
            {
                GGSettings f = new GGSettings(baseDir, version, repo, prot);
                Current = f;
                f.ShowPage(page);
                Application.Run(f);
            }
            catch (Exception ex) { LastError = ex.ToString(); }
            finally { Current = null; }
        });
        th.SetApartmentState(ApartmentState.STA);
        th.IsBackground = true;
        th.Start();
    }

    // Ohne laufenden Wächter (grind einstellungen)
    public static void ShowModal(string baseDir, string version, string repo, string[] prot, string page)
    {
        HostedInDaemon = false;
        using (GGSettings f = new GGSettings(baseDir, version, repo, prot))
        {
            Current = f;
            f.ShowPage(page);
            f.ShowDialog();
            Current = null;
        }
    }

    // ---- Fenster ----
    readonly string baseDir, confDir, version, repo;
    readonly string[] prot;
    readonly GGState state;
    readonly GGSidebar side = new GGSidebar();
    readonly Panel content = new Panel();
    readonly Panel banner = new Panel();
    readonly Label bannerText = new Label();
    readonly Label toast = new Label();
    readonly Dictionary<string, Panel> pages = new Dictionary<string, Panel>();
    readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
    readonly System.Windows.Forms.Timer toastTimer = new System.Windows.Forms.Timer();
    string current = "";
    int tick;

    GGListFile sites, apps;
    GGKeyFile conf;
    GGList list;
    GGInput search, addSite;
    Label addError;
    readonly List<GGChoice> tones = new List<GGChoice>();
    readonly List<GGThumb> thumbs = new List<GGThumb>();
    bool thumbsDone;
    Label todayNum, todayText, todayStatus, topList;
    GGWeek week;
    FlowLayoutPanel focusRow, pauseRow;
    Label updateStatus;
    GGButton updateGo, updateCheck;
    GGButton uninstall;
    GGToggle always;
    GGStepper from, to;
    readonly List<GGChip> days = new List<GGChip>();

    GGSettings(string baseDir, string version, string repo, string[] prot)
    {
        this.baseDir = baseDir;
        this.version = version;
        this.repo = repo;
        this.prot = prot ?? new string[0];
        confDir = Path.Combine(baseDir, "config");
        state = new GGState(Path.Combine(baseDir, "state"));
        GGUi.S = GGTray.DpiScale();

        Text = "GrindGuard – Einstellungen";
        try { Icon = GGBrand.TrayIcon(32, "aktiv"); } catch { }
        AutoScaleMode = AutoScaleMode.None;
        Font = GGUi.F(9.75f);
        BackColor = GGUi.Back;
        StartPosition = FormStartPosition.CenterScreen;
        // Laptops mit 150 % Skalierung: nie grösser als der freie Bildschirm
        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        ClientSize = new Size(Math.Min(GGUi.P(980), wa.Width - 40), Math.Min(GGUi.P(680), wa.Height - 70));
        MinimumSize = new Size(Math.Min(GGUi.P(760), wa.Width), Math.Min(GGUi.P(500), wa.Height));
        DoubleBuffered = true;
        KeyPreview = true;

        side.Dock = DockStyle.Left;
        side.Width = GGUi.P(236);
        side.Version = version;
        side.Picked += delegate (int i) { ShowPage(side.Pages[i]); };

        content.Dock = DockStyle.Fill;
        content.BackColor = GGUi.Back;

        banner.Dock = DockStyle.Top;
        banner.Height = GGUi.P(46);
        banner.BackColor = GGStyle.Red;
        banner.Visible = false;
        bannerText.Dock = DockStyle.Fill;
        bannerText.ForeColor = GGStyle.Paper;
        bannerText.Font = GGUi.B(9.5f);
        bannerText.TextAlign = ContentAlignment.MiddleLeft;
        bannerText.Padding = new Padding(GGUi.P(34), 0, GGUi.P(20), 0);
        banner.Controls.Add(bannerText);

        toast.AutoSize = false;
        toast.Height = GGUi.P(34);
        toast.Dock = DockStyle.Bottom;
        toast.TextAlign = ContentAlignment.MiddleLeft;
        toast.Padding = new Padding(GGUi.P(34), 0, 0, 0);
        toast.Font = GGUi.F(9f);
        toast.ForeColor = GGUi.Sub;
        toast.BackColor = GGUi.Back;

        Controls.Add(content);
        Controls.Add(side);
        content.Controls.Add(toast);
        content.Controls.Add(banner);
        // Erst die endgültigen Grössen festlegen, dann die Seiten füllen –
        // sonst verrutschen rechts verankerte Elemente beim ersten Layout.
        PerformLayout();
        content.PerformLayout();

        Reload();
        foreach (string p in side.Pages)
        {
            Panel pg = new Panel();
            pg.AutoScroll = true;
            pg.BackColor = GGUi.Back;
            pg.Visible = false;
            pages[p] = pg;
            content.Controls.Add(pg);
            pg.BringToFront();
            pg.Dock = DockStyle.Fill;
        }
        content.PerformLayout();
        BuildHeute(pages["Heute"]);
        BuildSperren(pages["Sperren"]);
        BuildWarnung(pages["Warnung"]);
        BuildZeiten(pages["Zeiten"]);
        BuildUeber(pages["Über"]);

        timer.Interval = 1000;
        timer.Tick += delegate { RefreshLive(); };
        timer.Start();
        toastTimer.Interval = 3500;
        toastTimer.Tick += delegate { toast.Text = ""; toastTimer.Stop(); };
        RefreshLive();
        KeyDown += delegate (object s, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) Close(); };
    }

    public void BringUp()
    {
        if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
        Show();
        Activate();
        GGLockGuard.Front(Handle);
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        BringUp();
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        timer.Stop();
        toastTimer.Stop();
        foreach (GGThumb t in thumbs) if (t.Image != null) t.Image.Dispose();
        base.OnFormClosed(e);
    }

    DateTime stampSites, stampApps;

    void Reload()
    {
        sites = new GGListFile(Path.Combine(confDir, "websites.txt"), false);
        apps = new GGListFile(Path.Combine(confDir, "apps.txt"), true);
        conf = new GGKeyFile(Path.Combine(confDir, "einstellungen.txt"));
        Stamp();
    }

    void Stamp()
    {
        try
        {
            stampSites = File.GetLastWriteTimeUtc(sites.Path);
            stampApps = File.GetLastWriteTimeUtc(apps.Path);
        }
        catch { }
    }

    // Wurde die Datei inzwischen anders gespeichert (Menü, Editor), zuerst neu laden
    // und die Einträge über ihren Text wiederfinden – nie eine veraltete Kopie speichern.
    List<GGEntry> Fresh(GGListFile f, List<GGEntry> es, out GGListFile ff)
    {
        ff = new GGListFile(f.Path, f.Apps);
        List<GGEntry> all = ff.Entries();
        List<GGEntry> r = new List<GGEntry>();
        foreach (GGEntry e in es)
        {
            string text = e.Text;
            GGEntry m = all.Find(delegate (GGEntry x) { return x.Text == text; });
            if (m != null) r.Add(m);
        }
        return r;
    }

    void Keep(GGListFile ff)
    {
        if (ff.Apps) apps = ff; else sites = ff;
        Stamp();
        list.Load(sites, apps);
    }

    void Saved(string what)
    {
        ConfigVersion++;
        Note(what);
    }

    void Note(string text)
    {
        toast.ForeColor = GGUi.Sub;
        toast.Text = text;
        toastTimer.Stop();
        toastTimer.Start();
    }

    void Fail(Exception ex)
    {
        toast.ForeColor = GGStyle.Red;
        toast.Text = "Nicht gespeichert: " + ex.Message;
        toastTimer.Stop();
    }

    public void ShowPage(string name)
    {
        if (name == "Update")
        {
            ShowPage("Über");
            if (updateCheck != null && updateCheck.Enabled) CheckUpdate(updateCheck);
            return;
        }
        if (string.IsNullOrEmpty(name) || !pages.ContainsKey(name)) name = string.IsNullOrEmpty(current) ? "Heute" : current;
        foreach (KeyValuePair<string, Panel> kv in pages) kv.Value.Visible = kv.Key == name;
        current = name;
        side.Selected = Array.IndexOf(side.Pages, name);
        side.Invalidate();
        if (name == "Warnung" && !thumbsDone) BeginInvoke((MethodInvoker)RenderThumbs);
        if (name == "Heute") RefreshToday();
    }

    // Befehl an den Wächter (läuft er nicht, startet ein eigener Prozess)
    void Request(string cmd)
    {
        if (HostedInDaemon)
        {
            lock (qlock) requests.Enqueue(cmd);
            return;
        }
        string[] parts = cmd.Split(':');
        RunGrind(parts[0] + (parts.Length > 1 ? " " + parts[1] : ""), false);
    }

    void RunGrind(string args, bool visible)
    {
        try
        {
            string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            ProcessStartInfo si = new ProcessStartInfo(ps,
                "-NoProfile -ExecutionPolicy Bypass " + (visible ? "" : "-WindowStyle Hidden ") + "-File \"" +
                Path.Combine(baseDir, "grindguard.ps1") + "\" " + args);
            si.UseShellExecute = true;
            si.WindowStyle = visible ? ProcessWindowStyle.Normal : ProcessWindowStyle.Hidden;
            si.WorkingDirectory = Path.GetTempPath();
            Process.Start(si);
        }
        catch (Exception ex) { Fail(ex); }
    }

    static void Open(string file, string args)
    {
        try { Process.Start(file, args); } catch { }
    }

    Label PageHead(Panel p, string title, string sub)
    {
        int x = GGUi.P(36);
        Label t = GGUi.Text(p, title, GGUi.Serif(25f), GGStyle.Ink, x - GGUi.P(3), GGUi.P(26), 0);
        Label s = GGUi.Text(p, sub, GGUi.F(10f), GGUi.Sub, x, t.Bottom + GGUi.P(2), GGUi.P(640));
        return s;
    }

    int Width0 { get { return ClientSize.Width - side.Width; } }

    // ---------------- Heute ----------------
    void BuildHeute(Panel p)
    {
        Label sub = PageHead(p, "Heute.", "Wie es läuft – und ein Klick für die nächste Fokus-Sitzung.");
        int x = GGUi.P(36), y = sub.Bottom + GGUi.P(22);
        todayNum = GGUi.Text(p, "0", GGUi.Serif(54f), GGStyle.Ink, x - GGUi.P(6), y, 0);
        todayText = GGUi.Text(p, "Ausrutscher heute.", GGUi.Serif(17f), GGStyle.Ink, x + GGUi.P(86), y + GGUi.P(22), 0);
        todayStatus = GGUi.Text(p, "", GGUi.F(10f), GGUi.Sub, x + GGUi.P(88), y + GGUi.P(56), GGUi.P(560));
        y += GGUi.P(112);

        GGUi.Caption(p, "Fokus-Sitzung", x, y);
        focusRow = new FlowLayoutPanel();
        focusRow.Location = new Point(x, y + GGUi.P(22));
        focusRow.Size = new Size(GGUi.P(660), GGUi.P(44));
        focusRow.BackColor = Color.Transparent;
        p.Controls.Add(focusRow);
        Label fx = GGUi.Text(p, "Listen eingefroren, keine Pause, kein Beenden – bis die Zeit um ist.", GGUi.F(8.75f), GGUi.Sub, x, y + GGUi.P(68), GGUi.P(640));
        y = fx.Bottom + GGUi.P(16);

        GGUi.Caption(p, "Pause", x, y);
        pauseRow = new FlowLayoutPanel();
        pauseRow.Location = new Point(x, y + GGUi.P(22));
        pauseRow.Size = new Size(GGUi.P(660), GGUi.P(44));
        pauseRow.BackColor = Color.Transparent;
        p.Controls.Add(pauseRow);
        y += GGUi.P(84);

        GGUi.Caption(p, "Die letzten 7 Tage", x, y);
        week = new GGWeek();
        week.Location = new Point(x, y + GGUi.P(24));
        week.Size = new Size(GGUi.P(400), GGUi.P(150));
        p.Controls.Add(week);
        GGUi.Caption(p, "Häufigste Ablenkungen", x + GGUi.P(450), y);
        topList = GGUi.Text(p, "", GGUi.F(10f), GGStyle.Ink, x + GGUi.P(450), y + GGUi.P(28), GGUi.P(240));
        topList.AutoSize = false;
        topList.Height = GGUi.P(150);
        BuildFocusButtons();
    }

    void BuildFocusButtons()
    {
        long fe = state.FocusEnd, pe = state.PauseEnd;
        focusRow.Controls.Clear();
        pauseRow.Controls.Clear();
        if (fe > 0)
        {
            long left = (fe - GGState.Now() + 59) / 60;
            foreach (int add in new int[] { 25, 50 })
            {
                int total = (int)left + add;
                GGButton b = new GGButton("+" + add + " Min verlängern", add == 25 ? "primary" : "secondary");
                b.Margin = new Padding(0, 0, GGUi.P(10), 0);
                b.Click += delegate { Request("fokus:" + total); Note("Fokus-Sitzung wird verlängert …"); };
                focusRow.Controls.Add(b);
            }
        }
        else
        {
            foreach (int m in new int[] { 25, 50, 90 })
            {
                int mm = m;
                GGButton b = new GGButton(m + " Minuten", m == 50 ? "primary" : "secondary");
                b.Margin = new Padding(0, 0, GGUi.P(10), 0);
                b.Click += delegate { Request("fokus:" + mm); Note("Fokus-Sitzung startet …"); };
                focusRow.Controls.Add(b);
            }
        }
        if (pe > 0)
        {
            GGButton b = new GGButton("Pause beenden", "primary");
            b.Click += delegate { Request("weiter"); Note("Pause beendet. Der Wächter ist wieder scharf."); };
            pauseRow.Controls.Add(b);
        }
        else
        {
            foreach (int m in new int[] { 10, 20, 30 })
            {
                int mm = m;
                GGButton b = new GGButton(m + " Minuten", "secondary");
                b.Margin = new Padding(0, 0, GGUi.P(10), 0);
                b.Enabled = fe == 0;
                b.Click += delegate { Request("pause:" + mm); Note("Pause: " + mm + " Minuten."); };
                pauseRow.Controls.Add(b);
            }
        }
    }

    void RefreshToday()
    {
        if (todayNum == null) return;
        List<string[]> strikes = state.Strikes();
        DateTime today = DateTime.Today;
        int n = state.CountOn(strikes, today);
        todayNum.Text = n.ToString(CultureInfo.InvariantCulture);
        todayText.Text = n == 1 ? "Ausrutscher heute." : "Ausrutscher heute.";
        todayText.Left = todayNum.Right + GGUi.P(6);
        todayStatus.Left = todayText.Left + GGUi.P(2);
        int start = conf.GetInt("SPERRZEIT_START", 10, 3, 300), plus = conf.GetInt("SPERRZEIT_PLUS", 5, 0, 300), max = conf.GetInt("SPERRZEIT_MAX", 60, 3, 300);
        int next = Math.Min(Math.Max(start, 3) + plus * n, Math.Max(max, start));
        todayStatus.Text = "Nächste Sperre: " + next + " Sekunden.";
        string[] names = { "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa" };
        for (int i = 0; i < 7; i++)
        {
            DateTime d = today.AddDays(i - 6);
            week.Counts[i] = state.CountOn(strikes, d);
            week.Labels[i] = i == 6 ? "Heute" : names[(int)d.DayOfWeek];
        }
        week.Invalidate();
        Dictionary<string, int> top = new Dictionary<string, int>();
        foreach (string[] s in strikes)
        {
            string k = s[2].Trim();
            if (k.Length == 0) continue;
            int c;
            top.TryGetValue(k, out c);
            top[k] = c + 1;
        }
        List<KeyValuePair<string, int>> sorted = new List<KeyValuePair<string, int>>(top);
        sorted.Sort(delegate (KeyValuePair<string, int> a, KeyValuePair<string, int> b) { return b.Value.CompareTo(a.Value); });
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < sorted.Count && i < 6; i++) sb.Append(sorted[i].Value).Append("×   ").Append(sorted[i].Key).Append("\n");
        topList.Text = sb.Length > 0 ? sb.ToString() : "Noch nichts. Gut so.";
    }

    void RefreshLive()
    {
        tick++;
        long fe = state.FocusEnd, pe = state.PauseEnd;
        string st = fe > 0 ? "fokus" : (pe > 0 ? "pause" : "aktiv");
        string status = fe > 0 ? "Fokus-Sitzung bis " + GGState.Clock(fe) + " Uhr."
            : (pe > 0 ? "Pause bis " + GGState.Clock(pe) + " Uhr." : "Wächter aktiv.");
        bool changed = side.State != st || side.Status != status;
        side.State = st;
        side.Status = status;
        if (changed) side.Invalidate();
        banner.Visible = fe > 0;
        if (fe > 0)
            bannerText.Text = "Fokus-Sitzung bis " + GGState.Clock(fe) + " Uhr. Deine Regeln sind eingefroren – Änderungen hier gelten ab der nächsten Sitzung.";
        if (uninstall != null) uninstall.Enabled = fe == 0;
        if (changed && focusRow != null) BuildFocusButtons();
        try
        {
            if (list != null && (File.GetLastWriteTimeUtc(sites.Path) != stampSites || File.GetLastWriteTimeUtc(apps.Path) != stampApps))
            {
                Reload();
                list.Load(sites, apps);
            }
        }
        catch { }
        if (current == "Heute" && (changed || tick % 5 == 0)) RefreshToday();
    }

    // ---------------- Sperren ----------------
    void BuildSperren(Panel p)
    {
        p.AutoScroll = false;
        Label sub = PageHead(p, "Sperren.", "Was GrindGuard schliesst. Schalter aus = bleibt offen. Jede Änderung wirkt sofort.");
        int x = GGUi.P(36), y = sub.Bottom + GGUi.P(18);
        int w = p.ClientSize.Width - 2 * x;
        search = new GGInput("Suchen, z. B. youtube oder steam", GGUi.P(300));
        search.Location = new Point(x, y);
        search.Box.TextChanged += delegate { list.Filter = search.Box.Text; };
        p.Controls.Add(search);
        GGButton allOff = new GGButton("Alle aus", "secondary");
        GGButton allOn = new GGButton("Alle an", "secondary");
        allOff.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        allOn.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        allOff.Location = new Point(x + w - allOff.Width, y);
        allOn.Location = new Point(allOff.Left - GGUi.P(10) - allOn.Width, y);
        allOff.Click += delegate { SetMany(list.VisibleEntries(false), false); };
        allOn.Click += delegate { SetMany(list.VisibleEntries(false), true); };
        p.Controls.Add(allOff);
        p.Controls.Add(allOn);
        y += GGUi.P(50);

        int bottomH = GGUi.P(92);
        list = new GGList();
        list.Location = new Point(x, y);
        list.Size = new Size(w, p.ClientSize.Height - y - bottomH);
        list.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        list.Load(sites, apps);
        list.Toggled += delegate (GGListFile f, List<GGEntry> es, bool on) { Apply(f, es, on); };
        p.Controls.Add(list);

        addSite = new GGInput("Website oder Suchbegriff sperren, z. B. chess.com oder suche: memes", GGUi.P(420));
        addSite.Anchor = AnchorStyles.Bottom | AnchorStyles.Left;
        addSite.Location = new Point(x, p.ClientSize.Height - bottomH + GGUi.P(18));
        addSite.Box.KeyDown += delegate (object o, KeyEventArgs e) { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; AddSite(); } };
        p.Controls.Add(addSite);
        GGButton addBtn = new GGButton("Sperren", "primary");
        addBtn.Anchor = AnchorStyles.Bottom | AnchorStyles.Left;
        addBtn.Location = new Point(addSite.Right + GGUi.P(10), addSite.Top);
        addBtn.Click += delegate { AddSite(); };
        p.Controls.Add(addBtn);
        GGButton pick = new GGButton("Programm wählen …", "secondary");
        pick.Anchor = AnchorStyles.Bottom | AnchorStyles.Right;
        pick.Location = new Point(x + w - pick.Width, addSite.Top);
        pick.Click += delegate { PickApp(); };
        p.Controls.Add(pick);
        addError = GGUi.Text(p, " ", GGUi.F(8.75f), GGStyle.Red, x, addSite.Bottom + GGUi.P(4), GGUi.P(520));
        addError.Anchor = AnchorStyles.Bottom | AnchorStyles.Left;
    }

    void Apply(GGListFile f, List<GGEntry> es, bool on)
    {
        try
        {
            GGListFile ff;
            List<GGEntry> fresh = Fresh(f, es, out ff);
            foreach (GGEntry e in fresh) ff.Set(e, on);
            ff.Save();
            Keep(ff);
            string what = es.Count == 1 ? es[0].Display : es.Count + " Einträge";
            Saved(what + (on ? " wird gesperrt." : " bleibt jetzt offen."));
        }
        catch (Exception ex) { Fail(ex); Reload(); list.Load(sites, apps); }
    }

    void SetMany(List<GGEntry> es, bool on)
    {
        try
        {
            List<GGEntry> ws = new List<GGEntry>(), xs = new List<GGEntry>();
            foreach (GGEntry e in es)
            {
                GGListFile f = list.FileOf(e);
                if (f == sites) ws.Add(e); else if (f == apps) xs.Add(e);
            }
            GGListFile fs, fa;
            List<GGEntry> a1 = Fresh(sites, ws, out fs), a2 = Fresh(apps, xs, out fa);
            foreach (GGEntry e in a1) fs.Set(e, on);
            foreach (GGEntry e in a2) fa.Set(e, on);
            if (a1.Count > 0) fs.Save();
            if (a2.Count > 0) fa.Save();
            sites = fs;
            apps = fa;
            Stamp();
            list.Load(sites, apps);
            Saved(on ? "Alles Angezeigte wird gesperrt." : "Alles Angezeigte bleibt offen.");
        }
        catch (Exception ex) { Fail(ex); Reload(); list.Load(sites, apps); }
    }

    void AddSite()
    {
        string err;
        string entry = GGListFile.NormalizeSite(addSite.Box.Text, out err);
        if (entry == null) { addError.Text = err; return; }
        try
        {
            GGListFile ff = new GGListFile(sites.Path, false);
            ff.Add(entry);
            ff.Save();
            addError.Text = " ";
            addSite.Box.Text = "";
            Keep(ff);
            Saved(entry + " wird ab jetzt gesperrt.");
        }
        catch (Exception ex) { Fail(ex); }
    }

    void PickApp()
    {
        using (GGAppPicker d = new GGAppPicker(prot))
        {
            if (d.ShowDialog(this) != DialogResult.OK || string.IsNullOrEmpty(d.Picked)) return;
            try
            {
                GGListFile ff = new GGListFile(apps.Path, true);
                ff.Add(d.Picked);
                ff.Save();
                Keep(ff);
                Saved(d.Picked + " wird ab jetzt geschlossen.");
            }
            catch (Exception ex) { Fail(ex); }
        }
    }

    // ---------------- Warnung ----------------
    void Set(string key, string value, string comment)
    {
        try
        {
            conf = new GGKeyFile(Path.Combine(confDir, "einstellungen.txt"));
            conf.Set(key, value, comment);
            conf.Save();
            Saved("Gespeichert.");
        }
        catch (Exception ex) { Fail(ex); conf = new GGKeyFile(Path.Combine(confDir, "einstellungen.txt")); }
    }

    void BuildWarnung(Panel p)
    {
        Label sub = PageHead(p, "Warnung.", "Wie die Sperre aussieht, klingt und wie lange sie dauert.");
        int x = GGUi.P(36), y = sub.Bottom + GGUi.P(24);
        GGUi.Caption(p, "Ton", x, y);
        y += GGUi.P(24);
        string ton = conf.Get("TON", "brutal");
        string[][] t = {
            new string[] { "brutal", "Brutal", "Harte Ansage, mit deinen Sprüchen aus sprueche.txt." },
            new string[] { "direkt", "Direkt", "Sachlich und klar. Keine Predigt." },
            new string[] { "ruhig", "Ruhig", "Freundlich, ohne Druck. Für entspannte Tage." } };
        int cw = GGUi.P(206), ch = GGUi.P(92);
        for (int i = 0; i < t.Length; i++)
        {
            GGChoice c = new GGChoice(t[i][1], t[i][2], cw, ch);
            c.Tag = t[i][0];
            c.Location = new Point(x + i * (cw + GGUi.P(12)), y);
            c.Selected = ton == t[i][0];
            c.Click += delegate (object s, EventArgs e)
            {
                GGChoice me = (GGChoice)s;
                foreach (GGChoice o in tones) o.Selected = o == me;
                Set("TON", (string)me.Tag, null);
            };
            tones.Add(c);
            p.Controls.Add(c);
        }
        y += ch + GGUi.P(30);

        GGUi.Caption(p, "Design der Sperre", x, y);
        y += GGUi.P(24);
        string design = conf.Get("DESIGN", "wechselnd").ToLowerInvariant();
        string[] keys = { "wechselnd", "nacht", "kobalt", "papier", "lexikon", "bordeaux" };
        string[] titles = { "Wechselnd", "Nacht", "Kobalt", "Papier", "Lexikon", "Bordeaux" };
        int tw = GGUi.P(206), th = GGUi.P(146);
        for (int i = 0; i < keys.Length; i++)
        {
            GGThumb tb = new GGThumb(titles[i], tw, th);
            tb.Tag = keys[i];
            tb.Location = new Point(x + (i % 3) * (tw + GGUi.P(12)), y + (i / 3) * (th + GGUi.P(10)));
            tb.Selected = design == keys[i] || (i == 0 && Array.IndexOf(keys, design) < 0);
            tb.Click += delegate (object s, EventArgs e)
            {
                GGThumb me = (GGThumb)s;
                foreach (GGThumb o in thumbs) o.Selected = o == me;
                Set("DESIGN", (string)me.Tag, "Design der Sperre: wechselnd, nacht, kobalt, papier, lexikon oder bordeaux");
            };
            thumbs.Add(tb);
            p.Controls.Add(tb);
        }
        y += 2 * (th + GGUi.P(10)) + GGUi.P(4);
        GGButton prev = new GGButton("Vorschau zeigen (6 Sekunden)", "secondary");
        prev.Location = new Point(x, y);
        prev.Click += delegate
        {
            string d = "wechselnd";
            foreach (GGThumb o in thumbs) if (o.Selected) d = (string)o.Tag;
            Request("test:" + d);
        };
        p.Controls.Add(prev);
        y += prev.Height + GGUi.P(34);

        GGUi.Caption(p, "Sperrzeit", x, y);
        y += GGUi.P(26);
        int sStart = conf.GetInt("SPERRZEIT_START", 10, 3, 300), sPlus = conf.GetInt("SPERRZEIT_PLUS", 5, 0, 300), sMax = conf.GetInt("SPERRZEIT_MAX", 60, 3, 300);
        GGStepper a = Stepper(p, "Erster Ausrutscher des Tages", x, y, 3, 300, 5, sStart, "s");
        GGStepper b = Stepper(p, "Jeder weitere zusätzlich", x + GGUi.P(220), y, 0, 120, 5, sPlus, "+s");
        GGStepper c2 = Stepper(p, "Höchstens", x + GGUi.P(440), y, 3, 300, 10, sMax, "s");
        a.Changed += delegate { if (a.Value > c2.Value) c2.Value = a.Value; Set("SPERRZEIT_START", a.Value.ToString(CultureInfo.InvariantCulture), null); if (c2.Value == a.Value) Set("SPERRZEIT_MAX", c2.Value.ToString(CultureInfo.InvariantCulture), null); };
        b.Changed += delegate { Set("SPERRZEIT_PLUS", b.Value.ToString(CultureInfo.InvariantCulture), null); };
        c2.Changed += delegate { if (c2.Value < a.Value) a.Value = c2.Value; Set("SPERRZEIT_MAX", c2.Value.ToString(CultureInfo.InvariantCulture), null); if (a.Value == c2.Value) Set("SPERRZEIT_START", a.Value.ToString(CultureInfo.InvariantCulture), null); };
        y += GGUi.P(84);

        GGUi.Caption(p, "Ton und Stimme", x, y);
        y += GGUi.P(26);
        int rowW = GGUi.P(652);
        GGSwitchRow alarm = new GGSwitchRow("Alarmton", "Kurzer Warnton, wenn die Sperre kommt.", rowW);
        alarm.Location = new Point(x, y);
        alarm.Toggle.On = conf.Get("ALARMTON", "1") == "1";
        alarm.Toggle.Changed += delegate { Set("ALARMTON", alarm.Toggle.On ? "1" : "0", null); };
        p.Controls.Add(alarm);
        y = alarm.Bottom + GGUi.P(12);
        GGSwitchRow voice = new GGSwitchRow("Warnung vorlesen", "Braucht eine deutsche Stimme in Windows (siehe grind doctor).", rowW);
        voice.Location = new Point(x, y);
        voice.Toggle.On = conf.Get("STIMME", "1") == "1";
        voice.Toggle.Changed += delegate { Set("STIMME", voice.Toggle.On ? "1" : "0", null); };
        p.Controls.Add(voice);
        y = voice.Bottom + GGUi.P(14);
        GGStepper vol = Stepper(p, "Lautstärke", x, y, 0, 100, 10, conf.GetInt("LAUTSTAERKE", 100, 0, 100), "%");
        vol.Changed += delegate { Set("LAUTSTAERKE", vol.Value.ToString(CultureInfo.InvariantCulture), null); };
        y += GGUi.P(90);
        Panel spacer = new Panel();
        spacer.Location = new Point(x, y);
        spacer.Size = new Size(1, GGUi.P(20));
        p.Controls.Add(spacer);
    }

    GGStepper Stepper(Panel p, string label, int x, int y, int min, int max, int step, int val, string unit)
    {
        GGUi.Text(p, label, GGUi.F(9.25f), GGUi.Sub, x, y, 0);
        GGStepper s = new GGStepper(min, max, step, val);
        s.Location = new Point(x, y + GGUi.P(24));
        if (unit == "s") s.Format = delegate (int v) { return v + " s"; };
        else if (unit == "+s") s.Format = delegate (int v) { return "+" + v + " s"; };
        else if (unit == "%") s.Format = delegate (int v) { return v + " %"; };
        p.Controls.Add(s);
        return s;
    }

    void RenderThumbs()
    {
        thumbsDone = true;
        string[] quotes = SampleQuotes();
        foreach (GGThumb t in thumbs)
        {
            string key = (string)t.Tag;
            try
            {
                Bitmap full;
                if (key == "wechselnd")
                {
                    full = new Bitmap(960, 540, PixelFormat.Format32bppArgb);
                    using (Graphics g = Graphics.FromImage(full))
                    {
                        for (int i = 0; i < GGPlates.Names.Length; i++)
                        {
                            using (Bitmap one = GGPlates.Render(GGPlates.Sample(GGPlates.Names[i], quotes), 960, 540, 0.62f, 9))
                            {
                                int sx = i * 960 / GGPlates.Names.Length, sw = 960 / GGPlates.Names.Length + 1;
                                g.DrawImage(one, new Rectangle(sx, 0, sw, 540), new Rectangle(sx, 0, sw, 540), GraphicsUnit.Pixel);
                            }
                        }
                    }
                }
                else full = GGPlates.Render(GGPlates.Sample(key, quotes), 960, 540, 0.62f, 9);
                Bitmap small = new Bitmap(t.Width - GGUi.P(8), t.Height - GGUi.P(34), PixelFormat.Format32bppArgb);
                using (Graphics g = Graphics.FromImage(small))
                {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(full, new Rectangle(0, 0, small.Width, small.Height));
                }
                full.Dispose();
                t.Image = small;
                t.Invalidate();
                Application.DoEvents();
            }
            catch { }
        }
    }

    string[] SampleQuotes()
    {
        List<string> q = new List<string>();
        try
        {
            foreach (string l in File.ReadAllLines(Path.Combine(confDir, "sprueche.txt"), Encoding.UTF8))
                if (l.Trim().Length > 0 && !l.TrimStart().StartsWith("#")) q.Add(l.Trim());
        }
        catch { }
        return q.ToArray();
    }

    // ---------------- Zeiten ----------------
    void BuildZeiten(Panel p)
    {
        Label sub = PageHead(p, "Zeiten.", "Wann GrindGuard aufpasst – und wie streng er dabei ist.");
        int x = GGUi.P(36), y = sub.Bottom + GGUi.P(24);
        int rowW = GGUi.P(652);
        string zeit = conf.Get("AKTIVE_ZEIT", "00:00-24:00");
        string tage = conf.Get("AKTIVE_TAGE", "1234567");
        int von = 0, bis = 1440;
        Match m = Regex.Match(zeit, @"^([0-2][0-9]):([0-5][0-9])-([0-2][0-9]):([0-5][0-9])$");
        if (m.Success)
        {
            von = int.Parse(m.Groups[1].Value) * 60 + int.Parse(m.Groups[2].Value);
            bis = int.Parse(m.Groups[3].Value) * 60 + int.Parse(m.Groups[4].Value);
        }
        bool immer = (von == 0 && bis == 1440 || von == bis) && tage == "1234567";

        GGUi.Caption(p, "Aktiv", x, y);
        y += GGUi.P(26);
        GGSwitchRow all = new GGSwitchRow("Immer aktiv", "Rund um die Uhr, an allen Tagen. Ausschalten, um Zeiten festzulegen.", rowW);
        all.Location = new Point(x, y);
        all.Toggle.On = immer;
        always = all.Toggle;
        p.Controls.Add(all);
        y = all.Bottom + GGUi.P(18);
        Func<int, string> hm = delegate (int v) { return (v / 60).ToString("00") + ":" + (v % 60).ToString("00"); };
        GGUi.Text(p, "Von", GGUi.F(9.25f), GGUi.Sub, x, y, 0);
        from = new GGStepper(0, 1440, 15, immer ? 480 : von);
        from.Format = hm;
        from.Location = new Point(x, y + GGUi.P(24));
        p.Controls.Add(from);
        GGUi.Text(p, "Bis", GGUi.F(9.25f), GGUi.Sub, x + GGUi.P(170), y, 0);
        to = new GGStepper(0, 1440, 15, immer ? 1080 : bis);
        to.Format = hm;
        to.Location = new Point(x + GGUi.P(170), y + GGUi.P(24));
        p.Controls.Add(to);
        GGUi.Text(p, "Über Mitternacht geht auch (z. B. 22:00 bis 02:00).", GGUi.F(8.75f), GGUi.Sub, x + GGUi.P(340), y + GGUi.P(34), GGUi.P(300));
        y += GGUi.P(80);
        GGUi.Text(p, "Tage", GGUi.F(9.25f), GGUi.Sub, x, y, 0);
        string[] dn = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" };
        string useDays = immer ? "12345" : tage;
        for (int i = 0; i < 7; i++)
        {
            GGChip c = new GGChip(dn[i]);
            c.Location = new Point(x + i * (c.Width + GGUi.P(8)), y + GGUi.P(24));
            c.On = useDays.IndexOf((char)('1' + i)) >= 0;
            c.Changed += delegate { SaveTimes(); };
            days.Add(c);
            p.Controls.Add(c);
        }
        from.Changed += delegate { SaveTimes(); };
        to.Changed += delegate { SaveTimes(); };
        always.Changed += delegate { SaveTimes(); };
        y += GGUi.P(90);
        EnableTimes();

        GGUi.Caption(p, "Verhalten", x, y);
        y += GGUi.P(26);
        y = Switch(p, x, y, rowW, "Nach der Sperre zurück zur Arbeit", "Bringt die letzte erlaubte App wieder nach vorne.", "ZURUECK");
        y = Switch(p, x, y, rowW, "Jagd-Erkennung", "Drei Ausrutscher in 10 Minuten = sofort die maximale Sperrzeit.", "JAGD");
        y = Switch(p, x, y, rowW, "Hart beenden", "Reagiert ein gesperrtes Programm nicht, wird es erzwungen geschlossen (ungespeichertes geht verloren).", "HART_BEENDEN");
        Panel spacer = new Panel();
        spacer.Location = new Point(x, y);
        spacer.Size = new Size(1, GGUi.P(20));
        p.Controls.Add(spacer);
    }

    int Switch(Panel p, int x, int y, int w, string title, string desc, string key)
    {
        GGSwitchRow r = new GGSwitchRow(title, desc, w);
        r.Location = new Point(x, y);
        r.Toggle.On = conf.Get(key, "1") == "1";
        r.Toggle.Changed += delegate { Set(key, r.Toggle.On ? "1" : "0", null); };
        p.Controls.Add(r);
        return r.Bottom + GGUi.P(12);
    }

    void EnableTimes()
    {
        bool on = !always.On;
        from.Enabled = on;
        to.Enabled = on;
        foreach (GGChip c in days) c.Enabled = on;
    }

    void SaveTimes()
    {
        EnableTimes();
        string z, t;
        if (always.On) { z = "00:00-24:00"; t = "1234567"; }
        else
        {
            Func<int, string> hm = delegate (int v) { return (v / 60).ToString("00") + ":" + (v % 60).ToString("00"); };
            z = hm(from.Value) + "-" + hm(to.Value);
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < days.Count; i++) if (days[i].On) sb.Append((char)('1' + i));
            t = sb.Length > 0 ? sb.ToString() : "1234567";
        }
        try
        {
            conf = new GGKeyFile(Path.Combine(confDir, "einstellungen.txt"));
            conf.Set("AKTIVE_ZEIT", z, null);
            conf.Set("AKTIVE_TAGE", t, null);
            conf.Save();
            Saved(always.On ? "Immer aktiv." : "Aktiv " + z.Replace("-", " bis ") + " Uhr.");
        }
        catch (Exception ex) { Fail(ex); }
    }

    // ---------------- Über ----------------
    void BuildUeber(Panel p)
    {
        int x = GGUi.P(36), y = GGUi.P(34);
        PictureBox mark = new PictureBox();
        mark.Image = GGBrand.Mark(GGUi.P(56), "aktiv");
        mark.SizeMode = PictureBoxSizeMode.AutoSize;
        mark.BackColor = Color.Transparent;
        mark.Location = new Point(x, y);
        p.Controls.Add(mark);
        Label t = GGUi.Text(p, "GrindGuard.", GGUi.Serif(30f), GGStyle.Ink, x - GGUi.P(4), y + GGUi.P(66), 0);
        Label v = GGUi.Text(p, "Version " + version + " für Windows", GGUi.F(10f), GGUi.Sub, x, t.Bottom, 0);
        y = v.Bottom + GGUi.P(16);
        Label d = GGUi.Text(p, "Dein Fokus-Wächter. Kein Konto, keine Cloud: Alles bleibt auf deinem PC. Nur wenn du unten auf „Nach Updates suchen“ klickst, fragt GrindGuard bei GitHub nach der neuesten Version.",
            GGUi.F(10f), Color.FromArgb(60, 60, 58), x, y, GGUi.P(600));
        y = d.Bottom + GGUi.P(26);

        GGUi.Caption(p, "Updates", x, y);
        y += GGUi.P(26);
        GGButton check = new GGButton("Nach Updates suchen", "secondary");
        updateCheck = check;
        check.Location = new Point(x, y);
        p.Controls.Add(check);
        updateGo = new GGButton("Jetzt aktualisieren", "primary");
        updateGo.Location = new Point(check.Right + GGUi.P(10), y);
        updateGo.Visible = false;
        updateGo.Click += delegate
        {
            if (state.FocusEnd > 0) { Note("Updates gibt es nach der Fokus-Sitzung."); return; }
            RunGrind("update fenster", true);
            Note("Das Update läuft im neuen Fenster.");
        };
        p.Controls.Add(updateGo);
        updateStatus = GGUi.Text(p, " ", GGUi.F(9.5f), GGUi.Sub, x, y + check.Height + GGUi.P(8), GGUi.P(600));
        check.Click += delegate { CheckUpdate(check); };
        y = updateStatus.Bottom + GGUi.P(22);

        GGUi.Caption(p, "Hilfe", x, y);
        y += GGUi.P(24);
        GGButton help = new GGButton("Anleitung öffnen", "link");
        help.Location = new Point(x, y);
        help.Click += delegate { Open("notepad.exe", "\"" + Path.Combine(baseDir, "LIESMICH.txt") + "\""); };
        p.Controls.Add(help);
        GGButton folder = new GGButton("Ordner mit den Listen", "link");
        folder.Location = new Point(help.Right + GGUi.P(26), y);
        folder.Click += delegate { Open("explorer.exe", "\"" + confDir + "\""); };
        p.Controls.Add(folder);
        GGButton log = new GGButton("Protokoll", "link");
        log.Location = new Point(folder.Right + GGUi.P(26), y);
        log.Click += delegate { Open("notepad.exe", "\"" + Path.Combine(Path.Combine(baseDir, "state"), "grindguard.log") + "\""); };
        p.Controls.Add(log);
        GGButton web = new GGButton("Projektseite", "link");
        web.Location = new Point(log.Right + GGUi.P(26), y);
        web.Click += delegate { Open("https://github.com/" + repo, ""); };
        p.Controls.Add(web);
        y += help.Height + GGUi.P(40);

        uninstall = new GGButton("GrindGuard deinstallieren …", "danger");
        uninstall.Location = new Point(x, y);
        uninstall.Click += delegate
        {
            if (state.FocusEnd > 0) { Note("Während einer Fokus-Sitzung geht das nicht."); return; }
            RunGrind("deinstallieren", false);
        };
        p.Controls.Add(uninstall);
    }

    void CheckUpdate(GGButton btn)
    {
        btn.Enabled = false;
        updateStatus.ForeColor = GGUi.Sub;
        updateStatus.Text = "Frage GitHub …";
        updateGo.Visible = false;
        ThreadPool.QueueUserWorkItem(delegate
        {
            string err;
            string latest = GGUpdate.Latest(repo, out err);
            try
            {
                BeginInvoke((MethodInvoker)delegate
                {
                    btn.Enabled = true;
                    if (latest == null)
                    {
                        updateStatus.ForeColor = GGStyle.Red;
                        updateStatus.Text = "Keine Verbindung zu GitHub (" + err + ").";
                    }
                    else if (GGUpdate.Newer(latest, version))
                    {
                        updateStatus.ForeColor = GGStyle.Ink;
                        updateStatus.Text = "GrindGuard " + latest + " ist da. Deine Listen und Einstellungen bleiben erhalten.";
                        updateGo.Visible = true;
                    }
                    else updateStatus.Text = "Du hast die neueste Version (" + version + ").";
                });
            }
            catch { }
        });
    }
}
