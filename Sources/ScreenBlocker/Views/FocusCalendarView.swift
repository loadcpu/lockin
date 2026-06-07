import SwiftUI

struct FocusCalendarView: View {
    @State private var data: [Date: TimeInterval] = [:]

    private let green = Color(red: 0.20, green: 0.78, blue: 0.35)
    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FOCUS HISTORY")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .tracking(0.5)

            yearView
            legendRow
        }
        .onAppear { load() }
    }

    // MARK: - Year (GitHub-style: cols = weeks, rows = Sun–Sat)

    private var yearView: some View {
        let weeks = buildWeeks()
        let size: CGFloat = 10
        let gap: CGFloat = 2
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: gap) {
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(i == 1 || i == 3 || i == 5 ? dayLabels[i] : "")
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
        HStack(spacing: 4) {
            Spacer()
            Text("Less").font(.system(size: 9)).foregroundColor(.secondary)
            ForEach(Array([0.0, 0.25, 0.5, 0.75, 1.0].enumerated()), id: \.0) { _, t in
                RoundedRectangle(cornerRadius: 2)
                    .fill(t == 0 ? Color.gray.opacity(0.15) : green.opacity(0.15 + t * 0.85))
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

    // Builds 53 weeks anchored so today is always in the last column.
    // Each inner array is [Sun, Mon, …, Sat]; nil = future or padding.
    private func buildWeeks() -> [[Date?]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayWD = cal.component(.weekday, from: today) - 1  // 0 = Sun
        // Sunday of the week containing today
        let thisSunday = cal.date(byAdding: .day, value: -todayWD, to: today)!
        // Start 52 weeks before this Sunday
        let startSunday = cal.date(byAdding: .day, value: -52 * 7, to: thisSunday)!

        var result: [[Date?]] = []
        var ws = startSunday
        for _ in 0..<53 {
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
        guard duration > 0 else { return Color.gray.opacity(0.12) }
        let t = min(1.0, duration / 7200)  // 2h = full intensity
        return green.opacity(0.15 + t * 0.85)
    }

    private func tooltip(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        let d = data[date] ?? 0
        return d > 0 ? "\(f.string(from: date)): \(d.formattedDuration) focused" : "\(f.string(from: date)): No focus"
    }
}
