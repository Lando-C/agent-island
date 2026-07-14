// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import AppKit
import Foundation
import ServiceManagement
import SwiftUI

enum AgentIslandSettingsKeys {
    static let idleWidth = "agentIsland.appearance.idleWidth"
    static let workingWidth = "agentIsland.appearance.workingWidth"
    static let settingsChanged = Notification.Name("AgentIslandSettingsChanged")
}

final class AgentSettingsWindowController: NSWindowController {
    init(
        monitor: AgentMonitor,
        scriptsRoot: URL,
        reinstallHooks: @escaping () -> Void,
        copyDiagnostics: @escaping () -> Void,
        createSupportBundle: @escaping () -> Void,
        copyWebBridgeToken: @escaping () -> Void
    ) {
        let view = AgentSettingsView(
            monitor: monitor,
            scriptsRoot: scriptsRoot,
            reinstallHooks: reinstallHooks,
            copyDiagnostics: copyDiagnostics,
            createSupportBundle: createSupportBundle,
            copyWebBridgeToken: copyWebBridgeToken,
            transportHealth: .shared
        )
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Agent Island Settings"
        window.contentView = hostingView
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance = "外观"
    case system = "系统"
    case safety = "安全"
    case diagnostics = "诊断"
    case roadmap = "路线"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .appearance: return "slider.horizontal.3"
        case .system: return "gearshape"
        case .safety: return "lock.shield"
        case .diagnostics: return "stethoscope"
        case .roadmap: return "map"
        }
    }
}

struct AgentSettingsView: View {
    @ObservedObject var monitor: AgentMonitor
    let scriptsRoot: URL
    let reinstallHooks: () -> Void
    let copyDiagnostics: () -> Void
    let createSupportBundle: () -> Void
    let copyWebBridgeToken: () -> Void
    @ObservedObject var transportHealth: TransportHealthStore

    @State private var selectedTab: SettingsTab = .diagnostics
    @State private var diagnosticsText = "点击 Run Diagnostics 生成报告。"
    @State private var diagnosticsRunning = false
    @State private var autoApprovalEnabled = AutoApprovalStore.load().enabled
    @State private var allowReadOnly = AutoApprovalStore.load().allowReadOnly
    @State private var idleWidth = AgentSettingsStore.idleWidth
    @State private var workingWidth = AgentSettingsStore.workingWidth
    @State private var launchStatus = LaunchAtLoginController.statusText
    @State private var smartSuppression = SmartSuppression.isEnabled
    @State private var floatingMode = IslandDisplayModeStore.mode == .floating
    @State private var soundEnabled = AgentIslandSoundSettings.enabled
    @State private var settingsMessage = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(minWidth: 760, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            runDiagnostics()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agent Island")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 8)

            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.icon)
                            .frame(width: 18)
                        Text(tab.rawValue)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundColor(selectedTab == tab ? .white : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
            }

            Spacer()

