import SwiftUI
import WebKit

/// A Profile keeps its own cookies, sign-ins, site data and cache, apart from every other
/// profile, so you can be signed in to two accounts on the same site at once.
struct HushProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var color: Int
}

/// A Space is a set of tabs (Work, Personal, Shopping…). Each window shows one Space at a
/// time; switching Spaces swaps the whole tab bar. A Space can use its own Profile.
struct BrowserSpace: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String
    var color: Int
    /// nil = the default profile (the same website data as before Spaces existed).
    var profile: UUID?
}

enum SpacePalette {
    static let colors: [Color] = [
        Color(red: 0.55, green: 0.42, blue: 1.0),   // Hush purple
        Color(red: 0.25, green: 0.56, blue: 1.0),   // blue
        Color(red: 0.20, green: 0.74, blue: 0.62),  // teal
        Color(red: 0.36, green: 0.78, blue: 0.36),  // green
        Color(red: 1.0, green: 0.72, blue: 0.20),   // yellow
        Color(red: 1.0, green: 0.52, blue: 0.24),   // orange
        Color(red: 1.0, green: 0.36, blue: 0.40),   // red
        Color(red: 0.96, green: 0.40, blue: 0.72),  // pink
    ]
    static func color(_ index: Int) -> Color { colors[((index % colors.count) + colors.count) % colors.count] }

    static let symbols = ["house.fill", "briefcase.fill", "cart.fill", "book.fill", "gamecontroller.fill",
                          "film.fill", "music.note", "airplane", "heart.fill", "star.fill",
                          "graduationcap.fill", "hammer.fill", "leaf.fill", "moon.stars.fill",
                          "paintpalette.fill", "dollarsign.circle.fill"]
}

/// Every Space and Profile (shared by all windows), and the website data store for each profile.
final class SpaceStore: ObservableObject {
    static let shared = SpaceStore()
    private static let spacesKey = "spaces"
    private static let profilesKey = "profiles"
    static let maxSpaces = 12
    static let maxProfiles = 8

    @Published private(set) var spaces: [BrowserSpace] = []
    @Published private(set) var profiles: [HushProfile] = []
    /// One data store per profile, shared by every window, so a sign-in shows up everywhere at once.
    private var stores: [UUID: WKWebsiteDataStore] = [:]

