import Foundation
import Darwin

/// Resolves the device's non-loopback IPv4 address (LAN subnet source),
/// mirroring Android `getLocalIpAddress()` in MainActivity.kt.
enum LocalIP {
    static func ipv4Address() -> String? {
        var interfaceNames: [String: String] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(firstAddr) }

        for pointer in sequence(first: (UnsafeMutablePointer<ifaddrs>)(firstAddr), next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let family = interface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            let address = ipv4String(from: interface.ifa_addr)

            if let address = address, address != "127.0.0.1" {
                interfaceNames[name] = address
            }
        }

        // Prefer Wi-Fi / cellular interfaces (like the link Java picks first).
        let preferredNames = ["en0", "en1", "rmnet0", "pdp_ip0", "tun0"]
        for name in preferredNames {
            if let ip = interfaceNames[name] { return ip }
        }

        // Fall back to the first non-loopback IPv4, similarly to Android.
        for ip in interfaceNames.values where ip != "127.0.0.1" {
            return ip
        }
        return nil
    }

    private static func ipv4String(from addr: UnsafeMutablePointer<sockaddr>?) -> String? {
        guard let addr = addr else { return nil }
        let address = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sockaddrIn -> String? in
            var inAddr = sockaddrIn.pointee.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &inAddr, &buffer, socklen_t(INET_ADDRSTRLEN))
            return String(cString: buffer)
        }
        return address
    }
}