import SwiftUI
import AppKit

struct BlockSetupView: View {
    let onStart: (_ minutes: Int, _ apps: [String], _ websites: [String]) -> Void
    let onCancel: () -> Void

    @ObservedObject private var service = BlockerService.shared
    @State private var selectedMinutes = 60
    @State private var customText = "60"
    @State private var items: [BlockItem] = []
    @State private var checked: Set<String> = []

    private let durationOptions: [(Int, String)] = [
        (25, "25m"), (60, "1h"), (120, "2h")
    ]

    private var isCustomSelected: Bool {
        !durationOptions.contains { $0.0 == selectedMinutes }
    }

    var body: some View {
        VStack(spacing: 0) {
            durationRow
            Divider()
            itemList
            Divider()
            actionBar
        }
        .frame(width: 560, height: 660)
        .onAppear(perform: loadItems)
    }

    // MARK: - Duration

    private var durationRow: some View {
        HStack(spacing: 8) {
            Text("Duration")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            ForEach(durationOptions, id: \.0) { mins, label in
                Button(label) {
                    selectedMinutes = mins
                    customText = "\(mins)"
                }
                .buttonStyle(DurationButtonStyle(selected: selectedMinutes == mins))
            }
            HStack(spacing: 3) {
                TextField("", text: $customText)
                    .textFieldStyle(.plain)
                    .font(.subheadline.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 38)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .background(isCustomSelected ? Color.blue : Color(NSColor.controlBackgroundColor))
                    .foregroundColor(isCustomSelected ? .white : .primary)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor), lineWidth: 1))
                    .onChange(of: customText) { val in
                        let digits = val.filter(\.isNumber)
                        if digits != val { customText = digits }
                        if let m = Int(digits), m > 0 {
                            selectedMinutes = min(m, 1440)
                        }
                    }
                Text("m")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Items list

    private var itemList: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No apps or websites configured")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Add items in Configure first.")
                        .font(.caption)
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

    private var configSection: some View {
        Group {
            if !configItems.isEmpty {
                sectionHeader("YOUR BLOCK LIST")
                ForEach(configItems) { item in itemRow(item) }
            }
        }
    }

    private var suggestionSection: some View {
        Group {
            sectionHeader("SUGGESTED")
            ForEach(suggestedItems) { item in itemRow(item) }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.caption2.bold())
                .foregroundColor(.secondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
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
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 6) {
                Text(item.category.rawValue)
                    .font(.caption)
                    .foregroundColor(item.category.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(item.category.color.opacity(0.10))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(item.category.color.opacity(0.30), lineWidth: 1.0))

                if item.todayDuration >= 60 {
                    Text(item.todayDuration.formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(item.category == .entertainment || item.category == .social ? .orange : .secondary)
                        .frame(width: 46, alignment: .trailing)
                } else {
                    Text("").frame(width: 46)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Action bar

    private var checkedApps:  [String] { items.filter { checked.contains($0.id) && $0.isApp  }.map(\.blockingName) }
    private var checkedSites: [String] { items.filter { checked.contains($0.id) && !$0.isApp }.map(\.blockingName) }
    private var checkedTotal: Int { checkedApps.count + checkedSites.count }

    private var actionBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Start") {
                    confirmAndStart()
                }
                .buttonStyle(.borderedProminent)
                .disabled(checkedTotal == 0)
                .tint(Color(red: 0.10, green: 0.22, blue: 0.82))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private func confirmAndStart() {
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

    // MARK: - Data loading

    private var configItems: [BlockItem] { items.filter(\.isFromConfig).sorted { $0.todayDuration > $1.todayDuration } }
    private var suggestedItems: [BlockItem] { items.filter { !$0.isFromConfig }.sorted { $0.todayDuration > $1.todayDuration } }

    private func loadItems() {
        let config = service.config
        let store = ActivityStore.shared
        let selfName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Lock In"
        let selfBundleID = Bundle.main.bundleIdentifier ?? ""
        var result: [BlockItem] = []

        // Single dual-path query (works with Screen Time DB and custom JSONL)
        let topUsage = store.topApps(forDays: 1, limit: 50)
        var durationByName: [String: TimeInterval] = [:]
        var durationByDomain: [String: TimeInterval] = [:]
        var bundleIDByName: [String: String] = [:]
        for u in topUsage {
            if let domain = u.domain {
                durationByDomain[domain, default: 0] += u.duration
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
            let dur = durationByDomain[domain] ?? 0
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
                guard !configWebsites.contains(domain) else { continue }
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

        items = result
        checked = Set(result.map(\.id))
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
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? Color.blue : Color(NSColor.controlBackgroundColor))
            .foregroundColor(selected ? .white : .primary)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
