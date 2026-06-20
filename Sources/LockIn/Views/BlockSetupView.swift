import SwiftUI
import AppKit
import TimerInputSupport

private let blockSetupAccentBlue = Color(nsColor: .controlAccentColor)
private let timerFieldWidth: CGFloat = 126
private let timerFieldHeight: CGFloat = 172
private let timerSeparatorWidth: CGFloat = 28
private enum TimerField: Hashable {
    case hours
    case minutes
    case seconds
}

struct BlockSetupView: View {
    let onStart: (_ minutes: Int, _ apps: [String], _ websites: [String]) -> Void
    let onCancel: () -> Void

    @ObservedObject private var service = BlockerService.shared
    @State private var selectedMinutes = 60
    @State private var customText = ""
    @State private var hourInput = "01"
    @State private var minuteInput = "00"
    @State private var secondInput = "00"
    @State private var items: [BlockItem] = []
    @State private var checked: Set<String> = []
    @State private var isLoadingItems = true
    @State private var focusedTimeField: TimerField?
    @State private var hasInitializedSelection = false
    @State private var manageSection: ManageSection = .apps
    @State private var appSearch = ""
    @State private var newWebsite = ""
    @State private var websiteError = ""

    private let durationOptions = [25, 60, 90]
    private enum SetupStep: String, CaseIterable {
        case list = "List"
        case timer = "Timer"
    }
    private enum ManageSection: String, CaseIterable {
        case apps = "Apps"
        case websites = "Websites"
        case limits = "Limits"
    }
    @State private var step: SetupStep = .list
    @State private var hoveredStep: SetupStep?
    @State private var hoveredManageSection: ManageSection?

    private var isCustomSelected: Bool {
        !durationOptions.contains(selectedMinutes)
    }

    private var hoursText: Binding<String> {
        Binding(
            get: { hourInput },
            set: { updateSelectedDuration(hours: $0, minutes: minuteInput, seconds: secondInput) }
        )
    }

    private var minutesText: Binding<String> {
        Binding(
            get: { minuteInput },
            set: { updateSelectedDuration(hours: hourInput, minutes: $0, seconds: secondInput) }
        )
    }

