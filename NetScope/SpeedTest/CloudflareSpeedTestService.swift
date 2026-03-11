import Foundation

enum SpeedTestServiceError: LocalizedError {
    case badResponse
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "Speed test server returned an invalid response."
        case .invalidPayload:
            return "Speed test server response was empty."
        }
    }
}

final class CloudflareSpeedTestService {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 45
            self.session = URLSession(configuration: configuration)
        }
    }

    func measurePingMS() async throws -> Double {
        guard let pingURL = URL(string: "https://speed.cloudflare.com/cdn-cgi/trace") else {
            throw SpeedTestServiceError.badResponse
        }

        var samples: [Double] = []
        samples.reserveCapacity(3)

        for _ in 0..<3 {
            var request = URLRequest(url: pingURL)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let start = ContinuousClock.now
            let (_, response) = try await session.data(for: request)
            let end = ContinuousClock.now

            try validate(response)
            samples.append(seconds(from: start.duration(to: end)) * 1_000)
        }

        guard !samples.isEmpty else {
            throw SpeedTestServiceError.badResponse
        }

        return samples.reduce(0, +) / Double(samples.count)
    }

    func measureDownloadMbps() async throws -> Double {
        guard let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=25000000") else {
            throw SpeedTestServiceError.badResponse
        }

        let start = ContinuousClock.now
        let (data, response) = try await session.data(from: downloadURL)
        let end = ContinuousClock.now

        try validate(response)
        guard !data.isEmpty else {
            throw SpeedTestServiceError.invalidPayload
        }

        let duration = max(seconds(from: start.duration(to: end)), 0.001)
        let bits = Double(data.count) * 8.0
        return bits / duration / 1_000_000
    }

    func measureUploadMbps() async throws -> Double {
        guard let uploadURL = URL(string: "https://speed.cloudflare.com/__up") else {
            throw SpeedTestServiceError.badResponse
        }

        let payload = Data(repeating: 0xA5, count: 6_000_000)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let start = ContinuousClock.now
        let (_, response) = try await session.upload(for: request, from: payload)
        let end = ContinuousClock.now

        try validate(response)

        let duration = max(seconds(from: start.duration(to: end)), 0.001)
        let bits = Double(payload.count) * 8.0
        return bits / duration / 1_000_000
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw SpeedTestServiceError.badResponse
        }
    }

    private func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
