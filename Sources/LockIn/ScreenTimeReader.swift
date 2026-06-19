import Foundation
import AppKit
import SQLite3

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

    struct Sample {
        let bundleID: String   // real bundle ID, or "web" for domain entries
        let domain: String?    // non-nil for website entries
        let duration: TimeInterval
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
        var apps = fetchInFocus(db: db, start: start, end: end)
        let web  = fetchWebUsage(db: db, start: start, end: end)

        if !web.isEmpty {
            apps.removeAll { Self.browserBundleIDs.contains($0.bundleID) }
        }
        return apps + web
    }

    func totalDuration(for date: Date) -> TimeInterval {
        guard let db = openDB() else { return 0 }
        defer { sqlite3_close(db) }
        let (start, end) = dayBounds(for: date)
        let sql = """
            SELECT SUM(MIN(ZENDDATE,?)-MAX(ZSTARTDATE,?))
            FROM ZOBJECT
            WHERE ZSTREAMNAME='/app/inFocus'
              AND ZVALUESTRING IS NOT NULL
              AND ZENDDATE>? AND ZSTARTDATE<?
        """
        guard let stmt = prepare(db, sql) else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, end);   sqlite3_bind_double(stmt, 2, start)
        sqlite3_bind_double(stmt, 3, start); sqlite3_bind_double(stmt, 4, end)
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_double(stmt, 0) : 0
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

    private func fetchInFocus(db: OpaquePointer, start: Double, end: Double) -> [Sample] {
        let sql = """
            SELECT ZVALUESTRING,
                   SUM(MIN(ZENDDATE,?)-MAX(ZSTARTDATE,?)) AS dur
            FROM ZOBJECT
            WHERE ZSTREAMNAME='/app/inFocus'
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
            let domain = canonicalizeDomain(raw)
            guard !Self.normalizedBrowserBundleIDs.contains(domain) else { continue }
            results.append(Sample(bundleID: "web", domain: domain, duration: dur))
        }
        return results
    }

    private func canonicalizeDomain(_ raw: String) -> String {
        DomainMatcher.normalizeHost(raw) ?? raw.lowercased()
    }
}
