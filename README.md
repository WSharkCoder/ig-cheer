# IG 应援

一个只为 Invictus Gaming 打 Call 的 macOS 菜单栏小工具。

左键点菜单栏图标打开应援面板；右键打开设置菜单。支持纵向与横向两种布局，可在菜单中随时切换。

<p align="center">
  <img src="docs/panel-vertical.png" width="440" alt="纵向界面"><br>
  <img src="docs/panel-horizontal.png" width="800" alt="横向界面">
</p>

> 预览图为透明背景，不含本机路径或本地模型信息；其中赛程、我的预测和 AI 预测使用演示数据。

## 功能

- **每日点赞应援**：每天只能点一次；按钮完成后变为「今日已应援」。
- **应援日历与连续天数**：月历标出已应援日期，显示当前连续应援天数。
- **我的预测（手动）**：单独的手动模块，逐场选择合法比分（IG 在左）；选择即保存到本地，不请求模型，也不消耗 Token。每个选项都按该场 **BO1 / BO3 / BO5** 生成，确保比分与赛制一致。
- **AI 预测**：读取 IG 的世界赛赛程，调用已配置的 OpenAI 兼容或 Anthropic Messages 模型；面板展示模型型号，并逐场标注 **BO1 / BO3 / BO5**，比分按赛制校验（BO1 为 1:0，BO3 为 2:0/2:1，BO5 为 3:0/3:1/3:2）。只有点击「刷新预测」才请求。它和「我的预测」是两个独立模块，互不覆盖。
- **多套模型配置**：可同时保存 DeepSeek、OpenAI、Claude 和本地 OpenAI 兼容服务，随时切换；模型 ID 支持下拉建议、从服务商 `/models` 拉取，也可以手填。
- **零 Token 配置测试**：设置里的「测试连接」只请求 `GET /models` 元数据，不发送推理请求，不消耗 Token；可验证地址、TLS、鉴权和可用模型。
- **API Key 加密存储**：Key 使用 AES-GCM 加密后写入本地配置文件；输入框不调用系统安全输入控件，不读取系统钥匙串，不会弹 Mac 密码。本地无鉴权服务可以留空 Key。
- **官网赛程同步**：附带抓取脚本，从 lolesports.com 公共赛程页提取 IG 比赛。
- **金句配置**：金句从纯文本文件读取，改完重新打开面板即可生效。
- **纯菜单栏应用**：`LSUIElement`，不显示 Dock 图标；面板 20 秒自动收起，点空白处立即收起。

## 界面与交互

### 纵向

适合快速看一眼今日金句、应援状态和下一场赛程。

- 头像、`IG 加油，冲冲冲！` 与状态行。
- 「今日金句」支持轮播与「换一句」；与下方点赞卡之间留出更明显的间距。
- 每日一次「点赞应援」。
- 月历、连续天数、我的预测、AI 预测和赛程纵向展开。我的预测和 AI 预测都以独立卡片展示；我的预测可逐场选择比分，AI 预测单独展示模型结果。
- 内容超过面板可视高度时，面板内部支持上下滑动；滚动不会打断自动收起计时。

### 横向

适合在桌面宽度下同时查看日历、预测和赛程。

- 日历与中间预测列上下边缘对齐，右侧赛程卡按内容自然高度展示；中间列上下分别是「我的预测」和「AI 预测」。
- 当前模型显示在 AI 预测卡顶部。
- 两张预测卡按较高一张对齐，只有一场待预测比赛时也不会出现上下错位。

右键菜单 →「展示模式」可切换，选择会记住。我的预测的选择会立即保存到本地，不触发模型请求；AI 预测卡底部的「刷新预测」与右键菜单的「刷新 AI 比分预测」等价。打开面板、切换模型、保存设置或刷新赛程都不会自动请求模型。

## 安装与构建

源码目录内执行：

```bash
./build.sh
```

脚本会编译、打包、ad-hoc 签名，并安装到：

```text
/Applications/IG应援.app
```

首次启动没有 Dock 图标，只在菜单栏出现。当前版本：`0.3.5`（build 17）。

## 模型配置与 API Key 安全

右键菜单 →「预测模型」→「模型配置…」。

每套配置包含：

- **显示名称**：面板 AI 徽章上展示的型号名，例如 `DeepSeek V3.2`。
- **API 格式**：`OpenAI 兼容` 或 `Anthropic Messages`。切换格式会自动填入对应的默认 Base URL 和常用模型。
- **模型标识**：请求体中的 `model`。下拉里是可编辑的建议列表，也可以直接输入任意 ID。
- **Base URL**：接口根地址，通常以 `/v1` 结尾。
- **API Key / Token**：可选；保存时加密。输入框是普通文本框，不触发 macOS 的 Passwords 自动填充或钥匙串授权。
- **测试连接**：只请求 `GET /models`，验证连接与鉴权，不消耗 Token。
- **设为当前预测模型**：预测时使用这一套配置。

