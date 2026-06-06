import Foundation

private struct FocusEntry: Codable {
    let date: String
    let duration: TimeInterval
}

final class FocusStore {
    static let shared = FocusStore()
    private let queue = DispatchQueue(label: "FocusStore", qos: .utility)
    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {}

    private var baseDir: URL {
        let dir = FileManager.screenblockerDir.appendingPathComponent("focus")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func record(duration: TimeInterval) {
        guard duration > 0 else { return }
        let dateStr = fmt.string(from: Date())
        let entry = FocusEntry(date: dateStr, duration: duration)
        queue.async {
            guard let data = try? JSONEncoder().encode(entry),
                  let line = String(data: data, encoding: .utf8) else { return }
            let url = self.baseDir.appendingPathComponent("\(dateStr).jsonl")
            let text = line + "\n"
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile()
                fh.write(Data(text.utf8))
                try? fh.close()
            } else {
                try? text.write(to: url, atomically: false, encoding: .utf8)
            }
        }
    }

    func focusTimeToday() -> TimeInterval {
        read(for: Date())
    }

    func focusTotal(forDays days: Int) -> TimeInterval {
        let cal = Calendar.current
        return (0..<days).reduce(0.0) { total, offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: Date()) else { return total }
            return total + read(for: d)
        }
    }

    private func read(for date: Date) -> TimeInterval {
        let url = baseDir.appendingPathComponent("\(fmt.string(from: date)).jsonl")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return content.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> FocusEntry? in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(FocusEntry.self, from: data)
            }
            .reduce(0) { $0 + $1.duration }
    }
}
