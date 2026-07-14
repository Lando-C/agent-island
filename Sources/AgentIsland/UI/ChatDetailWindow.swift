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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: snapshot.surface.icon)
                    .foregroundStyle(snapshot.family.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title).font(.headline).lineLimit(1)
                    Text(snapshot.sessionID.map { "session \(String($0.prefix(12)))" } ?? snapshot.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
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
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(store.items) { item in
                                ChatDetailItemView(item: item)
                                    .id(item.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: store.items.count) { _ in
                        if let last = store.items.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let path = store.sourcePath {
                Divider()
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .onAppear { store.load(snapshot: snapshot) }
    }
}

private struct ChatDetailItemView: View {
    var item: ChatDetailItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.title).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if let timestamp = item.timestamp {
                        Text(timestamp, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(item.body)
                    .font(.system(size: 12, design: item.role == .tool ? .monospaced : .default))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
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
