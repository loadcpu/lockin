import SwiftUI
import AppKit

extension Notification.Name {
    static let statsViewShouldReload = Notification.Name("StatsViewShouldReload")
}

struct StatsView: View {
    @ObservedObject private var service = BlockerService.shared
    @ObservedObject private var store = ActivityStore.shared
    @State private var range: TimeRange = .today
    @State private var totalDuration: TimeInterval = 0
    @State private var topApps: [ActivityStore.AppUsage] = []
    @State private var categories: [ActivityStore.CategoryUsage] = []
    @State private var focusTotal: TimeInterval = 0
    @State private var currentStreak: Int = 0
    @State private var longestStreak: Int = 0

    enum TimeRange: String, CaseIterable {
        case today = "Today"
        case week  = "Week"
        case month = "30 Days"

        var days: Int {
            switch self { case .today: return 1; case .week: return 7; case .month: return 30 }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if totalDuration < 1 {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        summaryCard
                        focusCalendarSection
                        categorySection
                        topAppsSection
                    }
                    .padding(24)
                }
            }
        }
        .frame(width: 600, height: 580)
        .onAppear(perform: reload)
        .onChange(of: range) { _ in reload() }
        .onChange(of: store.todayTotal) { _ in if range == .today { reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .statsViewShouldReload)) { _ in reload() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Screen Time", systemImage: "chart.bar.fill")
                .font(.title3.bold())
            Spacer()
            Picker("", selection: $range) {
                ForEach(TimeRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No activity recorded yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Screen Blocker tracks app usage as you work.\nData for \(range.rawValue.lowercased()) will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        let green = Color(red: 0.20, green: 0.78, blue: 0.35)
        return VStack(alignment: .leading, spacing: 10) {
            Text(rangeLabel)
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .tracking(0.5)

            HStack(alignment: .bottom, spacing: 0) {
                if focusTotal > 0 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(focusTotal.formattedDuration)
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(green)
                        Text("focused")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(totalDuration.formattedDuration)
                            .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundColor(.primary.opacity(0.5))
                        Text("screen time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(totalDuration.formattedDuration)
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        Text("screen time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }

            if focusTotal > 0 && totalDuration > 0 {
                let ratio = min(1.0, focusTotal / totalDuration)
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(NSColor.separatorColor))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(green.opacity(0.7))
                                .frame(width: max(4, geo.size.width * ratio))
                        }
                    }
                    .frame(height: 4)
                    Text("\(Int((ratio * 100).rounded()))% of screen time focused")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if productiveTime > 0 || distractingTime > 0 {
                productivityRow
            }

            if currentStreak > 0 || longestStreak > 0 {
                streakRow
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 1.0))
    }

    private var streakRow: some View {
        HStack(spacing: 16) {
            if currentStreak > 0 {
                streakChip("current streak", value: currentStreak, color: .orange, emoji: "🔥")
            }
            if longestStreak > 0 {
                streakChip("best streak", value: longestStreak, color: Color(red: 0.20, green: 0.78, blue: 0.35), emoji: "⭐")
            }
            Spacer()
        }
    }

    private func streakChip(_ label: String, value: Int, color: Color, emoji: String) -> some View {
        HStack(spacing: 5) {
            Text("\(emoji) \(value)d").font(.caption.bold()).foregroundColor(color)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
    }

    private var productivityRow: some View {
        HStack(spacing: 16) {
            if productiveTime > 0 {
                productivityChip("Productive", duration: productiveTime, color: Color(red: 0.20, green: 0.78, blue: 0.35))
            }
            if distractingTime > 0 {
                productivityChip("Distracting", duration: distractingTime, color: Color(red: 0.96, green: 0.26, blue: 0.21))
            }
            if neutralTime > 0 {
                productivityChip("Neutral", duration: neutralTime, color: Color(red: 0.65, green: 0.65, blue: 0.70))
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func productivityChip(_ name: String, duration: TimeInterval, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(.caption).foregroundColor(.secondary)
            Text(duration.formattedDuration).font(.caption.bold())
        }
    }

    private var rangeLabel: String {
        switch range {
        case .today: return "TODAY"
        case .week:  return "LAST 7 DAYS"
        case .month: return "LAST 30 DAYS"
        }
    }

    // MARK: - Focus calendar

    private var focusCalendarSection: some View {
        FocusCalendarView()
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 1.0))
    }

    // MARK: - Category section

    private var categorySection: some View {
        let visible = categories.filter { totalDuration > 0 && $0.duration / totalDuration * 100 >= 0.5 }
        return VStack(alignment: .leading, spacing: 12) {
            sectionLabel("BY CATEGORY")
            CategoryBar(segments: categorySegments)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(visible) { usage in categoryLegendRow(usage) }
            }
        }
    }

    private var categorySegments: [(Color, Double)] {
        guard totalDuration > 0 else { return [] }
        return categories.map { ($0.category.color, $0.duration / totalDuration) }
    }

    private var productiveTime: TimeInterval {
        categories.filter { $0.category.isProductive }.reduce(0) { $0 + $1.duration }
    }

    private var distractingTime: TimeInterval {
        categories.filter { $0.category.isDistracting }.reduce(0) { $0 + $1.duration }
    }

    private var neutralTime: TimeInterval {
        categories.filter { !$0.category.isProductive && !$0.category.isDistracting }.reduce(0) { $0 + $1.duration }
    }

    private func categoryLegendRow(_ usage: ActivityStore.CategoryUsage) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(usage.category.color)
                .frame(width: 3)
            HStack(spacing: 8) {
                Text(usage.category.rawValue).font(.subheadline).lineLimit(1)
                Spacer()
                Text(usage.duration.formattedDuration)
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
                Text(pct(usage.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor), lineWidth: 1.0))
    }

    private func pct(_ duration: TimeInterval) -> String {
        guard totalDuration > 0 else { return "0%" }
        return "\(Int((duration / totalDuration * 100).rounded()))%"
    }

    // MARK: - Top apps section

    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TOP APPS & SITES")
            VStack(spacing: 0) {
                ForEach(Array(topApps.enumerated()), id: \.0) { i, usage in
                    AppRow(
                        usage: usage,
                        totalDuration: totalDuration,
                        category: categoryBinding(for: usage)
                    )
                    if i < topApps.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor), lineWidth: 1.0))
        }
    }

    private func categoryBinding(for usage: ActivityStore.AppUsage) -> Binding<AppCategory> {
        let key = usage.domain ?? usage.bundleID
        return Binding(
            get: { self.service.config.category(for: key) },
            set: { newCat in
                self.service.config.appCategoryOverrides[key] = newCat.rawValue
                self.service.saveConfig()
                self.reload()
            }
        )
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundColor(.secondary)
            .tracking(0.5)
    }

    private func reload() {
        let d = range.days
        totalDuration = store.totalDuration(forDays: d)
        topApps = store.topApps(forDays: d, limit: 12)
        categories = store.categoryBreakdown(forDays: d) { service.config.category(for: $0) }
            .sorted { $0.duration > $1.duration }
        focusTotal = FocusStore.shared.focusTotal(forDays: d)
        currentStreak = FocusStore.shared.currentStreak()
        longestStreak = FocusStore.shared.longestStreak()
    }
}

