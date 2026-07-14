// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import SwiftUI

struct FloatingCompanionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: IslandViewModel
    var onBubbleChange: (Bool) -> Void
    var onOpen: (AgentSnapshot) -> Void
    var onDetails: (AgentSnapshot) -> Void

    @State private var showingBubble = false
    @State private var pulse = false
    private let ticker = Timer.publish(every: 0.72, on: .main, in: .common).autoconnect()

    static func panelSize(expanded: Bool) -> NSSize {
        expanded ? NSSize(width: 292, height: 154) : NSSize(width: 154, height: 64)
    }

    var body: some View {
        VStack(spacing: 7) {
            if showingBubble {
                bubble
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            companion
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(showingBubble ? 8 : 0)
        .onReceive(ticker) { _ in
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.3)) { pulse.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AgentIslandControlKeys.toggleRequested)) { _ in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                showingBubble.toggle()
            }
            onBubbleChange(showingBubble)
        }
        .onReceive(NotificationCenter.default.publisher(for: AgentIslandControlKeys.collapseRequested)) { _ in
            guard showingBubble else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                showingBubble = false
            }
            onBubbleChange(false)
        }
    }

    private var companion: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 42, height: 42)
                Circle()
                    .stroke(statusColor.opacity(0.8), lineWidth: 2)
                    .frame(width: pulse && isBusy ? 38 : 32, height: pulse && isBusy ? 38 : 32)
                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(statusColor)
                    .scaleEffect(pulse && isBusy ? 1.12 : 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Island")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(viewModel.headline)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                showingBubble.toggle()
            }
            onBubbleChange(showingBubble)
        }
        .help(showingBubble ? "收起状态气泡" : "查看当前会话状态")
    }

    @ViewBuilder
    private var bubble: some View {
        if let snapshot = viewModel.primarySnapshot {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: snapshot.surface.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(snapshot.family.tint)
                    .frame(width: 30, height: 30)
                    .background(snapshot.family.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(snapshot.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                    if let updated = snapshot.lastUpdated {
                        Text(updated, style: .relative)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    Button { onOpen(snapshot) } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.82))
                    .help("跳转到对应窗口")
                    Button { onDetails(snapshot) } label: {
                        Image(systemName: "text.bubble")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.82))
                    .help("查看聊天详情")
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
        } else {
            Text("当前没有活跃会话")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var isBusy: Bool {
        guard let snapshot = viewModel.primarySnapshot else { return false }
        return snapshot.phase == .working || snapshot.phase == .thinking
    }

    private var statusIcon: String {
        guard let snapshot = viewModel.primarySnapshot else { return "sparkles" }
        switch snapshot.phase {
        case .needsAttention, .error: return "exclamationmark.bubble.fill"
        case .done: return "checkmark.circle.fill"
        case .working: return "waveform"
        case .thinking: return "brain.head.profile"
        case .queued: return "pause.circle.fill"
        case .online, .idle, .available, .offline: return "sparkles"
        }
    }

    private var statusColor: Color {
        guard let snapshot = viewModel.primarySnapshot else { return .cyan }
        switch snapshot.phase {
        case .needsAttention, .error: return .orange
        case .working: return .green
        case .thinking: return .cyan
        case .queued: return .yellow
        case .done: return .blue
        case .online, .idle, .available, .offline: return .white
        }
    }
}
