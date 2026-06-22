import SwiftUI
import AppKit

private let dashboardAccentBlue = Color(
    red: 26.0 / 255.0,
    green: 56.0 / 255.0,
    blue: 209.0 / 255.0
)

struct DashboardView: View {
    @ObservedObject private var service = BlockerService.shared
    @ObservedObject private var store = ActivityStore.shared
    @ObservedObject private var updateChecker = AppUpdateChecker.shared
    let onStartBlocking: () -> Void
    let onViewStats: () -> Void

    @State private var focusToday: TimeInterval = 0
    var body: some View {
        VStack(spacing: 0) {
            heroSection
            if updateChecker.isUpdateAvailable {
                Spacer().frame(height: 14)
                updateBanner
            }
            Spacer().frame(height: 20)
            statusSection
            Spacer().frame(height: 16)
            Divider().padding(.horizontal, 20)
            quickStatsSection
            Spacer().frame(height: 20)
        }
        .frame(width: 340)
        .background(
            DashboardWindowSizer(trigger: service.isBlocking)
        )
        .onAppear {
            refreshStats()
            updateChecker.checkForUpdatesIfNeeded()
        }
        .onChange(of: store.todayTotal) { _ in refreshStats() }
    }

    private func refreshStats() {
        focusToday = FocusStore.shared.focusTimeToday()
    }

    // MARK: - Sections

    private var heroSection: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 72, height: 72)
                .padding(.top, 16)
            Text("Lock In")
                .font(.title2.bold())
        }
    }

    private var statusSection: some View {
        Group {
            if service.isBlocking {
                blockingStatus
            } else {
                readyStatus
            }
        }
        .padding(.horizontal, 20)
    }

    private var updateBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(dashboardAccentBlue)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Update available")
                        .font(.subheadline.weight(.semibold))
                    Text("Version \(updateChecker.latestVersion ?? "") is ready to download from GitHub.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button("Download Update") {
                    updateChecker.openDownloadPage()
                }
                .buttonStyle(.borderedProminent)
                .tint(dashboardAccentBlue)

                Button("Check Again") {
                    updateChecker.checkForUpdates(userInitiated: true)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(dashboardAccentBlue.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(dashboardAccentBlue.opacity(0.18), lineWidth: 1)
        )
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }

    private var blockingStatus: some View {
        VStack(spacing: 6) {
            Text("SESSION ACTIVE")
                .font(.footnote.bold())
                .foregroundColor(.red)
                .tracking(1)
            Text(service.remainingTimeString)
                .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
            Text("remaining")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.red.opacity(0.08))
        .cornerRadius(12)
    }

    private var readyStatus: some View {
        VStack(spacing: 14) {
            Label(
                service.hasLimitRestrictions ? "Category limits active" : "Ready to focus",
                systemImage: service.hasLimitRestrictions ? "lock.fill" : "checkmark.circle.fill"
            )
                .foregroundColor(service.hasLimitRestrictions ? .orange : .green)
                .font(.body)
            Button(action: onStartBlocking) {
                Text("Start Blocking")
                    .frame(width: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(dashboardAccentBlue)
        }
    }

    // MARK: - Quick stats

    private var quickStatsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("TODAY")
                    .font(.footnote.bold())
                    .foregroundColor(.secondary)
                    .tracking(0.6)
                Spacer()
                if updateChecker.isChecking {
                    Text("Checking updates…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Button("Statistics") { onViewStats() }
                    .buttonStyle(.plain)
                    .font(.footnote)
                    .foregroundColor(Color(
                        red: 57.0 / 255.0,
                        green: 123.0 / 255.0,
                        blue: 247.0 / 255.0
                    ))
            }

            if focusToday > 0 {
                HStack(alignment: .bottom, spacing: 6) {
                    Text(focusToday.formattedDuration)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.35))
                    Text("focus time")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 3)
                    Spacer()
                }
            } else {
                HStack {
                    Text("No focus sessions yet today")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct DashboardWindowSizer: NSViewRepresentable {
    let trigger: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            resizeWindow(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            resizeWindow(from: nsView)
        }
    }

    private func resizeWindow(from view: NSView) {
        guard
            let window = view.window,
            let hostingView = window.contentView as? NSHostingView<AnyView>
        else {
            return
        }

        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else { return }
        guard window.contentRect(forFrameRect: window.frame).size != fittingSize else { return }

        window.setContentSize(fittingSize)
    }
}
