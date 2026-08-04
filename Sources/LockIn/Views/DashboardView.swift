import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject private var service = BlockerService.shared
    @ObservedObject private var store = ActivityStore.shared
    let onStartBlocking: () -> Void
    let onViewStats: () -> Void

    @State private var focusToday: TimeInterval = 0
    @State private var showingBreakPicker = false
    @State private var breakMinutes: Double = 10
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
        .background(
            DashboardWindowSizer(trigger: service.isBlocking)
        )
        .onAppear {
            refreshStats()
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
                breakControls
            } else {
                readyStatus
            }
        }
        .padding(.horizontal, 20)
    }

    private var blockingStatus: some View {
        VStack(spacing: 6) {
            Text(service.isPaused ? "ON BREAK" : "SESSION ACTIVE")
                .font(.footnote.bold())
                .foregroundColor(service.isPaused ? .orange : AppTheme.linkBlue)
                .tracking(1)
            Text(service.isPaused ? service.breakCountdownString : service.remainingTimeString)
                .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
            Text(service.isPaused ? (service.breakRemainingSeconds > 0 ? "break remaining" : "break's over — resume when ready") : "remaining")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background((service.isPaused ? Color.orange : AppTheme.accentBlue).opacity(0.16))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var breakControls: some View {
        if service.isPaused {
            Button(action: { service.resumeSession() }) {
                Text("Resume Session").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accentBlue)
            .padding(.top, 10)
        } else if showingBreakPicker {
            VStack(spacing: 8) {
                Text("\(Int(breakMinutes)) min break")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Slider(value: $breakMinutes, in: 0...10, step: 1)
                HStack(spacing: 8) {
                    Button("Cancel") { showingBreakPicker = false }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("Start Break") {
                        service.pauseSession(minutes: Int(breakMinutes))
                        showingBreakPicker = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 10)
        } else if service.breaksAvailable > 0 {
            Button(action: { showingBreakPicker = true }) {
                Label("Take a Break (\(service.breaksAvailable) earned)", systemImage: "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.top, 10)
        }
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
            .tint(AppTheme.accentBlue)
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
                    .foregroundColor(AppTheme.linkBlue)
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
