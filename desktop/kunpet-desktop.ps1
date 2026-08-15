# =============================================================================
# Kun Like 桌宠 · 系统级悬浮窗（Windows WPF 透明置顶窗口）
# 由 DSH 宿主插件自动拉起；参数由宿主传入。
# 功能：精灵图动画、Agent 状态联动、拖动、点击互动语音、右键退出。
# 诊断：全程写入 D:\KUN_pet\kunpet-desktop.log
# =============================================================================
param(
  [string]$StateUrl = 'http://127.0.0.1:3080/kun-pet/state',
  [string]$SpriteUrl = 'http://127.0.0.1:3080/kun-pet/spritesheet.webp',
  [string]$SpritePath = 'D:\harness-UI\kun-like-pet\assets\spritesheet.webp',
  [string]$VoicePath = 'D:\harness-UI\kun-like-pet\assets\voice.mp3',
  [string]$PidFile = 'D:\KUN_pet\kunpet-desktop.pid'
)

$LogFile = 'D:\KUN_pet\kunpet-desktop.log'
$ErrorActionPreference = 'Stop'

function Log([string]$msg) {
  try { Add-Content -Path $LogFile -Value ('[' + (Get-Date -Format 'HH:mm:ss.fff') + '] ' + $msg) -Encoding UTF8 } catch { }
}

Set-Content -Path $LogFile -Value ('Kun Like desktop pet log - started') -Encoding UTF8
Log ('START pid=' + $PID)

# ---------- 单实例保护 ----------
if (Test-Path $PidFile) {
  $old = Get-Content $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($old -match '^\d+$') {
    $p = Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue
    if ($p -and ($p.ProcessName -match 'powershell')) {
      Log ('GUARD: another instance (pid ' + $old + ') is running, exiting')
      exit 0
    }
  }
  Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
  Log 'GUARD: stale pid file removed'
}
[System.IO.File]::WriteAllText($PidFile, [string]$PID, (New-Object System.Text.UTF8Encoding($false)))
Log 'PID file written'

$cleaned = $false
function Remove-PidFile {
  if (-not $cleaned) {
    $cleaned = $true
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
  }
}

