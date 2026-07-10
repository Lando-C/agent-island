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

## 手动下载安装

1. 打开 [GitHub Releases](https://github.com/Lando-C/agent-island/releases)。
2. 下载 `Agent-Island-macOS.zip` 和 `SHA256SUMS`。
3. 在两个文件所在目录执行：

   ```bash
   shasum -a 256 -c SHA256SUMS
   ```

4. 解压并将 `Agent Island.app` 移入 `/Applications`。
5. 当前开发预览版尚未经过 Apple 公证。首次打开时请按住 Control 点击 App，
   选择“打开”，再确认“打开”。
6. 打开 **Settings > Diagnostics**，安装 Hooks，并按需授予权限。

## 首次使用

1. 打开灵动岛菜单中的 **Settings...**。
2. 在 **Diagnostics** 查看 App、Hooks、Socket、事件流和终端能力状态。
3. 开启辅助功能权限后，Claude/Codex 等 App 才能精确跳到对应窗口。
4. 如果系统设置中的权限已开启但仍提示未授权，请删除旧的 Agent Island 条目，
   重新添加 `/Applications/Agent Island.app`，然后重启应用。
5. 缺少 tmux server、WezTerm、kitty、Warp、cmux 或 Kaku 只表示对应可选能力
   不可用，不代表 Agent Island 安装失败。

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

正常情况下，可选终端未安装或未运行会显示 `WARN`；真正阻止产品运行的问题才应
显示为 `FAIL`。

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
