import Foundation

enum NettopSamplerError: LocalizedError {
    case commandUnavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandUnavailable:
            return "nettop is unavailable on this system."
        case .commandFailed(let details):
            return "nettop failed: \(details)"
        }
    }
}

actor NettopSampler {
    private struct MutableProcessSnapshot {
        let pid: Int
        var processName: String
        var cumulativeDownloadBytes: UInt64
        var cumulativeUploadBytes: UInt64
        var connections: Set<ConnectionSnapshot>
    }

    private var previousTotalsByPID: [Int: (download: UInt64, upload: UInt64)] = [:]

    func sample(interval: TimeInterval) async throws -> [ProcessDeltaSnapshot] {
        let start = Date()
        let output = try runNettopSnapshot(interval: interval)
        let processSnapshots = parseCSV(output)
        let elapsed = max(Date().timeIntervalSince(start), 0.2)
        let effectiveInterval = elapsed
        var nextTotals: [Int: (download: UInt64, upload: UInt64)] = [:]
        var result: [ProcessDeltaSnapshot] = []
        result.reserveCapacity(processSnapshots.count)

        for process in processSnapshots {
            let previous = previousTotalsByPID[process.pid]
            let downloadDelta = safeDelta(current: process.cumulativeDownloadBytes, previous: previous?.download)
            let uploadDelta = safeDelta(current: process.cumulativeUploadBytes, previous: previous?.upload)

            nextTotals[process.pid] = (download: process.cumulativeDownloadBytes, upload: process.cumulativeUploadBytes)

            let downloadBps = Double(downloadDelta) * 8.0 / effectiveInterval
            let uploadBps = Double(uploadDelta) * 8.0 / effectiveInterval

            result.append(
                ProcessDeltaSnapshot(
                    process: process,
                    downloadBps: downloadBps,
                    uploadBps: uploadBps,
                    deltaDownloadBytes: downloadDelta,
                    deltaUploadBytes: uploadDelta
                )
            )
        }

        previousTotalsByPID = nextTotals
        return result
    }

    private func safeDelta(current: UInt64, previous: UInt64?) -> UInt64 {
        guard let previous else {
            return 0
        }
        return current >= previous ? current - previous : 0
    }

    private func runNettopSnapshot(interval: TimeInterval) throws -> String {
        let nettopPath = "/usr/bin/nettop"
        guard FileManager.default.isExecutableFile(atPath: nettopPath) else {
            throw NettopSamplerError.commandUnavailable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nettopPath)

        let sampleDelay = max(1.0, interval)
        let delayString = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), sampleDelay)
        process.arguments = ["-x", "-L", "2", "-n", "-s", delayString]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw NettopSamplerError.commandFailed(error.localizedDescription)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let details = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NettopSamplerError.commandFailed(details?.isEmpty == false ? details! : "exit status \(process.terminationStatus)")
        }

        return String(decoding: outputData, as: UTF8.self)
    }

    private func parseCSV(_ csv: String) -> [ProcessNetworkSnapshot] {
        var snapshotsByPID: [Int: MutableProcessSnapshot] = [:]
        var order: [Int] = []
        var currentPID: Int?

        let lastBlock = latestSnapshotBlock(in: csv)
        let lines = lastBlock.split(whereSeparator: \.isNewline)
        guard lines.count > 1 else {
            return []
        }

        for line in lines.dropFirst() {
            let fields = splitCSVLine(String(line))
            guard fields.count >= 6 else {
                continue
            }

            let token = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                continue
            }

            let interfaceName = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let state = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)

            if let processInfo = parseProcessToken(token) {
                let cumulativeDownload = UInt64(fields[4]) ?? 0
                let cumulativeUpload = UInt64(fields[5]) ?? 0

                if snapshotsByPID[processInfo.pid] == nil {
                    snapshotsByPID[processInfo.pid] = MutableProcessSnapshot(
                        pid: processInfo.pid,
                        processName: processInfo.name,
                        cumulativeDownloadBytes: cumulativeDownload,
                        cumulativeUploadBytes: cumulativeUpload,
                        connections: []
                    )
                    order.append(processInfo.pid)
                } else {
                    snapshotsByPID[processInfo.pid]?.processName = processInfo.name
                    snapshotsByPID[processInfo.pid]?.cumulativeDownloadBytes = cumulativeDownload
                    snapshotsByPID[processInfo.pid]?.cumulativeUploadBytes = cumulativeUpload
                }

                currentPID = processInfo.pid
                continue
            }

            guard let pid = currentPID,
                  var currentSnapshot = snapshotsByPID[pid],
                  let connection = parseConnectionToken(token, interfaceName: interfaceName, state: state) else {
                continue
            }

            currentSnapshot.connections.insert(connection)
            snapshotsByPID[pid] = currentSnapshot
        }

        return order.compactMap { pid in
            guard let snapshot = snapshotsByPID[pid] else {
                return nil
            }

            return ProcessNetworkSnapshot(
                pid: snapshot.pid,
                processName: snapshot.processName,
                cumulativeDownloadBytes: snapshot.cumulativeDownloadBytes,
                cumulativeUploadBytes: snapshot.cumulativeUploadBytes,
                connections: snapshot.connections.sorted { lhs, rhs in
                    lhs.remoteAddress < rhs.remoteAddress
                }
            )
        }
    }

    private func parseProcessToken(_ token: String) -> (name: String, pid: Int)? {
        guard !token.contains("<->"),
              let dotIndex = token.lastIndex(of: ".") else {
            return nil
        }

        let namePart = token[..<dotIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let pidPart = token[token.index(after: dotIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)

        guard !namePart.isEmpty,
              let pid = Int(pidPart) else {
            return nil
        }

        return (name: String(namePart), pid: pid)
    }

    private func parseConnectionToken(_ token: String, interfaceName: String, state: String) -> ConnectionSnapshot? {
        guard token.contains("<->") else {
            return nil
        }

        let parts = token.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return nil
        }

        let protocolName = String(parts[0]).uppercased()
        let endpointBlob = String(parts[1])

        guard let arrowRange = endpointBlob.range(of: "<->") else {
            return nil
        }

        let remoteEndpoint = String(endpointBlob[arrowRange.upperBound...])
        let parsedEndpoint = parseEndpoint(remoteEndpoint)
        guard parsedEndpoint.address != "*" else {
            return nil
        }

        return ConnectionSnapshot(
            remoteAddress: parsedEndpoint.address,
            remotePort: parsedEndpoint.port,
            protocolName: protocolName,
            state: state.isEmpty ? "Unknown" : state,
            interfaceName: interfaceName
        )
    }

    private func parseEndpoint(_ endpoint: String) -> (address: String, port: Int?) {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != "*",
              trimmed != "*:*",
              trimmed != "*.*" else {
            return (address: "*", port: nil)
        }

        var address = trimmed
        var port: Int?

        if let colonIndex = trimmed.lastIndex(of: ":") {
            let maybePort = trimmed[trimmed.index(after: colonIndex)...]
            if maybePort.allSatisfy(\.isNumber) {
                address = String(trimmed[..<colonIndex])
                port = Int(maybePort)
            }
        }

        if port == nil,
           let dotIndex = trimmed.lastIndex(of: ".") {
            let maybePort = trimmed[trimmed.index(after: dotIndex)...]
            if maybePort.allSatisfy(\.isNumber) {
                address = String(trimmed[..<dotIndex])
                port = Int(maybePort)
            }
        }

        if let scopeIndex = address.firstIndex(of: "%") {
            address = String(address[..<scopeIndex])
        }

        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return (address: normalized.isEmpty ? "*" : normalized, port: port)
    }

    private func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var insideQuotes = false

        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
                continue
            }

            if char == "," && !insideQuotes {
                fields.append(currentField)
                currentField = ""
            } else {
                currentField.append(char)
            }
        }

        fields.append(currentField)
        return fields
    }

    private func latestSnapshotBlock(in csv: String) -> String {
        let lines = csv.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let headerPrefix = "time,,interface,state,bytes_in,bytes_out"
        var headerIndexes: [Int] = []
        for (index, line) in lines.enumerated() where line.hasPrefix(headerPrefix) {
            headerIndexes.append(index)
        }

        guard let lastHeader = headerIndexes.last else {
            return csv
        }

        let suffix = lines[lastHeader...]
        return suffix.joined(separator: "\n")
    }
}
