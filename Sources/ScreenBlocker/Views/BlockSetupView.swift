import SwiftUI
import AppKit

struct BlockSetupView: View {
    let onStart: (_ minutes: Int, _ apps: [String], _ websites: [String]) -> Void
    let onCancel: () -> Void

    @ObservedObject private var service = BlockerService.shared
    @State private var selectedMinutes = 60
    @State private var items: [BlockItem] = []
    @State private var checked: Set<String> = []

    private let durationOptions: [(Int, String)] = [
        (25, "25m"), (60, "1h"), (120, "2h"), (240, "4h"), (480, "8h")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            durationRow
            Divider()
            itemList
            Divider()
            actionBar
        }
        .frame(width: 480)
        .onAppear(perform: loadItems)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Start Focus Session")
                    .font(.headline)
                Text("Choose duration and confirm what to block")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Duration

    private var durationRow: some View {
        HStack(spacing: 8) {
            Text("Duration")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            ForEach(durationOptions, id: \.0) { mins, label in
                Button(label) { selectedMinutes = mins }
                    .buttonStyle(DurationButtonStyle(selected: selectedMinutes == mins))
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
                        configSection
                        if suggestedItems.count > 0 {
                            suggestionSection
                        }
                    }
                }
                .frame(maxHeight: 280)
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
            sectionHeader("SUGGESTED – from today's usage")
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

            Image(systemName: item.isApp ? "app.fill" : "globe")
                .frame(width: 16)
                .foregroundColor(item.category.color)

            Text(item.displayName)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 6) {
                Text(item.category.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(5)

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
            if checkedTotal == 0 && !items.isEmpty {
                Text("Check at least one item to start blocking")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                Spacer()
                let total = checkedTotal
                Button("Start \(selectedMinutesLabel) Session – Block \(total) item\(total == 1 ? "" : "s")") {
                    onStart(selectedMinutes, checkedApps, checkedSites)
                }
                .buttonStyle(.borderedProminent)
                .disabled(total == 0)
                .tint(Color(red: 0.10, green: 0.22, blue: 0.82))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private var selectedMinutesLabel: String {
        durationOptions.first { $0.0 == selectedMinutes }?.1 ?? "\(selectedMinutes)m"
    }

    // MARK: - Data loading

    private var configItems: [BlockItem] { items.filter(\.isFromConfig) }
    private var suggestedItems: [BlockItem] { items.filter { !$0.isFromConfig } }

    private func loadItems() {
        let config = service.config
        let store = ActivityStore.shared
        let todayEvents = store.events(for: Date())
        let selfName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Screen Blocker"
        let selfBundleID = Bundle.main.bundleIdentifier ?? ""
        var result: [BlockItem] = []

        // Config apps — exclude this app
        for appName in config.blockedApps where appName.caseInsensitiveCompare(selfName) != .orderedSame {
            let dur = todayEvents
                .filter { $0.appName.caseInsensitiveCompare(appName) == .orderedSame }
                .reduce(0) { $0 + $1.duration }
            result.append(BlockItem(
                displayName: appName, blockingName: appName,
                isApp: true, isFromConfig: true,
                todayDuration: dur, category: .other
            ))
        }

        // Config websites
        for domain in config.blockedWebsites {
            let dur = todayEvents.filter { $0.domain == domain }.reduce(0) { $0 + $1.duration }
            result.append(BlockItem(
                displayName: domain, blockingName: domain,
                isApp: false, isFromConfig: true,
                todayDuration: dur, category: config.category(for: domain)
            ))
        }

        // Suggestions from today's usage — exclude this app
        let topUsage = store.topApps(for: Date(), limit: 20)
        for usage in topUsage where usage.duration >= 60
            && usage.bundleID != selfBundleID
            && usage.appName.caseInsensitiveCompare(selfName) != .orderedSame {
            let cat = config.category(for: ActivityStore.eventKey(
                ActivityEvent(timestamp: .now, duration: 0, appName: usage.appName,
                              bundleID: usage.bundleID, domain: usage.domain)
            ))
            guard cat == .entertainment || cat == .social else { continue }

            if let domain = usage.domain {
                guard !config.blockedWebsites.contains(domain) else { continue }
                result.append(BlockItem(
                    displayName: domain, blockingName: domain,
                    isApp: false, isFromConfig: false,
                    todayDuration: usage.duration, category: cat
                ))
            } else {
                let name = usage.appName
                guard !config.blockedApps.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
                result.append(BlockItem(
                    displayName: name, blockingName: name,
                    isApp: true, isFromConfig: false,
                    todayDuration: usage.duration, category: cat
                ))
            }
        }

        items = result
        // Pre-check everything
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
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
