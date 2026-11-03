# CampusLens（拾讯）

HarmonyOS NEXT 原生校园任务应用。《开源 AI 技术实践》路径 B：保留 ArkUI、SQLite、通知识别和系统日历，在现有应用中增加真实 Tool Calling 协议的智能助手。

**当前验收边界：代码已实现，构建及自动化测试通过；真实 DeepSeek 工具选择与结果回传已验证，模拟器中的完整业务流程尚未验收。** 本地规则识别和自动化测试中的模拟模型均不算真实大模型。

## 架构与目录

```text
entry/src/main/ets/
  pages/AIPage.ets                 智能助手、工具过程和原有文字/OCR入口
  pages/AnalysisResultPage.ets     编辑草稿、人工确认保存
  pages/TaskPage.ets               原有任务列表、编辑、日历操作
  pages/HomePage.ets               原有首页整理
  repositories/TaskRepository.ets  SQLite 持久化
  services/AgentService.ets        多轮模型工具协议及调用上限
  services/TaskToolExecutor.ets    白名单、参数校验、业务分发
  services/TaskQueryService.ets    查询和统计口径
  services/TaskDraftService.ets    内存草稿及确认状态
  services/AIService.ets           原有规则识别 + 网关 HTTP 客户端
  common/AgentConfig.ets           网关地址，绝不存放模型 Key
  common/DateTimeUtils.ets         中国时区严格日期校验
entry/src/ohosTest/                Hypium 与真实 SQLite 验证
server/src/                       Node.js 模型网关与工具 schema
server/test/                      网关 HTTP 协议测试
scripts/test-agent.mjs            实际业务源码的主机测试
```

流程：自然语言 → 原生客户端 → 本机网关 → DeepSeek 返回 tool_calls → 客户端校验并执行真实业务 → 将结果作为 role=tool 回传 → 模型中文回复。网关持有模型密钥；数据库在设备内。没有通过关键词判断用户意图来冒充模型选择工具。

| 工具 | 数据和副作用 |
|---|---|
| query_tasks | 读取真实 SQLite，支持状态、截止/活动时间范围、分页 |
| get_task_statistics | 读取完整数据库快照后统计，不使用分页结果计算 |
| create_task_draft | 仅生成内存草稿，用户进入确认页并保存后才写数据库 |

未完成 = 总数 − 已完成，包含已过期；即将到期 = 当前时间至未来 N 天（默认 7 天，两端包含），有截止时间且未完成的任务。活动时间不替代截止时间。首页仍沿用原有活动分组展示，不应把首页卡片数量当作该统计口径。日期格式统一 `YYYY-MM-DD HH:mm`，Asia/Shanghai，拒绝无效日期及结束早于开始。

模型没有删除、完成、直接创建数据库记录或操作日历的工具。草稿可取消、30 分钟过期，确认保存有重复提交保护；进程退出不保留未确认草稿。会话最长 4 次模型请求、8 次工具调用，每轮最多生成一个草稿。新会话取消待确认草稿。

## 运行环境

本机已验证：Windows、DevEco Studio，SDK API 26（26.0.0.105），项目 compatible/target 26.0.0，Node.js 24.14.1。本项目使用系统 NetworkKit、ArkData 和日历/OCR 能力；模块声明 INTERNET 权限。网关使用 Node.js 内置模块，无额外 npm 依赖，要求 Node.js 22 以上。

### 启动网关

在项目根目录复制 `.env.example` 为 `.env`，只在本机编辑 `LLM_API_KEY`。不要把 Key 发到聊天或放入应用配置。

```powershell
Copy-Item .env.example .env
# 使用编辑器填写 .env，勿将密钥作为命令行参数。
cd server
npm start
```

如果未配置 Key，网关可以启动，但模型请求返回明确的 503 错误。`GET http://127.0.0.1:3000/health` 仅返回配置状态，不返回 Key。`LLM_MODEL` 可按 DeepSeek 账户实际可用模型修改；默认模型已通过真实工具选择请求验证。

