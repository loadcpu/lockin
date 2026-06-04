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
            TabView(selection: $selectedTab) {
                appsTab
                    .tabItem { Label("Apps", systemImage: "app.badge.checkmark") }
                    .tag(0)
                websitesTab
                    .tabItem { Label("Websites", systemImage: "globe") }
                    .tag(1)
            }
            .padding(.top, 4)
        }
        .frame(width: 520, height: 520)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.fill")
                .font(.title2)
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Blocker")
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
                    Image(nsImage: resized(app.icon, to: 24))
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

    // MARK: - Helpers

    private func resized(_ image: NSImage, to size: CGFloat) -> NSImage {
        let result = NSImage(size: NSSize(width: size, height: size))
        result.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        result.unlockFocus()
        return result
    }
}
