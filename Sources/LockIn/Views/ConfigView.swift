import SwiftUI
import AppKit

struct ConfigView: View {
    @ObservedObject private var service = BlockerService.shared
    @State private var selectedTab = 0
    @State private var appSearch = ""
    @State private var newWebsite = ""
    @State private var websiteError = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabPicker
            Divider()
            Group {
                switch selectedTab {
                case 0: appsTab
                case 1: websitesTab
                default: limitsTab
                }
            }
        }
        .frame(width: 520, height: 520)
    }

    private var tabPicker: some View {
        HStack {
            Picker("", selection: $selectedTab) {
                Text("Apps").tag(0)
                Text("Websites").tag(1)
                Text("Limits").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.fill")
                .font(.title2)
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lock In")
                    .font(.headline)
                Text("Configure what gets blocked when a session starts")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Apps Tab

    private var appsTab: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search apps…", text: $appSearch)
                    .textFieldStyle(.plain)
                if !appSearch.isEmpty {
                    Button(action: { appSearch = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            let apps = AppScanner.shared.installedApps().filter {
                appSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(appSearch)
            }

            List(apps) { app in
                HStack(spacing: 10) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text(app.name)
                    Spacer()
                    Toggle("", isOn: blockedAppBinding(app.name))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.vertical, 1)
            }
            .listStyle(.plain)

            Divider()

            HStack {
                let count = service.config.blockedApps.count
                Text(count == 0 ? "No apps selected" : "\(count) app\(count == 1 ? "" : "s") will be killed during sessions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func blockedAppBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { service.config.blockedApps.contains(name) },
            set: { on in
                if on { if !service.config.blockedApps.contains(name) { service.config.blockedApps.append(name) } }
                else  { service.config.blockedApps.removeAll { $0 == name } }
                service.saveConfig()
            }
        )
    }

    // MARK: - Websites Tab

    private var websitesTab: some View {
        VStack(spacing: 0) {
            List {
                ForEach(service.config.blockedWebsites, id: \.self) { site in
                    HStack(spacing: 10) {
                        Image(systemName: "globe")
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        Text(site)
                        Spacer()
                        Button(action: {
                            service.config.blockedWebsites.removeAll { $0 == site }
                            service.saveConfig()
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)

            Divider()

            VStack(spacing: 4) {
                HStack {
                    TextField("Add domain (e.g. facebook.com)", text: $newWebsite)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addWebsite() }
                    Button("Add", action: addWebsite)
                        .disabled(newWebsite.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !websiteError.isEmpty {
                    Text(websiteError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Instant tab blocking")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(service.primedBrowserIDs.isEmpty
                        ? "Not set up — open browsers, then tap Setup"
                        : "\(service.primedBrowserIDs.count) browser\(service.primedBrowserIDs.count == 1 ? "" : "s") authorised")
                        .font(.caption)
                        .foregroundColor(service.primedBrowserIDs.isEmpty ? .orange : .secondary)
                }
                Spacer()
                Button("Setup…") {
                    grantBrowserPermissions()
                }
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
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

        let closedBrowsers = BlockerService.shared.forceQuitBrowsers(bundleIDs: runningUnprimed)
        let browserList = closedBrowsers.isEmpty
            ? "One or more browsers"
            : closedBrowsers.joined(separator: ", ")

        let alert = NSAlert()
        alert.messageText = "Permission Not Granted"
        alert.informativeText = "\(browserList) denied permission, so Lock In closed \(closedBrowsers.count == 1 ? "it" : "them") to prevent already-open tabs from bypassing website blocking.\n\nTo fix this, open System Settings → Privacy & Security → Automation and enable Lock In for each browser you use. macOS will not re-show the prompt automatically after you click Don't Allow."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        }
    }

    private func addWebsite() {
        let site = newWebsite
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .components(separatedBy: "/").first ?? ""

        guard !site.isEmpty else { return }

        if service.config.blockedWebsites.contains(site) {
            websiteError = "\(site) is already in the list"
            return
        }
        guard site.contains(".") else {
            websiteError = "Enter a valid domain (e.g. facebook.com)"
            return
        }

        service.config.blockedWebsites.append(site)
        service.saveConfig()
        newWebsite = ""
        websiteError = ""
    }

    // MARK: - Limits Tab

    private let limitPresets = [(0, "Off"), (5, "5m"), (10, "10m"), (15, "15m"), (30, "30m"), (60, "1h"), (90, "90m"), (120, "2h")]
    private let limitCategories: [AppCategory] = [.entertainment, .social, .work, .development, .communication, .creative]

    private var limitsTab: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Daily screen-time alerts")
                    .font(.subheadline.bold())
                Text("Get a notification when you exceed a category limit today. Resets at midnight.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            List {
                ForEach(limitCategories) { cat in
                    HStack(spacing: 12) {
                        Image(systemName: cat.icon)
                            .frame(width: 20)
                            .foregroundColor(cat.color)
                        Text(cat.rawValue)
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: limitBinding(cat)) {
                            ForEach(limitPresets, id: \.0) { mins, label in
                                Text(label).tag(mins)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)

            Divider()

            HStack {
                let active = limitCategories.filter {
                    (service.config.categoryLimits[$0.rawValue] ?? 0) > 0
                }.count
                Text(active == 0 ? "No limits set" : "\(active) limit\(active == 1 ? "" : "s") active")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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

}
