import SwiftUI

struct FocusCalendarView: View {
    @Binding var selectedDate: Date?
    let onSelectDate: (Date) -> Void

    @State private var data: [Date: TimeInterval] = [:]
    @State private var hoveredDate: Date? = nil

    private let green = Color(red: 0.20, green: 0.78, blue: 0.35)
    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FOCUS HISTORY")
                .font(.footnote.bold())
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
        let size: CGFloat = 12
        let gap: CGFloat = 3
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: gap) {
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(i == 1 || i == 3 || i == 5 ? dayLabels[i] : "")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 10, height: size)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.0) { _, week in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { d in
                            if let date = week[d] {
                                Button {
                                    selectedDate = date
                                    onSelectDate(date)
                                } label: {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(cellColor(data[date] ?? 0))
                                        .frame(width: size, height: size)
                                        .overlay(selectionOverlay(for: date))
                                }
                                .buttonStyle(.plain)
                                .onHover { inside in hoveredDate = inside ? date : nil }
                                .help(helpText(for: date))
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

    // MARK: - Legend + hover status

    private var legendRow: some View {
        HStack(spacing: 4) {
            if let date = hoveredDate {
                let d = data[date] ?? 0
                Text(d > 0 ? "\(dateFmt.string(from: date)): \(d.formattedDuration) focused"
                           : "\(dateFmt.string(from: date)): No focus")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("Less").font(.system(size: 11)).foregroundColor(.secondary)
            ForEach(Array([0.0, 0.25, 0.5, 0.75, 1.0].enumerated()), id: \.0) { _, t in
                RoundedRectangle(cornerRadius: 2)
                    .fill(t == 0 ? Color.gray.opacity(0.15) : green.opacity(0.15 + t * 0.85))
                    .frame(width: 12, height: 12)
            }
            Text("More").font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    // MARK: - Data

    private func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let d = FocusStore.shared.focusData(forLastDays: 371)
            DispatchQueue.main.async { data = d }
        }
    }

    // Builds weeks from the Sunday on or before Jan 1 of the current year
    // through the current week, so the grid always opens at January.
    // Each inner array is [Sun, Mon, …, Sat]; nil = future or padding.
    private func buildWeeks() -> [[Date?]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Jan 1 of the current year
        let year = cal.component(.year, from: today)
        let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        // Rewind to the Sunday of that week
        let jan1WD = cal.component(.weekday, from: jan1) - 1  // 0 = Sun
        let startSunday = cal.date(byAdding: .day, value: -jan1WD, to: jan1)!

        var result: [[Date?]] = []
        var ws = startSunday
        while ws <= today {
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

    @ViewBuilder
    private func selectionOverlay(for date: Date) -> some View {
        if let selectedDate, Calendar.current.isDate(selectedDate, inSameDayAs: date) {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.accentColor, lineWidth: 1.5)
        }
    }

    private func helpText(for date: Date) -> String {
        let d = data[date] ?? 0
        let focus = d > 0 ? "\(d.formattedDuration) focused" : "No focus"
        return "\(dateFmt.string(from: date)): \(focus). Click to view this day."
    }
}
