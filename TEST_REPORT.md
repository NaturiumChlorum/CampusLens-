# CampusLens 改造测试报告

更新时间：2026-10-29。所有通过结论对应实际执行；模型测试替身不算真实 DeepSeek 调用。

## 阶段与证据

| 阶段 | 实际工作及检查 | 结果与限制 |
|---|---|---|
| A 基线 | 备份原有 10 个未提交文件；使用本机 DevEco/Hvigor 构建 | 基线成功，日志 `.test/agent-baseline-build.log`；未重置或提交 Git |
| B 业务工具 | 新增 TaskQueryService、TaskToolExecutor、TaskDraftService、日期及模型类型；复用 Repository | 主机测试 13/13，通过查询、完整快照统计、校验、取消、确认与重复提交测试；存储使用测试替身 |
| C 模型网关 | 新增 server/src 和 server/test，AIService 增加 HTTP 模型客户端 | HTTP 测试 5/5；验证工具 schema、结果关联、鉴权和错误隐藏；上游为测试替身 |
| D 原生接入 | AIPage、AnalysisResultPage、TaskPage、INTERNET 权限；保留旧功能 | 编译通过；模拟器实际请求显示未配置 Key，见 `.test/campuslens-error.json`；未进行真实模型成功路径 |
| E 编译与设备 | 最终主 HAP 编译；Hypium 实际设备数据库测试 | 最终构建成功 1 分 13.404 秒；设备测试 5/5（既有测试及新 SQLite 测试） |
| F 交付文档 | README、DEMO、环境示例、忽略规则、本报告及 HTML 幻灯片 | 已写明启动、演示、安全配置和未验收范围 |

## 执行环境与日志

- Windows，DevEco 安装路径 `D:\devecostudio\DevEco Studio`，Node 24.14.1。
- SDK 26.0.0.105；API 26 模拟器 `127.0.0.1:5555`。
- 最终主构建日志：`.test/agent-final-build.log`，BUILD SUCCESSFUL。
- 设备测试构建：`.test/agent-device-test-build.log`，BUILD SUCCESSFUL。
- 设备测试：`.test/agent-device-test-run.log`，Tests run: 5, Failure: 0, Error: 0, Pass: 5。
- 主机复核：`node --test scripts/test-agent.mjs`，13 pass / 0 fail。
- 网关复核：`node --test server/test/gateway.test.mjs`，5 pass / 0 fail。

主机测试执行实际业务源文件的转译结果；ArkTS 语法和原生依赖由 Hvigor 验证。SQLite 测试通过启动 Ability 获取真实上下文，验证查询、统计、取消不写库、确认写库、拒绝重复确认和清理自己的测试记录。该测试不是完整 UI 点击测试。设备测试执行后，最终修改仅补充客户端历史调用 ID 检查及界面顶部对齐；最终主构建和主机测试已重新运行。

## 发现并修复的问题

- 首次集成编译遇到 ArkTS 构造参数属性、名义类型接口和异常重抛限制，已修正并重新编译通过。
- 设备测试初始使用应用上下文无法打开 RDB，后改为等待真实 Ability 上下文，最终 5 项通过。
- 截止时间未进入确认/编辑保存链路、宽松日期解析、保存重复点击等影响演示的问题已处理。
- 统计不会将数据库异常当作空数据；模型不能绕过白名单直接保存任务。
- 日历清理检查实际返回结果，部分失败不冒充全部成功。

## 安全及已有修改保护

- `.env` 和 `.env.local` 的 Git 忽略检查通过，`.env.example` 可跟踪。
- 检查最终 HAP ZIP 条目，未包含 `.env` 或 server 目录。
- 当前没有配置真实模型 Key。本次没有 Git commit、推送或公开仓库。
- HomePage、Index、ProfilePage、原 LocalUnit.test 与最初备份逐项 SHA256 一致；其余原有文件是在既有改动上叠加实现。
- `git diff --check` 通过；仅有 Windows 换行提示。原有测试未删除。

## 尚未验收

1. 真实 DeepSeek Tool Calling 成功链路：等待用户自行配置服务端 Key，再按 DEMO.md 验证；模型名、账户权限和余额届时确认。
2. 模型生成草稿后，通过完整 UI 保存/取消并再次查询的现场流程，尚未完成真实模型验收。
3. 真实照片 OCR、日历授权/同步/清理的完整设备回归；保留代码不等于所有设备能力已验收。
4. 真机签名与安装：本轮目标是模拟器，项目尚无 signingConfigs。
5. 编译仍有 deprecated router / AlertDialog、可能抛异常等警告；不宣称零警告。