设置页采用紧凑编辑：字段说明放在 **Hover** 提示里，底部两段常驻说明不再展示；API 格式、获取模型和测试连接也各有悬停说明。

模型配置窗口在切换到浏览器或其他 App 时会保持打开，并浮在普通窗口上方，方便复制 Token；只有标题栏左上角的关闭按钮会关闭它。所有输入框支持标准的 `Cmd+C` / `Cmd+V` / `Cmd+X` / `Cmd+A` / `Cmd+Z`。

### 两种 API 格式

| 格式 | 预测请求 | 鉴权 | 模型列表 |
| --- | --- | --- | --- |
| OpenAI 兼容 | `POST {BaseURL}/chat/completions` | `Authorization` 头，`Bearer` 前缀 + Key | `GET {BaseURL}/models` |
| Anthropic Messages | `POST {BaseURL}/messages` | `x-api-key` + `anthropic-version: 2023-06-01` | `GET {BaseURL}/models?limit=100` |

Anthropic 格式使用顶层 `system` 字段和必填的 `max_tokens`；回复从 `content[].text` 读取。两种格式都强制 JSON 输出，并兼容常见的代码块包裹。

DeepSeek 的 Anthropic Base URL 是 `https://api.deepseek.com/anthropic`；填 OpenAI 根地址 `https://api.deepseek.com` 时，App 会自动补上 `/anthropic`。DeepSeek V4 默认开启思考模式，比分请求会显式关闭 `thinking`，避免推理内容占满输出上限、导致 JSON 被截断。

### AI 请求与 Token 策略

预测请求只在用户点击「刷新预测」（或右键「刷新 AI 比分预测」）时发出；打开面板、切换模型、保存设置、刷新赛程都不会请求模型。

每次最多请求 3 场待赛，提示词只保留必要字段：

```text
system: Predict the LoL series score for IG. Input lines: index|opponent|BO|date. BO is 1, 3, or 5.
         Reply with JSON only: {"p":[{"m":0,"s":"3-1","c":64}]}
         s = IG score-opponent score, valid for the BO: winner reaches 1/2/3 wins for BO1/3/5.
         c = IG win probability 0-100. No markdown, no explanation.
user:   IG matches:
        0|TES|BO5|11-04
```

- 用索引代替比赛 UUID，避免模型回显长 ID，也减少输入/输出 token。
- 日期只发 `MM-dd`，BO 发 `BO1` / `BO3` / `BO5`，中文赛段与 ISO 时间不再重复发送。
- 输出上限固定为 `max_tokens: 256`，`temperature: 0.2`；预期只需一个短 JSON。
- 返回结果按索引回填到本地赛程，界面仍显示完整的对手、阶段和日期。
- **比分校验**：解析时要求胜者赢下 `(BO+1)/2` 局（BO1=1、BO3=2、BO5=3），败者小于该值；非法比分（例如 BO5 的 2:1）会被丢弃，避免缓存把错误赛制带到面板。

### 获取模型列表

点「获取模型」后，App 才会请求当前 Base URL 的 `/models`：

- 成功时把返回的 `data[].id` 填入可编辑下拉，按字母排序。
- 失败时保留内置常用列表，不会阻塞手填。
- 列表请求与预测请求是分开的，Key 不会因为打开设置窗口而发出。
- 远程服务（例如 DeepSeek）的 `/models` 需要鉴权；未填 Key 时 App 会保留内置模型建议并提示，不会发送无鉴权请求。

### 配置测试：零 Token 连通性检查

设置窗底部有「测试连接」。它只发送一次：

```http
GET {Base URL}/models
```

不会发送 `/chat/completions` 或 `/messages`，不会生成内容，也不消耗 Token。适合在保存配置前确认地址、TLS、鉴权和模型列表是否可用。

| 方案 | 消耗 Token | 能验证什么 | 本项目是否采用 |
| --- | --- | --- | --- |
| `GET /models` | 否 | 地址、TLS、鉴权、可用模型 | ✅「测试连接」 |
| `HEAD` / `GET` Base URL | 否 | 只能确认网络可达，不能验证 Key | 作为 404 时的提示 |
| `POST /chat/completions` + `max_tokens: 1` | **是** | 完整推理链路 | ❌ 不用 |
| Anthropic `count_tokens` | 不保证免费 | 只统计 token，不验证生成 | ❌ 不用 |

结果提示：

- **连接正常**：显示模型数量和延迟，并标注「未消耗 Token」。
- **401 / 403**：鉴权失败，Key 无效或权限不足。
- **404**：网络可达，但该服务没有 `/models`。此时不发送推理请求就无法继续验证 Key；App 会明确提示，而不会偷偷发一次付费请求。
- **本地服务**：`localhost` / `127.0.0.1` / `::1` 可以留空 Key，直接测试 `/models`。
- **远程服务未填 Key**：直接提示，不发送无鉴权请求。

> 零 Token 的前提是服务商提供免费的模型列表接口。OpenAI 兼容服务、Anthropic 和 Ollama 的 OpenAI 兼容端点通常满足；若服务商没有该接口，用任何「最小推理」方式测试都会产生 Token 费用，因此这里选择不自动回退。

