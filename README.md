# PinChat 2.0 初版

PinChat 是一个 macOS 原生 Codex 桌宠伴随组件，不是另一套聊天主应用。它通过本机 Codex App Server 和官方 ChatGPT 登录使用用户的 Free、Plus、Pro 或工作区额度，不需要 API Key，并继承本机 Codex 的默认模型、推理强度和人格。

## 核心体验

- 高保真蓝色 Codex 桌宠，支持待机、工作、完成、失败和拖动动画，并过滤图集中的透明空帧
- 点击桌宠旁的铅笔，以横向展开动画打开玻璃质感迷你输入条；再次点击或按 `Esc` 收起
- `⌥⇧Space` 在任意普通桌面或全屏 Space 快速打开输入条
- 请求发出后显示思考/完成状态卡
- 完成卡提供：`↗` 在 Codex 中打开、`✓` 确认完成、`↓/↑` 展开或折叠回答
- 完整回答按桌宠位置智能向上或向下展开，支持拖动、缩放、关闭和继续追问
- 回答面板初次展开时吸附桌宠；单独拖动后成为自由窗口
- Codex 风格 Markdown、代码块和跟随系统强调色的用户气泡
- 桌宠可在设置中关闭；无 Dock 图标、无历史任务列表、无独立主页面

## Codex 集成

PinChat 会依次查找：

1. `/Applications/ChatGPT.app/Contents/Resources/codex`
2. `/opt/homebrew/bin/codex`
3. `/usr/local/bin/codex`
4. 当前进程 `PATH` 中的 `codex`

对话通过真实 Codex 线程进行。`↗` 会先停止 PinChat 的同步、取消线程订阅并关闭 PinChat 启动的 App Server 子进程，再用 `codex://threads/<thread-id>` 打开同一任务，因此可以直接在 Codex 主应用里继续。

PinChat 不读取浏览器 Cookie，不保存密码或 API Key。官方 OAuth 凭据和额度均由本机 Codex 管理。PinChat 的快速提问使用只读沙箱和 `never` 审批；需要工具执行、文件修改或审批的工作应交接到 Codex 主应用。

## 桌宠素材

PinChat 不在仓库中打包官方桌宠二进制素材。运行时会按以下顺序加载：

1. Codex CLI 缓存：`~/.codex/cache/tui-pets/v1/assets/codex-spritesheet-v4.webp`
2. PinChat 缓存：`~/Library/Caches/PinChat/Pets/codex-spritesheet-v4.webp`
3. OpenAI 官方静态资源：`https://persistent.oaistatic.com/codex/pets/v1/codex-spritesheet-v4.webp`
4. 离线时使用内置的 Codex 风格矢量后备形象

官方图集为 1536×1872、8×9 帧；PinChat 会校验尺寸后再使用。

## 构建与验证

系统要求：macOS 14 或更高版本，以及 ChatGPT 桌面应用或可用的 Codex CLI。

```sh
cd /Users/foolyuyu/Code/PinChat
swift test
./scripts/build-app.sh
./scripts/verify-release.sh
```

默认产物位于 `Release/PinChat.app`。构建脚本使用本机 ad-hoc 签名，适合当前 Mac 测试；正式公开分发仍需要 Apple Developer ID 签名和公证。

也可以直接用 Xcode 打开 `Package.swift`，选择 `PinChat` scheme 运行。

## 安装与数据

1. 退出旧版 PinChat。
2. 将 `Release/PinChat.app` 拖入“应用程序”，或直接双击测试。
3. 首次运行时按提示使用 ChatGPT 官方登录。
4. 点击桌宠旁的铅笔，或按 `⌥⇧Space` 提问。

本地显示副本存放在 `~/Library/Application Support/PinChat/sessions.json`；窗口位置和开关存放在 macOS `UserDefaults`。历史任务统一在 Codex 主应用中管理，PinChat 不提供历史入口。

## 已知边界

- 本轮不包含语音、附件或其他 AI API；这些是未来候选项。
- PinChat 不修改 Codex 官方桌宠或 Codex 设置。若同时启用两个桌宠，可由用户在 Codex 设置中隐藏官方桌宠。
- 普通全屏 Space 可置顶；锁屏、登录界面、系统安全窗口和受保护 DRM 画面无法被第三方应用覆盖。
- 当前构建未公证。如 macOS 阻止首次打开，请在 Finder 中按住 Control 点击应用并选择“打开”。

## 官方能力依据

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex Authentication](https://learn.chatgpt.com/docs/auth)
- [Codex Pricing](https://learn.chatgpt.com/docs/pricing)
- [Codex Pets](https://learn.chatgpt.com/docs/pets)
