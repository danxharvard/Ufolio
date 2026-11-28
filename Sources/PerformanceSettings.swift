import SwiftUI

/// Settings › Performance: power modes, energy, memory and your footprint.
struct PerformanceSettings: View {
    @AppStorage(Prefs.powerMode) private var mode = PowerMode.automatic.rawValue
    @AppStorage(Prefs.tabSleepMinutes) private var tabSleep = 15.0
    @AppStorage(Prefs.freeMemoryAutomatically) private var freeMemory = true
    @AppStorage(Prefs.memorySaver) private var memorySaver = true
    @AppStorage(Prefs.autoPowerMode) private var autoPowerMode = true
    @AppStorage(Prefs.memoryLimitGB) private var memoryLimitGB = 0.0
    @AppStorage(Prefs.pauseBackgroundMedia) private var pauseMedia = false
    @AppStorage(Prefs.clearCacheOnQuit) private var clearCacheOnQuit = true
    @AppStorage(Prefs.preloadPages) private var preloadPages = true
    @ObservedObject private var center = PerformanceCenter.shared
    @State private var usage = PerformanceCenter.Usage()
    private let tick = Timer.publish(every: 5, tolerance: 2, on: .main, in: .default).autoconnect()

    private var hasFastDisplay: Bool { NSScreen.screens.contains { $0.maximumFramesPerSecond > 60 } }

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .performance, subtitle: "Choose how Ufolio balances speed, battery life and energy use, and see how much memory your tabs use.")
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    ForEach(PowerMode.allCases) { option in
                        PowerModeCard(mode: option, selected: mode == option.rawValue) {
                            withAnimation(.easeOut(duration: 0.15)) { mode = option.rawValue }
                        }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: center.effectiveMode.symbol)
                        .foregroundStyle(center.effectiveMode.colors.first ?? .accentColor)
                    Text(statusLine).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } header: { SectionTitle("Mode") } footer: {
                Footnote(modeFootnote)
            }

            Section {
                SettingsSwitch(title: "Pause sound and video in background tabs",
                               detail: center.isEco ? "Always on in Eco."
                                   : "When you switch tabs, the one you leave stops playing. Leave this off if you listen to music in another tab.",
                               symbol: "pause.circle.fill", colors: PowerMode.eco.colors,
                               isOn: Binding(get: { pauseMedia || center.isEco }, set: { pauseMedia = $0 }))
                    .disabled(center.isEco)
            } header: { SectionTitle("Energy") }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(PerformanceCenter.format(usage.total))
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                        Text(usageLine).font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Sleep Background Tabs") {
                            center.sleepBackgroundTabs(idleFor: 0)
                            remeasureSoon()
                        }
                        .disabled(usage.tabs.allSatisfy { $0.isAsleep || $0.isSelected })
                    }
                    let heaviest = Array(usage.tabs.filter { !$0.isAsleep && $0.bytes > 0 }.prefix(5))
                    if !heaviest.isEmpty {
                        let top = Double(heaviest.first?.bytes ?? 1)
                        VStack(spacing: 7) {
                            ForEach(heaviest) { item in
                                MemoryRow(item: item, fraction: Double(item.bytes) / max(top, 1)) {
                                    item.tab?.sleep()
                                    remeasureSoon()
                                }
                            }
                        }
                    }
                }
                SettingsSwitch(title: "Memory Saver",
                               detail: "Keeps Ufolio under its memory limit by putting the tabs you used least recently to sleep.",
                               symbol: "memorychip", colors: PowerMode.eco.colors, isOn: $memorySaver)
                if memorySaver {
                    LabeledContent("Memory limit") {
                        Picker("", selection: $memoryLimitGB) {
                            Text("Automatic (\(PerformanceCenter.format(max(1_073_741_824, ProcessInfo.processInfo.physicalMemory / 4))))").tag(0.0)
                            ForEach([1.0, 2.0, 3.0, 4.0, 6.0, 8.0], id: \.self) { gb in Text("\(Int(gb)) GB").tag(gb) }
                        }
                        .labelsHidden().fixedSize()
                    }
                }
                SettingsSwitch(title: "Power Mode",
                               detail: "Works out when a tab needs more, such as a big web app, a map or a 4K video, and lets it use extra memory. Drops back to light by itself a few minutes after.",
                               symbol: "bolt.fill", colors: PowerMode.performance.colors, isOn: $autoPowerMode)
                if autoPowerMode, let boost = center.powerBoost {
                    Label("On now: \(boost.reason), so Ufolio’s limit is \(PerformanceCenter.format(boost.limit)) for the moment.",
                          systemImage: "bolt.circle.fill")
                        .font(.system(size: 11.5)).foregroundStyle(Color.orange)
                }
                LabeledContent("Sleep inactive tabs") { Picker("", selection: $tabSleep) {
                    Text("Never").tag(0.0)
                    Text("After 5 minutes").tag(5.0)
                    Text("After 15 minutes").tag(15.0)
                    Text("After 30 minutes").tag(30.0)
                    Text("After 1 hour").tag(60.0)
                }.labelsHidden().fixedSize() }
                SettingsSwitch(title: "Free up memory automatically",
                               detail: "When your Mac runs low on memory, Ufolio puts background tabs to sleep straight away.",
                               symbol: "memorychip.fill", colors: PowerMode.balanced.colors,
                               isOn: $freeMemory)
            } header: { SectionTitle("Memory") } footer: {
                Footnote(memoryFootnote)
            }

            Section {
                // In Battery Saver and Eco it's off, and the switch shows that: it can't be turned on
                // until you leave them. Your own choice is kept and comes back with the mode.
                SettingsSwitch(title: "Instant pages",
                               detail: center.isPowerSaving
                                   ? "Off in \(center.effectiveMode.label), to save energy and data. It comes back \(preloadPages ? "on" : "as you set it") when you leave \(center.effectiveMode.label)."
                                   : "When you’ve as good as chosen a page (the top suggestion as you type is one you’ve visited, or you rest the pointer on a favourite or bookmark), Ufolio loads it in the background so it opens instantly. The site sees the visit as it loads. Never in Stealth windows, Battery Saver or Eco.",
                               symbol: "bolt.fill",
                               colors: [Color(red: 1.0, green: 0.78, blue: 0.25), Color(red: 0.95, green: 0.52, blue: 0.12)],
                               isOn: Binding(get: { preloadPages && !center.isPowerSaving }, set: { preloadPages = $0 }))
                    .disabled(center.isPowerSaving)
            } header: { SectionTitle("Speed") }

            Section {
                SettingsSwitch(title: "Clear page cache when Ufolio quits",
                               detail: "Ufolio takes almost no disk space between sessions. Sites load a little slower the first time after you open Ufolio. Sign-ins and cookies are kept.",
                               symbol: "internaldrive.fill",
                               colors: [Color(red: 0.45, green: 0.65, blue: 1.0), Color(red: 0.25, green: 0.42, blue: 0.90)],
                               isOn: $clearCacheOnQuit)
            } header: { SectionTitle("Disk") } footer: {
                Footnote("While Ufolio is open, its page cache is kept under 100 MB.")
            }

            Section {
                HStack(spacing: 12) {
                    IconTile(symbol: "leaf.fill", colors: PowerMode.eco.colors, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("About \(PerformanceCenter.format(center.dataSavedThisMonth)) of downloads avoided this month")
                            .font(.system(size: 13, weight: .medium))
                        Text("Every ad and tracker Force Field blocks is data your Mac, your network and distant data centres never had to move or power.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: { SectionTitle("Your footprint") } footer: {
                Footnote("A rough estimate, from the ads and trackers blocked in the last 30 days.")
            }
        }
        .formStyle(SafariFormStyle())
        .onAppear { usage = center.measure() }
        // Re-measured every few seconds with no animation (an animated refresh redrew the whole
        // pane each time), and only while the window is in front.
        .onReceive(tick) { _ in
            guard NSApp.isActive, NSApp.keyWindow?.identifier?.rawValue == "settings" else { return }
            usage = center.measure()
        }
    }

    private func remeasureSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { usage = center.measure() }
    }

    private var usageLine: String {
        var line = "used by Ufolio and \(usage.tabCount) \(usage.tabCount == 1 ? "tab" : "tabs")"
        if usage.asleepCount > 0 { line += ", \(usage.asleepCount) asleep" }
        return line
    }

    private var statusLine: String {
        let power = center.lowPowerMode ? "Low Power Mode is on" : center.onBattery ? "on battery" : "plugged in"
        return "Using \(center.effectiveMode.label) now (\(power))"
    }

    private var memoryFootnote: String {
        var text = "Sleeping tabs free their memory and wake instantly with the page as you left it. Tabs playing sound or video never sleep."
        if center.isPowerSaving && tabSleep > 5 {
            text += " In \(center.effectiveMode.label), tabs sleep after 5 minutes."
        }
        return text
    }

    private var modeFootnote: String {
        switch center.effectiveMode {
        case .performance:
            return hasFastDisplay
                ? "Pages scroll and animate at up to 120 Hz on your ProMotion display, and Ufolio looks up links before you click them. Applies to tabs you open from now on."
                : "Ufolio looks up links before you click them so pages open sooner. On a ProMotion display, pages also scroll at up to 120 Hz. Applies to tabs you open from now on."
        case .batterySaver:
            return "Background tabs slow down and sleep sooner, 3D graphics use the energy-saving chip where your Mac has one, and the start page stops animating. Applies to tabs you open from now on."
        case .eco:
            return "Everything in Battery Saver, plus no autoplaying video and nothing playing in tabs you’re not looking at. Applies to tabs you open from now on."
        default:
            return "WebKit’s everyday settings: quick and efficient."
        }
    }
}

