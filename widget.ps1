# Claude Usage Widget - donut halkalar + avatar + kucultme + sparkline + ETA + token/maliyet
# Proje bagimsiz. Token'i ~/.claude/.credentials.json'dan taze okur.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

if (-not ([System.Management.Automation.PSTypeName]'WinCur').Type) {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WinCur {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
}
"@
}

$baseDir    = Join-Path $env:USERPROFILE "claude-usage-widget"

# Tek instance: zaten calisiyorsa, mevcut pencereyi one getir ve bu kopya ciksin
$script:mutex = New-Object System.Threading.Mutex($false, "Local\ClaudeUsageWidgetSingleton")
if (-not $script:mutex.WaitOne(0)) {
  try { ([System.Threading.EventWaitHandle]::OpenExisting("Local\ClaudeUsageWidgetShow")).Set() } catch {}
  exit
}
$script:showEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, "Local\ClaudeUsageWidgetShow")

$credPath   = Join-Path $env:USERPROFILE ".claude\.credentials.json"
$projectsDir= Join-Path $env:USERPROFILE ".claude\projects"
$usageUrl   = "https://api.anthropic.com/api/oauth/usage"
$profileUrl = "https://api.anthropic.com/api/oauth/profile"

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Usage" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ResizeMode="NoResize"
        SizeToContent="WidthAndHeight" ShowInTaskbar="False"
        Left="40" Top="40" Opacity="0.97">
  <Grid>
    <Border x:Name="Full" Margin="18" CornerRadius="20" Width="312" BorderThickness="1">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#FB222634" Offset="0"/>
          <GradientStop Color="#FC181A24" Offset="0.55"/>
          <GradientStop Color="#FD111219" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Border.BorderBrush>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#664C8DFF" Offset="0"/>
          <GradientStop Color="#22FFFFFF" Offset="0.45"/>
          <GradientStop Color="#44B57BFF" Offset="1"/>
        </LinearGradientBrush>
      </Border.BorderBrush>
      <Border.Effect>
        <DropShadowEffect Color="#000000" BlurRadius="32" ShadowDepth="4" Direction="270" Opacity="0.62"/>
      </Border.Effect>
      <Grid>
        <Rectangle RadiusX="19" RadiusY="19" Height="90" VerticalAlignment="Top" Margin="1" IsHitTestVisible="False">
          <Rectangle.Fill>
            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
              <GradientStop Color="#16FFFFFF" Offset="0"/>
              <GradientStop Color="#00FFFFFF" Offset="1"/>
            </LinearGradientBrush>
          </Rectangle.Fill>
        </Rectangle>
        <Border Margin="1" CornerRadius="19" BorderThickness="1" IsHitTestVisible="False">
          <Border.BorderBrush>
            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
              <GradientStop Color="#3AFFFFFF" Offset="0"/>
              <GradientStop Color="#00FFFFFF" Offset="0.35"/>
            </LinearGradientBrush>
          </Border.BorderBrush>
        </Border>
        <StackPanel Margin="18,16,18,14">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Grid Grid.Column="0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Grid Grid.Column="0" Width="36" Height="36" VerticalAlignment="Center">
                <Ellipse>
                  <Ellipse.Fill>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                      <GradientStop Color="#FF4C8DFF" Offset="0"/>
                      <GradientStop Color="#FF7B84FF" Offset="0.5"/>
                      <GradientStop Color="#FFB57BFF" Offset="1"/>
                    </LinearGradientBrush>
                  </Ellipse.Fill>
                  <Ellipse.Effect>
                    <DropShadowEffect Color="#7B84FF" BlurRadius="14" ShadowDepth="0" Opacity="0.55"/>
                  </Ellipse.Effect>
                </Ellipse>
                <Ellipse>
                  <Ellipse.Fill>
                    <RadialGradientBrush GradientOrigin="0.5,0.0" Center="0.5,0.1" RadiusX="0.75" RadiusY="0.75">
                      <GradientStop Color="#55FFFFFF" Offset="0"/>
                      <GradientStop Color="#00FFFFFF" Offset="1"/>
                    </RadialGradientBrush>
                  </Ellipse.Fill>
                </Ellipse>
                <Ellipse Stroke="#48FFFFFF" StrokeThickness="1"/>
                <TextBlock x:Name="Initial" Text="C" Foreground="White" FontSize="16"
                           FontWeight="SemiBold" FontFamily="Segoe UI"
                           HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Grid>
              <StackPanel Grid.Column="1" Margin="10,0,8,0" VerticalAlignment="Center">
                <TextBlock x:Name="UserName" Text="Claude" Foreground="#FFF5F5FA"
                           FontSize="14" FontWeight="SemiBold" FontFamily="Segoe UI"
                           TextTrimming="CharacterEllipsis" TextWrapping="NoWrap"/>
                <Border x:Name="PlanBadge" CornerRadius="7" Padding="7,2,7,2"
                        HorizontalAlignment="Left" Margin="0,4,0,0" BorderThickness="1">
                  <Border.Background>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                      <GradientStop Color="#38B57BFF" Offset="0"/>
                      <GradientStop Color="#2C4C8DFF" Offset="1"/>
                    </LinearGradientBrush>
                  </Border.Background>
                  <Border.BorderBrush>
                    <SolidColorBrush Color="#3CCBB6FF"/>
                  </Border.BorderBrush>
                  <TextBlock x:Name="PlanText" Text="" Foreground="#FFDCCBFF" FontSize="9"
                             FontWeight="Bold" FontFamily="Segoe UI"/>
                </Border>
              </StackPanel>
            </Grid>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top" Margin="6,0,0,0">
              <TextBlock x:Name="MinBtn" Text="&#x2212;" Foreground="#FF9A9AB0" FontSize="15"
                         FontFamily="Segoe UI" Cursor="Hand" Background="Transparent"
                         Padding="4,0,4,4" Margin="0,-3,4,0" ToolTip="Kucult"/>
              <TextBlock x:Name="RefreshBtn" Text="&#x21bb;" Foreground="#FF9A9AB0" FontSize="14"
                         FontFamily="Segoe UI" Cursor="Hand" Background="Transparent"
                         Padding="4,0,4,4" Margin="0,-1,4,0"
                         RenderTransformOrigin="0.5,0.5" ToolTip="Yenile">
                <TextBlock.RenderTransform><RotateTransform x:Name="SpinT" Angle="0"/></TextBlock.RenderTransform>
              </TextBlock>
              <TextBlock x:Name="CloseBtn" Text="&#x2715;" Foreground="#FF9A9AB0" FontSize="12"
                         FontFamily="Segoe UI" Cursor="Hand" Background="Transparent"
                         Padding="4,1,2,4" ToolTip="Kapat"/>
            </StackPanel>
          </Grid>
          <Grid Margin="0,18,0,2">
            <Ellipse IsHitTestVisible="False" Margin="4,-6,4,-2">
              <Ellipse.Fill>
                <RadialGradientBrush>
                  <GradientStop Color="#264C8DFF" Offset="0"/>
                  <GradientStop Color="#12B57BFF" Offset="0.55"/>
                  <GradientStop Color="#00000000" Offset="1"/>
                </RadialGradientBrush>
              </Ellipse.Fill>
            </Ellipse>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0">
                <Grid Width="78" Height="78">
                  <Ellipse Width="52" Height="52" HorizontalAlignment="Center" VerticalAlignment="Center">
                    <Ellipse.Fill>
                      <RadialGradientBrush>
                        <GradientStop Color="#264C8DFF" Offset="0"/>
                        <GradientStop Color="#00000000" Offset="1"/>
                      </RadialGradientBrush>
                    </Ellipse.Fill>
                  </Ellipse>
                  <Ellipse Width="64" Height="64" Stroke="#FF262631" StrokeThickness="6"/>
                  <Path x:Name="ArcA" Stroke="#4C8DFF" StrokeThickness="6" StrokeStartLineCap="Round" StrokeEndLineCap="Round">
                    <Path.Effect><DropShadowEffect Color="#4C8DFF" BlurRadius="11" ShadowDepth="0" Opacity="0.75"/></Path.Effect>
                  </Path>
                  <TextBlock x:Name="PctA" Text="0%" Foreground="#FFF6F6FA" FontSize="15" FontWeight="SemiBold"
                             FontFamily="Segoe UI" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
                <TextBlock x:Name="LblA" Text="Session" Foreground="#FFDBDBE6" FontSize="11" FontWeight="SemiBold" FontFamily="Segoe UI" HorizontalAlignment="Center" Margin="0,7,0,0"/>
                <TextBlock x:Name="SubA" Text="5 hr" Foreground="#FF82829A" FontSize="9" FontFamily="Segoe UI" HorizontalAlignment="Center" Margin="0,2,0,0"/>
              </StackPanel>
              <StackPanel Grid.Column="1">
                <Grid Width="78" Height="78">
                  <Ellipse Width="52" Height="52" HorizontalAlignment="Center" VerticalAlignment="Center">
                    <Ellipse.Fill>
                      <RadialGradientBrush>
                        <GradientStop Color="#26B57BFF" Offset="0"/>
                        <GradientStop Color="#00000000" Offset="1"/>
                      </RadialGradientBrush>
                    </Ellipse.Fill>
                  </Ellipse>
                  <Ellipse Width="64" Height="64" Stroke="#FF262631" StrokeThickness="6"/>
                  <Path x:Name="ArcB" Stroke="#B57BFF" StrokeThickness="6" StrokeStartLineCap="Round" StrokeEndLineCap="Round">
                    <Path.Effect><DropShadowEffect Color="#B57BFF" BlurRadius="11" ShadowDepth="0" Opacity="0.75"/></Path.Effect>
                  </Path>
                  <TextBlock x:Name="PctB" Text="0%" Foreground="#FFF6F6FA" FontSize="15" FontWeight="SemiBold"
                             FontFamily="Segoe UI" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
                <TextBlock x:Name="LblB" Text="Weekly" Foreground="#FFDBDBE6" FontSize="11" FontWeight="SemiBold" FontFamily="Segoe UI" HorizontalAlignment="Center" Margin="0,7,0,0"/>
                <TextBlock x:Name="SubB" Text="7 day" Foreground="#FF82829A" FontSize="9" FontFamily="Segoe UI" HorizontalAlignment="Center" Margin="0,2,0,0"/>
              </StackPanel>
              <StackPanel Grid.Column="2">
                <Grid Width="78" Height="78">
                  <Ellipse Width="52" Height="52" HorizontalAlignment="Center" VerticalAlignment="Center">
                    <Ellipse.Fill>
                      <RadialGradientBrush>
                        <GradientStop Color="#262FD9C5" Offset="0"/>
                        <GradientStop Color="#00000000" Offset="1"/>
                      </RadialGradientBrush>
                    </Ellipse.Fill>
                  </Ellipse>
                  <Ellipse Width="64" Height="64" Stroke="#FF262631" StrokeThickness="6"/>
                  <Path x:Name="ArcC" Stroke="#2FD9C5" StrokeThickness="6" StrokeStartLineCap="Round" StrokeEndLineCap="Round">
                    <Path.Effect><DropShadowEffect Color="#2FD9C5" BlurRadius="11" ShadowDepth="0" Opacity="0.75"/></Path.Effect>
                  </Path>
                  <TextBlock x:Name="PctC" Text="0%" Foreground="#FFF6F6FA" FontSize="15" FontWeight="SemiBold"
                             FontFamily="Segoe UI" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
                <TextBlock x:Name="LblC" Text="Model" Foreground="#FFDBDBE6" FontSize="11" FontWeight="SemiBold" FontFamily="Segoe UI" HorizontalAlignment="Center" Margin="0,7,0,0"/>
                <TextBlock x:Name="SubC" Text="7 day" Foreground="#FF82829A" FontSize="9" FontFamily="Segoe UI" HorizontalAlignment="Center" Margin="0,2,0,0"/>
              </StackPanel>
            </Grid>
          </Grid>
          <Rectangle Height="1" Margin="0,15,0,10">
            <Rectangle.Fill>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                <GradientStop Color="#00FFFFFF" Offset="0"/>
                <GradientStop Color="#2AFFFFFF" Offset="0.5"/>
                <GradientStop Color="#00FFFFFF" Offset="1"/>
              </LinearGradientBrush>
            </Rectangle.Fill>
          </Rectangle>
          <TextBlock x:Name="Tokens" Text="" Foreground="#FF9C9CB2" FontSize="10" FontFamily="Segoe UI"
                     TextTrimming="CharacterEllipsis" TextWrapping="NoWrap"/>
          <TextBlock x:Name="Status" Text="" Foreground="#FF6A6A80" FontSize="9" FontFamily="Segoe UI"
                     HorizontalAlignment="Right" Margin="0,5,0,0"/>
        </StackPanel>
      </Grid>
    </Border>
    <Border x:Name="Mini" Margin="18" Width="84" Height="84" CornerRadius="42"
            Visibility="Collapsed" Cursor="Hand" ToolTip="Ac" BorderThickness="1.5">
      <Border.Background>
        <RadialGradientBrush GradientOrigin="0.5,0.3" Center="0.5,0.4" RadiusX="0.8" RadiusY="0.8">
          <GradientStop Color="#FF2B2F40" Offset="0"/>
          <GradientStop Color="#FF191B26" Offset="0.7"/>
          <GradientStop Color="#FF111219" Offset="1"/>
        </RadialGradientBrush>
      </Border.Background>
      <Border.BorderBrush>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#B45C9CFF" Offset="0"/>
          <GradientStop Color="#33FFFFFF" Offset="0.5"/>
          <GradientStop Color="#66B57BFF" Offset="1"/>
        </LinearGradientBrush>
      </Border.BorderBrush>
      <Border.Effect><DropShadowEffect Color="#4C8DFF" BlurRadius="28" ShadowDepth="0" Opacity="0.6"/></Border.Effect>
      <Grid>
        <Ellipse Width="46" Height="46" HorizontalAlignment="Center" VerticalAlignment="Center">
          <Ellipse.Fill>
            <RadialGradientBrush>
              <GradientStop Color="#304C8DFF" Offset="0"/>
              <GradientStop Color="#00000000" Offset="1"/>
            </RadialGradientBrush>
          </Ellipse.Fill>
        </Ellipse>
        <Ellipse Width="62" Height="62" Stroke="#FF2B2B38" StrokeThickness="7"/>
        <Path x:Name="ArcMini" Stroke="#FF5C9CFF" StrokeThickness="7" StrokeStartLineCap="Round" StrokeEndLineCap="Round">
          <Path.Effect><DropShadowEffect Color="#5C9CFF" BlurRadius="13" ShadowDepth="0" Opacity="0.85"/></Path.Effect>
        </Path>
        <TextBlock x:Name="PctMini" Text="0%" Foreground="#FFFFFFFF" FontSize="18" FontWeight="Bold"
                   FontFamily="Segoe UI" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)