### 本地模型示例

本地 OpenAI 兼容服务可以直接作为预测模型，Key 留空即可。以 Ollama 为例：

```bash
ollama serve
ollama pull qwen2.5:7b
```

配置：

```text
API 格式    OpenAI 兼容
Base URL   http://127.0.0.1:11434/v1
模型标识    qwen2.5:7b
API Key    留空
```

LM Studio、vLLM、llama.cpp server 等只要暴露 OpenAI 兼容的 `/v1` 端点，也可以按同样方式填写。App 识别 `localhost` / `127.0.0.1` / `::1` 为本地端点，允许在没有 Key 的情况下发预测请求。

### 加密方式

- API Key 使用 **AES-GCM** 加密，`models.json` 中只保存密文。
- 256 位本地主密钥保存在 `~/Library/Application Support/IGCheer/.model-key`，权限 `0600`。
- **不访问 macOS 钥匙串**，保存或读取 Key 都不会弹系统密码。
- API Key 输入框是普通 `NSTextField`，不使用 `NSSecureTextField`，因此不会出现 macOS 的 Passwords 自动填充/钥匙串授权菜单。
- 这是本地文件级加密：防护目标是避免 Key 明文出现在 `models.json`；同一台 Mac 的同一用户仍可读取主密钥。
- 配置文件权限设置为 `0600`。
- 支持多套配置并存；切换模型不会覆盖已有 Key。
- 本地无鉴权的 OpenAI 兼容服务可以留空 Key；远程服务必须配置 Key。
- 如果你之前保存过旧版 Key，升级后需要重新填写一次；新保存的 Key 使用 `v2.` 密文。

配置默认保存在：

```text
~/Library/Application Support/IGCheer/models.json
~/Library/Application Support/IGCheer/.model-key   # 本地主密钥，0600
```

## S16 赛程同步

脚本通过 lolesports.com 的公开赛程页提取内嵌的比赛数据，不依赖 API Token：

```bash
python3 tools/fetch_schedule.py
```

默认输出：

```text
~/Library/Application Support/IGCheer/schedule.json
```

常用参数：

```bash
python3 tools/fetch_schedule.py --print              # 只打印，不写文件
python3 tools/fetch_schedule.py --team IG --league worlds
python3 tools/fetch_schedule.py --out /tmp/ig.json   # 自定义输出路径
```

应用内也可以右键 →「刷新赛程（官网）」直接同步。脚本使用 Python 标准库，无需安装第三方依赖。

## 每日应援数据

每日点赞记录保存在：

```text
~/Library/Application Support/IGCheer/cheer.json
```

只记录日期键（如 `2026-11-01`），用于绘制月历和计算连续天数；同一日期重复点击不会增加记录。

## 我的预测数据

手动选择的比分保存在独立的文件：

```text
~/Library/Application Support/IGCheer/my-predictions.json
```

只记录 `matchID`、`igScore`、`opponentScore` 和更新时间。它与 AI 预测缓存 `predictions.json` 完全分离，点击「刷新预测」不会覆盖手动比分。

## 金句配置

金句从纯文本读取：

```text
~/Library/Application Support/IGCheer/quotes.txt
```

首次启动自动创建。每行一句，空行和 `#` 开头的注释行会被忽略；用 `|` 强制换行，例如：

```text
天不生TheShy，|LPL上单万古如长夜
```

右键菜单 →「打开金句配置…」可直接打开文件。文件为空或读取失败时回退到内置 6 句。

## 项目结构

```text
ig-cheer/
├── Sources/
│   ├── main.swift              # 菜单栏、窗口与菜单
│   ├── Models.swift            # 配置、加密、日历、赛程、预测数据
│   ├── PredictionClient.swift  # OpenAI / Anthropic 比分预测
│   ├── ModelCatalogClient.swift  # 从服务商 /models 拉取模型
│   ├── PanelWebView.swift      # 本地面板 WebView 宿主
│   ├── SettingsView.swift      # 模型配置窗口
│   ├── panel.html
│   ├── panel.css
│   └── panel.js
├── assets/                     # 运行时资源
├── artwork/                    # 原始插画素材
├── docs/                       # README 预览图
├── tools/
│   ├── fetch_schedule.py       # 无 Token 官网赛程抓取
│   ├── make_assets.swift       # 抠图 + App 图标
│   ├── make_bust_gray.swift    # 菜单栏灰阶半身图标
│   ├── make_avatar.swift       # 面板白灰头像
│   └── regenerate.sh           # 一键重新生成图标资源
├── build.sh
└── README.md
```

`build/` 是构建临时目录，不纳入源码。

## License

代码以 [MIT License](LICENSE) 开源。

IG 名称、标识与僵尸插画版权归各自权利人所有，不在 MIT 授权范围内；仓库中的相关图片仅用于构建和展示这个个人应援项目，详见 [NOTICE.md](NOTICE.md)。
