// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

final class ChatDetailWindowController: NSWindowController {
    init(snapshot: AgentSnapshot) {
        let view = ChatDetailView(snapshot: snapshot)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = snapshot.title
        window.minSize = NSSize(width: 420, height: 360)
        window.contentView = NSHostingView(rootView: view)
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

struct ChatDetailView: View {
    var snapshot: AgentSnapshot
    @StateObject private var store = ChatDetailStore()
    @State private var section: ChatDetailSection = .conversation

    private var visibleItems: [ChatDetailItem] {
        switch section {
        case .conversation:
            return store.items.filter(\.isConversation)
        case .activity:
            return store.items.filter(\.isActivity)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: snapshot.surface.icon)
                    .foregroundStyle(snapshot.family.tint)
                    .font(.system(size: 15, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title).font(.headline).lineLimit(1)
                    Text(snapshot.sessionID.map { "session \(String($0.prefix(12)))" } ?? snapshot.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
                Picker("显示内容", selection: $section) {
                    ForEach(ChatDetailSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 170)
                Button {
                    store.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("重新读取聊天记录")
            }
            .padding(16)

            Divider()

            if let error = store.errorMessage, store.items.isEmpty, !store.loading {
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("无法显示聊天记录").font(.headline)
                    Text(error).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            if store.historyTruncated {
                                ChatDetailHistoryNotice()
                            }
                            if visibleItems.isEmpty, !store.loading {
                                ChatDetailEmptyState(section: section) {
                                    section = .activity
                                }
                            }
                            ForEach(visibleItems) { item in
                                ChatDetailItemView(item: item, section: section)
                                    .id(item.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: visibleItems.last?.id) { _ in
                        if let last = visibleItems.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if store.sourcePath != nil {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                    Text("本机会话记录")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(store.sourcePath ?? "")
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .onAppear { store.load(snapshot: snapshot) }
    }
}

private enum ChatDetailSection: String, CaseIterable, Identifiable {
    case conversation
    case activity

    var id: String { rawValue }
    var title: String { self == .conversation ? "对话" : "工作记录" }
}

private struct ChatDetailItemView: View {
    var item: ChatDetailItem
    var section: ChatDetailSection

    var body: some View {
        if section == .conversation {
            conversationBody
        } else {
            activityBody
        }
    }

    private var conversationBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(item.title).font(.system(size: 12, weight: .semibold))
                Spacer()
                if let timestamp = item.timestamp {
                    Text(timestamp, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(item.body)
                .font(.system(size: 14))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 11)
                .overlay(alignment: .leading) {
                    Rectangle().fill(tint.opacity(0.7)).frame(width: 2)
                }
        }
        .padding(.vertical, 2)
    }

    private var activityBody: some View {
        DisclosureGroup {
            Text(item.rawActivityPreview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .padding(.leading, 27)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 19, height: 19)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 12, weight: .semibold))
                    Text(item.activitySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if let timestamp = item.timestamp {
                    Text(timestamp, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private var icon: String {
        switch item.role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .tool: return "wrench.and.screwdriver.fill"
        case .system: return "gearshape.fill"
        }
    }

    private var tint: Color {
        switch item.role {
        case .user: return .blue
        case .assistant: return .green
        case .tool: return .orange
        case .system: return .secondary
        }
    }
}

private struct ChatDetailHistoryNotice: View {
    var body: some View {
        Label("为加快打开速度，仅加载最近的会话记录。后续内容会实时追加。", systemImage: "clock.arrow.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ChatDetailEmptyState: View {
    var section: ChatDetailSection
    var showActivity: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: section == .conversation ? "text.bubble" : "clock")
                .font(.system(size: 25))
                .foregroundStyle(.secondary)
            Text(section == .conversation ? "尚未读取到可展示的对话" : "没有额外工作记录")
                .font(.headline)
            if section == .conversation {
                Button("查看工作记录", action: showActivity)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
