import Foundation

enum SpeedTestPhase: String {
    case idle
    case ping
    case download
    case upload
    case completed
    case failed

    var description: String {
        switch self {
        case .idle:
            return "Idle"
        case .ping:
            return "Testing Ping"
        case .download:
            return "Testing Download"
        case .upload:
            return "Testing Upload"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
}

struct SpeedTestResult: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let pingMS: Double
    let downloadMbps: Double
    let uploadMbps: Double

    init(id: UUID = UUID(), date: Date, pingMS: Double, downloadMbps: Double, uploadMbps: Double) {
        self.id = id
        self.date = date
        self.pingMS = pingMS
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
    }
}
