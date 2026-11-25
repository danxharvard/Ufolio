import SwiftUI

/// History (⌘Y): everything you've visited, newest first, grouped by day, with search. Each
/// profile has its own history: it opens on the profile of the window you're using, and you can
/// switch at the top when you have more than one.
struct HistoryWindowView: View {
    @ObservedObject private var spaces = SpaceStore.shared
    @State private var profile: UUID? = BrowserModel.frontmostNormal?.profileID

    var body: some View {
        VStack(spacing: 0) {
            if !spaces.profiles.isEmpty {
                Picker("Profile", selection: $profile) {
                    Text("Default").tag(UUID?.none)
                    ForEach(spaces.profiles) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding([.horizontal, .top], 14)
            }
            HistoryWindowContent(history: HistoryStore.store(for: profile))
                .id(profile)
        }
    }

    static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }
}

private struct HistoryWindowContent: View {
    @ObservedObject var history: HistoryStore
    @State private var query = ""

    private var days: [(day: Date, entries: [HistoryEntry])] {
        let q = query.lowercased()
        let matching = history.entries(matching: q)
            .sorted { $0.lastVisit > $1.lastVisit }
            .prefix(2000)
        let calendar = Calendar.current
        var groups: [Date: [HistoryEntry]] = [:]
        for entry in matching { groups[calendar.startOfDay(for: entry.lastVisit), default: []].append(entry) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search history", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                Button("Clear History…") { HushDialogs.clearHistory(in: .history) }
            }
            .padding(14)
            Divider()
            let groups = days
            if groups.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 34, weight: .light)).foregroundStyle(.tertiary)
                    Text(query.isEmpty ? "No history yet" : "Nothing matches “\(query)”").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups, id: \.day) { group in
                        Section(header: Text(HistoryWindowView.dayTitle(group.day)).font(.system(size: 12, weight: .semibold))) {
                            ForEach(group.entries) { entry in
                                HistoryRow(entry: entry, history: history)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(VisualEffect(material: .underWindowBackground, blending: .behindWindow).ignoresSafeArea())
        .frame(minWidth: 520, minHeight: 420)
        .hushDialogs(DialogHost.history)
    }

}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let history: HistoryStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Favicon(url: entry.url, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title.isEmpty ? (entry.url.host ?? entry.url.absoluteString) : entry.title)
                    .lineLimit(1)
                Text(entry.url.host?.strippingWWW ?? entry.url.absoluteString)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(entry.lastVisit.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            Button { history.remove(entry) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { open(newTab: false) }
        .contextMenu {
            Button { open(newTab: false) } label: { Label("Open", systemImage: "arrow.up.forward.square") }
            Button { open(newTab: true) } label: { Label("Open in New Tab", systemImage: "plus.square.on.square") }
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url.absoluteString, forType: .string)
            }
            Divider()
            Button { history.remove(entry) } label: { Label("Remove from History", systemImage: "trash") }
        }
    }

    private func open(newTab: Bool) {
        WindowOpener.ensureWindow()
        // If the browser window was closed it takes a moment to come back: wait for it, rather
        // than opening the page in a window that isn't there yet (which did nothing).
        let url = entry.url
        func attempt(_ tries: Int) {
            if let model = BrowserModel.frontmostNormal, model.window != nil {
                model.open(url, inNewTab: newTab)
                model.window?.makeKeyAndOrderFront(nil)
            } else if tries < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { attempt(tries + 1) }
            }
        }
        attempt(0)
    }
}
