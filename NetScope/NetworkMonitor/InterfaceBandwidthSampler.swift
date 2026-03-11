import Darwin
import Foundation

enum InterfaceBandwidthSamplerError: LocalizedError {
    case snapshotUnavailable

    var errorDescription: String? {
        switch self {
        case .snapshotUnavailable:
            return "Unable to read interface bandwidth counters."
        }
    }
}

actor InterfaceBandwidthSampler {
    private var previousTotals: (download: UInt64, upload: UInt64)?

    func sample(interval: TimeInterval) throws -> (downloadBps: Double, uploadBps: Double) {
        let totals = try readTotals()
        defer {
            previousTotals = totals
        }

        guard let previousTotals else {
            return (0, 0)
        }

        let downloadDelta = totals.download >= previousTotals.download ? totals.download - previousTotals.download : 0
        let uploadDelta = totals.upload >= previousTotals.upload ? totals.upload - previousTotals.upload : 0
        let effectiveInterval = max(interval, 0.2)

        return (
            downloadBps: Double(downloadDelta) * 8.0 / effectiveInterval,
            uploadBps: Double(uploadDelta) * 8.0 / effectiveInterval
        )
    }

    private func readTotals() throws -> (download: UInt64, upload: UInt64) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let head = pointer else {
            throw InterfaceBandwidthSamplerError.snapshotUnavailable
        }

        defer { freeifaddrs(head) }

        var totalDownload: UInt64 = 0
        var totalUpload: UInt64 = 0

        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }

            let flags = entry.ifa_flags
            let isUp = (flags & UInt32(IFF_UP)) != 0
            let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0
            guard isUp, !isLoopback else {
                continue
            }

            guard entry.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  let dataPointer = entry.ifa_data else {
                continue
            }

            let interfaceData = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            totalDownload += UInt64(interfaceData.ifi_ibytes)
            totalUpload += UInt64(interfaceData.ifi_obytes)
        }

        return (download: totalDownload, upload: totalUpload)
    }
}
