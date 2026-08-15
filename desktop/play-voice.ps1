# =============================================================================
# Kun Like 桌宠 · 系统级语音播放（宿主进程调用）
# WMP COM 优先；失败回退 MCI。播完自动退出。
# 注意：宿主 shell 服务会吞掉命令字符串中的 $-变量，因此播放逻辑必须放在
#       本脚本文件里，由 CONFIG.playCommand 以 -File 方式调用。
# =============================================================================
param(
  [string]$VoicePath = 'D:\harness-UI\kun-like-pet\assets\voice.mp3'
)
$ErrorActionPreference = 'SilentlyContinue'
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
  exit 0
} catch {
  try {
    $sig = '[DllImport("winmm.dll", CharSet = CharSet.Unicode)] public static extern int mciSendStringW(string cmd, System.Text.StringBuilder ret, int retLen, System.IntPtr hwnd);'
    $mci = Add-Type -MemberDefinition $sig -Name 'KunPetMciPlay' -Namespace 'KunPet' -PassThru
    $mci::mciSendStringW('close kunpetvoice', $null, 0, [System.IntPtr]::Zero) | Out-Null
    $r = $mci::mciSendStringW('open "' + $VoicePath + '" type mpegvideo alias kunpetvoice', $null, 0, [System.IntPtr]::Zero)
    if ($r -eq 0) {
      $mci::mciSendStringW('play kunpetvoice', $null, 0, [System.IntPtr]::Zero) | Out-Null
      Start-Sleep -Seconds 5
    }
  } catch { }
  exit 1
}