/// A switch with an icon tile, a title and a line of explanation.
private struct SettingsSwitch: View {
    let title: String
    let detail: String
    let symbol: String
    let colors: [Color]
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, colors: colors, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Toggle("", isOn: $isOn).toggleStyle(FluidSwitchStyle()).labelsHidden()
        }
    }
}

private struct PowerModeCard: View {
    let mode: PowerMode
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                IconTile(symbol: mode.symbol, colors: mode.colors, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.label).font(.system(size: 13, weight: .semibold))
                    Text(mode.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(11)
            // Every card the same size, whatever its text.
            .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.07 : hovering ? 0.05 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.07), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MemoryRow: View {
    let item: PerformanceCenter.TabUsage
    let fraction: Double
    let onSleep: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title).font(.system(size: 12)).lineLimit(1)
                    Spacer()
                    Text(PerformanceCenter.format(item.bytes))
                        .font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary).monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule().fill(LinearGradient(colors: SettingsTab.performance.colors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                }
                .frame(height: 4)
            }
            Button("Sleep", action: onSleep)
                .controlSize(.small)
                .disabled(item.isSelected)
                .accessibilityLabel(item.isSelected ? "The tab you’re looking at stays awake." : "Free this tab’s memory. It wakes when you go back to it.")
        }
    }
}
