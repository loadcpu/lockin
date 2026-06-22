import SwiftUI

struct FocusCalendarView: View {
    @Binding var selectedDate: Date?
    let onSelectDate: (Date) -> Void

    @State private var data: [Date: TimeInterval] = [:]
    @State private var hoveredDate: Date? = nil

    private let green = Color(red: 0.20, green: 0.78, blue: 0.35)
    private let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()
    private let monthFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
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
        let monthMarkers = buildMonthMarkers(for: weeks)
        let size: CGFloat = 12
        let gap: CGFloat = 3
        let weekStride = size + gap
        let gridWidth = CGFloat(weeks.count) * size + CGFloat(max(weeks.count - 1, 0)) * gap
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: gap) {
                VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .leading) {
                        Color.clear.frame(width: 28, height: 14)
                        ForEach(Array(monthMarkers.keys).sorted(), id: \.self) { index in
                            Text(monthMarkers[index] ?? "")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary.opacity(0.92))
                                .fixedSize(horizontal: true, vertical: false)
                                .offset(x: 28 + CGFloat(index) * weekStride)
                        }
                    }
                    .frame(width: 28 + gridWidth, height: 14, alignment: .leading)

                    HStack(alignment: .top, spacing: gap) {
                        VStack(alignment: .leading, spacing: gap) {
                            ForEach(0..<7, id: \.self) { i in
                                Text(weekdayLabel(for: i))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary.opacity(0.92))
                                    .frame(width: 28, height: size, alignment: .leading)
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
            }
        }
        .frame(maxHeight: 14 + 6 + (CGFloat(7) * size) + (CGFloat(6) * gap))
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

    private func buildMonthMarkers(for weeks: [[Date?]]) -> [Int: String] {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: Date())
        var markers: [Int: String] = [:]
        var lastMonth: Int?

        for (index, week) in weeks.enumerated() {
            guard let firstDateInCurrentYear = week
                .compactMap({ $0 })
                .first(where: { cal.component(.year, from: $0) == currentYear }) else { continue }

            let month = cal.component(.month, from: firstDateInCurrentYear)
            if month != lastMonth {
                markers[index] = monthFmt.string(from: firstDateInCurrentYear)
                lastMonth = month
            }
        }

        return markers
    }

    // MARK: - Helpers

    private func weekdayLabel(for index: Int) -> String {
        switch index {
        case 1: return "Mon"
        case 3: return "Wed"
        case 5: return "Fri"
        default: return ""
        }
    }

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
