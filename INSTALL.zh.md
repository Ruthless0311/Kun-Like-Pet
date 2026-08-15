# Kun Like 桌宠 · 安装步骤（创造模式）

## 为什么需要新会话
本插件是 DSH 动态插件，必须用 cordis_define / cordis_run 安装，而这两个工具只在
「创造模式」Agent preset 中注册。会话一旦有对话记录即锁定 preset，无法中途切换，
所以请在「创造模式」下新建一个会话再执行。

## 已就绪
- 素材：`assets/spritesheet.webp`、`assets/voice.mp3`
- 载荷：`kunpet.package.json`（已按 Windows 配好素材路径与播放命令）
- 源码：`src/host.js`（宿主半）、`src/client.js`（客户端半）

## 安装步骤（让创造模式会话里的 Agent 执行）
1. 读取 `D:\harness-UI\kun-like-pet\kunpet.package.json`
2. 调用 `cordis_define`，参数直接取该 JSON 的四个字段：
   - `plugin` = `{ "kind": "new", "idPrefix": "kunpet" }`
   - `name` = "Kun Like 桌宠"
   - `purpose` = 该 JSON 的 purpose 字段
   - `code.host` = 该 JSON 的 code.host 内容
   - `code.client` = 该 JSON 的 code.client 内容
3. 记录返回的 `pluginId` 与 `packageId`
4. 调用 `cordis_run`：
   - `pluginId` = 上一步返回值
   - `packageId` = 上一步返回值
   - `mode` = "run"
5. 若返回 `awaiting-approval`，在界面中允许；若返回 `starting`，等待浏览器异步完成
6. 刷新 Web 页面，右下角即出现小坤宠；可用 `kun_pet_debug` 工具查看状态机

## 说明
- 动态插件是会话级：桌宠形象只注入到激活它的会话页面；完成音由宿主系统级播放，
  任何窗口/会话完成任务都会响。
- `src/host.js` 顶部 CONFIG 已指向：
  - 精灵图：`D:/harness-UI/kun-like-pet/assets/spritesheet.webp`
  - 完成音：`D:/harness-UI/kun-like-pet/assets/voice.mp3`
  - 播放命令：`powershell -c (New-Object System.Media.SoundPlayer '...').PlaySync()`
