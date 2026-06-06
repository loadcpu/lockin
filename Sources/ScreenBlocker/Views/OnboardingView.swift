import SwiftUI
import AppKit

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step = 1
    @State private var appSearch = ""
    @ObservedObject private var service = BlockerService.shared

    var body: some View {
        VStack(spacing: 0) {
            progressDots
                .padding(.top, 20)
                .padding(.bottom, 4)

            Group {
                switch step {
                case 1: step1
                case 2: step2
                case 3: step3
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            navButtons
        }
        .frame(width: 440, height: 520)
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .fill(i == step ? Color.blue : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var step1: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 80, height: 80)
                .padding(.top, 16)

            Text("Welcome to Screen Blocker")
                .font(.title2.bold())

            Text("Stay focused by blocking distracting apps and websites during a timed session. When you start a session, blocked apps are force-quit and blocked websites are unreachable until time runs out.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
        }
        .padding(24)
    }

    // MARK: - Step 2: Pick apps

    private var step2: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Pick apps to block")
                    .font(.title3.bold())
                Text("These will be force-quit when a session starts.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search apps…", text: $appSearch).textFieldStyle(.plain)
                if !appSearch.isEmpty {
                    Button { appSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            Divider()

            let apps = AppScanner.shared.installedApps().filter {
                appSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(appSearch)
            }
            List(apps) { app in
                HStack(spacing: 10) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 22, height: 22)
                    Text(app.name)
                    Spacer()
                    Toggle("", isOn: blockedBinding(app.name))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.vertical, 1)
            }
            .listStyle(.plain)

            Divider()

            let count = service.config.blockedApps.count
            Text(count == 0 ? "No apps selected" : "\(count) app\(count == 1 ? "" : "s") selected")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Step 3: Browser permission

    private var step3: some View {
        VStack(spacing: 18) {
            Image(systemName: "globe")
                .font(.system(size: 54))
                .foregroundColor(.blue)
                .padding(.top, 16)

            Text("Instant website blocking")
                .font(.title3.bold())

            Text("Screen Blocker can reload your browser tabs the moment a session starts, so blocked sites are cut off immediately.\n\nOpen the browsers you use, then tap Grant Permission. macOS will ask once per browser — click Allow.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

            Button("Grant Permission") {
                BlockerService.shared.primeBrowserPermissions()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }

    // MARK: - Navigation

    private var navButtons: some View {
        HStack {
            if step > 1 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if step < 3 {
                Button("Next") { step += 1 }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Skip") { onFinish() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 8)
                Button("Done") { onFinish() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private func blockedBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { service.config.blockedApps.contains(name) },
            set: { on in
                if on { if !service.config.blockedApps.contains(name) { service.config.blockedApps.append(name) } }
                else  { service.config.blockedApps.removeAll { $0 == name } }
                service.saveConfig()
            }
        )
    }
}