$ctrl = @{}
foreach ($n in 'Full','Mini','Initial','UserName','PlanText','PlanBadge','MinBtn','RefreshBtn','CloseBtn','SpinT',
               'ArcA','ArcB','ArcC','PctA','PctB','PctC','ArcMini','PctMini',
               'LblA','SubA','LblB','SubB','LblC','SubC','Status','Tokens') {
  $ctrl[$n] = $win.FindName($n)
}

$script:cur  = @{ A=0.0; B=0.0; C=0.0 }
$script:tgt  = @{ A=0.0; B=0.0; C=0.0 }
$script:everOk = $false

# ---------- halka cizimi ----------
function Get-ArcGeometry([double]$pct, [double]$cx, [double]$cy, [double]$r) {
  if ($pct -le 0) { return $null }
  if ($pct -ge 99.99) { return New-Object System.Windows.Media.EllipseGeometry((New-Object System.Windows.Point($cx,$cy)), $r, $r) }
  $startA = -90.0 * [math]::PI / 180.0
  $sweep  = 3.6 * $pct
  $endA   = (-90.0 + $sweep) * [math]::PI / 180.0
  $sp = New-Object System.Windows.Point(($cx + $r*[math]::Cos($startA)), ($cy + $r*[math]::Sin($startA)))
  $ep = New-Object System.Windows.Point(($cx + $r*[math]::Cos($endA)),   ($cy + $r*[math]::Sin($endA)))
  $fig = New-Object System.Windows.Media.PathFigure
  $fig.StartPoint = $sp; $fig.IsClosed = $false
  $arc = New-Object System.Windows.Media.ArcSegment
  $arc.Point = $ep
  $arc.Size = New-Object System.Windows.Size($r, $r)
  $arc.SweepDirection = [System.Windows.Media.SweepDirection]::Clockwise
  $arc.IsLargeArc = ($sweep -gt 180)
  $fig.Segments.Add($arc)
  $geo = New-Object System.Windows.Media.PathGeometry
  $geo.Figures.Add($fig)
  return $geo
}

