import Foundation

/// Streams newline-terminated lines from a file, starting at a byte offset.
/// A trailing line without a newline is left unread so a later run can pick it up once complete.
struct LineReader {
    let path: String
    let startOffset: UInt64
    var chunkSize = 1 << 20

    /// Calls `body` with each complete line. Returns the offset just past the last complete line.
    func forEachLine(_ body: (Data) throws -> Void) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seek(toOffset: startOffset)

        var offset = startOffset
        var buffer = Data()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)
            var lineStart = buffer.startIndex
            while let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
                let line = buffer[lineStart..<newline]
                if !line.isEmpty { try body(Data(line)) }
                offset += UInt64(newline - lineStart + 1)
                lineStart = newline + 1
            }
            buffer = Data(buffer[lineStart...])
        }
        return offset
    }
}
