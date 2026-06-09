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

# Tek instance: zaten calisiyorsa cik
$script:mutex = New-Object System.Threading.Mutex($false, "Local\ClaudeUsageWidgetSingleton")
if (-not $script:mutex.WaitOne(0)) { exit }

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
        Left="40" Top="40" Opacity="0.93">
  <Grid>

    <!-- ================= TAM PANEL ================= -->
    <Border x:Name="Full" Margin="16" CornerRadius="18" Width="300">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#FA242430" Offset="0"/>
          <GradientStop Color="#FA15151C" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Border.BorderBrush>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#553A7BFF" Offset="0"/>
          <GradientStop Color="#22FFFFFF" Offset="1"/>
        </LinearGradientBrush>
      </Border.BorderBrush>
      <Border.BorderThickness>1</Border.BorderThickness>
      <Border.Effect>
        <DropShadowEffect Color="#000000" BlurRadius="24" ShadowDepth="0" Opacity="0.55"/>
      </Border.Effect>

      <StackPanel Margin="16,14,16,14">

        <Grid>
          <StackPanel Orientation="Horizontal">
            <Grid Width="34" Height="34" VerticalAlignment="Center">
              <Ellipse>
                <Ellipse.Fill>
                  <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                    <GradientStop Color="#FF4C8DFF" Offset="0"/>
                    <GradientStop Color="#FFB57BFF" Offset="1"/>
                  </LinearGradientBrush>
                </Ellipse.Fill>
              </Ellipse>
              <TextBlock x:Name="Initial" Text="C" Foreground="White" FontSize="16"
                         FontWeight="SemiBold" FontFamily="Segoe UI"
                         HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
              <TextBlock x:Name="UserName" Text="Claude" Foreground="#FFF2F2F6"
                         FontSize="14" FontWeight="SemiBold" FontFamily="Segoe UI"/>
              <Border x:Name="PlanBadge" Background="#33B57BFF" CornerRadius="4"
                      Padding="6,1,6,1" HorizontalAlignment="Left" Margin="0,3,0,0">
                <TextBlock x:Name="PlanText" Text="" Foreground="#FFCBB6FF" FontSize="9"
                           FontWeight="Bold" FontFamily="Segoe UI"/>
              </Border>
            </StackPanel>
          </StackPanel>

          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
            <TextBlock x:Name="MinBtn" Text="&#x2212;" Foreground="#FF9A9AA6" FontSize="16"
                       FontFamily="Segoe UI" Cursor="Hand" Margin="0,-3,12,0" ToolTip="Kucult"/>
            <TextBlock x:Name="RefreshBtn" Text="&#x21bb;" Foreground="#FF9A9AA6" FontSize="16"
                       FontFamily="Segoe UI" Cursor="Hand" Margin="0,0,12,0"
                       RenderTransformOrigin="0.5,0.5" ToolTip="Yenile">
              <TextBlock.RenderTransform><RotateTransform x:Name="SpinT" Angle="0"/></TextBlock.RenderTransform>
            </TextBlock>
            <TextBlock x:Name="CloseBtn" Text="&#x2715;" Foreground="#FF9A9AA6" FontSize="13"
                       FontFamily="Segoe UI" Cursor="Hand" ToolTip="Kapat"/>
          </StackPanel>
        </Grid>

        <Grid Margin="0,18,0,4">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>

          <StackPanel Grid.Column="0">
            <Grid Width="78" Height="78">
              <Ellipse Width="64" Height="64" Stroke="#FF2C2C36" StrokeThickness="7"/>
              <Path x:Name="ArcA" Stroke="#FF4C8DFF" StrokeThickness="7" StrokeStartLineCap="Round" StrokeEndLineCap="Round">
                <Path.Effect><DropShadowEffect Color="#4C8DFF" BlurRadius="9" ShadowDepth="0" Opacity="0.7"/></Path.Effect>
              </Path>
              <TextBlock x:Name="PctA" Text="0%" Foreground="#FFF2F2F6" FontSize="16" FontWeight="SemiBold"
                         FontFamily="Segoe UI" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <TextBlock Text="Session" Foreground="#FFAFAFBA" FontSize="10" FontFamily="Segoe UI" HorizontalAlignment="Center" Margin="0,4,0,0"/>
            <TextBlock Text="5 hr" Foreground="#FF74747E" FontSize="9" FontFamily="Segoe UI" HorizontalAlignment="Center"/>
          </StackPanel>

          <StackPanel Grid.Column="1">
            <Grid Width="78" Height="78">
              <Ellipse Width="64" Height="64" Stroke="#FF2C2C36" StrokeThickness="7"/>
              <Path x:Name="ArcB" Stroke="#FFB57BFF" StrokeThickness="7" StrokeStartLineCap="Round" StrokeEndLineCap="Round">
                <Path.Effect><DropShadowEffect Color="#B57BFF" BlurRadius="9" ShadowDepth="0" Opacity="0.7"/></Path.Effect>
              </Path>
              <TextBlock x:Name="PctB" Text="0%" Foreground="#FFF2F2F6" FontSize="16" FontWeight="SemiBold"
                         FontFamily="Segoe UI" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <TextBlock Text="Weekly" Foreground="#FFAFAFBA" FontSize="10" FontFamily="Segoe UI" HorizontalAlignment="Center" Margin="0,4,0,0"/>
            <TextBlock Text="7 day" Foreground="#FF74747E" FontSize="9" FontFamily="Segoe UI" HorizontalAlignment="Center"/>
          </StackPanel>

          <StackPanel Grid.Column="2">
            <Grid Width="78" Height="78">
              <Ellipse Width="64" Height="64" Stroke="#FF2C2C36" StrokeThickness="7"/>
              <Path x:Name="ArcC" Stroke="#FF2FD9C5" StrokeThickness="7" StrokeStartLineCap="Round" StrokeEndLineCap="Round">
                <Path.Effect><DropShadowEffect Color="#2FD9C5" BlurRadius="9" ShadowDepth="0" Opacity="0.7"/></Path.Effect>
              </Path>
              <TextBlock x:Name="PctC" Text="0%" Foreground="#FFF2F2F6" FontSize="16" FontWeight="SemiBold"
                         FontFamily="Segoe UI" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <TextBlock Text="Sonnet" Foreground="#FFAFAFBA" FontSize="10" FontFamily="Segoe UI" HorizontalAlignment="Center" Margin="0,4,0,0"/>
            <TextBlock Text="7 day" Foreground="#FF74747E" FontSize="9" FontFamily="Segoe UI" HorizontalAlignment="Center"/>
          </StackPanel>
        </Grid>

        <Border Height="1" Background="#22FFFFFF" Margin="0,16,0,8"/>

        <Grid>
          <TextBlock x:Name="Resets" Text="" Foreground="#FF8A8A94" FontSize="10" FontFamily="Segoe UI" HorizontalAlignment="Left"/>
          <TextBlock x:Name="Status" Text="" Foreground="#FF6E6E78" FontSize="10" FontFamily="Segoe UI" HorizontalAlignment="Right"/>
        </Grid>
        <TextBlock x:Name="Tokens" Text="" Foreground="#FF6E6E78" FontSize="10" FontFamily="Segoe UI" Margin="0,3,0,0"/>
      </StackPanel>
    </Border>

    <!-- ================= KUCULTULMUS YUVARLAK ================= -->
    <Border x:Name="Mini" Margin="16" Width="66" Height="66" CornerRadius="33" Visibility="Collapsed" Cursor="Hand" ToolTip="Ac">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#FA242430" Offset="0"/>
          <GradientStop Color="#FA15151C" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Border.BorderBrush>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#553A7BFF" Offset="0"/>
          <GradientStop Color="#22FFFFFF" Offset="1"/>
        </LinearGradientBrush>
      </Border.BorderBrush>
      <Border.BorderThickness>1</Border.BorderThickness>
      <Border.Effect><DropShadowEffect Color="#000000" BlurRadius="20" ShadowDepth="0" Opacity="0.55"/></Border.Effect>
      <Grid>
        <Ellipse Width="48" Height="48" Stroke="#FF2C2C36" StrokeThickness="6"/>
        <Path x:Name="ArcMini" Stroke="#FF4C8DFF" StrokeThickness="6" StrokeStartLineCap="Round" StrokeEndLineCap="Round">
          <Path.Effect><DropShadowEffect Color="#4C8DFF" BlurRadius="8" ShadowDepth="0" Opacity="0.75"/></Path.Effect>
        </Path>
        <TextBlock x:Name="PctMini" Text="0%" Foreground="#FFF2F2F6" FontSize="14" FontWeight="SemiBold"
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
               'Resets','Status','Tokens') {
  $ctrl[$n] = $win.FindName($n)
}

