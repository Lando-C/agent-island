// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import SwiftUI

/// A detached, session-first companion. It intentionally does not reuse the
/// notch panel hierarchy: identity, state, and the current session remain
/// legible in a small movable window.
struct FloatingCompanionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: IslandViewModel
    var onBubbleChange: (Bool) -> Void
    var onOpen: (AgentSnapshot) -> Void
    var onDetails: (AgentSnapshot) -> Void
    var onReturnToNotch: () -> Void

    @State private var showingBubble = false
    @State private var pulse = false
    @State private var themePreferences = CompanionThemeSettings.preferences
    private let ticker = Timer.publish(every: 0.84, on: .main, in: .common).autoconnect()

    static func panelSize(expanded: Bool) -> NSSize {
        PanelGeometryPolicy.floatingSize(expanded: expanded)
    }

    private var snapshot: AgentSnapshot? { viewModel.primarySnapshot }

    private var visual: CompanionVisualPolicy {
        guard let snapshot else {
            let family = AgentFamily.codex
            return .resolve(
                family: family,
                surface: .runtime,
                phase: .idle,
                theme: themePreferences.theme(for: family)
            )
        }
        return .resolve(
            family: snapshot.family,
            surface: snapshot.surface,
            phase: snapshot.phase,
            theme: themePreferences.theme(for: snapshot.family)
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            if showingBubble {
                sessionCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            compactCompanion
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(showingBubble ? 8 : 0)
        .onReceive(ticker) { _ in
            guard !reduceMotion, visual.motion == .breathe else {
                pulse = false
                return
            }
            withAnimation(.easeInOut(duration: 0.42)) { pulse.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AgentIslandControlKeys.toggleRequested)) { _ in
            setBubbleVisible(!showingBubble)
        }
        .onReceive(NotificationCenter.default.publisher(for: AgentIslandControlKeys.collapseRequested)) { _ in
            guard showingBubble else { return }
            setBubbleVisible(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: AgentIslandSettingsKeys.companionThemeChanged)) { _ in
            themePreferences = CompanionThemeSettings.preferences
        }
        .accessibilityElement(children: .contain)
    }

    private var compactCompanion: some View {
        HStack(spacing: 9) {
            companionSummary
                .contentShape(Rectangle())
                .onTapGesture { setBubbleVisible(!showingBubble) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(visual.identityLabel)，\(visual.stateLabel)")
                .accessibilityHint(showingBubble ? "收起会话卡片" : "展开主要会话")
                .accessibilityAction { setBubbleVisible(!showingBubble) }

            Button(action: onReturnToNotch) {
                Image(systemName: "arrow.up.to.line.compact")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.62))
            .help("回到刘海（⌥⌘N）")
            .accessibilityLabel("回到刘海")
        }
        .padding(.horizontal, 10)
        .frame(height: 68)
        .background(companionBackground)
        .contentShape(RoundedRectangle(cornerRadius: companionCornerRadius, style: .continuous))
        .help(showingBubble ? "收起会话卡片" : "查看主要会话")
    }

    private var companionSummary: some View {
        HStack(spacing: 9) {
            identityGlyph

            VStack(alignment: .leading, spacing: 4) {
                Text(visual.identityLabel)
                    .font(.system(size: 10, weight: .semibold, design: companionFontDesign))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Image(systemName: visual.phaseGlyph)
                        .font(.system(size: 9, weight: .bold))
                        .accessibilityHidden(true)
                    Text(visual.stateLabel)
                        .font(.system(size: 12, weight: .bold, design: companionFontDesign))
                        .lineLimit(1)
                }
                .foregroundStyle(stateColor)
            }

            Spacer(minLength: 0)

            if viewModel.activeSnapshots.count > 1 {
                Text("\(viewModel.activeSnapshots.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.74))
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .accessibilityLabel("\(viewModel.activeSnapshots.count) 个活跃会话")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identityGlyph: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: identityCornerRadius, style: .continuous)
                .fill(familyColor.opacity(0.2))
                .frame(width: 42, height: 42)
                .overlay {
                    RoundedRectangle(cornerRadius: identityCornerRadius, style: .continuous)
                        .stroke(familyColor.opacity(0.48), lineWidth: 1)
                }

            Image(systemName: visual.familyGlyph)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(familyColor)
                .frame(width: 42, height: 42)
                .scaleEffect(pulse ? 1.08 : 1)
                .accessibilityHidden(true)

            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.black.opacity(0.86), lineWidth: 2))
                .scaleEffect(pulse ? 1.22 : 1)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var sessionCard: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(visual.stateSummary)
                        .font(.system(size: 11, weight: .bold, design: companionFontDesign))
                        .foregroundStyle(stateColor)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(snapshot.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let updated = snapshot.lastUpdated {
                        Text(updated, style: .relative)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.44))
                    }
                    Spacer(minLength: 0)
                    actionButton("text.bubble", help: "查看聊天详情") {
                        onDetails(snapshot)
                    }
                    actionButton("arrow.up.forward.app", help: "跳转到对应窗口") {
                        onOpen(snapshot)
                    }
                }
            }
            .padding(11)
            .background(companionBackground)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("等待新任务")
                    .font(.system(size: 12, weight: .bold, design: companionFontDesign))
                    .foregroundStyle(.white)
                Text("当前没有活跃会话")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(companionBackground)
        }
    }

    private func actionButton(
        _ systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 22)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.84))
        .help(help)
        .accessibilityLabel(help)
    }

    private var companionBackground: some View {
        RoundedRectangle(cornerRadius: companionCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        familyColor.opacity(0.18),
                        Color.black.opacity(0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: companionCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
    }

    private var familyColor: Color {
        switch visual.familyPalette {
        case .codex: return Color(red: 0.18, green: 0.78, blue: 0.47)
        case .claude: return Color(red: 0.93, green: 0.55, blue: 0.22)
        case .science: return Color(red: 0.37, green: 0.68, blue: 1)
        case .chatgpt: return Color(red: 0.10, green: 0.74, blue: 0.60)
        }
    }

    private var stateColor: Color {
        switch visual.stateTone {
        case .neutral: return .white.opacity(0.74)
        case .active: return .green
        case .waiting: return .yellow
        case .attention: return .orange
        case .success: return .cyan
        case .failure: return .red
        }
    }

    private var companionCornerRadius: CGFloat {
        switch visual.theme {
        case .system: return 18
        case .friendly: return 24
        case .technical: return 8
        }
    }

    private var identityCornerRadius: CGFloat {
        switch visual.theme {
        case .system: return 12
        case .friendly: return 21
        case .technical: return 5
        }
    }

    private var companionFontDesign: Font.Design {
        visual.theme == .technical ? .monospaced : .rounded
    }

    private func setBubbleVisible(_ visible: Bool) {
        let changes = {
            showingBubble = visible
            if !visible { pulse = false }
        }
        if reduceMotion {
            changes()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8), changes)
        }
        onBubbleChange(visible)
    }
}
