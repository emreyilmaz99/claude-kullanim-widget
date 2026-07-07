using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;
using Microsoft.Win32;
using Path = System.Windows.Shapes.Path;

namespace ClaudeUsageWidget;

public partial class MainWindow : Window
{
    private static readonly string CredPath =
        System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude", ".credentials.json");
    private static readonly string ProjectsDir =
        System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude", "projects");
    private static readonly string SettingsPath =
        System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ClaudeUsageWidget", "settings.json");
    private const string UsageUrl = "https://api.anthropic.com/api/oauth/usage";
    private const string ProfileUrl = "https://api.anthropic.com/api/oauth/profile";

    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValueName = "ClaudeUsageWidget";

    private const string RepoOwner = "emreyilmaz99";
    private const string RepoName = "claude-kullanim-widget";
    private static readonly Version CurrentVersion = typeof(MainWindow).Assembly.GetName().Version ?? new Version(1, 0, 0, 0);
    private string? _updateUrl;

    private const string WarnHex = "#FFFFB454";   // >= %75
    private const string CritHex = "#FFFF5C6B";   // >= %90

    // palet: donut A/B/C halka renkleri + gosterge/mini vurgu rengi
    private sealed record Palette(string Name, string A, string B, string C, string Accent);
    private static readonly (string Key, Palette Pal)[] Palettes =
    {
        ("neon",    new Palette("Neon",    "#FF4C8DFF", "#FFB57BFF", "#FF2FD9C5", "#FF5C9CFF")),
        ("magenta", new Palette("Magenta", "#FFFF3FC8", "#FFC24FFF", "#FFFF6FE0", "#FFFF3FC8")),
        ("mor",     new Palette("Mor",     "#FFA96BFF", "#FF7B84FF", "#FFD08CFF", "#FFA96BFF")),
        ("yesil",   new Palette("Yeşil",   "#FF2FD98C", "#FF22C4A8", "#FF9CE05C", "#FF2FD98C")),
        ("turuncu", new Palette("Turuncu", "#FFFF9640", "#FFFFB454", "#FFFF7B54", "#FFFF9640")),
    };

    // saydamlik on ayarlari
    private static readonly (int Label, double Val)[] OpacityLevels =
        { (100, 1.0), (90, 0.9), (80, 0.8), (70, 0.7), (60, 0.6) };

