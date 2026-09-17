# PinChat 3.3 Codex 权限跟随版

PinChat 是一个 macOS 原生 Codex 桌宠伴随组件，不是另一套聊天主应用。它通过本机 Codex App Server 和官方 ChatGPT 登录使用用户的 Free、Plus、Pro 或工作区额度，不需要 API Key，并继承本机 Codex 的默认模型、推理强度和人格。

## 核心体验

- 高保真蓝色 Codex 桌宠，支持待机、工作、完成、失败和拖动动画，并过滤图集中的透明空帧
- 输入条或回答窗口中出现键入光标时，桌宠使用官方 16 向姿态看向文字插入点；文字增长、换行或移动插入点时同步调整
- 输入框失焦或关闭后恢复基础姿态；拖动、失败等明确状态仍优先显示自身动画，“减少动态效果”开启时自动降低采样频率
- 桌宠按官方实机参考保持约 52 pt，透明承载区进一步缩至 64×64 pt，不再保留下方铅笔入口
- 点击桌宠本体直接展开横向输入条；再次点击桌宠、按 `Esc` 或再次使用快捷键均可收起
- 输入条 `+` 支持添加多个文件/文件夹、照片和交互式截屏；附件可在发送前单独移除
- 输入条不再放置独立权限按钮；PinChat 每次提问前读取 Codex 主应用的本机权限选择，自动跟随“询问批准 / 自动审查 / 完全访问 / 只读 / 自定义权限”
- 当 Codex 当前设置确实要求审批时，小窗仍会显示真实命令、原因与路径，并支持拒绝、允许一次或本次对话允许
- `+` 还会读取本机 Codex 的真实技能与已连接应用，选择后通过官方 `skill` / `mention` 输入项调用
- 图片作为 Codex 原生本地图片输入发送，普通文件和文件夹作为用户选择的只读本机路径上下文发送
- 输入框与状态卡取消外围透明承载边并使用不透底系统表面，不再透出下方页面文字
- 鼠标在桌宠上短暂停留后，同时显示最多 5 个近期 Codex 桌面任务；工作中任务优先，每项独立显示“正在思考 / 等待操作 / 已完成 / 已停止 / 失败”并可准确跳转
- 悬停状态卡出现时点击桌宠，卡片先向中间收起，输入框再沿同一锚点紧接展开
- `⌥⇧Space` 在任意普通桌面或全屏 Space 快速打开输入条
- 输入条采用 360×50 pt 紧凑比例，请求发出后由 410×66 pt 思考/完成状态卡替换
- 纯对话在正式回答出现时自动展开回答窗口；命令、文件变更、工具、检索、子任务或审批等工作保持紧凑进度卡
- 展示类型由本机 Codex 的真实事件判断；工作模式一旦确认便保持到本轮结束，避免窗口来回跳动
- 完成卡提供：`↗` 在 Codex 中打开、`✓` 确认完成、`↓/↑` 展开或折叠回答
- 完整回答按桌宠位置智能向上或向下展开，支持拖动、缩放、关闭和继续追问
- 回答面板初次展开时吸附桌宠；单独拖动后成为自由窗口
- `↗` 会在释放 PinChat 对话连接后打开同一个 Codex 任务，可立即在桌面应用继续对话
- Codex 风格 Markdown、代码块和跟随系统强调色的用户气泡
- 桌宠可在设置中关闭；无 Dock 图标、无历史任务列表、无独立主页面

## Codex 集成

PinChat 会依次查找：

1. `/Applications/ChatGPT.app/Contents/Resources/codex`
2. `/opt/homebrew/bin/codex`
3. `/usr/local/bin/codex`
4. 当前进程 `PATH` 中的 `codex`

对话通过真实 Codex 线程进行。PinChat 使用两个相互独立的本机 App Server：对话通道负责账号、提问、流式回答和线程订阅；活动观察通道只读获取 Codex 桌面任务状态。

`↗` 会让对话通道取消当前线程订阅并彻底退出，等待线程释放完成后才通过 `codex://threads/<thread-id>` 打开同一任务，因此可以立即在 Codex 主应用中继续，不再触发“已在另一个应用中打开”。只读活动观察通道保持运行，不影响桌宠状态同步。用户下次打开输入框时会按需启动新的对话通道，且不会重新占用已交接任务。

