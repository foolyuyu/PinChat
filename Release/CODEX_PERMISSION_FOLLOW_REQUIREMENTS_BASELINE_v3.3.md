# PinChat v3.3 Codex 权限跟随需求基线

状态：已冻结  
版本：3.3  
日期：2026-09-17（Asia/Shanghai）

## 1. 产品定位

PinChat 是本机 Codex 的置顶输入与回答扩展，不是另一套 AI 应用。账号、额度、模型、人格、推理设置以及任务权限均以本机 Codex 为准，PinChat 不建立相互竞争的第二套权限状态。

## 2. 权限来源

- PinChat 只读解析 `~/.codex/.codex-global-state.json` 中 Codex Desktop 为 `local` host 保存的权限选择。
- 优先读取 `permission-selection-by-host-id:local`；兼容读取 `agent-mode-by-host-id.local`。
- 支持 Codex 的只读、询问批准、自动审查、完全访问、服务器默认和命名权限配置。
- 若状态文件暂时不可读或格式变化，保留最近一次有效值；首次无法解析时交由 Codex App Server 使用默认配置，不自行扩大权限。
- PinChat 不写入或修改 Codex 的全局状态、配置文件或权限配置。

## 3. 发送与同步

- 输入框每次展开及每次发送前刷新 Codex 当前权限。
- 新建任务、恢复既有 PinChat 任务、每轮 `turn/start` 和交接前恢复均使用同一份刷新后的权限。
- 完全访问对应 `approvalPolicy = never`、`sandbox = danger-full-access`，并在 `turn/start` 使用 `sandboxPolicy.type = dangerFullAccess`。
- 询问批准与自动审查使用工作区写入边界；自定义权限直接传递 Codex 保存的权限配置 ID。
- Codex 主应用修改权限后，PinChat 无需重启；下一次提问自动采用新设置。

## 4. 界面

- 输入框只保留附件入口、文本输入与发送/停止按钮，不显示 PinChat 独立权限按钮。
- 设置页只读展示“当前 Codex 权限（跟随）”，不提供另一套选择器。
- 仅当 Codex 当前权限实际产生审批请求时，回答窗口才显示审批卡。
- macOS 对桌面、文稿、照片、其他应用数据或完全磁盘访问的系统授权不属于 Codex 审批；PinChat 不伪装、绕过或反复代替系统授权。

## 5. 验收标准

- 本机 Codex 选择完全访问时，PinChat 的新任务和继续提问均落盘为 `approval_policy = never` 与 `sandbox_policy.type = danger-full-access`。
- 完全访问下执行工作区外普通文件命令不会产生 Codex `requestApproval`。
- Codex 切换为询问批准后，PinChat 下一次发送自动使用 `on-request + workspace-write`。
- 输入框无权限图标，设置页无权限 Picker。
- 原有审批协议保持兼容，用于 Codex 当前配置确实要求用户决定的情况。
- 自动测试、Release 构建、签名、需求哈希及实际启动验证全部通过。

## 6. 边界

- 本版不修改 Codex 主应用，不注入进程，不读取浏览器 Cookie，不接其他 AI API。
- 本版不承诺绕过 macOS TCC、完全磁盘访问、系统安全窗口、管理员策略或组织策略。
- 本版不更改 v1.0 至 v3.2 已冻结需求文件；冲突处以本 v3.3 增量基线为准。