            Text("AI Agent Operations Island")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(14)
        }
        .frame(width: 190)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            switch selectedTab {
            case .appearance:
                appearanceTab
            case .system:
                systemTab
            case .safety:
                safetyTab
            case .diagnostics:
                diagnosticsTab
            case .roadmap:
                roadmapTab
            }
            Spacer(minLength: 0)
        }
        .padding(22)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedTab.rawValue)
                .font(.system(size: 24, weight: .bold))
            Text(headerSubtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private var headerSubtitle: String {
        switch selectedTab {
        case .appearance:
            return "控制刘海宽度和后续吉祥物展示。"
        case .system:
            return "管理启动、权限和 Hook 修复入口。"
        case .safety:
            return "自动审批必须可解释、可关闭、边界明确。"
        case .diagnostics:
            return "把权限、Hook、Socket、tmux、终端跳转链路变成可见状态。"
        case .roadmap:
            return "公开发布前的产品化路线和功能覆盖面。"
        }
    }

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingSection("刘海宽度") {
                widthSlider("待机宽度", value: $idleWidth, range: 320...760)
                widthSlider("工作/展开宽度", value: $workingWidth, range: 420...1040)
                Text("宽度会立即保存，并在下一次展开/收起或屏幕变化时应用。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            settingSection("离岛和吉祥物") {
                Toggle("离岛模式", isOn: $floatingMode)
                    .help("也可在刘海上长按 0.35 秒后向下拖拽。浮窗位置会自动记忆，右键可回到刘海。")
                    .onChange(of: floatingMode) { value in
                        IslandDisplayModeStore.mode = value ? .floating : .notch
                        NotificationCenter.default.post(name: AgentIslandSettingsKeys.settingsChanged, object: nil)
                    }
                roadmapLine("动态吉祥物", "每个引擎支持 idle / working / warning 三态。")
                roadmapLine("声音提示", "开始、完成、需要审批、异常四类声音，默认关闭。")
            }
        }
    }

    private func widthSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) px")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 10)
                .onChange(of: value.wrappedValue) { _ in
                    AgentSettingsStore.idleWidth = idleWidth
                    AgentSettingsStore.workingWidth = workingWidth
                    NotificationCenter.default.post(name: AgentIslandSettingsKeys.settingsChanged, object: nil)
                }
        }
    }

    private var systemTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingSection("启动和权限") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("开机自启")
                            .font(.system(size: 13, weight: .semibold))
                        Text(launchStatus)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("启用") {
                        settingsMessage = LaunchAtLoginController.setEnabled(true)
                        launchStatus = LaunchAtLoginController.statusText
                    }
                    Button("关闭") {
                        settingsMessage = LaunchAtLoginController.setEnabled(false)
                        launchStatus = LaunchAtLoginController.statusText
                    }
                }

                HStack {
                    Button("辅助功能设置") {
                        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                    }
                    Button("通知设置") {
                        openSystemSettings("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                    }
                    Button("登录项设置") {
                        openSystemSettings("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
                    }
                }

                if !settingsMessage.isEmpty {
                    Text(settingsMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            settingSection("Hooks") {
                Text("Claude Code 使用 ~/.claude/settings.json，Codex CLI 使用 ~/.codex/hooks.json。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Button("重新安装 Hooks") {
                    reinstallHooks()
                }
            }

            settingSection("提醒行为") {
                Toggle("对应终端或 App 在前台时抑制自动展开", isOn: $smartSuppression)
                    .help("状态仍会更新；只抑制大范围自动展开，手动点击和菜单操作不受影响。")
                    .onChange(of: smartSuppression) { value in
                        SmartSuppression.isEnabled = value
                    }
                Toggle("声音提醒", isOn: $soundEnabled)
                    .help("默认关闭。开始、完成和需要处理分别使用系统内置声音；不会上传任何会话内容。")
                    .onChange(of: soundEnabled) { value in
                        AgentIslandSoundSettings.enabled = value
                    }
            }
        }
    }

    private var safetyTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingSection("自动审批") {
                Toggle("启用只读工具自动审批", isOn: $autoApprovalEnabled)
                    .help("默认关闭。开启后也只允许 Claude PermissionRequest 的 Read/Grep/Glob/LS/TodoRead 自动通过。")
                    .onChange(of: autoApprovalEnabled) { _ in saveAutoApproval() }
                Toggle("允许只读工具", isOn: $allowReadOnly)
                    .disabled(!autoApprovalEnabled)
                    .help("只读工具包括 Read、Grep、Glob、LS、TodoRead。Bash 不在自动审批范围内。")
                    .onChange(of: allowReadOnly) { _ in saveAutoApproval() }

                Text("危险操作永不自动通过：Write、Edit、MultiEdit、NotebookEdit、Bash/Shell、rm、sudo、git push --force、git reset --hard、git clean、权限修改、磁盘操作。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            settingSection("风险标记") {
                roadmapLine("safe_read", "只读工具，可选自动通过。")
                roadmapLine("manual_safe_shell", "看似只读的 shell，也仍需人工确认。")
                roadmapLine("dangerous_shell", "含删除、强推、sudo、重定向等模式，永不自动通过。")
            }
        }
    }

    private var diagnosticsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(diagnosticsRunning ? "Running..." : "Run Diagnostics") {
                    runDiagnostics()
                }
                .disabled(diagnosticsRunning)
                Button("Copy Report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diagnosticsText, forType: .string)
                }
                Button("Copy via Menu Action") {
                    copyDiagnostics()
                }
                Button("Create Redacted Support Bundle") {
                    createSupportBundle()
                }
                Button("Copy Web Bridge Token") {
                    copyWebBridgeToken()
                }
                Spacer()
                Button("Open Status Folder") {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent-island"))
                }
            }

            settingSection("传输状态") {
                if transportHealth.snapshots.isEmpty {
                    Text("等待 Agent Island 初始化传输。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(transportHealth.snapshots) { transport in
                        transportRow(transport)
                    }
                }
            }

            settingSection("当前状态来源") {
                let active = monitor.snapshots.filter { $0.phase != .offline && $0.phase != .available }
                if active.isEmpty {
                    Text("当前没有可展示的会话状态。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(active) { snapshot in
                        HStack(spacing: 8) {
                            Image(systemName: snapshot.evidence.isAuthoritative ? "checkmark.seal" : "questionmark.diamond")
                                .foregroundColor(snapshot.evidence.isAuthoritative ? .green : .orange)
                            Text(snapshot.title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(snapshot.evidence.label)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            ScrollView {
                Text(diagnosticsText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
        }
    }

    private func transportRow(_ transport: TransportHealthSnapshot) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: transportIcon(transport.state))
                .foregroundColor(transportColor(transport.state))
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(transport.name)
                        .font(.system(size: 12, weight: .semibold))
                    Text(transport.state.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(transportColor(transport.state))
                }
                if let protocolVersion = transport.protocolVersion, !protocolVersion.isEmpty {
                    Text(protocolVersion)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                if let lastSuccess = transport.lastSuccessAt {
                    Text("Last success \(lastSuccess, style: .relative)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                if let failure = transport.failure, !failure.isEmpty {
                    Text(failure)
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func transportIcon(_ state: TransportConnectionState) -> String {
        switch state {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .degraded: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        case .disabled, .unavailable: return "minus.circle"
        }
    }

    private func transportColor(_ state: TransportConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting: return .blue
        case .degraded: return .orange
        case .failed: return .red
        case .disabled, .unavailable: return .secondary
        }
    }

    private var roadmapTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingSection("状态与交互主线") {
                    roadmapLine("PendingRequest", "Claude 与 Codex 已支持经过验证的结构化问题/审批写回。")
                    roadmapLine("聊天详情", "已支持按需读取本地 JSONL；下一步改为增量 Hook 事件存储。")
                    roadmapLine("僵尸检测", "pid/tmux pane 消失自动标记 ended。")
                    roadmapLine("智能抑制", "对应终端/窗口在前台时已抑制自动展开，保留状态更新。")
                }
                settingSection("体验层") {
                    roadmapLine("离岛模式", "外接屏和多空间使用时让状态跟随当前工作屏。")
                    roadmapLine("吉祥物", "不是装饰，而是 idle/working/warning 的低成本识别。")
                    roadmapLine("声音", "默认关闭，按事件类型可配置。")
                }
                settingSection("开源发布") {
                    roadmapLine("README", "安装、权限、Hook、安全边界、隐私说明。")
                    roadmapLine("License hygiene", "MIT/Apache 可复用；GPL/CC BY-NC 只作参考。")
                    roadmapLine("Homebrew cask", "让用户不用手动 open dist app。")
                }
            }
        }
    }

    private func settingSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func roadmapLine(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle")
                .foregroundColor(.accentColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func runDiagnostics() {
        diagnosticsRunning = true
        diagnosticsText = "Running diagnostics..."
        let script = scriptsRoot.appendingPathComponent("agent-island-diagnostics")
        DispatchQueue.global(qos: .utility).async {
            let report = Self.runScript(script)
            DispatchQueue.main.async {
                diagnosticsText = report
                diagnosticsRunning = false
            }
        }
    }

    private func saveAutoApproval() {
        AutoApprovalStore.save(.init(enabled: autoApprovalEnabled, allowReadOnly: allowReadOnly))
    }

    private static func runScript(_ script: URL) -> String {
        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            return "Missing executable: \(script.path)"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let stdout = String(data: outputData, encoding: .utf8) ?? ""
            let stderr = String(data: errorData, encoding: .utf8) ?? ""
            return stderr.isEmpty ? stdout : stdout + "\n\n## stderr\n" + stderr
        } catch {
            return "Failed to run diagnostics: \(error.localizedDescription)"
        }
    }

    private func openSystemSettings(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}

enum AgentSettingsStore {
    static var idleWidth: Double {
        get {
            let value = UserDefaults.standard.double(forKey: AgentIslandSettingsKeys.idleWidth)
            return value > 0 ? value : 640
        }
        set { UserDefaults.standard.set(newValue, forKey: AgentIslandSettingsKeys.idleWidth) }
    }

    static var workingWidth: Double {
        get {
            let value = UserDefaults.standard.double(forKey: AgentIslandSettingsKeys.workingWidth)
            return value > 0 ? value : 640
        }
        set { UserDefaults.standard.set(newValue, forKey: AgentIslandSettingsKeys.workingWidth) }
    }
}

private struct AutoApprovalSettings: Codable {
    var enabled: Bool
    var allowReadOnly: Bool

    private enum CodingKeys: String, CodingKey {
        case enabled
        case allowReadOnly = "allow_read_only"
    }
}

private enum AutoApprovalStore {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-island")
            .appendingPathComponent("auto-approval.json")
    }

    static func load() -> AutoApprovalSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AutoApprovalSettings.self, from: data) else {
            return AutoApprovalSettings(enabled: false, allowReadOnly: true)
        }
        return settings
    }

    static func save(_ settings: AutoApprovalSettings) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

private enum LaunchAtLoginController {
    static var statusText: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "已启用。"
        case .notRegistered:
            return "未启用。"
        case .requiresApproval:
            return "需要在系统设置里确认。"
        case .notFound:
            return "当前 app 不在可注册位置，建议从 /Applications 启动。"
        @unknown default:
            return "未知状态。"
        }
    }

    static func setEnabled(_ enabled: Bool) -> String {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                return "已请求启用开机自启。"
            } else {
                try SMAppService.mainApp.unregister()
                return "已请求关闭开机自启。"
            }
        } catch {
            return "开机自启设置失败：\(error.localizedDescription)"
        }
    }
}