桌面任务摘要通过独立活动观察通道的只读 `thread/list` 索引以及对应本机任务记录中的 `task_started`、`task_complete`、`turn_aborted` 事件生成；它不会向模型额外发问，也不会订阅、接管或修改 Codex 桌面端任务。

PinChat 不读取浏览器 Cookie，不保存密码或 API Key。官方 OAuth 凭据、额度、模型、人格和任务权限均由本机 Codex 管理。PinChat 只读取得 Codex Desktop 对本机 host 保存的权限选择，并在创建、恢复和每轮执行时使用同一配置；不另存一套权限偏好。完全访问不会强制模型调用文件工具，且仍不能绕过 macOS 的隐私保护。

## 桌宠素材

PinChat 不在仓库中打包官方桌宠二进制素材。运行时会按以下顺序加载：

1. PinChat 方向图集缓存：`~/Library/Caches/PinChat/Pets/codex-spritesheet-directional.webp`
2. 只读本机 ChatGPT 应用的 `app.asar`，动态查找最新官方 Codex 方向图集并写入上述缓存
3. Codex CLI 旧图集缓存：`~/.codex/cache/tui-pets/v1/assets/codex-spritesheet-v4.webp`
4. PinChat 旧图集缓存：`~/Library/Caches/PinChat/Pets/codex-spritesheet-v4.webp`
5. OpenAI 官方旧版静态资源：`https://persistent.oaistatic.com/codex/pets/v1/codex-spritesheet-v4.webp`
6. 离线时使用内置的 Codex 风格矢量后备形象

当前方向图集为 1536×2288、8×11 帧；最后两行按正上方起每 22.5° 提供一个方向，共 16 向。旧版 1536×1872、8×9 图集仍可用于基础动画，PinChat 会校验尺寸后再使用。

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
4. 点击桌宠本体，或按 `⌥⇧Space` 提问；悬停桌宠可查看最近 Codex 桌面任务状态。

本地显示副本存放在 `~/Library/Application Support/PinChat/sessions.json`；窗口位置和开关存放在 macOS `UserDefaults`。历史任务统一在 Codex 主应用中管理，PinChat 不提供历史入口。

## 已知边界

- 本轮不包含语音或其他 AI API；这些是未来候选项。
- PinChat 不修改 Codex 官方桌宠或 Codex 设置。若同时启用两个桌宠，可由用户在 Codex 设置中隐藏官方桌宠。
- 普通全屏 Space 可置顶；锁屏、登录界面、系统安全窗口和受保护 DRM 画面无法被第三方应用覆盖。
- 当前构建未公证。如 macOS 阻止首次打开，请在 Finder 中按住 Control 点击应用并选择“打开”。
- 读取邮件、信息、浏览器数据及部分系统目录仍受 macOS TCC 管理；如任务确实需要，可在 PinChat 设置中打开“完全磁盘访问权限”页面并由用户手动授权。

## 2.1 官方桌宠参考记录

v2.1 在用户授权下对本机官方 Codex 桌宠完成了悬停、铅笔按下、松开与输入框展开的连续观察。官方桌宠约 60 pt 宽，悬停工具条约 120×40 pt，输入条约 322×42 pt，并在鼠标松开后约 120 ms 内完成替换。PinChat 没有提交包含用户界面的参考截图，只在冻结的 `Release/VISUAL_OPTIMIZATION_REQUIREMENTS_BASELINE_v2.1.md` 中保存去标识化测量值和验收标准。

## 2.2 桌面任务联动

v2.2 删除了功能重复的铅笔按钮。桌宠本体成为唯一点击入口；悬停约 0.32 秒展示桌面任务摘要，移出桌宠与卡片约 0.20 秒后收起。状态来源为本机真实 Codex 任务记录，并对大型任务文件使用增量读取，避免持续全量扫描。

## 2.3 Codex 无冲突交接

