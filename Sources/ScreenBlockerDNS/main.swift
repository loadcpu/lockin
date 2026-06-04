import Foundation
import Darwin

// Usage: ScreenBlockerDNS <domains-file>
//
// DNS (UDP :53):
//   Blocked domains  → A record 127.0.0.1 (AAAA/other queries → NOERROR, no answers)
//   Everything else  → forwarded to 8.8.8.8
//
// HTTP (TCP :80):
//   Any request      → "Focus Session Active" blocked page (domain shown in badge)
//
// HTTPS (TCP :443) is not intercepted; browsers show "Connection refused",
// which is instant and clearly intentional rather than a confusing network error.

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: ScreenBlockerDNS <domains-file>\n", stderr)
    exit(1)
}

let domainsFile = CommandLine.arguments[1]
let rawDomains = (try? String(contentsOfFile: domainsFile, encoding: .utf8)) ?? ""
let blockedDomains: Set<String> = Set(
    rawDomains.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        .filter { !$0.isEmpty }
)

let upstreamIP   = "8.8.8.8"
let upstreamPort = UInt16(53)

// MARK: - DNS helpers

func parseDomain(_ data: [UInt8], offset: Int) -> String {
    var labels: [String] = []
    var i = offset
    while i < data.count {
        let len = Int(data[i])
        if len == 0 { break }
        if len & 0xC0 == 0xC0 { break }
        i += 1
        guard i + len <= data.count else { break }
        if let label = String(bytes: data[i ..< i + len], encoding: .ascii) {
            labels.append(label)
        }
        i += len
    }
    return labels.joined(separator: ".").lowercased()
}

// Returns the index just past the domain name labels in the question section.
func questionNameEnd(_ data: [UInt8], offset: Int) -> Int {
    var i = offset
    while i < data.count {
        let len = Int(data[i])
        if len == 0 { return i + 1 }
        if len & 0xC0 == 0xC0 { return i + 2 }
        i += 1 + len
    }
    return i
}

func isBlocked(_ domain: String) -> Bool {
    if blockedDomains.contains(domain) { return true }
    for b in blockedDomains where domain.hasSuffix(".\(b)") { return true }
    return false
}

// For A queries: returns 127.0.0.1. For AAAA/other: NOERROR with no answers
// (browser then uses the A record and connects to our HTTP server).
func blockedDNSResponse(_ query: [UInt8]) -> [UInt8] {
    let nameEnd = questionNameEnd(query, offset: 12)
    let qtype: UInt16 = (nameEnd + 1) < query.count
        ? (UInt16(query[nameEnd]) << 8 | UInt16(query[nameEnd + 1]))
        : 0x0001

    var r = query
    r[2] = 0x81; r[3] = 0x80 // QR=1 RD=1 RA=1 RCODE=0
    r[8] = 0; r[9] = 0; r[10] = 0; r[11] = 0

    if qtype == 0x0001 { // A
        r[6] = 0; r[7] = 1
        return r + [
            0xC0, 0x0C,              // name: pointer to question
            0x00, 0x01, 0x00, 0x01,  // type A, class IN
            0x00, 0x00, 0x00, 0x01,  // TTL 1s
            0x00, 0x04,              // rdlength
            127, 0, 0, 1             // 127.0.0.1
        ]
    } else {
        r[6] = 0; r[7] = 0
        return r
    }
}

// MARK: - Socket helpers

func makeAddr(_ ip: String, port: UInt16) -> sockaddr_in {
    var a = sockaddr_in()
    a.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
    a.sin_family = sa_family_t(AF_INET)
    a.sin_port   = port.bigEndian
    a.sin_addr.s_addr = inet_addr(ip)
    return a
}

