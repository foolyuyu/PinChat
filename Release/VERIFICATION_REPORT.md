# PinChat 2.1 视觉优化版验证报告

验证日期：2026-09-15（Asia/Shanghai）

## 交付物

- `PinChat.app`：macOS 14+、Apple Silicon、本机 ad-hoc 签名的可运行应用，版本 0.2.1（3）。
- `PinChat-source.zip`：完整 Swift Package / Xcode 工程源码，不含 Git、构建缓存和应用产物。
- v1.0、v1.1、v2.0、v2.1 四份只读冻结需求及各自 SHA-256 校验文件。
- v2.0 冻结需求 SHA-256：`89a7896c1a7523d98afffe946c7ea573790295c67b3a5735e3ebd181d85596d1`。
- v2.1 冻结需求 SHA-256：`6636da523138b5b19b64c4889f063bc7cf687cec387ff4417e924b7e4a8d7427`。

## 构建与自动测试

- `swift test`：22 项测试全部通过。
- `xcodebuild -scheme PinChat -destination platform=macOS ... build`：通过。
- Release 构建：通过。
- `plutil -lint`：通过。
- `codesign --verify --deep --strict`：通过。
- v1.0、v1.1、v2.0、v2.1 冻结需求 SHA-256 校验：全部通过。

测试覆盖：

- 会话持久化、账号计划和本机 Codex 配置展示。
- Markdown 标题、段落、列表、引用、代码块及流式未闭合代码围栏。
- commentary 过滤、按消息 ID 合并、完成文本权威替换及中断回答保留。
- 窗口跨普通/全屏 Space 策略、多屏可见区域约束和鼠标抓取偏移。
- 桌宠状态到待机、工作、完成、失败和拖动动画的映射。
- v2.1 桌宠、入口、输入、状态卡、回答工具栏和追问按钮尺寸上限。
- 官方图集透明空帧检测与过滤。
- 回答面板根据可用空间选择向上或向下展开。
- 状态卡与回答面板吸附顺序、屏幕约束和手动拖动后解除吸附。

## 桌宠与视觉实测

- PinChat 成功从 OpenAI 官方地址下载 1536×1872 WebP 图集，校验尺寸并缓存到 `~/Library/Caches/PinChat/Pets/codex-spritesheet-v4.webp`。
- 用户授权后实机观察官方桌宠：可见宽约 60 pt，悬停工具条约 120×40 pt，轮廓铅笔图标约 15–16 pt，输入框约 322×42 pt，鼠标松开后首个约 120 ms 取样已基本展开。
- 参考截图包含用户界面内容，仅保存在被 Git 忽略的 `work/` 目录，没有进入仓库或源码包；去标识化测量结果冻结在 v2.1 基线。
- 桌宠实际使用官方 `codex-spritesheet-v4.webp`，待机、工作、完成和拖动时会切换对应动画行；解析时按 alpha 像素过滤每行动作末尾的透明空帧，断网且无缓存时保留矢量后备形象。
- v2.1 对运行中桌宠连续采样 18 帧，非透明像素数稳定在 9,576–9,613，未出现机器人整帧消失造成的闪烁。
- Release 应用的桌宠窗口背景透明，无外围矩形边框；铅笔按钮和输入条使用轻量系统材质、动态颜色和自然阴影。
- 根据用户反馈与官方界面同屏比较后，桌宠缩至 52×56 pt、透明承载窗口缩至 96×96 pt、铅笔缩至 28 pt；输入条为 360×50 pt，完成卡为 410×66 pt，回答工具栏按钮为 24 pt，关键图标本体均略小于官方参考。
- 铅笔现在是切换动作：首次点击让输入条从桌宠附近横向展开，再次点击以反向过渡收起；`Esc` 也可关闭输入条。
- 输入/状态出现时铅笔入口会被直接替换，面板覆盖原入口区域并紧贴桌宠；实测输入条在约 100 ms 取样时已经可输入。
- 迷你输入条、思考卡、完成卡、向下回答面板和向上回答面板均完成真实窗口截图检查。
- 用户消息为系统强调色蓝色气泡和白字；回答使用 Codex 风格系统字体、间距、Markdown 和代码块。
- 拖动桌宠约 `(-150,+179)` pt 时窗口移动约 `(-153,+187)` pt，误差仅来自 2 pt 拖动阈值；松手后可继续正常点击。
- `⌥⇧Space` 已用系统级键盘事件实测：可隐藏和再次打开迷你输入条，且不与 Codex 官方 `⌥Space` 默认入口冲突。

## 真实 Codex 请求与面板交互

- Release 应用成功使用现有 ChatGPT 账号启动本机 Codex App Server，无 API Key。
- v2.0 验证线程：`01a0a45b-f05d-77d1-b81c-090263a3ad28`。
- v2.1 视觉验证线程：`01a0a47f-0c47-70e3-8ca6-e80ad8504e80`。
- 首轮真实请求“用一句话回答：2+2等于几？”返回“2+2等于4。”；PinChat 依次显示工作动画、思考卡和完成卡。
- 回答面板成功展示当前问答，用户消息外观和最终回答无重复。
- 在回答面板内继续追问“再只回复：FOLLOWUP_OK”，同一线程返回 `FOLLOWUP_OK`；从 Codex 读取确认两个回合均为 `completed`，最终代理消息阶段均为 `final_answer`。
- 回答面板已验证单独拖动后从“已吸附”切换为“自由窗口”，并成功从 400×300 缩放到 520×420。
- 修复了回答面板展开动画被误判为用户拖动的问题；v2.1 首次展开实测显示“已吸附”。
- 桌宠位于屏幕上部时，状态卡及回答面板向下展开；拖至屏幕底部时，状态卡和回答面板自动改为向上展开。
- 拖动桌宠时，仍吸附的状态卡同步跟随；回答面板重新折叠再展开后恢复智能吸附。

## Codex 交接实测

- 从完成卡真实触发 `↗` 后，PinChat 先取消线程订阅并终止自己启动的 App Server 子进程，再打开深链。
- 交接后，PinChat 只保留 140×144 桌宠窗口，状态卡和回答面板关闭；本地当前会话切换为 `codexThreadID = null`、消息数为 0 的新空白任务。
- 使用 Codex 任务读取接口确认目标线程状态为 `idle`，两个真实回合及回答完整保留，可在 Codex 中继续。
- 再次点击 PinChat 铅笔后，新的 App Server 子进程按需启动，同时没有重新占用已交出的线程。

## 安全与边界

- PinChat 继续采用 `approvalPolicy = never` 与 `sandbox = read-only`；工具执行、文件修改和审批交由 Codex 主应用。
- 仓库和应用包不内嵌官方 WebP 二进制素材；运行时优先读取 Codex 缓存，其次读取 PinChat 缓存或下载官方资源。
- PinChat 不修改 Codex 官方桌宠和应用设置；用户可自行关闭官方桌宠以避免两个入口重叠。
- 全屏置顶指普通 macOS 全屏 Space，不包括锁屏、登录界面、系统安全窗口或受保护 DRM 画面。
- 本轮不含语音、附件、其他 AI API、Developer ID 签名、公证或 App Store 上架。

## 官方依据

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex Authentication](https://learn.chatgpt.com/docs/auth)
- [Codex Pricing](https://learn.chatgpt.com/docs/pricing)
- [Codex Pets](https://learn.chatgpt.com/docs/pets)
