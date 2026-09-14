import Foundation

/// Tool name and time of each MCP request, one JSON object per line. Nothing
/// about the request's content is kept.
public enum MCPRequestLog {
    static let maxBytes = 1_000_000

    public static func append(tool: String, at date: Date = Date(), to url: URL) {
        let entry: [String: Any] = ["tool": tool, "at": ISO8601DateFormatter().string(from: date)]
        guard var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
        let size = (try? handle.offset()) ?? 0
        try? handle.close()
        // Keep the newest half once it gets big.
        if size > maxBytes, let data = try? Data(contentsOf: url) {
            let tail = data.suffix(maxBytes / 2)
            let start = tail.firstIndex(of: 0x0A).map { $0 + 1 } ?? tail.startIndex
            try? Data(tail[start...]).write(to: url, options: .atomic)
        }
    }

    public static func count(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }
        return data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    public static func lastRequest(at url: URL) -> Date? {
        guard let data = try? Data(contentsOf: url),
              let line = data.split(separator: 0x0A).last,
              let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let at = entry["at"] as? String else { return nil }
        return ISO8601DateFormatter().date(from: at)
    }
}

/// The stable command AI apps are pointed at (~/Library/Application
/// Support/Gobbl/bin/gobbl-mcp): a tiny script that runs the server inside
/// whichever Gobbl.app is current, so configs survive moves and updates.
public enum MCPShim {
    public static func script(appPath: String) -> String {
        let quoted = "'" + appPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return """
        #!/bin/sh
        # Installed by Gobbl. Starts Gobbl's MCP server (memory for AI apps)
        # from the current Gobbl.app, so AI app settings survive updates.
        APP=\(quoted)
        if [ ! -x "$APP/Contents/MacOS/gobbl-mcp" ]; then
          APP=$(/usr/bin/mdfind "kMDItemCFBundleIdentifier == 'com.xeve.gobbl'" 2>/dev/null | head -n 1)
        fi
        if [ -z "$APP" ] || [ ! -x "$APP/Contents/MacOS/gobbl-mcp" ]; then
          echo "gobbl-mcp: Gobbl isn't installed. Get it at https://gobbl.xeve.io" >&2
          exit 1
        fi
        exec "$APP/Contents/MacOS/gobbl-mcp" "$@"

        """
    }
}

/// The gobbl-mcp end of the app socket: one `mcp\t{json}` line out, one JSON line back.
public enum MCPSocketBridge {
    public static func send(_ request: [String: Any], path: String, timeout: Int = 10) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MCPBridgeError.notRunning }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw MCPBridgeError.notRunning }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw MCPBridgeError.notRunning }
        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        var line = Data("mcp\t".utf8)
        line.append(try JSONSerialization.data(withJSONObject: request))
        line.append(0x0A)
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == line.count else { throw MCPBridgeError.notRunning }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while data.count < 8_000_000 {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
            if buffer[..<n].contains(0x0A) { break }
        }
        let end = data.firstIndex(of: 0x0A) ?? data.endIndex
        guard let answer = try? JSONSerialization.jsonObject(with: data[data.startIndex..<end]) as? [String: Any] else {
            throw MCPBridgeError.noAnswer
        }
        return answer
    }
}