function Draw-Rings {
  foreach ($k in 'A','B','C') {
    $ctrl["Arc$k"].Data = Get-ArcGeometry $script:cur[$k] 39 39 32
    $ctrl["Pct$k"].Text = ("{0:0}%" -f $script:cur[$k])
  }
  $ctrl.ArcMini.Data = Get-ArcGeometry $script:cur['A'] 42 42 31
  $ctrl.PctMini.Text = ("{0:0}%" -f $script:cur['A'])
}

# halka rengi: normalde kimlik rengi, yuksek kullanimda sari (>=75) / kirmizi (>=90)
function Set-RingColor([string]$k, [double]$pct, [string]$base) {
  $hex = if ($pct -ge 90) { '#FFFF5C6B' } elseif ($pct -ge 75) { '#FFFFB454' } else { $base }
  $c = [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($hex)
  $ctrl["Arc$k"].Stroke = New-Object System.Windows.Media.SolidColorBrush($c)
  if ($ctrl["Arc$k"].Effect) { $ctrl["Arc$k"].Effect.Color = $c }
}

# ---------- API ----------
function Get-Token { (Get-Content $credPath -Raw | ConvertFrom-Json).claudeAiOauth.accessToken }
function Get-Headers { @{ 'Authorization'="Bearer $(Get-Token)"; 'anthropic-beta'='oauth-2025-04-20'; 'Content-Type'='application/json' } }

function Format-Reset($iso) {
  if ([string]::IsNullOrEmpty($iso)) { return $null }
  try {
    $span = [datetimeoffset]::Parse($iso) - [datetimeoffset]::Now
    if ($span.TotalSeconds -le 0) { return "now" }
    if ($span.TotalDays  -ge 1) { return ("{0}d {1}h" -f [int]$span.TotalDays, $span.Hours) }
    if ($span.TotalHours -ge 1) { return ("{0}h {1}m" -f [int]$span.TotalHours, $span.Minutes) }
    return ("{0}m" -f [int]$span.TotalMinutes)
  } catch { return $null }
}

function Load-Profile {
  try {
    $p = Invoke-RestMethod -Uri $profileUrl -Headers (Get-Headers) -Method Get -TimeoutSec 15
    $name = if ($p.account.display_name) { $p.account.display_name } elseif ($p.account.full_name) { $p.account.full_name } else { "Claude" }
    $ctrl.UserName.Text = $name
    $ctrl.Initial.Text  = ($name.Substring(0,1)).ToUpper()
    $tier = $p.organization.rate_limit_tier
    if     ($tier -match 'max_(\d+)x') { $ctrl.PlanText.Text = "MAX $($matches[1])x" }
    elseif ($p.account.has_claude_max) { $ctrl.PlanText.Text = "MAX" }
    elseif ($p.account.has_claude_pro) { $ctrl.PlanText.Text = "PRO" }
    else   { $ctrl.PlanText.Text = "CLAUDE" }
  } catch { $ctrl.PlanBadge.Visibility = 'Collapsed' }
}

function Update-Usage {
  $spin = New-Object System.Windows.Media.Animation.DoubleAnimation(0, 360, ([timespan]::FromMilliseconds(600)))
  $ctrl.SpinT.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $spin)
  try {
    $r = Invoke-RestMethod -Uri $usageUrl -Headers (Get-Headers) -Method Get -TimeoutSec 15

    # ---- yeni 'limits' dizisi: session / weekly_all / weekly_scoped(model) ----
    $sPct=0.0; $sRst=$null
    $wPct=0.0; $wRst=$null
    $mPct=0.0; $mRst=$null; $mName=$null; $mSeen=$false

    if ($r.limits) {
      foreach ($l in $r.limits) {
        $p = [double]$l.percent
        switch ($l.kind) {
          'session'    { $sPct=$p; $sRst=$l.resets_at }
          'weekly_all' { $wPct=$p; $wRst=$l.resets_at }
          'weekly_scoped' {
            # birden fazla modele-ozel limit gelirse en yuksek kullanimliyi goster
            if (-not $mSeen -or $p -ge $mPct) {
              $mPct=$p; $mRst=$l.resets_at; $mSeen=$true
              if ($l.scope.model.display_name) { $mName=$l.scope.model.display_name }
            }
          }
        }
      }
    } else {
      # eski API alanlarina geri donus
      $sPct=[double]$r.five_hour.utilization; $sRst=$r.five_hour.resets_at
      $wPct=[double]$r.seven_day.utilization;  $wRst=$r.seven_day.resets_at
    }
    if (-not $mSeen) {
      if     ($r.seven_day_opus)   { $mPct=[double]$r.seven_day_opus.utilization;   $mRst=$r.seven_day_opus.resets_at;   $mName='Opus' }
      elseif ($r.seven_day_sonnet) { $mPct=[double]$r.seven_day_sonnet.utilization; $mRst=$r.seven_day_sonnet.resets_at; $mName='Sonnet' }
    }

    $script:tgt.A=$sPct; $script:tgt.B=$wPct; $script:tgt.C=$mPct

    Set-RingColor 'A'    $sPct '#FF4C8DFF'
    Set-RingColor 'B'    $wPct '#FFB57BFF'
    Set-RingColor 'C'    $mPct '#FF2FD9C5'
    Set-RingColor 'Mini' $sPct '#FF5C9CFF'

    $ra=Format-Reset $sRst; $ctrl.SubA.Text = if ($ra) { $ra } else { '5 hr' }
    $rb=Format-Reset $wRst; $ctrl.SubB.Text = if ($rb) { $rb } else { '7 day' }
    $rc=Format-Reset $mRst; $ctrl.SubC.Text = if ($rc) { $rc } else { '7 day' }
    $ctrl.LblC.Text = if ($mName) { $mName } else { 'Model' }

    $ctrl.Status.Text = "updated " + (Get-Date -Format "HH:mm")
    $script:everOk = $true
    $script:animTimer.Start()
    if ($refreshTimer) { $refreshTimer.Interval = [TimeSpan]::FromSeconds(120) }   # basari: normal araliga don
  } catch {
    # Hata: mevcut halka degerlerini KORU (sifirlama)
    $msg = $_.Exception.Message
    if     ($msg -match '401') { $ctrl.Status.Text = "token expired - open Claude Code"; if ($refreshTimer) { $refreshTimer.Interval = [TimeSpan]::FromSeconds(120) } }
    elseif ($msg -match '429') {
      # ust el geri cekilme: 120 -> 240 -> 480 -> 600 (cap)
      $cur = if ($refreshTimer) { $refreshTimer.Interval.TotalSeconds } else { 120 }
      $next = [math]::Min([math]::Max($cur * 2, 240), 600)
      if ($refreshTimer) { $refreshTimer.Interval = [TimeSpan]::FromSeconds($next) }
      $ctrl.Status.Text = "limit (429) - $([int]$next)sn sonra tekrar"
    }
    else { $ctrl.Status.Text = "baglanti yok"; if ($refreshTimer) { $refreshTimer.Interval = [TimeSpan]::FromSeconds(120) } }
    if (-not $script:everOk) { $ctrl.Status.Text += " (ilk veri bekleniyor)" }
  }
}