func sendUDP(_ fd: Int32, _ data: [UInt8], to addr: sockaddr_in) {
    var a = addr
    _ = withUnsafePointer(to: &a) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            sendto(fd, data, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
}

// MARK: - Blocked page

@Sendable func blockedPageHTML(domain: String) -> String {
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Focus Session Active</title>
    <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      display: flex; align-items: center; justify-content: center;
      min-height: 100vh;
      background: #0d0d0d;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", sans-serif;
      color: #fff;
    }
    .card {
      text-align: center;
      padding: 56px 40px;
      max-width: 460px;
      width: 100%;
    }
    .icon { font-size: 52px; margin-bottom: 28px; line-height: 1; }
    h1 {
      font-size: 28px; font-weight: 700;
      letter-spacing: -0.6px; margin-bottom: 14px;
    }
    .sub {
      font-size: 15px; color: #888; line-height: 1.65; margin-bottom: 36px;
    }
    .badge {
      display: inline-block;
      background: #181818; border: 1px solid #2c2c2c; border-radius: 8px;
      padding: 7px 16px;
      font-size: 12px; font-family: "SF Mono", "Menlo", monospace;
      color: #555; letter-spacing: 0.3px;
    }
    </style>
    </head>
    <body>
    <div class="card">
      <div class="icon">🛡</div>
      <h1>Focus Session Active</h1>
      <p class="sub">This site is blocked while your focus<br>session is running.</p>
      <div class="badge">\(domain)</div>
    </div>
    </body>
    </html>
    """
}

// MARK: - HTTP server (TCP :80)

func startHTTPServer() {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return }
    var reuseVal: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseVal, socklen_t(MemoryLayout<Int32>.size))
    var addr = makeAddr("0.0.0.0", port: 80)
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard ok == 0, listen(fd, 32) == 0 else { close(fd); return }

    DispatchQueue.global(qos: .utility).async {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { continue }
            DispatchQueue.global(qos: .utility).async { serveBlockedPage(client) }
        }
    }
}

func serveBlockedPage(_ fd: Int32) {
    defer { close(fd) }
    var tv = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    var buf = [UInt8](repeating: 0, count: 8192)
    let n = recv(fd, &buf, buf.count - 1, 0)
    guard n > 0 else { return }

    let request = String(bytes: buf[0..<n], encoding: .utf8) ?? ""
    var host = "blocked"
    for line in request.components(separatedBy: "\r\n") {
        if line.lowercased().hasPrefix("host:") {
            let raw = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            host = raw.components(separatedBy: ":").first ?? raw
            break
        }
    }

    let html  = blockedPageHTML(domain: host)
    let body  = Array(html.utf8)
    let head  = Array("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
    _ = head.withUnsafeBytes { send(fd, $0.baseAddress!, head.count, 0) }
    _ = body.withUnsafeBytes { send(fd, $0.baseAddress!, body.count, 0) }
}

// MARK: - DNS server (UDP :53)

let serverFd = socket(AF_INET, SOCK_DGRAM, 0)
guard serverFd >= 0 else {
    fputs("socket() failed: \(String(cString: strerror(errno)))\n", stderr)
    exit(1)
}
var reuseVal: Int32 = 1
setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &reuseVal, socklen_t(MemoryLayout<Int32>.size))

var bindAddr = makeAddr("127.0.0.1", port: 53)
guard withUnsafePointer(to: &bindAddr, {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
}) == 0 else {
    fputs("bind(:53) failed: \(String(cString: strerror(errno)))\n", stderr)
    exit(1)
}

startHTTPServer()
signal(SIGTERM, SIG_DFL)
signal(SIGINT,  SIG_DFL)

var queryBuf = [UInt8](repeating: 0, count: 512)
var clientAddr = sockaddr_in()
var clientLen  = socklen_t(MemoryLayout<sockaddr_in>.size)

while true {
    let n = withUnsafeMutablePointer(to: &clientAddr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            recvfrom(serverFd, &queryBuf, queryBuf.count, 0, $0, &clientLen)
        }
    }
    guard n > 12 else { continue }

    let query  = Array(queryBuf[0 ..< n])
    let domain = parseDomain(query, offset: 12)

    if isBlocked(domain) {
        sendUDP(serverFd, blockedDNSResponse(query), to: clientAddr)
    } else {
        let q = query
        let c = clientAddr
        DispatchQueue.global(qos: .utility).async {
            let upFd = socket(AF_INET, SOCK_DGRAM, 0)
            guard upFd >= 0 else { return }
            defer { close(upFd) }
            var tv = timeval(tv_sec: 3, tv_usec: 0)
            setsockopt(upFd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            var up = makeAddr(upstreamIP, port: upstreamPort)
            _ = withUnsafePointer(to: &up) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(upFd, q, q.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            var resp = [UInt8](repeating: 0, count: 4096)
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let nr = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(upFd, &resp, resp.count, 0, $0, &fromLen)
                }
            }
            guard nr > 0 else { return }
            sendUDP(serverFd, Array(resp[0 ..< nr]), to: c)
        }
    }
}