v2.3 将原本共用的 App Server 拆成对话和活动观察两个通道。打开 Codex 前，对话通道在 `thread/unsubscribe` 后完整退出，消除 App Server 无订阅宽限期内的占用竞争；观察通道继续运行，桌宠任务摘要不中断。冻结验收标准见 `Release/HANDOFF_FIX_REQUIREMENTS_BASELINE_v2.3.md`。

## 2.4 附件与纯净表面

v2.4 去除了输入框和状态卡四周额外的 4 pt 透明承载边，并改用不透底系统窗口背景。`+` 入口对齐官方 Codex 的添加文件、添加照片和截取 Appshot 三类动作；已选附件显示为可移除标签，输入框随附件自动增高。冻结验收标准见 `Release/ATTACHMENT_AND_SURFACE_REQUIREMENTS_BASELINE_v2.4.md`。

## 2.5 多任务与官方能力菜单

v2.5 将桌宠悬停摘要从单个最近任务升级为最多 5 项的动态列表，进行中任务优先并保留各自独立状态与跳转目标。输入框 `+` 通过官方 App Server 的 `skills/list`、`app/installed` 与 `app/list` 读取本机技能和已连接应用，并以 `skill` / `mention` 输入项调用；App Server 尚未开放的 ChatGPT 历史对话附加能力不会伪造成无效入口。冻结验收标准见 `Release/MULTITASK_AND_CAPABILITIES_REQUIREMENTS_BASELINE_v2.5.md`。

## 3.0 智能对话与任务展示

v3.0 根据本机 Codex App Server 的实际事件自动选择展示方式。只有正式回答且没有执行动作的请求会自动展开回答窗口；命令、文件变更、工具调用、网页检索、图片查看、子任务和审批请求保持进度卡。工作模式在本轮内锁定，手动展开最终回答和连续追问继续可用。冻结验收标准见 `Release/INTELLIGENT_PRESENTATION_REQUIREMENTS_BASELINE_v3.0.md`。

## 3.1 桌宠输入互动

v3.1 对齐官方桌宠的 16 向注视反馈：输入条或可继续追问的回答窗口获得键入焦点时，按文字插入光标相对桌宠中心的方向切换官方绘制姿态；光标随输入、换行或选区移动后同步调整，失焦或收起输入界面后回到基础动画。PinChat 从本机 ChatGPT 应用只读提取方向图集并缓存，不把官方二进制素材提交到仓库；素材不可用时自动回退旧图集。冻结验收标准见 `Release/PET_INTERACTION_REQUIREMENTS_BASELINE_v3.1.md`。

## 3.2 官方式权限与审批

v3.2 不再把 PinChat 任务固定为只读。输入条与设置页提供“询问批准”“自动批准”“完全访问”三档，分别映射到 Codex 官方的工作区沙箱、审批 reviewer 与全访问配置。命令执行、工作区外文件修改和 `request_permissions` 权限扩展会在回答小窗显示原始请求范围，并按官方 App Server 协议回传拒绝、单次允许或会话允许；失效请求会自动移除。冻结验收标准见 `Release/PERMISSIONS_REQUIREMENTS_BASELINE_v3.2.md`。

## 3.3 跟随 Codex 权限

v3.3 将 PinChat 明确收敛为 Codex 的置顶窗口扩展：移除输入框和设置页中的独立权限选择器，不再保存 PinChat 私有权限偏好。应用会只读解析 Codex Desktop 的本机 host 权限选择，并在每次提问前刷新；任务创建、恢复和 `turn/start` 使用相同的官方参数。Codex 设为完全访问时不再出现普通越界审批；若 Codex 本身选择询问批准，PinChat 才展示相同审批。冻结验收标准见 `Release/CODEX_PERMISSION_FOLLOW_REQUIREMENTS_BASELINE_v3.3.md`。

## 官方能力依据

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex Authentication](https://learn.chatgpt.com/docs/auth)
- [Codex Pricing](https://learn.chatgpt.com/docs/pricing)
- [Codex Pets](https://learn.chatgpt.com/docs/pets)
- [Codex Sandbox](https://learn.chatgpt.com/docs/sandboxing)