# ---------- JSONL token/maliyet (arka plan runspace) ----------
$tokenScript = {
  param($dir, $utcDate)
  $tok = 0.0; $cost = 0.0
  try {
    $files = Get-ChildItem -LiteralPath $dir -Recurse -Filter *.jsonl -File -ErrorAction SilentlyContinue |
             Where-Object { $_.LastWriteTime -ge [datetime]::Today.AddDays(-1) }
    foreach ($f in $files) {
      foreach ($line in [System.IO.File]::ReadLines($f.FullName)) {
        if ($line.IndexOf('"output_tokens"') -lt 0) { continue }
        if ($line.IndexOf($utcDate) -lt 0) { continue }
        $it=0.0;$ot=0.0;$cc=0.0;$cr=0.0
        if ($line -match '"input_tokens":(\d+)')                 { $it=[double]$matches[1] }
        if ($line -match '"output_tokens":(\d+)')                { $ot=[double]$matches[1] }
        if ($line -match '"cache_creation_input_tokens":(\d+)')  { $cc=[double]$matches[1] }
        if ($line -match '"cache_read_input_tokens":(\d+)')      { $cr=[double]$matches[1] }
        $m=''; if ($line -match '"model":"([^"]+)"') { $m=$matches[1] }
        $tok += $it + $ot + $cc + $cr
        $pi=15.0;$pw=18.75;$pr=1.5;$po=75.0
        if     ($m -like '*sonnet*') { $pi=3.0;$pw=3.75;$pr=0.3;$po=15.0 }
        elseif ($m -like '*haiku*')  { $pi=1.0;$pw=1.25;$pr=0.1;$po=5.0 }
        $cost += ($it*$pi + $cc*$pw + $cr*$pr + $ot*$po) / 1000000.0
      }
    }
  } catch {}
  $tk = if ($tok -ge 1000000) { '{0:0.0}M' -f ($tok/1000000) } elseif ($tok -ge 1000) { '{0:0.0}K' -f ($tok/1000) } else { [string][int]$tok }
  [pscustomobject]@{ text = ("bugun ~$tk token  -  ~`$" + ('{0:0.00}' -f $cost) + " (API esdegeri)") }
}