默认只监听本机 `127.0.0.1:3000`。需要对外监听时必须设置至少 24 字符的 `GATEWAY_TOKEN`，部署 HTTPS，并在应用的连接设置输入网关凭据；该凭据不是模型 Key。当前网关适合个人演示，不是多用户生产服务。

### 构建与模拟器

在 DevEco Studio 打开项目，同步依赖，启动 API 26 模拟器后运行 entry。当前签名配置为空；本机模拟器已接受 unsigned HAP，真机须另行配置自己的签名文件，不能提交证书和密码。

本机命令行构建（其他电脑修改安装路径）：

```powershell
$env:DEVECO_SDK_HOME='D:\devecostudio\DevEco Studio\sdk'
$env:JAVA_HOME='D:\devecostudio\DevEco Studio\jbr'
$env:NODE_HOME='D:\devecostudio\DevEco Studio\tools\node'
$env:PATH="$env:JAVA_HOME\bin;$env:NODE_HOME;$env:PATH"
& 'D:\devecostudio\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

让模拟器访问电脑上的网关：

```powershell
$hdc='D:\devecostudio\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc list targets
& $hdc -t 127.0.0.1:5555 rport tcp:3000 tcp:3000
& $hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-unsigned.hap
& $hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.example.campuslens
```

目标地址以 `list targets` 实际输出为准。在 AI 页选择智能助手，网关保持 `http://127.0.0.1:3000`。本地 HTTP 仅允许回环地址；远程地址使用 HTTPS。应用中可展开真实调用参数和结果。未配置模型时不会静默回退为关键词识别。

## 保留功能及边界

原有任务增删改查、完成状态、SQLite、首页和个人页保留。原有本地通知解析仍为规则模式，界面独立于智能助手。图片使用系统 OCR；内置样例在 OCR 不可用时可能返回预置样例文字，不能当作真实 OCR 验收。真实照片不会用样例文字冒充识别。系统日历仍需权限，支持原有同步/清理操作，不是双向同步。

默认不再自动填充演示数据；已有记录不清除。`AgentConfig.seedDemoOnEmpty` 仅用于需要时显式开启旧样例。学习计划和联网搜索未实现，避免扩张范围。

## 测试

```powershell
& 'D:\devecostudio\DevEco Studio\tools\node\node.exe' --test scripts/test-agent.mjs
& 'D:\devecostudio\DevEco Studio\tools\node\node.exe' --test server/test/gateway.test.mjs
```

业务测试使用 DevEco 随附 TypeScript 转译器执行实际非 UI 源码，注入模拟存储和模型；可通过 `TYPESCRIPT_PATH` 指向其他本地 TypeScript 包。ArkTS 兼容性由真实 HAP 编译验证。

设备测试：构建命令追加 `-p module=entry@ohosTest`，安装 `entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap` 后运行：

```powershell
& $hdc -t 127.0.0.1:5555 shell aa test -b com.example.campuslens -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000
```

必须检查 Hypium 的 Pass/Failure/Error 汇总，不能仅凭进程退出码判断。SQLite 测试只清理自己创建的记录，保留已有数据。详情见 [测试报告](TEST_REPORT.md) 和 [演示流程](DEMO.md)。

## 密钥与数据保护

`.env`、构建目录和签名文件已加入忽略规则。`.env.example` 只有空值；服务端从环境变量读取模型 Key，应用只保存网关地址和运行时访问凭据。不要将 `.env` 复制到 entry、资源目录、HAP 或日志中。启动网关时使用环境文件，不在命令行传 Key。

忽略规则不能清除已经提交的秘密。提交前检查 `git diff --cached` 与历史；若曾提交真实密钥，应立即撤销/轮换，再按仓库协作情况清理历史。本次没有提交 Git，也没有发布仓库。

用户输入和必要工具结果会经网关发送给模型供应商；演示使用非敏感任务，不输入个人隐私。网关错误不回显供应商响应体或密钥。网关有请求大小、并发、超时与频率限制；任务内容始终作为数据，不能获得额外工具权限。

项目介绍幻灯片：[离线 HTML](docs/slides.html)，支持方向键翻页和打印。
