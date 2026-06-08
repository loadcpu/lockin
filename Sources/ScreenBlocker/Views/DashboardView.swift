import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject private var service = BlockerService.shared
    @ObservedObject private var store = ActivityStore.shared
    let onStartBlocking: () -> Void
    let onConfigure: () -> Void
    let onViewStats: () -> Void

    @State private var focusToday: TimeInterval = 0

    var body: some View {
        VStack(spacing: 0) {
            heroSection
            Spacer().frame(height: 20)
            statusSection
            Spacer().frame(height: 16)
            Divider().padding(.horizontal, 20)
            quickStatsSection
            Divider().padding(.horizontal, 20)
            bottomBar
        }
        .frame(width: 300)
        .onAppear { refreshStats() }
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
                .padding(.top, 28)
            Text("Screen Blocker")
                .font(.title3.bold())
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

    private var blockingStatus: some View {
        VStack(spacing: 6) {
            Text("SESSION ACTIVE")
                .font(.caption.bold())
                .foregroundColor(.red)
                .tracking(1)
            Text(service.remainingTimeString)
                .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
            Text("remaining")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.red.opacity(0.08))
        .cornerRadius(12)
    }

    private var readyStatus: some View {
        VStack(spacing: 14) {
            Label("Ready to focus", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.subheadline)
            Button(action: onStartBlocking) {
                Text("Start Blocking")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(red: 0.10, green: 0.22, blue: 0.82))
        }
    }

    // MARK: - Quick stats

    private var quickStatsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("TODAY")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                    .tracking(0.6)
                Spacer()
                Button("View Details →") { onViewStats() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.blue)
            }

            if focusToday > 0 {
                HStack(alignment: .bottom, spacing: 6) {
                    Text(focusToday.formattedDuration)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.35))
                    Text("focus time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 3)
                    Spacer()
                }
            } else {
                HStack {
                    Text("No focus sessions yet today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button("Configure", action: onConfigure)
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.subheadline)
            Spacer()
            Button("Quit") {
                if service.isBlocking {
                    let a = NSAlert()
                    a.messageText = "Session Locked"
                    a.informativeText = "You cannot quit while a blocking session is active. Wait for the timer to expire."
                    a.alertStyle = .informational
                    a.addButton(withTitle: "OK")
                    a.runModal()
                } else {
                    NSApp.terminate(nil)
                }
            }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.subheadline)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}