$script:cur  = @{ A=0.0; B=0.0; C=0.0 }
$script:tgt  = @{ A=0.0; B=0.0; C=0.0 }

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
  $ctrl.ArcMini.Data = Get-ArcGeometry $script:cur['A'] 33 33 25
  $ctrl.PctMini.Text = ("{0:0}%" -f $script:cur['A'])
}

# ---------- API ----------
function Get-Token { (Get-Content $credPath -Raw | ConvertFrom-Json).claudeAiOauth.accessToken }
function Get-Headers { @{ 'Authorization'="Bearer $(Get-Token)"; 'anthropic-beta'='oauth-2025-04-20'; 'Content-Type'='application/json' } }

function Format-Reset($iso) {
  if ([string]::IsNullOrEmpty($iso)) { return $null }
  try {
    $span = [datetimeoffset]::Parse($iso) - [datetimeoffset]::Now
    if ($span.TotalSeconds -le 0) { return "now" }
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
    $script:tgt.A = [double]$r.five_hour.utilization
    $script:tgt.B = [double]$r.seven_day.utilization
    $script:tgt.C = if ($r.seven_day_sonnet) { [double]$r.seven_day_sonnet.utilization } else { 0.0 }
    $r5 = Format-Reset $r.five_hour.resets_at
    $r7 = Format-Reset $r.seven_day.resets_at
    $parts = @()
    if ($r5) { $parts += "5h: $r5" }
    if ($r7) { $parts += "7d: $r7" }
    $ctrl.Resets.Text = ($parts -join "   ")
    $ctrl.Status.Text = "updated " + (Get-Date -Format "HH:mm")
    $script:animTimer.Start()
  } catch {
    if ($_.Exception.Message -match '401') { $ctrl.Status.Text = "token expired - open Claude Code" }
    else { $ctrl.Status.Text = "offline" }
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
  $win.Left = $script:winStartLeft + ($ddx / $script:dpi)
  $win.Top  = $script:winStartTop  + ($ddy / $script:dpi)
})
$win.Add_MouseLeftButtonUp({
  if (-not $script:drag) { return }
  $script:drag = $false; $win.ReleaseMouseCapture()
  if ($ctrl.Mini.Visibility -eq 'Visible' -and -not $script:dragMoved) {
    $ctrl.Mini.Visibility = 'Collapsed'; $ctrl.Full.Visibility = 'Visible'
  }
})

$win.Add_MouseEnter({ try { $a = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, ([timespan]::FromMilliseconds(150))); $win.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a) } catch {} })
$win.Add_MouseLeave({ try { $a = New-Object System.Windows.Media.Animation.DoubleAnimation(0.93, ([timespan]::FromMilliseconds(200))); $win.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a) } catch {} })

$win.Add_Loaded({
  Load-Profile
  Update-Usage
  Start-TokenScan
})

$refreshTimer = New-Object System.Windows.Threading.DispatcherTimer
$refreshTimer.Interval = [TimeSpan]::FromSeconds(60)
$refreshTimer.Add_Tick({ Update-Usage })
$refreshTimer.Start()

[void]$win.ShowDialog()
