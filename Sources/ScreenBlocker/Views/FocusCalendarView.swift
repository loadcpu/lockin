import SwiftUI

struct FocusCalendarView: View {
    enum Range: String, CaseIterable {
        case week = "Week"; case month = "Month"; case year = "Year"
    }

    @State private var selectedRange: Range = .month
    @State private var data: [Date: TimeInterval] = [:]

    private let green = Color(red: 0.20, green: 0.78, blue: 0.35)
    private let daySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FOCUS HISTORY")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                Spacer()
                Picker("", selection: $selectedRange) {
                    ForEach(Range.allCases, id: \.self) { r in Text(r.rawValue).tag(r) }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            switch selectedRange {
            case .week:  weekView
            case .month: monthView
            case .year:  yearView
            }

            legendRow
        }
        .onAppear { load() }
    }

    // MARK: - Week (7 days horizontal, fills available width)

    private var weekView: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days: [Date] = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: cols, spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.0) { _, d in
                Text(shortDay(d)).font(.system(size: 9)).foregroundColor(.secondary)
            }
            ForEach(Array(days.enumerated()), id: \.0) { _, d in
                RoundedRectangle(cornerRadius: 4)
                    .fill(cellColor(data[d] ?? 0))
                    .aspectRatio(1, contentMode: .fit)
                    .help(tooltip(d))
            }
        }
    }

    // MARK: - Month (traditional calendar: rows = weeks, cols = Sun-Sat)

    private var monthView: some View {
        let weeks = buildWeeks(count: 5)
        let allCells: [Date?] = weeks.flatMap { $0 }
        let cols = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
        return LazyVGrid(columns: cols, spacing: 4) {
            ForEach(Array(daySymbols.enumerated()), id: \.0) { _, sym in
                Text(sym).font(.system(size: 9)).foregroundColor(.secondary).frame(maxWidth: .infinity)
            }
            ForEach(Array(allCells.enumerated()), id: \.0) { _, dateOpt in
                if let date = dateOpt {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(cellColor(data[date] ?? 0))
                        .aspectRatio(1, contentMode: .fit)
                        .help(tooltip(date))
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    // MARK: - Year (GitHub-style: cols = weeks, rows = days, scrollable)

    private var yearView: some View {
        let weeks = buildWeeks(count: 53)
        let size: CGFloat = 10
        let gap: CGFloat = 1
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: gap) {
                // M / W / F labels on left
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(i == 1 || i == 3 || i == 5 ? daySymbols[i] : "")
                            .font(.system(size: 7))
                            .foregroundColor(.secondary)
                            .frame(width: 8, height: size)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.0) { _, week in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { d in
                            if let date = week[d] {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(cellColor(data[date] ?? 0))
                                    .frame(width: size, height: size)
                                    .help(tooltip(date))
                            } else {
                                Color.clear.frame(width: size, height: size)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: CGFloat(7) * (size + gap))
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: 5) {
            Spacer()
            Text("Less").font(.system(size: 9)).foregroundColor(.secondary)
            ForEach(Array([0.0, 0.25, 0.5, 0.75, 1.0].enumerated()), id: \.0) { _, t in
                RoundedRectangle(cornerRadius: 2)
                    .fill(t == 0 ? Color.white.opacity(0.08) : green.opacity(0.15 + t * 0.85))
                    .frame(width: 10, height: 10)
            }
            Text("More").font(.system(size: 9)).foregroundColor(.secondary)
        }
    }

    // MARK: - Data

    private func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let d = FocusStore.shared.focusData(forLastDays: 371)
            DispatchQueue.main.async { data = d }
        }
    }

    // Returns [[Date?]] — each inner array is one week [Sun…Sat].
    // Used as columns for year view, or rows for month view.
    private func buildWeeks(count: Int) -> [[Date?]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let approxStart = cal.date(byAdding: .day, value: -(count * 7 - 1), to: today)!
        let wd = cal.component(.weekday, from: approxStart) - 1  // 0 = Sun
        let aligned = cal.date(byAdding: .day, value: -wd, to: approxStart)!

        var result: [[Date?]] = []
        var ws = aligned
        for _ in 0..<count {
            var week: [Date?] = []
            for d in 0..<7 {
                let date = cal.date(byAdding: .day, value: d, to: ws)!
                week.append(date <= today ? date : nil)
            }
            result.append(week)
            ws = cal.date(byAdding: .day, value: 7, to: ws)!
        }
        return result
    }

    // MARK: - Helpers

    private func cellColor(_ duration: TimeInterval) -> Color {
        guard duration > 0 else { return Color.white.opacity(0.08) }
        let t = min(1.0, duration / 7200)  // 2h = full intensity
        return green.opacity(0.15 + t * 0.85)
    }

    private func tooltip(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        let d = data[date] ?? 0
        return d > 0 ? "\(f.string(from: date)): \(d.formattedDuration) focused" : "\(f.string(from: date)): No focus"
    }

    private func shortDay(_ date: Date) -> String {
        ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][Calendar.current.component(.weekday, from: date) - 1]
    }
}
