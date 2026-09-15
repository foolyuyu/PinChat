# PinChat 初版

PinChat 是一个面向 Codex 的 macOS 原生轻量伴随组件，而不是另一套聊天主应用。它通过本机 Codex App Server 和官方 ChatGPT 登录使用用户的 Free、Plus、Pro 或工作区额度，不需要 API Key；右上角按钮会把当前会话直接交回 Codex 打开。

## 当前功能

- `⌥ Space` 全局快捷键显示或隐藏小窗
- 可关闭的常驻悬浮按钮，支持拖动、贴边和多显示器
- 小窗置顶、收起、拖动、缩放及位置持久化
- 小窗和悬浮按钮加入所有桌面空间，并支持普通全屏应用
- 官方 ChatGPT 浏览器登录及当前账号计划展示
- 模型、人格和推理强度继承本机 Codex 设置，不在小窗内另行覆盖
- 新建对话、流式回答、停止生成
- 接近 Codex 的正文排版，支持标题、段落、列表、引用、链接、行内代码和可复制代码块
- 当前小窗会话通过官方 `codex://threads/<thread-id>` 深链在 Codex 中继续打开
- 会话由 Codex 持久化和管理；PinChat 轮询同一 Codex 线程以同步从 Codex 端新增的问答，并仅保存小窗显示所需的本地副本
- 无 Dock 图标、无自建主页面，仅保留菜单栏和基础设置
- 浅色、深色模式跟随系统
- 菜单栏入口与错误提示

## 系统要求

- macOS 14 或更高版本
- ChatGPT 桌面应用，或可用的 Codex CLI
- 用户自己的 ChatGPT 账号

PinChat 会依次查找：

1. `/Applications/ChatGPT.app/Contents/Resources/codex`
2. `/opt/homebrew/bin/codex`
3. `/usr/local/bin/codex`
4. 当前进程 `PATH` 中的 `codex`

PinChat 不读取浏览器 Cookie，也不保存用户密码。登录由 Codex 官方 OAuth 流程完成，凭据由 Codex 的本机认证存储管理。

## 在 Xcode 中开发

用 Xcode 打开 `Package.swift`，选择 `PinChat` scheme 后运行即可。项目使用 Swift Package 作为 Xcode 原生工程描述，因此不依赖第三方工程生成工具。

也可以在终端运行：

```sh
cd PinChat
swift run PinChat
```

## 构建可运行应用

```sh
cd PinChat
./scripts/build-app.sh
```

默认产物位于项目内的 `Release/PinChat.app`。构建脚本会进行本机 ad-hoc 签名，适合当前 Mac 测试。正式分发仍需要 Apple Developer ID 签名和公证。

完整验收（测试、构建、Info.plist、签名和冻结需求校验）：

```sh
cd PinChat
./scripts/verify-release.sh
```

## 安装与首次使用

1. 退出正在运行的旧版 PinChat。
2. 将 `Release/PinChat.app` 拖入“应用程序”文件夹；也可以直接双击原位置中的应用测试。
3. 首次启动后，点击小窗中的“使用 ChatGPT 登录”，在浏览器完成官方登录。
4. 使用 `⌥ Space` 或屏幕边缘的悬浮按钮随时打开小窗。
5. 发送第一条消息后，右上角“在 Codex 中打开”会打开同一个 Codex 会话。

当前构建采用本机 ad-hoc 签名且未公证。如果 macOS 阻止首次打开，请在 Finder 中按住 Control 点击应用，选择“打开”，再确认一次。不要绕过系统的其他安全检查。

## 数据与设置

- 对话索引与显示内容：`~/Library/Application Support/PinChat/sessions.json`
- 窗口、置顶及悬浮按钮设置：macOS `UserDefaults`
- ChatGPT 登录：由 Codex 管理，不写入 PinChat 的会话文件

## 官方能力依据

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)：真实线程、回合、流式通知、账号及配置读取
- [Codex Authentication](https://learn.chatgpt.com/docs/auth)：ChatGPT 托管登录
- [Codex Pricing](https://learn.chatgpt.com/docs/pricing)：ChatGPT 计划内 Codex 使用方式

## 已知边界

- 当前只提供快速文本对话，不包含附件、语音和其他 AI API。
- 小窗不提供历史列表；历史会话统一在 Codex 主应用中管理。
- 小窗不覆盖本机 Codex 的模型、人格或推理强度；新会话继承 Codex 当前默认配置。工具执行与审批仍需在 Codex 主应用中完成。
- “全屏置顶”适用于普通 macOS 全屏 Space；系统锁屏、登录界面、系统安全权限窗口和受保护的 DRM 画面无法被第三方应用覆盖。
- `⌥ Space` 如果被其他应用占用，PinChat 会提示；初版设置页暂不支持修改快捷键。
