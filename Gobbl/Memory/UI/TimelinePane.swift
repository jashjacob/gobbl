import AppKit
import GobblCore
import SwiftUI

/// Memory → Timeline: a card per day with what got done, then morning,
/// afternoon and evening, each with the windows behind it (and Forget).
struct TimelinePane: View {
    @State private var center = DigestCenter.shared

    var body: some View {
        let days = Dictionary(grouping: center.digests, by: \.day).sorted { $0.key > $1.key }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if days.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No days yet").font(.title3.bold())
                        Text("Each morning Gobbl writes a short summary of the day before: what you worked on, not how long you spent. You can also summarise today so far.")
                            .foregroundStyle(.secondary)
                        Button("Summarise Today So Far") { summariseToday() }.disabled(center.building)
                    }
                    .padding(.top, 8)
                }
                ForEach(days, id: \.key) { day, parts in
                    DayCard(day: day, parts: parts.sorted { DayParts.order.firstIndex(of: $0.part) ?? 0 < DayParts.order.firstIndex(of: $1.part) ?? 0 })
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .toolbar {
            Button(action: summariseToday) {
                Label("Summarise Today", systemImage: center.building ? "hourglass" : "text.badge.plus")
            }
            .help("Write today's summary so far (uses one of the day's background AI calls)")
            .disabled(center.building)
        }
        .task { center.reload() }
    }

    private func summariseToday() {
        Task { await center.build(day: DayParts.dayKey(Date(), calendar: .current)) }
    }
}

private struct DayCard: View {
    let day: String
    let parts: [DayDigest]
    @State private var expanded = false

    var body: some View {
        let bullets = parts.flatMap(\.bullets)
        let apps = Array(NSOrderedSet(array: parts.flatMap(\.apps))) as? [String] ?? []
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.title3.bold())
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(parts, id: \.part) { part in
                    PartSection(day: day, digest: part)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(bullets.prefix(3).enumerated()), id: \.offset) { i, bullet in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().frame(width: 4, height: 4).foregroundStyle(.secondary)
                            Text(bullet).lineLimit(1)
                        }
                        .opacity(i == 2 && bullets.count > 3 ? 0.45 : 1)
                    }
                }
                if bullets.count > 3 {
                    Button("Show \(bullets.count - 3) more") { withAnimation(.snappy) { expanded = true } }
                        .buttonStyle(.link)
                }
            }
            if !apps.isEmpty {
                HStack(spacing: 6) {
                    ForEach(apps.prefix(8), id: \.self) { app in
                        Text(app).font(.caption).padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private var date: Date? { DayParts.range(of: day, calendar: .current)?.start }
    private var title: String {
        guard let date else { return day }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
    private var subtitle: String { date?.formatted(.dateTime.month(.abbreviated).day()) ?? "" }
}

private struct PartSection: View {
    let day: String
    let digest: DayDigest
    @State private var sources: [SegmentSummary]?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(digest.part.capitalized).font(.subheadline).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(digest.bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().frame(width: 4, height: 4).foregroundStyle(.secondary)
                        Text(bullet).fixedSize(horizontal: false, vertical: true)
                    }
                }
                DisclosureGroup("Sources") {
                    if let sources {
                        if sources.isEmpty { Text("Nothing left here.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(sources) { s in
                            HStack(spacing: 8) {
                                if let icon = icon(for: s.appBundle) {
                                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(s.app) · \(s.chat ?? s.domain ?? String(s.window.prefix(50)))").lineLimit(1)
                                    Text("\(s.started.formatted(date: .omitted, time: .shortened)), \(Int(s.minutes.rounded())) min")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Forget") {
                                    DigestCenter.shared.forget(segment: s.id)
                                    self.sources = sources.filter { $0.id != s.id }
                                }
                                .buttonStyle(.link)
                                .help("Delete everything Gobbl captured in this block")
                            }
                        }
                    } else {
                        ProgressView().controlSize(.small)
                            .onAppear { sources = DigestCenter.shared.sources(day: day, part: digest.part) }
                    }
                }
                .font(.callout)
            }
        }
    }

    private func icon(for bundle: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
