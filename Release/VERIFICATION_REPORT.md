# PinChat 3.3 Codex 权限跟随版验证报告

验证日期：2026-09-17（Asia/Shanghai）

## 交付物

- `PinChat.app`：macOS 14+、Apple Silicon、本机 ad-hoc 签名的可运行应用，版本 0.3.3（11）。
- `PinChat-source.zip`：完整 Swift Package / Xcode 工程源码，不含 Git、构建缓存和应用产物。
- v1.0、v1.1、v2.0、v2.1、v2.2、v2.3、v2.4、v2.5、v3.0、v3.1、v3.2、v3.3 十二份只读冻结需求及各自 SHA-256 校验文件。
- v2.1 冻结需求 SHA-256：`6636da523138b5b19b64c4889f063bc7cf687cec387ff4417e924b7e4a8d7427`。
- v2.2 冻结需求 SHA-256：`2fb38fd3a99e5214582154f2f1ea314def43c6414e6023c50733bc1e47d5d46c`。
- v2.3 冻结需求 SHA-256：`1165cc5dfd2048c83cf1706dfb2812ae0c58c1700dcbe6d8a8e869e4811bbbe6`。
- v2.4 冻结需求 SHA-256：`f168c3b480faab81a0ac63dea7e45e5cf294fef82e21951712738f4ebe3ea6a4`。
- v2.5 冻结需求 SHA-256：`499a9d4987d738c7141a30d3d41b038bc38828f5c328b2d0a01b46ab0737f61c`。
- v3.0 冻结需求 SHA-256：`b56450a0803b95f2d1021c41790da431770ab415424f7ab1471501d130f38d18`。
- v3.1 冻结需求 SHA-256：`15b64a470c67eb3beb664bf4331836ee38b7826b0de358b63314132062bc2145`。
- v3.2 冻结需求 SHA-256：`719a0d1ee6e2b8f02ae89dffef9955850ee3a02b9609723277b09447469447d1`。
- v3.3 冻结需求 SHA-256：`4435c230208442d9b3b1a2730d6014c27fea92fd035ce789858db9b3114b68db`。

## 构建与自动测试

- `swift test`：51 项测试全部通过。
- `xcodebuild -scheme PinChat -destination platform=macOS ... build`：通过。
- Release 构建：通过。
- `plutil -lint`：通过。
- `codesign --verify --deep --strict`：通过。
- v1.0 至 v3.3 全部冻结需求 SHA-256 校验：通过。

## Codex 权限跟随验证

- 本机 Codex Desktop 的共享状态当前为 `agent-mode-by-host-id.local = full-access`，同时 `permission-selection-by-host-id:local` 为 `agent-mode / full-access`；PinChat 解析结果为“完全访问”。
- PinChat 已移除输入框权限菜单和设置页权限选择器，不再读取或写入旧的 `pinChatPermissionModeV1` 偏好。
- 每次展开输入框及发送前都会刷新共享状态；新建、恢复、每轮 `turn/start` 和交接前恢复使用同一配置。
- 完全访问会同时发送 `approvalPolicy: never`、线程级 `sandbox: danger-full-access` 与轮次级 `sandboxPolicy.type: dangerFullAccess`，避免旧线程或下一轮退回工作区审批。
- 既有两次 PinChat 实际任务记录均确认 `approval_policy = never`、`sandbox_policy.type = danger-full-access`，且没有 Codex approval/request_permissions 事件；这证明此前出现的系统授权不是 Codex 完全访问参数失效。
- macOS TCC 仍会独立管理桌面、文稿、照片和其他应用数据；该系统层授权不能由 Codex 权限设置绕过。设置页保留“打开完全磁盘访问设置”入口。

## 真实审批链路验证

- 使用与 PinChat 相同的本机 Codex App Server 创建临时任务，确认实际启动参数为 `approvalPolicy: on-request`、`approvalsReviewer: user`、`sandbox.type: workspaceWrite`。
- 在该任务中请求执行 `/bin/zsh -lc 'touch /Applications/PinChat-Approval-Probe.tmp'`，服务端真实发出 `item/commandExecution/requestApproval`，不是界面模拟或单元测试伪造。
- 审批端选择拒绝后，App Server 接受 `decline` 响应，命令最终状态为 `declined`；`/Applications/PinChat-Approval-Probe.tmp` 未创建。
- 首次网络探针未触发审批，因为本机 Codex 的 `workspace-write` 配置报告 `networkAccess: true`；因此改用沙箱外文件写入完成边界验证，避免将允许范围内行为误判为审批成功。
- 命令、文件修改和权限扩展三类请求均由同一审批队列处理；停止进程、外部解决或任务结束时会清理过期请求，避免旧审批残留。

