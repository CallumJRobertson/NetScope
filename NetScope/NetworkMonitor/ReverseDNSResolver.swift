import Darwin
import Foundation

actor ReverseDNSResolver {
    private var cache: [String: String] = [:]

    func resolve(_ address: String) -> String? {
        if let cached = cache[address] {
            return cached
        }

        guard let hostname = reverseLookup(address), !hostname.isEmpty else {
            return nil
        }

        cache[address] = hostname
        return hostname
    }

    private func reverseLookup(_ address: String) -> String? {
        var hints = addrinfo(
            ai_flags: AI_NUMERICHOST,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(address, nil, &hints, &result) == 0, let result else {
            return nil
        }

        defer { freeaddrinfo(result) }

        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            result.pointee.ai_addr,
            result.pointee.ai_addrlen,
            &hostBuffer,
            socklen_t(hostBuffer.count),
            nil,
            0,
            NI_NAMEREQD
        )

        guard status == 0 else {
            return nil
        }

        return String(cString: hostBuffer)
    }
}