    private var secondsText: Binding<String> {
        Binding(
            get: { secondInput },
            set: { updateSelectedDuration(hours: hourInput, minutes: minuteInput, seconds: $0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .top)
        .onAppear {
            syncTimeFieldsFromSelection()
            loadItems()
        }
    }

    private var topBar: some View {
        ZStack {
            HStack {
                Spacer()
                    .frame(width: 196)
                Spacer()
            }

            HStack(spacing: 0) {
                ForEach(SetupStep.allCases, id: \.self) { current in
                    Button {
                        guard current != .timer || checkedTotal > 0 else { return }
                        step = current
                        if current == .list {
                            focusedTimeField = nil
                        }
                    } label: {
                        Text(current.rawValue)
                            .font(.body.weight(.semibold))
                            .foregroundColor(tabForeground(for: current))
                            .frame(width: 104, height: 34)
                            .background(tabBackground(for: current))
                    }
                    .buttonStyle(.plain)
                    .disabled(current == .timer && checkedTotal == 0)
                    .onHover { isHovering in
                        hoveredStep = isHovering ? current : (hoveredStep == current ? nil : hoveredStep)
                    }

                    if current != SetupStep.allCases.last {
                        Divider()
                            .frame(height: 18)
                    }
                }
            }
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .appWindowSurface()
    }

    private var content: some View {
        Group {
            switch step {
            case .list:
                itemList
            case .timer:
                timerStep
            }
        }
    }

    // MARK: - Items list

    private var itemList: some View {
        ScrollView {
            VStack(spacing: 18) {
                if suggestedItems.count > 0 {
                    suggestionSection
                }
                if !items.isEmpty {
                    configSection
                } else {
                    emptySelectionState
                }
                manageSectionCard
            }
            .padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity)
    }

    private var emptySelectionState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No apps or websites selected yet")
                .font(.body)
                .foregroundColor(.secondary)
            Text("Add what you want to block below, then continue to the timer.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private var timerStep: some View {
        VStack(spacing: 34) {
            VStack(spacing: -6) {
                HStack(alignment: .center, spacing: 0) {
                    timeLabel("hr")
                    timeLabelSeparator
                    timeLabel("min")
                    timeLabelSeparator
                    timeLabel("sec")
                }

                HStack(alignment: .center, spacing: 0) {
                    timeField(hoursText, field: .hours)
                    timeSeparator
                    timeField(minutesText, field: .minutes)
                    timeSeparator
                    timeField(secondsText, field: .seconds)
                }
            }

            VStack(spacing: 14) {
                Text("Presets")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    ForEach(durationOptions, id: \.self) { mins in
                        Button {
                            selectedMinutes = mins
                            syncTimeFieldsFromSelection()
                            focusedTimeField = nil
                        } label: {
                            Text("\(mins) min")
                        }
                        .buttonStyle(DurationButtonStyle(selected: selectedMinutes == mins))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 52)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var configSection: some View {
        Group {
            if !configItems.isEmpty {
                VStack(spacing: 0) {
                    sectionHeader("SELECTED")
                    groupedItemsSection(apps: configAppItems, websites: configWebsiteItems)
                }
            }
        }
    }

    private var suggestionSection: some View {
        Group {
            sectionHeader("SUGGESTED")
            groupedItemsSection(apps: suggestedAppItems, websites: suggestedWebsiteItems)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var manageSectionCard: some View {
        VStack(spacing: 0) {
            sectionHeader("CONFIGURE")
            manageSectionPicker
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 14)

            Group {
                switch manageSection {
                case .apps:
                    appsManager
                case .websites:
                    websitesManager
                case .limits:
                    limitsManager
                }
            }
        }
    }

    private var manageSectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(ManageSection.allCases, id: \.self) { section in
                Button {
                    manageSection = section
                } label: {
                    Text(section.rawValue)
                        .font(.body.weight(.semibold))
                        .foregroundColor(manageSectionForeground(for: section))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(manageSectionBackground(for: section))
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredManageSection = isHovering ? section : (hoveredManageSection == section ? nil : hoveredManageSection)
                }

                if section != ManageSection.allCases.last {
                    Divider()
                        .frame(height: 18)
                }
            }
        }
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var appsManager: some View {
        let displayedApps = Array(filteredInstalledApps.prefix(10))

        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search apps…", text: $appSearch)
                    .textFieldStyle(.plain)
                if !appSearch.isEmpty {
                    Button {
                        appSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .appCard(cornerRadius: 12)

            if displayedApps.isEmpty {
                HStack {
                    Text("No apps match your search")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .appCard(cornerRadius: 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayedApps.enumerated()), id: \.element.id) { index, app in
                        appConfigRow(app)
                        if index < displayedApps.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .appCard(cornerRadius: 14)
            }

            HStack {
                let count = service.config.blockedApps.count
                Text(count == 0 ? "No apps selected yet" : "\(count) app\(count == 1 ? "" : "s") ready to block")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func appConfigRow(_ app: AppInfo) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: blockedAppBinding(app.name))
                .labelsHidden()
                .toggleStyle(.checkbox)

            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 22, height: 22)

            Text(app.name)
                .font(.body)
                .lineLimit(1)

            Spacer()

            if let existingItem = items.first(where: { $0.isApp && $0.blockingName == app.name }) {
                Text(existingItem.category.rawValue)
                    .font(.body)
                    .foregroundColor(existingItem.category.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(existingItem.category.color.opacity(0.10))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(existingItem.category.color.opacity(0.30), lineWidth: 1.0))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var websitesManager: some View {
        VStack(spacing: 12) {
            if service.config.blockedWebsites.isEmpty {
                HStack {
                    Text("No websites added yet")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .appCard(cornerRadius: 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(service.config.blockedWebsites.enumerated()), id: \.element) { index, site in
                        websiteConfigRow(site)
                        if index < service.config.blockedWebsites.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .appCard(cornerRadius: 14)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    TextField("Add domain (e.g. facebook.com)", text: $newWebsite)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .appCard(cornerRadius: 12)
                        .onSubmit { addWebsite() }

                    Button("Add") {
                        addWebsite()
                    }
                    .buttonStyle(FooterCapsuleButtonStyle(kind: .primary))
                    .disabled(newWebsite.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !websiteError.isEmpty {
                    Text(websiteError)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Instant tab blocking")
                        .font(.footnote.weight(.medium))
                    Text(service.primedBrowserIDs.isEmpty
                        ? "Not set up — open browsers, then tap Setup"
                        : "\(service.primedBrowserIDs.count) browser\(service.primedBrowserIDs.count == 1 ? "" : "s") authorised")
                        .font(.footnote)
                        .foregroundColor(service.primedBrowserIDs.isEmpty ? .orange : .secondary)
                }
                Spacer()
                Button("Setup…") {
                    grantBrowserPermissions()
                }
                .buttonStyle(FooterCapsuleButtonStyle(kind: .secondary))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .appCard(cornerRadius: 14)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func websiteConfigRow(_ site: String) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: blockedWebsiteBinding(site))
                .labelsHidden()
                .toggleStyle(.checkbox)

            Image(systemName: "globe")
                .foregroundColor(service.config.category(for: site).color)
                .frame(width: 20)

            Text(site)
                .font(.body)

            Spacer()

            Text(service.config.category(for: site).rawValue)
                .font(.body)
                .foregroundColor(service.config.category(for: site).color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(service.config.category(for: site).color.opacity(0.10))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(service.config.category(for: site).color.opacity(0.30), lineWidth: 1.0))

            Button {
                service.config.blockedWebsites.removeAll { $0 == site }
                service.saveConfig()
                loadItems()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private let limitPresets = [(0, "Off"), (5, "5m"), (10, "10m"), (15, "15m"), (30, "30m"), (60, "1h"), (90, "90m"), (120, "2h")]
    private let limitCategories: [AppCategory] = [.entertainment, .social, .work, .development, .communication, .creative]

    private var limitsManager: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Daily screen-time alerts")
                    .font(.headline)
                Text("Get a notification when you exceed a category limit today. Resets at midnight.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                ForEach(Array(limitCategories.enumerated()), id: \.element.id) { index, category in
                    HStack(spacing: 12) {
                        Image(systemName: category.icon)
                            .frame(width: 20)
                            .foregroundColor(category.color)
                        Text(category.rawValue)
                            .font(.body)
                        Spacer()
                        Picker("", selection: limitBinding(category)) {
                            ForEach(limitPresets, id: \.0) { mins, label in
                                Text(label).tag(mins)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if index < limitCategories.count - 1 {
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .appCard(cornerRadius: 14)

            HStack {
                let active = limitCategories.filter {
                    (service.config.categoryLimits[$0.rawValue] ?? 0) > 0
                }.count
                Text(active == 0 ? "No limits set" : "\(active) limit\(active == 1 ? "" : "s") active")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func groupedItemsSection(apps: [BlockItem], websites: [BlockItem]) -> some View {
        VStack(spacing: 0) {
            if !apps.isEmpty {
                subsectionHeader("Apps")
                ForEach(apps) { item in itemRow(item) }
            }

            if !websites.isEmpty {
                subsectionHeader("Websites")
                ForEach(websites) { item in itemRow(item) }
            }
        }
    }

    private func subsectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundColor(.secondary.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func itemRow(_ item: BlockItem) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { checked.contains(item.id) },
                set: { if $0 { checked.insert(item.id) } else { checked.remove(item.id) } }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            Group {
                if let img = item.icon {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                } else if item.isApp {
                    Image(systemName: "app.fill").foregroundColor(.secondary)
                } else {
                    Image(systemName: "globe").foregroundColor(item.category.color)
                }
            }
            .frame(width: 20, height: 20)

            Text(item.displayName)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Text(item.category.rawValue)
                .font(.body)
                .foregroundColor(item.category.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(item.category.color.opacity(0.10))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(item.category.color.opacity(0.30), lineWidth: 1.0))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Action bar

    private var checkedApps:  [String] { items.filter { checked.contains($0.id) && $0.isApp  }.map(\.blockingName) }
    private var checkedSites: [String] { items.filter { checked.contains($0.id) && !$0.isApp }.map(\.blockingName) }
    private var checkedTotal: Int { checkedApps.count + checkedSites.count }

    private var actionBar: some View {
        HStack(spacing: 18) {
            if step == .list {
                Button("Cancel", action: onCancel)
                    .buttonStyle(FooterCapsuleButtonStyle(kind: .secondary))

                Button("Next") {
                    step = .timer
                }
                .buttonStyle(FooterCapsuleButtonStyle(kind: .primary))
                .disabled(checkedTotal == 0)
            } else {
                Button("Back") {
                    step = .list
                    focusedTimeField = nil
                }
                .buttonStyle(FooterCapsuleButtonStyle(kind: .secondary))

                Button("Start") {
                    confirmAndStart()
                }
                .buttonStyle(FooterCapsuleButtonStyle(kind: .primary))
                .disabled(checkedTotal == 0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .appWindowSurface()
    }

    private func confirmAndStart() {
        guard selectedMinutes > 0 else { return }
        focusedTimeField = nil

        guard selectedMinutes > 120 else {
            onStart(selectedMinutes, checkedApps, checkedSites)
            return
        }
        let h = selectedMinutes / 60
        let m = selectedMinutes % 60
        let label = m == 0 ? "\(h)h" : "\(h)h \(m)m"
        let alert = NSAlert()
        alert.messageText = "Start a \(label) session?"
        alert.informativeText = "This is a long session. Sessions cannot be cancelled once started."
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            onStart(selectedMinutes, checkedApps, checkedSites)
        }
    }

    private func tabBackground(for step: SetupStep) -> some View {
        Capsule()
            .fill(tabFill(for: step))
            .padding(2)
    }

    private func tabForeground(for step: SetupStep) -> Color {
        self.step == step ? .primary : .secondary
    }

    private func tabFill(for step: SetupStep) -> Color {
        if self.step == step {
            return Color.white.opacity(0.16)
        }
        if hoveredStep == step {
            return Color.white.opacity(0.08)
        }
        return .clear
    }

    private func manageSectionBackground(for section: ManageSection) -> some View {
        Capsule()
            .fill(manageSectionFill(for: section))
            .padding(2)
    }

    private func manageSectionForeground(for section: ManageSection) -> Color {
        manageSection == section ? .primary : .secondary
    }

    private func manageSectionFill(for section: ManageSection) -> Color {
        if manageSection == section {
            return Color.white.opacity(0.16)
        }
        if hoveredManageSection == section {
            return Color.white.opacity(0.08)
        }
        return .clear
    }

    // MARK: - Data loading

    private var configItems: [BlockItem] { items.filter(\.isFromConfig).sorted { $0.todayDuration > $1.todayDuration } }
    private var configAppItems: [BlockItem] { configItems.filter(\.isApp) }
    private var configWebsiteItems: [BlockItem] { configItems.filter { !$0.isApp } }
    private var suggestedItems: [BlockItem] { items.filter { !$0.isFromConfig }.sorted { $0.todayDuration > $1.todayDuration } }
    private var suggestedAppItems: [BlockItem] { suggestedItems.filter(\.isApp) }
    private var suggestedWebsiteItems: [BlockItem] { suggestedItems.filter { !$0.isApp } }
    private var filteredInstalledApps: [AppInfo] {
        let apps = AppScanner.shared.installedApps()
        guard !appSearch.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(appSearch) }
    }

    private func loadItems() {
        let config = service.config
        let store = ActivityStore.shared
        let selfName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Lock In"
        let selfBundleID = Bundle.main.bundleIdentifier ?? ""
        isLoadingItems = true
        let existingChecked = checked

        DispatchQueue.global(qos: .userInitiated).async {
            var result: [BlockItem] = []

            // Single dual-path query (works with Screen Time DB and custom JSONL)
            let topUsage = store.topApps(forDays: 1, limit: 50)
            var durationByName: [String: TimeInterval] = [:]
            var durationByDomain: [String: TimeInterval] = [:]
            var bundleIDByName: [String: String] = [:]
            for u in topUsage {
                if let domain = u.domain {
                    if let normalized = DomainMatcher.normalizeHost(domain) {
                        durationByDomain[normalized, default: 0] += u.duration
                    }
                } else {
                    durationByName[u.appName.lowercased(), default: 0] += u.duration
                    if !u.bundleID.isEmpty { bundleIDByName[u.appName.lowercased()] = u.bundleID }
                }
            }

            // Build name→icon map from installed apps (covers apps not used today)
            let installedByName: [String: AppInfo] = Dictionary(
                AppScanner.shared.installedApps().map { ($0.name.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first }
            )

            func iconForApp(name: String, bundleID: String) -> NSImage? {
                if !bundleID.isEmpty,
                   let url = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).first {
                    return NSWorkspace.shared.icon(forFile: url.path)
                }
                if let info = installedByName[name.lowercased()] {
                    return NSWorkspace.shared.icon(forFile: info.bundlePath)
                }
                return nil
            }

            // Config apps — exclude this app
            for appName in config.blockedApps where appName.caseInsensitiveCompare(selfName) != .orderedSame {
                let dur = durationByName[appName.lowercased()] ?? 0
                let bid = bundleIDByName[appName.lowercased()] ?? ""
                let cat = bid.isEmpty ? config.category(for: appName) : config.category(for: bid)
                result.append(BlockItem(
                    displayName: appName, blockingName: appName,
                    isApp: true, isFromConfig: true,
                    todayDuration: dur, category: cat,
                    icon: iconForApp(name: appName, bundleID: bid)
                ))
            }

            // Config websites
            for domain in config.blockedWebsites {
                let dur = durationByDomain.reduce(into: 0.0) { total, entry in
                    if DomainMatcher.matches(host: entry.key, blockedDomain: domain) {
                        total += entry.value
                    }
                }
                result.append(BlockItem(
                    displayName: domain, blockingName: domain,
                    isApp: false, isFromConfig: true,
                    todayDuration: dur, category: config.category(for: domain),
                    icon: nil
                ))
            }

            // Suggestions from today's usage — exclude this app and already-configured items
            let configAppNamesLower = Set(config.blockedApps.map { $0.lowercased() })
            let configWebsites = Set(config.blockedWebsites)
            for usage in topUsage where usage.duration >= 60
                && usage.bundleID != selfBundleID
                && usage.appName.caseInsensitiveCompare(selfName) != .orderedSame {
                let cat = config.category(for: ActivityStore.eventKey(
                    ActivityEvent(timestamp: .now, duration: 0, appName: usage.appName,
                                  bundleID: usage.bundleID, domain: usage.domain)
                ))
                guard cat == .entertainment || cat == .social else { continue }

                if let domain = usage.domain {
                    guard !configWebsites.contains(where: { DomainMatcher.matches(host: domain, blockedDomain: $0) }) else { continue }
                    result.append(BlockItem(
                        displayName: domain, blockingName: domain,
                        isApp: false, isFromConfig: false,
                        todayDuration: usage.duration, category: cat,
                        icon: nil
                    ))
                } else {
                    guard !configAppNamesLower.contains(usage.appName.lowercased()) else { continue }
                    result.append(BlockItem(
                        displayName: usage.appName, blockingName: usage.appName,
                        isApp: true, isFromConfig: false,
                        todayDuration: usage.duration, category: cat,
                        icon: iconForApp(name: usage.appName, bundleID: usage.bundleID)
                    ))
                }
            }

            DispatchQueue.main.async {
                self.items = result
                if self.hasInitializedSelection {
                    let newIDs = Set(result.map(\.id))
                    let configIDs = Set(result.filter(\.isFromConfig).map(\.id))
                    self.checked = existingChecked.intersection(newIDs).union(configIDs)
                } else {
                    self.checked = Set(result.map(\.id))
                    self.hasInitializedSelection = true
                }
                self.isLoadingItems = false
            }
        }
    }

    private func blockedAppBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { service.config.blockedApps.contains(name) },
            set: { isOn in
                if isOn {
                    if !service.config.blockedApps.contains(name) {
                        service.config.blockedApps.append(name)
                    }
                } else {
                    service.config.blockedApps.removeAll { $0 == name }
                }
                service.saveConfig()
                loadItems()
            }
        )
    }

    private func blockedWebsiteBinding(_ site: String) -> Binding<Bool> {
        Binding(
            get: { checked.contains("\(site):web") },
            set: { isOn in
                let id = "\(site):web"
                if isOn {
                    checked.insert(id)
                } else {
                    checked.remove(id)
                }
            }
        )
    }

    private func addWebsite() {
        guard let site = DomainMatcher.normalizeHost(newWebsite) else { return }

        if service.config.blockedWebsites.contains(site) {
            websiteError = "\(site) is already in the list"
            return
        }
        guard site.contains(".") else {
            websiteError = "Enter a valid domain (e.g. facebook.com)"
            return
        }

        service.config.blockedWebsites.insert(site, at: 0)
        service.saveConfig()
        checked.insert("\(site):web")
        newWebsite = ""
        websiteError = ""
        loadItems()
    }

    private func grantBrowserPermissions() {
        let alert = NSAlert()
        alert.messageText = "Grant Browser Permissions"
        alert.informativeText = "Open the browsers you use, then click Continue. macOS will ask permission to control each one — click Allow on each prompt.\n\nIf you previously clicked Don't Allow, open System Settings → Privacy & Security → Automation and enable Lock In there."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            BlockerService.shared.primeBrowserPermissions {
                self.checkForDeniedBrowsers()
            }
        } else if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        }
    }

    private func checkForDeniedBrowsers() {
        let runningUnprimed = BlockerService.shared.knownBrowserBundleIDs.filter { bid in
            NSRunningApplication.runningApplications(withBundleIdentifier: bid).first != nil &&
            !BlockerService.shared.primedBrowserIDs.contains(bid)
        }
        guard !runningUnprimed.isEmpty else { return }

        let browserList = runningUnprimed
            .map(BlockerService.shared.browserName(forBundleID:))
            .joined(separator: ", ")

        let alert = NSAlert()
        alert.messageText = "Permission Not Granted"
        alert.informativeText = "\(browserList) denied permission. Lock In will keep those browsers open, but already-open tabs may need a manual refresh before website blocking fully takes effect.\n\nTo fix this, open System Settings → Privacy & Security → Automation and enable Lock In for each browser you use. macOS will not re-show the prompt automatically after you click Don't Allow."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        }
    }

    private func limitBinding(_ category: AppCategory) -> Binding<Int> {
        Binding(
            get: { service.config.categoryLimits[category.rawValue] ?? 0 },
            set: { mins in
                if mins == 0 {
                    service.config.categoryLimits.removeValue(forKey: category.rawValue)
                } else {
                    service.config.categoryLimits[category.rawValue] = mins
                }
                service.saveConfig()
            }
        )
    }

    private func updateSelectedDuration(hours: String, minutes: String, seconds: String) {
        let normalized = TimerInputRules.normalized(hours: hours, minutes: minutes, seconds: seconds)

        hourInput = normalized.hoursText
        minuteInput = normalized.minutesText
        secondInput = normalized.secondsText
        selectedMinutes = normalized.totalMinutes
        customText = "\(selectedMinutes)"
    }

    private func syncTimeFieldsFromSelection() {
        let fields = TimerInputRules.fields(fromTotalMinutes: selectedMinutes)
        hourInput = fields.hoursText
        minuteInput = fields.minutesText
        secondInput = fields.secondsText
        customText = "\(selectedMinutes)"
    }

    private func timeLabel(_ text: String) -> some View {
        Text(text)
            .font(.title2.weight(.regular))
            .foregroundColor(.secondary)
            .frame(width: timerFieldWidth)
    }

    private var timeLabelSeparator: some View {
        Color.clear
            .frame(width: timerSeparatorWidth, height: 1)
    }

    private var timeSeparator: some View {
        Text(":")
            .font(.system(size: 98, weight: .ultraLight, design: .rounded))
            .foregroundColor(.white.opacity(0.9))
            .offset(y: -8)
            .frame(width: timerSeparatorWidth)
    }

    private func timeField(_ binding: Binding<String>, field: TimerField) -> some View {
        SelectAllTimerTextField(text: binding, focusedField: $focusedTimeField, field: field)
            .frame(width: timerFieldWidth, height: timerFieldHeight)
    }
}

// MARK: - Supporting types

private struct SelectAllTimerTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focusedField: TimerField?
    let field: TimerField

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> SelectAllNSTextField {
        let textField = SelectAllNSTextField()
        textField.delegate = context.coordinator
        textField.formatter = TimerDigitsFormatter()
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.focusRingType = .none
        textField.alignment = .center
        textField.font = .systemFont(ofSize: 108, weight: .ultraLight)
        if let descriptor = textField.font?.fontDescriptor.withDesign(.rounded) {
            textField.font = NSFont(descriptor: descriptor, size: 108)
        }
        textField.textColor = NSColor.white.withAlphaComponent(0.9)
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byClipping
        textField.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.stringValue = text
        textField.onFocus = {
            focusedField = field
        }
        return textField
    }

    func updateNSView(_ nsView: SelectAllNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if let editor = nsView.currentEditor(), editor.string != text {
            editor.string = text
            editor.selectedRange = NSRange(location: text.count, length: 0)
        }
        nsView.onFocus = {
            focusedField = field
        }
        nsView.applyEditorAppearance()

        if focusedField == field,
           let window = nsView.window,
           window.firstResponder !== nsView,
           window.firstResponder !== nsView.currentEditor() {
            window.makeFirstResponder(nsView)
            DispatchQueue.main.async {
                guard focusedField == field else { return }
                nsView.applyEditorAppearance()
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SelectAllTimerTextField

        init(_ parent: SelectAllTimerTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            let resolved = TimerInputRules.resolvedTextAfterEditing(
                currentText: parent.text,
                proposedText: textField.stringValue
            )

            if textField.stringValue != resolved {
                textField.stringValue = resolved
                if let editor = textField.currentEditor() {
                    editor.string = resolved
                    editor.selectAll(nil)
                }
            }

            parent.text = resolved
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.focusedField = parent.field
            guard let textField = notification.object as? SelectAllNSTextField else { return }
            DispatchQueue.main.async {
                textField.applyEditorAppearance()
            }
        }
    }
}

private final class TimerDigitsFormatter: Formatter {
    override func string(for obj: Any?) -> String? {
        guard let string = obj as? String else { return nil }
        return TimerInputRules.sanitize(string)
    }

    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        obj?.pointee = TimerInputRules.sanitize(string) as NSString
        return true
    }

    override func isPartialStringValid(
        _ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
        proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
        originalString origString: String,
        originalSelectedRange origSelRange: NSRange,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        let partialString = partialStringPtr.pointee as String
        let resolved = TimerInputRules.validatedPartialString(
            originalText: origString,
            proposedText: partialString
        )
        guard resolved != partialString else { return true }

        partialStringPtr.pointee = resolved as NSString
        proposedSelRangePtr?.pointee = NSRange(location: resolved.count, length: 0)
        return false
    }
}

private final class SelectAllNSTextField: NSTextField {
    var onFocus: (() -> Void)?

    func applyEditorAppearance() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = .clear
        editor.backgroundColor = .clear
        editor.drawsBackground = false
        editor.selectedTextAttributes = [
            .backgroundColor: NSColor.controlAccentColor,
            .foregroundColor: NSColor.white.withAlphaComponent(0.95)
        ]
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            DispatchQueue.main.async { [weak self] in
                self?.applyEditorAppearance()
            }
        }
        return becameFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        DispatchQueue.main.async { [weak self] in
            self?.onFocus?()
            self?.applyEditorAppearance()
            self?.currentEditor()?.selectAll(nil)
        }
    }
}

private struct BlockItem: Identifiable {
    let displayName: String
    let blockingName: String
    let isApp: Bool
    let isFromConfig: Bool
    let todayDuration: TimeInterval
    let category: AppCategory
    let icon: NSImage?

    var id: String { blockingName + (isApp ? ":app" : ":web") }
}

private struct DurationButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(selected ? blockSetupAccentBlue : AppTheme.controlSurface)
            .foregroundColor(selected ? .white : .primary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? blockSetupAccentBlue : AppTheme.separator, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct FooterCapsuleButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(minWidth: 78)
            .frame(height: 25)
            .padding(.horizontal, 13)
            .foregroundColor(foregroundColor(isPressed: configuration.isPressed))
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            return isPressed ? blockSetupAccentBlue.opacity(0.86) : blockSetupAccentBlue
        case .secondary:
            return isPressed ? Color.white.opacity(0.14) : Color.white.opacity(0.10)
        }
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            return .white
        case .secondary:
            return isPressed ? .primary.opacity(0.92) : .primary
        }
    }
}