新增测试覆盖：

- Codex Desktop 共享状态中本机 `agent-mode` 与命名权限配置的解析，且明确以新的 permission selection 覆盖旧模式值。
- “询问批准 / 自动审查 / 完全访问”到线程及轮次级 `approvalPolicy`、`approvalsReviewer`、`sandbox` 和 `sandboxPolicy` 的官方参数映射。
- 新建、恢复与每轮执行均使用发送前刷新后的 Codex 权限，避免旧任务继续落回先前配置。
- 命令审批的拒绝、允许一次与会话允许，以及数字/字符串 App Server 请求 ID。
- 权限扩展仅回传服务端明确请求的文件和网络范围；拒绝时回传空权限并限制在当前轮次。

- 键入光标目标到官方 16 向姿态的角度映射、0°/360° 边界、正上/右/下/左四个基准方向及中心死区。
- 方向姿态到第 10、11 行的准确行列映射，以及 1536×2288 方向图集和 1536×1872 旧图集兼容。
- 待机、工作、完成允许注视键入光标，拖动、失败和左右奔跑动画保持优先。
- 正式回答触发自动对话展示，执行型事件升级为工作展示，且工作模式在本轮内不再降级。
- 命令、文件变更、MCP/动态工具、协作子任务、检索、图片查看和审批请求的 App Server 分类。
- 最多 5 个任务的去重、进行中优先和更新时间排序，且每个任务保留独立状态。
- `systemError` 到失败状态的归约，以及 1 至 5 项任务面板的动态高度上限。
- App Server 技能、可访问应用和已安装可调用应用的解析过滤。
- 官方 `skill` / `mention` 输入项、调用标记与能力元数据持久化兼容。
- App Server 将照片映射为 `localImage`，将普通文件路径拼入只读本机上下文，并支持仅图片提交。
- 附件元数据持久化与旧版无附件 `sessions.json` 的向后兼容解码。
- 带附件输入框的 360×88 pt 动态尺寸，以及紧凑表面 0 pt 外圈透明 inset。
- 对话通道与桌面活动观察通道的独立角色，以及交接期间只保留观察通道。
- 交接后的对话通道按需重启状态，并校验 `codex://threads/<thread-id>` 保持原任务 ID。
- Codex `task_started`、`task_complete`、`turn_aborted` 事件到思考、完成、停止状态的归约。
- App Server 活跃状态以及等待用户输入标志优先于落盘历史事件。
- 悬停约 0.32 秒触发与约 0.20 秒跨窗容错时序。
- 删除铅笔后的 64×64 pt 透明承载区与 52×56 pt 桌宠可见尺寸约束。

既有测试继续覆盖会话持久化、账号与本机 Codex 配置、Markdown、消息去重、跨全屏 Space、多屏布局、拖动跟手、回答面板吸附、透明空帧过滤及关键视觉尺寸。

## 桌宠方向互动

- 已按桌宠中心到原生文字插入光标屏幕位置的夹角，每 22.5° 映射到一个方向姿态；正上方为 0°，顺时针排列 16 向。
- 输入条与可继续追问的回答窗口获得文本焦点后启动约 30 Hz 读取；输入、换行、点击、方向键改变选区或移动窗口时，方向随真实插入点更新。
- 输入框失焦、收起或切换应用后停止注视并恢复基础动画；系统开启“减少动态效果”时采样自动降至约 10 Hz，且不新增辅助功能或输入监控权限要求。
- 拖动时继续显示跳跃动画，失败等瞬时状态不会被方向帧覆盖；拖动结束且文本栏仍有键入焦点时恢复注视插入点。
- 运行时只读 `/Applications/ChatGPT.app/Contents/Resources/app.asar`，动态查找最新 `codex-spritesheet-v*.webp`，仅接受 1536×2288 方向图集并缓存至 PinChat；不修改 ChatGPT 应用。
- 官方二进制素材未进入 Git、应用包或源码压缩包。若 ChatGPT 资源缺失或格式变化，自动回退旧版 8×9 图集与离线矢量形象。
- Release 已从完整路径重新启动为新进程；运行时生成的方向缓存确认为 1536×2288，SHA-256 与本机 ChatGPT `app.asar` 内官方 v6 图集一致（`ac2990f24d55372411cebdc66a726e1fcbf5e80ec95378e2d25a6241abbedf88`）。
- 实机辅助功能检查确认点击桌宠后输入条直接展开、文本栏自动获得焦点，外观尺寸与既有 3.0 紧凑表面保持一致。

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

