import SwiftUI
import AppKit

private let dashboardAccentBlue = Color(
    red: 26.0 / 255.0,
    green: 56.0 / 255.0,
    blue: 209.0 / 255.0
)
private let dashboardLinkBlue = Color(
    red: 57.0 / 255.0,
    green: 123.0 / 255.0,
    blue: 247.0 / 255.0
)

struct DashboardView: View {
    @ObservedObject private var service = BlockerService.shared
    @ObservedObject private var store = ActivityStore.shared
    let onStartBlocking: () -> Void
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
            Spacer().frame(height: 20)
        }
        .frame(width: 340)
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
                Button("Statistics") { onViewStats() }
                    .buttonStyle(.plain)
                    .font(.footnote)
                    .foregroundColor(dashboardLinkBlue)
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
