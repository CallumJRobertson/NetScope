import Foundation
import SwiftUI

struct ThroughputSample: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let downloadBps: Double
    let uploadBps: Double
}

struct ConnectionSnapshot: Identifiable, Hashable {
    var id: String {
        "\(protocolName)-\(remoteAddress)-\(remotePort ?? -1)-\(state)-\(interfaceName)"
    }

    let remoteAddress: String
    let remotePort: Int?
    let protocolName: String
    let state: String
    let interfaceName: String
}

struct ProcessNetworkSnapshot: Identifiable, Hashable {
    var id: Int { pid }

    let pid: Int
    let processName: String
    let cumulativeDownloadBytes: UInt64
    let cumulativeUploadBytes: UInt64
    let connections: [ConnectionSnapshot]
}

struct ProcessDeltaSnapshot: Identifiable, Hashable {
    var id: Int { process.pid }

    let process: ProcessNetworkSnapshot
    let downloadBps: Double
    let uploadBps: Double
    let deltaDownloadBytes: UInt64
    let deltaUploadBytes: UInt64
}

struct AppUsageRow: Identifiable, Hashable {
    let id: String

    let pid: Int
    let groupKey: String
    let processCount: Int
    let appName: String
    let bundleIdentifier: String?
    let downloadBps: Double
    let uploadBps: Double
    let sessionDownloadBytes: UInt64
    let sessionUploadBytes: UInt64
    let connections: [ConnectionSnapshot]
}

struct TopConsumer: Identifiable, Hashable {
    let id: String
    let appName: String
    let totalBytes: UInt64
}

enum GraphMode: String, CaseIterable, Identifiable {
    case total
    case download
    case upload

    var id: String { rawValue }

    var label: String {
        switch self {
        case .total:
            return "Total"
        case .download:
            return "Download"
        case .upload:
            return "Upload"
        }
    }

    var color: Color {
        switch self {
        case .total:
            return .blue
        case .download:
            return .green
        case .upload:
            return .orange
        }
    }

    func value(for sample: ThroughputSample) -> Double {
        switch self {
        case .total:
            return sample.downloadBps + sample.uploadBps
        case .download:
            return sample.downloadBps
        case .upload:
            return sample.uploadBps
        }
    }
}

enum GraphDuration: String, CaseIterable, Identifiable {
    case oneMinute
    case fiveMinutes
    case thirtyMinutes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneMinute:
            return "1m"
        case .fiveMinutes:
            return "5m"
        case .thirtyMinutes:
            return "30m"
        }
    }

    var windowSeconds: TimeInterval {
        switch self {
        case .oneMinute:
            return 60
        case .fiveMinutes:
            return 300
        case .thirtyMinutes:
            return 1800
        }
    }
}
