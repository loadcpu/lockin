import SwiftUI
import AppKit

struct ConfigView: View {
    @ObservedObject private var service = BlockerService.shared
    @State private var selectedTab = 0
    @State private var appSearch = ""
    @State private var newWebsite = ""
    @State private var websiteError = ""
    private let configureBackground = AppTheme.background

    var body: some View {
        VStack(spacing: 0) {
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
        .frame(width: 560, height: 540)
        .background(configureBackground)
    }

    private var tabPicker: some View {
        HStack {
            Spacer()
            Picker("", selection: $selectedTab) {
                Text("Apps").tag(0)
                Text("Websites").tag(1)
                Text("Limits").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
            .background(configureBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.separator, lineWidth: 1)
            )
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
                        .font(.body)
                    Spacer()
                    Toggle("", isOn: blockedAppBinding(app.name))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.vertical, 1)
                .listRowBackground(configureBackground)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(configureBackground)

            Divider()

            HStack {
                let count = service.config.blockedApps.count
                Text(count == 0 ? "No apps selected" : "\(count) app\(count == 1 ? "" : "s") will be killed during sessions")
                    .font(.footnote)
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
                            .font(.body)
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
                    .listRowBackground(configureBackground)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(configureBackground)

            Divider()

            VStack(spacing: 4) {
                HStack {
                    TextField("Add domain (e.g. facebook.com)", text: $newWebsite)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(configureBackground)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.separator, lineWidth: 1)
                        )
                        .onSubmit { addWebsite() }
                    Button("Add", action: addWebsite)
                        .disabled(newWebsite.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !websiteError.isEmpty {
                    Text(websiteError)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Instant tab blocking")
                        .font(.footnote)
                        .fontWeight(.medium)
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
                .font(.footnote)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func grantBrowserPermissions() {
        BlockerService.shared.presentBrowserPermissionSetupAlert()
    }

    private func checkForDeniedBrowsers() {
        let runningUnprimed = BlockerService.shared.knownBrowserBundleIDs.filter { bid in
            NSRunningApplication.runningApplications(withBundleIdentifier: bid).first != nil &&
            !BlockerService.shared.primedBrowserIDs.contains(bid)
        }
        guard !runningUnprimed.isEmpty else { return }

        BlockerService.shared.presentBrowserPermissionDeniedAlert(bundleIDs: runningUnprimed)
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
                    .font(.headline)
                Text("Get a notification when you exceed a category limit today. Resets at midnight.")
                    .font(.footnote)
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
                            .font(.body)
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
                    .listRowBackground(configureBackground)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(configureBackground)
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