// MARK: - Category bar

struct CategoryBar: View {
    let segments: [(Color, Double)]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.0) { _, seg in
                    let w = max(4, (geo.size.width - CGFloat(segments.count - 1) * 2) * seg.1)
                    Rectangle().fill(seg.0).frame(width: w)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .frame(height: 10)
    }
}

// MARK: - App row

private struct AppRow: View {
    let usage: ActivityStore.AppUsage
    let totalDuration: TimeInterval
    @Binding var category: AppCategory

    private var fraction: Double {
        guard totalDuration > 0 else { return 0 }
        return min(1, usage.duration / totalDuration)
    }

    var body: some View {
        HStack(spacing: 10) {
            iconView.frame(width: 28, height: 28)

            Text(usage.displayName)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            categoryMenu

            Text(usage.duration.formattedDuration)
                .font(.system(.subheadline, design: .rounded).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 58, alignment: .trailing)

            miniBar
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var iconView: some View {
        if usage.domain != nil {
            Image(systemName: "globe")
                .font(.system(size: 18))
                .foregroundColor(category.color)
        } else if let img = usage.icon {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.fill").foregroundColor(.secondary)
        }
    }

    private var categoryMenu: some View {
        Menu {
            ForEach(AppCategory.allCases) { cat in
                Button { category = cat } label: {
                    Label(cat.rawValue, systemImage: cat.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle().fill(category.color).frame(width: 7, height: 7)
                Text(category.rawValue).font(.caption).foregroundColor(.secondary)
                Image(systemName: "chevron.down").font(.system(size: 8)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor), lineWidth: 1.0))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var miniBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.separatorColor))
                RoundedRectangle(cornerRadius: 4)
                    .fill(category.color.opacity(0.75))
                    .frame(width: max(4, geo.size.width * fraction))
            }
        }
        .frame(width: 70, height: 8)
    }
}