    private init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.profilesKey),
           let saved = try? JSONDecoder().decode([HushProfile].self, from: data) { profiles = Array(saved.prefix(Self.maxProfiles)) }
        if let data = d.data(forKey: Self.spacesKey),
           let saved = try? JSONDecoder().decode([BrowserSpace].self, from: data) { spaces = Array(saved.prefix(Self.maxSpaces)) }
        // A Space whose profile has gone uses the default one.
        let ids = Set(profiles.map(\.id))
        for i in spaces.indices where spaces[i].profile.map({ !ids.contains($0) }) ?? false { spaces[i].profile = nil }
        if spaces.isEmpty { spaces = [BrowserSpace(name: "Personal", symbol: "house.fill", color: 0)] }
    }

    var defaultSpace: BrowserSpace { spaces[0] }
    func space(_ id: UUID?) -> BrowserSpace? { spaces.first { $0.id == id } }
    func profile(_ id: UUID?) -> HushProfile? { profiles.first { $0.id == id } }

    // MARK: Website data

    func dataStore(forProfile id: UUID?) -> WKWebsiteDataStore {
        guard let id, profiles.contains(where: { $0.id == id }) else { return .default() }
        if let store = stores[id] { return store }
        let store = WKWebsiteDataStore(forIdentifier: id)
        stores[id] = store
        return store
    }

    func dataStore(forSpace id: UUID?) -> WKWebsiteDataStore { dataStore(forProfile: space(id)?.profile) }

    /// The default store plus every profile's (for Clear Website Data and Forget This Site).
    var allDataStores: [WKWebsiteDataStore] { [.default()] + profiles.map { dataStore(forProfile: $0.id) } }

    // MARK: Spaces

    @discardableResult
    func addSpace(name: String, symbol: String, color: Int, profile: UUID? = nil) -> BrowserSpace? {
        guard spaces.count < Self.maxSpaces else { return nil }
        let space = BrowserSpace(name: Self.clean(name, fallback: "Orbit \(spaces.count + 1)"), symbol: symbol, color: color, profile: profile)
        spaces.append(space)
        save()
        return space
    }

    func update(_ space: BrowserSpace) {
        guard let i = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        var fixed = space
        fixed.name = Self.clean(space.name, fallback: spaces[i].name)
        let profileChanged = spaces[i].profile != fixed.profile
        spaces[i] = fixed
        save()
        // The Space's open tabs move to the new profile's website data.
        if profileChanged { BrowserModel.all.allObjects.forEach { $0.spaceChangedProfile(space.id) } }
    }

    func removeSpace(_ id: UUID) {
        guard spaces.count > 1, let i = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces.remove(at: i)
        save()
        BrowserModel.all.allObjects.forEach { $0.spaceRemoved(id) }
    }

    func moveSpace(fromOffsets source: IndexSet, toOffset destination: Int) {
        spaces.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: Profiles

    @discardableResult
    func addProfile(name: String, color: Int) -> HushProfile? {
        guard profiles.count < Self.maxProfiles else { return nil }
        let profile = HushProfile(name: Self.clean(name, fallback: "Profile \(profiles.count + 1)"), color: color)
        profiles.append(profile)
        save()
        return profile
    }

    func renameProfile(_ id: UUID, to name: String) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].name = Self.clean(name, fallback: profiles[i].name)
        save()
    }

    /// Deletes a profile and all its website data. Spaces using it go back to the default
    /// profile; their open tabs reload there.
    func removeProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        let affected = spaces.filter { $0.profile == id }.map(\.id)
        for i in spaces.indices where spaces[i].profile == id { spaces[i].profile = nil }
        profiles.removeAll { $0.id == id }
        save()
        for space in affected { BrowserModel.all.allObjects.forEach { $0.spaceChangedProfile(space) } }
        // Opened just to wipe it if it wasn't used since launch (otherwise its cookies and
        // logins stayed on disk for good).
        // Its own history and bookmarks go with it.
        HistoryStore.forget(profile: id)
        BookmarkStore.forget(profile: id)
        RecentlyClosed.shared.clear(profile: id)
        try? FileManager.default.removeItem(at: AppPaths.support.appendingPathComponent("Profiles").appendingPathComponent(id.uuidString))
        let store = stores.removeValue(forKey: id) ?? WKWebsiteDataStore(forIdentifier: id)
        // Wipe the data straight away, then remove the store itself once nothing uses it.
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                WKWebsiteDataStore.remove(forIdentifier: id) { _ in }
            }
        }
    }

    private static func clean(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(30))
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(spaces), forKey: Self.spacesKey)
        d.set(try? JSONEncoder().encode(profiles), forKey: Self.profilesKey)
    }
}

// MARK: - The Space button (left of the tabs)

struct SpaceButton: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var store = SpaceStore.shared
    @State private var hovering = false
    @State private var editing: BrowserSpace?

    var body: some View {
        let space = store.space(model.spaceID) ?? store.defaultSpace
        Menu {
            ForEach(Array(store.spaces.enumerated()), id: \.element.id) { index, item in
                Button {
                    model.switchSpace(to: item.id)
                } label: {
                    Label(item.name + (item.id == space.id ? "  ✓" : "") + (index < 9 ? "    ⌃\(index + 1)" : ""), systemImage: item.symbol)
                }
            }
            Divider()
            Button("New Orbit…") {
                editing = BrowserSpace(name: "", symbol: SpacePalette.symbols[store.spaces.count % SpacePalette.symbols.count],
                                       color: store.spaces.count % SpacePalette.colors.count)
            }
            .disabled(store.spaces.count >= SpaceStore.maxSpaces)
            Button("Edit “\(space.name)”…") { editing = space }
            Button("Orbits & Profiles Settings…") { SettingsOpener.open(tab: .spaces) }
        } label: {
            ZStack {
                Circle().fill(SpacePalette.color(space.color).gradient)
                Image(systemName: space.symbol)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 20, height: 20)
            .overlay(alignment: .bottomTrailing) {
                if store.profile(space.profile) != nil {
                    Circle().fill(Color.white).frame(width: 7, height: 7)
                        .overlay(Circle().fill(SpacePalette.color(store.profile(space.profile)?.color ?? 0)).frame(width: 5, height: 5))
                        .offset(x: 2, y: 2)
                }
            }
            .padding(5)
            .background(Circle().fill(Color.primary.opacity(hovering ? 0.08 : 0)))
            .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("\(space.name) — click to switch Orbit (⌃1–9)")
        .popover(item: $editing, arrowEdge: .bottom) { space in
            SpaceEditor(space: space, isNew: !store.spaces.contains { $0.id == space.id }) { result in
                if let result {
                    if store.spaces.contains(where: { $0.id == result.id }) {
                        store.update(result)
                    } else if let made = store.addSpace(name: result.name, symbol: result.symbol, color: result.color, profile: result.profile) {
                        model.switchSpace(to: made.id)
                    }
                }
                editing = nil
            }
        }
    }
}

