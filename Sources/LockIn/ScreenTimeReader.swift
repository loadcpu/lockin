import Foundation
import AppKit
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class ScreenTimeReader {
    static let shared = ScreenTimeReader()

    private let dbPath: String
    private var cachedAvailable: Bool?

    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
    ]
    private static let normalizedBrowserBundleIDs: Set<String> = Set(browserBundleIDs.map { $0.lowercased() })
    private static let preferredAppStreamNames = ["/app/usage", "/app/inFocus"]

    struct Sample {
        let bundleID: String   // real bundle ID, or "web" for domain entries
        let domain: String?    // non-nil for website entries
        let duration: TimeInterval
    }

    struct Interval {
        let bundleID: String
        let start: Date
        let end: Date

        var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    }

    private init() {
        dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db")
            .path
    }

    var isAvailable: Bool {
        if let cached = cachedAvailable { return cached }
        var db: OpaquePointer?
        let ok = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
        sqlite3_close(db)
        cachedAvailable = ok
        return ok
    }

    // Returns merged app + web samples for a single calendar day.
    // Web usage replaces browser bundle ID entries to avoid double-counting.
    func samples(for date: Date) -> [Sample] {
        guard let db = openDB() else {
            cachedAvailable = false
            return []
        }
        defer { sqlite3_close(db) }

        let (start, end) = dayBounds(for: date)
        var apps = fetchAppUsage(db: db, start: start, end: end)
        let web  = fetchWebUsage(db: db, start: start, end: end)

        if !web.isEmpty {
            apps.removeAll { Self.browserBundleIDs.contains($0.bundleID) }
        }
        return apps + web
    }

    func totalDuration(for date: Date) -> TimeInterval {
        samples(for: date).reduce(0) { $0 + $1.duration }
    }

    func mediaIntervals(for date: Date) -> [Interval] {
        guard let db = openDB() else { return [] }
        defer { sqlite3_close(db) }
        let (start, end) = dayBounds(for: date)
        return fetchIntervals(db: db, streamName: "/app/mediaUsage", start: start, end: end)
    }

    // MARK: - Private

    private func openDB() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        return db
    }

    private func prepare(_ db: OpaquePointer?, _ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private func dayBounds(for date: Date) -> (Double, Double) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end   = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return (start.timeIntervalSinceReferenceDate, end.timeIntervalSinceReferenceDate)
    }

    private func fetchAppUsage(db: OpaquePointer, start: Double, end: Double) -> [Sample] {
        guard let streamName = availableAppStreamName(in: db) else { return [] }
        let sql = """
            SELECT ZVALUESTRING,
                   SUM(MIN(ZENDDATE,?)-MAX(ZSTARTDATE,?)) AS dur
            FROM ZOBJECT
            WHERE ZSTREAMNAME=?
              AND ZVALUESTRING IS NOT NULL
              AND ZENDDATE>? AND ZSTARTDATE<?
            GROUP BY ZVALUESTRING
            HAVING dur>1
            ORDER BY dur DESC
        """
        guard let stmt = prepare(db, sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, end);   sqlite3_bind_double(stmt, 2, start)
        sqlite3_bind_text(stmt, 3, streamName, -1, sqliteTransient)
        sqlite3_bind_double(stmt, 4, start); sqlite3_bind_double(stmt, 5, end)

        var results: [Sample] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let ptr = sqlite3_column_text(stmt, 0) else { continue }
            let bundleID = String(cString: ptr)
            let dur = sqlite3_column_double(stmt, 1)
            guard !bundleID.isEmpty, dur > 0 else { continue }
            results.append(Sample(bundleID: bundleID, domain: nil, duration: dur))
        }
        return results
    }

    // On macOS 12+, ZVALUESTRING for /app/webUsage is the visited domain.
    private func fetchWebUsage(db: OpaquePointer, start: Double, end: Double) -> [Sample] {
        let sql = """
            SELECT ZVALUESTRING,
                   SUM(MIN(ZENDDATE,?)-MAX(ZSTARTDATE,?)) AS dur
            FROM ZOBJECT
            WHERE ZSTREAMNAME='/app/webUsage'
              AND ZVALUESTRING IS NOT NULL
              AND ZENDDATE>? AND ZSTARTDATE<?
            GROUP BY ZVALUESTRING
            HAVING dur>1
            ORDER BY dur DESC
        """
        guard let stmt = prepare(db, sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, end);   sqlite3_bind_double(stmt, 2, start)
        sqlite3_bind_double(stmt, 3, start); sqlite3_bind_double(stmt, 4, end)

        var results: [Sample] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let ptr = sqlite3_column_text(stmt, 0) else { continue }
            let raw = String(cString: ptr)
            let dur = sqlite3_column_double(stmt, 1)
            guard !raw.isEmpty, dur > 0 else { continue }
            let normalized = raw.lowercased()
            if Self.normalizedBrowserBundleIDs.contains(normalized) {
                results.append(Sample(bundleID: raw, domain: nil, duration: dur))
                continue
            }
            let domain = canonicalizeDomain(raw)
            results.append(Sample(bundleID: "web", domain: domain, duration: dur))
        }
        return results
    }

    private func fetchIntervals(db: OpaquePointer, streamName: String, start: Double, end: Double) -> [Interval] {
        let sql = """
            SELECT ZVALUESTRING,
                   CASE WHEN ZSTARTDATE < ? THEN ? ELSE ZSTARTDATE END AS clippedStart,
                   CASE WHEN ZENDDATE > ? THEN ? ELSE ZENDDATE END AS clippedEnd
            FROM ZOBJECT
            WHERE ZSTREAMNAME=?
              AND ZVALUESTRING IS NOT NULL
              AND ZENDDATE>? AND ZSTARTDATE<?
            ORDER BY ZSTARTDATE ASC
        """
        guard let stmt = prepare(db, sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, start)
        sqlite3_bind_double(stmt, 2, start)
        sqlite3_bind_double(stmt, 3, end)
        sqlite3_bind_double(stmt, 4, end)
        sqlite3_bind_text(stmt, 5, streamName, -1, sqliteTransient)
        sqlite3_bind_double(stmt, 6, start)
        sqlite3_bind_double(stmt, 7, end)

        var intervals: [Interval] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let ptr = sqlite3_column_text(stmt, 0) else { continue }
            let bundleID = String(cString: ptr)
            let clippedStart = sqlite3_column_double(stmt, 1)
            let clippedEnd = sqlite3_column_double(stmt, 2)
            guard !bundleID.isEmpty, clippedEnd > clippedStart else { continue }
            intervals.append(
                Interval(
                    bundleID: bundleID,
                    start: Date(timeIntervalSinceReferenceDate: clippedStart),
                    end: Date(timeIntervalSinceReferenceDate: clippedEnd)
                )
            )
        }
        return intervals
    }

    private func canonicalizeDomain(_ raw: String) -> String {
        DomainMatcher.normalizeHost(raw) ?? raw.lowercased()
    }

    private func availableAppStreamName(in db: OpaquePointer) -> String? {
        for streamName in Self.preferredAppStreamNames {
            let sql = """
                SELECT 1
                FROM ZOBJECT
                WHERE ZSTREAMNAME=?
                LIMIT 1
            """
            guard let stmt = prepare(db, sql) else { continue }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, streamName, -1, sqliteTransient)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return streamName
            }
        }
        return nil
    }
}
