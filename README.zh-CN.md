# Agent Island

[English](README.md)

Agent Island 是面向 macOS 的 AI Agent 运行状态灵动岛。它区分 Codex、Claude
Code、Claude Desktop、Claude Science、ChatGPT、终端与网页会话，重点回答：谁真
正在工作、谁已完成、谁在等待人类审批或输入，以及如何点击回到对应窗口。

## 一键安装

系统要求：macOS 13 或更高版本。GitHub Release 提供同时支持 Apple Silicon 和
Intel Mac 的通用应用包。

在“终端”中运行：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Lando-C/agent-island/main/scripts/install)"
```

安装器会自动：

1. 获取最新的非草稿 GitHub Release。
2. 下载 `Agent-Island-macOS.zip` 和 `SHA256SUMS`。
3. 校验 SHA-256，校验失败时拒绝安装。
4. 将应用原子替换到 `/Applications/Agent Island.app`，失败时恢复旧版本。
5. 备份并安装 Claude Code 与 Codex CLI 状态 Hooks。
6. 启动 Agent Island。

安装器不会开启自动审批。自动审批默认关闭，`Write`、`Edit`、`Bash`、删除、
`sudo`、强推等危险操作永远不会被默认自动批准。

先检查脚本再运行：

```bash
curl -fsSL https://raw.githubusercontent.com/Lando-C/agent-island/main/scripts/install \
  -o /tmp/agent-island-install
less /tmp/agent-island-install
bash /tmp/agent-island-install
```

可选参数：

```bash
# 安装指定版本
bash /tmp/agent-island-install --version v0.1.0

# 不改 Claude/Codex Hook 配置
bash /tmp/agent-island-install --no-hooks