/// Name, icon, colour and profile for a Space.
struct SpaceEditor: View {
    @State var space: BrowserSpace
    let isNew: Bool
    let done: (BrowserSpace?) -> Void
    @ObservedObject private var store = SpaceStore.shared
    @State private var newProfileName = ""
    @State private var makingProfile = false
    /// A profile made in this editor: removed again if you cancel (it used to be left behind).
    @State private var madeProfile: UUID?
    /// Saved with Create/Save (or Return): anything else, Cancel or a click outside the popover, drops a profile made here.
    @State private var saved = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(SpacePalette.color(space.color).gradient)
                    Image(systemName: space.symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                TextField("Orbit name", text: $space.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit { saved = true; done(space) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 8), spacing: 6) {
                ForEach(SpacePalette.symbols, id: \.self) { symbol in
                    Button { space.symbol = symbol } label: {
                        Image(systemName: symbol).font(.system(size: 11.5))
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(space.symbol == symbol ? SpacePalette.color(space.color).opacity(0.25) : Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                ForEach(SpacePalette.colors.indices, id: \.self) { index in
                    Button { space.color = index } label: {
                        Circle().fill(SpacePalette.colors[index].gradient).frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(space.color == index ? 0.7 : 0), lineWidth: 2).padding(-3))
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Picker("Profile", selection: $space.profile) {
                    Text("Default").tag(UUID?.none)
                    ForEach(store.profiles) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                if makingProfile {
                    HStack {
                        TextField("New profile name", text: $newProfileName).textFieldStyle(.roundedBorder)
                            .onSubmit(addProfile)
                        Button("Add", action: addProfile)
                    }
                } else if store.profiles.count < SpaceStore.maxProfiles {
                    Button("New Profile…") { makingProfile = true }.buttonStyle(.link).font(.system(size: 11.5))
                }
                Text("Each profile has its own cookies and sign-ins, so you can use two accounts on one site.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { done(nil) }
                .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create Orbit" : "Save") { saved = true; done(space) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { if isNew { nameFocused = true } }
        // Closed without saving (Cancel, Esc, or a click outside the popover): a profile made
        // here goes again. A click outside used to leave it behind, used by no Orbit.
        .onDisappear { if !saved, let madeProfile { store.removeProfile(madeProfile) } }
    }

    private func addProfile() {
        if let profile = store.addProfile(name: newProfileName, color: (store.profiles.count + 2) % SpacePalette.colors.count) {
            space.profile = profile.id
            madeProfile = profile.id
        }
        newProfileName = ""
        makingProfile = false
    }
}

// MARK: - Settings › Spaces & Profiles

struct SpacesSettings: View {
    @ObservedObject private var store = SpaceStore.shared
    @State private var editing: BrowserSpace?
    @State private var renaming: HushProfile?
    @State private var newProfile = ""

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .spaces, subtitle: "Orbits keep sets of tabs apart, such as Work and Personal. Give an Orbit its own profile to keep its cookies and sign-ins separate too.")
            }
            Section {
                ForEach(store.spaces) { space in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(SpacePalette.color(space.color).gradient)
                            Image(systemName: space.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        }
                        .frame(width: 28, height: 28)
                        .shadow(color: SpacePalette.color(space.color).opacity(0.35), radius: 3, y: 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(space.name)
                            Text("Profile: \(store.profile(space.profile)?.name ?? "Default")")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { editing = space } label: { Image(systemName: "slider.horizontal.3") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit name, icon, colour and profile")
                            .popover(isPresented: Binding(get: { editing?.id == space.id }, set: { if !$0 { editing = nil } })) {
                                SpaceEditor(space: space, isNew: false) { result in
                                    if let result { store.update(result) }
                                    editing = nil
                                }
                            }
                        Button(role: .destructive) {
                            // Asks first: one stray click used to remove the Orbit straight away.
                            let first = store.spaces.first { $0.id != space.id }?.name ?? "your first Orbit"
                            DialogHost.settings.present(HushDialog(
                                art: .symbol(space.symbol), theme: .danger, motion: .drift,
                                title: "Remove the “\(space.name)” Orbit?",
                                message: "Its open tabs move to \(first). Its name, icon and colour are gone for good.",
                                choices: [.init(title: "Cancel", role: .cancel), .init(title: "Remove", role: .destructive)],
                                completion: { choice, _ in if choice == 1 { store.removeSpace(space.id) } }))
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .disabled(store.spaces.count <= 1)
                            .accessibilityLabel("Remove Orbit")   // no tooltip: the row vanishes when clicked
                    }
                }
                .onMove { store.moveSpace(fromOffsets: $0, toOffset: $1) }
                Button {
                    store.addSpace(name: "", symbol: SpacePalette.symbols[store.spaces.count % SpacePalette.symbols.count],
                                   color: store.spaces.count % SpacePalette.colors.count)
                } label: {
                    Label("Add Orbit", systemImage: "plus.circle.fill").foregroundStyle(Color.accentColor)
                }
                // At the limit it used to do nothing at all when clicked.
                .disabled(store.spaces.count >= SpaceStore.maxSpaces)
                .help(store.spaces.count >= SpaceStore.maxSpaces ? "You can have up to \(SpaceStore.maxSpaces) Orbits" : "")
                .buttonStyle(.borderless)
                .disabled(store.spaces.count >= SpaceStore.maxSpaces)
            } header: { SectionTitle("Orbits") } footer: {
                Footnote("Switch Orbits with the button left of your tabs, ⌃1 to ⌃9, or the Command Palette (⌘K). Drag to reorder.")
            }
            Section {
                HStack {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 18)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Default")
                        Text("Used by Orbits without their own profile").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                ForEach(store.profiles) { profile in
                    HStack {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 18))
                        .foregroundStyle(SpacePalette.color(profile.color).gradient)
                        if renaming?.id == profile.id {
                            TextField("Name", text: Binding(get: { renaming?.name ?? "" }, set: { renaming?.name = $0 }))
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { store.renameProfile(profile.id, to: renaming?.name ?? ""); renaming = nil }
                        } else {
                            Text(profile.name)
                        }
                        Spacer()
                        let users = store.spaces.filter { $0.profile == profile.id }.count
                        Text(users == 0 ? "Not used" : users == 1 ? "1 Orbit" : "\(users) Orbits")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Button { renaming = profile } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless).accessibilityLabel("Rename")
                        Button(role: .destructive) { confirmDelete(profile) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("New profile name", text: $newProfile)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addProfile)
                    Button("Add Profile", action: addProfile)
                        .disabled(store.profiles.count >= SpaceStore.maxProfiles)
                }
            } header: { SectionTitle("Profiles") } footer: {
                Footnote("A profile has its own cookies, sign-ins, site data, cache, history and bookmarks. Passwords are shared. Deleting a profile erases its website data, history and bookmarks.")
            }
        }
        .formStyle(SafariFormStyle())
    }

    private func addProfile() {
        store.addProfile(name: newProfile, color: (store.profiles.count + 2) % SpacePalette.colors.count)
        newProfile = ""
    }

    private func confirmDelete(_ profile: HushProfile) {
        DialogHost.settings.present(HushDialog(
            art: .symbol("person.crop.circle.badge.minus"), theme: .danger, motion: .drift,
            title: "Delete “\(profile.name)”?",
            message: "Signs you out of every site in this profile and erases its website data, history and bookmarks. Orbits using it switch to the default profile.",
            choices: [.init(title: "Cancel", role: .cancel), .init(title: "Delete", role: .destructive)],
            completion: { choice, _ in if choice == 1 { store.removeProfile(profile.id) } }))
    }
}
