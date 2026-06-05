import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject private var service = BlockerService.shared
    @ObservedObject private var store = ActivityStore.shared
    let onStartBlocking: () -> Void
    let onConfigure: () -> Void
    let onViewStats: () -> Void

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
                Text("Start Blocking…")
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

            HStack(alignment: .bottom, spacing: 6) {
                Text(store.todayTotal.formattedDuration)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("screen time")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 3)
                Spacer()
            }

            if store.todayTotal > 0 {
                miniCategoryBar
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var miniCategoryBar: some View {
        let segments = ActivityStore.shared
            .categoryBreakdown(for: Date()) { service.config.category(for: $0) }
            .map { ($0.category, store.todayTotal > 0 ? $0.duration / store.todayTotal : 0.0) }
        return CategoryBar(segments: segments)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button("Configure", action: onConfigure)
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.subheadline)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.subheadline)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}