HTML 幻灯片可离线打开；使用方向键翻页或打印。未取得模型 Key 不影响离线测试，但课程要求的真实智能体演示仍未完成，不能用模拟结果替代。

最终安装复核：2026-10-29 尝试覆盖安装最终 HAP，hdc 返回 Not match target founded，原设备连接已失效。最终 HAP 已编译成功，但需重新启动/连接模拟器后安装复核，不能沿用此前安装成功的结论。HTML 已完成源文件检查，尚未完成逐页浏览器视觉验收。

## 最新真实连接检查（2026-10-29）

已检测到用户配置模型 Key，并将其从可跟踪的 .env.example 移至被忽略的根目录 .env；示例中的 Key 已清空，检查过程未输出密钥。此项取代上文“尚无 Key”的历史状态。

首次通过实际网关向 DeepSeek 官方接口发起查询请求时返回 HTTP 402（余额不足）。用户充值后重新验证，三次真实模型请求分别返回 query_tasks、get_task_statistics、create_task_draft 的 tool_calls，工具名与参数符合预期。随后将明确标记为测试数据的工具结果逐一按 tool_call_id 回传，模型给出中文回复；这验证了供应商协议，未读取设备数据库，也未保存任务。模型在统计测试中把测试数据表述为“设备真实统计”，因此不能把该回复作为真实业务结果证明；正式验收须查看应用执行轨迹与真实 SQLite 数据。最近一次 hdc list targets 仍为 Empty，模拟器端到端流程待设备连接后完成。

## 2026-11-01 真实业务入口复核

`.test/live-roundtrip.mjs` 是测试数据来源，只用于模型协议验证。正式入口由 `AgentRuntime` 创建 `AgentService(new RemoteAIService(), new TaskToolExecutor(), TaskDraftService.getInstance())`。`TaskToolExecutor` 的查询和统计均调用 `TaskRepository.getAllTasks()`，再分别筛选和计算完整集合；`create_task_draft` 只建立内存草稿。确认页调用 `TaskDraftService.confirm()` 才执行 `TaskRepository.createTask()`。

本轮运行 `node --test scripts/test-agent.mjs`，13/13 通过；运行 Hvigor `assembleHap --mode module -p product=default -p buildMode=debug --no-daemon`，BUILD SUCCESSFUL，日志 `.test/agent-nov1-build.log`。历史模拟器 Hypium 结果为 5/5，通过时间早于本轮。`hdc list targets` 本轮仍为空，故不能声称已完成真实模型与设备 SQLite 的端到端验收。本轮未修改 Agent 实现或覆盖原有未提交改动。

## 2026-11-02 AI 页面整合

核对 `Index.ets` 后确认手机端和桌面端均已有四个导航项，没有新增第五个 Tab；造成独立聊天页观感的是 `AIPage.ets` 内部默认展示的助手/通知双模式和第二个输入框。本轮只修改 `AIPage.ets`：移除内部模式切换和第二输入框，让原通知输入区同时提供“智能处理”入口；保留原本地规则解析、OCR、桌面布局和确认页。Agent 结果在同页显示，工具记录默认收起，连接设置仍可展开。`AgentService`、`TaskToolExecutor`、DeepSeek 网关和 Repository 均未改动。

检查：Hvigor HAP 构建成功（`.test/agent-ui-nov2-build.log`）；业务主机测试 13/13 通过；`git diff --check` 通过。`hdc list targets` 无设备输出，本轮未做模拟器视觉及端到端复验。

## 2026-11-02 AI 页面第二轮调整

本轮仅修改 `AIPage.ets` 与 `ProfilePage.ets`，原四 Tab 导航、OCR、本地通知识别、确认页和 Agent 后端保留。AI 页面不再显示聊天气泡或清除会话按钮；原统一输入区配有“查询任务”“任务统计”快捷填词和“智能处理”按钮。快捷词仍须送至 DeepSeek，由模型选择工具。结果区从实际 `ToolExecution` 数据展示查询任务条目、统计值或待确认草稿，多工具结果可并列显示；模型中文回复作为补充。工具详情默认折叠。网关连接设置移入“我的 → 偏好设置”。

对比依据：旧版模拟器截图 `.test/campuslens-ui.png` 可见独立助手模式、双模式按钮、连接设置和新会话按钮；新版因 `hdc list targets` 为空，尚无真实设备截图，以上新版描述来自源码与 HAP 编译，不冒充视觉验收。最终 Hvigor 构建日志 `.test/agent-ui-final-build.log` 为 BUILD SUCCESSFUL；主机业务测试 13/13 通过，`git diff --check` 通过。
