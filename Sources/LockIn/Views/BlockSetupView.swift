import SwiftUI
import AppKit

private let blockSetupAccentBlue = Color(nsColor: .controlAccentColor)

struct BlockSetupView: View {
    let onStart: (_ minutes: Int, _ apps: [String], _ websites: [String]) -> Void
    let onCancel: () -> Void

    @ObservedObject private var service = BlockerService.shared
    @State private var selectedMinutes = 60
    @State private var customText = ""
    @State private var items: [BlockItem] = []
    @State private var checked: Set<String> = []
    @State private var isLoadingItems = true
    @FocusState private var isCustomFieldFocused: Bool

    private let durationOptions = [25, 60, 90]
    private enum SetupStep: String, CaseIterable {
        case list = "List"
        case timer = "Timer"
    }
    @State private var step: SetupStep = .list
    @State private var hoveredStep: SetupStep?

    private var isCustomSelected: Bool {
        !durationOptions.contains(selectedMinutes)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .top)
        .onAppear(perform: loadItems)
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
                            isCustomFieldFocused = false
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
        .background(Color(NSColor.windowBackgroundColor))
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
        Group {
            if isLoadingItems {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading apps and websites…")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No apps or websites configured")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text("Add items in Configure first.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if suggestedItems.count > 0 {
                            suggestionSection
                        }
                        configSection
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var timerStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Session length")
                    .font(.title3.weight(.semibold))
                Text("Choose how long this block should stay active.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(durationOptions, id: \.self) { mins in
                    Button {
                        selectedMinutes = mins
                        isCustomFieldFocused = false
                    } label: {
                        Text("\(mins) min")
                    }
                    .buttonStyle(DurationButtonStyle(selected: selectedMinutes == mins))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Custom")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isCustomSelected ? blockSetupAccentBlue : .secondary)

                HStack(spacing: 8) {
                    TextField("Type minutes", text: $customText)
                        .textFieldStyle(.plain)
                        .font(.title3.monospacedDigit())
                        .focused($isCustomFieldFocused)
                        .onChange(of: customText) { val in
                            let digits = val.filter(\.isNumber)
                            if digits != val { customText = digits }
                            if let m = Int(digits), m > 0 {
                                selectedMinutes = min(m, 1440)
                            }
                        }

                    Text("min")
                        .font(.body.weight(.medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(width: 220, height: 48)
                .background(isCustomSelected ? blockSetupAccentBlue.opacity(0.16) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isCustomSelected ? blockSetupAccentBlue : Color(NSColor.separatorColor), lineWidth: 1)
                )
                .cornerRadius(12)
                .onTapGesture {
                    isCustomFieldFocused = true
                }
            }

            Text("Selected: \(selectedMinutes) minutes")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var configSection: some View {
        Group {
            if !configItems.isEmpty {
                groupedItemsSection(apps: configAppItems, websites: configWebsiteItems)
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
                    isCustomFieldFocused = false
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
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func confirmAndStart() {
        guard selectedMinutes > 0 else { return }
        isCustomFieldFocused = false

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

    // MARK: - Data loading

    private var configItems: [BlockItem] { items.filter(\.isFromConfig).sorted { $0.todayDuration > $1.todayDuration } }
    private var configAppItems: [BlockItem] { configItems.filter(\.isApp) }
    private var configWebsiteItems: [BlockItem] { configItems.filter { !$0.isApp } }
    private var suggestedItems: [BlockItem] { items.filter { !$0.isFromConfig }.sorted { $0.todayDuration > $1.todayDuration } }
    private var suggestedAppItems: [BlockItem] { suggestedItems.filter(\.isApp) }
    private var suggestedWebsiteItems: [BlockItem] { suggestedItems.filter { !$0.isApp } }

    private func loadItems() {
        let config = service.config
        let store = ActivityStore.shared
        let selfName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Lock In"
        let selfBundleID = Bundle.main.bundleIdentifier ?? ""
        isLoadingItems = true

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
                self.checked = Set(result.map(\.id))
                self.isLoadingItems = false
            }
        }
    }
}

// MARK: - Supporting types

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
            .background(selected ? blockSetupAccentBlue : Color(NSColor.controlBackgroundColor))
            .foregroundColor(selected ? .white : .primary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? blockSetupAccentBlue : Color(NSColor.separatorColor), lineWidth: 1)
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
