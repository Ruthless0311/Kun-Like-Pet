# =============================================================================
# Kun Like 桌宠 · 系统级语音播放（宿主进程调用）
# MCI（winmm）优先；WMP COM 回退。
# 注意：本脚本必须以 shell.start 后台方式启动，
#       shell.run 前台路径实测静音（同一脚本、同一会话）。
# 全程写入 D:\KUN_pet\voice-play.log 便于诊断。
# =============================================================================
param(
  [string]$VoicePath = 'D:\harness-UI\kun-like-pet\assets\voice.mp3'
)
$ErrorActionPreference = 'Continue'
$log = 'D:\KUN_pet\voice-play.log'
('=== ' + (Get-Date -Format 'HH:mm:ss.fff') + ' play: ' + $VoicePath) | Out-File $log -Encoding UTF8

# 1. MCI（winmm mciSendString，DirectShow MPEG 解码）
try {
  $sig = '[DllImport("winmm.dll", CharSet = CharSet.Unicode)] public static extern int mciSendStringW(string cmd, System.Text.StringBuilder ret, int retLen, System.IntPtr hwnd);'
  $mci = Add-Type -MemberDefinition $sig -Name 'KunPetMciPlay2' -Namespace 'KunPet' -PassThru
  $mci::mciSendStringW('close kunpetvoice', $null, 0, [System.IntPtr]::Zero) | Out-Null
  $r = $mci::mciSendStringW('open "' + $VoicePath + '" type mpegvideo alias kunpetvoice', $null, 0, [System.IntPtr]::Zero)
  Add-Content $log ('MCI open rc=' + $r) -Encoding UTF8
  if ($r -eq 0) {
    $r2 = $mci::mciSendStringW('play kunpetvoice', $null, 0, [System.IntPtr]::Zero)
    Add-Content $log ('MCI play rc=' + $r2) -Encoding UTF8
    Start-Sleep -Seconds 5
    exit 0
  }
} catch {
  Add-Content $log ('MCI exception: ' + $_.Exception.Message) -Encoding UTF8
}

# 2. WMP COM 回退
try {
  $w = New-Object -ComObject WMPlayer.OCX
  $w.settings.volume = 100
  $w.URL = $VoicePath
  Start-Sleep -Milliseconds 400
  $t = 0.4
  while ($w.playState -ne 1 -and $t -lt 10) {
    Start-Sleep -Milliseconds 250
    $t += 0.25
  }
  Add-Content $log ('WMP done playState=' + $w.playState) -Encoding UTF8
  exit 0
} catch {
  Add-Content $log ('WMP exception: ' + $_.Exception.Message) -Encoding UTF8
  exit 1
}