- v3.0 每轮从“判断中”开始；纯回答出现时自动展开回答面板，执行型事件出现时保持或恢复紧凑进度卡。
- 类型判断使用 App Server 的真实 item 与 request 事件，不扫描问题关键词；同一工作轮次不会因最终文字回答再次自动展开。
- 自动展开只发生在状态首次从“判断中”进入“对话”时，用户手动关闭后不会被后续流式文字反复打开。
- PinChat 自己发起请求后的思考/完成状态卡、回答展开、拖动、缩放、关闭、继续追问和 Markdown 排版保持不变。
- v2.3 使用独立对话 App Server 处理账号、提问、流式回答和当前线程同步；独立活动观察 App Server 只读处理 `thread/list` 和桌面任务状态。
- 对话完成卡的 `↗` 会先执行 `thread/unsubscribe`，随后彻底终止并等待对话 App Server 退出，最后使用 `codex://threads/<thread-id>` 打开同一任务。
- Codex URL 只在对话进程退出完成后打开，消除了 App Server 无订阅宽限期造成的“已在另一个应用中打开”竞争。
- 交接后活动观察 App Server 保持运行；再次打开 PinChat 输入框时仅按需启动新的对话通道，不恢复已交接线程。
- 若 Codex URL 打开失败，PinChat 会重启对话通道并保留原会话，允许继续使用。
- 桌面任务悬停卡的 `↗` 可直接打开对应 Codex 任务；该路径只导航，不修改任务。
- Release 实机验证：PinChat 启动并连接后具有两个独立子 App Server；真实提问完成并点击 `↗` 后，对话子进程退出，仅保留一个活动观察子进程。
- 同一个已交接任务随后由 Codex 接受第二轮消息并无错误完成，证明原任务 ID 可继续使用且不存在 PinChat 活跃写入者占用。

## 附件入口与紧凑表面

- 登录状态下 `+` 为真实菜单，包含“添加文件和文件夹…”，“添加照片…”和“截屏…”；未登录时仍作为登录入口。
- 文件和照片选择使用 macOS 原生选择器并支持多选；截屏使用系统交互式区域/窗口选择，缓存位于 PinChat 的 Caches/Attachments 目录。
- 图片按官方 App Server `localImage` 输入发送；普通文件和文件夹只发送用户选择的绝对路径，保持只读 sandbox，不复制或修改源文件。
- 已选附件以横向可移除标签展示，输入框从 360×50 pt 自动扩展为 360×88 pt；允许无文字、仅附件发送。
- 输入框和状态卡移除了外围 4 pt 透明 padding、灰色细描边和透底材质，圆角实色表面直接贴合无边框窗口。

## 多任务与官方能力菜单

- 桌宠悬停面板同时显示最多 5 个近期 Codex 桌面任务；正在思考或等待操作的任务排在已完成、已停止和失败任务之前。
- 每项任务分别展示标题与真实状态，并将右侧跳转按钮绑定到该项自己的 Codex thread ID。
- 任务数量变化时面板由 66 pt 动态增高，最多 286 pt，并继续根据桌宠位置向可用空间展开。
- `+` 菜单通过 `skills/list` 读取本机技能，通过 `app/installed` 立即读取可调用应用，并用 `app/list` 更新名称与说明。
- 技能与应用可选择、取消和以标签移除；发送时分别映射为官方 `skill` 与 `mention` 输入项。
- 官方 App Server 未公开 ChatGPT 历史对话附加协议，本版不提供无效的仿制入口。

## 安全与边界

- PinChat 不再定义自己的默认权限；它只读跟随 Codex Desktop 为本机 host 保存的当前权限选择，不写入或修改 Codex 配置。
- Codex 选择“询问批准”时，越界命令、文件修改和权限扩展由小窗请求用户决定；选择“自动审查”时使用官方 `auto_review` reviewer；选择“完全访问”时使用 `danger-full-access + never`。
- 输入框与设置页不再提供 PinChat 私有权限选择器，避免同一台机器出现两套互相矛盾的权限状态。
- 权限表示可用能力上限，不要求模型对普通问答调用文件或命令工具；附件选择也不自动授予任意写权限。
- 完全访问仍受 macOS TCC 和完全磁盘访问权限约束，PinChat 只提供打开系统设置的入口，不自动更改系统隐私授权。
- 仓库和应用包不内嵌官方 WebP 二进制素材；运行时优先读取 Codex 缓存，其次读取 PinChat 缓存或下载官方资源。
- 本地任务索引与 rollout 仅读取，不写入、不删除、不改变 Codex 设置。
- 全屏置顶指普通 macOS 全屏 Space，不包括锁屏、登录界面、系统安全窗口或受保护 DRM 画面。
- 本轮不含语音、其他 AI API、Developer ID 签名、公证或 App Store 上架。