    private sealed class AppSettings
    {
        public string view { get; set; } = "donut";
        public string palette { get; set; } = "neon";
        public double opacity { get; set; } = 0.9;
        public bool autostart { get; set; }
    }

    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(15) };
    private readonly DispatcherTimer _refreshTimer;
    private readonly DispatcherTimer _animTimer;
    private readonly DispatcherTimer _showTimer;
    private readonly DispatcherTimer _tokenScanTimer;

    private readonly double[] _cur = new double[3];
    private readonly double[] _tgt = new double[3];
    private Path[] _arcs = null!;
    private TextBlock[] _pcts = null!;
    private bool _everOk;
    private bool _tokenBusy;
    private bool _clamping;

    private AppSettings _settings = new();
    private bool _minimized;
    private string _modelName = "Model";
    private Palette Pal => Palettes.FirstOrDefault(p => p.Key == _settings.palette).Pal ?? Palettes[0].Pal;

    // ---- buyuk gosterge ----
    private const double GCX = 75, GCY = 70;
    private const double GaugeStartDeg = 135, GaugeSweepDeg = 270;
    private readonly Line[] _ticks = new Line[41];
    private Ellipse _dashRing = null!, _hub = null!;
    private Path _speedArc = null!, _speedDashArc = null!;
    private Line _needle = null!;
    private readonly TextBlock[] _gaugeLabels = new TextBlock[6];   // 0,20,...,100

    // ---- mini gosterge ----
    private const double MCX = 42, MCY = 42;
    private readonly Line[] _miniTicks = new Line[11];
    private Ellipse _miniDashRing = null!, _miniHub = null!;
    private Path _miniSpeedArc = null!;
    private Line _miniNeedle = null!;

    private readonly Dictionary<string, Ellipse> _swatchSel = new();
    private readonly List<(Border B, double Val)> _opacityPills = new();

    public MainWindow()
    {
        InitializeComponent();
        _arcs = new[] { ArcA, ArcB, ArcC };
        _pcts = new[] { PctA, PctB, PctC };

        LoadSettings();
        BuildGauge();
        BuildMiniGauge();
        BuildSwatches();
        BuildOpacityPills();
        UpdateOptionVisuals();
        UpdateViewVisibility();

        ApplyBgOpacity(_settings.opacity, 0);   // saydamlik yalniz arka plan panellerine
        if (_settings.autostart) SetAutostart(true);   // yol degismis olabilir: tazele
        ApplyPalette();

        _animTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
        _animTimer.Tick += (_, _) => AnimStep();

        _refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(120) };
        _refreshTimer.Tick += async (_, _) => await UpdateUsageAsync();
        _refreshTimer.Start();

        _tokenScanTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(180) };
        _tokenScanTimer.Tick += (_, _) => StartTokenScan();
        _tokenScanTimer.Start();

        // ikinci kez baslatildiginda mevcut pencereyi one getir + gorunur konuma al
        _showTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        _showTimer.Tick += (_, _) =>
        {
            if (App.ShowEvent != null && App.ShowEvent.WaitOne(0))
            {
                _minimized = false;
                UpdateViewVisibility();
                Left = 40; Top = 40;
                Topmost = false; Topmost = true;
                Activate();
            }
        };
        _showTimer.Start();

        MinBtn.MouseLeftButtonUp += (_, _) => { _minimized = true; UpdateViewVisibility(); };
        CloseBtn.MouseLeftButtonUp += (_, _) => Close();
        RefreshBtn.MouseLeftButtonUp += async (_, _) =>
        {
            Status.Text = "yenileniyor...";
            _refreshTimer.Stop(); _refreshTimer.Start();
            StartTokenScan();
            await UpdateUsageAsync();
        };
        SettingsBtn.MouseLeftButtonUp += (_, _) => SettingsPanel.Visibility = Visibility.Visible;
        SetCloseBtn.MouseLeftButtonUp += (_, _) => SettingsPanel.Visibility = Visibility.Collapsed;
        UpdateNotice.MouseLeftButtonUp += (_, _) => OpenUrl(_updateUrl);
        VersionText.Text = $"Sürüm {CurrentVersion.Major}.{CurrentVersion.Minor}.{CurrentVersion.Build}";
        OptDonut.MouseLeftButtonUp += (_, _) => SetView("donut");
        OptSpeed.MouseLeftButtonUp += (_, _) => SetView("speed");
        AutoStartBtn.MouseLeftButtonUp += (_, _) => ToggleAutostart();

        PreviewMouseLeftButtonDown += OnDragStart;
        LocationChanged += OnLocationChanged;
        // uzerine gelince arka plan tamamen belirginlesir, ayrilinca ayarlanan saydamliga doner
        MouseEnter += (_, _) => ApplyBgOpacity(1.0, 150);
        MouseLeave += (_, _) => ApplyBgOpacity(_settings.opacity, 200);

        Loaded += async (_, _) =>
        {
            StartTokenScan();
            _ = CheckUpdateAsync();
            await Task.WhenAll(LoadProfileAsync(), UpdateUsageAsync());
        };
    }

    // ---------- guncelleme kontrolu (GitHub Releases) ----------
    private static Version Norm(Version v) => new(v.Major, v.Minor, Math.Max(v.Build, 0));

    private static void OpenUrl(string? url)
    {
        if (string.IsNullOrEmpty(url)) return;
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
    }

    private async Task CheckUpdateAsync()
    {
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get,
                $"https://api.github.com/repos/{RepoOwner}/{RepoName}/releases/latest");
            req.Headers.TryAddWithoutValidation("User-Agent", "ClaudeUsageWidget");
            req.Headers.TryAddWithoutValidation("Accept", "application/vnd.github+json");
            using var resp = await _http.SendAsync(req);
            if (!resp.IsSuccessStatusCode) return;   // henuz release yok / erisim yok: sessiz gec

            using var doc = JsonDocument.Parse(await resp.Content.ReadAsByteArrayAsync());
            var root = doc.RootElement;
            string? tag = Str(root, "tag_name");
            if (tag == null || !Version.TryParse(tag.TrimStart('v', 'V'), out var latest)) return;
            if (Norm(latest) <= Norm(CurrentVersion)) return;

            _updateUrl = Str(root, "html_url") ?? $"https://github.com/{RepoOwner}/{RepoName}/releases/latest";
            UpdateDot.Visibility = Visibility.Visible;
            UpdateNotice.Text = $"⭳ Güncelleme: v{Norm(latest)}";
            UpdateNotice.Visibility = Visibility.Visible;
        }
        catch { }
    }

    // ---------- ayarlar ----------
    private void LoadSettings()
    {
        try
        {
            if (File.Exists(SettingsPath))
                _settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllBytes(SettingsPath)) ?? new AppSettings();
        }
        catch { _settings = new AppSettings(); }
        if (!Palettes.Any(p => p.Key == _settings.palette)) _settings.palette = "neon";
        if (_settings.view != "donut" && _settings.view != "speed") _settings.view = "donut";
        _settings.opacity = Math.Clamp(_settings.opacity, 0.6, 1.0);
    }

    private void SaveSettings()
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(SettingsPath)!);
            File.WriteAllText(SettingsPath, JsonSerializer.Serialize(_settings));
        }
        catch { }
    }

    private void SetView(string view)
    {
        _settings.view = view;
        UpdateOptionVisuals();
        UpdateViewVisibility();
        SaveSettings();
    }

    private void SetPalette(string key)
    {
        _settings.palette = key;
        ApplyPalette();
        SaveSettings();
    }

    private void SetOpacity(double v)
    {
        _settings.opacity = v;
        ApplyBgOpacity(v, 150);   // secerken aninda onizle
        StyleOpacityPills();
        SaveSettings();
    }

    // Saydamligi YALNIZ arka plan panellerine uygula (icerik/gosterge opak kalir)
    private void ApplyBgOpacity(double to, int ms)
    {
        var anim = new DoubleAnimation(to, TimeSpan.FromMilliseconds(ms));
        FullBg.BeginAnimation(OpacityProperty, anim);
        MiniBg.BeginAnimation(OpacityProperty, anim);
        MiniSpeedBg.BeginAnimation(OpacityProperty, anim);
    }

    private void ToggleAutostart()
    {
        _settings.autostart = !_settings.autostart;
        SetAutostart(_settings.autostart);
        StyleAutostart();
        SaveSettings();
    }

    private static string ExePath => Environment.ProcessPath ?? "";

    private void SetAutostart(bool on)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, true) ?? Registry.CurrentUser.CreateSubKey(RunKeyPath);
            if (on) key.SetValue(RunValueName, $"\"{ExePath}\"");
            else key.DeleteValue(RunValueName, false);
        }
        catch { }
    }

    private void UpdateViewVisibility()
    {
        bool speed = _settings.view == "speed";
        Full.Visibility = _minimized ? Visibility.Collapsed : Visibility.Visible;
        DonutView.Visibility = speed ? Visibility.Collapsed : Visibility.Visible;
        SpeedView.Visibility = speed ? Visibility.Visible : Visibility.Collapsed;
        Mini.Visibility = _minimized && !speed ? Visibility.Visible : Visibility.Collapsed;
        MiniSpeed.Visibility = _minimized && speed ? Visibility.Visible : Visibility.Collapsed;
        if (_minimized) SettingsPanel.Visibility = Visibility.Collapsed;
    }

    private void UpdateOptionVisuals()
    {
        bool speed = _settings.view == "speed";
        StylePill(OptDonut, !speed);
        StylePill(OptSpeed, speed);
    }

    private void StylePill(Border pill, bool selected)
    {
        var ac = ParseColor(Pal.Accent);
        pill.Background = new SolidColorBrush(selected ? Color.FromArgb(0x30, ac.R, ac.G, ac.B) : Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF));
        pill.BorderBrush = new SolidColorBrush(selected ? Color.FromArgb(0x88, ac.R, ac.G, ac.B) : Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF));
    }

    private void BuildSwatches()
    {
        SwatchRow.Children.Clear();
        _swatchSel.Clear();
        foreach (var (key, pal) in Palettes)
        {
            var c = ParseColor(pal.Accent);
            var cell = new Grid { Width = 30, Height = 30, Margin = new Thickness(0, 0, 8, 0), Cursor = Cursors.Hand, Tag = "ui", ToolTip = pal.Name, Background = Brushes.Transparent };
            var sel = new Ellipse { Width = 28, Height = 28, Stroke = Brushes.White, StrokeThickness = 1.6, Visibility = Visibility.Collapsed };
            var dot = new Ellipse
            {
                Width = 20, Height = 20,
                Fill = new SolidColorBrush(c),
                Effect = new DropShadowEffect { Color = c, BlurRadius = 10, ShadowDepth = 0, Opacity = 0.7 }
            };
            cell.Children.Add(sel);
            cell.Children.Add(dot);
            string k = key;
            cell.MouseLeftButtonUp += (_, _) => SetPalette(k);
            _swatchSel[key] = sel;
            SwatchRow.Children.Add(cell);
        }
    }

    private void BuildOpacityPills()
    {
        OpacityRow.Children.Clear();
        _opacityPills.Clear();
        foreach (var (label, val) in OpacityLevels)
        {
            var pill = new Border
            {
                CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(1),
                Padding = new Thickness(9, 4, 9, 5), Cursor = Cursors.Hand, Tag = "ui",
                Margin = new Thickness(0, 0, 6, 0),
                Child = new TextBlock
                {
                    Text = label + "%", FontSize = 10.5,
                    Foreground = new SolidColorBrush(Color.FromRgb(0xE8, 0xE8, 0xF2)),
                    FontFamily = new FontFamily("Segoe UI")
                }
            };
            double v = val;
            pill.MouseLeftButtonUp += (_, _) => SetOpacity(v);
            _opacityPills.Add((pill, val));
            OpacityRow.Children.Add(pill);
        }
    }

    private void StyleOpacityPills()
    {
        var ac = ParseColor(Pal.Accent);
        foreach (var (b, val) in _opacityPills)
        {
            bool sel = Math.Abs(val - _settings.opacity) < 0.001;
            b.Background = new SolidColorBrush(sel ? Color.FromArgb(0x30, ac.R, ac.G, ac.B) : Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF));
            b.BorderBrush = new SolidColorBrush(sel ? Color.FromArgb(0x88, ac.R, ac.G, ac.B) : Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF));
        }
    }

    private void StyleAutostart()
    {
        var ac = ParseColor(Pal.Accent);
        bool on = _settings.autostart;
        AutoStartCheck.Text = on ? "☑" : "☐";   // ☑ / ☐
        AutoStartBtn.Background = new SolidColorBrush(on ? Color.FromArgb(0x30, ac.R, ac.G, ac.B) : Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF));
        AutoStartBtn.BorderBrush = new SolidColorBrush(on ? Color.FromArgb(0x88, ac.R, ac.G, ac.B) : Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF));
    }

    private void ApplyPalette()
    {
        var pal = Pal;
        var ac = ParseColor(pal.Accent);

        // donut halkalar: mevcut hedef degerlerle yeniden boya
        SetRingColor(ArcA, _tgt[0], pal.A);
        SetRingColor(ArcB, _tgt[1], pal.B);
        SetRingColor(ArcC, _tgt[2], pal.C);
        SetRingColor(ArcMini, _tgt[0], pal.Accent);

        // gosterge statikleri
        _dashRing.Stroke = new SolidColorBrush(Color.FromArgb(0x38, ac.R, ac.G, ac.B));
        _hub.Stroke = new SolidColorBrush(Color.FromArgb(0x90, ac.R, ac.G, ac.B));
        if (_hub.Effect is DropShadowEffect hg) hg.Color = ac;
        _miniDashRing.Stroke = new SolidColorBrush(Color.FromArgb(0x44, ac.R, ac.G, ac.B));
        _miniHub.Stroke = new SolidColorBrush(Color.FromArgb(0x90, ac.R, ac.G, ac.B));
        if (_miniHub.Effect is DropShadowEffect mh) mh.Color = ac;
        if (Mini.Effect is DropShadowEffect mg) mg.Color = ac;
        if (MiniSpeed.Effect is DropShadowEffect sg) sg.Color = ac;

        foreach (var (key, sel) in _swatchSel)
            sel.Visibility = key == _settings.palette ? Visibility.Visible : Visibility.Collapsed;

        StyleOpacityPills();
        StyleAutostart();
        UpdateOptionVisuals();
        DrawViews();
    }

    // ---------- gosterge cizimi ----------
    private static Point PtAt(double cx, double cy, double r, double deg)
    {
        double a = deg * Math.PI / 180.0;
        return new Point(cx + r * Math.Cos(a), cy + r * Math.Sin(a));
    }

    private static Geometry? GetSweepArc(double cx, double cy, double r, double startDeg, double endDeg)
    {
        if (endDeg - startDeg < 0.5) return null;
        var fig = new PathFigure { StartPoint = PtAt(cx, cy, r, startDeg), IsClosed = false };
        fig.Segments.Add(new ArcSegment(PtAt(cx, cy, r, endDeg), new Size(r, r), 0, endDeg - startDeg > 180, SweepDirection.Clockwise, true));
        var geo = new PathGeometry();
        geo.Figures.Add(fig);
        return geo;
    }

    private void BuildGauge()
    {
        GaugeCanvas.Children.Clear();

        _dashRing = new Ellipse { Width = 126, Height = 126, StrokeThickness = 3.2, StrokeDashArray = new DoubleCollection { 1.1, 1.5 } };
        Canvas.SetLeft(_dashRing, GCX - 63); Canvas.SetTop(_dashRing, GCY - 63);
        GaugeCanvas.Children.Add(_dashRing);

        _speedDashArc = new Path { StrokeThickness = 3.2, StrokeDashArray = new DoubleCollection { 1.1, 1.5 } };
        GaugeCanvas.Children.Add(_speedDashArc);

        // tikler: %0-100 arasi 41 adet, her %10'da buyuk
        for (int i = 0; i < _ticks.Length; i++)
        {
            bool major = i % 4 == 0;
            double deg = GaugeStartDeg + GaugeSweepDeg * i / (_ticks.Length - 1);
            var p1 = PtAt(GCX, GCY, major ? 47 : 51, deg);
            var p2 = PtAt(GCX, GCY, 58, deg);
            _ticks[i] = new Line
            {
                X1 = p1.X, Y1 = p1.Y, X2 = p2.X, Y2 = p2.Y,
                StrokeThickness = major ? 2.0 : 1.2,
                StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round
            };
            GaugeCanvas.Children.Add(_ticks[i]);
        }

        // rakamlar: 0,20,...,100
        for (int i = 0; i < _gaugeLabels.Length; i++)
        {
            double deg = GaugeStartDeg + GaugeSweepDeg * i / (_gaugeLabels.Length - 1);
            var p = PtAt(GCX, GCY, 39, deg);
            var tb = new TextBlock
            {
                Text = (i * 20).ToString(),
                FontSize = 7, FontFamily = new FontFamily("Bahnschrift, Segoe UI"),
                Foreground = new SolidColorBrush(Color.FromRgb(0x6E, 0x6E, 0x84)),
                Width = 20, TextAlignment = TextAlignment.Center
            };
            Canvas.SetLeft(tb, p.X - 10); Canvas.SetTop(tb, p.Y - 5);
            _gaugeLabels[i] = tb;
            GaugeCanvas.Children.Add(tb);
        }

        _speedArc = new Path
        {
            StrokeThickness = 3,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
            Effect = new DropShadowEffect { BlurRadius = 10, ShadowDepth = 0, Opacity = 0.9 }
        };
        GaugeCanvas.Children.Add(_speedArc);

        _needle = new Line
        {
            StrokeThickness = 2.6,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Triangle,
            Effect = new DropShadowEffect { BlurRadius = 9, ShadowDepth = 0, Opacity = 0.85 }
        };
        GaugeCanvas.Children.Add(_needle);

        _hub = new Ellipse
        {
            Width = 44, Height = 44, StrokeThickness = 1.4,
            Fill = new RadialGradientBrush(Color.FromRgb(0x20, 0x22, 0x2E), Color.FromRgb(0x12, 0x13, 0x1B)),
            Effect = new DropShadowEffect { BlurRadius = 14, ShadowDepth = 0, Opacity = 0.5 }
        };
        Canvas.SetLeft(_hub, GCX - 22); Canvas.SetTop(_hub, GCY - 22);
        GaugeCanvas.Children.Add(_hub);
    }

    private void BuildMiniGauge()
    {
        MiniGaugeCanvas.Children.Clear();

        _miniDashRing = new Ellipse { Width = 66, Height = 66, StrokeThickness = 3, StrokeDashArray = new DoubleCollection { 1.0, 1.4 } };
        Canvas.SetLeft(_miniDashRing, MCX - 33); Canvas.SetTop(_miniDashRing, MCY - 33);
        MiniGaugeCanvas.Children.Add(_miniDashRing);

        // tikler: kucuk kadran hissi
        for (int i = 0; i < _miniTicks.Length; i++)
        {
            bool major = i % 2 == 0;
            double deg = GaugeStartDeg + GaugeSweepDeg * i / (_miniTicks.Length - 1);
            var p1 = PtAt(MCX, MCY, major ? 24 : 26, deg);
            var p2 = PtAt(MCX, MCY, 30, deg);
            _miniTicks[i] = new Line
            {
                X1 = p1.X, Y1 = p1.Y, X2 = p2.X, Y2 = p2.Y,
                StrokeThickness = major ? 1.8 : 1.1,
                StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round
            };
            MiniGaugeCanvas.Children.Add(_miniTicks[i]);
        }

        _miniSpeedArc = new Path
        {
            StrokeThickness = 2.6,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
            Effect = new DropShadowEffect { BlurRadius = 8, ShadowDepth = 0, Opacity = 0.9 }
        };
        MiniGaugeCanvas.Children.Add(_miniSpeedArc);

        _miniNeedle = new Line
        {
            StrokeThickness = 2.2,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Triangle,
            Effect = new DropShadowEffect { BlurRadius = 7, ShadowDepth = 0, Opacity = 0.85 }
        };
        MiniGaugeCanvas.Children.Add(_miniNeedle);

        _miniHub = new Ellipse
        {
            Width = 30, Height = 30, StrokeThickness = 1.3,
            Fill = new RadialGradientBrush(Color.FromRgb(0x20, 0x22, 0x2E), Color.FromRgb(0x12, 0x13, 0x1B)),
            Effect = new DropShadowEffect { BlurRadius = 10, ShadowDepth = 0, Opacity = 0.5 }
        };
        Canvas.SetLeft(_miniHub, MCX - 15); Canvas.SetTop(_miniHub, MCY - 15);
        MiniGaugeCanvas.Children.Add(_miniHub);
    }

    private string LevelHex(double pct) => LevelHex(pct, Pal.Accent);
    private string LevelHex(double pct, string baseHex) => pct >= 90 ? CritHex : pct >= 75 ? WarnHex : baseHex;

    private void UpdateGauge()
    {
        double v = Math.Clamp(_cur[0], 0, 100);
        double deg = GaugeStartDeg + GaugeSweepDeg * v / 100.0;
        var c = ParseColor(LevelHex(v));
        var lit = new SolidColorBrush(c);
        var dim = new SolidColorBrush(Color.FromRgb(0x3A, 0x3A, 0x48));

        _speedArc.Data = GetSweepArc(GCX, GCY, 60.5, GaugeStartDeg, deg);
        _speedArc.Stroke = lit;
        if (_speedArc.Effect is DropShadowEffect ae) ae.Color = c;

        _speedDashArc.Data = GetSweepArc(GCX, GCY, 63, GaugeStartDeg, deg);
        _speedDashArc.Stroke = new SolidColorBrush(Color.FromArgb(0xB4, c.R, c.G, c.B));

        var np1 = PtAt(GCX, GCY, 5, deg + 180);
        var np2 = PtAt(GCX, GCY, 44, deg);
        _needle.X1 = np1.X; _needle.Y1 = np1.Y; _needle.X2 = np2.X; _needle.Y2 = np2.Y;
        _needle.Stroke = lit;
        if (_needle.Effect is DropShadowEffect ne) ne.Color = c;

        int litCount = (int)Math.Round(v / 100.0 * (_ticks.Length - 1));
        for (int i = 0; i < _ticks.Length; i++)
            _ticks[i].Stroke = i <= litCount && v > 0 ? lit : dim;

        PctS.Text = v.ToString("0") + "%";
    }

    private void UpdateMiniGauge()
    {
        double v = Math.Clamp(_cur[0], 0, 100);
        double deg = GaugeStartDeg + GaugeSweepDeg * v / 100.0;
        var c = ParseColor(LevelHex(v));
        var lit = new SolidColorBrush(c);
        var dim = new SolidColorBrush(Color.FromRgb(0x3A, 0x3A, 0x48));

        _miniSpeedArc.Data = GetSweepArc(MCX, MCY, 30, GaugeStartDeg, deg);
        _miniSpeedArc.Stroke = lit;
        if (_miniSpeedArc.Effect is DropShadowEffect ae) ae.Color = c;

        var np1 = PtAt(MCX, MCY, 4, deg + 180);
        var np2 = PtAt(MCX, MCY, 23, deg);
        _miniNeedle.X1 = np1.X; _miniNeedle.Y1 = np1.Y; _miniNeedle.X2 = np2.X; _miniNeedle.Y2 = np2.Y;
        _miniNeedle.Stroke = lit;
        if (_miniNeedle.Effect is DropShadowEffect ne) ne.Color = c;

        int litCount = (int)Math.Round(v / 100.0 * (_miniTicks.Length - 1));
        for (int i = 0; i < _miniTicks.Length; i++)
            _miniTicks[i].Stroke = i <= litCount && v > 0 ? lit : dim;

        PctMiniS.Text = v.ToString("0") + "%";
    }

    // ---------- donut halka cizimi ----------
    private static Geometry? GetArcGeometry(double pct, double cx, double cy, double r)
    {
        if (pct <= 0) return null;
        if (pct >= 99.99) return new EllipseGeometry(new Point(cx, cy), r, r);
        double sweep = 3.6 * pct;
        return GetSweepArc(cx, cy, r, -90, -90 + sweep);
    }

    private void DrawViews()
    {
        for (int i = 0; i < 3; i++)
        {
            _arcs[i].Data = GetArcGeometry(_cur[i], 39, 39, 32);
            _pcts[i].Text = _cur[i].ToString("0") + "%";
        }
        ArcMini.Data = GetArcGeometry(_cur[0], 42, 42, 31);
        PctMini.Text = _cur[0].ToString("0") + "%";

        UpdateGauge();
        UpdateMiniGauge();

        // hiz gorunumu sag bilgi kartlari
        PctWk.Text = _cur[1].ToString("0") + "%";
        PctMd.Text = _cur[2].ToString("0") + "%";
        WkDot.Fill = new SolidColorBrush(ParseColor(LevelHex(_cur[1], Pal.B)));
        MdDot.Fill = new SolidColorBrush(ParseColor(LevelHex(_cur[2], Pal.C)));
    }

    private void AnimStep()
    {
        bool done = true;
        for (int i = 0; i < 3; i++)
        {
            double d = _tgt[i] - _cur[i];
            if (Math.Abs(d) < 0.15) _cur[i] = _tgt[i];
            else { _cur[i] += d * 0.16; done = false; }
        }
        DrawViews();
        if (done) _animTimer.Stop();
    }

    private static Color ParseColor(string hex) => (Color)ColorConverter.ConvertFromString(hex);

    // halka rengi: normalde palet rengi, yuksek kullanimda sari (>=75) / kirmizi (>=90)
    private void SetRingColor(Path arc, double pct, string baseHex)
    {
        var c = ParseColor(LevelHex(pct, baseHex));
        arc.Stroke = new SolidColorBrush(c);
        if (arc.Effect is DropShadowEffect ds) ds.Color = c;
    }

    // ---------- API ----------
    private static string ReadToken()
    {
        using var doc = JsonDocument.Parse(File.ReadAllBytes(CredPath));
        return doc.RootElement.GetProperty("claudeAiOauth").GetProperty("accessToken").GetString() ?? "";
    }

    // JSON spec geregi UTF-8: ham baytlardan parse, charset/encoding sorunu olamaz
    private async Task<JsonDocument> GetJsonAsync(string url)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.TryAddWithoutValidation("Authorization", "Bearer " + ReadToken());
        req.Headers.TryAddWithoutValidation("anthropic-beta", "oauth-2025-04-20");
        using var resp = await _http.SendAsync(req);
        resp.EnsureSuccessStatusCode();
        return JsonDocument.Parse(await resp.Content.ReadAsByteArrayAsync());
    }

    private static double Num(JsonElement el) => el.ValueKind switch
    {
        JsonValueKind.Number => el.GetDouble(),
        JsonValueKind.String when double.TryParse(el.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var d) => d,
        _ => 0.0
    };

    private static string? Str(JsonElement parent, string prop) =>
        parent.TryGetProperty(prop, out var el) && el.ValueKind == JsonValueKind.String ? el.GetString() : null;

    private static string? FormatReset(string? iso)
    {
        if (string.IsNullOrEmpty(iso)) return null;
        if (!DateTimeOffset.TryParse(iso, CultureInfo.InvariantCulture, DateTimeStyles.None, out var at)) return null;
        var span = at - DateTimeOffset.Now;
        if (span.TotalSeconds <= 0) return "now";
        if (span.TotalDays >= 1) return $"{Math.Floor(span.TotalDays)}d {span.Hours}h";
        if (span.TotalHours >= 1) return $"{Math.Floor(span.TotalHours)}h {span.Minutes}m";
        return $"{Math.Floor(span.TotalMinutes)}m";
    }

    private async Task LoadProfileAsync()
    {
        try
        {
            using var doc = await GetJsonAsync(ProfileUrl);
            var root = doc.RootElement;
            root.TryGetProperty("account", out var acc);

            string name = Str(acc, "display_name") ?? Str(acc, "full_name") ?? "Claude";
            UserName.Text = name;
            Initial.Text = name[..1].ToUpperInvariant();

            string tier = root.TryGetProperty("organization", out var org) ? Str(org, "rate_limit_tier") ?? "" : "";
            var m = Regex.Match(tier, @"max_(\d+)x");
            if (m.Success) PlanText.Text = $"MAX {m.Groups[1].Value}x";
            else if (acc.TryGetProperty("has_claude_max", out var hm) && hm.ValueKind == JsonValueKind.True) PlanText.Text = "MAX";
            else if (acc.TryGetProperty("has_claude_pro", out var hp) && hp.ValueKind == JsonValueKind.True) PlanText.Text = "PRO";
            else PlanText.Text = "CLAUDE";
        }
        catch { PlanBadge.Visibility = Visibility.Collapsed; }
    }

    private async Task UpdateUsageAsync()
    {
        SpinT.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromMilliseconds(600)));
        try
        {
            using var doc = await GetJsonAsync(UsageUrl);
            var root = doc.RootElement;

            // ---- yeni 'limits' dizisi: session / weekly_all / weekly_scoped(model) ----
            double sPct = 0, wPct = 0, mPct = 0;
            string? sRst = null, wRst = null, mRst = null, mName = null;
            bool mSeen = false;

            if (root.TryGetProperty("limits", out var limits) && limits.ValueKind == JsonValueKind.Array)
            {
                foreach (var l in limits.EnumerateArray())
                {
                    double p = l.TryGetProperty("percent", out var pe) ? Num(pe) : 0;
                    string? rst = Str(l, "resets_at");
                    switch (Str(l, "kind"))
                    {
                        case "session": sPct = p; sRst = rst; break;
                        case "weekly_all": wPct = p; wRst = rst; break;
                        case "weekly_scoped":
                            // birden fazla modele-ozel limit gelirse en yuksek kullanimliyi goster
                            if (!mSeen || p >= mPct)
                            {
                                mPct = p; mRst = rst; mSeen = true;
                                if (l.TryGetProperty("scope", out var sc) && sc.TryGetProperty("model", out var mo))
                                    mName = Str(mo, "display_name") ?? mName;
                            }
                            break;
                    }
                }
            }
            else
            {
                // eski API alanlarina geri donus
                if (root.TryGetProperty("five_hour", out var fh)) { sPct = Num(fh.GetProperty("utilization")); sRst = Str(fh, "resets_at"); }
                if (root.TryGetProperty("seven_day", out var sd)) { wPct = Num(sd.GetProperty("utilization")); wRst = Str(sd, "resets_at"); }
            }
            if (!mSeen)
            {
                if (root.TryGetProperty("seven_day_opus", out var so)) { mPct = Num(so.GetProperty("utilization")); mRst = Str(so, "resets_at"); mName = "Opus"; }
                else if (root.TryGetProperty("seven_day_sonnet", out var ss)) { mPct = Num(ss.GetProperty("utilization")); mRst = Str(ss, "resets_at"); mName = "Sonnet"; }
            }

            _tgt[0] = sPct; _tgt[1] = wPct; _tgt[2] = mPct;
            _modelName = mName ?? "Model";

            var pal = Pal;
            SetRingColor(ArcA, sPct, pal.A);
            SetRingColor(ArcB, wPct, pal.B);
            SetRingColor(ArcC, mPct, pal.C);
            SetRingColor(ArcMini, sPct, pal.Accent);

            SubA.Text = FormatReset(sRst) ?? "5 hr";
            SubB.Text = FormatReset(wRst) ?? "7 day";
            SubC.Text = FormatReset(mRst) ?? "7 day";
            SubS.Text = SubA.Text;
            SubWk.Text = SubB.Text;
            SubMd.Text = SubC.Text;
            LblC.Text = _modelName;
            LblMd.Text = _modelName;

            Status.Text = "güncellendi " + DateTime.Now.ToString("HH:mm");
            _everOk = true;
            _animTimer.Start();
            _refreshTimer.Interval = TimeSpan.FromSeconds(120);   // basari: normal araliga don
        }
        catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.Unauthorized)
        {
            Status.Text = "token süresi dolmuş — Claude Code'u aç" + FirstDataSuffix();
            _refreshTimer.Interval = TimeSpan.FromSeconds(120);
        }
        catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.TooManyRequests)
        {
            // ustel geri cekilme: 120 -> 240 -> 480 -> 600 (cap)
            double next = Math.Min(Math.Max(_refreshTimer.Interval.TotalSeconds * 2, 240), 600);
            _refreshTimer.Interval = TimeSpan.FromSeconds(next);
            Status.Text = $"limit (429) — {(int)next}sn sonra tekrar" + FirstDataSuffix();
        }
        catch
        {
            // Hata: mevcut deger ve gorunumleri KORU (sifirlama yok)
            Status.Text = "bağlantı yok" + FirstDataSuffix();
            _refreshTimer.Interval = TimeSpan.FromSeconds(120);
        }
    }

    private string FirstDataSuffix() => _everOk ? "" : " (ilk veri bekleniyor)";

    // ---------- JSONL token/maliyet (arka plan is parcacigi) ----------
    private async void StartTokenScan()
    {
        if (_tokenBusy) return;
        _tokenBusy = true;
        try
        {
            string utcDate = DateTime.UtcNow.ToString("yyyy-MM-dd");
            Tokens.Text = await Task.Run(() => ScanTokens(ProjectsDir, utcDate));
        }
        catch { }
        finally { _tokenBusy = false; }
    }

    private static readonly Regex RxIn    = new("\"input_tokens\":(\\d+)", RegexOptions.Compiled);
    private static readonly Regex RxOut   = new("\"output_tokens\":(\\d+)", RegexOptions.Compiled);
    private static readonly Regex RxCc    = new("\"cache_creation_input_tokens\":(\\d+)", RegexOptions.Compiled);
    private static readonly Regex RxCr    = new("\"cache_read_input_tokens\":(\\d+)", RegexOptions.Compiled);
    private static readonly Regex RxModel = new("\"model\":\"([^\"]+)\"", RegexOptions.Compiled);

    private static double MatchNum(Regex rx, string line)
        => rx.Match(line) is { Success: true } m ? double.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture) : 0.0;

    private static string ScanTokens(string dir, string utcDate)
    {
        double tok = 0, cost = 0;
        try
        {
            var opts = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true };
            var cutoff = DateTime.Today.AddDays(-1);
            foreach (var file in Directory.EnumerateFiles(dir, "*.jsonl", opts))
            {
                try
                {
                    if (File.GetLastWriteTime(file) < cutoff) continue;
                    using var fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                    using var sr = new StreamReader(fs);
                    string? line;
                    while ((line = sr.ReadLine()) != null)
                    {
                        if (!line.Contains("\"output_tokens\"") || !line.Contains(utcDate)) continue;
                        double it = MatchNum(RxIn, line), ot = MatchNum(RxOut, line);
                        double cc = MatchNum(RxCc, line), cr = MatchNum(RxCr, line);
                        string model = RxModel.Match(line) is { Success: true } m ? m.Groups[1].Value : "";
                        tok += it + ot + cc + cr;
                        // $/MTok: input, cache-write, cache-read, output (varsayilan: opus sinifi)
                        double pi = 15.0, pw = 18.75, pr = 1.5, po = 75.0;
                        if (model.Contains("sonnet")) { pi = 3.0; pw = 3.75; pr = 0.3; po = 15.0; }
                        else if (model.Contains("haiku")) { pi = 1.0; pw = 1.25; pr = 0.1; po = 5.0; }
                        cost += (it * pi + cc * pw + cr * pr + ot * po) / 1_000_000.0;
                    }
                }
                catch { }
            }
        }
        catch { }
        string tk = tok >= 1_000_000 ? (tok / 1_000_000).ToString("0.0") + "M"
                  : tok >= 1_000     ? (tok / 1_000).ToString("0.0") + "K"
                  : ((int)tok).ToString();
        return $"bugün ~{tk} token  ·  ~${cost:0.00} (API eşdeğeri)";
    }

    // ---------- surukleme + mini'de tikla-ac ----------
    private void OnDragStart(object sender, MouseButtonEventArgs e)
    {
        // etkilesimli ogeler (Tag="ui") ve icindekiler suruklemeyi baslatmaz
        var d = e.OriginalSource as DependencyObject;
        while (d != null && d != this)
        {
            if (d is FrameworkElement fe && (fe.Tag as string) == "ui") return;
            d = VisualTreeHelper.GetParent(d);
        }
        double startL = Left, startT = Top;
        try { DragMove(); } catch { return; }   // DragMove birakilana kadar bloklar
        bool moved = Math.Abs(Left - startL) > 3 || Math.Abs(Top - startT) > 3;
        if (!moved && _minimized)
        {
            _minimized = false;
            UpdateViewVisibility();
        }
    }

    // ekran sinirlari icinde tut (kaybolmasin)
    private void OnLocationChanged(object? sender, EventArgs e)
    {
        if (_clamping) return;
        _clamping = true;
        try
        {
            double vl = SystemParameters.VirtualScreenLeft, vt = SystemParameters.VirtualScreenTop;
            double vw = SystemParameters.VirtualScreenWidth, vh = SystemParameters.VirtualScreenHeight;
            Left = Math.Max(vl, Math.Min(Left, vl + vw - ActualWidth));
            Top = Math.Max(vt, Math.Min(Top, vt + vh - ActualHeight));
        }
        finally { _clamping = false; }
    }
}
