# PinChat 2.3 Codex 无冲突交接版验证报告

验证日期：2026-09-15（Asia/Shanghai）

## 交付物

- `PinChat.app`：macOS 14+、Apple Silicon、本机 ad-hoc 签名的可运行应用，版本 0.2.3（5）。
- `PinChat-source.zip`：完整 Swift Package / Xcode 工程源码，不含 Git、构建缓存和应用产物。
- v1.0、v1.1、v2.0、v2.1、v2.2、v2.3 六份只读冻结需求及各自 SHA-256 校验文件。
- v2.1 冻结需求 SHA-256：`6636da523138b5b19b64c4889f063bc7cf687cec387ff4417e924b7e4a8d7427`。
- v2.2 冻结需求 SHA-256：`2fb38fd3a99e5214582154f2f1ea314def43c6414e6023c50733bc1e47d5d46c`。
- v2.3 冻结需求 SHA-256：`1165cc5dfd2048c83cf1706dfb2812ae0c58c1700dcbe6d8a8e869e4811bbbe6`。

## 构建与自动测试

- `swift test`：27 项测试全部通过。
- `xcodebuild -scheme PinChat -destination platform=macOS ... build`：通过。
- Release 构建：通过。
- `plutil -lint`：通过。
- `codesign --verify --deep --strict`：通过。
- v1.0 至 v2.3 全部冻结需求 SHA-256 校验：通过。

新增测试覆盖：

- 对话通道与桌面活动观察通道的独立角色，以及交接期间只保留观察通道。
- 交接后的对话通道按需重启状态，并校验 `codex://threads/<thread-id>` 保持原任务 ID。
- Codex `task_started`、`task_complete`、`turn_aborted` 事件到思考、完成、停止状态的归约。
- App Server 活跃状态以及等待用户输入标志优先于落盘历史事件。
- 悬停约 0.32 秒触发与约 0.20 秒跨窗容错时序。
- 删除铅笔后的 64×64 pt 透明承载区与 52×56 pt 桌宠可见尺寸约束。

既有测试继续覆盖会话持久化、账号与本机 Codex 配置、Markdown、消息去重、跨全屏 Space、多屏布局、拖动跟手、回答面板吸附、透明空帧过滤及关键视觉尺寸。

## 桌面任务同步

- PinChat 通过本机 Codex App Server 的只读 `thread/list` 获取最近活跃的 Codex Desktop 顶层任务；过滤子代理和 PinChat 自己创建的 App Server 任务。
- 状态不是按时间猜测：读取对应本机 rollout 的最近 `task_started`、`task_complete` 或 `turn_aborted` 事件，分别显示“正在思考”“已完成”或“已停止”。App Server 若报告 `activeFlags`，显示“等待你的操作”。
- 对 115 MB 的真实当前任务文件完成验证：从尾部按块反向查找最近任务事件，命中后缓存偏移；后续每 1.25 秒只读取新增部分，不持续全量扫描。
- 当前验证任务的最后两个真实生命周期事件依次为 `task_complete`、`task_started`，归约结果为“正在思考”。
- 同步失败时保留最近一次有效摘要，不清空卡片，避免文件短暂波动造成闪烁。
- 任务摘要仅包含状态和标题；不增加历史任务列表，不接 API，不产生额外模型请求，也不接管桌面端任务。

## 桌宠入口与悬停交互

- 独立铅笔按钮及相关 SwiftUI 视图已删除；空闲态只保留 Codex 桌宠本体。
- 桌宠图像继续为 52×56 pt，透明窗口从 v2.1 的 96×96 pt 缩至 64×64 pt，外围和下方不再预留铅笔区域。
- Release 实机与辅助功能树确认空闲窗口只有“打开 PinChat”桌宠，没有铅笔按钮。
- 点击桌宠后，360×50 pt 输入框直接展开并自动聚焦；辅助功能树确认文本栏处于焦点。按 `Esc` 后恢复仅桌宠空闲态。
- 鼠标停留 0.32 秒才展开状态卡，减少掠过误触；离开桌宠后延迟 0.20 秒关闭，使鼠标可跨越 3 pt 间隔进入状态卡而不闪烁。
- 悬停卡用非激活方式置前，不会抢走 Codex 桌面端或其他应用当前输入焦点。
- 点击已展开悬停卡对应的桌宠时，410×66 pt 状态卡在 0.13 秒内向自身中间横向收起，随后 360×50 pt 输入框以 0.17 秒横向揭示沿同一锚点展开。
- 拖动桌宠开始时会立即取消悬停任务并关闭临时状态卡，避免卡片滞留；普通桌面与全屏 Space 继续使用 `.canJoinAllSpaces` 和 `.fullScreenAuxiliary`。

## PinChat 对话与 Codex 交接

- PinChat 自己发起请求后的思考/完成状态卡、回答展开、拖动、缩放、关闭、继续追问和 Markdown 排版保持不变。
- v2.3 使用独立对话 App Server 处理账号、提问、流式回答和当前线程同步；独立活动观察 App Server 只读处理 `thread/list` 和桌面任务状态。
- 对话完成卡的 `↗` 会先执行 `thread/unsubscribe`，随后彻底终止并等待对话 App Server 退出，最后使用 `codex://threads/<thread-id>` 打开同一任务。
- Codex URL 只在对话进程退出完成后打开，消除了 App Server 无订阅宽限期造成的“已在另一个应用中打开”竞争。
- 交接后活动观察 App Server 保持运行；再次打开 PinChat 输入框时仅按需启动新的对话通道，不恢复已交接线程。
- 若 Codex URL 打开失败，PinChat 会重启对话通道并保留原会话，允许继续使用。
- 桌面任务悬停卡的 `↗` 可直接打开对应 Codex 任务；该路径只导航，不修改任务。
- Release 实机验证：PinChat 启动并连接后具有两个独立子 App Server；真实提问完成并点击 `↗` 后，对话子进程退出，仅保留一个活动观察子进程。
- 同一个已交接任务随后由 Codex 接受第二轮消息并无错误完成，证明原任务 ID 可继续使用且不存在 PinChat 活跃写入者占用。

## 安全与边界

- PinChat 快速提问继续采用 `approvalPolicy = never` 与 `sandbox = read-only`；工具执行、文件修改和审批交由 Codex 主应用。
- 仓库和应用包不内嵌官方 WebP 二进制素材；运行时优先读取 Codex 缓存，其次读取 PinChat 缓存或下载官方资源。
- 本地任务索引与 rollout 仅读取，不写入、不删除、不改变 Codex 设置。
- 全屏置顶指普通 macOS 全屏 Space，不包括锁屏、登录界面、系统安全窗口或受保护 DRM 画面。
- 本轮不含语音、附件、其他 AI API、Developer ID 签名、公证或 App Store 上架。