$script:tokPS = $null; $script:tokHandle = $null; $script:tokenBusy = $false
function Start-TokenScan {
  if ($script:tokenBusy) { return }
  $script:tokenBusy = $true
  $script:tokPS = [PowerShell]::Create()
  [void]$script:tokPS.AddScript($tokenScript.ToString()).AddArgument($projectsDir).AddArgument(((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')))
  $script:tokHandle = $script:tokPS.BeginInvoke()
}

$tokPoll = New-Object System.Windows.Threading.DispatcherTimer
$tokPoll.Interval = [TimeSpan]::FromSeconds(1)
$tokPoll.Add_Tick({
  if ($script:tokHandle -and $script:tokHandle.IsCompleted) {
    try { $res = $script:tokPS.EndInvoke($script:tokHandle); $o = $res | Select-Object -Last 1; if ($o) { $ctrl.Tokens.Text = $o.text } } catch {}
    if ($script:tokPS) { $script:tokPS.Dispose() }
    $script:tokPS = $null; $script:tokHandle = $null; $script:tokenBusy = $false
  }
})
$tokPoll.Start()

$tokScanTimer = New-Object System.Windows.Threading.DispatcherTimer
$tokScanTimer.Interval = [TimeSpan]::FromSeconds(180)
$tokScanTimer.Add_Tick({ Start-TokenScan })
$tokScanTimer.Start()

# ---------- animasyon ----------
$script:animTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:animTimer.Interval = [TimeSpan]::FromMilliseconds(16)
$script:animTimer.Add_Tick({
  $done = $true
  foreach ($k in 'A','B','C') {
    $c = $script:cur[$k]; $t = $script:tgt[$k]; $d = $t - $c
    if ([math]::Abs($d) -lt 0.15) { $script:cur[$k] = $t } else { $script:cur[$k] = $c + $d * 0.16; $done = $false }
  }
  Draw-Rings
  if ($done) { $script:animTimer.Stop() }
})

# ---------- buton aksiyonlari ----------
$ctrl.MinBtn.Add_MouseLeftButtonUp({ $ctrl.Full.Visibility = 'Collapsed'; $ctrl.Mini.Visibility = 'Visible' })
$ctrl.CloseBtn.Add_MouseLeftButtonUp({ $win.Close() })
$ctrl.RefreshBtn.Add_MouseLeftButtonUp({ $ctrl.Status.Text = "refreshing..."; Update-Usage; Start-TokenScan; $refreshTimer.Stop(); $refreshTimer.Start() })

# ---------- manuel surukleme + mini'de tikla-ac ----------
$script:drag = $false; $script:dragMoved = $false; $script:dpi = 1.0
$win.Add_PreviewMouseLeftButtonDown({
  $src = $args[1].OriginalSource
  if ($src -eq $ctrl.MinBtn -or $src -eq $ctrl.RefreshBtn -or $src -eq $ctrl.CloseBtn) { return }
  $pt = New-Object WinCur+POINT; [void][WinCur]::GetCursorPos([ref]$pt)
  $script:dragStartX = $pt.X; $script:dragStartY = $pt.Y
  $script:winStartLeft = $win.Left; $script:winStartTop = $win.Top
  $script:dragMoved = $false; $script:drag = $true
  $ps = [System.Windows.PresentationSource]::FromVisual($win)
  if ($ps) { $script:dpi = $ps.CompositionTarget.TransformToDevice.M11 } else { $script:dpi = 1.0 }
  [void]$win.CaptureMouse()
})
$win.Add_MouseMove({
  if (-not $script:drag) { return }
  if ($args[1].LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) { return }
  $pt = New-Object WinCur+POINT; [void][WinCur]::GetCursorPos([ref]$pt)
  $ddx = $pt.X - $script:dragStartX; $ddy = $pt.Y - $script:dragStartY
  if ([math]::Abs($ddx) -gt 3 -or [math]::Abs($ddy) -gt 3) { $script:dragMoved = $true }
  $nl = $script:winStartLeft + ($ddx / $script:dpi)
  $nt = $script:winStartTop  + ($ddy / $script:dpi)
  # ekran sinirlari icinde tut (kaybolmasin)
  $vsL = [System.Windows.SystemParameters]::VirtualScreenLeft
  $vsT = [System.Windows.SystemParameters]::VirtualScreenTop
  $vsW = [System.Windows.SystemParameters]::VirtualScreenWidth
  $vsH = [System.Windows.SystemParameters]::VirtualScreenHeight
  $w = $win.ActualWidth; $h = $win.ActualHeight
  $nl = [math]::Max($vsL, [math]::Min($nl, $vsL + $vsW - $w))
  $nt = [math]::Max($vsT, [math]::Min($nt, $vsT + $vsH - $h))
  $win.Left = $nl; $win.Top = $nt
})
$win.Add_MouseLeftButtonUp({
  if (-not $script:drag) { return }
  $script:drag = $false; $win.ReleaseMouseCapture()
  if ($ctrl.Mini.Visibility -eq 'Visible' -and -not $script:dragMoved) {
    $ctrl.Mini.Visibility = 'Collapsed'; $ctrl.Full.Visibility = 'Visible'
  }
})

$win.Add_MouseEnter({ try { $a = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, ([timespan]::FromMilliseconds(150))); $win.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a) } catch {} })
$win.Add_MouseLeave({ try { $a = New-Object System.Windows.Media.Animation.DoubleAnimation(0.97, ([timespan]::FromMilliseconds(200))); $win.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a) } catch {} })

$win.Add_Loaded({
  Load-Profile
  Update-Usage
  Start-TokenScan
})

$refreshTimer = New-Object System.Windows.Threading.DispatcherTimer
$refreshTimer.Interval = [TimeSpan]::FromSeconds(120)
$refreshTimer.Add_Tick({ Update-Usage })
$refreshTimer.Start()

# ikinci kez baslatildiginda mevcut pencereyi one getir + gorunur konuma al
$showTimer = New-Object System.Windows.Threading.DispatcherTimer
$showTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$showTimer.Add_Tick({
  if ($script:showEvent -and $script:showEvent.WaitOne(0)) {
    $ctrl.Mini.Visibility = 'Collapsed'; $ctrl.Full.Visibility = 'Visible'
    $win.Left = 40; $win.Top = 40
    $win.Topmost = $false; $win.Topmost = $true
    [void]$win.Activate()
  }
})
$showTimer.Start()

[void]$win.ShowDialog()