try {
  Add-Type -AssemblyName PresentationFramework
  Add-Type -AssemblyName PresentationCore
  Add-Type -AssemblyName WindowsBase
  Log 'WPF assemblies loaded'

  # ---------- 尺寸与契约 ----------
  $CW = 192.0
  $CH = 208.0
  $SCALE = 0.85
  $W = $CW * $SCALE
  $H = $CH * $SCALE
  $WIN_W = 260.0
  $BUBBLE_H = 46.0
  $WIN_H = $H + $BUBBLE_H

  $ROWS = @{
    'idle'     = @{ row = 0; frames = @(280, 110, 110, 140, 140, 320) }
    'runRight' = @{ row = 1; frames = @(120, 120, 120, 120, 120, 120, 120, 220) }
    'runLeft'  = @{ row = 2; frames = @(120, 120, 120, 120, 120, 120, 120, 220) }
    'wave'     = @{ row = 3; frames = @(140, 140, 140, 280) }
    'jump'     = @{ row = 4; frames = @(140, 140, 140, 140, 280) }
    'failed'   = @{ row = 5; frames = @(140, 140, 140, 140, 140, 140, 140, 240) }
    'waiting'  = @{ row = 6; frames = @(150, 150, 150, 150, 150, 260) }
    'working'  = @{ row = 7; frames = @(120, 120, 120, 120, 120, 220) }
    'review'   = @{ row = 8; frames = @(150, 150, 150, 150, 150, 280) }
  }
  $MODE_ANIM = @{
    'idle' = 'idle'; 'working' = 'working'; 'review' = 'review'
    'waiting' = 'waiting'; 'failed' = 'failed'; 'celebrating' = 'wave'
  }
  $BUBBLES = @{
    'idle' = '休息中~ 有事叫我'
    'working' = '努力工作中…'
    'review' = '思考中…'
    'waiting' = '在等你回复哦~'
    'failed' = '呜…出错了 (._.)'
    'celebrating' = '完成啦！你干嘛~哎哟'
    'dragging' = '呜哇~ 别拽我！'
    'poke' = '诶嘿~'
  }

  # ---------- 状态 ----------
  $script:mode = 'idle'
  $script:lastSeq = -1
  $script:stateLogged = $false
  $script:celebrateAnim = 'wave'
  $script:dragging = $false
  $script:dragDir = 'runRight'
  $script:reaction = $null
  $script:reactionUntil = [DateTime]::MinValue
  $script:animName = ''
  $script:frameIndex = 0
  $script:frameAcc = 0.0
  $script:appliedRow = -1
  $script:voiceCheckAt = [DateTime]::MinValue
  $script:voiceChecked = $true

  function Set-Anim([string]$name) {
    if ($script:animName -eq $name) { return }
    # 跑步左右行是同一套动作的镜像：切换时保留当前帧，避免画面跳闪
    $isRun = ($name -eq 'runRight' -or $name -eq 'runLeft')
    $wasRun = ($script:animName -eq 'runRight' -or $script:animName -eq 'runLeft')
    $script:animName = $name
    if (-not ($isRun -and $wasRun)) {
      $script:frameIndex = 0
      $script:frameAcc = 0.0
    }
  }

  # ---------- 语音（WMP COM 优先，失败则回退 MCI；均记录日志） ----------
  $script:wmp = $null
  $script:mciType = $null
  function Start-Voice {
    try {
      if ($null -eq $script:wmp) {
        $script:wmp = New-Object -ComObject WMPlayer.OCX
        $script:wmp.settings.volume = 100
      }
      $script:wmp.URL = $VoicePath
      $script:wmp.controls.play() | Out-Null
      $script:voiceCheckAt = [DateTime]::Now.AddMilliseconds(900)
      $script:voiceChecked = $false
      Log 'voice: WMP play started'
      return
    } catch {
      Log ('voice: WMP failed: ' + $_.Exception.Message)
    }
    try {
      if ($null -eq $script:mciType) {
        $sig = '[DllImport("winmm.dll", CharSet = CharSet.Unicode)] public static extern int mciSendStringW(string cmd, System.Text.StringBuilder ret, int retLen, System.IntPtr hwnd);'
        $script:mciType = Add-Type -MemberDefinition $sig -Name 'KunPetMci' -Namespace 'KunPet' -PassThru
      }
      $script:mciType::mciSendStringW('close kunpetvoice', $null, 0, [System.IntPtr]::Zero) | Out-Null
      $r = $script:mciType::mciSendStringW('open "' + $VoicePath + '" type mpegvideo alias kunpetvoice', $null, 0, [System.IntPtr]::Zero)
      if ($r -ne 0) {
        Log ('voice: MCI open failed code ' + $r)
        return
      }
      $script:mciType::mciSendStringW('play kunpetvoice', $null, 0, [System.IntPtr]::Zero) | Out-Null
      Log 'voice: MCI play started'
    } catch {
      Log ('voice: MCI failed: ' + $_.Exception.Message)
    }
  }

  # ---------- 窗口 ----------
  $window = New-Object System.Windows.Window
  $window.WindowStyle = 'None'
  $window.AllowsTransparency = $true
  $window.Background = [System.Windows.Media.Brushes]::Transparent
  $window.Topmost = $true
  $window.ShowInTaskbar = $false
  $window.ShowActivated = $false
  $window.ResizeMode = 'NoResize'
  $window.WindowStartupLocation = 'Manual'
  $window.Width = $WIN_W
  $window.Height = $WIN_H

  $grid = New-Object System.Windows.Controls.Grid
  $row0 = New-Object System.Windows.Controls.RowDefinition
  $row0.Height = New-Object System.Windows.GridLength($BUBBLE_H)
  $row1 = New-Object System.Windows.Controls.RowDefinition
  $row1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
  $grid.RowDefinitions.Add($row0)
  $grid.RowDefinitions.Add($row1)
  $window.Content = $grid

  # 气泡
  $bubbleText = New-Object System.Windows.Controls.TextBlock
  $bubbleText.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
  $bubbleText.FontSize = 13.0
  $bubbleText.Text = $BUBBLES['idle']
  $bubbleText.TextAlignment = 'Center'
  $bubbleText.MaxWidth = 236.0
  $bubbleBorder = New-Object System.Windows.Controls.Border
  $bubbleBorder.CornerRadius = New-Object System.Windows.CornerRadius(12)
  $bubbleBorder.Background = [System.Windows.Media.Brushes]::White
  $bubbleBorder.Padding = New-Object System.Windows.Thickness(12, 6, 12, 6)
  $bubbleBorder.HorizontalAlignment = 'Center'
  $bubbleBorder.VerticalAlignment = 'Top'
  $bubbleBorder.Child = $bubbleText
  [System.Windows.Controls.Grid]::SetRow($bubbleBorder, 0)
  $grid.Children.Add($bubbleBorder) | Out-Null

  # 精灵区域（缩放后的格 163.2×176.8；缩放与平移放进 RenderTransformGroup，避免 LayoutTransform 的布局开销）
  $canvas = New-Object System.Windows.Controls.Canvas
  $canvas.HorizontalAlignment = 'Center'
  $canvas.VerticalAlignment = 'Bottom'
  $canvas.Width = $W
  $canvas.Height = $H
  # Clip 必须放在不动的 canvas 上：WPF 中 Clip 会跟随 RenderTransform 一起移动
  $canvas.Clip = New-Object System.Windows.Media.RectangleGeometry(New-Object System.Windows.Rect(0, 0, $W, $H))
  [System.Windows.Controls.Grid]::SetRow($canvas, 1)
  $grid.Children.Add($canvas) | Out-Null

  $spriteHost = New-Object System.Windows.Controls.Image
  $spriteHost.Stretch = 'None'
  # Image 元素须按完整精灵图尺寸放置（元素自身会把内容裁剪到自己的盒子），
  # 由 canvas 上的固定 Clip 开窗；TransformGroup = 缩放 0.85 + 平移取帧。
  $spriteHost.Width = 1536.0
  $spriteHost.Height = 1872.0
  $scale = New-Object System.Windows.Media.ScaleTransform($SCALE, $SCALE)
  $translate = New-Object System.Windows.Media.TranslateTransform
  $group = New-Object System.Windows.Media.TransformGroup
  $group.Children.Add($scale) | Out-Null
  $group.Children.Add($translate) | Out-Null
  $spriteHost.RenderTransform = $group
  $canvas.Children.Add($spriteHost) | Out-Null

  # 兜底表情（素材解码失败时显示）
  $emoji = New-Object System.Windows.Controls.TextBlock
  $emoji.Text = [char]::ConvertFromUtf32(0x1F424)
  $emoji.FontSize = 110.0
  $emoji.Width = $W
  $emoji.Height = $H
  $emoji.TextAlignment = 'Center'
  $emoji.LineHeight = $H
  $emoji.Visibility = 'Collapsed'
  $canvas.Children.Add($emoji) | Out-Null
  Log 'window controls built'

  # ---------- 加载精灵图（优先本地文件：受限令牌下 WinINet 无法下载，WIC 可本地解码 PNG/WebP） ----------
  $bitmap = $null
  try {
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.UriSource = New-Object System.Uri('file:///' + ($SpritePath -replace '\\', '/'))
    $bi.CacheOption = 'OnLoad'
    $bi.EndInit()
    $bi.Freeze()
    $bitmap = $bi
    Log 'bitmap loaded via local file (WIC)'
  } catch {
    Log ('bitmap local file load failed: ' + $_.Exception.Message)
  }
  if ($null -eq $bitmap) {
    try {
      $bi = New-Object System.Windows.Media.Imaging.BitmapImage
      $bi.BeginInit()
      $bi.UriSource = New-Object System.Uri($SpriteUrl)
      $bi.CacheOption = 'OnLoad'
      $bi.EndInit()
      $bi.Freeze()
      $bitmap = $bi
      Log 'bitmap loaded via WPF http'
    } catch {
      Log ('bitmap http load failed: ' + $_.Exception.Message)
    }
  }
  if ($null -ne $bitmap) {
    $spriteHost.Source = $bitmap
  } else {
    $emoji.Visibility = 'Visible'
    Log 'bitmap FAILED - showing emoji fallback'
  }

  # ---------- 定时器 ----------
  $animTimer = New-Object System.Windows.Threading.DispatcherTimer
  $animTimer.Interval = [TimeSpan]::FromMilliseconds(30)

  $stateTimer = New-Object System.Windows.Threading.DispatcherTimer
  $stateTimer.Interval = [TimeSpan]::FromMilliseconds(400)

  $stateTimer.Add_Tick({
    try {
      $s = Invoke-RestMethod -Uri $StateUrl -TimeoutSec 2
      if ($s -ne $null) {
        $m = [string]$s.mode
        if ($m -eq '') { $m = 'idle' }
        if ($m -eq 'celebrating') {
          $sq = [int]$s.seq
          if ($sq -ne $script:lastSeq) {
            $script:lastSeq = $sq
            if ($script:celebrateAnim -eq 'wave') { $script:celebrateAnim = 'jump' } else { $script:celebrateAnim = 'wave' }
          }
        }
        $script:mode = $m
        if (-not $script:stateLogged) {
          $script:stateLogged = $true
          Log ('state poll OK: mode=' + $script:mode + ' seq=' + [string]$s.seq)
        }
      }
    } catch { }
  })

  $animTimer.Add_Tick({
    try {
      if ($script:reaction -ne $null -and [DateTime]::Now -ge $script:reactionUntil) {
        $script:reaction = $null
      }
      $desired = 'idle'
      if ($script:dragging) {
        $desired = $script:dragDir
      } elseif ($null -ne $script:reaction) {
        $desired = 'wave'
      } elseif ($script:mode -eq 'celebrating') {
        $desired = $script:celebrateAnim
      } else {
        $d = $MODE_ANIM[$script:mode]
        if ($null -ne $d) { $desired = [string]$d }
      }
      Set-Anim $desired
      $spec = $ROWS[$script:animName]
      if ($null -eq $spec) { $spec = $ROWS['idle'] }
      if ($script:dragging) {
        # 拖动期间冻结帧推进：只随方向切换行，减少分层窗口重绘（消除重影）
        $rowNow = [int]$spec.row
        if ($rowNow -ne $script:appliedRow) {
          $script:appliedRow = $rowNow
          $translate.X = -($script:frameIndex * $W)
          $translate.Y = -($rowNow * $H)
        }
      } else {
        $count = $spec.frames.Count
        $script:frameAcc += 30.0
        $guard = 0
        while ($script:frameAcc -ge [double]$spec.frames[$script:frameIndex]) {
          $script:frameAcc -= [double]$spec.frames[$script:frameIndex]
          $script:frameIndex = ($script:frameIndex + 1) % $count
          $guard++
          if ($guard -gt 64) { $script:frameAcc = 0.0; break }
        }
        $script:appliedRow = [int]$spec.row
        $translate.X = -($script:frameIndex * $W)
        $translate.Y = -([int]$spec.row * $H)
      }

      $b = 'idle'
      if ($script:dragging) { $b = 'dragging' } elseif ($null -ne $script:reaction) { $b = 'poke' } else { $b = $script:mode }
      $t = $BUBBLES[$b]
      if ($null -eq $t) { $t = $BUBBLES['idle'] }
      $bubbleText.Text = [string]$t

      # 语音播放状态复查（诊断用）
      if (-not $script:voiceChecked -and $script:voiceCheckAt -ne [DateTime]::MinValue -and [DateTime]::Now -ge $script:voiceCheckAt) {
        $script:voiceChecked = $true
        try { Log ('voice: playState=' + $script:wmp.playState) } catch { Log 'voice: playState check failed' }
      }
    } catch {
      Log ('anim tick error: ' + $_.Exception.Message)
    }
  })

  # ---------- 拖动 / 点击 ----------
  # 全程使用 Win32 物理像素坐标：GetCursorPos 取鼠标、SetWindowPos 移窗口、GetWindowRect 取窗口位置
  $script:win32Type = $null
  try {
    $src = @'
using System;
using System.Runtime.InteropServices;
namespace KunPet {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L; public int T; public int R; public int B; }
  public static class Win32 {
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hAfter, int X, int Y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  }
}
'@
    Add-Type -TypeDefinition $src | Out-Null
    $script:win32Type = [KunPet.Win32]
  } catch { Log ('win32 compile failed: ' + $_.Exception.Message) }

  $script:dragStart = $null
  $script:dragStartLeft = 0.0
  $script:dragStartTop = 0.0
  $script:dragMoved = $false
  $script:dragLogged = $false
  $script:dragMoveCount = 0
  $script:lastMoveL = 0.0
  $script:lastMoveT = 0.0
  # 自己的位置跟踪（SetWindowPos 移动后 WPF 的 Left/Top 会过期，不能再用）
  $script:posKnown = $false
  $script:petLeft = 0.0
  $script:petTop = 0.0
  $script:dpiScale = 0.0
  # 缓存虚拟屏幕边界（拖动时不再每次读取 SystemParameters）
  $script:vsL = [System.Windows.SystemParameters]::VirtualScreenLeft
  $script:vsT = [System.Windows.SystemParameters]::VirtualScreenTop
  $script:vsW = [System.Windows.SystemParameters]::VirtualScreenWidth
  $script:vsH = [System.Windows.SystemParameters]::VirtualScreenHeight
  $script:hwnd = [IntPtr]::Zero
  try { $script:hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle } catch { }

  $window.Add_MouseLeftButtonDown({
    try {
      if (-not $script:posKnown -and $script:hwnd -ne [IntPtr]::Zero -and $null -ne $script:win32Type) {
        $r0 = New-Object KunPet.RECT
        if ($script:win32Type::GetWindowRect($script:hwnd, [ref]$r0)) {
          $script:posKnown = $true
          $script:petLeft = [double]$r0.L
          $script:petTop = [double]$r0.T
        }
      }
      if (-not $script:posKnown) {
        $script:posKnown = $true
        $script:petLeft = $window.Left
        $script:petTop = $window.Top
      }
      $p0 = New-Object KunPet.POINT
      $script:win32Type::GetCursorPos([ref]$p0) | Out-Null
      # 物理像素屏幕坐标：窗口移动时窗口内相对坐标会变（反馈环），屏幕坐标才是正确基准
      $script:dragStart = $p0
      $script:dragStartLeft = $script:petLeft
      $script:dragStartTop = $script:petTop
      $script:lastMoveL = $script:petLeft
      $script:lastMoveT = $script:petTop
      $script:dragMoved = $false
      $script:dragLogged = $false
      $script:dragMoveCount = 0
      $script:dragging = $true
      $window.CaptureMouse() | Out-Null
    } catch { Log ('drag down error: ' + $_.Exception.Message) }
  })

  $window.Add_MouseMove({
    if ($null -eq $script:dragStart) { return }
    try {
      $p1 = New-Object KunPet.POINT
      $script:win32Type::GetCursorPos([ref]$p1) | Out-Null
      $dx = [double]$p1.X - [double]$script:dragStart.X
      $dy = [double]$p1.Y - [double]$script:dragStart.Y
      if ([math]::Abs($dx) -gt 4 -or [math]::Abs($dy) -gt 4) { $script:dragMoved = $true }
      # 方向切换带滞回（6px），避免抖动导致动画来回切换
      if ($dx -gt 6) { $script:dragDir = 'runRight' } elseif ($dx -lt -6) { $script:dragDir = 'runLeft' }
      if ($script:dpiScale -le 0) {
        try {
          $src = [System.Windows.PresentationSource]::FromVisual($window)
          if ($null -ne $src) { $script:dpiScale = $src.CompositionTarget.TransformToDevice.M11 }
        } catch { }
        if ($script:dpiScale -le 0) { $script:dpiScale = 1.0 }
      }
      $left = [math]::Min([math]::Max($script:dragStartLeft + $dx, ($script:vsL - 0.7 * $W) * $script:dpiScale), ($script:vsL + $script:vsW - 0.3 * $W) * $script:dpiScale)
      $top = [math]::Min([math]::Max($script:dragStartTop + $dy, ($script:vsT - 0.5 * $H) * $script:dpiScale), ($script:vsT + $script:vsH - 0.5 * $H) * $script:dpiScale)
      # 微小位移跳过（减少 DWM 更新次数）
      if ([math]::Abs($left - $script:lastMoveL) -lt 3 -and [math]::Abs($top - $script:lastMoveT) -lt 3) { return }
      $script:lastMoveL = $left
      $script:lastMoveT = $top
      $script:petLeft = $left
      $script:petTop = $top
      if (-not $script:dragLogged) {
        $script:dragLogged = $true
        Log ('drag: down=(' + [int]$script:dragStart.X + ',' + [int]$script:dragStart.Y + ')')
      }
      $script:dragMoveCount++
      if ($script:hwnd -ne [IntPtr]::Zero -and $null -ne $script:win32Type) {
        # SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
        $script:win32Type::SetWindowPos($script:hwnd, [IntPtr]::Zero, [int][math]::Round($left), [int][math]::Round($top), 0, 0, 0x0015) | Out-Null
      } else {
        $window.Left = $left / $script:dpiScale
        $window.Top = $top / $script:dpiScale
      }
    } catch { Log ('drag move error: ' + $_.Exception.Message) }
  })

  $window.Add_MouseLeftButtonUp({
    if ($null -eq $script:dragStart) { return }
    $wasClick = -not $script:dragMoved
    $script:dragStart = $null
    $script:dragging = $false
    try { $window.ReleaseMouseCapture() | Out-Null } catch { }
    if ($wasClick) {
      $script:reaction = 'wave'
      $script:reactionUntil = [DateTime]::Now.AddMilliseconds(2400)
      Log 'click: reaction wave + voice'
      Start-Voice
    }
  })

  # ---------- 右键菜单退出 ----------
  $menu = New-Object System.Windows.Controls.ContextMenu
  $exitItem = New-Object System.Windows.Controls.MenuItem
  $exitItem.Header = '退出 Kun Like 桌宠'
  $exitItem.Add_Click({ $window.Close() })
  $menu.Items.Add($exitItem) | Out-Null
  $window.ContextMenu = $menu

  # ---------- 初始位置（主屏工作区右下角） ----------
  $wa = [System.Windows.SystemParameters]::WorkArea
  $window.Left = $wa.Right - $WIN_W - 20
  $window.Top = $wa.Bottom - $WIN_H - 20

  $window.Add_Closed({
    $stateTimer.Stop()
    $animTimer.Stop()
    if ($null -ne $script:wmp) { try { $script:wmp.close() } catch { } }
    Remove-PidFile
    Log 'WINDOW CLOSED (clean)'
  })

  $stateTimer.Start()
  $animTimer.Start()
  Log 'entering message loop'

  $app = New-Object System.Windows.Application
  $app.ShutdownMode = 'OnMainWindowClose'
  $app.Run($window) | Out-Null
  Log 'message loop ended'
} catch {
  Log ('FATAL: ' + $_.Exception.Message)
  Log ($_.ScriptStackTrace | Out-String)
} finally {
  Remove-PidFile
  Log 'EXIT (finally)'
}
