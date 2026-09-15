# PinChat MVP 验证报告

验证日期：2026-09-15（Asia/Shanghai）

## 交付物

- `PinChat.app`：macOS 14+、Apple Silicon、本机 ad-hoc 签名的可运行应用。
- `PinChat-source.zip`：完整 Swift Package / Xcode 工程源码，不含 `.build` 缓存。
- `REQUIREMENTS_BASELINE_v1.0.md`：用户确认后冻结的需求基线。
- `REQUIREMENTS_BASELINE_v1.0.sha256`：需求基线完整性校验。

## 构建与自动测试

- `swift test`：12 项测试全部通过。
- `xcodebuild -scheme PinChat -destination platform=macOS ... build`：通过。
- Release 构建：通过。
- `plutil -lint`：通过。
- `codesign --verify --deep --strict`：通过。
- 冻结需求 SHA-256 校验：通过。
- 源码压缩包完整性测试：通过。

自动测试覆盖：

- 会话持久化。
- 账号计划名称展示。
- 本机 Codex 模型、推理强度和人格展示。
- Markdown 标题、段落、列表、引用及代码块解析。
- 流式过程中未闭合代码围栏的稳定渲染。
- 中断回答的局部内容不会被后续同步误删。
- 远端消息 ID 与本地显示消息的稳定合并。
- 多显示器窗口可见区域回收。
- 悬浮按钮贴边。
- 普通 Space 与全屏 Space 的 AppKit 窗口策略。

## 实际运行与 Codex 集成

- 最终 `PinChat.app` 已在本机成功启动。
- 运行中的 PinChat 已成功拉起 `/Applications/ChatGPT.app/Contents/Resources/codex app-server`。
- App Server 识别到现有 ChatGPT Plus 登录。
- 新版创建的真实 Codex 线程：`01a0a33d-1098-7ac0-a537-c0b055b9a4ad`。
- 该线程由 Codex 读取确认，模型为 `gpt-5.6-terra`、推理强度为 `high`、人格无额外覆盖；与验证时本机 Codex 的有效默认配置一致。
- 已验证真实文本发送、流式回答、停止生成以及中断后局部回答保留。
- 已从 Codex 侧向同一线程追加测试回合，PinChat 在首轮轮询中同步到 `SYNC_OK`；针对 App Server 不返回中断片段的情况，合并策略和回归测试均确保本地中断片段不会被后续 Codex 回合覆盖。
- 已验证右上角按钮使 PinChat 收起、Codex 成为前台，且目标线程存在于 Codex 任务列表。
- 已验证小窗中无历史会话入口；历史由 Codex 主应用管理。
- 已通过应用偏好域实际关闭悬浮按钮和置顶后重启：68×68 悬浮窗口消失，小窗从 floating layer 3 降为 normal layer 0；恢复设置后，悬浮窗口以 status-bar layer 25、小窗以 floating layer 3 重新出现。

## 窗口与视觉

- 小窗与悬浮按钮均使用 `canJoinAllSpaces`、`fullScreenAuxiliary` 和 `stationary`。
- 小窗默认使用 floating level；悬浮按钮使用 status-bar level。
- 小窗支持拖动、缩放、位置与尺寸持久化；悬浮按钮支持拖动、贴边、开关与位置持久化。
- 显示器参数变化时会把两个窗口回收到可见屏幕范围。
- 回答采用轻量正文流，用户输入保留弱化气泡；支持系统字体、系统等宽字体、标题、段落、列表、引用、链接、行内代码及可横向滚动和复制的代码块。
- 浅色与深色使用动态系统色和材质。

## 已确认边界

- 工具执行、文件修改、终端命令及审批在 Codex 主应用中继续；小窗使用只读、无审批的安全边界。
- 全屏置顶指普通 macOS 全屏 Space，不包括锁屏、登录界面、系统安全窗口或受保护 DRM 画面。
- 本轮不含其他 AI API、附件、语音、模板、Developer ID 签名、公证或 App Store 上架。

## 官方依据

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex Authentication](https://learn.chatgpt.com/docs/auth)
- [Codex Pricing](https://learn.chatgpt.com/docs/pricing)