# 安装后不自动启动
bash /tmp/agent-island-install --no-open
```

以后重复执行一键安装命令即可更新。

稳定版在发布到 Homebrew tap 后可通过以下命令安装：

```bash
brew install --cask Lando-C/tap/agent-island
```

## 手动下载安装

1. 打开 [GitHub Releases](https://github.com/Lando-C/agent-island/releases)。
2. 下载 `Agent-Island-macOS.zip` 和 `SHA256SUMS`。
3. 在两个文件所在目录执行：

   ```bash
   shasum -a 256 -c SHA256SUMS
   ```

4. 解压并将 `Agent Island.app` 移入 `/Applications`。
5. 稳定版会经过 Apple 公证；开发预览版仍可能需要按住 Control 点击 App，选择
   “打开”，再确认“打开”。
6. 打开 **Settings > Diagnostics**，安装 Hooks，并按需授予权限。

## 首次使用

1. 打开灵动岛菜单中的 **Settings...**。
2. 在 **Diagnostics** 查看 App、Hooks、Socket、事件流和终端能力状态。
3. 开启辅助功能权限后，Claude/Codex 等 App 才能精确跳到对应窗口。
4. 如果系统设置中的权限已开启但仍提示未授权，请删除旧的 Agent Island 条目，
   重新添加 `/Applications/Agent Island.app`，然后重启应用。
5. 缺少 tmux server、WezTerm、kitty、Warp、cmux 或 Kaku 只表示对应可选能力
   不可用，不代表 Agent Island 安装失败。

## 当前交互能力

- Claude Code 的 `PermissionRequest`、`AskUserQuestion`、`Elicitation` 可在岛内
  直接允许、拒绝或回答；支持多问题、多选项和自由文本。
- Codex Desktop 存在实时 `cxc-*/broker.sock` 时，可直接回答
  `requestUserInput` 及命令、文件、权限审批；broker 不可用或请求过期时会安全失败，
  保留 Codex 原生提示，不会假装提交成功。
- 点击会话行的对话按钮，可按需读取本地 Claude/Codex JSONL，查看用户消息、AI
  回复、工具调用和工具结果。多个详情窗口共享增量会话存储，只读取新追加的 JSONL
  内容，并合并 Hook 与 Codex broker 工具事件。
- 对应 App 或终端已在前台时，智能抑制只阻止自动大展开；状态更新、手动展开和
  通知计数不受影响。
- 长按刘海 0.35 秒并向下拖拽可进入独立离岛伴侣；点击会显示当前会话气泡，位置按
  显示器自动记忆，右键可回到刘海。
- 僵尸检测会同时核对 PID、命令链、准确 TTY 和 tmux pane；仅有 shell 或空 pane
  存活不会让已结束任务继续显示为工作中。
- 诊断页会显示 Hook Socket、Codex App Server、会话追尾、进程/TTY、tmux 等传输的
  连接状态、协议版本、最后成功时间与失败原因；也会显示终端跳转实际采用的精确/
  回退路径。
- 终端跳转支持 tmux、iTerm2、Terminal、Ghostty、WezTerm、kitty、cmux 等；
  cmux 支持 tab/terminal ID，WezTerm 会枚举多个 GUI socket。
- 每条状态会标明来源：实时 Hook、App 记录、App Server、网页桥接、进程探测或
  启发式。进程在线不会被伪装为已确认的工作中。

## 从源码安装

需要 Xcode Command Line Tools：

```bash
git clone https://github.com/Lando-C/agent-island.git
cd agent-island
scripts/test-swift
scripts/build-app
ditto "dist/Agent Island.app" "/Applications/Agent Island.app"
"/Applications/Agent Island.app/Contents/Resources/scripts/install-hooks" --all
open "/Applications/Agent Island.app"
```

## 诊断

应用内可以运行并复制诊断报告，也可以在终端执行：

```bash
"/Applications/Agent Island.app/Contents/Resources/scripts/agent-island-diagnostics"
```

生成可安全反馈的脱敏支持包：

```bash
"/Applications/Agent Island.app/Contents/Resources/scripts/agent-island-support-bundle"
```

该支持包不包含 `events.jsonl`、聊天记录、Hook payload、命令、session ID 或项目路径。

正常情况下，可选终端未安装或未运行会显示 `WARN`；真正阻止产品运行的问题才应
显示为 `FAIL`。

## 网页端 Bridge

Chrome/Chromium 可以加载可选的本地网页 Bridge，以显示 ChatGPT、Claude 和 Codex
网页会话的最小状态。它只监听 `127.0.0.1`，每台机器使用独立配对令牌，并且只发送
引擎名、页面派生会话键、标题、状态和 URL 路径，不读取或上传正文、提问、回复、
Cookie 或凭证。

1. 在 Agent Island 的 **Settings > Diagnostics** 点击 **Copy Web Bridge Token**。
2. 打开 `chrome://extensions`，开启开发者模式，选择“加载已解压的扩展程序”。
3. 选择仓库内 `extensions/agent-island-web-bridge`，或 App 内
   `Contents/Resources/WebBridgeExtension`。
4. 打开扩展选项页，粘贴令牌并保存。

网页 DOM 只能提供启发式信号，所以界面会明确标记为“网页桥接”，不会与 Hook 或
App transcript 的确认状态混为一谈。完整边界和移除方式见
[网页 Bridge 说明](docs/WEB_BRIDGE.md)。终端精确能力与回退策略见
[终端跳转矩阵](docs/TERMINAL_JUMP_MATRIX.md)。

## 卸载

先删除 Agent Island 自己的 Hooks，再删除应用。此操作会保留其他工具的 Hooks，
并先创建配置备份：

```bash
"/Applications/Agent Island.app/Contents/Resources/scripts/install-hooks" --uninstall
rm -rf "/Applications/Agent Island.app"
```

按需删除本地事件和日志：

```bash
rm -rf "$HOME/.agent-island"
```

## 隐私与安全

- 状态、事件和日志只写入本机 `~/.agent-island`。
- 不上传会话、对话、Hook payload 或诊断信息。
- Hook 配置写入前会创建 `.agent-island.bak`。
- 自动审批默认关闭，只读候选也必须由用户主动开启。
- 完整功能、已知边界和路线图见 [README.md](README.md)、
  [产品蓝图](docs/PRODUCT_BLUEPRINT.md) 和 [路线图](docs/ROADMAP.md)。
